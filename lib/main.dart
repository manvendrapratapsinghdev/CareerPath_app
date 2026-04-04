import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'data/bookmark_repository.dart';
import 'data/profile_repository.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/analytics_service.dart';
import 'services/api_client.dart';
import 'services/bookmark_service.dart';
import 'services/career_data_service.dart';
import 'services/network_service.dart';
import 'services/profile_service.dart';
import 'widgets/network_aware_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured yet — analytics will be no-op.
  }

  final prefs = await SharedPreferences.getInstance();
  final profileRepo = ProfileRepository(prefs);
  final profileService = ProfileService(profileRepo);
  final bookmarkService = BookmarkService(BookmarkRepository(prefs));
  final careerDataService = CareerDataService(ApiClient());
  final networkService = NetworkService();
  final analyticsService = AnalyticsService();

  // Check profile from local storage only — no network call here.
  final hasProfile = await profileService.isProfileComplete();

  runApp(CareerPathApp(
    profileService: profileService,
    bookmarkService: bookmarkService,
    careerDataService: careerDataService,
    networkService: networkService,
    analyticsService: analyticsService,
    hasProfile: hasProfile,
  ));
}

class CareerPathApp extends StatelessWidget {
  final ProfileService profileService;
  final BookmarkService bookmarkService;
  final CareerDataService careerDataService;
  final NetworkService networkService;
  final AnalyticsService analyticsService;
  final bool hasProfile;

  const CareerPathApp({
    super.key,
    required this.profileService,
    required this.bookmarkService,
    required this.careerDataService,
    required this.networkService,
    required this.analyticsService,
    required this.hasProfile,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Career Path Guidance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      navigatorObservers: [analyticsService.observer],
      routes: {
        '/home': (_) => HomeScreen(
              profileService: profileService,
              bookmarkService: bookmarkService,
              careerDataService: careerDataService,
              analyticsService: analyticsService,
            ),
      },
      home: NetworkAwareWrapper(
        networkService: networkService,
        child: hasProfile
            ? HomeScreen(
                profileService: profileService,
                bookmarkService: bookmarkService,
                careerDataService: careerDataService,
                analyticsService: analyticsService,
              )
            : ProfileScreen(
                profileService: profileService,
                analyticsService: analyticsService,
              ),
      ),
    );
  }
}
