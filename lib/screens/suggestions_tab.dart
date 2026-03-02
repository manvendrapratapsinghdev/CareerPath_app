import 'package:flutter/material.dart';

import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/profile_data.dart';
import '../services/career_data_service.dart';
import '../services/profile_service.dart';
import 'profile_screen.dart';
import 'sub_option_screen.dart';

class SuggestionsTab extends StatefulWidget {
  final ProfileService profileService;
  final CareerDataService careerDataService;

  const SuggestionsTab({
    super.key,
    required this.profileService,
    required this.careerDataService,
  });

  @override
  State<SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends State<SuggestionsTab> {
  ProfileData? _profile;
  List<CareerNode> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final profile = await widget.profileService.getProfile();
    List<CareerNode> categories = [];
    if (profile != null && profile.stream.isNotEmpty) {
      categories =
          widget.careerDataService.getCategoriesForStream(profile.stream);
    }
    if (mounted) {
      setState(() {
        _profile = profile;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  void _navigateToSubOption(CareerNode node) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubOptionScreen(
          careerDataService: widget.careerDataService,
          nodeId: node.id,
          breadcrumbs: [BreadcrumbEntry(nodeId: node.id, label: node.name)],
        ),
      ),
    );
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          profileService: widget.profileService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_profile == null || _profile!.stream.isEmpty) {
      return _buildNoStreamPrompt();
    }

    return _buildCategoryList();
  }

  Widget _buildNoStreamPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Complete your profile to see personalized suggestions',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _navigateToProfile,
              child: const Text('Go to Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    if (_categories.isEmpty) {
      return const Center(
        child: Text('No career categories available for your stream.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final node = _categories[index];
        return Card(
          child: ListTile(
            title: Text(node.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _navigateToSubOption(node),
          ),
        );
      },
    );
  }
}
