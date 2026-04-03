import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/models/profile_data.dart';
import 'package:career_path/screens/profile_screen.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  late ProfileService profileService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    profileService = ProfileService(ProfileRepository(prefs));
  });

  Widget buildApp({ProfileData? existingProfile}) {
    return MaterialApp(
      routes: {
        '/home': (_) => const Scaffold(body: Text('Home Screen')),
      },
      home: ProfileScreen(
        profileService: profileService,
        existingProfile: existingProfile,
      ),
    );
  }

  group('ProfileScreen', () {
    testWidgets('displays name field and stream selection cards',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);
      expect(find.text('Commerce'), findsOneWidget);
      expect(find.text('Art'), findsOneWidget);
    });

    testWidgets('displays Get Started and Skip for now buttons',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('shows Welcome! title for new profile', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Welcome!'), findsOneWidget);
    });

    testWidgets('shows Edit Profile title when editing', (tester) async {
      await tester.pumpWidget(buildApp(
        existingProfile: ProfileData(name: 'Alice', stream: 'science'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('pre-fills name when editing', (tester) async {
      await tester.pumpWidget(buildApp(
        existingProfile: ProfileData(name: 'Alice', stream: 'science'),
      ));
      await tester.pumpAndSettle();

      final nameField =
          tester.widget<TextFormField>(find.byType(TextFormField));
      expect(nameField.controller?.text, 'Alice');
    });

    testWidgets('validates name is not empty on save', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Select a stream first by tapping the Science card
      await tester.tap(find.text('Science'));
      await tester.pump();

      // Scroll down to reach the button
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Tap save without entering name
      await tester.tap(find.text('Get Started'));
      await tester.pump();

      expect(find.text('Please enter your name'), findsOneWidget);
    });

    testWidgets('saves profile and navigates to home', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Enter name
      await tester.enterText(find.byType(TextFormField), 'Bob');

      // Select stream by tapping Commerce card
      await tester.tap(find.text('Commerce'));
      await tester.pump();

      // Scroll down to reach the button
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Tap save
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // Should navigate to home
      expect(find.text('Home Screen'), findsOneWidget);

      // Verify profile was saved
      final profile = await profileService.getProfile();
      expect(profile?.name, 'Bob');
      expect(profile?.stream, 'commerce');
    });

    testWidgets('skip navigates to home without saving', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Scroll down to reach skip button
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      // Should navigate to home
      expect(find.text('Home Screen'), findsOneWidget);

      // Profile should not be saved
      final profile = await profileService.getProfile();
      expect(profile, isNull);
    });
  });
}
