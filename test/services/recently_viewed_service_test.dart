import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/recently_viewed_repository.dart';
import 'package:career_path/services/recently_viewed_service.dart';

void main() {
  late RecentlyViewedService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = RecentlyViewedService(RecentlyViewedRepository(prefs));
  });

  test('initially has no recent items', () {
    expect(service.recentIds, isEmpty);
  });

  test('addVisit records a node id', () async {
    await service.addVisit('node-1');
    expect(service.recentIds, ['node-1']);
  });

  test('addVisit maintains most-recent-first order', () async {
    await service.addVisit('node-1');
    await service.addVisit('node-2');
    expect(service.recentIds, ['node-2', 'node-1']);
  });

  test('notifies listeners on addVisit', () async {
    int callCount = 0;
    service.addListener(() => callCount++);

    await service.addVisit('node-1');
    expect(callCount, 1);

    await service.addVisit('node-1'); // revisit
    expect(callCount, 2); // always notifies (order changed)
  });

  test('notifies listeners on clear', () async {
    int callCount = 0;
    await service.addVisit('node-1');
    service.addListener(() => callCount++);

    await service.clear();
    expect(callCount, 1);
    expect(service.recentIds, isEmpty);
  });

  test('delegates cap enforcement to repository', () async {
    for (int i = 1; i <= 20; i++) {
      await service.addVisit('node-$i');
    }
    expect(service.recentIds.length, 15);
  });
}
