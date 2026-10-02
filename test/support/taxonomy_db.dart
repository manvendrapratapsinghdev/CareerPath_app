import 'package:career_path/data/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The bundled schema's taxonomy part, trimmed to what the queries read
/// (same shape as `test/data/local_database_taxonomy_test.dart`).
const taxonomySchema = [
  'CREATE TABLE career_nodes (id INTEGER PRIMARY KEY, slug TEXT, '
      'stream_id INTEGER, parent_id INTEGER, name TEXT, intro TEXT)',
  'CREATE TABLE institutes (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
      'city TEXT, website TEXT, description TEXT, source_id TEXT, '
      'district TEXT, state TEXT, institution_type TEXT)',
  'CREATE TABLE institute_rankings (institute_id INTEGER, system TEXT, '
      'year INTEGER, category TEXT, nirf_institute_id TEXT, rank INTEGER, '
      'rank_band TEXT, score REAL, source_url TEXT, '
      'PRIMARY KEY (institute_id, system, year, category))',
  'CREATE TABLE institution_groups (code TEXT PRIMARY KEY, name TEXT, '
      'description TEXT, sort_order INTEGER)',
  'CREATE TABLE families (slug TEXT PRIMARY KEY, name TEXT, group_code TEXT, '
      'regulators TEXT, official_list_url TEXT, national_count INTEGER, '
      'national_count_as_of TEXT)',
  'CREATE TABLE institute_classification (institute_id INTEGER PRIMARY KEY, '
      'group_code TEXT NOT NULL, family_slug TEXT, ownership TEXT, '
      'statutory_basis TEXT, admits_students INTEGER NOT NULL DEFAULT 1, '
      'parent_institute_id INTEGER, is_family_record INTEGER NOT NULL DEFAULT 0, '
      'regulators TEXT, listed INTEGER NOT NULL DEFAULT 1, ugc_verified INTEGER, '
      'ugc_list_name TEXT, ugc_reference_id TEXT, ugc_source_url TEXT, '
      'ugc_checked_at TEXT, confidence TEXT NOT NULL, source_url TEXT, '
      'verified_at TEXT, notes TEXT)',
  'CREATE TABLE institute_accreditations (institute_id INTEGER, body TEXT, '
      "programme TEXT NOT NULL DEFAULT '', grade TEXT, status TEXT, "
      'valid_until TEXT, source_url TEXT)',
  'CREATE TABLE domains (slug TEXT PRIMARY KEY, name TEXT, route_type TEXT, '
      'regulators TEXT, entrance_exams TEXT, sort_order INTEGER)',
  'CREATE TABLE domain_nodes (node_id INTEGER PRIMARY KEY, domain_slug TEXT)',
  'CREATE TABLE domain_tiers (domain_slug TEXT, tier INTEGER, label TEXT, '
      'group_codes TEXT, family_slugs TEXT, entry_exams TEXT, '
      'PRIMARY KEY (domain_slug, tier))',
  'CREATE TABLE institute_domain_tiers (institute_id INTEGER, '
      'domain_slug TEXT, tier INTEGER, PRIMARY KEY (institute_id, domain_slug))',
  'CREATE TABLE states (code TEXT PRIMARY KEY, lgd_code INTEGER, '
      'country_code TEXT, name TEXT, kind TEXT, zone TEXT)',
];

/// A fresh in-memory database with [taxonomySchema] and [seed] applied,
/// wrapped in a [LocalDatabase]. Call [sqfliteFfiInit] once per test file.
Future<LocalDatabase> openTaxonomyDb(List<String> seed) async {
  final database = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  for (final sql in [...taxonomySchema, ...seed]) {
    await database.execute(sql);
  }
  return LocalDatabase.withDatabase(database);
}
