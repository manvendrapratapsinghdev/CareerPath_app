import 'dart:typed_data';

import 'semantic_index_storage_stub.dart'
    if (dart.library.io) 'semantic_index_storage_io.dart'
    if (dart.library.js_interop) 'semantic_index_storage_web.dart' as platform;

Future<Map<String, (String, Float32List)>> loadSemanticIndex(
  Object? directory, {
  required int dimensions,
}) => platform.loadSemanticIndex(directory, dimensions: dimensions);

Future<void> saveSemanticIndex(
  Object? directory,
  Map<String, (String, Float32List)> entries, {
  required int dimensions,
}) => platform.saveSemanticIndex(
  directory,
  entries,
  dimensions: dimensions,
);
