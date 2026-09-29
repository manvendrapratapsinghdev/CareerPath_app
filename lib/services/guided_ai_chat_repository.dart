import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/ai_provider_config.dart';
import '../config/api_urls.dart';
import '../models/ai_chat.dart';
import 'ai_chat_repository.dart';
import 'ai_guardrails.dart';
import 'ai_language.dart';
import 'ai_response_parser.dart';
import 'gemini_key_service.dart';
import 'guided_ai_prompts.dart';
import 'live_voice_prompts.dart';
import 'live_voice_tools.dart';
import 'local_ai_grounding_service.dart';

/// The AI Guide's typed-chat repository: classifies each question, answers
/// app-help and small talk directly, grounds career questions in local
/// CareerPath data and returns a structured, sectioned answer with
/// follow-up questions.
class GuidedAiChatRepository extends AiChatRepository {
  static const insufficientAnswer =
      'Sorry, I don’t have enough information about that in CareerPath. '
      'Please visit the Explore tab to browse the available career paths.';
  static const insufficientAnswerHindi =
      'माफ़ कीजिए, CareerPath में इसके बारे में पर्याप्त जानकारी नहीं है। '
      'उपलब्ध करियर देखने के लिए Explore टैब खोलें।';
  static const insufficientAnswerHinglish =
      'Sorry, CareerPath mein iske baare mein poori jaankari nahi hai. '
      'Available career paths dekhne ke liye Explore tab kholiye.';
  static const unsupportedLanguageAnswer =
      'Please use English or Hindi so I can help you safely.';
  static const rateLimitAnswer =
      'You are asking questions very quickly. Please wait a moment and try '
      'again.';
  static const policyWarningAnswer =
      'Please don’t use abusive or inappropriate language. I’m here to help '
      'with career and education questions. Continued misuse may temporarily '
      'block chat.';
  static const blockedAnswer =
      'Chat has been temporarily blocked because of repeated inappropriate '
      'language. Please try again later or continue in Explore.';

  static const _supportedLocales = {'en', 'hi'};
  static const _rateLimit = 10;
  static const _rateWindow = Duration(minutes: 1);
  static const _cacheTtl = Duration(hours: 1);

  final GeminiKeyService _keyService;
  final LocalAiGroundingService _grounding;
  final http.Client _client;
  final Future<String> Function() _loadAppHelp;
  final ExtraGrounding? _extraGrounding;
  final DateTime Function() _clock;
  final String model;

  /// Pause before retrying a rate-limited request.
  final Duration retryDelay;

  int _policyStrikes = 0;
  bool _chatBlocked = false;
  final _requestTimes = <DateTime>[];
  final _cache = <String, (DateTime, AiChatResponse)>{};

  /// Answers for suggested follow-up questions, keyed by question text.
  final _followUpAnswers = <String, String>{};

