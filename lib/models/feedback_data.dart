enum FeedbackCategory {
  bug('Bug Report'),
  feature('Feature Request'),
  other('Other');

  final String label;
  const FeedbackCategory(this.label);
}

class FeedbackData {
  final int rating;
  final FeedbackCategory category;
  final String message;

  const FeedbackData({
    required this.rating,
    required this.category,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'category': category.name,
        'message': message,
      };

  factory FeedbackData.fromJson(Map<String, dynamic> json) => FeedbackData(
        rating: json['rating'] as int,
        category: FeedbackCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => FeedbackCategory.other,
        ),
        message: json['message'] as String,
      );
}
