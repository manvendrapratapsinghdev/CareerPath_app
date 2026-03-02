import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/career_paths_json_parser.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/data/streams_json_parser.dart';
import 'package:career_path/main.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  testWidgets('App launches and shows ProfileScreen when no profile',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final profileService = ProfileService(ProfileRepository(prefs));
    final careerDataService = CareerDataService(
      StreamsJsonParser(),
      CareerPathsJsonParser(),
    );

    await tester.pumpWidget(CareerPathApp(
      profileService: profileService,
      careerDataService: careerDataService,
      hasProfile: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Create Profile'), findsOneWidget);
  });
}
