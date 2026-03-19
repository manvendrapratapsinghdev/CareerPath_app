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
  String? _error;

  // Palettes cycle by index — no slug hardcoding needed.
  static const _iconPalette = <IconData>[
    Icons.school,
    Icons.biotech,
    Icons.calculate,
    Icons.science,
    Icons.design_services,
    Icons.account_balance,
    Icons.trending_up,
    Icons.gavel,
    Icons.people,
    Icons.translate,
    Icons.movie_creation,
    Icons.business_center,
    Icons.theater_comedy,
    Icons.work_outline,
  ];

  static const _colorPalette = <Color>[
    Color(0xFF4CAF50),
    Color(0xFF009688),
    Color(0xFF2196F3),
    Color(0xFF3F51B5),
    Color(0xFF673AB7),
    Color(0xFF795548),
    Color(0xFF00BCD4),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFFFF5722),
    Color(0xFFF44336),
    Color(0xFF607D8B),
    Color(0xFF8D6E63),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() { _isLoading = true; _error = null; });
    widget.careerDataService.reset();
    try {
      final profile = await widget.profileService.getProfile();
      List<CareerNode> categories = [];
      if (profile != null && profile.stream.isNotEmpty) {
        await widget.careerDataService.ensureInitialized();
        categories = await widget.careerDataService
            .fetchStreamCategories(profile.stream);
      }
      if (mounted) {
        setState(() {
          _profile = profile;
          _categories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to connect to server. Check your connection and retry.';
        });
      }
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

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_profile == null || _profile!.stream.isEmpty) {
      return _buildNoStreamPrompt();
    }

    return _buildCategoryList();
  }

  Widget _buildNoStreamPrompt() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_add_alt_1,
                  size: 48, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              'Complete your profile to see personalized suggestions',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _navigateToProfile,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Go to Profile'),
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

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length + 1,
        itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 4),
            child: Text(
              'Explore career paths in your stream',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        final node = _categories[index - 1];
        final i = index - 1;
        final icon = _iconPalette[i % _iconPalette.length];
        final color = _colorPalette[i % _colorPalette.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _navigateToSubOption(node),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (node.childIds.isNotEmpty)
                            Text(
                              '${node.childIds.length} paths available',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
      );
  }
}
