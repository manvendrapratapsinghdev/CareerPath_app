import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/bookmark_repository.dart';

void main() {
  late BookmarkRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = BookmarkRepository(prefs);
  });

  test('getAll returns empty list initially', () {
    expect(repo.getAll(), isEmpty);
  });

  test('add stores a node id', () async {
    await repo.add('node-1');
    expect(repo.getAll(), ['node-1']);
  });

  test('add does not duplicate', () async {
    await repo.add('node-1');
    await repo.add('node-1');
    expect(repo.getAll(), ['node-1']);
  });

  test('remove deletes a node id', () async {
    await repo.add('node-1');
    await repo.add('node-2');
    await repo.remove('node-1');
    expect(repo.getAll(), ['node-2']);
  });

  test('remove is no-op for missing id', () async {
    await repo.add('node-1');
    await repo.remove('missing');
    expect(repo.getAll(), ['node-1']);
  });

  test('isBookmarked returns correct state', () async {
    expect(repo.isBookmarked('node-1'), isFalse);
    await repo.add('node-1');
    expect(repo.isBookmarked('node-1'), isTrue);
    await repo.remove('node-1');
    expect(repo.isBookmarked('node-1'), isFalse);
  });

  test('persists across instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo1 = BookmarkRepository(prefs);
    await repo1.add('node-1');

    final repo2 = BookmarkRepository(prefs);
    expect(repo2.isBookmarked('node-1'), isTrue);
  });
}
