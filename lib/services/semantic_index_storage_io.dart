import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Map<String, (String, Float32List)>> loadSemanticIndex(
  Object? directory, {
  required int dimensions,
}) async {
  final dir = directory as Directory;
  final meta = File('${dir.path}/ai_semantic_index.json');
  final data = File('${dir.path}/ai_semantic_index.bin');
  if (!await meta.exists() || !await data.exists()) return {};
  try {
    final entries = (jsonDecode(await meta.readAsString()) as List).cast<Map>();
    final floats = Float32List.view(Uint8List.fromList(await data.readAsBytes()).buffer);
    final result = <String, (String, Float32List)>{};
    for (var i = 0; i < entries.length; i++) {
      if ((i + 1) * dimensions > floats.length) break;
      result[entries[i]['id'] as String] = (
        entries[i]['hash'] as String,
        Float32List.fromList(floats.sublist(i * dimensions, (i + 1) * dimensions)),
      );
    }
    return result;
  } on Object {
    return {};
  }
}

Future<void> saveSemanticIndex(
  Object? directory,
  Map<String, (String, Float32List)> entries, {
  required int dimensions,
}) async {
  final dir = directory as Directory;
  await dir.create(recursive: true);
  final ids = entries.keys.toList();
  final floats = Float32List(ids.length * dimensions);
  for (var i = 0; i < ids.length; i++) {
    floats.setAll(i * dimensions, entries[ids[i]]!.$2);
  }
  await File('${dir.path}/ai_semantic_index.bin').writeAsBytes(
    floats.buffer.asUint8List(),
    flush: true,
  );
  await File('${dir.path}/ai_semantic_index.json').writeAsString(
    jsonEncode([
      for (final id in ids) {'id': id, 'hash': entries[id]!.$1},
    ]),
    flush: true,
  );
}
