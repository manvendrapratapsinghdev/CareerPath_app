import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'data/profile_repository.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/api_client.dart';
import 'services/career_data_service.dart';
import 'services/network_service.dart';
import 'services/profile_service.dart';
import 'widgets/network_aware_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final profileRepo = ProfileRepository(prefs);
  final profileService = ProfileService(profileRepo);
  final careerDataService = CareerDataService(ApiClient());
  final networkService = NetworkService();

  // Check profile from local storage only — no network call here.
  final hasProfile = await profileService.isProfileComplete();

  runApp(CareerPathApp(
    profileService: profileService,
    careerDataService: careerDataService,
    networkService: networkService,
    hasProfile: hasProfile,
  ));
}

class CareerPathApp extends StatelessWidget {
  final ProfileService profileService;
  final CareerDataService careerDataService;
  final NetworkService networkService;
  final bool hasProfile;

  const CareerPathApp({
    super.key,
    required this.profileService,
    required this.careerDataService,
    required this.networkService,
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
      routes: {
        '/home': (_) => HomeScreen(
              profileService: profileService,
              careerDataService: careerDataService,
            ),
      },
      home: NetworkAwareWrapper(
        networkService: networkService,
        child: hasProfile
            ? HomeScreen(
                profileService: profileService,
                careerDataService: careerDataService,
              )
            : ProfileScreen(profileService: profileService),
      ),
    );
  }
}
