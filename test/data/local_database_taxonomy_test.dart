import 'dart:io';

import 'package:career_path/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The taxonomy part of the bundled schema, trimmed to what the queries read.
const _schema = [
  'CREATE TABLE career_nodes (id INTEGER PRIMARY KEY, slug TEXT, '
      'stream_id INTEGER, parent_id INTEGER, name TEXT, intro TEXT)',
  'CREATE TABLE institutes (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
      'city TEXT, website TEXT, description TEXT, source_id TEXT, '
      'district TEXT, state TEXT, institution_type TEXT)',
  'CREATE TABLE institute_rankings (institute_id INTEGER, system TEXT, '
      'year INTEGER, category TEXT, nirf_institute_id TEXT, rank INTEGER, '
      'rank_band TEXT, score REAL, source_url TEXT, '
      'PRIMARY KEY (institute_id, system, year, category))',
  'CREATE TABLE institution_groups (code TEXT PRIMARY KEY, name TEXT, '
      'description TEXT, sort_order INTEGER)',
  'CREATE TABLE families (slug TEXT PRIMARY KEY, name TEXT, group_code TEXT, '
      'regulators TEXT, official_list_url TEXT, national_count INTEGER, '
      'national_count_as_of TEXT)',
  'CREATE TABLE institute_classification (institute_id INTEGER PRIMARY KEY, '
      'group_code TEXT NOT NULL, family_slug TEXT, ownership TEXT, '
      'statutory_basis TEXT, admits_students INTEGER NOT NULL DEFAULT 1, '
      'parent_institute_id INTEGER, is_family_record INTEGER NOT NULL DEFAULT 0, '
      'regulators TEXT, listed INTEGER NOT NULL DEFAULT 1, ugc_verified INTEGER, '
      'ugc_list_name TEXT, ugc_reference_id TEXT, ugc_source_url TEXT, '
      'ugc_checked_at TEXT, confidence TEXT NOT NULL, source_url TEXT, '
      'verified_at TEXT, notes TEXT)',
  'CREATE TABLE institute_verifications (institute_id INTEGER, '
      'authority TEXT, list_name TEXT, list_url TEXT, list_as_of TEXT, '
      'reference_id TEXT, verified_at TEXT, '
      'PRIMARY KEY (institute_id, authority, list_name))',
  'CREATE TABLE institute_accreditations (institute_id INTEGER, body TEXT, '
      "programme TEXT NOT NULL DEFAULT '', grade TEXT, status TEXT, "
      'valid_until TEXT, source_url TEXT)',
  'CREATE TABLE domains (slug TEXT PRIMARY KEY, name TEXT, route_type TEXT, '
      'regulators TEXT, entrance_exams TEXT, sort_order INTEGER)',
  'CREATE TABLE domain_nodes (node_id INTEGER PRIMARY KEY, domain_slug TEXT)',
  'CREATE TABLE domain_tiers (domain_slug TEXT, tier INTEGER, label TEXT, '
      'group_codes TEXT, family_slugs TEXT, entry_exams TEXT, '
      'PRIMARY KEY (domain_slug, tier))',
  'CREATE TABLE institute_domain_tiers (institute_id INTEGER, '
      'domain_slug TEXT, tier INTEGER, PRIMARY KEY (institute_id, domain_slug))',
  'CREATE TABLE states (code TEXT PRIMARY KEY, lgd_code INTEGER, '
      'country_code TEXT, name TEXT, kind TEXT, zone TEXT)',
];

