import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

import '../models/domain.dart';
import '../models/domain_tier.dart';
import '../models/institute_accreditation.dart';
import '../models/institute_campus.dart';
import '../models/institute_catalog.dart';
import '../models/institute_classification.dart';
import '../models/institute_domain_tier.dart';
import '../models/place_alias.dart';
import '../models/place_record.dart';
import '../models/district_region.dart';
import '../models/institute_verification.dart';
import '../models/institution_family.dart';
import '../models/institution_group.dart';
import '../models/state_region.dart';
import 'local_database_platform.dart';

/// Manages the bundled SQLite database lifecycle.
/// Always copies from assets to ensure latest data.
class LocalDatabase {
  Database? _db;

  /// Table names present in the open DB, read once (see [_hasTables]).
  Set<String>? _tables;

  static const _assetPath = 'assets/data/career_path.db';
  static const _dbFileName = 'career_path.db';

  LocalDatabase();

  /// Wraps an already-open database. Tests open one with sqflite_common_ffi.
  @visibleForTesting
  LocalDatabase.withDatabase(Database database) : _db = database;

  Future<void> init() async {
    _tables = null;
    // The platform helper uses a file on mobile/desktop and IndexedDB-backed
    // SQLite WASM in a browser. Keeping dart:io out of this class is required
    // for Flutter Web to finish startup and call runApp().
    _db = await openBundledDatabase(
      assetPath: _assetPath,
      databaseName: _dbFileName,
    );
  }

  Database get db {
    if (_db == null) throw StateError('LocalDatabase not initialized');
    return _db!;
  }

