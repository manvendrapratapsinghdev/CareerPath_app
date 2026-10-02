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
    final families = await widget.catalog.getFamilies();
    final groups = await widget.catalog.getInstitutionGroups();
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

  Future<void> _chooseLocation() async {
    final selection = await showInstituteLocationFilterSheet(
      context,
      locations: widget.locations,
      prefs: widget.prefs,
      initial: _locationFilter,
    );
    if (selection == null || !mounted) return;
    setState(() {
      _locationFilter = selection;
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
            key: const Key('institute-location-button'),
            tooltip: l10n.institute_locationFilterTooltip,
            onPressed: _chooseLocation,
            icon: const Icon(Icons.location_on_outlined),
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
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        _FilterSummary(
          location: _locationFilter,
          onClear:
              _locationFilter.isAllIndia &&
                  !_ugcVerifiedOnly &&
                  _groupCode == null &&
                  _familySlug == null
              ? null
              : _clearFilters,
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          key: const Key('ugc-verified-only'),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(l10n.institute_hidePrivateWithoutUgc),
          value: _ugcVerifiedOnly,
          onChanged: (value) => setState(() {
            _ugcVerifiedOnly = value;
            _data = _load();
          }),
        ),
        _dropdown<String>(
          key: const Key('ladder-group-filter'),
          label: l10n.institute_groupLabel,
          value: _groupCode,
          values: [
            for (final group in data.groups)
              DropdownMenuItem(value: group.code, child: Text(group.name)),
          ],
          onChanged: (value) => setState(() {
            _groupCode = value;
            if (_familySlug != null &&
                !data.families.any(
                  (family) =>
                      family.slug == _familySlug && family.groupCode == value,
                )) {
              _familySlug = null;
            }
            _data = _load();
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        _dropdown<String>(
          key: const Key('ladder-family-filter'),
          label: l10n.institute_familyLabel,
          value: _familySlug,
          values: [
            for (final family in data.families)
              if (_groupCode == null || family.groupCode == _groupCode)
                DropdownMenuItem(value: family.slug, child: Text(family.name)),
          ],
          onChanged: (value) => setState(() {
            _familySlug = value;
            _data = _load();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final rung in data.ladder)
          _TierCard(
            tier: rung.tier,
            institutes: rung.institutes,
            familiesBySlug: familiesBySlug,
          ),
      ],
    );
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

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> values,
    required ValueChanged<T?> onChanged,
  }) => DropdownButtonFormField<T>(
    key: key,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem<T>(
        value: null,
        child: Text(AppLocalizations.of(context)!.institute_allLabel(label)),
      ),
      ...values,
    ],
    onChanged: onChanged,
  );
}

class _FilterSummary extends StatelessWidget {
  final InstituteLocationFilter location;
  final VoidCallback? onClear;

  const _FilterSummary({required this.location, this.onClear});

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
    ];
    return Row(
      children: [
        const Icon(Icons.filter_alt_outlined),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(l10n.institute_showingFilters(labels.join(' · '))),
        ),
        if (onClear != null)
          TextButton(onPressed: onClear, child: Text(l10n.institute_clear)),
      ],
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
