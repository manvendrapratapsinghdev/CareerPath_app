import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/screens/suggestions_tab.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  late ProfileService profileService;
  late CareerDataService careerDataService;

  final testStreams = [
    StreamModel(
        id: 'science', name: 'Science', categoryIds: ['sci_maths', 'sci_bio']),
    StreamModel(
        id: 'commerce',
        name: 'Commerce',
        categoryIds: ['comm_ca', 'comm_fin']),
  ];

  final testNodes = <String, CareerNode>{
    'sci_maths': CareerNode(
        id: 'sci_maths', name: 'Maths', childIds: ['btech']),
    'sci_bio': CareerNode(id: 'sci_bio', name: 'Bio', childIds: []),
    'btech':
        CareerNode(id: 'btech', name: 'B.Tech', parentId: 'sci_maths', childIds: []),
    'comm_ca': CareerNode(
        id: 'comm_ca', name: 'Chartered Accountancy', childIds: []),
    'comm_fin': CareerNode(id: 'comm_fin', name: 'Finance', childIds: []),
  };

  Future<void> initServices({Map<String, Object>? prefsValues}) async {
    SharedPreferences.setMockInitialValues(prefsValues ?? {});
    final prefs = await SharedPreferences.getInstance();
    profileService = ProfileService(ProfileRepository(prefs));
    careerDataService = CareerDataService(ApiClient());
    careerDataService.initializeWithData(testStreams, testNodes);
  }

  Widget buildApp() {
    return MaterialApp(
      home: Scaffold(
        body: SuggestionsTab(
          profileService: profileService,
          careerDataService: careerDataService,
        ),
      ),
    );
  }

  group('SuggestionsTab', () {
    testWidgets('shows prompt when no profile saved', (tester) async {
      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Personalize your feed'), findsOneWidget);
      expect(find.text('Set Up Profile'), findsOneWidget);
    });

    testWidgets('Set Up Profile button navigates to ProfileScreen',
        (tester) async {
      await initServices();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Up Profile'));
      await tester.pumpAndSettle();

      // ProfileScreen should show the welcome text
      expect(find.text('Welcome!'), findsOneWidget);
    });

    testWidgets('shows career categories when stream is saved',
        (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Maths'), findsOneWidget);
      expect(find.text('Bio'), findsOneWidget);
    });

    testWidgets('categories are displayed as cards with chevron',
        (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Bob',
        'profile_stream': 'commerce',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Chartered Accountancy'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);
      // 2 category cards (dashboard header is a Container, not a Card)
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    });

    testWidgets('shows dashboard header with stream info', (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Science Stream'), findsOneWidget);
      expect(find.text('2 career paths available'), findsOneWidget);
    });

    testWidgets('tapping a category navigates to SubOptionScreen',
        (tester) async {
      await initServices(prefsValues: {
        'profile_name': 'Alice',
        'profile_stream': 'science',
      });
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maths'));
      await tester.pumpAndSettle();

      // SubOptionScreen shows child nodes for Maths
      expect(find.text('B.Tech'), findsOneWidget);
    });
  });
}
