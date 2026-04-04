import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/leaf_details_cache.dart';
import 'package:career_path/models/leaf_details.dart';
import 'package:career_path/models/book.dart';
import 'package:career_path/models/institute.dart';
import 'package:career_path/models/job_sector.dart';

void main() {
  late LeafDetailsCache cache;

  final testDetails = LeafDetails(
    nodeApiId: 1,
    slug: 'test-node',
    name: 'Test Career',
    intro: 'A test career path',
    books: [
      const Book(id: 1, title: 'Test Book', author: 'Author'),
    ],
    institutes: [
      const Institute(id: 1, name: 'Test Institute', city: 'Delhi'),
    ],
    jobSectors: [
      const JobSector(id: 1, name: 'Tech', description: 'Technology sector'),
    ],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    cache = LeafDetailsCache(prefs);
  });

  test('get returns null for missing entry', () {
    expect(cache.get('missing'), isNull);
  });

  test('has returns false for missing entry', () {
    expect(cache.has('missing'), isFalse);
  });

  test('save and get round-trips correctly', () async {
    await cache.save('test-node', testDetails);
    expect(cache.has('test-node'), isTrue);

    final retrieved = cache.get('test-node');
    expect(retrieved, isNotNull);
    expect(retrieved!.name, 'Test Career');
    expect(retrieved.intro, 'A test career path');
    expect(retrieved.books.length, 1);
    expect(retrieved.books.first.title, 'Test Book');
    expect(retrieved.institutes.length, 1);
    expect(retrieved.institutes.first.name, 'Test Institute');
    expect(retrieved.jobSectors.length, 1);
    expect(retrieved.jobSectors.first.name, 'Tech');
  });

  test('remove deletes cached entry', () async {
    await cache.save('test-node', testDetails);
    expect(cache.has('test-node'), isTrue);

    await cache.remove('test-node');
    expect(cache.has('test-node'), isFalse);
    expect(cache.get('test-node'), isNull);
  });
}
