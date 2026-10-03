import 'package:career_path/data/local_database.dart';
import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/screens/institute_ladder_screen.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/services/location_service.dart';
import 'package:career_path/services/route_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  "INSERT INTO states VALUES ('IN-MH', 27, 'IN', 'Maharashtra', 'state', 'west')",
  "INSERT INTO districts VALUES (1, 'IN-MH', 'Mumbai Suburban')",
  "INSERT INTO places VALUES (10, 1, 'Mumbai', 'city', 0)",
  "INSERT INTO institutes (id, name, city, district, state) "
      "VALUES (1, 'IIT Bombay', 'Mumbai', 'Mumbai Suburban', 'Maharashtra')",
  "INSERT INTO institution_groups VALUES ('G1', 'National flagship', NULL, 1)",
  "INSERT INTO families VALUES ('iit', 'Indian Institutes of Technology', 'G1', 'MoE', NULL, 23, '2026-10-01')",
  'INSERT INTO institute_classification (institute_id, group_code, family_slug, '
      'ownership, confidence) VALUES (1, \'G1\', \'iit\', \'central_govt\', \'high\')',
  "INSERT INTO institute_rankings (institute_id, system, year, category, rank, source_url) "
      "VALUES (1, 'NIRF', 2025, 'Engineering', 3, 'https://www.nirfindia.org/')",
  "INSERT INTO domains VALUES ('engineering', 'Engineering', 'degree', 'AICTE', 'JEE Main', 1), "
      "('ca_cma_cs', 'CA / CMA / CS', 'professional_body', 'ICAI, ICMAI, ICSI', 'Foundation, Executive', 10)",
  "INSERT INTO domain_tiers VALUES ('engineering', 1, 'Institutes of National Importance', 'G1', 'iit', 'JEE Advanced')",
  "INSERT INTO institute_domain_tiers VALUES (1, 'engineering', 1)",
  "INSERT INTO campuses VALUES (1, 1, NULL, 10, 1, NULL, NULL)",
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late LocalDatabase local;
  late InstituteCatalogService catalog;
  late LocationService locations;
  late RouteService routes;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    local = await openTaxonomyDb(_seed);
    locations = LocationService(
      loadStates: local.getStates,
      loadCities: local.getInstituteCities,
      loadDistricts: local.getDistricts,
      loadPlaces: local.getPlaces,
      loadPlaceAliases: local.getPlaceAliases,
    );
    catalog = InstituteCatalogService(
      local.getInstituteCatalog,
      taxonomy: local,
      locations: locations,
    );
    routes = RouteService(local);
  });

  tearDown(() => local.close());

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('engineering domain opens its ranked ladder and filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InstituteLadderScreen(
          domainSlug: 'engineering',
          catalog: catalog,
          locations: locations,
          routes: routes,
          prefs: prefs,
        ),
      ),
    );
    await pumpUntilFound(tester, find.byKey(const Key('ladder-overview')));
    await tester.pumpAndSettle();

    expect(find.text('College ladder'), findsOneWidget);
    expect(find.byKey(const Key('ladder-overview')), findsOneWidget);
    expect(find.textContaining('institution tiers'), findsOneWidget);
    expect(find.byKey(const Key('ladder-group-G1')), findsOneWidget);
    expect(find.byKey(const Key('institute-card-1')), findsNothing);

    await tester.tap(find.byKey(const Key('ladder-group-G1')));
    await tester.pumpAndSettle();
    expect(find.text('IIT Bombay'), findsOneWidget);
    expect(find.text('NIRF 2025 Engineering #3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ladder-filter-control')));
    await tester.pumpAndSettle();
    expect(find.text('Filter'), findsOneWidget);
    expect(find.byKey(const Key('ugc-verified-only')), findsOneWidget);
    expect(find.byKey(const Key('ladder-group-filter')), findsOneWidget);
    expect(find.byKey(const Key('ladder-family-filter')), findsOneWidget);
    expect(find.byKey(const Key('ladder-filter-apply')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ladder-filter-apply')));
    await pumpUntilFound(tester, find.byKey(const Key('ladder-group-G1')));
    expect(find.byKey(const Key('ladder-group-G1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ladder-group-G1')));
    await tester.pump();
    expect(find.byKey(const Key('institute-card-1')), findsOneWidget);
  });

  testWidgets(
    'professional body domain shows route steps, not a college ladder',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: InstituteLadderScreen(
            domainSlug: 'ca_cma_cs',
            catalog: catalog,
            locations: locations,
            routes: routes,
            prefs: prefs,
          ),
        ),
      );
      await pumpUntilFound(tester, find.text('Steps and entry routes'));

      expect(find.text('Steps and entry routes'), findsOneWidget);
      expect(find.text('Choose the professional body'), findsOneWidget);
      expect(find.text('ICAI · ICMAI · ICSI'), findsOneWidget);
      expect(find.text('Foundation · Executive'), findsOneWidget);
      expect(
        find.textContaining('alternatives, not consecutive'),
        findsOneWidget,
      );
      expect(find.text('College ladder'), findsNothing);
    },
  );
}
