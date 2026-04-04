import 'package:firebase_analytics/firebase_analytics.dart';

/// Centralized analytics service wrapping Firebase Analytics.
/// All event logging goes through this class.
class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // ── Screen tracking ─────────────────────────────────────────────────────

  Future<void> logScreenView(String screenName) =>
      _analytics.logScreenView(screenName: screenName);

  // ── Profile events ──────────────────────────────────────────────────────

  Future<void> logProfileCreated(String stream) =>
      _analytics.logEvent(name: 'profile_created', parameters: {
        'stream': stream,
      });

  Future<void> logProfileUpdated(String stream) =>
      _analytics.logEvent(name: 'profile_updated', parameters: {
        'stream': stream,
      });

  Future<void> logProfileSkipped() =>
      _analytics.logEvent(name: 'profile_skipped');

  // ── Navigation events ───────────────────────────────────────────────────

  Future<void> logStreamExpanded(String streamName) =>
      _analytics.logEvent(name: 'stream_expanded', parameters: {
        'stream_name': streamName,
      });

  Future<void> logCategoryTapped(String categoryName) =>
      _analytics.logEvent(name: 'category_tapped', parameters: {
        'category_name': categoryName,
      });

  Future<void> logNodeTapped(String nodeName, {required bool isLeaf}) =>
      _analytics.logEvent(name: 'node_tapped', parameters: {
        'node_name': nodeName,
        'is_leaf': isLeaf.toString(),
      });

  // ── Leaf detail events ──────────────────────────────────────────────────

  Future<void> logBookTapped(String bookTitle) =>
      _analytics.logEvent(name: 'book_tapped', parameters: {
        'book_title': bookTitle,
      });

  Future<void> logInstituteTapped(String instituteName) =>
      _analytics.logEvent(name: 'institute_tapped', parameters: {
        'institute_name': instituteName,
      });

  Future<void> logSectionExpanded(String sectionName) =>
      _analytics.logEvent(name: 'section_expanded', parameters: {
        'section_name': sectionName,
      });

  // ── Share events ───────────────────────────────────────────────────────

  Future<void> logShareCareerPath(String nodeName) =>
      _analytics.logEvent(name: 'share_career_path', parameters: {
        'node_name': nodeName,
      });

  // ── Search events ──────────────────────────────────────────────────────

  Future<void> logSearch(String query, int resultCount) =>
      _analytics.logEvent(name: 'search', parameters: {
        'query': query,
        'result_count': resultCount,
      });

  // ── Bookmark events ─────────────────────────────────────────────────────

  Future<void> logBookmarkAdded(String nodeName) =>
      _analytics.logEvent(name: 'bookmark_added', parameters: {
        'node_name': nodeName,
      });

  Future<void> logBookmarkRemoved(String nodeName) =>
      _analytics.logEvent(name: 'bookmark_removed', parameters: {
        'node_name': nodeName,
      });

  // ── Tab events ──────────────────────────────────────────────────────────

  Future<void> logTabChanged(String tabName) =>
      _analytics.logEvent(name: 'tab_changed', parameters: {
        'tab_name': tabName,
      });
}
