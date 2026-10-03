import '../data/local_database.dart';
import '../models/domain_tier.dart';
import '../models/institute_catalog.dart';
import '../models/institute_campus.dart';
import '../models/institute_classification.dart';
import '../models/institute_accreditation.dart';
import '../models/institute_location_filter.dart';
import '../models/domain.dart';
import '../models/institution_family.dart';
import '../models/institution_group.dart';
import 'course_levels.dart';
import 'location_service.dart';
import 'search_aliases.dart';

/// One institute found by [InstituteCatalogService.find], with the courses
/// that matched the question.
typedef InstituteMatch = ({
  InstituteRecord record,
  List<InstituteCourse> courses,
});

/// Best [InstituteMatch]es plus how many institutes and courses matched.
/// [place] is the state, city or district the question named, if any, and
/// [inPlace] how many institutes are there before any subject or level
/// filter; [levels] are the course levels asked for.
typedef InstituteMatches = ({
  List<InstituteMatch> hits,
  int totalInstitutes,
  int totalCourses,
  String? place,
  int inPlace,
  Set<String> levels,
});

/// The UGC line on an institute card (plan §8.6): only private rows are
/// checked; government rows show no badge.
enum UgcBadge { verified, notVerified, pending, notApplicable }

/// NIRF highlight on an institute card (plan §8.6).
enum RankHighlight { none, top100, top10 }

/// One institute as the ladder, filter and card views show it.
class InstituteListing {
  final int instituteId;
  final String name;
  final String? city;
  final String? district;
  final String? state;
  final List<InstituteCampus> campuses;

  /// Null only for an institute that is not classified yet.
  final InstituteClassification? classification;
  final String? groupName;
  final String? familyName;

  /// Tier on the domain ladder asked for, if any.
  final int? tier;

  /// The rank to show (domain category first, then Overall …); null =
  /// "Not ranked" unless [naacGrade] is set.
  final InstituteRanking? ranking;
  final RankHighlight highlight;

  /// Institution-level NAAC grade, the fallback when there is no NIRF rank.
  final String? naacGrade;
  final List<InstituteAccreditation> accreditations;
  final UgcBadge ugcBadge;

  const InstituteListing({
    required this.instituteId,
    required this.name,
    this.city,
    this.district,
    this.state,
    this.campuses = const [],
    this.classification,
    this.groupName,
    this.familyName,
    this.tier,
    this.ranking,
    this.highlight = RankHighlight.none,
    this.naacGrade,
    this.accreditations = const [],
    this.ugcBadge = UgcBadge.notApplicable,
  });

  @override
  String toString() => 'InstituteListing($instituteId, $name)';
}

/// One tier of a domain's college ladder with its institutes, best first.
/// [institutes] may be empty: the UI says so plainly.
typedef LadderTier = ({DomainTier tier, List<InstituteListing> institutes});

/// The combined institute filter (plan §6.4, §9). Null / empty fields mean
/// "any". [tier] needs [domainSlug]. [ugcVerifiedOnly] drops private rows
/// that are not UGC verified and keeps government rows (§8.6).
class InstituteFilter {
  final String? domainSlug;
  final int? tier;
  final String? groupCode;
  final String? familySlug;

  /// `institute_classification.ownership` values (private, state_govt …).
  final Set<String> ownerships;

  /// A state or city from [LocationService.resolve].
  final ResolvedPlace? place;

  /// Saved India → state → district → city selection for catalog screens.
  final InstituteLocationFilter? locationFilter;
  final bool ugcVerifiedOnly;
  final bool admitsStudentsOnly;

