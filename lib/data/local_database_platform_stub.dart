import 'package:sqflite/sqflite.dart';

Future<Database> openBundledDatabase({
  required String assetPath,
  required String databaseName,
}) => throw UnsupportedError('This platform has no local database support.');
