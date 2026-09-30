import '../models/ai_chat.dart';

/// A structured answer: titled sections plus follow-up question/answer
/// pairs.
class ParsedAiAnswer {
  final List<AiAnswerSection> sections;
  final List<String> questions;
  final List<String> answers;

  const ParsedAiAnswer({
    required this.sections,
    required this.questions,
    required this.answers,
  });

  bool get isEmpty => sections.isEmpty;

  /// Follow-up questions that come with a non-empty answer.
  List<String> get answeredQuestions => [
    for (var i = 0; i < questions.length && i < answers.length; i++)
      if (answers[i].trim().isNotEmpty) questions[i],
  ];
}

/// Parses model output of the form
/// `<Title>…</Title> body … Questions: 1. … Answers: 1. …`.
class AiResponseParser {
  const AiResponseParser._();

  static final _blockHeading = RegExp(
    r'^\s*(?:#{1,6}\s*)?(?:\*\*)?\s*(Questions|Answers)\s*(?:\*\*)?\s*:?\s*(?:\*\*)?\s*$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _inlineHeading = RegExp(
    r'(?:^|\s)(?:\*\*)?(Questions|Answers)(?:\*\*)?\s*:',
    caseSensitive: false,
  );
  static final _titled = RegExp(
    r'<Title>(.*?)</Title>(.*?)(?=<Title>|$)',
    caseSensitive: false,
    dotAll: true,
  );
  static final _tag = RegExp(r'<[^>]+>');
  static final _openTag = RegExp(r'<[^>]*$');
  static final _numbering = RegExp(r'^\s*(?:\d+[.)]|[-*•]+)\s*');

  static ParsedAiAnswer parse(String raw) {
    var headings = _blockHeading.allMatches(raw).toList();
    if (headings.isEmpty) headings = _inlineHeading.allMatches(raw).toList();
    RegExpMatch? questions;
    RegExpMatch? answers;
    for (final heading in headings) {
      final name = heading.group(1)!.toLowerCase();
      if (name == 'questions' && questions == null) questions = heading;
      if (name == 'answers' &&
          answers == null &&
          (questions == null || heading.start > questions.start)) {
        answers = heading;
      }
    }
    final cuts = [?questions?.start, ?answers?.start];
    final summaryEnd = cuts.isEmpty
        ? raw.length
        : cuts.reduce((a, b) => a < b ? a : b);

    return ParsedAiAnswer(
      sections: _sections(raw.substring(0, summaryEnd)),
      questions: questions == null
          ? const []
          : _items(
              raw.substring(
                questions.end,
                answers != null ? answers.start : raw.length,
              ),
            ),
      answers: answers == null ? const [] : _items(raw.substring(answers.end)),
    );
  }

  /// Plain text for read-aloud and copy, without generic headings.
  static String plainText(List<AiAnswerSection> sections) => sections
      .map(
        (section) => _isGeneric(section.title)
            ? section.body
            // A lead-in such as "Let's look at your options:" flows into its
            // sentence; a heading gets a full stop.
            : section.title.trimRight().endsWith(':')
            ? '${section.title.trimRight()} ${section.body}'
            : '${section.title}. ${section.body}',
      )
      .join('\n\n');

  static bool _isGeneric(String title) {
    final t = title.toLowerCase().replaceAll(':', '').trim();
    return t.isEmpty || t == 'here you go' || t == 'summary' || t == 'answer';
  }

  static List<AiAnswerSection> _sections(String text) {
    if (text.trim().isEmpty) return const [];
    final result = <AiAnswerSection>[];
    final firstTitle = _titled.firstMatch(text);
    if (firstTitle == null) {
      return [AiAnswerSection(title: 'Summary', body: _clean(text))];
    }
    final lead = _clean(text.substring(0, firstTitle.start));
    if (lead.isNotEmpty) {
      result.add(AiAnswerSection(title: 'Summary', body: lead));
    }
    for (final match in _titled.allMatches(text)) {
      final title = match.group(1)!.replaceAll(_tag, '').trim();
      final body = _clean(match.group(2)!);
      if (title.isNotEmpty && body.isNotEmpty) {
        result.add(AiAnswerSection(title: title, body: body));
      }
    }
    return result;
  }

  static String _clean(String value) => value
      .replaceAll(_tag, '')
      .replaceAll(_openTag, '')
      .replaceAll('**', '')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^[*\-]\s+'), '• '))
      .join('\n');

  static List<String> _items(String raw) => raw
      .split('\n')
      .where((line) => _blockHeading.matchAsPrefix(line) == null)
      .map((line) => _clean(line.replaceFirst(_numbering, '')))
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}
