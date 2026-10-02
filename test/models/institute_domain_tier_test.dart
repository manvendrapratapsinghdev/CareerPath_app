import 'package:career_path/models/institute_domain_tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an institute_domain_tiers row and round-trips it', () {
    final t = InstituteDomainTier.fromJson({
      'institute_id': 12,
      'domain_slug': 'engineering',
      'tier': 2,
    });
    expect(t.instituteId, 12);

    final restored = InstituteDomainTier.fromJson(t.toJson());
    expect(restored.domainSlug, 'engineering');
    expect(restored.tier, 2);
  });
}
