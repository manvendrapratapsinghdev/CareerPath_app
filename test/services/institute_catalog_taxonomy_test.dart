import 'dart:io';

import 'package:career_path/data/local_database.dart';
import 'package:career_path/models/institute_catalog.dart';
import 'package:career_path/models/institute_classification.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  'INSERT INTO institutes (id, name, city, state) VALUES '
      "(1, 'IITs', 'Various', NULL), "
      "(10, 'IIT Bombay', 'Mumbai', 'Maharashtra'), "
      "(11, 'IIT Delhi', 'New Delhi', 'Delhi'), "
      "(12, 'IIT Bombay CTARA', 'Mumbai', 'Maharashtra'), "
      "(13, 'IIT Coaching Hub', 'Kota', 'Rajasthan'), "
      "(14, 'IIT Newcampus', 'Jodhpur', 'Rajasthan'), "
      "(20, 'NLSIU Bengaluru', 'Bengaluru', 'Karnataka'), "
      "(21, 'NLU Jodhpur', 'Jodhpur', 'Rajasthan'), "
      "(30, 'Private Law School', 'Jaipur', 'Rajasthan'), "
      "(31, 'Unverified Law College', 'Jaipur', 'Rajasthan'), "
      "(32, 'Unclassified College', 'Jaipur', 'Rajasthan')",
  "INSERT INTO institution_groups VALUES ('G1', 'National flagship', 'INIs', 1), "
      "('G4', 'State public universities', 'State', 4), "
      "('G8', 'Private colleges', 'Private', 8)",
  "INSERT INTO families VALUES ('iit', 'IITs', 'G1', 'MoE', NULL, 23, NULL), "
      "('nlu', 'National Law Universities', 'G4', 'BCI', NULL, 26, NULL)",
  'INSERT INTO institute_classification (institute_id, group_code, family_slug, '
      'ownership, admits_students, parent_institute_id, is_family_record, '
      'listed, ugc_verified, confidence) VALUES '
      "(1, 'G1', 'iit', 'central_govt', 1, NULL, 1, 0, NULL, 'high'), "
      "(10, 'G1', 'iit', 'central_govt', 1, NULL, 0, 1, NULL, 'high'), "
      "(11, 'G1', 'iit', 'central_govt', 1, NULL, 0, 1, NULL, 'high'), "
      "(12, 'G1', 'iit', 'central_govt', 1, 10, 0, 1, NULL, 'high'), "
      "(13, 'G1', 'iit', 'private', 1, NULL, 0, 0, 0, 'low'), "
      "(14, 'G1', 'iit', 'central_govt', 0, NULL, 0, 1, NULL, 'medium'), "
      "(20, 'G4', 'nlu', 'state_govt', 1, NULL, 0, 1, NULL, 'high'), "
      "(21, 'G4', 'nlu', 'state_govt', 1, NULL, 0, 1, NULL, 'high'), "
      "(30, 'G8', NULL, 'private', 1, NULL, 0, 1, 1, 'medium'), "
      "(31, 'G8', NULL, 'private', 1, NULL, 0, 1, 0, 'medium')",
  'INSERT INTO institute_rankings (institute_id, system, year, category, rank, '
      'rank_band, source_url) VALUES '
      "(10, 'NIRF', 2025, 'Overall', 3, NULL, 'u'), "
      "(10, 'NIRF', 2025, 'Engineering', 2, NULL, 'u'), "
      "(11, 'NIRF', 2025, 'Overall', 2, NULL, 'u'), "
      "(20, 'NIRF', 2025, 'Law', 1, NULL, 'u'), "
      "(21, 'NIRF', 2025, 'Law', NULL, '51-100', 'u')",
  "INSERT INTO institute_accreditations VALUES (30, 'NAAC', '', 'A', "
      "'accredited', '2028-01-01', 'https://naac.gov.in/')",
  "INSERT INTO domains VALUES ('engineering', 'Engineering', 'degree', 'AICTE', "
      "'JEE Main', 1), ('law', 'Law', 'degree', 'BCI', 'CLAT', 17)",
  "INSERT INTO domain_tiers VALUES "
      "('law', 1, 'National Law Universities', 'G4', 'nlu', 'CLAT'), "
      "('law', 2, 'Institutes of National Importance', 'G1', NULL, NULL), "
      "('law', 3, 'Private colleges', 'G8', NULL, NULL), "
      "('law', 4, 'Open and distance', 'G9', NULL, NULL), "
      "('engineering', 1, 'INIs', 'G1', NULL, 'JEE Advanced')",
  'INSERT INTO institute_domain_tiers VALUES '
      "(1, 'engineering', 1), (10, 'engineering', 1), (11, 'engineering', 1), "
      "(12, 'engineering', 1), (14, 'engineering', 1), "
      "(20, 'law', 1), (21, 'law', 1), (10, 'law', 2), "
      "(30, 'law', 3), (31, 'law', 3)",
  "INSERT INTO states VALUES ('IN-RJ', 8, 'IN', 'Rajasthan', 'state', 'north'), "
      "('IN-DL', 7, 'IN', 'Delhi', 'ut', 'north'), "
      "('IN-KA', 29, 'IN', 'Karnataka', 'state', 'south'), "
      "('IN-MH', 27, 'IN', 'Maharashtra', 'state', 'west')",
];

