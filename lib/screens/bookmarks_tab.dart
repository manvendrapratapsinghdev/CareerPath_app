import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
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
import 'compare_screen.dart';
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
  bool _compareMode = false;
  final Set<String> _selected = {};

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

  void _toggleCompareMode() {
    setState(() {
      _compareMode = !_compareMode;
      _selected.clear();
    });
  }

  void _toggleSelection(String nodeId) {
    setState(() {
      if (_selected.contains(nodeId)) {
        _selected.remove(nodeId);
      } else if (_selected.length < 3) {
        _selected.add(nodeId);
      }
    });
  }

  void _startComparison(List<CareerNode> allNodes) {
    final selectedNodes =
        allNodes.where((n) => _selected.contains(n.id)).toList();
    Navigator.push(
      context,
      SmoothPageRoute(
        page: CompareScreen(
          careerDataService: widget.careerDataService,
          nodes: selectedNodes,
          analyticsService: widget.analyticsService,
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
    final l = AppLocalizations.of(context)!;
    final ids = widget.bookmarkService.bookmarkedIds;
    final nodes = ids
        .map((id) => widget.careerDataService.getNodeById(id))
        .where((n) => n != null)
        .cast<CareerNode>()
        .toList();

    if (nodes.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_outline_rounded,
        title: l.bookmarks_noSavedTitle,
        subtitle: l.bookmarks_noSavedSubtitle,
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: AppSpacing.pagePadding.copyWith(bottom: 80),
          itemCount: nodes.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHeader(nodes.length);
            }
            final node = nodes[index - 1];
            return AnimatedListItem(
              index: index - 1,
              child: _buildNodeTile(node),
            );
          },
        ),
        if (_compareMode && _selected.length >= 2)
          Positioned(
            bottom: AppSpacing.lg,
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            child: FilledButton.icon(
              onPressed: () => _startComparison(nodes),
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text(l.bookmarks_compareNPaths(_selected.length)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(int count) {
    final l = AppLocalizations.of(context)!;
    if (count < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _compareMode
                  ? l.bookmarks_selectToCompare
                  : l.bookmarks_savedPathsCount(count),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          TextButton.icon(
            onPressed: _toggleCompareMode,
            icon: Icon(
              _compareMode ? Icons.close_rounded : Icons.compare_arrows_rounded,
              size: 18,
            ),
            label: Text(_compareMode ? l.bookmarks_cancel : l.bookmarks_compare),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(CareerNode node) {
    final l = AppLocalizations.of(context)!;
    final isSelected = _selected.contains(node.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _compareMode
              ? () => _toggleSelection(node.id)
              : () => _navigateToNode(node),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                if (_compareMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(node.id),
                  ),
                ] else ...[
                  const AccentIconBox(
                    icon: Icons.star_rounded,
                    color: AppColors.warning,
                  ),
                ],
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.bookmarks_savedCareerPath,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (!_compareMode)
                  IconButton(
                    onPressed: () {
                      widget.analyticsService?.logBookmarkRemoved(node.name);
                      widget.bookmarkService.toggle(node.id);
                    },
                    icon: const Icon(Icons.bookmark_rounded),
                    color: Theme.of(context).colorScheme.primary,
                    tooltip: l.bookmarks_removeBookmark,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
