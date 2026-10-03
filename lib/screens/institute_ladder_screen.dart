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
  String? _familySlug;
  bool _ugcVerifiedOnly = false;
  late Future<_LadderData> _data;

  @override
  void initState() {
    super.initState();
    _locationFilter = InstituteLocationFilter.decode(
      widget.prefs?.getString(instituteLocationPreferenceKey),
    );
    _data = _load();
  }

  Future<_LadderData> _load() async {
    // Keep this local SQLite read pipeline ordered. Multiple independent
    // connections are inexpensive on-device, but the shared cached database
    // can otherwise queue several nested catalog reads during a screen build.
    final route = await widget.routes.routeForDomain(widget.domainSlug);
    // Filter options are derived from the currently applicable location and
    // UGC data, so the picker never offers groups/families with no records.
    final availableLadder = await widget.catalog.ladderFor(
      widget.domainSlug,
      locationFilter: _locationFilter,
      ugcVerifiedOnly: _ugcVerifiedOnly,
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
      ugcVerifiedOnly: _ugcVerifiedOnly,
      groupCode: _groupCode,
      familySlug: _familySlug,
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
          prefs: widget.prefs,
          initialLocation: _locationFilter,
          initialUgcVerifiedOnly: _ugcVerifiedOnly,
          initialGroupCode: _groupCode,
          initialFamilySlug: _familySlug,
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
      _ugcVerifiedOnly = selection.ugcVerifiedOnly;
      _groupCode = selection.groupCode;
      _familySlug = selection.familySlug;
      _data = _load();
    });
  }

  String _locationSummaryLabel(
    BuildContext context,
    InstituteLocationFilter filter,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (filter.onlineOnly) return l10n.institute_online;
    if (filter.placeName != null) return filter.placeName!;
    if (filter.districtName != null) return filter.districtName!;
    if (filter.stateName != null) return filter.stateName!;
    return l10n.institute_allIndia;
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
      _ugcVerifiedOnly = false;
      _groupCode = null;
      _familySlug = null;
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
          ugcVerifiedOnly: _ugcVerifiedOnly,
          groupName: _groupName(data),
          familyName: _familyName(data),
          onClear:
              _locationFilter.isAllIndia &&
                  !_ugcVerifiedOnly &&
                  _groupCode == null &&
                  _familySlug == null
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

  String? _familyName(_LadderData data) {
    if (_familySlug == null) return null;
    for (final family in data.families) {
      if (family.slug == _familySlug) return family.name;
    }
    return _familySlug;
  }

  String _activeFilterSummary(_LadderData data) {
    final l10n = AppLocalizations.of(context)!;
    final labels = <String>[
      _locationSummaryLabel(context, _locationFilter),
      ?_groupName(data),
      ?_familyName(data),
      if (_ugcVerifiedOnly) l10n.institute_hidePrivateWithoutUgc,
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
  final bool ugcVerifiedOnly;
  final String? groupName;
  final String? familyName;
  final VoidCallback? onClear;

  const _FilterSummary({
    required this.location,
    this.ugcVerifiedOnly = false,
    this.groupName,
    this.familyName,
    this.onClear,
  });

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
      ?familyName,
      if (ugcVerifiedOnly) l10n.institute_hidePrivateWithoutUgc,
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
  final SharedPreferences? prefs;
  final InstituteLocationFilter initialLocation;
  final bool initialUgcVerifiedOnly;
  final String? initialGroupCode;
  final String? initialFamilySlug;

  const _LadderFilterPage({
    required this.data,
    required this.locations,
    required this.prefs,
    required this.initialLocation,
    required this.initialUgcVerifiedOnly,
    required this.initialGroupCode,
    required this.initialFamilySlug,
  });

  @override
  State<_LadderFilterPage> createState() => _LadderFilterPageState();
}

class _LadderFilterPageState extends State<_LadderFilterPage> {
  late InstituteLocationFilter _location;
  late bool _ugcVerifiedOnly;
  late String? _groupCode;
  late String? _familySlug;

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
    _ugcVerifiedOnly = widget.initialUgcVerifiedOnly;
    _groupCode = widget.initialGroupCode;
    _familySlug = widget.initialFamilySlug;
  }

  Future<void> _chooseLocation() async {
    final next = await showInstituteLocationFilterSheet(
      context,
      locations: widget.locations,
      prefs: widget.prefs,
      initial: _location,
      persist: false,
    );
    if (next != null && mounted) setState(() => _location = next);
  }

  void _apply() => Navigator.pop(
    context,
    _LadderFilterSelection(
      location: _location,
      ugcVerifiedOnly: _ugcVerifiedOnly,
      groupCode: _groupCode,
      familySlug: _familySlug,
    ),
  );

  void _clear() => setState(() {
    _location = const InstituteLocationFilter();
    _ugcVerifiedOnly = false;
    _groupCode = null;
    _familySlug = null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final families = widget.data.families
        .where((family) => _groupCode == null || family.groupCode == _groupCode)
        .toList(growable: false);
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
              leading: const Icon(Icons.location_on_outlined),
              title: Text(_locationLabel(l10n)),
              subtitle: Text(l10n.institute_locationFilterTooltip),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _chooseLocation,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: SwitchListTile(
              key: const Key('ugc-verified-only'),
              title: Text(l10n.institute_hidePrivateWithoutUgc),
              value: _ugcVerifiedOnly,
              onChanged: (value) => setState(() => _ugcVerifiedOnly = value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _filterDropdown<String>(
            key: const Key('ladder-group-filter'),
            label: l10n.institute_groupLabel,
            allLabel: l10n.institute_allLabel(l10n.institute_groupLabel),
            value: _groupCode,
            values: [
              for (final group in widget.data.groups)
                DropdownMenuItem(value: group.code, child: Text(group.name)),
            ],
            onChanged: (value) => setState(() {
              _groupCode = value;
              if (_familySlug != null &&
                  !widget.data.families.any(
                    (family) =>
                        family.slug == _familySlug &&
                        (value == null || family.groupCode == value),
                  )) {
                _familySlug = null;
              }
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          _filterDropdown<String>(
            key: const Key('ladder-family-filter'),
            label: l10n.institute_familyLabel,
            allLabel: l10n.institute_allLabel(l10n.institute_familyLabel),
            value: _familySlug,
            values: [
              for (final family in families)
                DropdownMenuItem(value: family.slug, child: Text(family.name)),
            ],
            onChanged: (value) => setState(() => _familySlug = value),
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
    if (_location.onlineOnly) return l10n.institute_online;
    if (_location.placeName != null) return _location.placeName!;
    if (_location.districtName != null) return _location.districtName!;
    if (_location.stateName != null) return _location.stateName!;
    return l10n.institute_allIndia;
  }
}

DropdownButtonFormField<T> _filterDropdown<T>({
  required Key key,
  required String label,
  required String allLabel,
  required T? value,
  required List<DropdownMenuItem<T>> values,
  required ValueChanged<T?> onChanged,
}) => DropdownButtonFormField<T>(
  key: key,
  initialValue: value,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: [
    DropdownMenuItem<T>(value: null, child: Text(allLabel)),
    ...values,
  ],
  onChanged: onChanged,
);

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
  final bool ugcVerifiedOnly;
  final String? groupCode;
  final String? familySlug;

  const _LadderFilterSelection({
    required this.location,
    required this.ugcVerifiedOnly,
    required this.groupCode,
    required this.familySlug,
  });
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
