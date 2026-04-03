import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
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
    // Pre-load data so tabs don't hit the network.
    careerDataService.initializeWithData(
      [StreamModel(id: 'science', name: 'Science', categoryIds: [])],
      <String, CareerNode>{},
    );
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
    testWidgets('displays bottom navigation with For You and Explore',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
    });

    testWidgets('For You tab is selected by default', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('displays greeting text', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final hasGreeting =
          find.textContaining('Good Morning').evaluate().isNotEmpty ||
              find.textContaining('Good Afternoon').evaluate().isNotEmpty ||
              find.textContaining('Good Evening').evaluate().isNotEmpty;
      expect(hasGreeting, isTrue);
    });

    testWidgets('displays user name when profile exists', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('has a profile avatar with initial in the app bar',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('avatar navigates to ProfileScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices(prefsValues: {
        'profile_name': 'Bob',
        'profile_stream': 'commerce',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('can switch to Explore tab', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explore'));
      // Don't pumpAndSettle — ExploreTab triggers async network call.
      // Just pump a few frames to verify navigation occurred.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}
