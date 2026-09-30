/// Snaps misspelled or misheard search words to the closest word that
/// actually appears in CareerPath data ("enginering" → "engineering",
/// "jaipr" → "jaipur"), so exact keyword matching still finds the records.
///
/// Only words from names (careers, colleges, places, courses) are correction
/// targets. A word that is real English (the bundled dictionary), appears
/// anywhere in the data, or is a common query word is left alone — so
/// "mother" never becomes "other" and "best" never becomes "west".
class SearchSpellCorrector {
  /// Shorter words are too ambiguous to correct ("law" vs "low").
  static const minLength = 4;

  /// Bundled English word list, one lowercase word per line.
  static const dictionaryAsset = 'assets/data/english_words.txt';

  /// Parses [dictionaryAsset]; heavy enough to run in a background isolate.
  static Set<String> parseDictionary(String text) =>
      text.split('\n').where((word) => word.isNotEmpty).toSet();

  /// Words missing from the 1934 dictionary and the data that students use.
  static const _commonWords = {
    // Modern English
    'coding', 'email', 'internet', 'laptop', 'mobile', 'offline', 'online',
    'placement', 'placements', 'software', 'startup', 'startups', 'website',
    'youtube', 'okay',
    // English
    'about', 'admission', 'after', 'before', 'best', 'become', 'career',
    'careers', 'cheap', 'class', 'college', 'colleges', 'course', 'courses',
    'cutoff', 'details', 'eligibility', 'exam', 'exams', 'fees', 'from',
    'good', 'government', 'help', 'into', 'jobs', 'know', 'like', 'list',
    'marks', 'near', 'options', 'percent', 'please', 'private', 'rank',
    'ranking', 'salary', 'should', 'study', 'suggest', 'tell', 'that',
    'there', 'these', 'this', 'what', 'when', 'where', 'which', 'with',
    'want', 'will', 'your',
    // Hinglish
    'accha', 'achha', 'baad', 'batao', 'bataiye', 'chahiye', 'hain', 'karna',
    'karoon', 'karu', 'kaise', 'kaun', 'kaunsa', 'kitna', 'konsa', 'kuch',
    'liye', 'mein', 'mujhe', 'padhai', 'sakta', 'sakti', 'wala', 'wale',
    'acchi', 'achi', 'agar', 'apna', 'apni', 'bahut', 'banana', 'banna',
    'bhai', 'chahta', 'chahti', 'didi', 'isme', 'jaana', 'jana', 'kaha',
    'kahan', 'kaunse', 'kaunsi', 'kitne', 'kitni', 'kyunki', 'lekin',
    'milega', 'milegi', 'naukri', 'padhna', 'paise', 'pehle', 'samjhao',
    'samjhaiye', 'sabse', 'sarkari', 'sirf', 'unka', 'wali',
  };

  final Set<String> _known;
  final Set<String> _dictionary;
  final Map<int, List<String>> _byLength = {};
  final Map<String, int> _frequency = {};

  /// [names] are correction targets; [otherText] (descriptions, intros) only
  /// marks words as correctly spelled.
  SearchSpellCorrector({
    required Iterable<String> names,
    Iterable<String> otherText = const [],
    Set<String> dictionary = const {},
  }) : _known = {..._commonWords},
       _dictionary = dictionary {
    for (final text in names) {
      for (final word in words(text)) {
        _frequency[word] = (_frequency[word] ?? 0) + 1;
      }
    }
    for (final word in _frequency.keys) {
      _known.add(word);
      if (word.length >= minLength - 2) {
        (_byLength[word.length] ??= []).add(word);
      }
    }
    for (final text in otherText) {
      _known.addAll(words(text));
    }
  }

  int get vocabularySize => _frequency.length;

  static Iterable<String> words(String text) => RegExp(r'[a-z0-9]+')
      .allMatches(text.toLowerCase().replaceAll('.', ''))
      .map((match) => match.group(0)!);

  /// [query] with each misspelled word replaced; everything else, including
  /// non-Latin script, is kept exactly as given.
  String correctQuery(String query) =>
      query.replaceAllMapped(RegExp('[A-Za-z0-9]+'), (match) {
        final word = match.group(0)!;
        final corrected = correct(word.toLowerCase());
        return corrected == word.toLowerCase() ? word : corrected;
      });

  /// The closest data word to [word], or [word] itself when it is already
  /// known, too short, contains digits, or nothing is close enough.
  ///
  /// A word the data itself misspells once ("psycology" beside many
  /// "psychology") comes back with the common spelling too, so both the
  /// typo'd record and the correctly spelled ones match.
  String correct(String word) {
    if (word.length < minLength || word.contains(RegExp('[0-9]'))) {
      return word;
    }
    if (_frequency[word] == 1 && word.length >= 6) {
      final common = _closest(word, maxEdits: 1, minFrequency: 5);
      return common == null ? word : '$word $common';
    }
    if (isWord(word)) return word;
    return _closest(word, maxEdits: word.length <= 7 ? 1 : 2) ?? word;
  }