  // ── Streams ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStreams() async {
    final streams = await db.rawQuery(
      'SELECT id, slug, name, intro FROM streams ORDER BY id',
    );
    final roots = await db.rawQuery(
      'SELECT id, stream_id FROM career_nodes WHERE parent_id IS NULL ORDER BY id',
    );
    // Group root node IDs by stream
    final rootsByStream = <int, List<int>>{};
    for (final r in roots) {
      final sid = r['stream_id'] as int;
      (rootsByStream[sid] ??= []).add(r['id'] as int);
    }
    return streams.map((s) {
      final sid = s['id'] as int;
      return {
        'id': sid,
        'slug': s['slug'],
        'name': s['name'],
        'intro': s['intro'],
        'root_node_ids': rootsByStream[sid] ?? [],
      };
    }).toList();
  }

  // ── Root Nodes ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStreamRootNodes(int streamId) async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro FROM career_nodes '
      'WHERE stream_id = ? AND parent_id IS NULL ORDER BY id',
      [streamId],
    );
    final nodeIds = rows.map((r) => r['id'] as int).toList();
    final childMap = await _buildChildMap(nodeIds);
    return rows.map((r) {
      final id = r['id'] as int;
      final childIds = childMap[id] ?? [];
      return {
        'id': id,
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': streamId,
        'parent_id': null,
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      };
    }).toList();
  }

  // ── Children ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNodeChildren(int nodeId) async {
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro, stream_id FROM career_nodes '
      'WHERE parent_id = ? ORDER BY id',
      [nodeId],
    );
    final nodeIds = rows.map((r) => r['id'] as int).toList();
    final childMap = await _buildChildMap(nodeIds);
    return rows.map((r) {
      final id = r['id'] as int;
      final childIds = childMap[id] ?? [];
      return {
        'id': id,
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': r['stream_id'],
        'parent_id': nodeId,
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      };
    }).toList();
  }

  // ── Leaf Details ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getNodeDetails(int nodeId) async {
    final nodes = await db.rawQuery(
      'SELECT id, slug, name, intro FROM career_nodes WHERE id = ?',
      [nodeId],
    );
    if (nodes.isEmpty) throw Exception('Node $nodeId not found');
    final node = nodes.first;

    // Run all 3 resource queries in parallel
    final results = await Future.wait([
      db.rawQuery(
        'SELECT b.id, b.title, b.author, b.url, b.description '
        'FROM books b JOIN node_books nb ON nb.book_id = b.id '
        'WHERE nb.node_id = ? ORDER BY b.title',
        [nodeId],
      ),
      db.rawQuery(
        'SELECT i.id, i.source_id, i.name, i.city, i.district, i.state, '
        'i.institution_type, i.website, i.description '
        'FROM institutes i JOIN node_institutes ni ON ni.institute_id = i.id '
        'WHERE ni.node_id = ? ORDER BY i.name',
        [nodeId],
      ),
      db.rawQuery(
        'SELECT js.id, js.name, js.description '
        'FROM job_sectors js JOIN node_job_sectors njs ON njs.job_sector_id = js.id '
        'WHERE njs.node_id = ? ORDER BY js.name',
        [nodeId],
      ),
    ]);

    return {
      'id': node['id'],
      'slug': node['slug'],
      'name': node['name'],
      'intro': node['intro'],
      'books': results[0].map((b) => Map<String, dynamic>.from(b)).toList(),
      'institutes': results[1]
          .map((i) => Map<String, dynamic>.from(i))
          .toList(),
      'job_sectors': results[2]
          .map((j) => Map<String, dynamic>.from(j))
          .toList(),
    };
  }

  // ── Institute catalog (courses, rankings, accreditations) — batched queries

  Future<List<Map<String, dynamic>>> getInstituteCatalog() async {
    final hasCampusTables = await _hasTables(const [
      'campuses',
      'places',
      'districts',
      'states',
    ]);
    final campusRows = hasCampusTables
        ? await db.rawQuery(
            'SELECT c.id, c.institute_id, c.name, c.place_id, p.name AS place_name, '
            'd.name AS district_name, d.lgd_code AS district_lgd, '
            's.code AS state_code, s.name AS state_name, c.is_main, '
            'c.source_url, c.verified_at FROM campuses c '
            'JOIN places p ON p.id = c.place_id '
            'JOIN districts d ON d.lgd_code = p.district_lgd '
            'JOIN states s ON s.code = d.state_code '
            'ORDER BY c.institute_id, c.is_main DESC, p.name',
          )
        : <Map<String, Object?>>[];
    final hasClassificationTable = await _hasTables(const [
      'institute_classification',
    ]);
    final classificationRows = hasClassificationTable
        ? await db.rawQuery('SELECT * FROM institute_classification')
        : <Map<String, Object?>>[];
    final hasAccreditationTable = await _hasTables(const [
      'institute_accreditations',
    ]);
    final accreditationRows = hasAccreditationTable
        ? await db.rawQuery(
            'SELECT institute_id, body, programme, grade, status, valid_until, '
            'source_url FROM institute_accreditations '
            "ORDER BY institute_id, CASE body WHEN 'NAAC' THEN 0 ELSE 1 END, programme",
          )
        : <Map<String, Object?>>[];
    final results = await Future.wait([
      db.rawQuery(
        'SELECT id, source_id, name, city, district, state, '
        'institution_type, website, description FROM institutes ORDER BY name',
      ),
      db.rawQuery(
        'SELECT id, institute_id, name, level, credential, specialization, '
        'duration, mode, eligibility, official_course_url '
        'FROM institute_courses ORDER BY institute_id, name',
      ),
      db.rawQuery(
        'SELECT ccn.course_id, cn.slug FROM course_career_nodes ccn '
        'JOIN career_nodes cn ON cn.id = ccn.node_id',
      ),
      db.rawQuery(
        'SELECT institute_id, system, year, category, rank, rank_band, '
        'score, source_url FROM institute_rankings '
        'ORDER BY year DESC, category, rank',
      ),
      db.rawQuery('SELECT institute_id, category FROM institute_categories'),
    ]);
    final courseCareers = <int, List<String>>{};
    for (final row in results[2]) {
      (courseCareers[row['course_id'] as int] ??= []).add(
        row['slug'] as String,
      );
    }
    final courses = <int, List<Map<String, dynamic>>>{};
    for (final row in results[1]) {
      final course = Map<String, dynamic>.from(row)
        ..['career_slugs'] = courseCareers[row['id'] as int] ?? const [];
      (courses[row['institute_id'] as int] ??= []).add(course);
    }
    final rankings = <int, List<Map<String, dynamic>>>{};
    for (final row in results[3]) {
      (rankings[row['institute_id'] as int] ??= []).add(
        Map<String, dynamic>.from(row),
      );
    }
    final categories = <int, List<String>>{};
    for (final row in results[4]) {
      (categories[row['institute_id'] as int] ??= []).add(
        row['category'] as String,
      );
    }
    final campuses = <int, List<Map<String, dynamic>>>{};
    for (final row in campusRows) {
      (campuses[row['institute_id'] as int] ??= []).add(
        Map<String, dynamic>.from(row),
      );
    }
    final classifications = <int, Map<String, dynamic>>{
      for (final row in classificationRows)
        row['institute_id'] as int: Map<String, dynamic>.from(row),
    };
    final accreditations = <int, List<Map<String, dynamic>>>{};
    for (final row in accreditationRows) {
      (accreditations[row['institute_id'] as int] ??= []).add(
        Map<String, dynamic>.from(row),
      );
    }
    return results[0].map((row) {
      final id = row['id'] as int;
      return {
        ...row,
        'courses': courses[id] ?? const [],
        'rankings': rankings[id] ?? const [],
        'categories': categories[id] ?? const [],
        'campuses': campuses[id] ?? const [],
        'classification': classifications[id],
        'accreditations': accreditations[id] ?? const [],
      };
    }).toList();
  }

  // ── Book catalog (every book with its career paths) — 2 queries ────────

  Future<List<Map<String, dynamic>>> getBookCatalog() async {
    final results = await Future.wait([
      db.rawQuery(
        'SELECT id, title, author, url, description FROM books ORDER BY title',
      ),
      db.rawQuery(
        'SELECT nb.book_id, cn.slug, cn.name FROM node_books nb '
        'JOIN career_nodes cn ON cn.id = nb.node_id ORDER BY cn.name',
      ),
    ]);
    final slugs = <int, List<String>>{};
    final names = <int, List<String>>{};
    for (final row in results[1]) {
      final bookId = row['book_id'] as int;
      (slugs[bookId] ??= []).add(row['slug'] as String);
      (names[bookId] ??= []).add(row['name'] as String);
    }
    return results[0].map((row) {
      final id = row['id'] as int;
      return {
        ...row,
        'node_ids': slugs[id] ?? const <String>[],
        'node_names': names[id] ?? const <String>[],
      };
    }).toList();
  }

  // ── All Nodes (for eager-load) — 2 queries total ───────────────────────

  Future<List<Map<String, dynamic>>> getAllNodes() async {
    // Query 1: all nodes
    final rows = await db.rawQuery(
      'SELECT id, slug, name, intro, stream_id, parent_id '
      'FROM career_nodes ORDER BY id',
    );
    // Query 2: all parent→child relationships in one shot
    final allChildren = await db.rawQuery(
      'SELECT parent_id, id FROM career_nodes '
      'WHERE parent_id IS NOT NULL ORDER BY parent_id, id',
    );
    final childMap = <int, List<int>>{};
    for (final c in allChildren) {
      final pid = c['parent_id'] as int;
      (childMap[pid] ??= []).add(c['id'] as int);
    }

    return rows.map((r) {
      final id = r['id'] as int;
      final childIds = childMap[id] ?? [];
      return {
        'id': id,
        'slug': r['slug'],
        'name': r['name'],
        'intro': r['intro'],
        'stream_id': r['stream_id'],
        'parent_id': r['parent_id'],
        'is_leaf': childIds.isEmpty,
        'child_ids': childIds,
      };
    }).toList();
  }

  // ── Helper: batch child lookup ──────────────────────────────────────────

  Future<Map<int, List<int>>> _buildChildMap(List<int> parentIds) async {
    if (parentIds.isEmpty) return {};
    final placeholders = List.filled(parentIds.length, '?').join(',');
    final children = await db.rawQuery(
      'SELECT parent_id, id FROM career_nodes '
      'WHERE parent_id IN ($placeholders) ORDER BY parent_id, id',
      parentIds,
    );
    final map = <int, List<int>>{};
    for (final c in children) {
      final pid = c['parent_id'] as int;
      (map[pid] ??= []).add(c['id'] as int);
    }
    return map;
  }

  // ── Institution taxonomy (plan §7) ─────────────────────────────────────
  //
  // Every query returns empty / null when its tables are missing, so an
  // older bundled DB (or a test fixture) without the taxonomy still works.

  /// The 13 institution groups, G1 first.
  Future<List<InstitutionGroup>> getInstitutionGroups() async {
    if (!await _hasTables(const ['institution_groups'])) return const [];
    final rows = await db.rawQuery(
      'SELECT code, name, description, sort_order FROM institution_groups '
      'ORDER BY sort_order, code',
    );
    return rows.map(InstitutionGroup.fromJson).toList(growable: false);
  }

  Future<InstitutionGroup?> getInstitutionGroup(String code) async {
    if (!await _hasTables(const ['institution_groups'])) return null;
    final rows = await db.rawQuery(
      'SELECT code, name, description, sort_order FROM institution_groups '
      'WHERE code = ?',
      [code],
    );
    return rows.isEmpty ? null : InstitutionGroup.fromJson(rows.first);
  }

  /// Every family (including ones with no institute yet), by group then
  /// name; only [groupCode]'s families when given.
  Future<List<InstitutionFamily>> getFamilies({String? groupCode}) async {
    if (!await _hasTables(const ['families'])) return const [];
    final orderByGroup = await _hasTables(const ['institution_groups']);
    final rows = await db.rawQuery(
      'SELECT f.slug, f.name, f.group_code, f.regulators, '
      'f.official_list_url, f.national_count, f.national_count_as_of '
      'FROM families f '
      '${orderByGroup ? 'LEFT JOIN institution_groups g ON g.code = f.group_code ' : ''}'
      '${groupCode == null ? '' : 'WHERE f.group_code = ? '}'
      'ORDER BY ${orderByGroup ? 'g.sort_order, ' : ''}f.name',
      [?groupCode],
    );
    return rows.map(InstitutionFamily.fromJson).toList(growable: false);
  }

  Future<InstitutionFamily?> getFamily(String slug) async {
    if (!await _hasTables(const ['families'])) return null;
    final rows = await db.rawQuery(
      'SELECT slug, name, group_code, regulators, official_list_url, '
      'national_count, national_count_as_of FROM families WHERE slug = ?',
      [slug],
    );
    return rows.isEmpty ? null : InstitutionFamily.fromJson(rows.first);
  }

  /// How many listed top-level institutes each family has in the DB
  /// ("31 NITs in India · 6 listed"). Families with none are absent.
  Future<Map<String, int>> getFamilyListedCounts() async {
    if (!await _hasTables(const ['institute_classification'])) return const {};
    final rows = await db.rawQuery(
      'SELECT c.family_slug, COUNT(*) AS n FROM institute_classification c '
      'WHERE c.family_slug IS NOT NULL AND ${_listingFilter()} '
      'GROUP BY c.family_slug',
    );
    return {
      for (final row in rows)
        row['family_slug'] as String: (row['n'] as num).toInt(),
    };
  }

  /// The classification of one institute, or null if it has none.
  Future<InstituteClassification?> getInstituteClassification(
    int instituteId,
  ) async {
    if (!await _hasTables(const ['institute_classification'])) return null;
    final rows = await db.rawQuery(
      'SELECT * FROM institute_classification WHERE institute_id = ?',
      [instituteId],
    );
    return rows.isEmpty ? null : InstituteClassification.fromJson(rows.first);
  }

  /// Institutes in a family, by name. Family summary rows ("IITs"),
  /// unlisted rows and campuses/departments of another institute are left
  /// out unless asked for.
  Future<List<InstituteClassification>> getInstitutesInFamily(
    String familySlug, {
    bool includeChildren = false,
    bool includeFamilyRecords = false,
    bool includeUnlisted = false,
  }) => _classifiedInstitutes(
    'c.family_slug = ?',
    [familySlug],
    includeChildren: includeChildren,
    includeFamilyRecords: includeFamilyRecords,
    includeUnlisted: includeUnlisted,
  );

  /// Institutes in a group, by name; same exclusions as
  /// [getInstitutesInFamily].
  Future<List<InstituteClassification>> getInstitutesInGroup(
    String groupCode, {
    bool includeChildren = false,
    bool includeFamilyRecords = false,
    bool includeUnlisted = false,
  }) => _classifiedInstitutes(
    'c.group_code = ?',
    [groupCode],
    includeChildren: includeChildren,
    includeFamilyRecords: includeFamilyRecords,
    includeUnlisted: includeUnlisted,
  );

  /// Every listed, top-level classification row (no family, child or
  /// unlisted rows), by institute name. The catalog filter reads it once.
  Future<List<InstituteClassification>> getListedClassifications() =>
      _classifiedInstitutes(
        '1 = 1',
        const [],
        includeChildren: false,
        includeFamilyRecords: false,
        includeUnlisted: false,
      );

  /// Campuses, departments and centres whose parent is [parentInstituteId].
  Future<List<InstituteClassification>> getChildInstitutes(
    int parentInstituteId, {
    bool includeUnlisted = false,
  }) => _classifiedInstitutes(
    'c.parent_institute_id = ?',
    [parentInstituteId],
    includeChildren: true,
    includeFamilyRecords: false,
    includeUnlisted: includeUnlisted,
  );

  /// Official lists the institute appears on.
  Future<List<InstituteVerification>> getInstituteVerifications(
    int instituteId,
  ) async {
    if (!await _hasTables(const ['institute_verifications'])) return const [];
    final rows = await db.rawQuery(
      'SELECT institute_id, authority, list_name, list_url, list_as_of, '
      'reference_id, verified_at FROM institute_verifications '
      'WHERE institute_id = ? ORDER BY authority, list_name',
      [instituteId],
    );
    return rows.map(InstituteVerification.fromJson).toList(growable: false);
  }

  /// NAAC grades and NBA programme accreditations, NAAC first.
  Future<List<InstituteAccreditation>> getInstituteAccreditations(
    int instituteId,
  ) async {
    if (!await _hasTables(const ['institute_accreditations'])) {
      return const [];
    }
    final rows = await db.rawQuery(
      'SELECT institute_id, body, programme, grade, status, valid_until, '
      'source_url FROM institute_accreditations WHERE institute_id = ? '
      "ORDER BY CASE body WHEN 'NAAC' THEN 0 ELSE 1 END, programme",
      [instituteId],
    );
    return rows.map(InstituteAccreditation.fromJson).toList(growable: false);
  }

  /// One institute's rankings for [system], newest year first. With
  /// [latestYearOnly], only the institute's most recent snapshot year.
  Future<List<InstituteRanking>> getInstituteRankings(
    int instituteId, {
    String system = 'NIRF',
    bool latestYearOnly = false,
  }) async {
    if (!await _hasTables(const ['institute_rankings'])) return const [];
    final rows = await db.rawQuery(
      'SELECT system, year, category, rank, rank_band, score, source_url '
      'FROM institute_rankings r WHERE institute_id = ? AND system = ? '
      '${latestYearOnly ? 'AND year = (SELECT MAX(year) FROM institute_rankings '
                'WHERE institute_id = r.institute_id AND system = r.system) ' : ''}'
      'ORDER BY year DESC, category',
      [instituteId, system],
    );
    return rows.map(InstituteRanking.fromJson).toList(growable: false);
  }

  /// The NIRF rank to show for an institute (plan §8.6): the domain-matched
  /// category first (e.g. Engineering), then Overall / University /
  /// College; the latest year within a category. Null = "Not ranked".
  Future<InstituteRanking?> getDisplayRanking(
    int instituteId, {
    String? domainSlug,
  }) async {
    final rankings = await getInstituteRankings(instituteId);
    if (rankings.isEmpty) return null;
    for (final category in nirfCategoriesFor(domainSlug)) {
      // Already newest-year first.
      for (final ranking in rankings) {
        if (ranking.category == category) return ranking;
      }
    }
    return null;
  }

  /// All domains in display order.
  Future<List<Domain>> getDomains() async {
    if (!await _hasTables(const ['domains'])) return const [];
    final rows = await db.rawQuery(
      'SELECT slug, name, route_type, regulators, entrance_exams, sort_order '
      'FROM domains ORDER BY sort_order, slug',
    );
    return rows.map(Domain.fromJson).toList(growable: false);
  }

  Future<Domain?> getDomain(String slug) async {
    if (!await _hasTables(const ['domains'])) return null;
    final rows = await db.rawQuery(
      'SELECT slug, name, route_type, regulators, entrance_exams, sort_order '
      'FROM domains WHERE slug = ?',
      [slug],
    );
    return rows.isEmpty ? null : Domain.fromJson(rows.first);
  }

  /// The domain a career node belongs to: its own `domain_nodes` row or
  /// the nearest ancestor's (descendants inherit). Null when none.
  Future<String?> getDomainSlugForNode(int nodeId) async {
    if (!await _hasTables(const ['domain_nodes', 'career_nodes'])) return null;
    final rows = await db.rawQuery(
      'WITH RECURSIVE up(id, parent_id, depth) AS ('
      '  SELECT id, parent_id, 0 FROM career_nodes WHERE id = ? '
      '  UNION ALL '
      '  SELECT cn.id, cn.parent_id, up.depth + 1 FROM career_nodes cn '
      '  JOIN up ON cn.id = up.parent_id'
      ') '
      'SELECT dn.domain_slug FROM up JOIN domain_nodes dn ON dn.node_id = up.id '
      'ORDER BY up.depth LIMIT 1',
      [nodeId],
    );
    return rows.isEmpty ? null : rows.first['domain_slug'] as String;
  }

  /// The domain a career node belongs to when the caller has the node's
  /// public slug (the form used by [CareerDataService]). Descendants inherit
  /// the nearest ancestor's domain mapping.
  Future<String?> getDomainSlugForNodeKey(String nodeKey) async {
    if (!await _hasTables(const ['domain_nodes', 'career_nodes'])) return null;
    final numericId = int.tryParse(nodeKey) ?? -1;
    final rows = await db.rawQuery(
      'WITH RECURSIVE up(id, parent_id, depth) AS ('
      '  SELECT id, parent_id, 0 FROM career_nodes '
      '  WHERE id = ? OR slug = ? '
      '  UNION ALL '
      '  SELECT cn.id, cn.parent_id, up.depth + 1 FROM career_nodes cn '
      '  JOIN up ON cn.id = up.parent_id'
      ') '
      'SELECT dn.domain_slug FROM up JOIN domain_nodes dn ON dn.node_id = up.id '
      'ORDER BY up.depth LIMIT 1',
      [numericId, nodeKey],
    );
    return rows.isEmpty ? null : rows.first['domain_slug'] as String;
  }

  /// A domain's college ladder, tier 1 (top) first.
  Future<List<DomainTier>> getDomainTiers(String domainSlug) async {
    if (!await _hasTables(const ['domain_tiers'])) return const [];
    final rows = await db.rawQuery(
      'SELECT domain_slug, tier, label, group_codes, family_slugs, entry_exams '
      'FROM domain_tiers WHERE domain_slug = ? ORDER BY tier',
      [domainSlug],
    );
    return rows.map(DomainTier.fromJson).toList(growable: false);
  }

  /// Institutes placed on [domainSlug]'s ladder (optionally one [tier]),
  /// by tier then institute name. Unlisted, family and child rows are
  /// excluded when the classification table is present.
  Future<List<InstituteDomainTier>> getInstitutesOnDomainLadder(
    String domainSlug, {
    int? tier,
  }) async {
    if (!await _hasTables(const ['institute_domain_tiers'])) return const [];
    final filterListings = await _hasTables(const ['institute_classification']);
    final rows = await db.rawQuery(
      'SELECT t.institute_id, t.domain_slug, t.tier '
      'FROM institute_domain_tiers t '
      'JOIN institutes i ON i.id = t.institute_id '
      '${filterListings ? 'LEFT JOIN institute_classification c ON c.institute_id = t.institute_id ' : ''}'
      'WHERE t.domain_slug = ? ${tier == null ? '' : 'AND t.tier = ? '}'
      '${filterListings ? 'AND (c.institute_id IS NULL OR (${_listingFilter()})) ' : ''}'
      'ORDER BY t.tier, i.name',
      [domainSlug, ?tier],
    );
    return rows.map(InstituteDomainTier.fromJson).toList(growable: false);
  }

  /// Every ladder an institute is on (one row per domain).
  Future<List<InstituteDomainTier>> getInstituteDomainTiers(
    int instituteId,
  ) async {
    if (!await _hasTables(const ['institute_domain_tiers'])) return const [];
    final rows = await db.rawQuery(
      'SELECT institute_id, domain_slug, tier FROM institute_domain_tiers '
      'WHERE institute_id = ? ORDER BY domain_slug',
      [instituteId],
    );
    return rows.map(InstituteDomainTier.fromJson).toList(growable: false);
  }

  /// All states and union territories, by name.
  Future<List<StateRegion>> getStates() async {
    if (!await _hasTables(const ['states'])) return const [];
    final rows = await db.rawQuery(
      'SELECT code, lgd_code, country_code, name, kind, zone FROM states '
      'ORDER BY name',
    );
    return rows.map(StateRegion.fromJson).toList(growable: false);
  }

  /// LGD districts, optionally limited to one state.
  Future<List<DistrictRegion>> getDistricts({String? stateCode}) async {
    if (!await _hasTables(const ['districts', 'states'])) return const [];
    final rows = await db.rawQuery(
      'SELECT lgd_code, state_code, name FROM districts '
      '${stateCode == null ? '' : 'WHERE state_code = ? '}ORDER BY name',
      [?stateCode],
    );
    return rows.map(DistrictRegion.fromJson).toList(growable: false);
  }

  /// LGD places, optionally limited to one district.
  Future<List<PlaceRecord>> getPlaces({int? districtLgd}) async {
    if (!await _hasTables(const ['places', 'districts'])) return const [];
    final rows = await db.rawQuery(
      'SELECT p.id, p.district_lgd, d.name AS district_name, '
      'd.state_code, p.name, p.kind, p.is_district_hq FROM places p '
      'JOIN districts d ON d.lgd_code = p.district_lgd '
      '${districtLgd == null ? '' : 'WHERE p.district_lgd = ? '}ORDER BY p.name',
      [?districtLgd],
    );
    return rows.map(PlaceRecord.fromJson).toList(growable: false);
  }

  /// Alternate place spellings, each linked to exactly one canonical target.
  Future<List<PlaceAlias>> getPlaceAliases() async {
    if (!await _hasTables(const ['place_aliases'])) return const [];
    final rows = await db.rawQuery(
      'SELECT alias, place_id, district_lgd, state_code '
      'FROM place_aliases ORDER BY alias',
    );
    return rows.map(PlaceAlias.fromJson).toList(growable: false);
  }

  /// Official campus-to-place links for one institute or the whole catalog.
  Future<List<InstituteCampus>> getCampuses({int? instituteId}) async {
    if (!await _hasTables(const [
      'campuses',
      'places',
      'districts',
      'states',
    ])) {
      return const [];
    }
    final rows = await db.rawQuery(
      'SELECT c.id, c.institute_id, c.name, c.place_id, p.name AS place_name, '
      'd.name AS district_name, d.lgd_code AS district_lgd, '
      's.code AS state_code, s.name AS state_name, c.is_main, '
      'c.source_url, c.verified_at FROM campuses c '
      'JOIN places p ON p.id = c.place_id '
      'JOIN districts d ON d.lgd_code = p.district_lgd '
      'JOIN states s ON s.code = d.state_code '
      '${instituteId == null ? '' : 'WHERE c.institute_id = ? '} '
      'ORDER BY c.institute_id, c.is_main DESC, p.name',
      [?instituteId],
    );
    return rows.map(InstituteCampus.fromJson).toList(growable: false);
  }

  /// Distinct (city, state) pairs on institutes, by city. The place
  /// resolver matches cities against these until `places` is filled.
  Future<List<({String city, String? state})>> getInstituteCities() async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT TRIM(city) AS city, state FROM institutes '
      "WHERE city IS NOT NULL AND TRIM(city) <> '' ORDER BY city, state",
    );
    return [
      for (final row in rows)
        (city: row['city'] as String, state: row['state'] as String?),
    ];
  }

  // ── Taxonomy helpers ───────────────────────────────────────────────────

  Future<List<InstituteClassification>> _classifiedInstitutes(
    String where,
    List<Object?> args, {
    required bool includeChildren,
    required bool includeFamilyRecords,
    required bool includeUnlisted,
  }) async {
    if (!await _hasTables(const ['institute_classification'])) return const [];
    final filter = _listingFilter(
      includeChildren: includeChildren,
      includeFamilyRecords: includeFamilyRecords,
      includeUnlisted: includeUnlisted,
    );
    final rows = await db.rawQuery(
      'SELECT c.* FROM institute_classification c '
      'JOIN institutes i ON i.id = c.institute_id '
      'WHERE $where AND $filter ORDER BY i.name',
      args,
    );
    return rows.map(InstituteClassification.fromJson).toList(growable: false);
  }

  /// SQL condition on alias `c` (institute_classification) that keeps real,
  /// listed, top-level institutes unless an `include…` flag widens it.
  static String _listingFilter({
    bool includeChildren = false,
    bool includeFamilyRecords = false,
    bool includeUnlisted = false,
  }) {
    final parts = [
      if (!includeUnlisted) 'c.listed = 1',
      if (!includeFamilyRecords) 'c.is_family_record = 0',
      if (!includeChildren) 'c.parent_institute_id IS NULL',
    ];
    return parts.isEmpty ? '1 = 1' : parts.join(' AND ');
  }

  /// True when every table in [names] exists. An older bundled DB has none
  /// of the taxonomy tables, so callers return empty instead of throwing.
  Future<bool> _hasTables(List<String> names) async {
    final tables = _tables ??= (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')",
    )).map((row) => row['name'] as String).toSet();
    return names.every(tables.contains);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _tables = null;
  }
}
