import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/leaf_details.dart';
import '../services/analytics_service.dart';
import '../services/api_client.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../services/exploration_service.dart';
import '../services/recently_viewed_service.dart';
import '../widgets/accent_icon_box.dart';
import '../widgets/depth_indicator.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_transitions.dart';
import '../widgets/resource_tiles.dart';
import '../widgets/shimmer_loading.dart';

class SubOptionScreen extends StatefulWidget {
  final CareerDataService careerDataService;
  final BookmarkService? bookmarkService;
  final ExplorationService? explorationService;
  final RecentlyViewedService? recentlyViewedService;
  final AnalyticsService? analyticsService;
  final String nodeId;
  final List<BreadcrumbEntry> breadcrumbs;

  const SubOptionScreen({
    super.key,
    required this.careerDataService,
    this.bookmarkService,
    this.explorationService,
    this.recentlyViewedService,
    this.analyticsService,
    required this.nodeId,
    required this.breadcrumbs,
  });

  @override
  State<SubOptionScreen> createState() => _SubOptionScreenState();
}

class _SubOptionScreenState extends State<SubOptionScreen> {
  late Future<List<CareerNode>> _childrenFuture;
  late final CareerNode? _currentNode;
  Future<LeafDetails?>? _leafDetailsFuture;
  LeafDetails? _leafDetails;
  bool _booksExpanded = false;
  bool _institutesExpanded = false;
  bool _jobSectorsExpanded = false;
  bool _isLeaf = false;

  @override
  void initState() {
    super.initState();
    _currentNode = widget.careerDataService.getNodeById(widget.nodeId);
    _childrenFuture = _loadChildren();
    widget.bookmarkService?.addListener(_onBookmarkChanged);
    widget.explorationService?.markVisited(widget.nodeId);
    widget.recentlyViewedService?.addVisit(widget.nodeId);
    widget.analyticsService?.logNodeViewed(
      _currentNode?.name ?? widget.nodeId,
      isLeaf: _currentNode?.isLeaf ?? false,
    );
  }

  @override
  void dispose() {
    widget.bookmarkService?.removeListener(_onBookmarkChanged);
    super.dispose();
  }

  void _onBookmarkChanged() {
    if (mounted) setState(() {});
  }

  int? _computeMaxDepth() {
    final rootId = widget.breadcrumbs.first.nodeId;
    final depthFromRoot = widget.careerDataService.getMaxDepthFrom(rootId);
    if (depthFromRoot == null) return null;
    return depthFromRoot + 1; // +1 to include root level
  }

  Future<List<CareerNode>> _loadChildren({bool forceRefresh = false}) async {
    final children = await widget.careerDataService
        .fetchChildrenOf(widget.nodeId, forceRefresh: forceRefresh);
    if (children.isEmpty && mounted) {
      setState(() {
        _isLeaf = true;
        _leafDetailsFuture = _loadLeafDetails(forceRefresh);
      });
    }
    return children;
  }

  Future<LeafDetails?> _loadLeafDetails(bool forceRefresh) async {
    try {
      final details = await widget.careerDataService
          .getLeafDetails(widget.nodeId, forceRefresh: forceRefresh);
      if (details != null) {
        widget.bookmarkService?.cacheDetails(widget.nodeId, details);
      }
      if (mounted) setState(() => _leafDetails = details);
      return details;
    } catch (_) {
      // Offline fallback: try cached details
      final cached = widget.bookmarkService?.getCachedDetails(widget.nodeId);
      if (cached != null && mounted) {
        setState(() => _leafDetails = cached);
      }
      return cached;
    }
  }

