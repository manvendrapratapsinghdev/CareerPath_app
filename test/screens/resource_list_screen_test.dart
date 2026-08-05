import 'package:career_path/models/institute.dart';
import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/screens/resource_filter_screen.dart';
import 'package:career_path/screens/resource_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const institutes = [
    Institute(
      id: 1,
      name: 'Amity University Rajasthan',
      district: 'Jaipur',
      state: 'Rajasthan',
    ),
    Institute(
      id: 2,
      name: 'Career Point University',
      district: 'Kota',
      state: 'Rajasthan',
    ),
    Institute(
      id: 3,
      name: 'Mohanlal Sukhadia University',
      district: 'Udaipur',
      state: 'Rajasthan',
    ),
  ];

  Widget buildScreen() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ResourceListScreen<Institute>(
        title: 'Top Institutes',
        searchHint: 'Search',
        noResultsTitle: 'No results',
        noResultsSubtitle: 'Try a different search term',
        items: institutes,
        searchableText: (institute) => [
          institute.name,
          institute.district,
          institute.state,
        ].whereType<String>().join(' '),
        itemBuilder: (institute) => Text(institute.name),
        filterOptions: const [
          ResourceFilterOption(id: 'Jaipur', label: 'Jaipur', count: 1),
          ResourceFilterOption(id: 'Kota', label: 'Kota', count: 1),
          ResourceFilterOption(id: 'Udaipur', label: 'Udaipur', count: 1),
        ],
        filterPredicate: (institute, selectedLocations) =>
            selectedLocations.contains(institute.district),
      ),
    );
  }

  testWidgets('shows the complete local list before searching', (tester) async {
    await tester.pumpWidget(buildScreen());

    expect(find.text('Amity University Rajasthan'), findsOneWidget);
    expect(find.text('Career Point University'), findsOneWidget);
    expect(find.text('Mohanlal Sukhadia University'), findsOneWidget);
  });

  testWidgets('filters the loaded list using name and location', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());

    await tester.enterText(
      find.byKey(const Key('resource-list-search')),
      'kota career',
    );
    await tester.pump();

    expect(find.text('Career Point University'), findsOneWidget);
    expect(find.text('Amity University Rajasthan'), findsNothing);
    expect(find.text('Mohanlal Sukhadia University'), findsNothing);
  });

  testWidgets('shows an empty state and can clear the query', (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.enterText(
      find.byKey(const Key('resource-list-search')),
      'not present',
    );
    await tester.pump();

    expect(find.text('No results'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.text('Amity University Rajasthan'), findsOneWidget);
    expect(find.text('Career Point University'), findsOneWidget);
    expect(find.text('Mohanlal Sukhadia University'), findsOneWidget);
  });

  testWidgets('opens a location screen and applies a district filter', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.byKey(const Key('resource-filter-button')));
    await tester.pumpAndSettle();

    expect(find.text('Filter by location'), findsOneWidget);
    expect(find.text('Jaipur'), findsOneWidget);
    expect(find.text('Kota'), findsOneWidget);
    expect(find.text('Udaipur'), findsOneWidget);

    await tester.tap(find.byKey(const Key('location-filter-Kota')));
    await tester.tap(find.byKey(const Key('location-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Career Point University'), findsOneWidget);
    expect(find.text('Amity University Rajasthan'), findsNothing);
    expect(find.text('Mohanlal Sukhadia University'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Kota'), findsOneWidget);
  });

  testWidgets('searches the available locations before selection', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.byKey(const Key('resource-filter-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-filter-search')),
      'udai',
    );
    await tester.pump();

    expect(find.text('Udaipur'), findsOneWidget);
    expect(find.text('Jaipur'), findsNothing);
    expect(find.text('Kota'), findsNothing);
  });
}
