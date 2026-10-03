import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/domain_tier.dart';
import '../models/institute_location_filter.dart';
import '../models/institution_group.dart';
import '../models/institution_family.dart';
import '../services/institute_catalog_service.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import 'institute_location_filter_sheet.dart';

class InstituteLadderScreen extends StatefulWidget {
  final String domainSlug;
  final InstituteCatalogService catalog;
  final LocationService locations;
  final RouteService routes;
  final SharedPreferences? prefs;

  const InstituteLadderScreen({
    super.key,
    required this.domainSlug,
    required this.catalog,
    required this.locations,
    required this.routes,
    this.prefs,
  });

  @override
  State<InstituteLadderScreen> createState() => _InstituteLadderScreenState();
}

class _InstituteLadderScreenState extends State<InstituteLadderScreen> {
  late InstituteLocationFilter _locationFilter;
  String? _groupCode;
  late Future<_LadderData> _data;

  @override
  void initState() {
    super.initState();
    final saved = InstituteLocationFilter.decode(
      widget.prefs?.getString(instituteLocationPreferenceKey),
    );
    _locationFilter = InstituteLocationFilter(
      stateCode: saved.stateCode,
      stateName: saved.stateName,
    );
    _data = _load();
  }

  Future<_LadderData> _load() async {
    // Keep this local SQLite read pipeline ordered. Multiple independent
    // connections are inexpensive on-device, but the shared cached database
    // can otherwise queue several nested catalog reads during a screen build.
    final route = await widget.routes.routeForDomain(widget.domainSlug);
    // Filter options are derived from the currently applicable state data, so
    // the group picker never offers groups with no records.
    final availableLadder = await widget.catalog.ladderFor(
      widget.domainSlug,
      locationFilter: _locationFilter,
    );
    final availableListings = [
      for (final rung in availableLadder) ...rung.institutes,
    ];
    final availableGroupCodes = availableListings
        .map((listing) => listing.classification?.groupCode)
        .whereType<String>()
        .toSet();
    final availableFamilySlugs = availableListings
        .map((listing) => listing.classification?.familySlug)
        .whereType<String>()
        .toSet();
    final allFamilies = await widget.catalog.getFamilies();
    final allGroups = await widget.catalog.getInstitutionGroups();
    final families = allFamilies
        .where((family) => availableFamilySlugs.contains(family.slug))
        .toList(growable: false);
    final groups = allGroups
        .where((group) => availableGroupCodes.contains(group.code))
        .toList(growable: false);
    final ladder = await widget.catalog.ladderFor(
      widget.domainSlug,
      locationFilter: _locationFilter,
      groupCode: _groupCode,
    );
    return _LadderData(
      route: route,
      families: families,
      groups: groups,
      ladder: ladder,
    );
  }

