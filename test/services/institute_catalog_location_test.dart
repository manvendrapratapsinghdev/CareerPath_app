import 'package:career_path/data/local_database.dart';
import 'package:career_path/models/institute_location_filter.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  "INSERT INTO states VALUES ('IN-MH', 27, 'IN', 'Maharashtra', 'state', 'west'), "
      "('IN-RJ', 8, 'IN', 'Rajasthan', 'state', 'north')",
  "INSERT INTO districts VALUES (1, 'IN-MH', 'Mumbai Suburban'), "
      "(2, 'IN-RJ', 'Jaipur'), "
      "(3, 'IN-MH', 'Other Mumbai')",
  "INSERT INTO places VALUES (10, 1, 'Mumbai', 'city', 0), "
      "(20, 2, 'Jaipur', 'city', 0), "
      "(30, 3, 'Mumbai', 'city', 0)",
  "INSERT INTO place_aliases VALUES ('bombay', 10, NULL, NULL)",
  'INSERT INTO institutes (id, name, city, district, state) VALUES '
      "(1, 'IIT Bombay', 'Mumbai', 'Mumbai Suburban', 'Maharashtra'), "
      "(2, 'Legacy Mumbai College', 'Mumbai', 'Mumbai Suburban', 'Maharashtra'), "
      "(3, 'NIT Jaipur', 'Jaipur', 'Jaipur', 'Rajasthan'), "
      "(4, 'Other Mumbai College', 'Mumbai', 'Other Mumbai', 'Maharashtra')",
  "INSERT INTO institution_groups VALUES ('G1', 'National flagship', NULL, 1), "
      "('G2', 'National technical institutes', NULL, 2)",
  "INSERT INTO families VALUES ('iit', 'IITs', 'G1', 'MoE', NULL, NULL, NULL), "
      "('nit', 'NITs', 'G2', 'MoE', NULL, NULL, NULL)",
  'INSERT INTO institute_classification (institute_id, group_code, family_slug, '
      'ownership, confidence) VALUES '
      "(1, 'G1', 'iit', 'central_govt', 'high'), "
      "(2, 'G8', NULL, 'private', 'medium'), "
      "(3, 'G2', 'nit', 'central_govt', 'high'), "
      "(4, 'G2', 'nit', 'central_govt', 'high')",
  "INSERT INTO domains VALUES ('engineering', 'Engineering', 'degree', 'AICTE', 'JEE Main', 1)",
  "INSERT INTO domain_tiers VALUES ('engineering', 1, 'Institutes of National Importance', 'G1,G2', 'iit,nit', 'JEE Advanced')",
  "INSERT INTO institute_domain_tiers VALUES (1, 'engineering', 1), "
      "(2, 'engineering', 1), (3, 'engineering', 1), "
      "(4, 'engineering', 1)",
  "INSERT INTO campuses VALUES (1, 1, NULL, 10, 1, NULL, NULL), "
      "(2, 3, NULL, 20, 1, NULL, NULL), "
      "(3, 4, NULL, 30, 1, NULL, NULL)",
];

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late LocationService locations;
  late InstituteCatalogService catalog;

  setUp(() async {
    local = await openTaxonomyDb(_seed);
    locations = LocationService(
      loadStates: local.getStates,
      loadCities: local.getInstituteCities,
      loadDistricts: local.getDistricts,
      loadPlaces: local.getPlaces,
      loadPlaceAliases: local.getPlaceAliases,
    );
    catalog = InstituteCatalogService(
      local.getInstituteCatalog,
      taxonomy: local,
      locations: locations,
    );
  });

  tearDown(() => local.close());

  test(
    'resolves canonical/alias places and matches mapped campuses only',
    () async {
      await catalog.ensureLoaded();
      await catalog.ensureLocationsLoaded();
      final bombay = await locations.resolve('Bombay');
      expect(bombay?.label, 'Mumbai');
      expect(bombay?.district, 'Mumbai Suburban');
      expect(bombay?.state?.code, 'IN-MH');

      final matches = catalog.find('engineering colleges in Bombay');
      // College ladder queries share the same mapped-campus place contract.
      final ladder = await catalog.ladderSearch(
        'top engineering colleges in Bombay',
      );
      expect(ladder?.map((item) => item.instituteId), [1]);
      expect(matches.place, 'Mumbai');
      expect(matches.hits.map((hit) => hit.record.institute.id), [1]);

      final familyAliasLadder = await catalog.ladderSearch(
        'top IIT colleges in Bombay',
      );
      expect(familyAliasLadder?.map((item) => item.instituteId), [1]);
    },
  );

  test(
    'cascading state/district/city filters exclude unmapped legacy rows',
    () async {
      await locations.ensureLoaded();
      expect(
        locations.districtsIn('IN-MH').map((district) => district.lgdCode),
        contains(1),
      );
      expect(locations.placesInDistrict(1).single.name, 'Mumbai');

      final byState = await catalog.filter(
        const InstituteFilter(
          locationFilter: InstituteLocationFilter(
            stateCode: 'IN-MH',
            stateName: 'Maharashtra',
          ),
        ),
      );
      expect(byState.map((item) => item.instituteId), [1, 4]);

      final byDistrict = await catalog.filter(
        const InstituteFilter(
          locationFilter: InstituteLocationFilter(
            stateCode: 'IN-MH',
            stateName: 'Maharashtra',
            districtLgd: 1,
            districtName: 'Mumbai Suburban',
          ),
        ),
      );
      expect(byDistrict.map((item) => item.instituteId), [1]);

      final byCity = await catalog.filter(
        const InstituteFilter(
          locationFilter: InstituteLocationFilter(
            stateCode: 'IN-MH',
            stateName: 'Maharashtra',
            districtLgd: 1,
            districtName: 'Mumbai Suburban',
            placeId: 10,
            placeName: 'Mumbai',
          ),
        ),
      );
      expect(byCity.map((item) => item.instituteId), [1]);

      final sameNameDifferentPlace = await catalog.filter(
        const InstituteFilter(
          locationFilter: InstituteLocationFilter(
            stateCode: 'IN-MH',
            stateName: 'Maharashtra',
            districtLgd: 1,
            districtName: 'Mumbai Suburban',
            placeId: 10,
            placeName: 'Mumbai',
          ),
        ),
      );
      expect(sameNameDifferentPlace.map((item) => item.instituteId), [1]);

      // An unmapped row does not inherit the old city/state strings.
      final legacy = await catalog.displayInfo(2);
      expect(legacy?.city, isNull);
      expect(legacy?.state, isNull);
    },
  );
}
