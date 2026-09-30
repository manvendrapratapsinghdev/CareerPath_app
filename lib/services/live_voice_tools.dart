import 'package:flutter/foundation.dart';

import '../config/ai_provider_config.dart';
import '../models/ai_chat.dart';
import 'ai_guardrails.dart';
import 'ai_response_parser.dart';
import 'gemini_live_client.dart';
import 'live_voice_prompts.dart';
import 'local_ai_grounding_service.dart';

/// What one voice turn produced, used to build the chat messages.
class VoiceTurn {
  String? question;
  String intent = VoiceIntent.career;
  String language = 'english';
  bool isFollowUp = false;
  List<AiChatSource> sources = const [];
  List<AiAnswerSection> sections = const [];
  List<String> suggestions = const [];
  String? directAnswer;

  /// A search ran but found nothing — the guide is answering from general
  /// knowledge or admitting it doesn't know, not from CareerPath records.
  bool noRecordsFound = false;
}

/// Answers the voice assistant's tool calls on the device, from the same
/// CareerPath grounding and guardrails the typed chat uses.
class LiveVoiceTools {
  static const offTopicAnswer =
      'I can help with careers, courses, colleges and the CareerPath app. '
      'Please ask me about a stream, course or career path.';
  static const smallTalkAnswer =
      'Happy to chat! I can help you explore streams, courses, colleges and '
      'careers. What would you like to know?';
  static const offensiveAnswer =
      'Please keep it respectful. I am here to help with career and '
      'education questions.';
  static const unsupportedLanguageAnswer =
      'Please ask in English, Hindi or another supported Indian language.';

  final LocalAiGroundingService grounding;
  final Future<String> Function() loadAppHelp;
  final String? Function()? streamId;

  /// Semantic search merged with keyword grounding, as in typed chat.
  final ExtraGrounding? extraGrounding;

  VoiceTurn turn = VoiceTurn();
  final _memory = <(String, String)>[];

  // Semantic lookup started while the student is still speaking, so the
  // records are usually ready by the time the model asks for them.
  Future<AiGroundingContext>? _prefetch;
  String _prefetchText = '';
  int _prefetchCount = 0;
  static const _maxPrefetchesPerTurn = 3;
  static const _minPrefetchWords = 3;

  LiveVoiceTools({
    required this.grounding,
    required this.loadAppHelp,
    this.streamId,
    this.extraGrounding,
  });

  void startTurn() {
    turn = VoiceTurn();
    _prefetch = null;
    _prefetchText = '';
    _prefetchCount = 0;
  }

  /// Starts a background semantic lookup for what has been heard so far.
  /// Bounded per turn because embedding calls share a per-minute quota.
  void prefetch(String heard) {
    final text = heard.trim();
    if (extraGrounding == null ||
        text == _prefetchText ||
        _prefetchCount >= _maxPrefetchesPerTurn ||
        text.split(RegExp(r'\s+')).length < _minPrefetchWords) {
      return;
    }
    _prefetchCount++;
    _prefetchText = text;
    _prefetch = _semantic(text);
  }

  Future<AiGroundingContext> _semantic(String query) async {
    final extra = extraGrounding;
    if (extra == null) return AiGroundingContext.empty;
    try {
      return await extra(query, streamId?.call());
    } on Object catch (error) {
      debugPrint(
        '[AI Guide voice] semantic search failed (${error.runtimeType})',
      );
      return AiGroundingContext.empty;
    }
  }

  /// Keyword and semantic grounding for [query]. The speculative lookup is
  /// reused when it covered (nearly) the whole spoken question.
  Future<AiGroundingContext> _retrieve(
    String query, {
    bool broad = false,
  }) async {
    final spoken = turn.question ?? '';
    final wordsHeard = spoken.trim().split(RegExp(r'\s+')).length;
    final prefetchWords = _prefetchText.isEmpty
        ? 0
        : _prefetchText.split(RegExp(r'\s+')).length;
    final reusable = _prefetch != null && wordsHeard - prefetchWords <= 3;
    final semantic = reusable ? _prefetch! : _semantic(query);
    final keyword = await grounding.retrieve(
      query: query,
      streamId: streamId?.call(),
      broad: broad,
    );
    return AiGroundingContext.merge(keyword, await semantic);
  }

  /// Keeps the last few turns so follow-ups and reconnects keep context.
  void remember(String question, String answer) {
    if (question.trim().isEmpty || answer.trim().isEmpty) return;
    _memory.add((question, answer));
    while (_memory.length > AiProviderConfig.liveMemoryTurns) {
      _memory.removeAt(0);
    }
  }

