import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_transitions.dart';
import 'resource_filter_screen.dart';

/// Displays an already-loaded resource list with an in-memory search filter.
class ResourceListScreen<T> extends StatefulWidget {
  final String title;
  final String searchHint;
  final String noResultsTitle;
  final String noResultsSubtitle;
  final List<T> items;
  final String Function(T item) searchableText;
  final Widget Function(T item) itemBuilder;
  final List<ResourceFilterOption> filterOptions;
  final bool Function(T item, Set<String> selectedIds)? filterPredicate;

  const ResourceListScreen({
    super.key,
    required this.title,
    required this.searchHint,
    required this.noResultsTitle,
    required this.noResultsSubtitle,
    required this.items,
    required this.searchableText,
    required this.itemBuilder,
    this.filterOptions = const [],
    this.filterPredicate,
  });

  @override
  State<ResourceListScreen<T>> createState() => _ResourceListScreenState<T>();
}

class _ResourceListScreenState<T> extends State<ResourceListScreen<T>> {
  final _searchController = TextEditingController();
  final Set<String> _selectedFilterIds = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<T> get _filteredItems {
    final terms = _query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    return widget.items.where((item) {
      if (_selectedFilterIds.isNotEmpty &&
          !(widget.filterPredicate?.call(item, _selectedFilterIds) ?? false)) {
        return false;
      }
      if (terms.isEmpty) return true;
      final searchableText = widget.searchableText(item).toLowerCase();
      return terms.every(searchableText.contains);
    }).toList();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  Future<void> _openFilters() async {
    final selected = await Navigator.push<Set<String>>(
      context,
      SmoothPageRoute(
        page: ResourceFilterScreen(
          options: widget.filterOptions,
          initialSelection: _selectedFilterIds,
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedFilterIds
          ..clear()
          ..addAll(selected);
      });
    }
  }

  List<ResourceFilterOption> get _selectedFilterOptions {
    return widget.filterOptions
        .where((option) => _selectedFilterIds.contains(option.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final filteredItems = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.filterOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Badge(
                isLabelVisible: _selectedFilterIds.isNotEmpty,
                label: Text('${_selectedFilterIds.length}'),
                child: IconButton(
                  key: const Key('resource-filter-button'),
                  tooltip: l.resource_filterTooltip,
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.base,
              AppSpacing.base,
              AppSpacing.sm,
            ),
            child: TextField(
              key: const Key('resource-list-search'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.mdAll,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_selectedFilterIds.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _selectedFilterOptions.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final option = _selectedFilterOptions[index];
                  return InputChip(
                    label: Text(option.label),
                    onDeleted: () {
                      setState(() => _selectedFilterIds.remove(option.id));
                    },
                  );
                },
              ),
            ),
          Expanded(
            child: filteredItems.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: widget.noResultsTitle,
                    subtitle: widget.noResultsSubtitle,
                  )
                : ListView.builder(
                    key: const Key('resource-list-results'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      0,
                      AppSpacing.base,
                      AppSpacing.xl,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) =>
                        widget.itemBuilder(filteredItems[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
