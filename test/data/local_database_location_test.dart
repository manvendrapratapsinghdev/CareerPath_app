import 'package:career_path/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  "INSERT INTO states VALUES ('IN-MH', 27, 'IN', 'Maharashtra', 'state', 'west'), "
      "('IN-RJ', 8, 'IN', 'Rajasthan', 'state', 'north')",
  "INSERT INTO districts VALUES (1, 'IN-MH', 'Mumbai Suburban'), "
      "(2, 'IN-RJ', 'Jaipur')",
  "INSERT INTO places VALUES (10, 1, 'Mumbai', 'city', 0), "
      "(20, 2, 'Jaipur', 'city', 0)",
  "INSERT INTO place_aliases VALUES ('bombay', 10, NULL, NULL)",
  "INSERT INTO institutes (id, name) VALUES (100, 'IIT Bombay')",
  "INSERT INTO campuses VALUES (1, 100, NULL, 10, 1, NULL, NULL)",
];

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  setUp(() async => local = await openTaxonomyDb(_seed));
  tearDown(() => local.close());

  test('reads and filters district, place, and alias tables', () async {
    expect((await local.getDistricts()).map((district) => district.name), [
      'Jaipur',
      'Mumbai Suburban',
    ]);
    expect((await local.getDistricts(stateCode: 'IN-MH')).single.lgdCode, 1);
    expect((await local.getPlaces()).map((place) => place.name), [
      'Jaipur',
      'Mumbai',
    ]);
    expect((await local.getPlaces(districtLgd: 1)).single.id, 10);
    final alias = (await local.getPlaceAliases()).single;
    expect(alias.alias, 'bombay');
    expect(alias.placeId, 10);
  });

  test(
    'campuses and institute catalog use the full canonical place path',
    () async {
      final campus = (await local.getCampuses()).single;
      expect(campus.instituteId, 100);
      expect(campus.placeName, 'Mumbai');
      expect(campus.districtLgd, 1);
      expect(campus.stateCode, 'IN-MH');
      // No source URL means this is mapped, not individually source-verified.
      expect(campus.sourceUrl, isNull);
      expect(campus.verifiedAt, isNull);

      final institute = (await local.getInstituteCatalog()).single;
      expect((institute['campuses'] as List).single['place_name'], 'Mumbai');
      expect(institute['classification'], isNull);
    },
  );
}
