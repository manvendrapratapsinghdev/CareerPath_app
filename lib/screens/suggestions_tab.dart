import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/profile_data.dart';
import '../services/analytics_service.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../services/exploration_service.dart';
import '../services/recently_viewed_service.dart';
import '../services/profile_service.dart';
import '../widgets/accent_icon_box.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_transitions.dart';
import '../widgets/shimmer_loading.dart';
import 'profile_screen.dart';
import 'sub_option_screen.dart';

class SuggestionsTab extends StatefulWidget {
  final ProfileService profileService;
  final BookmarkService? bookmarkService;
  final ExplorationService? explorationService;
  final RecentlyViewedService? recentlyViewedService;
  final CareerDataService careerDataService;
  final AnalyticsService? analyticsService;

  const SuggestionsTab({
    super.key,
    required this.profileService,
    this.bookmarkService,
    this.explorationService,
    this.recentlyViewedService,
    required this.careerDataService,
    this.analyticsService,
  });

  @override
  State<SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends State<SuggestionsTab> {
  ProfileData? _profile;
  List<CareerNode> _categories = [];
  bool _isLoading = true;
  String? _error;

  static const _iconPalette = AppColors.categoryIcons;

  @override
  void initState() {
    super.initState();
    _loadData();
    widget.explorationService?.addListener(_onServiceChanged);
    widget.recentlyViewedService?.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    widget.explorationService?.removeListener(_onServiceChanged);
    widget.recentlyViewedService?.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted) setState(() { _isLoading = true; _error = null; });
    if (forceRefresh) {
      widget.careerDataService.reset(clearHttpCache: true);
    }
    try {
      final profile = await widget.profileService.getProfile();
      List<CareerNode> categories = [];
      if (profile != null && profile.stream.isNotEmpty) {
        await widget.careerDataService.ensureInitialized();
        categories = await widget.careerDataService
            .fetchStreamCategories(profile.stream, forceRefresh: forceRefresh);
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
          _error = '_connection_error_';
        });
      }
    }
  }

  void _navigateToSubOption(CareerNode node) {
    widget.analyticsService?.logCategoryTapped(node.name);
    Navigator.push(
      context,
      SmoothPageRoute(
        page: SubOptionScreen(
          careerDataService: widget.careerDataService,
          bookmarkService: widget.bookmarkService,
          explorationService: widget.explorationService,
          recentlyViewedService: widget.recentlyViewedService,
          analyticsService: widget.analyticsService,
          nodeId: node.id,
          breadcrumbs: [BreadcrumbEntry(nodeId: node.id, label: node.name)],
        ),
      ),
    );
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      SmoothPageRoute(
        page: ProfileScreen(profileService: widget.profileService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_isLoading) return _buildLoadingState();
    if (_error != null) return ErrorState(message: l.suggestions_connectionError, onRetry: _loadData);
    if (_profile == null || _profile!.stream.isEmpty) return _buildNoProfileState(l);
    return _buildContent(l);
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton for header card
          ShimmerLoading(
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.lgAll,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Skeleton list
          const SkeletonList(itemCount: 4),
        ],
      ),
    );
  }

  Widget _buildNoProfileState(AppLocalizations l) {
    return EmptyState(
      icon: Icons.person_add_alt_1_rounded,
      title: l.suggestions_personalizeTitle,
      subtitle: l.suggestions_personalizeSubtitle,
      actionLabel: l.suggestions_setUpProfile,
      onAction: _navigateToProfile,
    );
  }

  Widget _buildContent(AppLocalizations l) {
    if (_categories.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_rounded,
        title: l.suggestions_noPathsTitle,
        subtitle: l.suggestions_noPathsSubtitle,
        actionLabel: l.suggestions_refresh,
        onAction: () => _loadData(forceRefresh: true),
      );
    }

    final recentIds = widget.recentlyViewedService?.recentIds ?? [];
    final hasRecent = recentIds.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView.builder(
        padding: AppSpacing.pagePadding,
        itemCount: _categories.length + 1 + (hasRecent ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) return _buildDashboardHeader();
          if (hasRecent && index == 1) return _buildRecentlyViewed(recentIds);

          final i = index - 1 - (hasRecent ? 1 : 0);
          final node = _categories[i];
          final color = AppColors.accentPalette[i % AppColors.accentPalette.length];
          final icon = _iconPalette[i % _iconPalette.length];

          return AnimatedListItem(
            index: i,
            child: _CategoryCard(
              node: node,
              icon: icon,
              color: color,
              onTap: () => _navigateToSubOption(node),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentlyViewed(List<String> recentIds) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedNodes = <CareerNode>[];
    for (final id in recentIds) {
      final node = widget.careerDataService.getNodeById(id);
      if (node != null) resolvedNodes.add(node);
    }
    if (resolvedNodes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.suggestions_recentlyViewed,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: resolvedNodes.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final node = resolvedNodes[index];
                return ActionChip(
                  avatar: Icon(
                    node.isLeaf
                        ? Icons.work_outline_rounded
                        : Icons.folder_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  label: SizedBox(
                    width: 100,
                    child: Text(
                      node.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  onPressed: () {
                    widget.analyticsService?.logRecentlyViewedTapped(node.name);
                    Navigator.push(
                      context,
                      SmoothPageRoute(
                        page: SubOptionScreen(
                          careerDataService: widget.careerDataService,
                          bookmarkService: widget.bookmarkService,
                          explorationService: widget.explorationService,
                          recentlyViewedService: widget.recentlyViewedService,
                          analyticsService: widget.analyticsService,
                          nodeId: node.id,
                          breadcrumbs: [
                            BreadcrumbEntry(nodeId: node.id, label: node.name),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader() {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final streamName = _profile?.stream ?? '';
    final streamColor = _getStreamColor(streamName);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              streamColor.withValues(alpha: 0.08),
              streamColor.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: streamColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: streamColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(
                _getStreamIcon(streamName),
                color: streamColor,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.suggestions_streamLabel('${streamName[0].toUpperCase()}${streamName.substring(1)}'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: streamColor,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.suggestions_careerPathsAvailable(_categories.length),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (widget.explorationService != null &&
                      _categories.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _buildProgressBar(streamColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(Color color) {
    final categoryIds = _categories.map((c) => c.id).toList();
    final visited =
        widget.explorationService!.visitedCountFor(categoryIds);
    final total = categoryIds.length;
    final progress = total > 0 ? visited / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)!.suggestions_exploredProgress(visited, total),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Color _getStreamColor(String stream) {
    switch (stream.toLowerCase()) {
      case 'science': return AppColors.science;
      case 'commerce': return AppColors.commerce;
      case 'art': return AppColors.art;
      default: return AppColors.primaryLight;
    }
  }

  IconData _getStreamIcon(String stream) {
    switch (stream.toLowerCase()) {
      case 'science': return Icons.science_rounded;
      case 'commerce': return Icons.account_balance_rounded;
      case 'art': return Icons.palette_rounded;
      default: return Icons.school_rounded;
    }
  }
}

class _CategoryCard extends StatelessWidget {
  final CareerNode node;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.node,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                AccentIconBox(icon: icon, color: color, size: 48),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (node.childIds.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          l.suggestions_pathsAvailable(node.childIds.length),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
