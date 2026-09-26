import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_chat.dart';
import 'ai_gemini_json.dart';
import 'career_data_service.dart';
import 'guided_ai_prompts.dart';
import 'institute_catalog_service.dart';
import 'local_ai_grounding_service.dart';

/// Daily trending starter questions for the AI Guide's empty screen.
class AiTrendingService {
  static const _key = 'ai_trending_questions';
  static const _dateKey = 'ai_trending_date';

  final AiGeminiJson _gemini;
  final CareerDataService _careers;
  final InstituteCatalogService? _catalog;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  AiTrendingService({
    required AiGeminiJson gemini,
    required CareerDataService careers,
    required SharedPreferences prefs,
    InstituteCatalogService? catalog,
    DateTime Function()? clock,
  }) : _gemini = gemini,
       _careers = careers,
       _catalog = catalog,
       _prefs = prefs,
       _clock = clock ?? DateTime.now;

  /// Cached questions for today, or a new set; null when unavailable.
  Future<List<String>?> questions() async {
    final today = _day(_clock());
    final cached = _prefs.getStringList(_key);
    if (cached != null &&
        cached.isNotEmpty &&
        _prefs.getString(_dateKey) == today) {
      return cached;
    }
    try {
      final titles = await pickTitles();
      if (titles.isEmpty) return cached;
      final json = await _gemini.generate(
        instruction: GuidedAiPrompts.trendingTopics,
        input: titles.map((t) => '- $t').join('\n'),
        schema: const {
          'type': 'OBJECT',
          'required': ['questions'],
          'properties': {
            'questions': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
        },
        maxOutputTokens: 300,
      );
      final questions = ((json['questions'] as List?) ?? const [])
          .map((q) => q.toString().trim())
          .where(isValidQuestion)
          .take(3)
          .toList();
      if (questions.isEmpty) return cached;
      await _prefs.setStringList(_key, questions);
      await _prefs.setString(_dateKey, today);
      return questions;
    } on Object {
      return cached;
    }
  }

  /// A date-seeded mix of career paths and ranked institutes.
  Future<List<String>> pickTitles() async {
    await _careers.ensureInitialized();
    await _catalog?.ensureLoaded();
    final now = _clock();
    final random = math.Random(now.year * 1000 + now.month * 40 + now.day);
    final careers = _careers.getAllNodes().where((n) => n.isLeaf).toList()
      ..shuffle(random);
    final ranked =
        (_catalog?.records ?? const [])
            .where((r) => r.rankings.isNotEmpty)
            .toList()
          ..shuffle(random);
    return [
      ...careers.take(2).map((n) => '${n.name} (career path)'),
      ...ranked.take(1).map((r) => '${r.institute.name} (ranked institute)'),
    ];
  }

  /// Rejects runaway model output: one short question only.
  static bool isValidQuestion(String question) {
    final words = question.split(RegExp(r'\s+'));
    return question.length <= 110 &&
        words.length >= 3 &&
        words.length <= 15 &&
        '?'.allMatches(question).length == 1;
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

/// A short intro and question/answer pairs about one source record.
class AiDeepDive {
  final String intro;
  final List<(String, String)> faqs;

  const AiDeepDive({required this.intro, required this.faqs});
}

/// Builds "Learn more about this" deep dives for chat sources.
class AiDeepDiveService {
  final AiGeminiJson _gemini;
  final LocalAiGroundingService _grounding;
  final _cache = <String, AiDeepDive>{};

  AiDeepDiveService({
    required AiGeminiJson gemini,
    required LocalAiGroundingService grounding,
  }) : _gemini = gemini,
       _grounding = grounding;

  Future<AiDeepDive> deepDive(AiChatSource source, {bool hindi = false}) async {
    final cacheKey = '${hindi ? 'hi' : 'en'}:${source.sourceId}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final context = await _grounding.retrieve(query: source.title);
    final record = recordBlock(context.text, source.sourceId) ?? context.text;
    final fallback = AiDeepDive(intro: source.title, faqs: const []);
    if (record.trim().isEmpty) return fallback;
    try {
      final json = await _gemini.generate(
        instruction:
            'Write a short deep dive about one CareerPath record using ONLY '
            'the record. Return JSON with "intro": two warm, simple sentences '
            'for a student, and "faqs": exactly 3 objects {"question", '
            '"answer"} a student might ask, each answer one or two sentences '
            'from the record. Never add fees, cut-offs, salaries or dates '
            'that are not in the record. Write in '
            '${hindi ? 'Hindi (Devanagari)' : 'English'}.',
        input: record,
        schema: const {
          'type': 'OBJECT',
          'required': ['intro', 'faqs'],
          'properties': {
            'intro': {'type': 'STRING'},
            'faqs': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['question', 'answer'],
                'properties': {
                  'question': {'type': 'STRING'},
                  'answer': {'type': 'STRING'},
                },
              },
            },
          },
        },
      );
      final dive = AiDeepDive(
        intro: json['intro']?.toString().trim() ?? source.title,
        faqs: [
          for (final faq
              in (json['faqs'] as List? ?? const []).whereType<Map>())
            if ('${faq['question'] ?? ''}'.trim().isNotEmpty &&
                '${faq['answer'] ?? ''}'.trim().isNotEmpty)
              ('${faq['question']}'.trim(), '${faq['answer']}'.trim()),
        ].take(3).toList(),
      );
      if (dive.faqs.isNotEmpty) _cache[cacheKey] = dive;
      return dive;
    } on Object {
      return fallback;
    }
  }

  /// The grounding block that starts with `SOURCE <sourceId>`.
  static String? recordBlock(String text, String sourceId) {
    final start = text.indexOf('SOURCE $sourceId\n');
    if (start < 0) return null;
    final next = text.indexOf('\nSOURCE ', start + 1);
    final details = text.indexOf('\nDETAILS FOR $sourceId', start);
    final end = next < 0 ? text.length : next;
    var block = text.substring(start, end).trim();
    if (details > 0) {
      final detailsEnd = text.indexOf('\nDETAILS FOR ', details + 1);
      block +=
          '\n${text.substring(details, detailsEnd < 0 ? text.length : detailsEnd).trim()}';
    }
    return block;
  }
}

/// AI answer feedback (helpful / not helpful with reasons), kept on device.
class AiFeedbackService {
  static const _key = 'ai_answer_feedback';
  static const _limit = 200;

  final SharedPreferences _prefs;

  AiFeedbackService(this._prefs);

  List<Map<String, dynamic>> get entries => (_prefs.getStringList(_key) ?? [])
      .map((e) => jsonDecode(e) as Map<String, dynamic>)
      .toList();

  Future<void> save({
    required String messageId,
    required bool helpful,
    String question = '',
    String answer = '',
    List<String> reasons = const [],
    String comment = '',
  }) async {
    final list = _prefs.getStringList(_key) ?? [];
    list.add(
      jsonEncode({
        'messageId': messageId,
        'helpful': helpful,
        'question': question,
        'answer': answer.length > 2000 ? answer.substring(0, 2000) : answer,
        'reasons': reasons,
        'comment': comment,
        'at': DateTime.now().toIso8601String(),
      }),
    );
    await _prefs.setStringList(
      _key,
      list.length > _limit ? list.sublist(list.length - _limit) : list,
    );
  }
}

/// Optional AI Guide extras, created in main.dart.
class AiGuideExtras {
  final AiTrendingService trending;
  final AiDeepDiveService deepDive;
  final AiFeedbackService feedback;

  const AiGuideExtras({
    required this.trending,
    required this.deepDive,
    required this.feedback,
  });
}
