import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/rate_prompt_repository.dart';
import 'package:career_path/services/rate_prompt_service.dart';

void main() {
  late RatePromptService service;
  late RatePromptRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = RatePromptRepository(prefs);
    service = RatePromptService(repo);
  });

  test('shouldShowPrompt returns false on fresh install', () async {
    await service.recordSession();
    expect(service.shouldShowPrompt(), isFalse);
  });

  test('shouldShowPrompt returns true after 5 sessions', () async {
    for (int i = 0; i < 5; i++) {
      await repo.incrementSessionCount();
    }
    await repo.setFirstSessionDate('2026-04-04');
    expect(service.shouldShowPrompt(), isTrue);
  });

  test('shouldShowPrompt returns true after 3 days', () async {
    await repo.incrementSessionCount(); // only 1 session
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
    await repo.setFirstSessionDate(
      threeDaysAgo.toIso8601String().substring(0, 10),
    );
    expect(service.shouldShowPrompt(), isTrue);
  });

  test('shouldShowPrompt returns false when dontAskAgain is true', () async {
    for (int i = 0; i < 5; i++) {
      await repo.incrementSessionCount();
    }
    await repo.setFirstSessionDate('2026-04-01');
    await repo.setDontAskAgain(true);
    expect(service.shouldShowPrompt(), isFalse);
  });

  test('shouldShowPrompt returns false after markShownThisSession', () async {
    for (int i = 0; i < 5; i++) {
      await repo.incrementSessionCount();
    }
    await repo.setFirstSessionDate('2026-04-04');
    service.markShownThisSession();
    expect(service.shouldShowPrompt(), isFalse);
  });

  test('recordDontAskAgain persists flag', () async {
    await service.recordDontAskAgain();
    expect(repo.getDontAskAgain(), isTrue);
  });

  test('recordSession increments count and sets first date', () async {
    await service.recordSession();
    expect(repo.getSessionCount(), 1);
    expect(repo.getFirstSessionDate(), isNotNull);
  });

  test('recordSession does not overwrite existing first date', () async {
    await repo.setFirstSessionDate('2026-01-01');
    await service.recordSession();
    expect(repo.getFirstSessionDate(), '2026-01-01');
  });

  test('boundary: 4 sessions + 2 days = false', () async {
    for (int i = 0; i < 4; i++) {
      await repo.incrementSessionCount();
    }
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
    await repo.setFirstSessionDate(
      twoDaysAgo.toIso8601String().substring(0, 10),
    );
    expect(service.shouldShowPrompt(), isFalse);
  });
}