List<int> _ids(List<InstituteListing> listings) =>
    listings.map((listing) => listing.instituteId).toList();

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late InstituteCatalogService catalog;
  late LocationService places;

  setUp(() async {
    local = await openTaxonomyDb(_seed);
    catalog = InstituteCatalogService(
      local.getInstituteCatalog,
      taxonomy: local,
    );
    places = LocationService(
      loadStates: local.getStates,
      loadCities: local.getInstituteCities,
    );
  });

  tearDown(() => local.close());

  group('ladderFor', () {
    test('tiers come top first; family, child and unlisted rows are left '
        'out; best rank first within a tier', () async {
      final ladder = await catalog.ladderFor('engineering');
      expect(ladder.map((t) => t.tier.label), ['INIs']);
      // Both rank 2 (Engineering vs Overall) → by name; no rank last.
      expect(_ids(ladder.single.institutes), [10, 11, 14]);
    });

    test('ranks, bands, NAAC grades and empty tiers', () async {
      final ladder = await catalog.ladderFor('law');
      expect(ladder.map((t) => t.tier.tier), [1, 2, 3, 4]);
      expect(_ids(ladder[0].institutes), [20, 21]); // rank 1, then a band
      expect(_ids(ladder[1].institutes), [10]);
      expect(ladder[1].institutes.single.ranking?.category, 'Overall');
      // NAAC "A" before an institute with neither rank nor grade.
      expect(_ids(ladder[2].institutes), [30, 31]);
      expect(ladder[3].institutes, isEmpty);
      expect(ladder[0].institutes.every((l) => l.tier == 1), isTrue);
    });

    test('an unknown domain has no ladder', () async {
      expect(await catalog.ladderFor('astrology'), isEmpty);
    });
  });

  group('filter', () {
    test('no criteria lists every listed top-level institute', () async {
      final all = await catalog.filter(const InstituteFilter());
      // Best rank first (Overall for no domain), then NAAC, then by name.
      // Law-only ranks do not count without a domain.
      expect(_ids(all), [11, 10, 30, 14, 20, 21, 31]);
      expect(all.every((l) => l.tier == null), isTrue);
    });

    test('domain and tier', () async {
      final law = await catalog.filter(
        const InstituteFilter(domainSlug: 'law'),
      );
      expect(_ids(law), [20, 21, 10, 30, 31]);
      final tier3 = await catalog.filter(
        const InstituteFilter(domainSlug: 'law', tier: 3),
      );
      expect(_ids(tier3), [30, 31]);
    });

    test('group, family, ownership and admits-students', () async {
      expect(
        _ids(await catalog.filter(const InstituteFilter(groupCode: 'G1'))),
        [11, 10, 14],
      );
      expect(
        _ids(
          await catalog.filter(
            const InstituteFilter(groupCode: 'G1', admitsStudentsOnly: true),
          ),
        ),
        [11, 10],
      );
      expect(
        _ids(await catalog.filter(const InstituteFilter(familySlug: 'nlu'))),
        [20, 21],
      );
      expect(
        _ids(
          await catalog.filter(
            const InstituteFilter(ownerships: {'private', 'trust'}),
          ),
        ),
        [30, 31],
      );
    });

    test('UGC verified only drops unverified private rows and keeps '
        'government ones', () async {
      final verified = await catalog.filter(
        const InstituteFilter(domainSlug: 'law', ugcVerifiedOnly: true),
      );
      expect(_ids(verified), [20, 21, 10, 30]);
    });

    test('a resolved state or city narrows the list', () async {
      final rajasthan = await places.resolve('RJ');
      expect(_ids(await catalog.filter(InstituteFilter(place: rajasthan))), [
        30,
        14,
        21,
        31,
      ]);
      final jaipur = await places.resolve('Jaipur');
      expect(
        _ids(
          await catalog.filter(
            InstituteFilter(domainSlug: 'law', place: jaipur),
          ),
        ),
        [30, 31],
      );
      final karnataka = await places.resolve('karnataka');
      expect(
        _ids(
          await catalog.filter(
            InstituteFilter(groupCode: 'G1', place: karnataka),
          ),
        ),
        isEmpty,
      );
    });
  });

  group('displayInfo', () {
    test('group and family names, domain rank, highlight and tier', () async {
      final info = await catalog.displayInfo(10, domainSlug: 'engineering');
      expect(info?.name, 'IIT Bombay');
      expect(info?.city, 'Mumbai');
      expect(info?.groupName, 'National flagship');
      expect(info?.familyName, 'IITs');
      expect(info?.ranking?.category, 'Engineering');
      expect(info?.ranking?.rank, 2);
      expect(info?.highlight, RankHighlight.top10);
      expect(info?.tier, 1);
      expect(info?.ugcBadge, UgcBadge.notApplicable);
      // Without a domain: Overall rank, no tier.
      final plain = await catalog.displayInfo(10);
      expect(plain?.ranking?.category, 'Overall');
      expect(plain?.tier, isNull);
    });

    test('a band within 100 is a top-100 highlight', () async {
      final info = await catalog.displayInfo(21, domainSlug: 'law');
      expect(info?.ranking?.rankBand, '51-100');
      expect(info?.highlight, RankHighlight.top100);
    });

    test('private rows show their UGC result and NAAC fallback', () async {
      final verified = await catalog.displayInfo(30, domainSlug: 'law');
      expect(verified?.ugcBadge, UgcBadge.verified);
      expect(verified?.ranking, isNull);
      expect(verified?.naacGrade, 'A');
      expect(verified?.highlight, RankHighlight.none);
      expect(verified?.familyName, isNull);
      final unverified = await catalog.displayInfo(31);
      expect(unverified?.ugcBadge, UgcBadge.notVerified);
      expect(unverified?.naacGrade, isNull);
    });

    test('child and unclassified institutes still get info', () async {
      final child = await catalog.displayInfo(12);
      expect(child?.classification?.parentInstituteId, 10);
      expect(child?.familyName, 'IITs');
      final unclassified = await catalog.displayInfo(32);
      expect(unclassified?.name, 'Unclassified College');
      expect(unclassified?.classification, isNull);
      expect(unclassified?.groupName, isNull);
      expect(unclassified?.ugcBadge, UgcBadge.notApplicable);
      expect(await catalog.displayInfo(999), isNull);
    });
  });

  test('without a taxonomy source the new APIs are empty', () async {
    final plain = InstituteCatalogService(local.getInstituteCatalog);
    expect(await plain.ladderFor('law'), isEmpty);
    expect(await plain.filter(const InstituteFilter()), isEmpty);
    expect(await plain.displayInfo(10), isNull);
  });

  test('existing search still works with a taxonomy source', () async {
    await catalog.ensureLoaded();
    expect(catalog.search('NLU Jodhpur').first.institute.id, 21);
    expect(catalog.idsInPlace('colleges in Jaipur'), {30, 31, 32});
  });

  group('badges', () {
    test('ugcBadgeFor follows ownership and the UGC flag', () {
      InstituteClassification row(String? ownership, bool? ugc) =>
          InstituteClassification(
            instituteId: 1,
            groupCode: 'G8',
            ownership: ownership,
            ugcVerified: ugc,
          );
      expect(
        InstituteCatalogService.ugcBadgeFor(row('private', true)),
        UgcBadge.verified,
      );
      expect(
        InstituteCatalogService.ugcBadgeFor(row('private', false)),
        UgcBadge.notVerified,
      );
      expect(
        InstituteCatalogService.ugcBadgeFor(row('trust', null)),
        UgcBadge.notVerified,
      );
      expect(
        InstituteCatalogService.ugcBadgeFor(row('state_govt', null)),
        UgcBadge.notApplicable,
      );
      expect(
        InstituteCatalogService.ugcBadgeFor(row(null, null)),
        UgcBadge.notApplicable,
      );
      expect(InstituteCatalogService.ugcBadgeFor(null), UgcBadge.notApplicable);
    });

    test('highlightFor uses the rank, else the end of the band', () {
      InstituteRanking ranked({int? rank, String? band}) => InstituteRanking(
        system: 'NIRF',
        year: 2025,
        category: 'Engineering',
        rank: rank,
        rankBand: band,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked(rank: 10)),
        RankHighlight.top10,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked(rank: 11)),
        RankHighlight.top100,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked(rank: 100)),
        RankHighlight.top100,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked(rank: 101)),
        RankHighlight.none,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked(band: '51-100')),
        RankHighlight.top100,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked(band: '101-150')),
        RankHighlight.none,
      );
      expect(
        InstituteCatalogService.highlightFor(ranked()),
        RankHighlight.none,
      );
      expect(InstituteCatalogService.highlightFor(null), RankHighlight.none);
    });
  });

  test('the bundled asset builds a real ladder', () async {
    // Read a private copy: another process may be rewriting the asset.
    final tmp = await Directory.systemTemp.createTemp('career_path_db');
    final copy = await File(
      'assets/data/career_path.db',
    ).copy(p.join(tmp.path, 'career_path.db'));
    final real = LocalDatabase.withDatabase(
      await databaseFactoryFfi.openDatabase(
        copy.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      ),
    );
    try {
      if ((await real.getDomainTiers('engineering')).isEmpty) return;
      final service = InstituteCatalogService(
        real.getInstituteCatalog,
        taxonomy: real,
      );
      final ladder = await service.ladderFor('engineering');
      final top = ladder.first.institutes;
      expect(top, isNotEmpty);
      expect(top.every((l) => l.tier == ladder.first.tier.tier), isTrue);
      expect(
        top.every((l) => l.classification?.isFamilyRecord == false),
        isTrue,
      );
      final bombay = top.firstWhere((l) => l.name.endsWith('Bombay'));
      expect(bombay.familyName, isNotNull);
      expect(bombay.highlight, RankHighlight.top10);
      expect(bombay.ugcBadge, UgcBadge.notApplicable);
    } finally {
      await real.close();
      await tmp.delete(recursive: true);
    }
  });
}
