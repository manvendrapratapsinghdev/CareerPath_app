import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/exploration_repository.dart';

void main() {
  late ExplorationRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = ExplorationRepository(prefs);
  });

  test('getAll returns empty set initially', () {
    expect(repo.getAll(), isEmpty);
  });

  test('markVisited stores a node id', () async {
    await repo.markVisited('node-1');
    expect(repo.getAll(), {'node-1'});
  });

  test('markVisited does not duplicate', () async {
    await repo.markVisited('node-1');
    await repo.markVisited('node-1');
    expect(repo.getAll().length, 1);
  });

  test('isVisited returns correct state', () async {
    expect(repo.isVisited('node-1'), isFalse);
    await repo.markVisited('node-1');
    expect(repo.isVisited('node-1'), isTrue);
  });
}