  Future<void> _showFilterSheet(_LadderData data) async {
    final selection = await Navigator.of(context).push<_LadderFilterSelection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LadderFilterPage(
          data: data,
          locations: widget.locations,
          initialLocation: _locationFilter,
          initialGroupCode: _groupCode,
        ),
      ),
    );
    if (selection == null || !mounted) return;
    final preferences = widget.prefs ?? await SharedPreferences.getInstance();
    await preferences.setString(
      instituteLocationPreferenceKey,
      selection.location.encode(),
    );
    setState(() {
      _locationFilter = selection.location;
      _groupCode = selection.groupCode;
      _data = _load();
    });
  }

  Future<void> _clearFilters() async {
    final preferences = widget.prefs ?? await SharedPreferences.getInstance();
    await preferences.setString(
      instituteLocationPreferenceKey,
      const InstituteLocationFilter().encode(),
    );
    if (!mounted) return;
    setState(() {
      _locationFilter = const InstituteLocationFilter();
      _groupCode = null;
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<_LadderData>(
          future: _data,
          builder: (context, snapshot) => Text(
            snapshot.data?.route?.hasCollegeLadder == false
                ? l10n.institute_stepsTitle
                : l10n.institute_ladderTitle,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('ladder-filter-control'),
            tooltip: l10n.resource_filterTooltip,
            onPressed: () async {
              final snapshot = await _data;
              if (mounted) _showFilterSheet(snapshot);
            },
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_LadderData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: AppSpacing.pagePadding,
                child: Text(l10n.institute_ladderLoadError),
              ),
            );
          }
          final data = snapshot.data!;
          final route = data.route;
          if (route == null) {
            return Center(child: Text(l10n.institute_noRouteData));
          }
          if (!route.hasCollegeLadder) return _buildSteps(route);
          return _buildLadder(data, colorScheme);
        },
      ),
    );
  }

  Widget _buildLadder(_LadderData data, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    final familiesBySlug = {
      for (final family in data.families) family.slug: family,
    };
    final listedCount = data.ladder.fold<int>(
      0,
      (total, rung) => total + rung.institutes.length,
    );
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        Card(
          key: const Key('ladder-overview'),
          child: ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            isThreeLine: true,
            title: Text(data.route!.domain.name),
            subtitle: Text(
              l10n.institute_collegeLadderSubtitle(data.ladder.length),
            ),
            trailing: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: AppRadius.pillAll,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  l10n.institute_coverageListed(listedCount),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _FilterSummary(
          location: _locationFilter,
          groupName: _groupName(data),
          onClear: _locationFilter.isAllIndia && _groupCode == null
              ? null
              : _clearFilters,
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: Text(l10n.institute_groupLabel),
            subtitle: Text(
              l10n.institute_showingFilters(_activeFilterSummary(data)),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ..._groupCards(data, familiesBySlug),
      ],
    );
  }

  List<Widget> _groupCards(
    _LadderData data,
    Map<String, InstitutionFamily> familiesBySlug,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final counts = <String, int>{};
    for (final rung in data.ladder) {
      for (final listing in rung.institutes) {
        final code = listing.classification?.groupCode;
        if (code != null) counts[code] = (counts[code] ?? 0) + 1;
      }
    }
    final groups = [
      for (final group in data.groups)
        if ((counts[group.code] ?? 0) > 0) group,
    ];
    if (groups.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: Text(l10n.institute_noListedInTier)),
        ),
      ];
    }
    return [
      for (final group in groups)
        _GroupCard(
          key: Key('ladder-group-${group.code}'),
          group: group,
          listedCount: counts[group.code]!,
          tiers: [
            for (final rung in data.ladder)
              if (rung.institutes.any(
                (listing) => listing.classification?.groupCode == group.code,
              ))
                (
                  tier: rung.tier,
                  institutes: rung.institutes
                      .where(
                        (listing) =>
                            listing.classification?.groupCode == group.code,
                      )
                      .toList(growable: false),
                ),
          ],
          familiesBySlug: familiesBySlug,
        ),
    ];
  }

  String? _groupName(_LadderData data) {
    if (_groupCode == null) return null;
    for (final group in data.groups) {
      if (group.code == _groupCode) return group.name;
    }
    return _groupCode;
  }

  String _activeFilterSummary(_LadderData data) {
    final l10n = AppLocalizations.of(context)!;
    final labels = <String>[
      if (_locationFilter.isAllIndia)
        l10n.institute_allIndia
      else if (_locationFilter.stateName != null)
        _locationFilter.stateName!,
      ?_groupName(data),
    ];
    return labels.join(' · ');
  }

  Widget _buildSteps(CareerRoute route) {
    final l10n = AppLocalizations.of(context)!;
    final domain = route.domain;
    final bodies = domain.regulatorList;
    final exams = route.entryExams;
    final steps = <({String title, String detail, IconData icon})>[
      if (bodies.isNotEmpty)
        (
          title: l10n.institute_chooseProfessionalBody,
          detail: bodies.join(' · '),
          icon: Icons.account_balance_outlined,
        ),
      if (exams.isNotEmpty)
        (
          title: route.type == RouteType.exam
              ? l10n.institute_relevantExams
              : l10n.institute_entryRoutes,
          detail: exams.join(' · '),
          icon: Icons.assignment_outlined,
        ),
    ];
    if (steps.isEmpty) {
      steps.add((
        title: l10n.institute_checkOfficialRoute,
        detail: l10n.institute_entryRequirementsVary,
        icon: Icons.info_outline,
      ));
    }
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        Text(domain.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.institute_stepsAndEntryRoutes),
        const SizedBox(height: AppSpacing.lg),
        for (var index = 0; index < steps.length; index++)
          _RouteStepCard(index: index + 1, step: steps[index]),
        if (route.type == RouteType.professionalBody &&
            domain.slug == 'ca_cma_cs') ...[
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.institute_caCmaCsNote),
        ],
      ],
    );
  }
}

