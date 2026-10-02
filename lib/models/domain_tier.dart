import 'sqlite_values.dart';

/// One rung of a domain's college ladder (`domain_tiers`): apex families
/// first (e.g. NLUs for Law), then groups G1 → G9.
class DomainTier {
  final String domainSlug;

  /// 1 = top.
  final int tier;
  final String label;

  /// Raw CSV, e.g. `G4` or `G5,G7`.
  final String groupCodes;

  /// Raw CSV of the families an apex tier picks, e.g. `nlu`; `null` means
  /// every family of [groupCodes].
  final String? familySlugs;
  final String? entryExams;

  const DomainTier({
    required this.domainSlug,
    required this.tier,
    required this.label,
    required this.groupCodes,
    this.familySlugs,
    this.entryExams,
  });

  factory DomainTier.fromJson(Map<String, dynamic> json) => DomainTier(
    domainSlug: json['domain_slug'] as String,
    tier: (json['tier'] as num).toInt(),
    label: json['label'] as String,
    groupCodes: json['group_codes'] as String? ?? '',
    familySlugs: json['family_slugs'] as String?,
    entryExams: json['entry_exams'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'domain_slug': domainSlug,
    'tier': tier,
    'label': label,
    'group_codes': groupCodes,
    'family_slugs': familySlugs,
    'entry_exams': entryExams,
  };

  List<String> get groupCodeList => splitSqliteList(groupCodes);
  List<String> get familySlugList => splitSqliteList(familySlugs);

  /// An apex tier names specific families instead of whole groups.
  bool get isApex => familySlugList.isNotEmpty;

  @override
  String toString() => 'DomainTier($domainSlug #$tier $label)';
}
