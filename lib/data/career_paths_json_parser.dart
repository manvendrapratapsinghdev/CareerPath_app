import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/career_node.dart';

class CareerPathsJsonParser {
  /// Parses raw JSON string into a map of CareerNode objects keyed by ID.
  Map<String, CareerNode> parse(String jsonString) {
    final Map<String, dynamic> jsonMap =
        json.decode(jsonString) as Map<String, dynamic>;
    final List<dynamic> nodesList = jsonMap['nodes'] as List<dynamic>;
    final nodes = nodesList
        .map((e) => CareerNode.fromJson(e as Map<String, dynamic>))
        .toList();
    return {for (final node in nodes) node.id: node};
  }

  /// Serializes a map of CareerNode objects back to a JSON string.
  String serialize(Map<String, CareerNode> nodes) {
    return json.encode({
      'nodes': nodes.values.map((n) => n.toJson()).toList(),
    });
  }

  /// Loads and parses career_paths.json from Flutter assets.
  Future<Map<String, CareerNode>> loadFromAssets() async {
    final jsonString =
        await rootBundle.loadString('assets/data/career_paths.json');
    return parse(jsonString);
  }
}
