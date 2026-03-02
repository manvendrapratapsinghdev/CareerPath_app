import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/stream_model.dart';

class StreamsJsonParser {
  /// Parses raw JSON string into a list of StreamModel objects.
  List<StreamModel> parse(String jsonString) {
    final Map<String, dynamic> jsonMap = json.decode(jsonString) as Map<String, dynamic>;
    final List<dynamic> streamsList = jsonMap['streams'] as List<dynamic>;
    return streamsList
        .map((e) => StreamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Serializes a list of StreamModel objects back to a JSON string.
  String serialize(List<StreamModel> streams) {
    return json.encode({
      'streams': streams.map((s) => s.toJson()).toList(),
    });
  }

  /// Loads and parses streams.json from Flutter assets.
  Future<List<StreamModel>> loadFromAssets() async {
    final jsonString = await rootBundle.loadString('assets/data/streams.json');
    return parse(jsonString);
  }
}
