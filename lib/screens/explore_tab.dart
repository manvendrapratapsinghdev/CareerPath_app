import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../models/stream_model.dart';
import '../services/analytics_service.dart';
import '../services/api_client.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../widgets/accent_icon_box.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_transitions.dart';
import '../widgets/shimmer_loading.dart';
import 'sub_option_screen.dart';

class ExploreTab extends StatefulWidget {
  final CareerDataService careerDataService;
  final BookmarkService? bookmarkService;
  final AnalyticsService? analyticsService;

  const ExploreTab({
    super.key,
    required this.careerDataService,
    this.bookmarkService,
    this.analyticsService,
  });

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  static const _iconPalette = AppColors.streamIcons;

  late Map<String, bool> _expandedStreams;
  final Map<String, Future<List<CareerNode>>> _categoryFutures = {};
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _expandedStreams = {};
    _initFuture = widget.careerDataService.ensureInitialized().then((_) {
      if (!mounted) return;
      final streams = widget.careerDataService.getAllStreams();
      setState(() {
        if (streams.isNotEmpty) {
          _expandedStreams[streams[0].id] = true;
          _categoryFutures[streams[0].id] =
              widget.careerDataService.fetchStreamCategories(streams[0].id);
          for (int i = 1; i < streams.length; i++) {
            _expandedStreams[streams[i].id] = false;
          }
        }
      });
    });
  }

  Future<void> _refreshData() async {
    widget.careerDataService.reset(clearHttpCache: true);
    setState(() {
      _expandedStreams = {};
      _categoryFutures.clear();
      _initFuture = widget.careerDataService.ensureInitialized().then((_) {
        if (!mounted) return;
        final streams = widget.careerDataService.getAllStreams();
        setState(() {
          if (streams.isNotEmpty) {
            _expandedStreams[streams[0].id] = true;
            _categoryFutures[streams[0].id] =
                widget.careerDataService.fetchStreamCategories(streams[0].id);
            for (int i = 1; i < streams.length; i++) {
              _expandedStreams[streams[i].id] = false;
            }
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: AppSpacing.pagePadding,
            child: SkeletonList(itemCount: 3),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Failed to load data',
            onRetry: _refreshData,
          );
        }

        final streams = widget.careerDataService.getAllStreams();
        if (streams.isEmpty) {
          return const EmptyState(
            icon: Icons.explore_off_rounded,
            title: 'No streams available',
            subtitle: 'Check back later for career streams',
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshData,
          child: ListView.builder(
            padding: AppSpacing.pagePadding,
            itemCount: streams.length,
            itemBuilder: (context, index) {
              final stream = streams[index];
              return AnimatedListItem(
                index: index,
                child: _StreamSection(
                  stream: stream,
                  categoryFuture: _categoryFutures[stream.id],
                  careerDataService: widget.careerDataService,
                  bookmarkService: widget.bookmarkService,
                  analyticsService: widget.analyticsService,
                  icon: _iconPalette[index % _iconPalette.length],
                  color: AppColors.accentPalette[index % AppColors.accentPalette.length],
                  isExpanded: _expandedStreams[stream.id] ?? false,
                  onExpanded: () {
                    setState(() {
                      final willExpand = !(_expandedStreams[stream.id] ?? false);
                      _expandedStreams[stream.id] = willExpand;
                      if (willExpand) {
                        widget.analyticsService?.logStreamExpanded(stream.name);
                        _categoryFutures[stream.id] ??=
                            widget.careerDataService
                                .fetchStreamCategories(stream.id);
                      }
                    });
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StreamSection extends StatelessWidget {
  final StreamModel stream;
  final Future<List<CareerNode>>? categoryFuture;
  final CareerDataService careerDataService;
  final BookmarkService? bookmarkService;
  final AnalyticsService? analyticsService;
  final IconData icon;
  final Color color;
  final bool isExpanded;
  final VoidCallback onExpanded;

  const _StreamSection({
    required this.stream,
    required this.categoryFuture,
    required this.careerDataService,
    this.bookmarkService,
    this.analyticsService,
    required this.icon,
    required this.color,
    required this.isExpanded,
    required this.onExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.xs,
            ),
            title: Row(
              children: [
                AccentIconBox(icon: icon, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stream.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                      ),
                      Text(
                        '${stream.rootNodeCount} categor${stream.rootNodeCount != 1 ? 'ies' : 'y'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (_) => onExpanded(),
            children: [
              Divider(
                height: 1,
                indent: AppSpacing.base,
                endIndent: AppSpacing.base,
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
              _buildCategoryContent(context, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryContent(BuildContext context, ColorScheme colorScheme) {
    if (categoryFuture == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.base),
        child: SkeletonList(itemCount: 2),
      );
    }

    return FutureBuilder<List<CareerNode>>(
      future: categoryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: SkeletonList(itemCount: 2),
          );
        }
        if (snapshot.hasError) {
          final isServerDown = snapshot.error is ServerDownException;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Center(
              child: Text(
                isServerDown
                    ? 'Server is down.\nPlease contact admin (9807942950) to start the server.'
                    : 'Failed to load categories',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
              ),
            ),
          );
        }

        final categories = snapshot.data ?? [];
        if (categories.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: Text(
                'No categories available',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: List.generate(categories.length, (i) {
              final node = categories[i];
              return AnimatedListItem(
                index: i,
                child: _CategoryTile(
                  node: node,
                  color: color,
                  careerDataService: careerDataService,
                  bookmarkService: bookmarkService,
                  analyticsService: analyticsService,
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CareerNode node;
  final Color color;
  final CareerDataService careerDataService;
  final BookmarkService? bookmarkService;
  final AnalyticsService? analyticsService;

  const _CategoryTile({
    required this.node,
    required this.color,
    required this.careerDataService,
    this.bookmarkService,
    this.analyticsService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              SmoothPageRoute(
                page: SubOptionScreen(
                  careerDataService: careerDataService,
                  bookmarkService: bookmarkService,
                  analyticsService: analyticsService,
                  nodeId: node.id,
                  breadcrumbs: [
                    BreadcrumbEntry(nodeId: node.id, label: node.name),
                  ],
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                AccentIconBox(
                  icon: Icons.folder_outlined,
                  color: color,
                  size: 40,
                  iconSize: 20,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (!node.isLeaf)
                        Text(
                          '${node.childCount} sub-paths',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
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
