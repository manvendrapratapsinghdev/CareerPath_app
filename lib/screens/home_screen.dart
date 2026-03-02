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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Career Map'),
          actions: [
            GestureDetector(
              onTap: _navigateToEditProfile,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    _profile?.name.isNotEmpty == true
                        ? _profile!.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Suggestions (for you)'),
              Tab(text: 'Explore'),
            ],
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
