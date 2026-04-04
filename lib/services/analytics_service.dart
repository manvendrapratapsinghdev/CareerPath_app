/// Stub analytics service — Firebase removed to reduce app size.
/// All methods are no-ops. Re-add firebase_analytics when needed.
class AnalyticsService {
  Future<void> logScreenView(String screenName) async {}
  Future<void> logProfileCreated(String stream) async {}
  Future<void> logProfileUpdated(String stream) async {}
  Future<void> logProfileSkipped() async {}
  Future<void> logStreamExpanded(String streamName) async {}
  Future<void> logCategoryTapped(String categoryName) async {}
  Future<void> logNodeTapped(String nodeName, {required bool isLeaf}) async {}
  Future<void> logBookTapped(String bookTitle) async {}
  Future<void> logInstituteTapped(String instituteName) async {}
  Future<void> logSectionExpanded(String sectionName) async {}
  Future<void> logShareCareerPath(String nodeName) async {}
  Future<void> logSearch(String query, int resultCount) async {}
  Future<void> logBookmarkAdded(String nodeName) async {}
  Future<void> logBookmarkRemoved(String nodeName) async {}
  Future<void> logTabChanged(String tabName) async {}
}
