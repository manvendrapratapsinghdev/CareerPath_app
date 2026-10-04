import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> openBundledDatabase({
  required String assetPath,
  required String databaseName,
}) async {
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final factory = databaseFactoryFfiWeb;
  await factory.writeDatabaseBytes(databaseName, bytes);
  return factory.openDatabase(
    databaseName,
    options: OpenDatabaseOptions(readOnly: true),
  );
}