  GuidedAiChatRepository({
    required GeminiKeyService keyService,
    required LocalAiGroundingService groundingService,
    required Future<String> Function() loadAppHelp,
    ExtraGrounding? extraGrounding,
    http.Client? client,
    DateTime Function()? clock,
    this.model = AiProviderConfig.model,
    this.retryDelay = const Duration(seconds: 3),
  }) : _keyService = keyService,
       _grounding = groundingService,
       _loadAppHelp = loadAppHelp,
       _extraGrounding = extraGrounding,
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  @override
  Future<AiChatResponse> send(AiChatRequest request) async {
    final question = request.messages.isEmpty
        ? ''
        : request.messages.last.content.trim();
    final language = _replyLanguage(question, request.locale);
    AiChatResponse reply(
      AiChatStatus status,
      String answer, {
      bool blocked = false,
    }) => _response(request, status, answer, chatBlocked: blocked);

    if (question.isEmpty) {
      return reply(
        AiChatStatus.error,
        'Please enter a career or education question.',
      );
    }
    if (!_supportedLocales.contains(request.locale)) {
      return reply(AiChatStatus.unsupportedLanguage, unsupportedLanguageAnswer);
    }
    if (AiGuardrails.needsSafetySupport(question)) {
      return reply(
        AiChatStatus.safetySupport,
        AiGuardrails.safetySupportAnswer,
      );
    }
    if (_chatBlocked) {
      return reply(AiChatStatus.blocked, blockedAnswer, blocked: true);
    }
    if (AiGuardrails.isPromptInjection(question)) {
      return reply(
        AiChatStatus.policyWarning,
        AiGuardrails.promptInjectionAnswer,
      );
    }
    if (AiGuardrails.isAbusive(question)) {
      _policyStrikes++;
      if (_policyStrikes >= 2) {
        _chatBlocked = true;
        return reply(AiChatStatus.blocked, blockedAnswer, blocked: true);
      }
      return reply(AiChatStatus.policyWarning, policyWarningAnswer);
    }
    if (!_allowRequest()) {
      return reply(AiChatStatus.policyWarning, rateLimitAnswer);
    }

    final history = request.messages.sublist(0, request.messages.length - 1);
    final cacheKey = history.isEmpty
        ? '${request.locale}:${request.streamId}:${_normalise(question)}'
        : null;
    final cached = cacheKey == null ? null : _cache[cacheKey];
    if (cached != null && _clock().difference(cached.$1) < _cacheTtl) {
      return _withRequestId(cached.$2, request.requestId);
    }
    final storedFollowUp = _followUpAnswers[_normalise(question)];

    final intent = await _classify(question, history);
    debugPrint('[AI Guide] intent=${intent.intent}');

    switch (intent.intent) {
      case VoiceIntent.offensive:
        return reply(AiChatStatus.policyWarning, policyWarningAnswer);
      case VoiceIntent.unsafe:
        return reply(
          AiChatStatus.safetySupport,
          AiGuardrails.safetySupportAnswer,
        );
      case VoiceIntent.offTopic:
        return reply(AiChatStatus.answered, LiveVoiceTools.offTopicAnswer);
      case VoiceIntent.smallTalk:
        return reply(AiChatStatus.answered, LiveVoiceTools.smallTalkAnswer);
      case VoiceIntent.appHelp:
        return _appHelp(request, question, language);
    }

    final searchQuery = intent.searchQuery.isNotEmpty
        ? intent.searchQuery
        : intent.rewritten ?? question;
    final grounding = await _retrieve(searchQuery, request.streamId);
    if (grounding.isEmpty) {
      return _fallback(request, storedFollowUp, language);
    }

    final raw = await _generate(
      GuidedAiPrompts.answer(
        question: intent.rewritten ?? question,
        records: grounding.text,
        language: language,
        overview: intent.intent == VoiceIntent.overview,
      ),
      question,
      history: history,
    );
    final parsed = AiResponseParser.parse(raw);
    if (parsed.isEmpty || _isRefusal(parsed)) {
      return _fallback(request, storedFollowUp, language);
    }

    for (var i = 0; i < parsed.questions.length; i++) {
      if (i < parsed.answers.length && parsed.answers[i].trim().isNotEmpty) {
        _followUpAnswers[_normalise(parsed.questions[i])] = parsed.answers[i];
      }
    }
    final response = AiChatResponse(
      requestId: request.requestId,
      status: AiChatStatus.answered,
      answer: AiResponseParser.plainText(parsed.sections),
      sources: grounding.sources.take(3).toList(growable: false),
      suggestedPrompts: parsed.answeredQuestions.take(3).toList(),
      dataVersion: 'bundled-career-path-db',
      sections: parsed.sections,
    );
    if (cacheKey != null) _cache[cacheKey] = (_clock(), response);
    return response;
  }

  // ── Steps ────────────────────────────────────────────────────────────────

