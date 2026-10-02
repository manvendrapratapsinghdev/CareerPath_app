import 'package:career_path/models/institute_accreditation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a NAAC row and round-trips it', () {
    final a = InstituteAccreditation.fromJson({
      'institute_id': 50,
      'body': 'NAAC',
      'programme': '',
      'grade': 'A++',
      'status': 'accredited',
      'valid_until': '2029-03-31',
      'source_url': 'https://naac.gov.in/',
    });
    expect(a.isInstitutionLevel, isTrue);

    final restored = InstituteAccreditation.fromJson(a.toJson());
    expect(restored.body, 'NAAC');
    expect(restored.grade, 'A++');
    expect(restored.validUntil, '2029-03-31');
    expect(restored.sourceUrl, 'https://naac.gov.in/');
  });

  test('an NBA programme row is not institution level', () {
    final a = InstituteAccreditation.fromJson({
      'institute_id': 50,
      'body': 'NBA',
      'programme': 'B.Tech Civil',
      'source_url': 'https://www.nbaind.org/',
    });
    expect(a.isInstitutionLevel, isFalse);
    expect(a.grade, isNull);
  });
}
