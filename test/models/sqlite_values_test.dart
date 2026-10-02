import 'package:career_path/models/sqlite_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads SQLite flags as ints, bools or text', () {
    expect(sqliteBoolOrNull(1), isTrue);
    expect(sqliteBoolOrNull(0), isFalse);
    expect(sqliteBoolOrNull(true), isTrue);
    expect(sqliteBoolOrNull('0'), isFalse);
    expect(sqliteBoolOrNull(null), isNull);
    expect(sqliteBoolOrNull('maybe'), isNull);
    expect(sqliteBool(null, fallback: true), isTrue);
  });

  test('writes flags back as 1/0/null', () {
    expect(sqliteFlag(true), 1);
    expect(sqliteFlag(false), 0);
    expect(sqliteFlag(null), isNull);
  });

  test('splits comma and semicolon lists', () {
    expect(splitSqliteList('G5,G7'), ['G5', 'G7']);
    expect(splitSqliteList('JEE Advanced; JEE Main; '), [
      'JEE Advanced',
      'JEE Main',
    ]);
    expect(splitSqliteList(null), isEmpty);
    expect(splitSqliteList('  '), isEmpty);
  });
}