  Future<({String intent, String searchQuery, String? rewritten})> _classify(
    String question,
    List<AiChatMessage> history,
  ) async {
    final recent = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    final transcript = recent.isEmpty
        ? 'None'
        : recent
              .map(
                (m) =>
                    '${m.role == AiChatRole.user ? 'Student' : 'Guide'}: '
                    '${_clip(m.content, 400)}',
              )
              .join('\n');
    try {
      final text = await _post(
        systemInstruction: GuidedAiPrompts.intent(history: transcript),
        contents: [_userTurn(question)],
        responseSchema: GuidedAiPrompts.intentSchema,
        temperature: 0,
        maxOutputTokens: 200,
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      var intent = json['intent']?.toString() ?? VoiceIntent.career;
      if (!VoiceIntent.all.contains(intent)) intent = VoiceIntent.career;
      if (history.isEmpty &&
          (intent == VoiceIntent.followUp ||
              intent == VoiceIntent.clarification)) {
        intent = VoiceIntent.career;
      }
      final rewritten = json['follow_up_query']?.toString().trim();
      return (
        intent: intent,
        searchQuery: json['search_query']?.toString().trim() ?? '',
        rewritten: rewritten == null || rewritten.isEmpty ? null : rewritten,
      );
    } on GeminiKeyException {
      rethrow;
    } on Object {
      return (intent: VoiceIntent.career, searchQuery: '', rewritten: null);
    }
  }

  Future<AiGroundingContext> _retrieve(String query, String? streamId) async {
    final keyword = await _grounding.retrieve(query: query, streamId: streamId);
    final extra = _extraGrounding;
    if (extra == null) return keyword;
    AiGroundingContext semantic;
    try {
      semantic = await extra(query, streamId);
    } on Object {
      return keyword;
    }
    return AiGroundingContext.merge(keyword, semantic);
  }

  Future<AiChatResponse> _appHelp(
    AiChatRequest request,
    String question,
    ReplyLanguage language,
  ) async {
    final help = await _loadAppHelp();
    final raw = await _post(
      systemInstruction: GuidedAiPrompts.appHelp,
      contents: [
        _userTurn(
          'APP HELP:\n$help\n\nQUESTION: $question\n\n'
          'Reply in ${AiLanguage.instruction(language)}.',
        ),
      ],
    );
    final parsed = AiResponseParser.parse(raw);
    return AiChatResponse(
      requestId: request.requestId,
      status: AiChatStatus.answered,
      answer: AiResponseParser.plainText(parsed.sections),
      dataVersion: 'bundled-career-path-db',
      sections: parsed.sections,
    );
  }

  AiChatResponse _fallback(
    AiChatRequest request,
    String? storedFollowUp,
    ReplyLanguage language,
  ) {
    if (storedFollowUp != null) {
      return AiChatResponse(
        requestId: request.requestId,
        status: AiChatStatus.answered,
        answer: storedFollowUp,
        dataVersion: 'bundled-career-path-db',
      );
    }
    return _response(
      request,
      AiChatStatus.insufficientData,
      AiLanguage.pick(
        language,
        english: insufficientAnswer,
        hindi: insufficientAnswerHindi,
        hinglish: insufficientAnswerHinglish,
      ),
    );
  }

  Future<String> _generate(
    String systemInstruction,
    String question, {
    required List<AiChatMessage> history,
  }) {
    final recent = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    return _post(
      systemInstruction: systemInstruction,
      contents: [
        for (final message in recent)
          {
            'role': message.role == AiChatRole.assistant ? 'model' : 'user',
            'parts': [
              {'text': message.content},
            ],
          },
        _userTurn(question),
      ],
    );
  }

  Future<String> _post({
    required String systemInstruction,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? responseSchema,
    double temperature = 0.3,
    int maxOutputTokens = AiProviderConfig.maxOutputTokens,
    bool retryOnRateLimit = true,
  }) async {
    final key = await _keyService.getKey();
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(ApiUrls.geminiGenerateContent(model)),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'CareerPath/1.0',
              'x-goog-api-key': key,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': systemInstruction},
                ],
              },
              'contents': contents,
              'generationConfig': {
                'temperature': temperature,
                'maxOutputTokens': maxOutputTokens,
                ..._thinkingConfig(model),
                if (responseSchema != null)
                  'responseMimeType': 'application/json',
                'responseSchema': ?responseSchema,
              },
            }),
          )
          .timeout(AiProviderConfig.generationTimeout);
    } on Exception {
      throw const GeminiKeyException('generation_unavailable');
    }
    if (response.statusCode == 429 && retryOnRateLimit) {
      // The shared key is rate limited per minute; one short retry usually
      // succeeds.
      await Future<void>.delayed(retryDelay);
      return _post(
        systemInstruction: systemInstruction,
        contents: contents,
        responseSchema: responseSchema,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        retryOnRateLimit: false,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiKeyException('gemini_http_${response.statusCode}');
    }
    try {
      final parts =
          ((((jsonDecode(response.body) as Map)['candidates'] as List).first
                      as Map)['content']
                  as Map)['parts']
              as List;
      final text = parts
          .whereType<Map>()
          .where((part) => part['thought'] != true)
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (text.trim().isEmpty) throw const FormatException();
      return text;
    } on Object {
      throw const GeminiKeyException('invalid_gemini_response');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _thinkingConfig(String model) {
    if (model.startsWith('gemini-2.5')) {
      return {
        'thinkingConfig': {'thinkingBudget': 0},
      };
    }
    if (model.startsWith('gemini-3')) {
      return {
        'thinkingConfig': {'thinkingLevel': 'minimal'},
      };
    }
    return const {};
  }

  static Map<String, dynamic> _userTurn(String text) => {
    'role': 'user',
    'parts': [
      {'text': text},
    ],
  };

  bool _allowRequest() {
    final now = _clock();
    _requestTimes.removeWhere((time) => now.difference(time) >= _rateWindow);
    if (_requestTimes.length >= _rateLimit) return false;
    _requestTimes.add(now);
    return true;
  }

  static bool _isRefusal(ParsedAiAnswer parsed) {
    final text = parsed.sections.map((s) => s.body).join(' ').toLowerCase();
    return parsed.sections.length == 1 &&
        (text.contains("isn't available in careerpath") ||
            text.contains('उपलब्ध नहीं'));
  }

  /// The language to answer in, detected from the question itself so a
  /// Hindi-UI student typing English (or Hinglish) still gets that language
  /// back. The UI locale is only a fallback when there is no question text
  /// to detect from.
  static ReplyLanguage _replyLanguage(String question, String locale) {
    if (question.trim().isEmpty) {
      return locale == 'hi' ? ReplyLanguage.hindi : ReplyLanguage.english;
    }
    return AiLanguage.detect(question);
  }

  static String _normalise(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  AiChatResponse _withRequestId(AiChatResponse cached, String requestId) =>
      AiChatResponse(
        requestId: requestId,
        status: cached.status,
        answer: cached.answer,
        sources: cached.sources,
        suggestedPrompts: cached.suggestedPrompts,
        dataVersion: cached.dataVersion,
        sections: cached.sections,
      );

  AiChatResponse _response(
    AiChatRequest request,
    AiChatStatus status,
    String answer, {
    bool chatBlocked = false,
  }) => AiChatResponse(
    requestId: request.requestId,
    status: status,
    answer: answer,
    chatBlocked: chatBlocked,
    dataVersion: 'bundled-career-path-db',
  );

  @override
  void dispose() {
    _policyStrikes = 0;
    _chatBlocked = false;
    _client.close();
  }
}
