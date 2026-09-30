import 'package:career_path/services/ai_language.dart';
import 'package:career_path/services/guided_ai_prompts.dart';
import 'package:career_path/services/live_voice_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keywords keep the place, course and level across follow-ups', () {
    for (final prompt in [
      GuidedAiPrompts.intent(history: 'None'),
      LiveVoicePrompts.systemInstruction(),
    ]) {
      expect(prompt, contains('level (UG, PG, diploma, PhD)'));
      expect(prompt, contains('"and in Jodhpur?"'));
      expect(prompt, contains('change only the place'));
    }
  });

  test('answers use the match count and coverage note', () {
    final typed = GuidedAiPrompts.answer(
      question: 'colleges in Goa',
      records: 'COVERAGE: CareerPath has no institutes in Goa yet.',
      language: ReplyLanguage.english,
      overview: false,
    );
    final voice = LiveVoicePrompts.systemInstruction();
    for (final prompt in [typed, voice]) {
      expect(prompt, contains('MATCH SUMMARY'));
      expect(prompt, contains('COVERAGE'));
      expect(prompt, contains('never name colleges from other places'));
    }
  });
}
