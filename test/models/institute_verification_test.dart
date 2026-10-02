import 'package:career_path/models/institute_verification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an institute_verifications row and round-trips it', () {
    final v = InstituteVerification.fromJson({
      'institute_id': 375,
      'authority': 'MoE',
      'list_name': 'IIT Council list of Indian Institutes of Technology',
      'list_url': 'https://www.iitsystem.ac.in/',
      'list_as_of': '2026-10-01',
      'reference_id': 'https://www.iitkgp.ac.in',
      'verified_at': '2026-10-01',
    });
    expect(v.instituteId, 375);
    expect(v.authority, 'MoE');

    final restored = InstituteVerification.fromJson(v.toJson());
    expect(restored.listName, v.listName);
    expect(restored.listUrl, 'https://www.iitsystem.ac.in/');
    expect(restored.referenceId, 'https://www.iitkgp.ac.in');
    expect(restored.verifiedAt, '2026-10-01');
  });

  test('optional fields may be missing', () {
    final v = InstituteVerification.fromJson({
      'institute_id': 1,
      'authority': 'UGC',
      'list_name': 'Deemed universities',
    });
    expect(v.listAsOf, isNull);
    expect(v.referenceId, isNull);
    expect(v.listUrl, '');
  });
}
