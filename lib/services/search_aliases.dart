import 'dart:convert';

import 'search_spell_corrector.dart';

/// Hinglish filler words that carry no search meaning. They are skipped when
/// matching, because short ones hide inside names ("hai" in "blockchain").
const searchFillerWords = {
  'aap',
  'acha',
  'accha',
  'achha',
  'achi',
  'acchi',
  'apna',
  'apni',
  'aur',
  'baad',
  'bahut',
  'banana',
  'banaye',
  'bane',
  'banna',
  'banu',
  'batao',
  'bataiye',
  'bataye',
  'bhi',
  'chahiye',
  'chahta',
  'chahti',
  'hai',
  'hain',
  'hi',
  'ho',
  'hota',
  'hote',
  'hoti',
  'hum',
  'humein',
  'ka',
  'kab',
  'kaha',
  'kahan',
  'kaisa',
  'kaise',
  'kar',
  'kare',
  'karein',
  'karen',
  'karna',
  'karo',
  'karoon',
  'karu',
  'kaun',
  'kaunsa',
  'kaunse',
  'kaunsi',
  'ke',
  'ki',
  'kitna',
  'kitne',
  'kitni',
  'ko',
  'konsa',
  'kuch',
  'kya',
  'kyon',
  'kyun',
  'lie',
  'liye',
  'mai',
  'mein',
  'mera',
  'mere',
  'meri',
  'mujhe',
  'par',
  'pe',
  'pehle',
  'sabse',
  'sakta',
  'sakte',
  'sakti',
  'samjhao',
  'samjhaiye',
  'se',
  'tha',
  'thi',
  'toh',
  'wala',
  'wale',
  'wali',
  'ya',
};

/// Expands abbreviations, old names and Hinglish words in a search
/// ("engg" → engineering, "bhu" → banaras hindu university, "vakil" →
/// lawyer) so the records they stand for are found. The student's own words
/// are always kept; expansions are added after them.
///
/// The table is [asset], built by `tooling/build_search_aliases.py` from the
/// hand-written `tooling/search_aliases.txt` and abbreviations found in the
/// database.
class SearchAliases {
  static const asset = 'assets/data/search_aliases.json';

  final Map<String, List<String>> _aliases;
  final int _longestKey;

  SearchAliases(Map<String, List<String>> aliases)
    : _aliases = aliases,
      _longestKey = aliases.keys.fold(
        1,
        (longest, key) =>
            key.split(' ').length > longest ? key.split(' ').length : longest,
      );

  /// Parses [asset]: `{"key": ["expansion", ...]}`.
  factory SearchAliases.parse(String json) => SearchAliases({
    for (final MapEntry(:key, :value)
        in (jsonDecode(json) as Map<String, dynamic>).entries)
      key: [for (final expansion in value as List) expansion as String],
  });

  /// Every word used in a key, so spelling correction leaves them alone.
  Iterable<String> get keyWords =>
      _aliases.keys.expand((key) => key.split(' '));

  /// [query] followed by the expansions of every alias it contains (whole
  /// words, case and dots ignored, so "B.Tech" matches "btech"). The longest
  /// alias wins: "sarkari naukri" expands as a phrase, not as "sarkari".
  String expand(String query) {
    final words = SearchSpellCorrector.words(query).toList();
    final present = words.toSet();
    final extra = <String>[];
    var start = 0;
    while (start < words.length) {
      var matched = 1;
      for (var length = _longestKey; length >= 1; length--) {
        if (start + length > words.length) continue;
        final expansions =
            _aliases[words.sublist(start, start + length).join(' ')];
        if (expansions == null) continue;
        for (final expansion in expansions) {
          for (final word in expansion.split(' ')) {
            if (present.add(word)) extra.add(word);
          }
        }
        matched = length;
        break;
      }
      start += matched;
    }
    return extra.isEmpty ? query : '$query ${extra.join(' ')}';
  }
}