const _seed = [
  "INSERT INTO career_nodes VALUES (1, 'science', 1, NULL, 'Science', NULL), "
      "(2, 'engineering', 1, 1, 'Engineering', NULL), "
      "(3, 'civil', 1, 2, 'Civil Engineering', NULL), "
      "(4, 'law', 3, NULL, 'Law', NULL)",
  "INSERT INTO institutes (id, name) VALUES (1, 'IITs'), "
      "(10, 'IIT Bombay'), (11, 'IIT Delhi'), (12, 'IIT Bombay CTARA'), "
      "(13, 'IIT Coaching Hub'), (20, 'NLSIU Bengaluru'), "
      "(30, 'Private Law School')",
  "INSERT INTO institution_groups VALUES ('G1', 'National flagship', 'INIs', 1), "
      "('G4', 'State public universities', 'State', 4), "
      "('G8', 'Private colleges', 'Private', 8)",
  "INSERT INTO families VALUES ('iit', 'IITs', 'G1', 'MoE', NULL, 23, '2026-10-01'), "
      "('nlu', 'National Law Universities', 'G4', 'BCI', NULL, 26, NULL), "
      "('aiims', 'AIIMS', 'G1', 'MoHFW', NULL, 23, NULL)",
  'INSERT INTO institute_classification (institute_id, group_code, family_slug, '
      'ownership, parent_institute_id, is_family_record, listed, ugc_verified, '
      'confidence) VALUES '
      "(1, 'G1', 'iit', 'central_govt', NULL, 1, 0, NULL, 'high'), "
      "(10, 'G1', 'iit', 'central_govt', NULL, 0, 1, NULL, 'high'), "
      "(11, 'G1', 'iit', 'central_govt', NULL, 0, 1, NULL, 'high'), "
      "(12, 'G1', 'iit', 'central_govt', 10, 0, 1, NULL, 'high'), "
      "(13, 'G1', 'iit', 'private', NULL, 0, 0, 0, 'low'), "
      "(20, 'G4', 'nlu', 'state_govt', NULL, 0, 1, NULL, 'high'), "
      "(30, 'G8', NULL, 'private', NULL, 0, 1, 1, 'medium')",
  "INSERT INTO institute_verifications VALUES (10, 'MoE', 'IIT list', "
      "'https://www.iitsystem.ac.in/', '2026-10-01', NULL, '2026-10-01')",
  "INSERT INTO institute_accreditations VALUES (30, 'NAAC', '', 'A', "
      "'accredited', '2028-01-01', 'https://naac.gov.in/'), "
      "(30, 'NBA', 'LLB', NULL, 'accredited', NULL, 'https://www.nbaind.org/')",
  'INSERT INTO institute_rankings (institute_id, system, year, category, rank, '
      'rank_band, source_url) VALUES '
      "(10, 'NIRF', 2025, 'Overall', 3, NULL, 'u'), "
      "(10, 'NIRF', 2025, 'Engineering', 2, NULL, 'u'), "
      "(10, 'NIRF', 2024, 'Engineering', 3, NULL, 'u'), "
      "(11, 'NIRF', 2024, 'Overall', 2, NULL, 'u'), "
      "(20, 'NIRF', 2025, 'Law', 1, NULL, 'u')",
  "INSERT INTO domains VALUES ('engineering', 'Engineering', 'degree', 'AICTE', "
      "'JEE Main', 1), ('law', 'Law', 'degree', 'BCI', 'CLAT', 17)",
  "INSERT INTO domain_nodes VALUES (2, 'engineering'), (4, 'law')",
  "INSERT INTO domain_tiers VALUES ('law', 2, 'INIs', 'G1', NULL, NULL), "
      "('law', 1, 'National Law Universities', 'G4', 'nlu', 'CLAT'), "
      "('engineering', 1, 'INIs', 'G1', NULL, 'JEE Advanced')",
  "INSERT INTO institute_domain_tiers VALUES (11, 'engineering', 1), "
      "(10, 'engineering', 1), (1, 'engineering', 1), (20, 'law', 1), "
      "(10, 'law', 2)",
  "INSERT INTO states VALUES ('IN-RJ', 8, 'IN', 'Rajasthan', 'state', 'north'), "
      "('IN-DL', 7, 'IN', 'Delhi', 'ut', 'north')",
];

