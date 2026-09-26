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

  VoiceTurn turn = VoiceTurn();
  final _memory = <(String, String)>[];

  LiveVoiceTools({
    required this.grounding,
    required this.loadAppHelp,
    this.streamId,
  });

  void startTurn() => turn = VoiceTurn();

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
    return {...base, 'next_tool': 'search_careers'};
  }

  Future<Map<String, dynamic>> _search(Map<String, dynamic> args) async {
    final query = args['query']?.toString().trim() ?? turn.question ?? '';
    final context = await grounding.retrieve(
      query: turn.isFollowUp ? '${_memory.last.$1} $query' : query,
      streamId: streamId?.call(),
    );
    turn.sources = context.sources;
    return {
      'record_count': context.sources.length,
      'records': context.isEmpty ? 'NO RECORDS FOUND' : context.text,
      'next_step':
          'Do not speak yet. Call format_answer now with the structured '
          'draft built from these records.',
    };
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
