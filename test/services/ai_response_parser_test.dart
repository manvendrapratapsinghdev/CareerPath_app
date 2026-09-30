import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/services/ai_response_parser.dart';

void main() {
  test('splits titled sections, questions and answers', () {
    final parsed = AiResponseParser.parse('''
<Title>Here you go:</Title> Engineering is a Science path.
<Title>Options</Title>
- Computer Science
- Mechanical

Questions:
1. Which colleges offer it?
2. What books help?

Answers:
1. IIT Jodhpur.
2. Engineering Mathematics.
''');

    expect(parsed.sections.map((s) => s.title), ['Here you go:', 'Options']);
    expect(parsed.sections[1].body, '• Computer Science\n• Mechanical');
    expect(parsed.questions, ['Which colleges offer it?', 'What books help?']);
    expect(parsed.answers.first, 'IIT Jodhpur.');
    expect(parsed.answeredQuestions, hasLength(2));
    expect(
      AiResponseParser.plainText(parsed.sections),
      startsWith('Engineering is a Science path.'),
    );
  });

  test('untitled text becomes a single summary section', () {
    final parsed = AiResponseParser.parse('Just a plain answer.');
    expect(parsed.sections.single.title, 'Summary');
    expect(parsed.questions, isEmpty);
  });

  test('answer sections round-trip through JSON', () {
    const section = AiAnswerSection(title: 'Options', body: 'PCM or PCB');
    final restored = AiAnswerSection.fromJson(section.toJson());
    expect(restored.title, 'Options');
    expect(restored.body, 'PCM or PCB');
  });

  test('a colon lead-in flows into its sentence in read-aloud text', () {
    final parsed = AiResponseParser.parse(
      "<Title>Let's look at your options:</Title> Engineering is a good fit.\n"
      '<Title>Options</Title> Civil and mechanical.',
    );
    expect(
      AiResponseParser.plainText(parsed.sections),
      "Let's look at your options: Engineering is a good fit.\n\n"
      'Options. Civil and mechanical.',
    );
  });
}
