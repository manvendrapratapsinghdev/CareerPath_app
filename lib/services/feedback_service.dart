import 'package:url_launcher/url_launcher.dart';

import '../models/feedback_data.dart';

class FeedbackService {
  static const _feedbackEmail = 'feedback@tacrotech.com';

  Uri buildMailtoUri(FeedbackData data) {
    final subject = 'CareerPath Feedback: ${data.category.label}';
    final body = '''
Rating: ${'⭐' * data.rating} (${data.rating}/5)
Category: ${data.category.label}

${data.message}

---
Sent from CareerPath App
''';
    return Uri(
      scheme: 'mailto',
      path: _feedbackEmail,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );
  }

  Future<bool> submitFeedback(FeedbackData data) async {
    final uri = buildMailtoUri(data);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }
}
