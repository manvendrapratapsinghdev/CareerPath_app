import 'dart:convert';

import 'search_spell_corrector.dart';

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
  /// words, case and dots ignored, so "B.Tech" matches "btech").
  String expand(String query) {
    final words = SearchSpellCorrector.words(query).toList();
    final present = words.toSet();
    final extra = <String>[];
    for (var start = 0; start < words.length; start++) {
      for (var length = 1; length <= _longestKey; length++) {
        if (start + length > words.length) break;
        final key = words.sublist(start, start + length).join(' ');
        for (final expansion in _aliases[key] ?? const <String>[]) {
          for (final word in expansion.split(' ')) {
            if (present.add(word)) extra.add(word);
          }
        }
      }
    }
    return extra.isEmpty ? query : '$query ${extra.join(' ')}';
  }
}