class _FilterSummary extends StatelessWidget {
  final InstituteLocationFilter location;
  final String? groupName;
  final VoidCallback? onClear;

  const _FilterSummary({required this.location, this.groupName, this.onClear});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = <String>[
      if (location.onlineOnly) l10n.institute_online,
      if (location.placeName != null) location.placeName!,
      if (location.districtName != null && location.placeName == null)
        location.districtName!,
      if (location.stateName != null && location.districtName == null)
        location.stateName!,
      if (location.isAllIndia) l10n.institute_allIndia,
      ?groupName,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(Icons.filter_alt_outlined),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.institute_showingFilters(labels.join(' · ')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              TextButton(onPressed: onClear, child: Text(l10n.institute_clear)),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final InstitutionGroup group;
  final int listedCount;
  final List<LadderTier> tiers;
  final Map<String, InstitutionFamily> familiesBySlug;

  const _GroupCard({
    super.key,
    required this.group,
    required this.listedCount,
    required this.tiers,
    required this.familiesBySlug,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(group.name),
        subtitle: Text(l10n.institute_coverageListed(listedCount)),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: const Icon(Icons.account_balance_outlined),
        ),
        children: [
          for (final rung in tiers)
            _TierCard(
              tier: rung.tier,
              institutes: rung.institutes,
              familiesBySlug: familiesBySlug,
            ),
        ],
      ),
    );
  }
}

class _LadderFilterPage extends StatefulWidget {
  final _LadderData data;
  final LocationService locations;
  final InstituteLocationFilter initialLocation;
  final String? initialGroupCode;

  const _LadderFilterPage({
    required this.data,
    required this.locations,
    required this.initialLocation,
    required this.initialGroupCode,
  });

  @override
  State<_LadderFilterPage> createState() => _LadderFilterPageState();
}

