import '../data/rate_prompt_repository.dart';

class RatePromptService {
  final RatePromptRepository _repository;
  bool _shownThisSession = false;

  RatePromptService(this._repository);

  /// Call once at app startup to track session and first launch date.
  Future<void> recordSession() async {
    await _repository.incrementSessionCount();
    if (_repository.getFirstSessionDate() == null) {
      await _repository.setFirstSessionDate(
        DateTime.now().toIso8601String().substring(0, 10),
      );
    }
  }

  bool shouldShowPrompt() {
    if (_shownThisSession) return false;
    if (_repository.getDontAskAgain()) return false;

    final sessionCount = _repository.getSessionCount();
    final firstDateStr = _repository.getFirstSessionDate();

    bool sessionThreshold = sessionCount >= 5;
    bool daysThreshold = false;
    if (firstDateStr != null) {
      final firstDate = DateTime.tryParse(firstDateStr);
      if (firstDate != null) {
        final daysSince = DateTime.now().difference(firstDate).inDays;
        daysThreshold = daysSince >= 3;
      }
    }

    return sessionThreshold || daysThreshold;
  }

  void markShownThisSession() {
    _shownThisSession = true;
  }

  Future<void> recordDontAskAgain() async {
    await _repository.setDontAskAgain(true);
  }
}
