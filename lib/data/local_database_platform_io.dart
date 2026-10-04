import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<Database> openBundledDatabase({
  required String assetPath,
  required String databaseName,
}) async {
  final dbDir = await getDatabasesPath();
  final dbPath = p.join(dbDir, databaseName);
  await Directory(dbDir).create(recursive: true);

  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  await File(dbPath).writeAsBytes(bytes, flush: true);
  return openDatabase(dbPath, readOnly: true);
}
