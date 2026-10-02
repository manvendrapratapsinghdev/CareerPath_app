import 'package:career_path/models/domain_tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an apex domain_tiers row and round-trips it', () {
    final t = DomainTier.fromJson({
      'domain_slug': 'law',
      'tier': 1,
      'label': 'National Law Universities',
      'group_codes': 'G4',
      'family_slugs': 'nlu',
      'entry_exams': 'CLAT, AILET',
    });
    expect(t.isApex, isTrue);
    expect(t.familySlugList, ['nlu']);

    final restored = DomainTier.fromJson(t.toJson());
    expect(restored.domainSlug, 'law');
    expect(restored.tier, 1);
    expect(restored.label, 'National Law Universities');
    expect(restored.entryExams, 'CLAT, AILET');
  });

  test('a group tier lists several groups and is not apex', () {
    final t = DomainTier.fromJson({
      'domain_slug': 'management',
      'tier': 6,
      'label': 'Private',
      'group_codes': 'G5,G7',
    });
    expect(t.groupCodeList, ['G5', 'G7']);
    expect(t.isApex, isFalse);
    expect(t.familySlugs, isNull);
  });
}