  void _shareCareerPath() {
    final name = _currentNode?.name ?? '';
    final buffer = StringBuffer('Career Path: $name\n');
    if (_currentNode?.intro != null && _currentNode!.intro!.isNotEmpty) {
      buffer.writeln('\n${_currentNode.intro}');
    }
    if (_leafDetails != null) {
      if (_leafDetails!.institutes.isNotEmpty) {
        buffer.writeln('\nTop Institutes:');
        for (final inst in _leafDetails!.institutes.take(3)) {
          buffer.write('- ${inst.name}');
          if (inst.city != null) buffer.write(' (${inst.city})');
          buffer.writeln();
        }
      }
      if (_leafDetails!.jobSectors.isNotEmpty) {
        buffer.writeln('\nJob Sectors:');
        for (final sector in _leafDetails!.jobSectors.take(3)) {
          buffer.writeln('- ${sector.name}');
        }
      }
    }
    buffer.writeln('\n${AppLocalizations.of(context)!.sub_shareFooter}');
    widget.analyticsService?.logShareCareerPath(name);
    SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  Future<void> _refreshData() async {
    setState(() {
      _leafDetailsFuture = null;
      _childrenFuture = _loadChildren(forceRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.breadcrumbs.isNotEmpty ? widget.breadcrumbs.last.label : '',
        ),
        actions: [
          if (_isLeaf && widget.bookmarkService != null)
            IconButton(
              onPressed: () {
                final isNowBookmarked =
                    !widget.bookmarkService!.isBookmarked(widget.nodeId);
                if (isNowBookmarked) {
                  widget.analyticsService
                      ?.logBookmarkAdded(_currentNode?.name ?? widget.nodeId);
                } else {
                  widget.analyticsService
                      ?.logBookmarkRemoved(_currentNode?.name ?? widget.nodeId);
                }
                widget.bookmarkService!.toggle(
                  widget.nodeId,
                  details: _leafDetails,
                );
              },
              icon: Icon(
                widget.bookmarkService!.isBookmarked(widget.nodeId)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded,
              ),
              tooltip: widget.bookmarkService!.isBookmarked(widget.nodeId)
                  ? l.sub_removeBookmark
                  : l.sub_saveCareerPath,
            ),
          if (_isLeaf)
            IconButton(
              onPressed: _shareCareerPath,
              icon: const Icon(Icons.share_rounded),
              tooltip: l.sub_shareTooltip,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb trail
          if (widget.breadcrumbs.length > 1)
            _BreadcrumbBar(
              breadcrumbs: widget.breadcrumbs,
              colorScheme: colorScheme,
              currentDepth: widget.breadcrumbs.length,
              maxDepth: _computeMaxDepth(),
            ),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: FutureBuilder<List<CareerNode>>(
                future: _childrenFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: AppSpacing.pagePadding,
                      child: SkeletonList(itemCount: 4),
                    );
                  }
                  if (snapshot.hasError) {
                    final isServerDown = snapshot.error is ServerDownException;
                    return ErrorState(
                      message: isServerDown
                          ? l.sub_serverDownError
                          : l.sub_loadError,
                      onRetry: _refreshData,
                    );
                  }
                  final children = snapshot.data ?? [];
                  if (children.isEmpty) {
                    return FutureBuilder<LeafDetails?>(
                      future: _leafDetailsFuture,
                      builder: (context, leafSnapshot) {
                        return _LeafView(
                          node: _currentNode,
                          details: leafSnapshot.data,
                          isLoading: leafSnapshot.connectionState ==
                              ConnectionState.waiting,
                          booksExpanded: _booksExpanded,
                          institutesExpanded: _institutesExpanded,
                          jobSectorsExpanded: _jobSectorsExpanded,
                          onBooksToggle: () =>
                              setState(() => _booksExpanded = !_booksExpanded),
                          onInstitutesToggle: () => setState(
                              () => _institutesExpanded = !_institutesExpanded),
                          onJobSectorsToggle: () => setState(
                              () => _jobSectorsExpanded = !_jobSectorsExpanded),
                        );
                      },
                    );
                  }
                  return _buildChildList(context, children, colorScheme);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildList(
    BuildContext context,
    List<CareerNode> children,
    ColorScheme colorScheme,
  ) {
    final l = AppLocalizations.of(context)!;
    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: children.length,
      itemBuilder: (context, index) {
        final child = children[index];
        return AnimatedListItem(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    SmoothPageRoute(
                      page: SubOptionScreen(
                        careerDataService: widget.careerDataService,
                        bookmarkService: widget.bookmarkService,
                        explorationService: widget.explorationService,
                        recentlyViewedService: widget.recentlyViewedService,
                        analyticsService: widget.analyticsService,
                        nodeId: child.id,
                        breadcrumbs: [
                          ...widget.breadcrumbs,
                          BreadcrumbEntry(nodeId: child.id, label: child.name),
                        ],
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    children: [
                      AccentIconBox(
                        icon: child.isLeaf
                            ? Icons.star_rounded
                            : Icons.account_tree_outlined,
                        color: child.isLeaf
                            ? AppColors.warning
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              child.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              child.isLeaf
                                  ? l.sub_careerEndpoint
                                  : l.sub_optionsAhead(child.childCount),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        child.isLeaf
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.chevron_right_rounded,
                        size: child.isLeaf ? 16 : 24,
                        color: colorScheme.onSurfaceVariant,
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

// ── Breadcrumb Bar ──────────────────────────────────────────────────────────

class _BreadcrumbBar extends StatelessWidget {
  final List<BreadcrumbEntry> breadcrumbs;
  final ColorScheme colorScheme;
  final int currentDepth;
  final int? maxDepth;

  const _BreadcrumbBar({
    required this.breadcrumbs,
    required this.colorScheme,
    required this.currentDepth,
    this.maxDepth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildCrumbs(context)),
            ),
            const SizedBox(height: 4),
            DepthIndicator(
              currentDepth: currentDepth,
              maxDepth: maxDepth,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCrumbs(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < breadcrumbs.length; i++) {
      final crumb = breadcrumbs[i];
      final isLast = i == breadcrumbs.length - 1;

      if (i > 0) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ));
      }

      widgets.add(
        GestureDetector(
          onTap: isLast
              ? null
              : () {
                  final popCount = breadcrumbs.length - 1 - i;
                  for (int j = 0; j < popCount; j++) {
                    Navigator.pop(context);
                  }
                },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isLast
                  ? colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: AppRadius.smAll,
            ),
            child: Text(
              crumb.label,
              style: TextStyle(
                fontSize: 13,
                color: isLast
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

// ── Leaf View ───────────────────────────────────────────────────────────────

class _LeafView extends StatelessWidget {
  final CareerNode? node;
  final LeafDetails? details;
  final bool isLoading;
  final bool booksExpanded;
  final bool institutesExpanded;
  final bool jobSectorsExpanded;
  final VoidCallback onBooksToggle;
  final VoidCallback onInstitutesToggle;
  final VoidCallback onJobSectorsToggle;

  const _LeafView({
    required this.node,
    required this.details,
    required this.isLoading,
    required this.booksExpanded,
    required this.institutesExpanded,
    required this.jobSectorsExpanded,
    required this.onBooksToggle,
    required this.onInstitutesToggle,
    required this.onJobSectorsToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero header
          _buildHero(context, l),
          const SizedBox(height: AppSpacing.lg),

          // Intro text
          if (node?.intro != null && node!.intro!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                node!.intro!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Detail sections
          if (isLoading) ...[
            const SkeletonList(itemCount: 3),
          ] else if (details != null) ...[
            ResourceSection(
              title: l.sub_recommendedBooks,
              subtitle: details!.books.isEmpty
                  ? l.sub_noBooksAvailable
                  : l.sub_booksCount(details!.books.length),
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF6366F1),
              isExpanded: booksExpanded,
              onToggle: onBooksToggle,
              children: details!.books.map((b) => BookTile(book: b)).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            ResourceSection(
              title: l.sub_topInstitutes,
              subtitle: details!.institutes.isEmpty
                  ? l.sub_noInstitutesAvailable
                  : l.sub_institutesCount(details!.institutes.length),
              icon: Icons.school_rounded,
              color: const Color(0xFF14B8A6),
              isExpanded: institutesExpanded,
              onToggle: onInstitutesToggle,
              children: details!.institutes
                  .map((i) => InstituteTile(institute: i))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            ResourceSection(
              title: l.sub_jobSectors,
              subtitle: details!.jobSectors.isEmpty
                  ? l.sub_noSectorsAvailable
                  : l.sub_sectorsCount(details!.jobSectors.length),
              icon: Icons.work_rounded,
              color: const Color(0xFFF59E0B),
              isExpanded: jobSectorsExpanded,
              onToggle: onJobSectorsToggle,
              children: details!.jobSectors
                  .map((s) => JobSectorTile(sector: s))
                  .toList(),
            ),
          ] else ...[
            EmptyState(
              icon: Icons.upcoming_rounded,
              title: l.sub_moreDetailsSoonTitle,
              subtitle: l.sub_moreDetailsSoonSubtitle,
            ),
          ],

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, AppLocalizations l) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withValues(alpha: 0.15),
                  AppColors.success.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              size: 36,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            node?.name ?? '',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: AppRadius.pillAll,
            ),
            child: Text(
              l.sub_finalCareerOption,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
