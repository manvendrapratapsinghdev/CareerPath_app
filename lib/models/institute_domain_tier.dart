/// Which ladder rung an institute sits on for a domain
/// (`institute_domain_tiers`, derived by tooling; the app applies no rules).
class InstituteDomainTier {
  final int instituteId;
  final String domainSlug;
  final int tier;

  const InstituteDomainTier({
    required this.instituteId,
    required this.domainSlug,
    required this.tier,
  });

  factory InstituteDomainTier.fromJson(Map<String, dynamic> json) =>
      InstituteDomainTier(
        instituteId: (json['institute_id'] as num).toInt(),
        domainSlug: json['domain_slug'] as String,
        tier: (json['tier'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
    'institute_id': instituteId,
    'domain_slug': domainSlug,
    'tier': tier,
  };

  @override
  String toString() => 'InstituteDomainTier($instituteId, $domainSlug #$tier)';
}
