import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/empty_state.dart';

class ResourceFilterOption {
  final String id;
  final String label;
  final int count;

  const ResourceFilterOption({
    required this.id,
    required this.label,
    required this.count,
  });
}

/// A dedicated multi-select filter screen for a local resource list.
class ResourceFilterScreen extends StatefulWidget {
  final List<ResourceFilterOption> options;
  final Set<String> initialSelection;

  const ResourceFilterScreen({
    super.key,
    required this.options,
    required this.initialSelection,
  });

  @override
  State<ResourceFilterScreen> createState() => _ResourceFilterScreenState();
}

class _ResourceFilterScreenState extends State<ResourceFilterScreen> {
  final _searchController = TextEditingController();
  late Set<String> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.of(widget.initialSelection);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ResourceFilterOption> get _visibleOptions {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _clear() {
    setState(() => _selectedIds.clear());
  }

  void _apply() {
    Navigator.pop(context, Set<String>.of(_selectedIds));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final visibleOptions = _visibleOptions;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.resource_filterLocationTitle),
        actions: [
          TextButton(
            key: const Key('location-filter-clear'),
            onPressed: _selectedIds.isEmpty ? null : _clear,
            child: Text(l.resource_filterClear),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: AppSpacing.pagePadding,
            child: TextField(
              key: const Key('location-filter-search'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: l.resource_filterSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
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
          Expanded(
            child: visibleOptions.isEmpty
                ? EmptyState(
                    icon: Icons.location_off_rounded,
                    title: l.search_noResultsTitle,
                    subtitle: l.search_noResultsSubtitle,
                  )
                : ListView.separated(
                    key: const Key('location-filter-options'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      0,
                      AppSpacing.base,
                      AppSpacing.xl,
                    ),
                    itemCount: visibleOptions.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) {
                      final option = visibleOptions[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: CheckboxListTile(
                          key: Key('location-filter-${option.id}'),
                          value: _selectedIds.contains(option.id),
                          onChanged: (_) => _toggle(option.id),
                          title: Text(option.label),
                          subtitle: Text(l.sub_institutesCount(option.count)),
                          secondary: const Icon(Icons.location_on_outlined),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            minimum: AppSpacing.pagePadding,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _selectedIds.isEmpty ? null : _clear,
                    child: Text(l.resource_filterAllLocations),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    key: const Key('location-filter-apply'),
                    onPressed: _apply,
                    child: Text(
                      _selectedIds.isEmpty
                          ? l.resource_filterApply
                          : '${l.resource_filterApply} '
                                '· ${l.resource_filterSelectedCount(_selectedIds.length)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
