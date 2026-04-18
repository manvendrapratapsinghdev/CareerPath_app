import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/models/feedback_data.dart';
import 'package:career_path/services/feedback_service.dart';

void main() {
  late FeedbackService service;

  setUp(() {
    service = FeedbackService();
  });

  test('buildMailtoUri contains correct email', () {
    final data = FeedbackData(
      rating: 4,
      category: FeedbackCategory.feature,
      message: 'Add dark mode',
    );
    final uri = service.buildMailtoUri(data);
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'iosmanvendra@gmail.com');
  });

  test('buildMailtoUri includes subject with category', () {
    final data = FeedbackData(
      rating: 3,
      category: FeedbackCategory.bug,
      message: 'App crashes',
    );
    final uri = service.buildMailtoUri(data);
    expect(uri.queryParameters['subject'], contains('Bug Report'));
  });

  test('buildMailtoUri includes rating in body', () {
    final data = FeedbackData(
      rating: 5,
      category: FeedbackCategory.other,
      message: 'Great app!',
    );
    final uri = service.buildMailtoUri(data);
    expect(uri.queryParameters['body'], contains('5/5'));
  });

  test('buildMailtoUri includes message in body', () {
    final data = FeedbackData(
      rating: 2,
      category: FeedbackCategory.bug,
      message: 'Search is broken',
    );
    final uri = service.buildMailtoUri(data);
    expect(uri.queryParameters['body'], contains('Search is broken'));
  });

  test('buildMailtoUri handles all categories', () {
    for (final cat in FeedbackCategory.values) {
      final data = FeedbackData(rating: 3, category: cat, message: 'test');
      final uri = service.buildMailtoUri(data);
      expect(uri.queryParameters['subject'], contains(cat.label));
    }
  });
}
