import 'package:sqflite/sqflite.dart';

import 'local_database_platform_stub.dart'
    if (dart.library.io) 'local_database_platform_io.dart'
    if (dart.library.js_interop) 'local_database_platform_web.dart' as platform;

Future<Database> openBundledDatabase({
  required String assetPath,
  required String databaseName,
}) => platform.openBundledDatabase(
  assetPath: assetPath,
  databaseName: databaseName,
);
