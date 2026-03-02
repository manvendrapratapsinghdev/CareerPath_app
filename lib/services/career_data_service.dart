import 'package:flutter/foundation.dart' show visibleForTesting;

import '../data/career_paths_json_parser.dart';
import '../data/streams_json_parser.dart';
import '../models/career_node.dart';
import '../models/stream_model.dart';

class CareerDataService {
  final StreamsJsonParser _streamsParser;
  final CareerPathsJsonParser _careerPathsParser;

  List<StreamModel> _streams = [];
  Map<String, CareerNode> _nodesMap = {};
  bool _initialized = false;

  CareerDataService(this._streamsParser, this._careerPathsParser);

  /// Initializes by loading both JSON files into memory. Call once at app start.
  Future<void> initialize() async {
    try {
      _streams = await _streamsParser.loadFromAssets();
      _nodesMap = await _careerPathsParser.loadFromAssets();
      _initialized = true;
    } catch (e) {
      _streams = [];
      _nodesMap = {};
      _initialized = false;
      rethrow;
    }
  }

  /// Returns all available streams.
  List<StreamModel> getAllStreams() {
    return List.unmodifiable(_streams);
  }

  /// Returns top-level career categories for a given stream ID.
  List<CareerNode> getCategoriesForStream(String streamId) {
    final stream = _streams.cast<StreamModel?>().firstWhere(
          (s) => s!.id == streamId,
          orElse: () => null,
        );
    if (stream == null) return [];
    return stream.categoryIds
        .map((id) => _nodesMap[id])
        .whereType<CareerNode>()
        .toList();
  }

  /// Returns child career nodes for a given parent node ID.
  List<CareerNode> getChildrenOf(String nodeId) {
    final node = _nodesMap[nodeId];
    if (node == null) return [];
    return node.childIds
        .map((id) => _nodesMap[id])
        .whereType<CareerNode>()
        .toList();
  }

  /// Returns a single career node by ID, or null if not found.
  CareerNode? getNodeById(String nodeId) {
    return _nodesMap[nodeId];
  }

  /// Initializes with pre-parsed data. For testing only.
  @visibleForTesting
  void initializeWithData(
      List<StreamModel> streams, Map<String, CareerNode> nodes) {
    _streams = streams;
    _nodesMap = nodes;
    _initialized = true;
  }
}
