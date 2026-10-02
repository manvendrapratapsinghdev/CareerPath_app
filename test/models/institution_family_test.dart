import 'package:career_path/models/institution_family.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a families row and round-trips it', () {
    final family = InstitutionFamily.fromJson({
      'slug': 'nit',
      'name': 'National Institutes of Technology',
      'group_code': 'G2',
      'regulators': 'MoE; AICTE',
      'official_list_url': 'https://nitcouncil.org.in/',
      'national_count': 31,
      'national_count_as_of': '2026-10-01',
    });
    expect(family.nationalCount, 31);
    expect(family.regulatorList, ['MoE', 'AICTE']);

    final restored = InstitutionFamily.fromJson(family.toJson());
    expect(restored.slug, 'nit');
    expect(restored.groupCode, 'G2');
    expect(restored.officialListUrl, 'https://nitcouncil.org.in/');
    expect(restored.nationalCountAsOf, '2026-10-01');
  });

  test('a family with no confirmed count parses with nulls', () {
    final family = InstitutionFamily.fromJson({
      'slug': 'iti',
      'name': 'Industrial Training Institutes',
      'group_code': 'G9',
    });
    expect(family.nationalCount, isNull);
    expect(family.regulatorList, isEmpty);
  });
}
