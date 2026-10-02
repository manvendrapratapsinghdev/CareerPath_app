import 'package:career_path/models/institution_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an institution_groups row and round-trips it', () {
    final group = InstitutionGroup.fromJson({
      'code': 'G2',
      'name': 'National technical institutes',
      'description': 'NIT, IIIT and IIEST.',
      'sort_order': 2,
    });
    expect(group.code, 'G2');
    expect(group.sortOrder, 2);
    expect(group.admitsStudents, isTrue);

    final restored = InstitutionGroup.fromJson(group.toJson());
    expect(restored.name, 'National technical institutes');
    expect(restored.description, 'NIT, IIIT and IIEST.');
  });

  test('group X admits no students and missing fields default', () {
    final group = InstitutionGroup.fromJson({'code': 'X', 'name': 'None'});
    expect(group.admitsStudents, isFalse);
    expect(group.description, isNull);
    expect(group.sortOrder, 0);
  });
}
