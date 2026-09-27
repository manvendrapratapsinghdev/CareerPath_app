/// The language a reply should use, chosen from each message itself.
enum ReplyLanguage {
  english,
  hindi,

  /// Hindi written in English letters ("engineering ke baad kya karu").
  hinglish,

  /// A script the AI Guide does not support (e.g. Tamil, Arabic).
  unsupported,
}

class AiLanguage {
  const AiLanguage._();

  static final _devanagari = RegExp(r'[ऀ-ॿ]');
  static final _latin = RegExp(r'[A-Za-z]');
  static final _anyLetter = RegExp(r'\p{L}', unicode: true);

  /// Common Hindi words as typed in English letters. Words that collide with
  /// common English words ("me", "ho", "so", "is") are deliberately left out
  /// so an ordinary English sentence isn't misread as Hinglish.
  static const _hinglishWords = {
    'kya', 'kyaa', 'hai', 'hain', 'ke', 'ki', 'ka', 'ko', 'se',
    'mein', 'mai', 'main', 'mujhe', 'muje', 'mera', 'meri', 'baad', 'bad',
    'kaise', 'kaisa', 'kaun', 'konsa', 'kaunsa', 'kitna', 'kitni', 'kab',
    'kahan', 'kaha', 'karu', 'karoon', 'karna', 'karne', 'kar', 'chahiye',
    'chahta', 'chahti', 'nahi', 'nahin', 'aur', 'ya', 'bhi', 'hota', 'hoti',
    'batao', 'bataiye', 'bataye', 'padhai', 'naukri', 'accha', 'acha',
    'sabse', 'liye', 'wala', 'wali', 'kuch', 'koi', 'tha', 'thi', 'raha',
    'rahi', 'sakta', 'sakti', 'sakte', 'yeh', 'ye', 'woh', 'wo', 'agar',
  };

  static ReplyLanguage detect(String text) {
    final devanagari = _devanagari.allMatches(text).length;
    final latin = _latin.allMatches(text).length;
    final other = _anyLetter.allMatches(text).length - devanagari - latin;
    if (other > devanagari && other > latin) return ReplyLanguage.unsupported;
    if (devanagari > 0 && devanagari >= latin / 3) return ReplyLanguage.hindi;
    final words = text
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final hindiWords = words.where(_hinglishWords.contains).length;
    if (hindiWords >= 2 || (words.length <= 4 && hindiWords >= 1)) {
      return ReplyLanguage.hinglish;
    }
    return ReplyLanguage.english;
  }

  /// Instruction for the model describing the reply language.
  static String instruction(ReplyLanguage language) => switch (language) {
    ReplyLanguage.hindi =>
      'Hindi in Devanagari script, keeping course, college and exam names as '
          'written in the records',
    ReplyLanguage.hinglish =>
      'Hinglish: simple Hindi written in English (Roman) letters, the way the '
          'student wrote, e.g. "Engineering ke baad aap software developer ban '
          'sakte hain." Do not use Devanagari',
    _ => 'English',
  };

  /// Text-to-speech locale for reading [text] aloud.
  static String speechLocale(String text) => switch (detect(text)) {
    ReplyLanguage.hindi => 'hi-IN',
    ReplyLanguage.hinglish => 'en-IN',
    _ => 'en-US',
  };

  /// A fixed reply in the student's language.
  static String pick(
    ReplyLanguage language, {
    required String english,
    required String hindi,
    required String hinglish,
  }) => switch (language) {
    ReplyLanguage.hindi => hindi,
    ReplyLanguage.hinglish => hinglish,
    _ => english,
  };
}
