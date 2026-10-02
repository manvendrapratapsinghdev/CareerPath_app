import 'package:career_path/models/institute_classification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a government row: flags as ints, UGC not applicable', () {
    final c = InstituteClassification.fromJson({
      'institute_id': 12,
      'group_code': 'G1',
      'family_slug': 'iit',
      'ownership': 'central_govt',
      'statutory_basis': 'Institutes of Technology Act, 1961',
      'admits_students': 1,
      'parent_institute_id': null,
      'is_family_record': 0,
      'regulators': 'MoE',
      'listed': 1,
      'ugc_verified': null,
      'confidence': 'high',
      'source_url': 'https://www.iitsystem.ac.in/',
      'verified_at': '2026-10-01',
      'notes': null,
    });
    expect(c.instituteId, 12);
    expect(c.familySlug, 'iit');
    expect(c.ugcVerified, isNull);
    expect(c.isPrivate, isFalse);
    expect(c.isTopLevelListing, isTrue);

    final restored = InstituteClassification.fromJson(c.toJson());
    expect(restored.statutoryBasis, 'Institutes of Technology Act, 1961');
    expect(restored.confidence, 'high');
    expect(restored.listed, isTrue);
    expect(restored.ugcVerified, isNull);
    expect(c.toJson()['listed'], 1);
    expect(c.toJson()['is_family_record'], 0);
  });

  test('parses a private row with a UGC No result', () {
    final c = InstituteClassification.fromJson({
      'institute_id': 7,
      'group_code': 'G8',
      'ownership': 'private',
      'ugc_verified': 0,
      'ugc_list_name': 'UGC 2(f)',
      'ugc_source_url': 'https://www.ugc.gov.in/',
      'ugc_checked_at': '2026-10-01',
      'regulators': 'AICTE, NBA',
      'confidence': 'medium',
    });
    expect(c.isPrivate, isTrue);
    expect(c.ugcVerified, isFalse);
    expect(c.regulatorList, ['AICTE', 'NBA']);

    final restored = InstituteClassification.fromJson(c.toJson());
    expect(restored.ugcVerified, isFalse);
    expect(restored.ugcListName, 'UGC 2(f)');
    expect(restored.ugcCheckedAt, '2026-10-01');
  });

  test('department and family rows are not top-level listings', () {
    final department = InstituteClassification.fromJson({
      'institute_id': 10,
      'group_code': 'G1',
      'parent_institute_id': 442,
      'confidence': 'high',
    });
    expect(department.isChild, isTrue);
    expect(department.isTopLevelListing, isFalse);

    final family = InstituteClassification.fromJson({
      'institute_id': 1,
      'group_code': 'G1',
      'is_family_record': true,
      'listed': false,
      'confidence': 'high',
    });
    expect(family.isFamilyRecord, isTrue);
    expect(family.listed, isFalse);
    expect(family.isTopLevelListing, isFalse);
  });

  test('missing flags take the schema defaults', () {
    final c = InstituteClassification.fromJson({
      'institute_id': 3,
      'group_code': 'G6',
    });
    expect(c.admitsStudents, isTrue);
    expect(c.listed, isTrue);
    expect(c.isFamilyRecord, isFalse);
    expect(c.confidence, 'low');
  });
}
