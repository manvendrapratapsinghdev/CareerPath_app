import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/screens/home_screen.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  late ProfileService profileService;
  late CareerDataService careerDataService;

  Future<void> initServices({Map<String, Object>? prefsValues}) async {
    SharedPreferences.setMockInitialValues(prefsValues ?? {});
    final prefs = await SharedPreferences.getInstance();
    profileService = ProfileService(ProfileRepository(prefs));
    careerDataService = CareerDataService(ApiClient());
  }

  Widget buildApp() {
    return MaterialApp(
      home: HomeScreen(
        profileService: profileService,
        careerDataService: careerDataService,
      ),
    );
  }

  group('HomeScreen', () {
    testWidgets('displays two tabs: Suggestions and Explore', (tester) async {
      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.tabs.length, 2);

      final tab0 = tabBar.tabs[0] as Tab;
      final tab1 = tabBar.tabs[1] as Tab;
      expect(tab0.text, 'Suggestions');
      expect(tab1.text, 'Explore');
    });

    testWidgets('Suggestions tab is selected by default', (tester) async {
      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // The Suggestions tab body should be visible
      // Since SuggestionsTab placeholder shows 'Suggestions' text,
      // and the tab label also says 'Suggestions', we check the TabBar state
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.tabs.length, 2);

      // DefaultTabController starts at index 0 (Suggestions)
      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(controller.index, 0);
    });

    testWidgets('displays Career as title', (tester) async {
      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Career'), findsOneWidget);
    });

    testWidgets('displays Career title even when profile exists', (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Career'), findsOneWidget);
    });

    testWidgets('has a profile avatar in the app bar', (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('avatar navigates to ProfileScreen', (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Bob',
        'profile_stream': 'commerce',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();

      // ProfileScreen should be displayed with Edit Profile title
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('can switch to Explore tab', (tester) async {
      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();

      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(controller.index, 1);
    });
  });
}
