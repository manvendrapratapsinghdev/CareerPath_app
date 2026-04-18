import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/breadcrumb_entry.dart';
import '../models/career_node.dart';
import '../services/analytics_service.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../widgets/accent_icon_box.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_transitions.dart';
import 'sub_option_screen.dart';

class SearchScreen extends StatefulWidget {
  final CareerDataService careerDataService;
  final BookmarkService bookmarkService;
  final AnalyticsService? analyticsService;

  const SearchScreen({
    super.key,
    required this.careerDataService,
    required this.bookmarkService,
    this.analyticsService,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<CareerNode> _results = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.analyticsService?.logScreenView('search');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final results = widget.careerDataService.searchNodes(query);
      if (mounted) {
        setState(() => _results = results);
      }
      if (query.trim().isNotEmpty) {
        widget.analyticsService?.logSearch(query, results.length);
      }
    });
    // Immediately update to show/hide clear button
    setState(() {});
  }

  void _navigateToNode(CareerNode node) {
    widget.analyticsService?.logNodeTapped(node.name, isLeaf: node.isLeaf);
    Navigator.push(
      context,
      SmoothPageRoute(
        page: SubOptionScreen(
          careerDataService: widget.careerDataService,
          bookmarkService: widget.bookmarkService,
          analyticsService: widget.analyticsService,
          nodeId: node.id,
          breadcrumbs: [BreadcrumbEntry(nodeId: node.id, label: node.name)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onSearch,
          decoration: InputDecoration(
            hintText: l.search_hint,
            border: InputBorder.none,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                _onSearch('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    final l = AppLocalizations.of(context)!;
    if (_controller.text.isEmpty) {
      return EmptyState(
        icon: Icons.search_rounded,
        title: l.search_emptyTitle,
        subtitle: l.search_emptySubtitle,
      );
    }

    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: l.search_noResultsTitle,
        subtitle: l.search_noResultsSubtitle,
      );
    }

    return ListView.builder(
      padding: AppSpacing.pagePadding,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final node = _results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _navigateToNode(node),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    AccentIconBox(
                      icon: node.isLeaf
                          ? Icons.star_rounded
                          : Icons.account_tree_outlined,
                      color: node.isLeaf
                          ? AppColors.warning
                          : colorScheme.primary,
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
                          const SizedBox(height: 2),
                          Text(
                            node.isLeaf
                                ? l.search_careerEndpoint
                                : l.search_optionsAhead(node.childCount),
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
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
