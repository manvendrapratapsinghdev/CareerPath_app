import '../models/institute_catalog.dart';

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

  final Future<List<Map<String, dynamic>>> Function() _loader;
  List<InstituteRecord>? _records;
  Future<void>? _loading;

  InstituteCatalogService(this._loader);

  InstituteCatalogService.withRecords(List<InstituteRecord> records)
    : _loader = (() async => const []),
      _records = records;

  List<InstituteRecord> get records => _records ?? const [];

  Future<void> ensureLoaded() {
    if (_records != null) return Future.value();
    return _loading ??= _loader()
        .then((rows) {
          _records = rows.map(InstituteRecord.fromJson).toList(growable: false);
        })
        .whenComplete(() => _loading = null);
  }

  static bool asksForRankings(String query) =>
      _tokens(query).any(_rankingWords.contains);

  /// Institutes whose name, location or course names match [query].
  List<InstituteRecord> search(String query, {int limit = 5}) {
    final tokens = _tokens(query).difference(_stopWords);
    if (tokens.isEmpty) return const [];
    final scored = <(InstituteRecord, int)>[];
    for (final record in records) {
      final institute = record.institute;
      final name = institute.name.toLowerCase();
      final place =
          '${institute.city ?? ''} ${institute.district ?? ''} '
                  '${institute.state ?? ''}'
              .toLowerCase();
      final courses = record.courses
          .map((c) => '${c.name} ${c.specialization ?? ''}')
          .join(' ')
          .toLowerCase();
      var score = 0;
      for (final token in tokens) {
        if (_hasWord(name, token)) {
          score += 10;
        } else if (_hasWord(place, token)) {
          score += 6;
        } else if (_hasWord(courses, token)) {
          score += 2;
        }
      }
      if (score >= 6) scored.add((record, score));
    }
    scored.sort((a, b) {
      final order = b.$2.compareTo(a.$2);
      return order != 0
          ? order
          : a.$1.institute.name.compareTo(b.$1.institute.name);
    });
    return scored.take(limit).map((entry) => entry.$1).toList();
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
            (token) => _hasWord(pair.$1.institute.name.toLowerCase(), token),
          ),
        )
        .toList();
    final selected = named.isNotEmpty ? named : pairs;
    selected.sort((a, b) => a.$2.sortKey.compareTo(b.$2.sortKey));
    return selected.take(limit).toList();
  }

  /// Grounding text for one institute.
  static String describe(InstituteRecord record) {
    final institute = record.institute;
    final lines = <String>[
      'Title: ${institute.name}',
      if (institute.location != null) 'Location: ${institute.location}',
      if (institute.website?.isNotEmpty == true)
        'Website: ${institute.website}',
      if (institute.description?.trim().isNotEmpty == true)
        'Description: ${_clip(institute.description!.trim(), 400)}',
      if (record.categories.isNotEmpty)
        'Categories: ${record.categories.join(', ')}',
      if (record.courses.isNotEmpty)
        'Courses: ${record.courses.take(10).map(_courseLabel).join('; ')}'
            '${record.courses.length > 10 ? ' (+${record.courses.length - 10} more)' : ''}',
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

  static bool _hasWord(String haystack, String token) => RegExp(
    '(^|[^a-z0-9])${RegExp.escape(token)}',
  ).hasMatch(haystack.replaceAll('.', ''));

  static String _clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
