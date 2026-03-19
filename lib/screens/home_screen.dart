import 'package:flutter/material.dart';

import '../models/profile_data.dart';
import '../services/career_data_service.dart';
import '../services/profile_service.dart';
import 'explore_tab.dart';
import 'profile_screen.dart';
import 'suggestions_tab.dart';

class HomeScreen extends StatefulWidget {
  final ProfileService profileService;
  final CareerDataService careerDataService;

  const HomeScreen({
    super.key,
    required this.profileService,
    required this.careerDataService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProfileData? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await widget.profileService.getProfile();
    if (mounted) {
      setState(() => _profile = profile);
    }
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          profileService: widget.profileService,
          existingProfile: _profile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Career'),
          actions: [
            GestureDetector(
              onTap: _navigateToEditProfile,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    _profile?.name.isNotEmpty == true
                        ? _profile!.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Column(
              children: [
                const Divider(height: 1, thickness: 0.5),
                TabBar(
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(icon: Icon(Icons.lightbulb_outline), text: 'Suggestions'),
                    Tab(icon: Icon(Icons.explore_outlined), text: 'Explore'),
                  ],
                ),
                const Divider(height: 1, thickness: 0.5),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            SuggestionsTab(
              profileService: widget.profileService,
              careerDataService: widget.careerDataService,
            ),
            ExploreTab(careerDataService: widget.careerDataService),
          ],
        ),
      ),
    );
  }
}
