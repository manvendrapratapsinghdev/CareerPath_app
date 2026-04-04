import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../services/analytics_service.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../services/exploration_service.dart';
import '../widgets/accent_icon_box.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_transitions.dart';
import '../widgets/shimmer_loading.dart';
import 'sub_option_screen.dart';

class BookmarksTab extends StatefulWidget {
  final BookmarkService bookmarkService;
  final ExplorationService? explorationService;
  final CareerDataService careerDataService;
  final AnalyticsService? analyticsService;

  const BookmarksTab({
    super.key,
    required this.bookmarkService,
    this.explorationService,
    required this.careerDataService,
    this.analyticsService,
  });

  @override
  State<BookmarksTab> createState() => _BookmarksTabState();
}

class _BookmarksTabState extends State<BookmarksTab> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = widget.careerDataService.ensureInitialized();
    widget.bookmarkService.addListener(_onBookmarksChanged);
  }

  @override
  void dispose() {
    widget.bookmarkService.removeListener(_onBookmarksChanged);
    super.dispose();
  }

  void _onBookmarksChanged() {
    if (mounted) setState(() {});
  }

  void _navigateToNode(CareerNode node) {
    Navigator.push(
      context,
      SmoothPageRoute(
        page: SubOptionScreen(
          careerDataService: widget.careerDataService,
          bookmarkService: widget.bookmarkService,
          explorationService: widget.explorationService,
          analyticsService: widget.analyticsService,
          nodeId: node.id,
          breadcrumbs: [BreadcrumbEntry(nodeId: node.id, label: node.name)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: AppSpacing.pagePadding,
            child: SkeletonList(itemCount: 4),
          );
        }
        return _buildContent();
      },
    );
  }

  Widget _buildContent() {
    final ids = widget.bookmarkService.bookmarkedIds;
    final nodes = ids
        .map((id) => widget.careerDataService.getNodeById(id))
        .where((n) => n != null)
        .cast<CareerNode>()
        .toList();

    if (nodes.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmark_outline_rounded,
        title: 'No saved paths yet',
        subtitle:
            'Bookmark career paths you like\nand they\'ll appear here',
      );
    }

    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        return AnimatedListItem(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _navigateToNode(node),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    children: [
                      const AccentIconBox(
                        icon: Icons.star_rounded,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              node.name,
                              style:
                                  Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Saved career path',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          widget.analyticsService
                              ?.logBookmarkRemoved(node.name);
                          widget.bookmarkService.toggle(node.id);
                        },
                        icon: const Icon(Icons.bookmark_rounded),
                        color: Theme.of(context).colorScheme.primary,
                        tooltip: 'Remove bookmark',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
