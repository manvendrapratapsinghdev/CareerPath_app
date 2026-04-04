import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'data/bookmark_repository.dart';
import 'data/exploration_repository.dart';
import 'data/profile_repository.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'services/analytics_service.dart';
import 'services/api_client.dart';
import 'services/bookmark_service.dart';
import 'services/career_data_service.dart';
import 'services/exploration_service.dart';
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
  final explorationService = ExplorationService(ExplorationRepository(prefs));
  final careerDataService = CareerDataService(ApiClient());
  final networkService = NetworkService();
  final analyticsService = AnalyticsService();

  // Check profile and onboarding from local storage — no network call here.
  final hasProfile = await profileService.isProfileComplete();
  final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;

  runApp(CareerPathApp(
    prefs: prefs,
    profileService: profileService,
    bookmarkService: bookmarkService,
    explorationService: explorationService,
    careerDataService: careerDataService,
    networkService: networkService,
    analyticsService: analyticsService,
    hasProfile: hasProfile,
    onboardingSeen: onboardingSeen,
  ));
}

class CareerPathApp extends StatelessWidget {
  final SharedPreferences prefs;
  final ProfileService profileService;
  final BookmarkService bookmarkService;
  final ExplorationService explorationService;
  final CareerDataService careerDataService;
  final NetworkService networkService;
  final AnalyticsService analyticsService;
  final bool hasProfile;
  final bool onboardingSeen;

  const CareerPathApp({
    super.key,
    required this.prefs,
    required this.profileService,
    required this.bookmarkService,
    required this.explorationService,
    required this.careerDataService,
    required this.networkService,
    required this.analyticsService,
    required this.hasProfile,
    required this.onboardingSeen,
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
              explorationService: explorationService,
              careerDataService: careerDataService,
              analyticsService: analyticsService,
            ),
        '/profile': (_) => ProfileScreen(
              profileService: profileService,
              analyticsService: analyticsService,
            ),
      },
      home: NetworkAwareWrapper(
        networkService: networkService,
        child: _buildInitialScreen(),
      ),
    );
  }

  Widget _buildInitialScreen() {
    if (hasProfile) {
      return HomeScreen(
        profileService: profileService,
        bookmarkService: bookmarkService,
        explorationService: explorationService,
        careerDataService: careerDataService,
        analyticsService: analyticsService,
      );
    }
    if (!onboardingSeen) {
      return _OnboardingWrapper(prefs: prefs);
    }
    return ProfileScreen(
      profileService: profileService,
      analyticsService: analyticsService,
    );
  }
}

class _OnboardingWrapper extends StatelessWidget {
  final SharedPreferences prefs;

  const _OnboardingWrapper({required this.prefs});

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      onComplete: () async {
        await prefs.setBool('onboarding_seen', true);
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/profile');
        }
      },
    );
  }
}
