import 'package:career_path/services/ai_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiLanguage.detect', () {
    test('detects English', () {
      expect(
        AiLanguage.detect('What can I do after 12th science?'),
        ReplyLanguage.english,
      );
    });

    test('detects Hindi written in Devanagari', () {
      expect(
        AiLanguage.detect('मुझे यूपी में कुछ कॉलेज बताओ जो बीए करवाते हैं'),
        ReplyLanguage.hindi,
      );
    });

    test('detects Hinglish written in Latin letters', () {
      expect(
        AiLanguage.detect('engineering ke baad mujhe kya karna chahiye'),
        ReplyLanguage.hinglish,
      );
    });

    test('detects Hinglish from a short common phrase', () {
      expect(AiLanguage.detect('kya hai'), ReplyLanguage.hinglish);
    });

    test('detects an unsupported script', () {
      expect(
        AiLanguage.detect('எனக்கு உதவி வேண்டும்'),
        ReplyLanguage.unsupported,
      );
    });
  });

  group('AiLanguage.instruction', () {
    test('gives a language-specific writing instruction', () {
      expect(AiLanguage.instruction(ReplyLanguage.english), 'English');
      expect(
        AiLanguage.instruction(ReplyLanguage.hindi),
        contains('Devanagari'),
      );
      expect(
        AiLanguage.instruction(ReplyLanguage.hinglish),
        contains('Hinglish'),
      );
      expect(AiLanguage.instruction(ReplyLanguage.unsupported), 'English');
    });
  });

  group('AiLanguage.speechLocale', () {
    test('picks a TTS locale matching the detected language', () {
      expect(AiLanguage.speechLocale('Tell me about NEET'), 'en-US');
      expect(AiLanguage.speechLocale('इंजीनियरिंग के बारे में बताओ'), 'hi-IN');
      expect(AiLanguage.speechLocale('mujhe kya karna chahiye'), 'en-IN');
    });
  });

  group('AiLanguage.pick', () {
    test('returns the value matching the language', () {
      String pick(ReplyLanguage language) => AiLanguage.pick(
        language,
        english: 'e',
        hindi: 'h',
        hinglish: 'g',
      );
      expect(pick(ReplyLanguage.english), 'e');
      expect(pick(ReplyLanguage.hindi), 'h');
      expect(pick(ReplyLanguage.hinglish), 'g');
      expect(pick(ReplyLanguage.unsupported), 'e');
    });
  });
}