  /// Known to the data, the common-word list or the dictionary, directly or
  /// as a plural or other inflection ("colleges", "studied", "studying").
  bool isWord(String word) {
    bool known(String w) => _known.contains(w) || _dictionary.contains(w);
    if (known(word)) return true;
    for (final (suffix, replacements) in _inflections) {
      if (!word.endsWith(suffix) || word.length - suffix.length < 3) continue;
      final stem = word.substring(0, word.length - suffix.length);
      if (replacements.any((end) => known('$stem$end'))) return true;
    }
    return false;
  }

  static const _inflections = [
    ('ies', ['y']),
    ('es', ['', 'e']),
    ('s', ['']),
    ('ied', ['y']),
    ('ed', ['', 'e']),
    ('ing', ['', 'e']),
    ('ly', ['']),
    ('er', ['', 'e']),
    ('ers', ['', 'e']),
  ];

  String? _closest(String word, {required int maxEdits, int minFrequency = 1}) {
    String? best;
    var bestRank = const (999, 1, 0);
    for (
      var length = word.length - maxEdits;
      length <= word.length + maxEdits;
      length++
    ) {
      for (final candidate in _byLength[length] ?? const <String>[]) {
        if (candidate == word || _frequency[candidate]! < minFrequency) {
          continue;
        }
        final sameStart = candidate.codeUnitAt(0) == word.codeUnitAt(0);
        // A changed first letter is only trusted in longer words
        // ("kemistry" → "chemistry"); in short ones it's usually another word.
        if (!sameStart && word.length < 6) continue;
        // Half-edit units: sound-alike changes are cheap.
        final cost = distance(word, candidate, maxEdits * 2);
        if (cost > maxEdits * 2) continue;
        final rank = (cost, sameStart ? 0 : 1, -_frequency[candidate]!);
        if (_better(rank, bestRank) ||
            (rank == bestRank &&
                best != null &&
                candidate.compareTo(best) < 0)) {
          best = candidate;
          bestRank = rank;
        }
      }
    }
    return best;
  }

  static bool _better((int, int, int) a, (int, int, int) b) => a.$1 != b.$1
      ? a.$1 < b.$1
      : a.$2 != b.$2
      ? a.$2 < b.$2
      : a.$3 < b.$3;

  static const _vowels = 'aeiouy';

  /// Letters students swap when spelling by sound.
  static const _soundAlike = {'ck', 'kc', 'sz', 'zs', 'vw', 'wv'};

  static int _substitution(int a, int b) {
    if (a == b) return 0;
    final x = String.fromCharCode(a), y = String.fromCharCode(b);
    if (_vowels.contains(x) && _vowels.contains(y)) return 1;
    return _soundAlike.contains('$x$y') ? 1 : 2;
  }

  static int _indel(int c) => _vowels.contains(String.fromCharCode(c)) ? 1 : 2;

  /// Optimal string alignment distance in half-edit units: a vowel change,
  /// added or dropped vowel, or sound-alike letter (c/k, s/z, v/w) costs 1;
  /// any other insert, delete, substitute or swap of neighbours costs 2.
  /// Returns `max + 1` as soon as the cost must exceed [max].
  static int distance(String a, String b, int max) {
    if ((a.length - b.length).abs() > max) return max + 1;
    var twoBack = List<int>.filled(b.length + 1, 0);
    var previous = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      previous[j] = previous[j - 1] + _indel(b.codeUnitAt(j - 1));
    }
    for (var i = 1; i <= a.length; i++) {
      final ca = a.codeUnitAt(i - 1);
      final current = List<int>.filled(b.length + 1, 0)
        ..[0] = previous[0] + _indel(ca);
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j++) {
        final cb = b.codeUnitAt(j - 1);
        var value = previous[j] + _indel(ca);
        final insert = current[j - 1] + _indel(cb);
        if (insert < value) value = insert;
        final substitute = previous[j - 1] + _substitution(ca, cb);
        if (substitute < value) value = substitute;
        if (i > 1 &&
            j > 1 &&
            ca == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == cb &&
            twoBack[j - 2] + 2 < value) {
          value = twoBack[j - 2] + 2;
        }
        current[j] = value;
        if (value < rowMin) rowMin = value;
      }
      if (rowMin > max) return max + 1;
      twoBack = previous;
      previous = current;
    }
    return previous[b.length];
  }
}
