import 'dart:io';

import 'package:career_path/data/local_database.dart';
import 'package:career_path/models/state_region.dart';
import 'package:career_path/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/taxonomy_db.dart';

const _seed = [
  "INSERT INTO states VALUES ('IN-RJ', 8, 'IN', 'Rajasthan', 'state', 'north'), "
      "('IN-DL', 7, 'IN', 'Delhi', 'ut', 'north'), "
      "('IN-KA', 29, 'IN', 'Karnataka', 'state', 'south'), "
      "('IN-UP', 9, 'IN', 'Uttar Pradesh', 'state', 'central'), "
      "('IN-OD', 21, 'IN', 'Odisha', 'state', 'east'), "
      "('IN-AS', 18, 'IN', 'Assam', 'state', 'north_east'), "
      "('IN-CG', 22, 'IN', 'Chhattisgarh', 'state', 'central'), "
      "('IN-HP', 2, 'IN', 'Himachal Pradesh', 'state', 'north'), "
      "('IN-JK', 1, 'IN', 'Jammu and Kashmir', 'ut', 'north'), "
      "('IN-TG', 36, 'IN', 'Telangana', 'state', 'south')",
  'INSERT INTO institutes (id, name, city, state) VALUES '
      "(1, 'IIT Jodhpur', 'Jodhpur', 'Rajasthan'), "
      "(2, 'MNIT Jaipur', 'Jaipur', 'Rajasthan'), "
      "(3, 'IISc', 'Bengaluru', 'Karnataka'), "
      "(4, 'Old Bangalore College', 'Bangalore', 'Karnataka'), "
      "(5, 'IIT Delhi', 'New Delhi', 'Delhi'), "
      "(6, 'Delhi College', 'Delhi', 'Delhi'), "
      "(7, 'GGU', 'Bilaspur', 'Chhattisgarh'), "
      "(8, 'AIIMS Bilaspur', 'Bilaspur', 'Himachal Pradesh'), "
      "(9, 'IGNOU Regional', 'Various', NULL), "
      "(10, 'Allahabad University', 'Prayagraj', 'Uttar Pradesh'), "
      "(11, 'Shouted College', 'JAIPUR', 'Rajasthan')",
];

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late LocationService service;

  setUp(() async {
    local = await openTaxonomyDb(_seed);
    service = LocationService(
      loadStates: local.getStates,
      loadCities: local.getInstituteCities,
    );
  });

  tearDown(() => local.close());

  group('resolve', () {
    test('a state name resolves to the state', () async {
      final place = await service.resolve('Rajasthan');
      expect(place?.level, PlaceLevel.state);
      expect(place?.state?.code, 'IN-RJ');
      expect(place?.via, PlaceMatch.name);
      expect(place?.label, 'Rajasthan');
      expect((await service.resolve('uttar pradesh'))?.state?.code, 'IN-UP');
      expect((await service.resolve('Jammu & Kashmir'))?.state?.code, 'IN-JK');
    });

    test('abbreviations and former names resolve to the state', () async {
      final rj = await service.resolve('RJ');
      expect(rj?.state?.code, 'IN-RJ');
      expect(rj?.via, PlaceMatch.abbreviation);
      expect((await service.resolve('U.P.'))?.state?.code, 'IN-UP');
      expect((await service.resolve('TS'))?.state?.code, 'IN-TG');
      final orissa = await service.resolve('Orissa');
      expect(orissa?.state?.code, 'IN-OD');
      expect(orissa?.via, PlaceMatch.alias);
    });

    test('a city resolves with its state', () async {
      final place = await service.resolve('jodhpur');
      expect(place?.level, PlaceLevel.city);
      expect(place?.city, 'Jodhpur');
      expect(place?.state?.code, 'IN-RJ');
      expect(place?.via, PlaceMatch.name);
      expect(place?.district, isNull);
    });

    test('an old city name resolves to the current one, both spellings '
        'counted', () async {
      final place = await service.resolve('Bangalore');
      expect(place?.level, PlaceLevel.city);
      expect(place?.city, 'Bengaluru');
      expect(place?.state?.code, 'IN-KA');
      expect(place?.via, PlaceMatch.alias);
      expect(place?.cityKeys, containsAll(['bengaluru', 'bangalore']));
      expect((await service.resolve('Bengaluru'))?.via, PlaceMatch.name);
      // An alias with no institutes yet still resolves (honest empty list).
      final bombay = await service.resolve('Bombay');
      expect(bombay?.city, 'Mumbai');
      expect(bombay?.state?.code, isNull); // no IN-MH row in this fixture
      expect((await service.resolve('allahabad'))?.city, 'Prayagraj');
    });

    test('a state name wins over a city of the same name', () async {
      final delhi = await service.resolve('Delhi');
      expect(delhi?.level, PlaceLevel.state);
      expect(delhi?.state?.code, 'IN-DL');
      final newDelhi = await service.resolve('New Delhi');
      expect(newDelhi?.level, PlaceLevel.city);
      expect(newDelhi?.state?.code, 'IN-DL');
    });

    test('a city in two states has no state', () async {
      final place = await service.resolve('Bilaspur');
      expect(place?.city, 'Bilaspur');
      expect(place?.state, isNull);
    });

    test('places are found inside a sentence', () async {
      final city = await service.resolve('engineering colleges in Jodhpur');
      expect(city?.city, 'Jodhpur');
      final both = await service.resolve('law colleges in jaipur rajasthan');
      expect(both?.city, 'Jaipur');
      final state = await service.resolve('top MBA colleges in UP');
      expect(state?.state?.code, 'IN-UP');
      final named = await service.resolve('colleges in new delhi');
      expect(named?.city, 'New Delhi');
    });

    test('short words are not read as abbreviations in a sentence', () async {
      // "as" (Assam) and "or" (Odisha) are words here.
      expect(await service.resolve('as good or better colleges'), isNull);
      expect((await service.resolve('AS'))?.state?.code, 'IN-AS');
    });

    test(
      'a city that disagrees with the named state yields the state',
      () async {
        final place = await service.resolve('jodhpur karnataka');
        expect(place?.level, PlaceLevel.state);
        expect(place?.state?.code, 'IN-KA');
      },
    );

    test('unknown, empty and placeholder text resolves to null', () async {
      expect(await service.resolve('   '), isNull);
      expect(await service.resolve('Atlantis'), isNull);
      expect(await service.resolve('Various'), isNull);
    });

    test('resolveLoaded is null before loading and works after', () async {
      expect(service.resolveLoaded('Rajasthan'), isNull);
      await service.ensureLoaded();
      expect(service.resolveLoaded('Rajasthan')?.state?.code, 'IN-RJ');
    });
  });

  group('ResolvedPlace.matches', () {
    test('a state matches records in that state', () async {
      final place = (await service.resolve('Delhi'))!;
      expect(place.matches(city: 'New Delhi', state: 'Delhi'), isTrue);
      expect(place.matches(city: 'Jaipur', state: 'Rajasthan'), isFalse);
      // City but no state: the city carries the state's name.
      expect(place.matches(city: 'New Delhi'), isTrue);
      expect(place.matches(city: 'Jaipur'), isFalse);
    });

    test('a city matches every spelling, by city or district', () async {
      final place = (await service.resolve('Bangalore'))!;
      expect(place.matches(city: 'Bangalore', state: 'Karnataka'), isTrue);
      expect(place.matches(city: 'Bengaluru', state: 'Karnataka'), isTrue);
      expect(place.matches(district: 'Bengaluru'), isTrue);
      expect(place.matches(city: 'Mysuru', state: 'Karnataka'), isFalse);
      // Same city name in another state is a different place.
      expect(place.matches(city: 'Bengaluru', state: 'Rajasthan'), isFalse);
    });

    test('a city in two states matches either', () async {
      final place = (await service.resolve('Bilaspur'))!;
      expect(
        place.matches(city: 'Bilaspur', state: 'Himachal Pradesh'),
        isTrue,
      );
      expect(place.matches(city: 'Bilaspur', state: 'Chhattisgarh'), isTrue);
    });
  });

  group('lookups', () {
    test('states are listed by name and look up by name or code', () async {
      await service.ensureLoaded();
      expect(service.states.first.name, 'Assam');
      expect(service.stateNamed('tamil nadu'), isNull);
      expect(service.stateNamed('uttar pradesh')?.code, 'IN-UP');
      expect(service.stateByCode('in-rj')?.name, 'Rajasthan');
      expect(service.stateByCode('IN-XX'), isNull);
    });

    test('citiesIn lists the cities of one state', () async {
      await service.ensureLoaded();
      // "JAIPUR" and "Jaipur" are one city, shown in mixed case.
      expect(service.citiesIn('IN-RJ'), ['Jaipur', 'Jodhpur']);
      expect(service.citiesIn('IN-KA'), ['Bengaluru']);
      expect(service.citiesIn('IN-CG'), ['Bilaspur']);
      expect(service.citiesIn('IN-HP'), ['Bilaspur']);
    });

    test('loads once even when asked concurrently', () async {
      var calls = 0;
      final counted = LocationService(
        loadStates: () async {
          calls++;
          return const [
            StateRegion(
              code: 'IN-GA',
              lgdCode: 30,
              name: 'Goa',
              kind: 'state',
              zone: 'west',
            ),
          ];
        },
        loadCities: () async => const [(city: 'Goa', state: 'Goa')],
      );
      await Future.wait([counted.ensureLoaded(), counted.resolve('goa')]);
      await counted.resolve('GA');
      expect(calls, 1);
      expect(counted.resolveLoaded('Goa')?.level, PlaceLevel.state);
    });

    test('compact keeps lowercase letters and digits only', () {
      expect(LocationService.compact(' Tamil Nadu! '), 'tamilnadu');
      expect(LocationService.compact(null), '');
    });
  });

  test('the bundled asset resolves real places', () async {
    // Read a private copy: another process may be rewriting the asset.
    final tmp = await Directory.systemTemp.createTemp('career_path_db');
    final copy = await File(
      'assets/data/career_path.db',
    ).copy(p.join(tmp.path, 'career_path.db'));
    final real = LocalDatabase.withDatabase(
      await databaseFactoryFfi.openDatabase(
        copy.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      ),
    );
    try {
      final places = LocationService(
        loadStates: real.getStates,
        loadCities: real.getInstituteCities,
      );
      await places.ensureLoaded();
      if (places.states.isEmpty) return; // asset predates the states table
      expect((await places.resolve('RJ'))?.state?.name, 'Rajasthan');
      expect((await places.resolve('Tamil Nadu'))?.state?.code, 'IN-TN');
      final bangalore = await places.resolve('bangalore');
      expect(bangalore?.city, 'Bengaluru');
      expect(bangalore?.state?.code, 'IN-KA');
      expect(places.citiesIn('IN-RJ'), contains('Jodhpur'));
    } finally {
      await real.close();
      await tmp.delete(recursive: true);
    }
  });
}