void main() {
  sqfliteFfiInit();

  late Database database;
  late LocalDatabase local;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in [..._schema, ..._seed]) {
      await database.execute(sql);
    }
    local = LocalDatabase.withDatabase(database);
  });

  tearDown(() => local.close());

  group('groups and families', () {
    test('groups come in sort order and look up by code', () async {
      final groups = await local.getInstitutionGroups();
      expect(groups.map((g) => g.code), ['G1', 'G4', 'G8']);
      expect(
        (await local.getInstitutionGroup('G4'))?.name,
        'State public universities',
      );
      expect(await local.getInstitutionGroup('G99'), isNull);
    });

    test(
      'families are ordered by group, then name, and filter by group',
      () async {
        final all = await local.getFamilies();
        expect(all.map((f) => f.slug), ['aiims', 'iit', 'nlu']);
        final g1 = await local.getFamilies(groupCode: 'G1');
        expect(g1.map((f) => f.slug), ['aiims', 'iit']);
        expect((await local.getFamily('iit'))?.nationalCount, 23);
        expect(await local.getFamily('nope'), isNull);
      },
    );

    test('listed counts skip family, child and unlisted rows', () async {
      final counts = await local.getFamilyListedCounts();
      expect(counts, {'iit': 2, 'nlu': 1});
    });
  });

  group('classification', () {
    test('reads one institute and keeps UGC NULL for government', () async {
      final iit = await local.getInstituteClassification(10);
      expect(iit?.familySlug, 'iit');
      expect(iit?.ugcVerified, isNull);
      final private = await local.getInstituteClassification(30);
      expect(private?.ugcVerified, isTrue);
      expect(await local.getInstituteClassification(999), isNull);
    });

    test(
      'family members exclude family, child and unlisted rows by default',
      () async {
        final iits = await local.getInstitutesInFamily('iit');
        expect(iits.map((c) => c.instituteId), [10, 11]);

        final everything = await local.getInstitutesInFamily(
          'iit',
          includeChildren: true,
          includeFamilyRecords: true,
          includeUnlisted: true,
        );
        expect(everything.map((c) => c.instituteId), [10, 12, 13, 11, 1]);
      },
    );

    test('group members use the same exclusions', () async {
      expect(
        (await local.getInstitutesInGroup('G1')).map((c) => c.instituteId),
        [10, 11],
      );
      expect(
        (await local.getInstitutesInGroup('G8')).map((c) => c.instituteId),
        [30],
      );
    });

    test('children of an institute are its campuses and departments', () async {
      final children = await local.getChildInstitutes(10);
      expect(children.map((c) => c.instituteId), [12]);
      expect(children.single.parentInstituteId, 10);
      expect(await local.getChildInstitutes(11), isEmpty);
    });
  });

  group('verification and ranking', () {
    test('verifications and accreditations per institute', () async {
      final v = await local.getInstituteVerifications(10);
      expect(v.single.authority, 'MoE');
      expect(await local.getInstituteVerifications(11), isEmpty);

      final a = await local.getInstituteAccreditations(30);
      expect(a.map((x) => x.body), ['NAAC', 'NBA']);
      expect(a.first.isInstitutionLevel, isTrue);
    });

    test(
      'rankings come newest first; latestYearOnly trims old years',
      () async {
        final all = await local.getInstituteRankings(10);
        expect(all.map((r) => '${r.year} ${r.category}'), [
          '2025 Engineering',
          '2025 Overall',
          '2024 Engineering',
        ]);
        final latest = await local.getInstituteRankings(
          10,
          latestYearOnly: true,
        );
        expect(latest.map((r) => r.year).toSet(), {2025});
      },
    );

    test('display ranking prefers the domain category, then Overall', () async {
      final eng = await local.getDisplayRanking(10, domainSlug: 'engineering');
      expect(eng?.label, 'NIRF 2025 Engineering');
      expect(eng?.rank, 2);

      final overall = await local.getDisplayRanking(10, domainSlug: 'law');
      expect(overall?.category, 'Overall');

      final older = await local.getDisplayRanking(
        11,
        domainSlug: 'engineering',
      );
      expect(older?.label, 'NIRF 2024 Overall');

      expect(await local.getDisplayRanking(30), isNull);
    });
  });

  group('domains and tiers', () {
    test('domains in order, one by slug', () async {
      expect((await local.getDomains()).map((d) => d.slug), [
        'engineering',
        'law',
      ]);
      expect((await local.getDomain('law'))?.entranceExams, 'CLAT');
      expect(await local.getDomain('x'), isNull);
    });

    test('a node inherits the nearest ancestor domain', () async {
      expect(await local.getDomainSlugForNode(3), 'engineering');
      expect(await local.getDomainSlugForNode(2), 'engineering');
      expect(await local.getDomainSlugForNode(4), 'law');
      expect(await local.getDomainSlugForNode(1), isNull);
    });

    test(
      'the ladder is ordered by tier and apex tiers name families',
      () async {
        final tiers = await local.getDomainTiers('law');
        expect(tiers.map((t) => t.tier), [1, 2]);
        expect(tiers.first.isApex, isTrue);
        expect(tiers.first.familySlugList, ['nlu']);
      },
    );

    test(
      'institutes on a ladder skip family records, sorted by name',
      () async {
        final eng = await local.getInstitutesOnDomainLadder('engineering');
        expect(eng.map((t) => t.instituteId), [10, 11]);
        final lawTop = await local.getInstitutesOnDomainLadder('law', tier: 1);
        expect(lawTop.map((t) => t.instituteId), [20]);
        final mine = await local.getInstituteDomainTiers(10);
        expect(mine.map((t) => '${t.domainSlug}:${t.tier}'), [
          'engineering:1',
          'law:2',
        ]);
      },
    );
  });

  test('states are listed by name', () async {
    final states = await local.getStates();
    expect(states.map((s) => s.code), ['IN-DL', 'IN-RJ']);
    expect(states.first.isUnionTerritory, isTrue);
  });

  test(
    'an older DB without the taxonomy tables returns empty, not errors',
    () async {
      final old = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await old.execute(_schema[1]); // institutes only
      final legacy = LocalDatabase.withDatabase(old);

      expect(await legacy.getInstitutionGroups(), isEmpty);
      expect(await legacy.getInstitutionGroup('G1'), isNull);
      expect(await legacy.getFamilies(), isEmpty);
      expect(await legacy.getFamily('iit'), isNull);
      expect(await legacy.getFamilyListedCounts(), isEmpty);
      expect(await legacy.getInstituteClassification(1), isNull);
      expect(await legacy.getInstitutesInFamily('iit'), isEmpty);
      expect(await legacy.getInstitutesInGroup('G1'), isEmpty);
      expect(await legacy.getChildInstitutes(1), isEmpty);
      expect(await legacy.getInstituteVerifications(1), isEmpty);
      expect(await legacy.getInstituteAccreditations(1), isEmpty);
      expect(await legacy.getInstituteRankings(1), isEmpty);
      expect(await legacy.getDisplayRanking(1), isNull);
      expect(await legacy.getDomains(), isEmpty);
      expect(await legacy.getDomain('law'), isNull);
      expect(await legacy.getDomainSlugForNode(1), isNull);
      expect(await legacy.getDomainTiers('law'), isEmpty);
      expect(await legacy.getInstitutesOnDomainLadder('law'), isEmpty);
      expect(await legacy.getInstituteDomainTiers(1), isEmpty);
      expect(await legacy.getStates(), isEmpty);
      await legacy.close();
    },
  );

  test('the bundled asset answers the taxonomy queries', () async {
    // Read a private copy: another process may be rewriting the asset.
    final asset = File('assets/data/career_path.db');
    final tmp = await Directory.systemTemp.createTemp('career_path_db');
    final copy = await asset.copy(p.join(tmp.path, 'career_path.db'));
    final bundled = await databaseFactoryFfi.openDatabase(
      copy.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final real = LocalDatabase.withDatabase(bundled);
    try {
      final groups = await real.getInstitutionGroups();
      if (groups.isEmpty) return; // asset predates the taxonomy tables
      expect(groups.first.code, 'G1');
      expect(groups.length, 13);
      expect((await real.getFamily('iit'))?.groupCode, 'G1');
      final iits = await real.getInstitutesInFamily('iit');
      expect(iits, isNotEmpty);
      expect(iits.every((c) => c.isTopLevelListing), isTrue);
      final lawTiers = await real.getDomainTiers('law');
      expect(lawTiers.first.familySlugList, contains('nlu'));
      expect(await real.getStates(), hasLength(greaterThanOrEqualTo(36)));
    } finally {
      await real.close();
      await tmp.delete(recursive: true);
    }
  });
}
