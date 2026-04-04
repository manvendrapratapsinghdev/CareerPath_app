import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/exploration_repository.dart';
import 'package:career_path/services/exploration_service.dart';

void main() {
  late ExplorationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = ExplorationService(ExplorationRepository(prefs));
  });

  test('initially has no visited nodes', () {
    expect(service.visitedIds, isEmpty);
    expect(service.isVisited('node-1'), isFalse);
  });

  test('markVisited tracks a node', () async {
    await service.markVisited('node-1');
    expect(service.isVisited('node-1'), isTrue);
  });

  test('notifies listeners only for new visits', () async {
    int callCount = 0;
    service.addListener(() => callCount++);

    await service.markVisited('node-1');
    expect(callCount, 1);

    // Revisit same node — no notification
    await service.markVisited('node-1');
    expect(callCount, 1);
  });

  test('visitedCountFor returns correct count', () async {
    await service.markVisited('a');
    await service.markVisited('c');

    expect(service.visitedCountFor(['a', 'b', 'c', 'd']), 2);
    expect(service.visitedCountFor(['b', 'd']), 0);
    expect(service.visitedCountFor([]), 0);
  });
}
