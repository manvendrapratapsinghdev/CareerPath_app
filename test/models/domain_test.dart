import 'package:career_path/models/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a domains row and round-trips it', () {
    final d = Domain.fromJson({
      'slug': 'engineering',
      'name': 'Engineering',
      'route_type': 'degree',
      'regulators': 'AICTE',
      'entrance_exams': 'JEE Advanced; JEE Main; state CETs',
      'sort_order': 1,
    });
    expect(d.hasCollegeLadder, isTrue);
    expect(d.entranceExamList, ['JEE Advanced', 'JEE Main', 'state CETs']);

    final restored = Domain.fromJson(d.toJson());
    expect(restored.slug, 'engineering');
    expect(restored.routeType, 'degree');
    expect(restored.regulators, 'AICTE');
    expect(restored.sortOrder, 1);
  });

  test('professional and exam routes have no college ladder', () {
    final d = Domain.fromJson({
      'slug': 'ca_cma_cs',
      'name': 'CA, CMA and CS',
      'route_type': 'professional_body',
      'sort_order': 15,
    });
    expect(d.hasCollegeLadder, isFalse);
    expect(d.regulatorList, isEmpty);
  });
}