  String? sessionContext() => _memory.isEmpty
      ? null
      : 'RECENT CONVERSATION:\n${_memory.map((t) => 'Student: ${t.$1}\nGuide: ${t.$2}').join('\n')}';

  Future<Map<String, dynamic>> execute(LiveFunctionCall call) async {
    try {
      return switch (call.name) {
        'route_query' => await _route(call.args),
        'search_careers' => await _search(call.args),
        'format_answer' => _format(call.args),
        _ => {'error': 'unknown_tool'},
      };
    } on Object catch (error) {
      debugPrint(
        '[AI Guide voice] tool ${call.name} failed (${error.runtimeType})',
      );
      return {'error': 'tool_failed'};
    }
  }

  Future<Map<String, dynamic>> _route(Map<String, dynamic> args) async {
    final query = args['query']?.toString().trim() ?? '';
    var intent = args['intent']?.toString() ?? VoiceIntent.career;
    if (!VoiceIntent.all.contains(intent)) intent = VoiceIntent.career;
    final language = args['input_language']?.toString() ?? 'english';
    final isFollowUp = args['is_follow_up'] == true && _memory.isNotEmpty;
    final standalone = args['standalone_query']?.toString().trim();

    turn
      ..question = query
      ..intent = intent
      ..language = language
      ..isFollowUp = isFollowUp;

    final base = <String, dynamic>{
      'intent': intent,
      'standalone_query': standalone == null || standalone.isEmpty
          ? query
          : standalone,
    };

    // Same local rules as typed chat, applied to the transcript.
    final direct = AiGuardrails.needsSafetySupport(query)
        ? AiGuardrails.safetySupportAnswer
        : AiGuardrails.isPromptInjection(query)
        ? AiGuardrails.promptInjectionAnswer
        : AiGuardrails.isAbusive(query) || intent == VoiceIntent.offensive
        ? offensiveAnswer
        : intent == VoiceIntent.unsafe
        ? AiGuardrails.safetySupportAnswer
        : language == 'unsupported'
        ? unsupportedLanguageAnswer
        : intent == VoiceIntent.offTopic
        ? offTopicAnswer
        : intent == VoiceIntent.smallTalk
        ? smallTalkAnswer
        : null;
    if (direct != null) {
      turn.directAnswer = direct;
      return {
        ...base,
        'direct_response': {'summary': direct},
      };
    }
    if (intent == VoiceIntent.appHelp) {
      return {...base, 'app_help_context': await loadAppHelp()};
    }
    if (isFollowUp && args['requires_search'] == false) {
      return {...base, 'context_only': true};
    }
    // Retrieve here, in the same step, so the model needs no separate
    // search_careers round trip before answering. English keywords match
    // the records far better than a full or non-English sentence; they are
    // already resolved from the conversation for follow-ups.
    final keywords = args['search_keywords']?.toString().trim() ?? '';
    final standaloneQuery = base['standalone_query'] as String;
    return {
      ...base,
      ...await _records(
        keywords.isNotEmpty
            ? keywords
            : isFollowUp
            ? '${_memory.last.$1} $standaloneQuery'
            : standaloneQuery,
        broad: intent == VoiceIntent.overview || intent == VoiceIntent.advice,
      ),
    };
  }

  Future<Map<String, dynamic>> _records(
    String query, {
    bool broad = false,
  }) async {
    final context = await _retrieve(query, broad: broad);
    turn.sources = context.sources;
    turn.noRecordsFound = context.isEmpty;
    return {
      'record_count': context.sources.length,
      'records': context.isEmpty ? 'NO RECORDS FOUND' : context.text,
      'next_step':
          'Do not speak yet. Call format_answer now with the structured '
          'draft built from these records.',
    };
  }

  Future<Map<String, dynamic>> _search(Map<String, dynamic> args) async {
    final query = args['query']?.toString().trim() ?? turn.question ?? '';
    return _records(turn.isFollowUp ? '${_memory.last.$1} $query' : query);
  }

  Map<String, dynamic> _format(Map<String, dynamic> args) {
    final parsed = AiResponseParser.parse(args['draft']?.toString() ?? '');
    if (parsed.isEmpty) return {'error': 'empty_draft'};
    turn
      ..sections = parsed.sections
      ..suggestions = parsed.answeredQuestions.take(3).toList();
    return {'status': 'formatted', 'next': 'Now speak only the direct answer.'};
  }
}
