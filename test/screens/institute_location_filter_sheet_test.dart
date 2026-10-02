import 'package:career_path/models/district_region.dart';
import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/models/institute_location_filter.dart';
import 'package:career_path/models/place_record.dart';
import 'package:career_path/models/state_region.dart';
import 'package:career_path/screens/institute_location_filter_sheet.dart';
import 'package:career_path/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('state, district and city cascade and persist on apply', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final locations = LocationService(
      loadStates: () async => const [
        StateRegion(
          code: 'IN-MH',
          lgdCode: 27,
          name: 'Maharashtra',
          kind: 'state',
          zone: 'west',
        ),
      ],
      loadCities: () async => const [],
      loadDistricts: () async => const [
        DistrictRegion(lgdCode: 1, stateCode: 'IN-MH', name: 'Mumbai Suburban'),
      ],
      loadPlaces: () async => const [
        PlaceRecord(
          id: 10,
          districtLgd: 1,
          districtName: 'Mumbai Suburban',
          stateCode: 'IN-MH',
          name: 'Mumbai',
          kind: 'city',
        ),
      ],
      loadPlaceAliases: () async => const [],
    );

    InstituteLocationFilter? applied;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  applied = await showInstituteLocationFilterSheet(
                    context,
                    locations: locations,
                    prefs: prefs,
                  );
                },
                child: const Text('Open filter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open filter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-state')), findsOneWidget);
    expect(find.byKey(const Key('location-district')), findsOneWidget);

    await tester.tap(find.byKey(const Key('location-state')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maharashtra').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location-district')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mumbai Suburban').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location-city')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mumbai').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-filter-apply')));
    await tester.pumpAndSettle();

    expect(applied?.stateCode, 'IN-MH');
    expect(applied?.districtLgd, 1);
    expect(applied?.placeId, 10);
    expect(
      InstituteLocationFilter.decode(
        prefs.getString(instituteLocationPreferenceKey),
      ).placeId,
      10,
    );
  });
}
