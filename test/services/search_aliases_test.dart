import 'dart:io';

import 'package:career_path/services/search_aliases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final aliases = SearchAliases({
    'engg': ['engineering'],
    'cs': ['computer science', 'company secretary'],
    'jee': ['engineering entrance'],
    'jee advanced': ['iit engineering'],
    'btech': ['bachelor of technology', 'engineering'],
    'sarkari naukri': ['government jobs'],
  });

  test('adds expansions after the original words', () {
    expect(
      aliases.expand('best engg colleges'),
      'best engg colleges engineering',
    );
    expect(aliases.expand('no aliases here'), 'no aliases here');
  });

  test('matches whole words, ignoring case and dots', () {
    expect(aliases.expand('B.Tech in CS'), contains('bachelor of technology'));
    expect(aliases.expand('B.Tech in CS'), contains('company secretary'));
    // "cs" inside another word is not an alias.
    expect(aliases.expand('physics'), 'physics');
  });

  test('the longest alias wins, and words are not repeated', () {
    // "jee advanced" is one alias; "jee" alone is not expanded inside it.
    expect(aliases.expand('JEE Advanced'), 'JEE Advanced iit engineering');
    expect(aliases.expand('JEE mains'), 'JEE mains engineering entrance');
    expect(aliases.expand('sarkari naukri'), 'sarkari naukri government jobs');
    expect(
      RegExp(r'\bengineering\b').allMatches(aliases.expand('btech engg')),
      hasLength(1),
    );
  });

  test('key words are exposed for spelling correction', () {
    expect(aliases.keyWords, containsAll(['engg', 'sarkari', 'naukri']));
  });

  test('the bundled table is well formed and safe', () {
    final bundled = SearchAliases.parse(
      File(SearchAliases.asset).readAsStringSync(),
    );
    // Everyday words must never expand.
    for (final word in ['it', 'me', 'be', 'see', 'the', 'and', 'march']) {
      expect(bundled.expand(word), word, reason: word);
    }
    // A sample of hand-written and database-derived aliases.
    expect(bundled.expand('engg'), contains('engineering'));
    expect(bundled.expand('mbbs'), contains('medical'));
    expect(bundled.expand('neet'), contains('medical'));
    expect(bundled.expand('vakil'), contains('lawyer'));
    expect(bundled.expand('bhu'), contains('banaras hindu university'));
    expect(bundled.expand('afmc'), contains('armed forces medical college'));
    expect(bundled.expand('colleges in up'), contains('uttar pradesh'));
  });
}
