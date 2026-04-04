import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/feedback_data.dart';
import '../services/analytics_service.dart';
import '../services/feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  final FeedbackService feedbackService;
  final AnalyticsService? analyticsService;

  const FeedbackScreen({
    super.key,
    required this.feedbackService,
    this.analyticsService,
  });

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  int _rating = 0;
  FeedbackCategory _category = FeedbackCategory.feature;
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final data = FeedbackData(
      rating: _rating,
      category: _category,
      message: _messageController.text.trim(),
    );

    final launched = await widget.feedbackService.submitFeedback(data);

    if (!mounted) return;
    setState(() => _submitting = false);

    if (launched) {
      widget.analyticsService?.logFeedbackSubmitted(_category.name, _rating);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback!')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email app found. Please install one or email us directly.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Feedback')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How would you rate this app?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _buildStarRating(colorScheme),
                const SizedBox(height: AppSpacing.lg),
                Text('Category',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _buildCategorySelector(),
                const SizedBox(height: AppSpacing.lg),
                Text('Your Message',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _messageController,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    hintText: 'Tell us what you think...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 10) {
                      return 'Please enter at least 10 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit Feedback'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStarRating(ColorScheme colorScheme) {
    return Row(
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        return IconButton(
          onPressed: () => setState(() => _rating = starIndex),
          icon: Icon(
            starIndex <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: starIndex <= _rating
                ? Colors.amber
                : colorScheme.onSurfaceVariant,
            size: 36,
          ),
        );
      }),
    );
  }

  Widget _buildCategorySelector() {
    return SegmentedButton<FeedbackCategory>(
      segments: FeedbackCategory.values
          .map((c) => ButtonSegment(value: c, label: Text(c.label)))
          .toList(),
      selected: {_category},
      onSelectionChanged: (selected) {
        setState(() => _category = selected.first);
      },
    );
  }
}
