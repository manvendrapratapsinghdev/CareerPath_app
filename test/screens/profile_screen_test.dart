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
    testWidgets('displays name field and stream radio buttons', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);
      expect(find.text('Commerce'), findsOneWidget);
      expect(find.text('Art'), findsOneWidget);
    });

    testWidgets('displays Save and Skip buttons', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('shows Create Profile title for new profile', (tester) async {
      await tester.pumpWidget(buildApp());

      expect(find.text('Create Profile'), findsOneWidget);
    });

    testWidgets('shows Edit Profile title when editing', (tester) async {
      await tester.pumpWidget(buildApp(
        existingProfile: ProfileData(name: 'Alice', stream: 'science'),
      ));

      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('pre-fills name and stream when editing', (tester) async {
      await tester.pumpWidget(buildApp(
        existingProfile: ProfileData(name: 'Alice', stream: 'science'),
      ));

      final nameField = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(nameField.controller?.text, 'Alice');

      // Science radio should be selected
      final scienceRadio = tester.widget<RadioListTile<String>>(
        find.widgetWithText(RadioListTile<String>, 'Science'),
      );
      expect(scienceRadio.checked, isTrue);
    });

    testWidgets('validates name is not empty on save', (tester) async {
      await tester.pumpWidget(buildApp());

      // Select a stream first
      await tester.tap(find.text('Science'));
      await tester.pump();

      // Tap save without entering name
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Please enter your name'), findsOneWidget);
    });

    testWidgets('saves profile and navigates to home', (tester) async {
      await tester.pumpWidget(buildApp());

      // Enter name
      await tester.enterText(find.byType(TextFormField), 'Bob');

      // Select stream
      await tester.tap(find.text('Commerce'));
      await tester.pump();

      // Tap save
      await tester.tap(find.text('Save'));
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

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Should navigate to home
      expect(find.text('Home Screen'), findsOneWidget);

      // Profile should not be saved
      final profile = await profileService.getProfile();
      expect(profile, isNull);
    });
  });
}
