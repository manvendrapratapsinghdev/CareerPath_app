import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/institute_location_filter.dart';
import '../services/location_service.dart';

const instituteLocationPreferenceKey = 'institute_location_filter';

Future<InstituteLocationFilter?> showInstituteLocationFilterSheet(
  BuildContext context, {
  required LocationService locations,
  SharedPreferences? prefs,
  InstituteLocationFilter? initial,
}) async {
  final preferences = prefs ?? await SharedPreferences.getInstance();
  if (!context.mounted) return null;
  final starting =
      initial ??
      InstituteLocationFilter.decode(
        preferences.getString(instituteLocationPreferenceKey),
      );
  final result = await showModalBottomSheet<InstituteLocationFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        InstituteLocationFilterSheet(locations: locations, initial: starting),
  );
  if (result != null) {
    await preferences.setString(
      instituteLocationPreferenceKey,
      result.encode(),
    );
  }
  return result;
}

/// Cascading India → State/UT → District → City filter shared by the ladder
/// and the institute catalog.
class InstituteLocationFilterSheet extends StatefulWidget {
  final LocationService locations;
  final InstituteLocationFilter initial;

  const InstituteLocationFilterSheet({
    super.key,
    required this.locations,
    required this.initial,
  });

  @override
  State<InstituteLocationFilterSheet> createState() =>
      _InstituteLocationFilterSheetState();
}

class _InstituteLocationFilterSheetState
    extends State<InstituteLocationFilterSheet> {
  late Future<void> _load;
  String? _stateCode;
  int? _districtLgd;
  int? _placeId;
  bool _onlineOnly = false;

  @override
  void initState() {
    super.initState();
    _stateCode = widget.initial.stateCode;
    _districtLgd = widget.initial.districtLgd;
    _placeId = widget.initial.placeId;
    _onlineOnly = widget.initial.onlineOnly;
    _load = widget.locations.ensureLoaded();
  }

  void _selectAllIndia() => setState(() {
    _stateCode = null;
    _districtLgd = null;
    _placeId = null;
    _onlineOnly = false;
  });

  void _selectOnline() => setState(() {
    _stateCode = null;
    _districtLgd = null;
    _placeId = null;
    _onlineOnly = true;
  });

  InstituteLocationFilter _selection() {
    final state = _stateCode == null
        ? null
        : widget.locations.stateByCode(_stateCode!);
    final district = _districtLgd == null
        ? null
        : widget.locations.districtByCode(_districtLgd!);
    final place = _placeId == null
        ? null
        : widget.locations.placeById(_placeId!);
    return InstituteLocationFilter(
      stateCode: state?.code,
      stateName: state?.name,
      districtLgd: district?.lgdCode,
      districtName: district?.name,
      placeId: place?.id,
      placeName: place?.name,
      onlineOnly: _onlineOnly,
    );
  }

  void _apply() => Navigator.pop(context, _selection());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.88;
    return SizedBox(
      height: height,
      child: Material(
        color: colorScheme.surface,
        child: SafeArea(
          child: FutureBuilder<void>(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(l10n.institute_locationUnavailable));
              }
              final state = _stateCode == null
                  ? null
                  : widget.locations.stateByCode(_stateCode!);
              final districts = state == null
                  ? const []
                  : widget.locations.districtsIn(state.code);
              final district = _districtLgd == null
                  ? null
                  : widget.locations.districtByCode(_districtLgd!);
              final places = district == null
                  ? const []
                  : widget.locations.placesInDistrict(district.lgdCode);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      AppSpacing.sm,
                      AppSpacing.base,
                      AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.institute_studyLocation,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        ChoiceChip(
                          key: const Key('location-all-india'),
                          label: Text(l10n.institute_allIndia),
                          selected: !_onlineOnly && _stateCode == null,
                          onSelected: (_) => _selectAllIndia(),
                        ),
                        ChoiceChip(
                          key: const Key('location-online'),
                          label: Text(l10n.institute_online),
                          selected: _onlineOnly,
                          onSelected: (_) => _selectOnline(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                      ),
                      children: [
                        DropdownButtonFormField<String>(
                          key: const Key('location-state'),
                          initialValue: _stateCode,
                          decoration: InputDecoration(
                            labelText: l10n.institute_stateOrUnionTerritory,
                          ),
                          items: [
                            for (final item in widget.locations.states)
                              DropdownMenuItem(
                                value: item.code,
                                child: Text(item.name),
                              ),
                          ],
                          onChanged: _onlineOnly
                              ? null
                              : (value) => setState(() {
                                  _stateCode = value;
                                  _districtLgd = null;
                                  _placeId = null;
                                }),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<int>(
                          key: const Key('location-district'),
                          initialValue:
                              districts.any(
                                (item) => item.lgdCode == _districtLgd,
                              )
                              ? _districtLgd
                              : null,
                          decoration: InputDecoration(
                            labelText: l10n.institute_district,
                          ),
                          items: [
                            for (final item in districts)
                              DropdownMenuItem(
                                value: item.lgdCode,
                                child: Text(item.name),
                              ),
                          ],
                          onChanged: state == null || _onlineOnly
                              ? null
                              : (value) => setState(() {
                                  _districtLgd = value;
                                  _placeId = null;
                                }),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<int>(
                          key: const Key('location-city'),
                          initialValue:
                              places.any((item) => item.id == _placeId)
                              ? _placeId
                              : null,
                          decoration: InputDecoration(
                            labelText: l10n.institute_cityTown,
                          ),
                          items: [
                            for (final item in places)
                              DropdownMenuItem(
                                value: item.id,
                                child: Text(item.name),
                              ),
                          ],
                          onChanged: district == null || _onlineOnly
                              ? null
                              : (value) => setState(() => _placeId = value),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('location-filter-reset'),
                            onPressed: _selectAllIndia,
                            child: Text(l10n.institute_allIndia),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton(
                            key: const Key('location-filter-apply'),
                            onPressed: _apply,
                            child: Text(l10n.institute_applyLocation),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