class _LadderFilterPageState extends State<_LadderFilterPage> {
  late InstituteLocationFilter _location;
  late String? _groupCode;

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
    _groupCode = widget.initialGroupCode;
  }

  Future<void> _chooseLocation() async {
    final next = await Navigator.of(context).push<InstituteLocationFilter>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _StateFilterPage(locations: widget.locations, initial: _location),
      ),
    );
    if (next != null && mounted) setState(() => _location = next);
  }

  Future<void> _chooseGroup() async {
    final selection = await Navigator.of(context).push<_GroupFilterSelection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _GroupFilterPage(
          groups: widget.data.groups,
          initialGroupCode: _groupCode,
        ),
      ),
    );
    if (selection != null && mounted) {
      setState(() => _groupCode = selection.groupCode);
    }
  }

  void _apply() => Navigator.pop(
    context,
    _LadderFilterSelection(location: _location, groupCode: _groupCode),
  );

  void _clear() => setState(() {
    _location = const InstituteLocationFilter();
    _groupCode = null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.resource_filterTooltip),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            key: const Key('ladder-filter-apply'),
            onPressed: _apply,
            child: Text(l10n.resource_filterApply),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          Card(
            child: ListTile(
              key: const Key('ladder-location-filter'),
              leading: const Icon(Icons.location_on_outlined),
              title: Text(_locationLabel(l10n)),
              subtitle: Text(l10n.institute_stateOrUnionTerritory),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _chooseLocation,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              key: const Key('ladder-group-filter'),
              leading: const Icon(Icons.layers_outlined),
              title: Text(_groupLabel(l10n)),
              subtitle: Text(l10n.institute_groupLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _chooseGroup,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  child: Text(l10n.resource_filterClear),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('ladder-filter-apply-bottom'),
                  onPressed: _apply,
                  child: Text(l10n.resource_filterApply),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _locationLabel(AppLocalizations l10n) {
    if (_location.stateName != null) return _location.stateName!;
    return l10n.institute_allIndia;
  }

  String _groupLabel(AppLocalizations l10n) {
    if (_groupCode == null) {
      return l10n.institute_allLabel(l10n.institute_groupLabel);
    }
    for (final group in widget.data.groups) {
      if (group.code == _groupCode) return group.name;
    }
    return _groupCode!;
  }
}

class _StateFilterPage extends StatefulWidget {
  final LocationService locations;
  final InstituteLocationFilter initial;

  const _StateFilterPage({required this.locations, required this.initial});

  @override
  State<_StateFilterPage> createState() => _StateFilterPageState();
}

class _StateFilterPageState extends State<_StateFilterPage> {
  late String? _stateCode;
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _stateCode = widget.initial.stateCode;
    _load = widget.locations.ensureLoaded();
  }

  void _reset() => setState(() => _stateCode = null);

  void _apply() {
    final state = _stateCode == null
        ? null
        : widget.locations.stateByCode(_stateCode!);
    Navigator.pop(
      context,
      InstituteLocationFilter(stateCode: state?.code, stateName: state?.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.institute_stateOrUnionTerritory),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            key: const Key('ladder-location-reset'),
            onPressed: _reset,
            child: Text(l10n.resource_filterClear),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(l10n.institute_locationUnavailable));
          }
          return ListView(
            padding: AppSpacing.pagePadding,
            children: [
              Card(
                child: ListTile(
                  key: const Key('ladder-location-all-india'),
                  title: Text(l10n.institute_allIndia),
                  selected: _stateCode == null,
                  trailing: _stateCode == null
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: _reset,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final state in widget.locations.states)
                Card(
                  child: ListTile(
                    key: Key('ladder-location-${state.code}'),
                    title: Text(state.name),
                    selected: _stateCode == state.code,
                    trailing: _stateCode == state.code
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () => setState(() => _stateCode = state.code),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('ladder-location-apply'),
                onPressed: _apply,
                child: Text(l10n.institute_applyLocation),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupFilterPage extends StatefulWidget {
  final List<InstitutionGroup> groups;
  final String? initialGroupCode;

  const _GroupFilterPage({
    required this.groups,
    required this.initialGroupCode,
  });

  @override
  State<_GroupFilterPage> createState() => _GroupFilterPageState();
}

class _GroupFilterPageState extends State<_GroupFilterPage> {
  late String? _groupCode;

  @override
  void initState() {
    super.initState();
    _groupCode = widget.initialGroupCode;
  }

  void _reset() => setState(() => _groupCode = null);

  void _apply() =>
      Navigator.pop(context, _GroupFilterSelection(groupCode: _groupCode));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.institute_groupLabel),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            key: const Key('ladder-group-reset'),
            onPressed: _reset,
            child: Text(l10n.resource_filterClear),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          Card(
            child: ListTile(
              key: const Key('ladder-group-all'),
              title: Text(l10n.institute_allLabel(l10n.institute_groupLabel)),
              selected: _groupCode == null,
              trailing: _groupCode == null
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: _reset,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final group in widget.groups)
            Card(
              child: ListTile(
                key: Key('ladder-group-option-${group.code}'),
                title: Text(group.name),
                selected: _groupCode == group.code,
                trailing: _groupCode == group.code
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => setState(() => _groupCode = group.code),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('ladder-group-apply'),
            onPressed: _apply,
            child: Text(l10n.resource_filterApply),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final DomainTier tier;
  final List<InstituteListing> institutes;
  final Map<String, InstitutionFamily> familiesBySlug;

  const _TierCard({
    required this.tier,
    required this.institutes,
    required this.familiesBySlug,
  });

  String _coverageLabel(AppLocalizations l10n) {
    final familySlugs = tier.familySlugList;
    if (familySlugs.length == 1) {
      final family = familiesBySlug[familySlugs.single];
      if (family?.nationalCount != null) {
        final listed = institutes
            .where((item) => item.classification?.familySlug == family!.slug)
            .length;
        return l10n.institute_coverageInIndia(family!.nationalCount!, listed);
      }
    }
    return l10n.institute_coverageListed(institutes.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('ladder-tier-${tier.tier}'),
        initiallyExpanded: tier.tier == 1,
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Text('T${tier.tier}'),
        ),
        title: Text(tier.label),
        subtitle: Text(_coverageLabel(l10n)),
        children: [
          if (institutes.isEmpty)
            Padding(
              padding: EdgeInsets.all(AppSpacing.base),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.institute_noListedInTier),
              ),
            )
          else
            for (final listing in institutes)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: InstituteListingCard(listing: listing),
              ),
        ],
      ),
    );
  }
}

class InstituteListingCard extends StatelessWidget {
  final InstituteListing listing;

  const InstituteListingCard({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final rank = listing.ranking;
    final private = listing.classification?.isPrivate ?? false;
    final location = listing.campuses.isNotEmpty
        ? listing.campuses
              .map((campus) => '${campus.placeName}, ${campus.stateName}')
              .toSet()
              .join(' · ')
        : [listing.city, listing.state]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .toSet()
              .join(', ');
    final hasUnverifiedLocation = listing.campuses.isEmpty
        ? location.isNotEmpty
        : listing.campuses.any(
            (campus) =>
                campus.sourceUrl?.trim().isNotEmpty != true ||
                campus.verifiedAt?.trim().isNotEmpty != true,
          );
    final accreditationLines = listing.accreditations
        .where((entry) => entry.body == 'NBA')
        .map(
          (entry) => [
            'NBA',
            if (entry.programme.isNotEmpty) entry.programme,
            if (entry.grade?.isNotEmpty == true) entry.grade,
            if (entry.status?.isNotEmpty == true) entry.status,
          ].join(' · '),
        )
        .toSet();
    return Card(
      key: Key('institute-card-${listing.instituteId}'),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(listing.name, style: theme.textTheme.titleMedium),
            if (location.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(location, style: theme.textTheme.bodySmall),
              if (hasUnverifiedLocation) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.institute_mappedLocationDisclaimer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.institute_locationUnavailable,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (listing.groupName != null || listing.familyName != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  listing.familyName,
                  listing.groupName,
                ].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _InfoBadge(
                  key: Key('ranking-${listing.instituteId}'),
                  label: rank != null
                      ? '${rank.label} #${rank.rankLabel}'
                      : listing.naacGrade != null
                      ? 'NAAC ${listing.naacGrade}'
                      : l10n.institute_notRanked,
                  emphasis: listing.highlight != RankHighlight.none,
                ),
                if (listing.highlight == RankHighlight.top10 && rank != null)
                  _InfoBadge(
                    label: l10n.institute_top10(rank.label),
                    emphasis: true,
                  ),
                if (listing.highlight == RankHighlight.top100 && rank != null)
                  _InfoBadge(
                    label: l10n.institute_nirfTop100(rank.year),
                    emphasis: true,
                  ),
                ...accreditationLines.map((line) => _InfoBadge(label: line)),
                if (private && listing.ugcBadge == UgcBadge.verified)
                  _InfoBadge(label: l10n.institute_ugcVerified, emphasis: true),
                if (private && listing.ugcBadge == UgcBadge.notVerified)
                  _InfoBadge(label: l10n.institute_ugcNotVerified),
                if (private && listing.ugcBadge == UgcBadge.pending)
                  _InfoBadge(label: l10n.institute_ugcPending),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final bool emphasis;

  const _InfoBadge({super.key, required this.label, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasis ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _RouteStepCard extends StatelessWidget {
  final int index;
  final ({String title, String detail, IconData icon}) step;

  const _RouteStepCard({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            child: Text('$index'),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(step.icon),
                title: Text(step.title),
                subtitle: Text(step.detail),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LadderFilterSelection {
  final InstituteLocationFilter location;
  final String? groupCode;

  const _LadderFilterSelection({
    required this.location,
    required this.groupCode,
  });
}

class _GroupFilterSelection {
  final String? groupCode;

  const _GroupFilterSelection({required this.groupCode});
}

class _LadderData {
  final CareerRoute? route;
  final List<InstitutionFamily> families;
  final List<InstitutionGroup> groups;
  final List<LadderTier> ladder;

  const _LadderData({
    required this.route,
    required this.families,
    required this.groups,
    required this.ladder,
  });
}
