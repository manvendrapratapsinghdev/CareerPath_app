import '../models/institute_catalog.dart';
import 'course_levels.dart';
import 'search_aliases.dart';

/// One institute found by [InstituteCatalogService.find], with the courses
/// that matched the question.
typedef InstituteMatch = ({
  InstituteRecord record,
  List<InstituteCourse> courses,
});

/// Best [InstituteMatch]es plus how many institutes and courses matched.
typedef InstituteMatches = ({
  List<InstituteMatch> hits,
  int totalInstitutes,
  int totalCourses,
});

/// Institutes with their courses and NIRF rankings, loaded once from the
/// bundled database and searched in memory.
class InstituteCatalogService {
  static const _rankingWords = {'nirf', 'rank', 'ranks', 'ranking', 'rankings'};
  static const _stopWords = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'of',
    'in',
    'on',
    'for',
    'to',
    'at',
    'is',
    'are',
    'what',
    'which',
    'where',
    'who',
    'how',
    'me',
    'show',
    'tell',
    'list',
    'about',
    'does',
    'do',
    'offer',
    'offers',
    'available',
    'top',
    'best',
    'college',
    'colleges',
    'institute',
    'institutes',
    'university',
    'course',
    'courses',
    'india',
  };
  static const _rankingCategories = {
    'overall',
    'engineering',
    'management',
    'pharmacy',
    'university',
    'college',
    'medical',
    'law',
    'architecture',
    'research',
    'dental',
    'agriculture',
    'innovation',
  };

  /// Indian states/UTs as they appear in the bundled records, keyed by their
  /// normalised (lowercase, no spaces) form so both the full name and common
  /// abbreviations resolve to the same value.
  static const _stateAliases = <String, String>{
    'andhrapradesh': 'andhra pradesh',
    'ap': 'andhra pradesh',
    'arunachalpradesh': 'arunachal pradesh',
    'assam': 'assam',
    'bihar': 'bihar',
    'chhattisgarh': 'chhattisgarh',
    'cg': 'chhattisgarh',
    'goa': 'goa',
    'gujarat': 'gujarat',
    'haryana': 'haryana',
    'himachalpradesh': 'himachal pradesh',
    'hp': 'himachal pradesh',
    'jharkhand': 'jharkhand',
    'karnataka': 'karnataka',
    'kerala': 'kerala',
    'madhyapradesh': 'madhya pradesh',
    'mp': 'madhya pradesh',
    'maharashtra': 'maharashtra',
    'manipur': 'manipur',
    'meghalaya': 'meghalaya',
    'mizoram': 'mizoram',
    'nagaland': 'nagaland',
    'odisha': 'odisha',
    'orissa': 'odisha',
    'punjab': 'punjab',
    'rajasthan': 'rajasthan',
    'sikkim': 'sikkim',
    'tamilnadu': 'tamil nadu',
    'tn': 'tamil nadu',
    'telangana': 'telangana',
    'ts': 'telangana',
    'tripura': 'tripura',
    'uttarpradesh': 'uttar pradesh',
    'up': 'uttar pradesh',
    'uttarakhand': 'uttarakhand',
    'uk': 'uttarakhand',
    'ua': 'uttarakhand',
    'westbengal': 'west bengal',
    'wb': 'west bengal',
    'delhi': 'delhi',
    'newdelhi': 'delhi',
    'ncr': 'delhi',
    'jammuandkashmir': 'jammu and kashmir',
    'jammukashmir': 'jammu and kashmir',
    'jk': 'jammu and kashmir',
    'ladakh': 'ladakh',
    'puducherry': 'puducherry',
    'pondicherry': 'puducherry',
    'chandigarh': 'chandigarh',
  };

  final Future<List<Map<String, dynamic>>> Function() _loader;
  List<InstituteRecord>? _records;
  Future<void>? _loading;

  InstituteCatalogService(this._loader);

  InstituteCatalogService.withRecords(List<InstituteRecord> records)
    : _loader = (() async => const []),
      _records = records;

  List<InstituteRecord> get records => _records ?? const [];

  /// Distinct source-defined institutional groups currently available.
  /// Values are read from the database; the app does not own a fixed list.
  List<String> get institutionTypes {
    final values =
        records
            .map((record) => record.institute.institutionType?.trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return List.unmodifiable(values);
  }

  /// Records belonging to the source-defined [institutionType].
  List<InstituteRecord> byInstitutionType(String institutionType) {
    final requested = institutionType.trim().toLowerCase();
    if (requested.isEmpty) return const [];
    return records
        .where(
          (record) =>
              record.institute.institutionType?.trim().toLowerCase() ==
              requested,
        )
        .toList(growable: false);
  }

  Future<void> ensureLoaded() {
    if (_records != null) return Future.value();
    return _loading ??= _loader()
        .then((rows) {
          _records = rows.map(InstituteRecord.fromJson).toList(growable: false);
          _places = null;
        })
        .whenComplete(() => _loading = null);
  }

  /// Two-token state names (e.g. "uttar" + "pradesh") that a single-token
  /// alias can't cover, since query tokens lose word order.
  static const _multiWordStates = <(String, String, String)>[
    ('andhra', 'pradesh', 'andhra pradesh'),
    ('arunachal', 'pradesh', 'arunachal pradesh'),
    ('himachal', 'pradesh', 'himachal pradesh'),
    ('madhya', 'pradesh', 'madhya pradesh'),
    ('uttar', 'pradesh', 'uttar pradesh'),
    ('west', 'bengal', 'west bengal'),
    ('tamil', 'nadu', 'tamil nadu'),
    ('jammu', 'kashmir', 'jammu and kashmir'),
  ];

  static bool asksForRankings(String query) =>
      _tokens(query).any(_rankingWords.contains);

  /// The state named in [tokens], if any, in its canonical form.
  static String? _requestedState(Set<String> tokens) {
    for (final entry in _stateAliases.entries) {
      if (tokens.contains(entry.key)) return entry.value;
    }
    for (final (first, second, state) in _multiWordStates) {
      if (tokens.contains(first) && tokens.contains(second)) return state;
    }
    return null;
  }

  static String _normalizedState(String? state) {
    final lower = (state ?? '').toLowerCase().trim();
    final compact = lower.replaceAll(RegExp(r'[^a-z]'), '');
    return _stateAliases[compact] ?? lower;
  }

  /// Institutes whose name, location or course names match [query]. When the
  /// question names a state, city or district, only institutes actually
  /// there are considered — otherwise a loosely-matching college from
  /// elsewhere ("medical college" in Lucknow for "MBBS in Bhopal") can still
  /// hit the score threshold below and crowd out real results.
  List<InstituteRecord> search(String query, {int limit = 5}) => find(
    query,
    limit: limit,
  ).hits.map((hit) => hit.record).toList(growable: false);

  /// Like [search], with the courses that matched each institute and how
  /// many institutes and courses matched in all (before [limit]).
  ///
  /// A level named in the query ("PG", "diploma", "PhD") keeps only
  /// institutes with a course at that level, and only those courses count.
  /// Every course is searched, not just the ones shown in [describe].
  InstituteMatches find(String query, {int limit = 5}) {
    final tokens = _tokens(
      query,
    ).difference(_stopWords).difference(searchFillerWords);
    if (tokens.isEmpty) {
      return (hits: const [], totalInstitutes: 0, totalCourses: 0);
    }
    final requestedState = _requestedState(tokens);
    final requestedPlaces = _requestedPlaces(tokens);
    final levels = CourseLevels.requested(tokens);
    final words = tokens.where((t) => !CourseLevels.isLevelWord(t)).toSet();
    final scored = <(InstituteMatch, int, bool)>[];
    for (final record in records) {
      final (:name, :place, :state) = _searchText(record);
      if (requestedState != null &&
          state != requestedState &&
          // Some records have a city but no state; a city that carries the
          // state's name (New Delhi, Chandigarh, Goa) still places them.
          (state.isNotEmpty || !place.contains(' $requestedState'))) {
        continue;
      }
      if (requestedPlaces.isNotEmpty && !requestedPlaces.any(place.contains)) {
        continue;
      }
      final atLevel = levels.isEmpty
          ? record.courses
          : record.courses
                .where(
                  (c) => CourseLevels.ofCourse(c.level).any(levels.contains),
                )
                .toList(growable: false);
      if (levels.isNotEmpty && atLevel.isEmpty) continue;
      final matched = <InstituteCourse>[];
      // A requested state that matched already confirms relevance, even when
      // the query used an abbreviation ("UP") that never appears in the
      // stored place text.
      var score = requestedState != null ? 6 : 0;
      var allWordsFound = words.isNotEmpty;
      var subjectFound = false;
      for (final token in words) {
        final hits = atLevel.where((c) => _hasWord(_courseText(c), token));
        for (final course in hits) {
          if (!matched.contains(course)) matched.add(course);
        }
        if (_hasWord(name, token)) {
          score += 10;
          // "Delhi" in "Delhi School of Economics" is the place, not a
          // subject such as "engineering".
          if (!_hasWord(place, token)) subjectFound = true;
        } else if (_hasWord(place, token)) {
          score += 6;
        } else if (hits.isNotEmpty) {
          score += 2;
          subjectFound = true;
        } else {
          allWordsFound = false;
        }
      }
      // Every word found, some only in a course ("B.Pharm colleges"): the
      // institute offers what was asked for.
      if (allWordsFound && matched.isNotEmpty) score += 4;
      if (score < 6) continue;
      final courses = matched.isNotEmpty
          ? matched
          : levels.isNotEmpty
          ? atLevel
          : const <InstituteCourse>[];
      scored.add(((record: record, courses: courses), score, subjectFound));
    }
    // With a place named, every college there scores; once some also match
    // the subject ("engineering colleges in Maharashtra"), the rest go.
    if (scored.any((entry) => entry.$3)) {
      scored.removeWhere((entry) => !entry.$3);
    }
    scored.sort((a, b) {
      final order = b.$2.compareTo(a.$2);
      return order != 0
          ? order
          : a.$1.record.institute.name.compareTo(b.$1.record.institute.name);
    });
    return (
      hits: scored.take(limit).map((entry) => entry.$1).toList(growable: false),
      totalInstitutes: scored.length,
      totalCourses: scored.fold(
        0,
        (sum, entry) => sum + entry.$1.courses.length,
      ),
    );
  }

  /// Ranked institutes, best first, optionally for one category such as
  /// "Engineering"; names in [query] narrow the list.
  List<(InstituteRecord, InstituteRanking)> rankings(
    String query, {
    int limit = 8,
  }) {
    final tokens = _tokens(query);
    final categories = tokens.intersection(_rankingCategories);
    final nameTokens = tokens
        .difference(_stopWords)
        .difference(searchFillerWords)
        .difference(_rankingWords)
        .difference(_rankingCategories);
    final pairs = <(InstituteRecord, InstituteRanking)>[
      for (final record in records)
        for (final ranking in record.rankings)
          if (categories.isEmpty ||
              categories.contains(ranking.category.toLowerCase()))
            (record, ranking),
    ];
    final named = pairs
        .where(
          (pair) => nameTokens.any(
            (token) => _hasWord(_searchText(pair.$1).name, token),
          ),
        )
        .toList();
    final selected = named.isNotEmpty ? named : pairs;
    selected.sort((a, b) => a.$2.sortKey.compareTo(b.$2.sortKey));
    return selected.take(limit).toList();
  }

  /// Grounding text for one institute. [matched] courses (from [find]) are
  /// listed first, so the course the student asked about is always shown.
  static String describe(
    InstituteRecord record, {
    List<InstituteCourse> matched = const [],
  }) {
    final others = [
      for (final course in record.courses)
        if (!matched.contains(course)) course,
    ];
    final institute = record.institute;
    final lines = <String>[
      'Title: ${institute.name}',
      if (institute.location != null) 'Location: ${institute.location}',
      if (institute.website?.isNotEmpty == true)
        'Website: ${institute.website}',
      if (institute.description?.trim().isNotEmpty == true)
        'Description: ${_clip(institute.description!.trim(), 400)}',
      if (institute.institutionType?.trim().isNotEmpty == true)
        'Institution type: ${institute.institutionType!.trim()}',
      if (record.categories.isNotEmpty)
        'Categories: ${record.categories.join(', ')}',
      if (matched.isNotEmpty)
        'Matching courses (${matched.length}): '
            '${matched.take(10).map(_courseLabel).join('; ')}'
            '${matched.length > 10 ? ' (+${matched.length - 10} more)' : ''}',
      if (matched.isNotEmpty && others.isNotEmpty)
        'Other courses: ${others.length}'
      else if (others.isNotEmpty)
        'Courses: ${others.take(10).map(_courseLabel).join('; ')}'
            '${others.length > 10 ? ' (+${others.length - 10} more)' : ''}',
      if (record.rankings.isNotEmpty)
        'Rankings: ${record.rankings.map((r) => '${r.label}: ${r.rankLabel}${r.score == null ? '' : ' (score ${r.score})'}').join('; ')}',
    ];
    return lines.join('\n');
  }

  static String _courseLabel(InstituteCourse course) {
    final details = [
      if (course.level.isNotEmpty) course.level,
      if (course.duration?.isNotEmpty == true) course.duration!,
      if (course.eligibility?.isNotEmpty == true)
        'eligibility: ${_clip(course.eligibility!, 80)}',
    ];
    return details.isEmpty
        ? course.name
        : '${course.name} (${details.join(', ')})';
  }

  static Set<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9.]+'))
      .map((token) => token.replaceAll('.', ''))
      .where((token) => token.length >= 2)
      .toSet();

  /// Cities and districts in the records (as `' word word'` haystack text),
  /// built once; placeholders such as "Various" are not places.
  List<(Set<String>, String)>? _places;

  List<(Set<String>, String)> get _knownPlaces => _places ??= () {
    final seen = <String>{};
    return [
      for (final record in records)
        for (final value in [record.institute.city, record.institute.district])
          if (value != null)
            if (_haystack(value).trim() case final place
                when place.isNotEmpty &&
                    !_notPlaces.contains(place) &&
                    seen.add(place))
              (place.split(' ').toSet(), ' $place'),
    ];
  }();

  static const _notPlaces = {'various', 'online', 'multiple', 'pan india'};

  /// Haystack text of every known city or district all of whose words are in
  /// [tokens].
  List<String> _requestedPlaces(Set<String> tokens) => [
    for (final (words, place) in _knownPlaces)
      if (tokens.containsAll(words)) place,
  ];

  /// Searchable text of one record, built once (the records never change):
  /// see [_haystack].
  static final _texts = Expando<({String name, String place, String state})>();

  static ({String name, String place, String state}) _searchText(
    InstituteRecord record,
  ) => _texts[record] ??= () {
    final institute = record.institute;
    return (
      name: _haystack(institute.name),
      place: _haystack(
        '${institute.city ?? ''} ${institute.district ?? ''} '
        '${institute.state ?? ''} ${institute.institutionType ?? ''}',
      ),
      state: _normalizedState(institute.state),
    );
  }();

  static final _courseTexts = Expando<String>();

  /// Searchable name and specialization of one course, built once.
  static String _courseText(InstituteCourse course) => _courseTexts[course] ??=
      _haystack('${course.name} ${course.specialization ?? ''}');

  static final _nonWord = RegExp('[^a-z0-9]+');

  /// Lowercase, dots dropped, every other non-alphanumeric run turned into
  /// one space and a leading space added — so "a word of [haystack] starts
  /// with [token]" is a plain `contains(' token')`.
  static String _haystack(String text) =>
      ' ${text.toLowerCase().replaceAll('.', '').replaceAll(_nonWord, ' ')}';

  /// Some word of [haystack] (from [_haystack]) starts with [token].
  static bool _hasWord(String haystack, String token) =>
      haystack.contains(' $token');

  static String _clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
