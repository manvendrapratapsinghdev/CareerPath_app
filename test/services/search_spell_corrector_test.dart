import 'dart:io';

import 'package:career_path/services/search_spell_corrector.dart';
import 'package:flutter_test/flutter_test.dart';

SearchSpellCorrector _corrector({Set<String> dictionary = const {}}) =>
    SearchSpellCorrector(
      names: [
        'Engineering',
        'Civil Engineering',
        'Mechanical Engineering',
        'Computer Science Engineering',
        'Doctor (MBBS)',
        'Medical Laboratory Technology',
        'Chemistry',
        'Journalism & Mass Communication',
        'Jaipur',
        'Jaipur',
        'Bhopal',
        'Banasthali Vidyapith',
        'Rajasthan',
        'Madhya Pradesh',
        'Uttar Pradesh',
        'Police Services',
        'Hotel Management',
        'Hotel Management',
        'Psychology',
        'Psychology',
        'Psychology',
        'Psychology',
        'Psychology',
        'B.Sc Psycology',
      ],
      otherText: ['Study the best courses to become a doctor.'],
      dictionary: dictionary,
    );

void main() {
  test('snaps misspelled or misheard words to data words', () {
    final c = _corrector();
    expect(c.correctQuery('enginering'), 'engineering');
    expect(c.correctQuery('computr science'), 'computer science');
    expect(c.correctQuery('docter'), 'doctor');
    expect(c.correctQuery('jaipr'), 'jaipur');
    expect(c.correctQuery('banasthli'), 'banasthali');
    expect(c.correctQuery('rajastan'), 'rajasthan');
    expect(c.correctQuery('madya pardesh'), 'madhya pradesh');
    expect(c.correctQuery('jurnalism'), 'journalism');
  });

  test('sound-alike spellings count as small changes', () {
    final c = _corrector();
    // Two plain edits each, but only vowel and c/k changes.
    expect(c.correctQuery('medicle'), 'medical');
    expect(c.correctQuery('jaipore'), 'jaipur');
    expect(c.correctQuery('kemistry'), 'chemistry');
  });

  test('keeps the rest of the query exactly as given', () {
    final c = _corrector();
    expect(
      c.correctQuery('Best Enginering colleges in Jaipur?'),
      'Best engineering colleges in Jaipur?',
    );
    expect(c.correctQuery('12th ke baad kya karu'), '12th ke baad kya karu');
    expect(c.correctQuery('इंजीनियरिंग enginering'), 'इंजीनियरिंग engineering');
  });

  test('never corrects real words, short words or numbers', () {
    final c = _corrector(dictionary: {'mother', 'place', 'hostel', 'money'});
    // "mother"→"other"-style mistakes are blocked by the dictionary.
    for (final word in ['mother', 'place', 'hostel', 'money']) {
      expect(c.correct(word), word);
    }
    // Data words, words from descriptions and common query words.
    for (final word in ['engineering', 'courses', 'best', 'fees', 'kaise']) {
      expect(c.correct(word), word);
    }
    // Inflections of known words.
    for (final word in ['colleges', 'doctors', 'studies', 'studying']) {
      expect(c.isWord(word) || c.correct(word) == word, isTrue, reason: word);
    }
    // Too short to correct safely, or contains digits.
    expect(c.correct('law'), 'law');
    expect(c.correct('jpr'), 'jpr');
    expect(c.correct('12th'), '12th');
  });

  test('short words only change when the first letter matches', () {
    final c = _corrector();
    // Under 6 letters a changed first letter is usually another word.
    expect(c.correct('hotl'), 'hotel');
    expect(c.correct('botel'), 'botel');
    // Longer words may change it ("kemistry" → "chemistry").
    expect(c.correct('bolice'), 'police');
  });

  test('a word the data misspells once also searches the common spelling', () {
    final c = _corrector();
    expect(c.correctQuery('psycology'), 'psycology psychology');
    expect(c.correctQuery('psychology'), 'psychology');
  });

  test('distance counts edits in half units with sound-alike discounts', () {
    int d(String a, String b) => SearchSpellCorrector.distance(a, b, 10);
    expect(d('jaipur', 'jaipur'), 0);
    expect(d('jaipr', 'jaipur'), 1); // dropped vowel
    expect(d('docter', 'doctor'), 1); // vowel swap
    expect(d('kemistry', 'chemistry'), 3); // c/k + dropped h
    expect(d('desgin', 'design'), 2); // neighbours swapped
    expect(d('bhopl', 'bhxpal'), greaterThan(2));
    expect(SearchSpellCorrector.distance('engineering', 'eng', 2), 3);
  });

  test('the bundled dictionary protects everyday words', () {
    final file = File(SearchSpellCorrector.dictionaryAsset);
    final dictionary = SearchSpellCorrector.parseDictionary(
      file.readAsStringSync(),
    );
    expect(dictionary.length, greaterThan(100000));
    final c = _corrector(dictionary: dictionary);
    for (final word in ['mother', 'place', 'hotel', 'money', 'police']) {
      expect(c.correct(word), word, reason: word);
    }
    // "hostel" must stay a hostel, not become "hotel".
    expect(c.correctQuery('hostel fees'), 'hostel fees');
    // Misspellings are not in the dictionary, so they are still fixed.
    expect(c.correctQuery('enginering'), 'engineering');
    expect(c.correctQuery('jaipr'), 'jaipur');
  });
}
