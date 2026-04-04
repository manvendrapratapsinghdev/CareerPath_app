import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/data_source.dart';
import 'package:career_path/data/local_data_source.dart';
import 'package:career_path/data/local_database.dart';

/// Minimal LocalDatabase stub for testing.
class _StubDatabase extends LocalDatabase {
  @override
  Future<void> init() async {}
  @override
  Future<List<Map<String, dynamic>>> getStreams() async => [];
  @override
  Future<List<Map<String, dynamic>>> getAllNodes() async => [];
}

void main() {
  late CareerDataService service;

  setUp(() {
    // Use LocalDataSource so isLocal == true
    service = CareerDataService(LocalDataSource(_StubDatabase()));
  });

  test('returns 0 for leaf node', () {
    service.initializeWithData(
      [StreamModel(id: 's', name: 'S', rootNodeCount: 1, categoryIds: ['a'])],
      {
        'a': CareerNode(id: 'a', name: 'A', childIds: [], childCount: 0),
      },
    );
    expect(service.getMaxDepthFrom('a'), 0);
  });

  test('returns correct depth for linear chain', () {
    service.initializeWithData(
      [StreamModel(id: 's', name: 'S', rootNodeCount: 1, categoryIds: ['a'])],
      {
        'a': CareerNode(id: 'a', name: 'A', childIds: ['b'], childCount: 1),
        'b': CareerNode(id: 'b', name: 'B', childIds: ['c'], childCount: 1),
        'c': CareerNode(id: 'c', name: 'C', childIds: [], childCount: 0),
      },
    );
    expect(service.getMaxDepthFrom('a'), 2);
    expect(service.getMaxDepthFrom('b'), 1);
    expect(service.getMaxDepthFrom('c'), 0);
  });

  test('returns longest branch for branching tree', () {
    service.initializeWithData(
      [StreamModel(id: 's', name: 'S', rootNodeCount: 1, categoryIds: ['a'])],
      {
        'a': CareerNode(
            id: 'a', name: 'A', childIds: ['b', 'c'], childCount: 2),
        'b': CareerNode(id: 'b', name: 'B', childIds: [], childCount: 0),
        'c': CareerNode(id: 'c', name: 'C', childIds: ['d'], childCount: 1),
        'd': CareerNode(id: 'd', name: 'D', childIds: [], childCount: 0),
      },
    );
    expect(service.getMaxDepthFrom('a'), 2); // a → c → d
  });

  test('returns null for unknown nodeId', () {
    service.initializeWithData(
      [StreamModel(id: 's', name: 'S', rootNodeCount: 0, categoryIds: [])],
      {},
    );
    expect(service.getMaxDepthFrom('nonexistent'), isNull);
  });

  test('returns null for API mode service', () {
    final apiService = CareerDataService(_FakeApiDataSource());
    apiService.initializeWithData(
      [StreamModel(id: 's', name: 'S', rootNodeCount: 1, categoryIds: ['a'])],
      {
        'a': CareerNode(id: 'a', name: 'A', childIds: [], childCount: 0),
      },
    );
    expect(apiService.getMaxDepthFrom('a'), isNull);
  });
}

class _FakeApiDataSource implements DataSource {
  @override
  Future<List<Map<String, dynamic>>> getStreams(
          {bool forceRefresh = false}) async =>
      [];
  @override
  Future<List<Map<String, dynamic>>> getStreamRootNodes(int streamApiId,
          {bool forceRefresh = false}) async =>
      [];
  @override
  Future<List<Map<String, dynamic>>> getNodeChildren(int nodeApiId,
          {bool forceRefresh = false}) async =>
      [];
  @override
  Future<Map<String, dynamic>> getNodeDetails(int nodeApiId,
          {bool forceRefresh = false}) async =>
      {};
}
