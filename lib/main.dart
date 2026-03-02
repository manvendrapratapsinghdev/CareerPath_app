import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/career_paths_json_parser.dart';
import 'data/profile_repository.dart';
import 'data/streams_json_parser.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/career_data_service.dart';
import 'services/profile_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    final profileRepo = ProfileRepository(prefs);
    final profileService = ProfileService(profileRepo);

    final careerDataService = CareerDataService(
      StreamsJsonParser(),
      CareerPathsJsonParser(),
    );
    await careerDataService.initialize();

    final hasProfile = await profileService.isProfileComplete();

    runApp(CareerPathApp(
      profileService: profileService,
      careerDataService: careerDataService,
      hasProfile: hasProfile,
    ));
  } catch (e) {
    runApp(const _ErrorApp());
  }
}

class CareerPathApp extends StatelessWidget {
  final ProfileService profileService;
  final CareerDataService careerDataService;
  final bool hasProfile;

  const CareerPathApp({
    super.key,
    required this.profileService,
    required this.careerDataService,
    required this.hasProfile,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Career Path Guidance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routes: {
        '/home': (_) => HomeScreen(
              profileService: profileService,
              careerDataService: careerDataService,
            ),
      },
      home: hasProfile
          ? HomeScreen(
              profileService: profileService,
              careerDataService: careerDataService,
            )
          : ProfileScreen(profileService: profileService),
    );
  }
}

class _ErrorApp extends StatelessWidget {
  const _ErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to initialize the app. Please restart.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
