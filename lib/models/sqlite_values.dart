/// Helpers for reading SQLite row values into model fields.
///
/// SQLite has no boolean type: flags arrive as `1`/`0` (or `NULL`). JSON that
/// went through `toJson` may carry real booleans, so both are accepted.
bool? sqliteBoolOrNull(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == '1' || text == 'true') return true;
  if (text == '0' || text == 'false') return false;
  return null;
}

/// Like [sqliteBoolOrNull], with [fallback] when the value is missing.
bool sqliteBool(Object? value, {required bool fallback}) =>
    sqliteBoolOrNull(value) ?? fallback;

/// Writes a flag back in the SQLite shape (`1`/`0`, `null` stays `null`).
int? sqliteFlag(bool? value) => value == null ? null : (value ? 1 : 0);

/// Splits a list column such as `'G5,G7'` or `'NMC; INC'` into trimmed,
/// non-empty items. Commas and semicolons both separate items.
List<String> splitSqliteList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(RegExp(r'[,;]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
