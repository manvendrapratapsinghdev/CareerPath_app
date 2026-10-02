import 'package:career_path/models/state_region.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a states row and round-trips it', () {
    final s = StateRegion.fromJson({
      'code': 'IN-JK',
      'lgd_code': 1,
      'country_code': 'IN',
      'name': 'Jammu and Kashmir',
      'kind': 'ut',
      'zone': 'north',
    });
    expect(s.isUnionTerritory, isTrue);

    final restored = StateRegion.fromJson(s.toJson());
    expect(restored.code, 'IN-JK');
    expect(restored.lgdCode, 1);
    expect(restored.name, 'Jammu and Kashmir');
    expect(restored.zone, 'north');
  });

  test('country defaults to India', () {
    final s = StateRegion.fromJson({
      'code': 'IN-RJ',
      'lgd_code': 8,
      'name': 'Rajasthan',
      'kind': 'state',
      'zone': 'north',
    });
    expect(s.countryCode, 'IN');
    expect(s.isUnionTerritory, isFalse);
  });
}
