import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/recently_viewed_repository.dart';

void main() {
  late RecentlyViewedRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = RecentlyViewedRepository(prefs);
  });

  test('getAll returns empty list initially', () {
    expect(repo.getAll(), isEmpty);
  });

  test('addVisit stores a node id at the front', () async {
    await repo.addVisit('node-1');
    expect(repo.getAll(), ['node-1']);
  });

  test('addVisit prepends new items (most recent first)', () async {
    await repo.addVisit('node-1');
    await repo.addVisit('node-2');
    await repo.addVisit('node-3');
    expect(repo.getAll(), ['node-3', 'node-2', 'node-1']);
  });

  test('addVisit moves existing item to front (no duplicates)', () async {
    await repo.addVisit('node-1');
    await repo.addVisit('node-2');
    await repo.addVisit('node-3');
    await repo.addVisit('node-1');
    expect(repo.getAll(), ['node-1', 'node-3', 'node-2']);
  });

  test('addVisit caps at 15 items', () async {
    for (int i = 1; i <= 16; i++) {
      await repo.addVisit('node-$i');
    }
    final list = repo.getAll();
    expect(list.length, 15);
    expect(list.first, 'node-16');
    expect(list.last, 'node-2');
    expect(list.contains('node-1'), isFalse);
  });

  test('addVisit moves last item to front without exceeding cap', () async {
    for (int i = 1; i <= 15; i++) {
      await repo.addVisit('node-$i');
    }
    await repo.addVisit('node-1');
    final list = repo.getAll();
    expect(list.length, 15);
    expect(list.first, 'node-1');
  });

  test('clear removes all entries', () async {
    await repo.addVisit('node-1');
    await repo.addVisit('node-2');
    await repo.clear();
    expect(repo.getAll(), isEmpty);
  });

  test('persists across instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo1 = RecentlyViewedRepository(prefs);
    await repo1.addVisit('node-1');

    final repo2 = RecentlyViewedRepository(prefs);
    expect(repo2.getAll(), ['node-1']);
  });
}
