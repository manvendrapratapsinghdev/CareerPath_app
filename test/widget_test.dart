import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/main.dart';
import 'package:career_path/data/bookmark_repository.dart';
import 'package:career_path/data/exploration_repository.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/bookmark_service.dart';
import 'package:career_path/services/exploration_service.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/analytics_service.dart';
import 'package:career_path/services/network_service.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  testWidgets('App launches and shows ProfileScreen when no profile',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final profileService = ProfileService(ProfileRepository(prefs));
    final careerDataService = CareerDataService(ApiClient());
    final networkService = NetworkService();
    final analyticsService = AnalyticsService();

    final bookmarkService = BookmarkService(BookmarkRepository(prefs));
    final explorationService = ExplorationService(ExplorationRepository(prefs));

    await tester.pumpWidget(CareerPathApp(
      profileService: profileService,
      bookmarkService: bookmarkService,
      explorationService: explorationService,
      careerDataService: careerDataService,
      networkService: networkService,
      analyticsService: analyticsService,
      hasProfile: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
  });
}
