import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/rate_prompt_repository.dart';

void main() {
  late RatePromptRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = RatePromptRepository(prefs);
  });

  test('sessionCount starts at 0', () {
    expect(repo.getSessionCount(), 0);
  });

  test('incrementSessionCount increments by 1', () async {
    await repo.incrementSessionCount();
    expect(repo.getSessionCount(), 1);
    await repo.incrementSessionCount();
    expect(repo.getSessionCount(), 2);
  });

  test('firstSessionDate starts as null', () {
    expect(repo.getFirstSessionDate(), isNull);
  });

  test('setFirstSessionDate persists date string', () async {
    await repo.setFirstSessionDate('2026-04-01');
    expect(repo.getFirstSessionDate(), '2026-04-01');
  });

  test('dontAskAgain defaults to false', () {
    expect(repo.getDontAskAgain(), isFalse);
  });

  test('setDontAskAgain persists boolean', () async {
    await repo.setDontAskAgain(true);
    expect(repo.getDontAskAgain(), isTrue);
  });

  test('persists across instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo1 = RatePromptRepository(prefs);
    await repo1.incrementSessionCount();
    await repo1.setFirstSessionDate('2026-04-01');
    await repo1.setDontAskAgain(true);

    final repo2 = RatePromptRepository(prefs);
    expect(repo2.getSessionCount(), 1);
    expect(repo2.getFirstSessionDate(), '2026-04-01');
    expect(repo2.getDontAskAgain(), isTrue);
  });
}
