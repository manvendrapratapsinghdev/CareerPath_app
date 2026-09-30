/// Study levels of courses, in a fixed small vocabulary.
///
/// The database spells a course's level about 85 ways ("UG", "Under
/// Graduate", "postgraduate_diploma", "integrated undergraduate-postgraduate"),
/// so levels are compared only after [ofCourse] reduces them to these keys.
class CourseLevels {
  const CourseLevels._();

  static const ug = 'ug';
  static const pg = 'pg';
  static const doctoral = 'doctoral';
  static const diploma = 'diploma';
  static const certificate = 'certificate';
  static const integrated = 'integrated';

  static final _separators = RegExp(r'[^a-z]+');

  /// Words of a stored level, each mapped to the levels it names. Several
  /// can apply ("ug/pg", "postgraduate diploma", "integrated undergraduate").
  static const _levelWords = <String, String>{
    'ug': ug,
    'undergraduate': ug,
    'graduate': ug,
    'graduation': ug,
    'pg': pg,
    'postgraduate': pg,
    'postgraduation': pg,
    'speciality': pg,
    'doctoral': doctoral,
    'postdoctoral': doctoral,
    'phd': doctoral,
    'fellowship': doctoral,
    'research': doctoral,
    'diploma': diploma,
    'certificate': certificate,
    'skill': certificate,
    'vocational': certificate,
    'integrated': integrated,
    'dual': integrated,
  };

  /// Words a student uses to ask for a level. "Graduation" is left out: it
  /// means UG in "graduation courses" but PG in "after graduation".
  static const _queryWords = <String, String>{
    'ug': ug,
    'undergraduate': ug,
    'bachelor': ug,
    'bachelors': ug,
    'pg': pg,
    'postgraduate': pg,
    'master': pg,
    'masters': pg,
    'phd': doctoral,
    'doctoral': doctoral,
    'doctorate': doctoral,
    'diploma': diploma,
    'certificate': certificate,
    'integrated': integrated,
  };

  /// The levels a stored level string names; empty when it names none
  /// ("mixed", "bridge course"). "Postgraduate diploma" names both PG and
  /// diploma, so it answers a question about either.
  static Set<String> ofCourse(String level) {
    final words = level
        .toLowerCase()
        .replaceAll('ph.d', 'phd')
        // "Post Graduate", "Under Graduation", "Super Speciality".
        .replaceAllMapped(
          RegExp(r'\b(post|under) (graduat)'),
          (m) => '${m[1]}${m[2]}',
        )
        .split(_separators);
    return {for (final word in words) ?_levelWords[word]};
  }

  /// The levels a student asked for among [tokens] (lowercase words).
  static Set<String> requested(Iterable<String> tokens) => {
    for (final token in tokens) ?_queryWords[token],
  };

  /// Words in [tokens] that only name a level, so they need not match text.
  static bool isLevelWord(String token) => _queryWords.containsKey(token);
}
