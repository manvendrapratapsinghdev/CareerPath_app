import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/data/streams_json_parser.dart';
import 'package:career_path/models/stream_model.dart';

void main() {
  late StreamsJsonParser parser;

  setUp(() {
    parser = StreamsJsonParser();
  });

  group('parse', () {
    test('parses valid JSON into list of StreamModel', () {
      const jsonString = '{"streams":[{"id":"science","name":"Science","categoryIds":["cat1","cat2"]}]}';

      final result = parser.parse(jsonString);

      expect(result.length, 1);
      expect(result[0].id, 'science');
      expect(result[0].name, 'Science');
      expect(result[0].categoryIds, ['cat1', 'cat2']);
    });

    test('parses multiple streams', () {
      final jsonString = json.encode({
        'streams': [
          {'id': 'science', 'name': 'Science', 'categoryIds': ['a']},
          {'id': 'commerce', 'name': 'Commerce', 'categoryIds': ['b', 'c']},
          {'id': 'art', 'name': 'Art', 'categoryIds': []},
        ]
      });

      final result = parser.parse(jsonString);

      expect(result.length, 3);
      expect(result[0].id, 'science');
      expect(result[1].id, 'commerce');
      expect(result[2].id, 'art');
      expect(result[2].categoryIds, isEmpty);
    });

    test('parses empty streams list', () {
      const jsonString = '{"streams":[]}';

      final result = parser.parse(jsonString);

      expect(result, isEmpty);
    });
  });

  group('serialize', () {
    test('serializes list of StreamModel to JSON string', () {
      final streams = [
        StreamModel(id: 'science', name: 'Science', categoryIds: ['cat1']),
      ];

      final jsonString = parser.serialize(streams);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      expect(decoded['streams'], isList);
      expect((decoded['streams'] as List).length, 1);
      expect((decoded['streams'] as List)[0]['id'], 'science');
    });

    test('serializes empty list', () {
      final jsonString = parser.serialize([]);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      expect(decoded['streams'], isEmpty);
    });
  });

  group('round-trip', () {
    test('parse then serialize then parse produces equivalent objects', () {
      final original = [
        StreamModel(id: 'science', name: 'Science', categoryIds: ['a', 'b']),
        StreamModel(id: 'commerce', name: 'Commerce', categoryIds: ['c']),
      ];

      final serialized = parser.serialize(original);
      final reparsed = parser.parse(serialized);

      expect(reparsed.length, original.length);
      for (int i = 0; i < original.length; i++) {
        expect(reparsed[i], original[i]);
      }
    });
  });
}
