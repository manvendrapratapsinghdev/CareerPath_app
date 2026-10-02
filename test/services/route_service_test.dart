import 'package:career_path/data/local_database.dart';
import 'package:career_path/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  "INSERT INTO career_nodes VALUES (1, 'science', 1, NULL, 'Science', NULL), "
      "(2, 'engineering', 1, 1, 'Engineering', NULL), "
      "(3, 'civil', 1, 2, 'Civil Engineering', NULL), "
      "(4, 'law', 3, NULL, 'Law', NULL), "
      "(5, 'ca', 2, NULL, 'Chartered Accountant', NULL), "
      "(6, 'upsc', 3, NULL, 'Civil services', NULL)",
  "INSERT INTO domains VALUES ('engineering', 'Engineering', 'degree', 'AICTE', "
      "'JEE Advanced; JEE Main', 1), "
      "('law', 'Law', 'degree', 'BCI', 'CLAT; AILET', 17), "
      "('ca_cma_cs', 'CA / CMA / CS', 'professional_body', 'ICAI', "
      "'CA Foundation', 15), "
      "('civil_services', 'Civil services', 'exam', NULL, 'UPSC CSE', 18), "
      "('aviation_maritime', 'Aviation', 'mixed', NULL, NULL, 20)",
  "INSERT INTO domain_nodes VALUES (2, 'engineering'), (4, 'law'), "
      "(5, 'ca_cma_cs'), (6, 'civil_services')",
  "INSERT INTO domain_tiers VALUES "
      "('law', 2, 'Institutes of National Importance', 'G1', NULL, NULL), "
      "('law', 1, 'National Law Universities', 'G4', 'nlu', 'CLAT; LSAT India'), "
      "('engineering', 1, 'INIs', 'G1', NULL, 'JEE Advanced'), "
      "('ca_cma_cs', 1, 'Professional bodies', 'G10a', 'icai', NULL)",
];

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late RouteService routes;

  setUp(() async {
    local = await openTaxonomyDb(_seed);
    routes = RouteService(local);
  });

  tearDown(() => local.close());

  test('a node inherits its ancestor domain, ladder and exams', () async {
    final route = await routes.routeForNode(3); // Civil → Engineering
    expect(route?.domain.slug, 'engineering');
    expect(route?.type, RouteType.degree);
    expect(route?.tierLabels, ['INIs']);
    // Domain exams first; the tier's repeat of JEE Advanced is not doubled.
    expect(route?.entryExams, ['JEE Advanced', 'JEE Main']);
    expect(route?.hasCollegeLadder, isTrue);
  });

  test(
    'a node slug resolves the same inherited route as its numeric ID',
    () async {
      final route = await routes.routeForNodeKey('civil');
      expect(route?.domain.slug, 'engineering');
      expect(route?.tierLabels, ['INIs']);
    },
  );

  test('tiers come top first and add tier-only exams', () async {
    final route = await routes.routeForDomain('law');
    expect(route?.tierLabels, [
      'National Law Universities',
      'Institutes of National Importance',
    ]);
    expect(route?.tiers.first.familySlugList, ['nlu']);
    expect(route?.entryExams, ['CLAT', 'AILET', 'LSAT India']);
  });

  test('route types are read from the domain', () async {
    final ca = await routes.routeForNode(5);
    expect(ca?.type, RouteType.professionalBody);
    expect(ca?.hasCollegeLadder, isFalse);
    final upsc = await routes.routeForNode(6);
    expect(upsc?.type, RouteType.exam);
    expect(upsc?.tiers, isEmpty);
    expect(upsc?.entryExams, ['UPSC CSE']);
    final aviation = await routes.routeForDomain('aviation_maritime');
    expect(aviation?.type, RouteType.mixed);
    expect(aviation?.hasCollegeLadder, isTrue);
    expect(aviation?.entryExams, isEmpty);
  });

  test('no domain gives no route', () async {
    expect(await routes.routeForNode(1), isNull); // Science root, unmapped
    expect(await routes.routeForNode(999), isNull);
    expect(await routes.routeForDomain('astrology'), isNull);
  });

  test('RouteType.parse maps DB values, unknown as degree', () {
    expect(RouteType.parse('degree'), RouteType.degree);
    expect(RouteType.parse('professional_body'), RouteType.professionalBody);
    expect(RouteType.parse('exam'), RouteType.exam);
    expect(RouteType.parse('mixed'), RouteType.mixed);
    expect(RouteType.parse(null), RouteType.degree);
    expect(RouteType.parse('other'), RouteType.degree);
  });
}
