import 'dart:typed_data';

/// Semantic indexing is optional on the web; keyword grounding remains fully
/// available without filesystem persistence.
Future<Map<String, (String, Float32List)>> loadSemanticIndex(
  Object? directory, {
  required int dimensions,
}) async => {};

Future<void> saveSemanticIndex(
  Object? directory,
  Map<String, (String, Float32List)> entries, {
  required int dimensions,
}) async {}
