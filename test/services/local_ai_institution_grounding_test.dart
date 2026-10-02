import 'package:career_path/data/local_database.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:career_path/services/location_service.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  "INSERT INTO states VALUES ('IN-MH', 27, 'IN', 'Maharashtra', 'state', 'west'), "
      "('IN-RJ', 8, 'IN', 'Rajasthan', 'state', 'north'), "
      "('IN-KL', 32, 'IN', 'Kerala', 'state', 'south')",
  "INSERT INTO districts VALUES (1, 'IN-MH', 'Mumbai Suburban'), "
      "(2, 'IN-RJ', 'Jaipur')",
  "INSERT INTO places VALUES (10, 1, 'Mumbai', 'city', 0), "
      "(20, 2, 'Jaipur', 'city', 0)",
  "INSERT INTO place_aliases VALUES ('bombay', 10, NULL, NULL)",
  "INSERT INTO institutes (id, name, city, district, state) VALUES "
      "(1, 'IIT Bombay', 'Mumbai', 'Mumbai Suburban', 'Maharashtra'), "
      "(2, 'NIT Jaipur', 'Jaipur', 'Jaipur', 'Rajasthan')",
  "INSERT INTO institution_groups VALUES ('G1', 'National flagship', NULL, 1), "
      "('G2', 'National technical institutes', NULL, 2)",
  "INSERT INTO families VALUES ('iit', 'Indian Institutes of Technology', 'G1', 'MoE', NULL, 23, NULL), "
      "('nit', 'National Institutes of Technology', 'G2', 'MoE', NULL, 31, NULL)",
  'INSERT INTO institute_classification (institute_id, group_code, family_slug, '
      'ownership, confidence) VALUES '
      "(1, 'G1', 'iit', 'central_govt', 'high'), "
      "(2, 'G2', 'nit', 'central_govt', 'high')",
  "INSERT INTO domains VALUES ('engineering', 'Engineering', 'degree', 'AICTE', 'JEE Main', 1)",
  "INSERT INTO domain_tiers VALUES ('engineering', 1, 'Institutes of National Importance', 'G1,G2', 'iit,nit', 'JEE Advanced')",
  "INSERT INTO institute_domain_tiers VALUES (1, 'engineering', 1), (2, 'engineering', 1)",
  "INSERT INTO campuses VALUES (1, 1, NULL, 10, 1, NULL, NULL), "
      "(2, 2, NULL, 20, 1, NULL, NULL)",
];

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late LocalAiGroundingService grounding;

  setUp(() async {
    local = await openTaxonomyDb(_seed);
    final locations = LocationService(
      loadStates: local.getStates,
      loadCities: local.getInstituteCities,
      loadDistricts: local.getDistricts,
      loadPlaces: local.getPlaces,
      loadPlaceAliases: local.getPlaceAliases,
    );
    final catalog = InstituteCatalogService(
      local.getInstituteCatalog,
      taxonomy: local,
      locations: locations,
    );
    final careers = CareerDataService(ApiClient())
      ..initializeWithData(const <StreamModel>[], const <String, CareerNode>{});
    grounding = LocalAiGroundingService(careers, catalog: catalog);
  });

  tearDown(() => local.close());

  test(
    'typed, chat and voice grounding can cite the same alias-filtered ladder',
    () async {
      final result = await grounding.retrieve(
        query: 'top engineering colleges in Bombay',
      );
      expect(result.text, contains('SOURCE institute:1'));
      expect(result.text, contains('IIT Bombay'));
      expect(
        result.text,
        contains('Institution family: Indian Institutes of Technology'),
      );
      expect(result.text, contains('Campus locations: Mumbai, Maharashtra'));
      expect(
        result.text,
        contains(
          'Location provenance: mapped from existing institute records; not independently verified',
        ),
      );
      expect(result.text, isNot(contains('NIT Jaipur')));
      expect(
        result.sources
            .where((source) => source.sourceType == 'institute')
            .single
            .title,
        'IIT Bombay',
      );
    },
  );

  test(
    'an empty local ladder reports incomplete coverage, no wrong-place results',
    () async {
      final result = await grounding.retrieve(
        query: 'top engineering colleges in Kerala',
      );
      expect(
        result.sources.where((source) => source.sourceType == 'institute'),
        isEmpty,
      );
      expect(
        result.text,
        contains('CareerPath does not currently list matching institutes'),
      );
      expect(result.text, isNot(contains('IIT Bombay')));
    },
  );
}
