import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'data/bookmark_repository.dart';
import 'data/exploration_repository.dart';
import 'data/leaf_details_cache.dart';
import 'data/local_database.dart';
import 'data/local_data_source.dart';
import 'data/profile_repository.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'services/analytics_service.dart';
import 'services/bookmark_service.dart';
import 'services/career_data_service.dart';
import 'services/exploration_service.dart';
import 'services/network_service.dart';
import 'services/profile_service.dart';
import 'services/theme_service.dart';
import 'widgets/network_aware_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured — analytics will be no-op.
  }

  final prefs = await SharedPreferences.getInstance();
  final profileRepo = ProfileRepository(prefs);
  final profileService = ProfileService(profileRepo);
  final leafDetailsCache = LeafDetailsCache(prefs);
  final bookmarkService = BookmarkService(BookmarkRepository(prefs), leafDetailsCache);
  final explorationService = ExplorationService(ExplorationRepository(prefs));

  final localDb = LocalDatabase();
  await localDb.init();
  final careerDataService = CareerDataService(LocalDataSource(localDb));
  final networkService = NetworkService();
  final analyticsService = AnalyticsService();
  final themeService = ThemeService(prefs);

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
    themeService: themeService,
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
  final ThemeService themeService;
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
    required this.themeService,
    required this.hasProfile,
    required this.onboardingSeen,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) => MaterialApp(
      title: 'Career Path Guidance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeService.themeMode,
      navigatorObservers: [analyticsService.observer],
      routes: {
        '/home': (_) => HomeScreen(
              profileService: profileService,
              bookmarkService: bookmarkService,
              explorationService: explorationService,
              careerDataService: careerDataService,
              analyticsService: analyticsService,
              themeService: themeService,
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
        themeService: themeService,
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
