import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/main.dart';
import 'package:career_path/data/bookmark_repository.dart';
import 'package:career_path/data/exploration_repository.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/bookmark_service.dart';
import 'package:career_path/services/exploration_service.dart';
import 'package:career_path/services/theme_service.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/analytics_service.dart';
import 'package:career_path/services/network_service.dart';
import 'package:career_path/services/profile_service.dart';
import 'package:career_path/data/recently_viewed_repository.dart';
import 'package:career_path/services/recently_viewed_service.dart';
import 'package:career_path/data/rate_prompt_repository.dart';
import 'package:career_path/services/rate_prompt_service.dart';
import 'package:career_path/services/feedback_service.dart';
import 'package:career_path/services/locale_service.dart';

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
    final recentlyViewedService = RecentlyViewedService(RecentlyViewedRepository(prefs));
    final ratePromptService = RatePromptService(RatePromptRepository(prefs));
    final feedbackService = FeedbackService();
    final themeService = ThemeService(prefs);
    final localeService = LocaleService(prefs);

    await tester.pumpWidget(CareerPathApp(
      prefs: prefs,
      profileService: profileService,
      bookmarkService: bookmarkService,
      explorationService: explorationService,
      recentlyViewedService: recentlyViewedService,
      ratePromptService: ratePromptService,
      careerDataService: careerDataService,
      networkService: networkService,
      analyticsService: analyticsService,
      feedbackService: feedbackService,
      themeService: themeService,
      localeService: localeService,
      hasProfile: false,
      onboardingSeen: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
  });
}
