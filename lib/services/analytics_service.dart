import 'package:firebase_analytics/firebase_analytics.dart';

/// Centralized analytics service wrapping Firebase Analytics.
/// Safe to use even if Firebase fails to initialize — all methods become no-ops.
class AnalyticsService {
  final FirebaseAnalytics? _analytics;

  AnalyticsService() : _analytics = _tryGetAnalytics();

  static FirebaseAnalytics? _tryGetAnalytics() {
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics ?? FirebaseAnalytics.instance);

  bool get _enabled => _analytics != null;

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (!_enabled) return;
    await _analytics!.logEvent(name: name, parameters: params);
  }

  // ── Screen tracking ─────────────────────────────────────────────────────

  Future<void> logScreenView(String screenName) async {
    if (!_enabled) return;
    await _analytics!.logScreenView(screenName: screenName);
  }

  // ── Profile events ──────────────────────────────────────────────────────

  Future<void> logProfileCreated(String stream) =>
      _log('profile_created', {'stream': stream});

  Future<void> logProfileUpdated(String stream) =>
      _log('profile_updated', {'stream': stream});

  Future<void> logProfileSkipped() => _log('profile_skipped');

  // ── Navigation events ───────────────────────────────────────────────────

  Future<void> logStreamExpanded(String streamName) =>
      _log('stream_expanded', {'stream_name': streamName});

  Future<void> logCategoryTapped(String categoryName) =>
      _log('category_tapped', {'category_name': categoryName});

  Future<void> logNodeTapped(String nodeName, {required bool isLeaf}) =>
      _log('node_tapped', {'node_name': nodeName, 'is_leaf': isLeaf.toString()});

  // ── Leaf detail events ──────────────────────────────────────────────────

  Future<void> logBookTapped(String bookTitle) =>
      _log('book_tapped', {'book_title': bookTitle});

  Future<void> logInstituteTapped(String instituteName) =>
      _log('institute_tapped', {'institute_name': instituteName});

  Future<void> logSectionExpanded(String sectionName) =>
      _log('section_expanded', {'section_name': sectionName});

  // ── Share events ───────────────────────────────────────────────────────

  Future<void> logShareCareerPath(String nodeName) =>
      _log('share_career_path', {'node_name': nodeName});

  // ── Search events ──────────────────────────────────────────────────────

  Future<void> logSearch(String query, int resultCount) =>
      _log('search', {'query': query, 'result_count': resultCount});

  // ── Bookmark events ─────────────────────────────────────────────────────

  Future<void> logBookmarkAdded(String nodeName) =>
      _log('bookmark_added', {'node_name': nodeName});

  Future<void> logBookmarkRemoved(String nodeName) =>
      _log('bookmark_removed', {'node_name': nodeName});

  // ── Tab events ──────────────────────────────────────────────────────────

  Future<void> logTabChanged(String tabName) =>
      _log('tab_changed', {'tab_name': tabName});
}
