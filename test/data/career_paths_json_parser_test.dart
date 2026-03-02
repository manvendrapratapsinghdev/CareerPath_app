import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/data/career_paths_json_parser.dart';
import 'package:career_path/models/career_node.dart';

void main() {
  late CareerPathsJsonParser parser;

  setUp(() {
    parser = CareerPathsJsonParser();
  });

  group('parse', () {
    test('parses valid JSON into map of CareerNode keyed by ID', () {
      final jsonString = json.encode({
        'nodes': [
          {'id': 'eng', 'name': 'Engineering', 'parentId': null, 'childIds': ['cs', 'mech']},
          {'id': 'cs', 'name': 'Computer Science', 'parentId': 'eng', 'childIds': []},
        ]
      });

      final result = parser.parse(jsonString);

      expect(result.length, 2);
      expect(result['eng']!.name, 'Engineering');
      expect(result['eng']!.childIds, ['cs', 'mech']);
      expect(result['cs']!.parentId, 'eng');
      expect(result['cs']!.isLeaf, isTrue);
    });

    test('parses empty nodes list', () {
      const jsonString = '{"nodes":[]}';
      final result = parser.parse(jsonString);
      expect(result, isEmpty);
    });

    test('handles nodes with no parentId', () {
      final jsonString = json.encode({
        'nodes': [
          {'id': 'root', 'name': 'Root', 'childIds': ['a']},
        ]
      });

      final result = parser.parse(jsonString);
      expect(result['root']!.parentId, isNull);
    });
  });

  group('serialize', () {
    test('serializes map of CareerNode to JSON string', () {
      final nodes = {
        'eng': CareerNode(id: 'eng', name: 'Engineering', childIds: ['cs']),
      };

      final jsonString = parser.serialize(nodes);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      expect(decoded['nodes'], isList);
      expect((decoded['nodes'] as List).length, 1);
      expect((decoded['nodes'] as List)[0]['id'], 'eng');
    });

    test('serializes empty map', () {
      final jsonString = parser.serialize({});
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      expect(decoded['nodes'], isEmpty);
    });
  });

  group('round-trip', () {
    test('parse then serialize then parse produces equivalent objects', () {
      final original = {
        'eng': CareerNode(id: 'eng', name: 'Engineering', childIds: ['cs', 'mech']),
        'cs': CareerNode(id: 'cs', name: 'CS', parentId: 'eng', childIds: []),
        'mech': CareerNode(id: 'mech', name: 'Mechanical', parentId: 'eng', childIds: []),
      };

      final serialized = parser.serialize(original);
      final reparsed = parser.parse(serialized);

      expect(reparsed.length, original.length);
      for (final key in original.keys) {
        expect(reparsed[key], original[key]);
      }
    });
  });
}
