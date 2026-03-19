import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';

void main() {
  late CareerDataService service;

  final testStreams = [
    StreamModel(id: 'science', name: 'Science', categoryIds: ['sci_maths', 'sci_bio']),
    StreamModel(id: 'commerce', name: 'Commerce', categoryIds: ['comm_ca']),
  ];

  final testNodes = <String, CareerNode>{
    'sci_maths': CareerNode(id: 'sci_maths', name: 'Maths', childIds: ['btech', 'bsc']),
    'sci_bio': CareerNode(id: 'sci_bio', name: 'Bio', childIds: ['mbbs']),
    'btech': CareerNode(id: 'btech', name: 'B.Tech', parentId: 'sci_maths', childIds: []),
    'bsc': CareerNode(id: 'bsc', name: 'B.Sc', parentId: 'sci_maths', childIds: []),
    'mbbs': CareerNode(id: 'mbbs', name: 'MBBS', parentId: 'sci_bio', childIds: []),
    'comm_ca': CareerNode(id: 'comm_ca', name: 'CA', childIds: []),
  };

  setUp(() {
    service = CareerDataService(ApiClient());
    service.initializeWithData(testStreams, testNodes);
  });

  group('getAllStreams', () {
    test('returns all parsed streams', () {
      final streams = service.getAllStreams();
      expect(streams.length, 2);
      expect(streams[0].id, 'science');
      expect(streams[1].id, 'commerce');
    });

    test('returns unmodifiable list', () {
      final streams = service.getAllStreams();
      expect(() => streams.add(StreamModel(id: 'x', name: 'X', categoryIds: [])),
          throwsUnsupportedError);
    });
  });

  group('getCategoriesForStream', () {
    test('returns correct nodes for science stream', () {
      final categories = service.getCategoriesForStream('science');
      expect(categories.length, 2);
      expect(categories.map((c) => c.id), containsAll(['sci_maths', 'sci_bio']));
    });

    test('returns correct nodes for commerce stream', () {
      final categories = service.getCategoriesForStream('commerce');
      expect(categories.length, 1);
      expect(categories[0].id, 'comm_ca');
    });

    test('returns empty list for unknown stream', () {
      final categories = service.getCategoriesForStream('unknown');
      expect(categories, isEmpty);
    });
  });

  group('getChildrenOf', () {
    test('returns correct child nodes', () {
      final children = service.getChildrenOf('sci_maths');
      expect(children.length, 2);
      expect(children.map((c) => c.id), containsAll(['btech', 'bsc']));
    });

    test('returns empty list for leaf node', () {
      final children = service.getChildrenOf('btech');
      expect(children, isEmpty);
    });

    test('returns empty list for unknown node', () {
      final children = service.getChildrenOf('nonexistent');
      expect(children, isEmpty);
    });
  });

  group('getNodeById', () {
    test('returns node for valid ID', () {
      final node = service.getNodeById('sci_maths');
      expect(node, isNotNull);
      expect(node!.name, 'Maths');
    });

    test('returns null for unknown ID', () {
      final node = service.getNodeById('nonexistent');
      expect(node, isNull);
    });
  });
}