  const InstituteFilter({
    this.domainSlug,
    this.tier,
    this.groupCode,
    this.familySlug,
    this.ownerships = const {},
    this.place,
    this.locationFilter,
    this.ugcVerifiedOnly = false,
    this.admitsStudentsOnly = false,
  });
}

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

  /// Source of the taxonomy (groups, families, tiers, rankings). Without
  /// it the ladder, filter and display APIs return empty / null.
  final LocalDatabase? _taxonomy;
  final LocationService? _locations;

  InstituteCatalogService(
    this._loader, {
    LocalDatabase? taxonomy,
    LocationService? locations,
  }) : _taxonomy = taxonomy,
       _locations = locations;

  InstituteCatalogService.withRecords(
    List<InstituteRecord> records, {
    LocalDatabase? taxonomy,
    LocationService? locations,
  }) : _loader = (() async => const []),
       _records = records,
       _taxonomy = taxonomy,
       _locations = locations;

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
          _covered = null;
          _byId = null;
        })
        .whenComplete(() => _loading = null);
  }

  /// Loads the shared location index used by typed chat, voice and filters.
  Future<void> ensureLocationsLoaded() async {
    await _locations?.ensureLoaded();
  }

  String? resolvePlaceLabel(String query) =>
      _locations?.resolveLoaded(query)?.label;

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

  /// Whether the student supplied a filter that should widen the default
  /// top-only result. Broad requests such as "engineering colleges" stay on
  /// the first result; a named place, level, course or institute name is an
  /// intentional narrowing and may show the fuller ranked list.
  bool hasSpecificSearchFilter(String query) {
    final tokens = _tokens(
      query,
    ).difference(_stopWords).difference(searchFillerWords);
    if (tokens.isEmpty) return false;
    if (_locations?.resolveLoaded(query) != null ||
        _requestedState(tokens) != null ||
        _requestedPlaces(tokens).isNotEmpty ||
        CourseLevels.requested(tokens).isNotEmpty) {
      return true;
    }

    // Keep generic subject/category words broad. An exact institute/family
    // word such as "IIT" or "AIIMS" is a meaningful name filter.
    const generic = {
      ..._rankingWords,
      ..._rankingCategories,
      'best',
      'course',
      'courses',
      'institute',
      'institutes',
      'india',
      'top',
    };
    final nameTokens = tokens.difference(generic);
    return nameTokens.any(
      (token) =>
          records.any((record) => _hasWord(_searchText(record).name, token)),
    );
  }

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
      return (
        hits: const [],
        totalInstitutes: 0,
        totalCourses: 0,
        place: null,
        inPlace: 0,
        levels: const {},
      );
    }
    final requestedState = _requestedState(tokens);
    final requestedPlaces = _requestedPlaces(tokens);
    final resolvedPlace = _locations?.resolveLoaded(query);
    final levels = CourseLevels.requested(tokens);
    final words = tokens.where((t) => !CourseLevels.isLevelWord(t)).toSet();
    final scored = <(InstituteMatch, int, bool)>[];
    var inPlace = 0;
    for (final record in records) {
      final matchesPlace = resolvedPlace == null
          ? _isIn(record, requestedState, requestedPlaces)
          : _locations!.matchesRecord(resolvedPlace, record);
      if (!matchesPlace) continue;
      final (:name, :place, state: _) = _searchText(record);
      inPlace++;
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
      if (order != 0) return order;
      final rankOrder = _recordRankKey(
        a.$1.record,
      ).compareTo(_recordRankKey(b.$1.record));
      return rankOrder != 0
          ? rankOrder
          : a.$1.record.institute.name.compareTo(b.$1.record.institute.name);
    });
    return (
      hits: scored.take(limit).map((entry) => entry.$1).toList(growable: false),
      totalInstitutes: scored.length,
      totalCourses: scored.fold(
        0,
        (sum, entry) => sum + entry.$1.courses.length,
      ),
      place: resolvedPlace != null
          ? resolvedPlace.label
          : requestedPlaces.isNotEmpty
          ? requestedPlaces.first.trim()
          : requestedState,
      inPlace:
          resolvedPlace != null ||
              requestedState != null ||
              requestedPlaces.isNotEmpty
          ? inPlace
          : 0,
      levels: levels,
    );
  }

  /// Ids of the institutes in the state, city or district [query] names;
  /// null when it names none (then every institute may match).
  Set<int>? idsInPlace(String query) {
    final tokens = _tokens(
      query,
    ).difference(_stopWords).difference(searchFillerWords);
    final requestedState = _requestedState(tokens);
    final requestedPlaces = _requestedPlaces(tokens);
    if (requestedState == null && requestedPlaces.isEmpty) return null;
    return {
      for (final record in records)
        if (_isIn(record, requestedState, requestedPlaces)) record.institute.id,
    };
  }

  /// [record] is in the requested state (if any) and one of the requested
  /// cities or districts (if any).
  static bool _isIn(
    InstituteRecord record,
    String? requestedState,
    List<String> requestedPlaces,
  ) {
    final (:place, :state, name: _) = _searchText(record);
    if (requestedState != null &&
        state != requestedState &&
        // Some records have a city but no state; a city that carries the
        // state's name (New Delhi, Chandigarh, Goa) still places them.
        (state.isNotEmpty || !place.contains(' $requestedState'))) {
      return false;
    }
    return requestedPlaces.isEmpty || requestedPlaces.any(place.contains);
  }

  /// States with institutes, most first, as "Rajasthan (123)"; computed
  /// from the records, so it follows the data.
  List<String> get coveredStates => _covered ??= () {
    final counts = <String, int>{};
    for (final record in records) {
      final states = _locations?.hasCampusScopedLocationData == true
          ? record.campuses.map((campus) => campus.stateName.trim()).toSet()
          : {record.institute.state?.trim() ?? ''};
      for (final state in states) {
        if (state.isNotEmpty) counts[state] = (counts[state] ?? 0) + 1;
      }
    }
    final states = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final state in states) '$state (${counts[state]})'];
  }();
  List<String>? _covered;

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

  // ── Taxonomy: ladder, filter and card info (plan §9, §8.6) ─────────────

  Map<int, InstituteRecord>? _byId;
  Future<_Taxonomy>? _taxonomyCache;

  Map<int, InstituteRecord> get _recordsById =>
      _byId ??= {for (final record in records) record.institute.id: record};

  /// [domainSlug]'s college ladder, tier 1 first, each tier's institutes
  /// sorted NIRF rank → band → NAAC grade → name. Family summary rows,
  /// unlisted rows and campuses/departments of another institute are left
  /// out. Tiers with no institute are kept (empty list).
  Future<List<LadderTier>> ladderFor(
    String domainSlug, {
    InstituteLocationFilter? locationFilter,
    bool ugcVerifiedOnly = false,
    String? groupCode,
    String? familySlug,
  }) async {
    final db = _taxonomy;
    if (db == null) return const [];
    final tiers = await db.getDomainTiers(domainSlug);
    if (tiers.isEmpty) return const [];
    final listings = await filter(
      InstituteFilter(
        domainSlug: domainSlug,
        locationFilter: locationFilter,
        ugcVerifiedOnly: ugcVerifiedOnly,
        groupCode: groupCode,
        familySlug: familySlug,
      ),
    );
    return [
      for (final tier in tiers)
        (
          tier: tier,
          institutes: listings
              .where((listing) => listing.tier == tier.tier)
              .toList(growable: false),
        ),
    ];
  }

  /// Listed top-level institutes matching every field of [filter]. With a
  /// domain they come by tier, then best rank; otherwise best rank first.
  Future<List<InstituteListing>> filter(InstituteFilter filter) async {
    final db = _taxonomy;
    if (db == null) return const [];
    await ensureLoaded();
    final taxonomy = await _loadTaxonomy(db);
    final domain = filter.domainSlug;
    final Map<int, int?> candidates = domain == null
        ? {for (final id in taxonomy.listed.keys) id: null}
        : {
            for (final row in await db.getInstitutesOnDomainLadder(
              domain,
              tier: filter.tier,
            ))
              row.instituteId: row.tier,
          };
    final listings = <InstituteListing>[];
    for (final MapEntry(key: id, value: tier) in candidates.entries) {
      final classification = taxonomy.listed[id];
      final record = _recordsById[id];
      if (classification == null || record == null) continue;
      if (!_passes(filter, classification, record)) continue;
      listings.add(_listing(taxonomy, record, classification, domain, tier));
    }
    listings.sort(_compareListings);
    return listings;
  }

  /// Database-defined domain list for catalog navigation.
  Future<List<Domain>> getDomains() async {
    final db = _taxonomy;
    return db == null ? const [] : db.getDomains();
  }

  Future<List<InstitutionFamily>> getFamilies({String? groupCode}) async {
    final db = _taxonomy;
    return db == null ? const [] : db.getFamilies(groupCode: groupCode);
  }

  Future<List<InstitutionGroup>> getInstitutionGroups() async {
    final db = _taxonomy;
    return db == null ? const [] : db.getInstitutionGroups();
  }

  InstituteRecord? recordById(int instituteId) => _recordsById[instituteId];

  /// Matches a student's college/ranking question to a known domain and
  /// returns the already ranked ladder results, narrowed with the same place
  /// resolver used by the UI. Null means this was not a domain ladder query.
  Future<List<InstituteListing>?> ladderSearch(
    String query, {
    int limit = 8,
    bool verifiedOnly = false,
  }) async {
    final db = _taxonomy;
    if (db == null) return null;
    await ensureLoaded();
    await ensureLocationsLoaded();
    final domains = await db.getDomains();
    final compactQuery = LocationService.compact(query);
    final words = RegExp(
      r'[a-z0-9]+',
    ).allMatches(query.toLowerCase()).map((match) => match.group(0)!).toSet();
    final candidates = <(Domain, int)>[];
    const domainAliases = <String, Set<String>>{
      'engineering': {'engg', 'btech', 'iit', 'jee'},
      'medical': {'mbbs', 'doctor', 'doctors', 'aiims', 'neet'},
      'management': {'mba', 'iim', 'cat'},
      'law': {'llb', 'nlu', 'clat', 'lawyer'},
      'ca_cma_cs': {'ca', 'cma', 'cs', 'icai', 'icsi', 'icmai'},
      'pharmacy': {'pharmacy', 'bpharm', 'dpharm'},
      'architecture': {'architecture', 'nata', 'architect'},
      'agriculture': {'agriculture', 'agri', 'icar'},
    };
    for (final domain in domains) {
      final terms = domain.name
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((term) => term.length > 1 && term != 'and')
          .toSet();
      final compactName = LocationService.compact(domain.name);
      final slugTerms = domain.slug.split('_').where((term) => term.length > 1);
      final nameMatched =
          compactName.isNotEmpty && compactQuery.contains(compactName);
      final wordsMatched = terms.isNotEmpty && terms.every(words.contains);
      final slugMatched =
          slugTerms.isNotEmpty && slugTerms.every(words.contains);
      final aliasMatched = (domainAliases[domain.slug] ?? const <String>{})
          .intersection(words)
          .isNotEmpty;
      if (nameMatched || wordsMatched || slugMatched || aliasMatched) {
        candidates.add((
          domain,
          nameMatched ? 100 + terms.length : (aliasMatched ? 20 : terms.length),
        ));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    final domain = candidates.first.$1;
    final queryWords = words;
    final asksForCatalog = queryWords.any(
      const {
        'college',
        'colleges',
        'university',
        'universities',
        'institute',
        'institutes',
        'rank',
        'rankings',
        'ranking',
        'nirf',
        'top',
        'best',
      }.contains,
    );
    if (!asksForCatalog || !domain.hasCollegeLadder) return null;
    final place = _locations?.resolveLoaded(query);
    final listings = await filter(
      InstituteFilter(
        domainSlug: domain.slug,
        place: place,
        ugcVerifiedOnly: verifiedOnly,
      ),
    );
    return listings.take(limit).toList(growable: false);
  }

  /// Card info for one institute: group and family names, display ranking
  /// for [domainSlug] (with its top-10 / top-100 highlight), tier on that
  /// ladder, NAAC fallback and UGC badge. Null for an unknown institute.
  Future<InstituteListing?> displayInfo(
    int instituteId, {
    String? domainSlug,
  }) async {
    final db = _taxonomy;
    if (db == null) return null;
    await ensureLoaded();
    final record = _recordsById[instituteId];
    if (record == null) return null;
    final taxonomy = await _loadTaxonomy(db);
    final classification =
        taxonomy.listed[instituteId] ??
        await db.getInstituteClassification(instituteId);
    int? tier;
    if (domainSlug != null) {
      for (final row in await db.getInstituteDomainTiers(instituteId)) {
        if (row.domainSlug == domainSlug) tier = row.tier;
      }
    }
    return _listing(taxonomy, record, classification, domainSlug, tier);
  }

  /// The UGC line for a classification (plan §8.6).
  static UgcBadge ugcBadgeFor(InstituteClassification? classification) {
    if (classification == null) return UgcBadge.notApplicable;
    if (classification.ugcVerified == true) return UgcBadge.verified;
    if (classification.ugcVerified == false) {
      return UgcBadge.notVerified;
    }
    if (classification.isPrivate) return UgcBadge.pending;
    return UgcBadge.notApplicable;
  }

  /// Top 10 / top 100 for a display ranking: an exact rank, or a band
  /// that ends within the limit ("51-100").
  static RankHighlight highlightFor(InstituteRanking? ranking) {
    if (ranking == null) return RankHighlight.none;
    final best =
        ranking.rank ??
        RegExp(r'\d+')
            .allMatches(ranking.rankBand ?? '')
            .map((match) => int.parse(match.group(0)!))
            .fold<int?>(null, (last, value) => value);
    if (best == null) return RankHighlight.none;
    if (best <= 10) return RankHighlight.top10;
    if (best <= 100) return RankHighlight.top100;
    return RankHighlight.none;
  }

  bool _passes(
    InstituteFilter filter,
    InstituteClassification classification,
    InstituteRecord record,
  ) {
    if (filter.groupCode != null &&
        classification.groupCode != filter.groupCode) {
      return false;
    }
    if (filter.familySlug != null &&
        classification.familySlug != filter.familySlug) {
      return false;
    }
    if (filter.ownerships.isNotEmpty &&
        !filter.ownerships.contains(classification.ownership)) {
      return false;
    }
    if (filter.admitsStudentsOnly && !classification.admitsStudents) {
      return false;
    }
    if (filter.ugcVerifiedOnly &&
        classification.isPrivate &&
        classification.ugcVerified != true) {
      return false;
    }
    final locationFilter = filter.locationFilter;
    if (locationFilter != null) {
      return _locations?.matchesFilter(locationFilter, record) ??
          _matchesLocationFilter(locationFilter, record);
    }
    final place = filter.place;
    final institute = record.institute;
    return place == null ||
        (_locations?.matchesRecord(place, record) ??
            place.matches(
                  city: institute.city,
                  district: institute.district,
                  state: institute.state,
                ) ||
                record.campuses.any(place.matchesCampus));
  }

  static bool _matchesLocationFilter(
    InstituteLocationFilter filter,
    InstituteRecord record,
  ) {
    if (filter.isAllIndia) return true;
    if (filter.onlineOnly) {
      return (record.institute.city ?? '').toLowerCase().contains('online') ||
          record.courses.any(
            (course) => (course.mode ?? '').toLowerCase().contains('online'),
          );
    }
    final campuses = record.campuses;
    if (filter.placeId != null) {
      return campuses.any((campus) => campus.placeId == filter.placeId) ||
          (campuses.isEmpty &&
              LocationService.compact(record.institute.city) ==
                  LocationService.compact(filter.placeName));
    }
    if (filter.districtLgd != null) {
      return campuses.any(
            (campus) => campus.districtLgd == filter.districtLgd,
          ) ||
          (campuses.isEmpty &&
              LocationService.compact(record.institute.district) ==
                  LocationService.compact(filter.districtName));
    }
    return campuses.any(
          (campus) =>
              campus.stateCode.toUpperCase() == filter.stateCode?.toUpperCase(),
        ) ||
        (campuses.isEmpty &&
            LocationService.compact(record.institute.state) ==
                LocationService.compact(filter.stateName));
  }

  InstituteListing _listing(
    _Taxonomy taxonomy,
    InstituteRecord record,
    InstituteClassification? classification,
    String? domainSlug,
    int? tier,
  ) {
    final id = record.institute.id;
    final ranking = _displayRanking(record.rankings, domainSlug);
    final accreditations = record.accreditations;
    String? naac;
    if (ranking == null) {
      for (final accreditation in accreditations) {
        if (accreditation.body == 'NAAC' && accreditation.grade != null) {
          naac = accreditation.grade;
          break;
        }
      }
    }
    final institute = record.institute;
    final hasCampusScopedLocations =
        _locations?.hasCampusScopedLocationData == true;
    return InstituteListing(
      instituteId: id,
      name: institute.name,
      city: hasCampusScopedLocations && record.campuses.isEmpty
          ? null
          : institute.city,
      district: hasCampusScopedLocations && record.campuses.isEmpty
          ? null
          : institute.district,
      state: hasCampusScopedLocations && record.campuses.isEmpty
          ? null
          : institute.state,
      campuses: record.campuses,
      classification: classification,
      groupName: taxonomy.groupNames[classification?.groupCode],
      familyName: taxonomy.familyNames[classification?.familySlug],
      tier: tier,
      ranking: ranking,
      highlight: highlightFor(ranking),
      naacGrade: naac,
      accreditations: accreditations,
      ugcBadge: ugcBadgeFor(classification),
    );
  }

  static InstituteRanking? _displayRanking(
    List<InstituteRanking> rankings,
    String? domainSlug,
  ) {
    final nirfRankings = rankings.where((ranking) => ranking.system == 'NIRF');
    for (final category in nirfCategoriesFor(domainSlug)) {
      for (final ranking in nirfRankings) {
        if (ranking.category == category) return ranking;
      }
    }
    return null;
  }

  static const _naacOrder = ['A++', 'A+', 'A', 'B++', 'B+', 'B', 'C'];

  /// Tier, then exact NIRF rank, then band, then NAAC grade, then name.
  static int _compareListings(InstituteListing a, InstituteListing b) {
    int key(InstituteListing listing) {
      final ranking = listing.ranking;
      if (ranking?.rank != null) return ranking!.rank!;
      if (ranking != null) return 100000 + ranking.sortKey;
      final naac = _naacOrder.indexOf(listing.naacGrade?.trim() ?? '');
      return naac >= 0 ? 200000 + naac : 300000;
    }

    return [
      (a.tier ?? 0).compareTo(b.tier ?? 0),
      key(a).compareTo(key(b)),
      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    ].firstWhere((order) => order != 0, orElse: () => 0);
  }

  Future<_Taxonomy> _loadTaxonomy(LocalDatabase db) =>
      _taxonomyCache ??= () async {
        final groups = await db.getInstitutionGroups();
        final families = await db.getFamilies();
        final listed = await db.getListedClassifications();
        return _Taxonomy(
          groupNames: {for (final group in groups) group.code: group.name},
          familyNames: {
            for (final family in families) family.slug: family.name,
          },
          listed: {for (final row in listed) row.instituteId: row},
        );
      }();

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
      if (record.campuses.isNotEmpty)
        'Mapped campus locations: ${record.campuses.map((campus) => '${campus.placeName}, ${campus.stateName}').toSet().join('; ')}',
      if (record.campuses.any(_hasUnverifiedLocation))
        'Location provenance: mapped from existing institute records; not independently verified',
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

  /// Grounding text for a classified institute, including only facts present
  /// in the taxonomy and ranking tables.
  String describeListing(InstituteListing listing) {
    final record = _recordsById[listing.instituteId];
    final classification = listing.classification;
    final rank = listing.ranking;
    final badge = listing.ugcBadge;
    final campusLocations = listing.campuses
        .map((campus) => '${campus.placeName}, ${campus.stateName}'.trim())
        .toSet();
    return [
      'Title: ${listing.name}',
      if (campusLocations.isNotEmpty)
        'Campus locations: ${campusLocations.join('; ')}'
      else if (listing.city != null || listing.state != null)
        'Location: ${[listing.city, listing.state].whereType<String>().where((part) => part.isNotEmpty).join(', ')}',
      if (campusLocations.isNotEmpty &&
              listing.campuses.any(_hasUnverifiedLocation) ||
          campusLocations.isEmpty &&
              (listing.city != null || listing.state != null))
        'Location provenance: mapped from existing institute records; not independently verified',
      if (listing.groupName != null) 'Institution group: ${listing.groupName}',
      if (listing.familyName != null)
        'Institution family: ${listing.familyName}',
      if (listing.tier != null) 'Domain tier: ${listing.tier}',
      if (rank != null)
        'Ranking: ${rank.label} #${rank.rankLabel}'
      else if (listing.naacGrade != null)
        'Accreditation: NAAC ${listing.naacGrade}'
      else
        'Ranking: Not ranked',
      if (listing.highlight == RankHighlight.top10)
        'Highlight: Top 10 · ${rank!.label}'
      else if (listing.highlight == RankHighlight.top100)
        'Highlight: NIRF Top 100 · ${rank!.year}',
      if (badge == UgcBadge.verified) 'UGC status: verified',
      if (badge == UgcBadge.notVerified) 'UGC status: not verified',
      if (badge == UgcBadge.pending) 'UGC status: pending evidence',
      if (classification?.regulators?.trim().isNotEmpty == true)
        'Regulators: ${classification!.regulators}',
      if (record?.institute.website?.isNotEmpty == true)
        'Website: ${record!.institute.website}',
    ].join('\n');
  }

  static bool _hasUnverifiedLocation(InstituteCampus campus) =>
      campus.sourceUrl?.trim().isNotEmpty != true ||
      campus.verifiedAt?.trim().isNotEmpty != true;

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

  /// Best available ranking for search tie-breaking. Relevance remains the
  /// primary ordering signal, while equally relevant records stay top first.
  static int _recordRankKey(InstituteRecord record) {
    if (record.rankings.isEmpty) return 300000;
    return record.rankings
        .map(
          (ranking) =>
              ranking.rank != null ? ranking.rank! : 100000 + ranking.sortKey,
        )
        .reduce((a, b) => a < b ? a : b);
  }

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

/// Group / family names and listed classifications, read once.
class _Taxonomy {
  final Map<String, String> groupNames;
  final Map<String, String> familyNames;
  final Map<int, InstituteClassification> listed;

  const _Taxonomy({
    required this.groupNames,
    required this.familyNames,
    required this.listed,
  });
}
