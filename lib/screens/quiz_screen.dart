import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../services/analytics_service.dart';

class QuizScreen extends StatefulWidget {
  final AnalyticsService? analyticsService;

  const QuizScreen({super.key, this.analyticsService});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentIndex = 0;
  final Map<String, int> _scores = {};
  bool _showResult = false;

  static const _questions = [
    _Question(
      question: 'What kind of activity excites you most?',
      options: [
        _Option('Experimenting and building things', ['engineering', 'science', 'technology']),
        _Option('Solving puzzles and analyzing data', ['analytics', 'finance', 'research']),
        _Option('Creating art, music, or stories', ['creative', 'media', 'design']),
        _Option('Leading teams and organizing events', ['management', 'business', 'law']),
      ],
    ),
    _Question(
      question: 'Which subject do you enjoy the most?',
      options: [
        _Option('Physics or Mathematics', ['engineering', 'technology', 'research']),
        _Option('Biology or Chemistry', ['medical', 'pharmacy', 'science']),
        _Option('Economics or Business Studies', ['finance', 'business', 'management']),
        _Option('Languages or Social Studies', ['creative', 'law', 'media']),
      ],
    ),
    _Question(
      question: 'In a group project, you usually...',
      options: [
        _Option('Do the technical or hands-on work', ['engineering', 'technology', 'science']),
        _Option('Research and gather information', ['research', 'analytics', 'medical']),
        _Option('Design the presentation or visuals', ['design', 'creative', 'media']),
        _Option('Coordinate and manage the team', ['management', 'business', 'law']),
      ],
    ),
    _Question(
      question: 'What type of work environment appeals to you?',
      options: [
        _Option('Lab, workshop, or tech office', ['engineering', 'science', 'technology']),
        _Option('Hospital, clinic, or research center', ['medical', 'pharmacy', 'research']),
        _Option('Studio, agency, or freelance', ['creative', 'design', 'media']),
        _Option('Corporate office or courtroom', ['business', 'finance', 'law']),
      ],
    ),
    _Question(
      question: 'Which skill are you most proud of?',
      options: [
        _Option('Problem-solving and logical thinking', ['engineering', 'analytics', 'technology']),
        _Option('Attention to detail and patience', ['medical', 'research', 'pharmacy']),
        _Option('Creativity and imagination', ['creative', 'design', 'media']),
        _Option('Communication and persuasion', ['management', 'law', 'business']),
      ],
    ),
    _Question(
      question: 'What would you watch a documentary about?',
      options: [
        _Option('Space exploration or AI', ['technology', 'engineering', 'science']),
        _Option('Medical breakthroughs or nature', ['medical', 'science', 'research']),
        _Option('Film making or art history', ['creative', 'media', 'design']),
        _Option('Business empires or legal battles', ['business', 'finance', 'law']),
      ],
    ),
    _Question(
      question: 'Your ideal weekend project?',
      options: [
        _Option('Building an app or fixing gadgets', ['technology', 'engineering', 'analytics']),
        _Option('Reading research papers or gardening', ['research', 'medical', 'science']),
        _Option('Painting, writing, or photography', ['creative', 'design', 'media']),
        _Option('Planning a startup or debating', ['business', 'management', 'law']),
      ],
    ),
    _Question(
      question: 'Which impact matters most to you?',
      options: [
        _Option('Innovating technology for the future', ['technology', 'engineering', 'science']),
        _Option('Saving lives and improving health', ['medical', 'pharmacy', 'research']),
        _Option('Inspiring people through art and culture', ['creative', 'media', 'design']),
        _Option('Building businesses and shaping policy', ['business', 'finance', 'law']),
      ],
    ),
  ];

  static const _careerMap = <String, List<String>>{
    'engineering': ['Software Engineering', 'Mechanical Engineering', 'Civil Engineering'],
    'technology': ['Data Science', 'Artificial Intelligence', 'Cybersecurity'],
    'science': ['Physics Research', 'Environmental Science', 'Astronomy'],
    'medical': ['Medicine (MBBS)', 'Dentistry', 'Veterinary Science'],
    'pharmacy': ['Pharmacology', 'Biotechnology', 'Clinical Research'],
    'research': ['Scientific Research', 'Academic Research', 'R&D'],
    'analytics': ['Data Analytics', 'Actuarial Science', 'Statistics'],
    'finance': ['Chartered Accountancy', 'Investment Banking', 'Financial Planning'],
    'business': ['Entrepreneurship', 'Marketing', 'International Business'],
    'management': ['Business Management', 'HR Management', 'Operations'],
    'law': ['Corporate Law', 'Civil Law', 'International Law'],
    'creative': ['Graphic Design', 'Creative Writing', 'Animation'],
    'design': ['UI/UX Design', 'Fashion Design', 'Interior Design'],
    'media': ['Journalism', 'Film Direction', 'Digital Marketing'],
  };

  void _selectOption(_Option option) {
    if (_currentIndex == 0) {
      widget.analyticsService?.logQuizStarted();
    }
    for (final tag in option.tags) {
      _scores[tag] = (_scores[tag] ?? 0) + 1;
    }
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      final topNames = _topCategories.map((e) => e.key).toList();
      widget.analyticsService?.logQuizCompleted(topNames);
      setState(() => _showResult = true);
    }
  }

  List<MapEntry<String, int>> get _topCategories {
    final sorted = _scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).toList();
  }

  void _shareResult() {
    final top = _topCategories;
    final buffer = StringBuffer('My CareerPath Quiz Results!\n\n');
    for (int i = 0; i < top.length; i++) {
      final tag = top[i].key;
      final careers = _careerMap[tag] ?? [];
      buffer.writeln('${i + 1}. ${tag[0].toUpperCase()}${tag.substring(1)}');
      for (final c in careers.take(2)) {
        buffer.writeln('   - $c');
      }
    }
    buffer.writeln('\nTake the quiz on CareerPath app!');
    SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  void _restart() {
    setState(() {
      _currentIndex = 0;
      _scores.clear();
      _showResult = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showResult ? 'Your Results' : 'Career Quiz'),
      ),
      body: _showResult ? _buildResults() : _buildQuestion(),
    );
  }

  Widget _buildQuestion() {
    final question = _questions[_currentIndex];
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (_currentIndex + 1) / _questions.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress
            Row(
              children: [
                Text(
                  '${_currentIndex + 1}/${_questions.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ClipRRect(
                    borderRadius: AppRadius.pillAll,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor:
                          colorScheme.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            // Question
            Text(
              question.question,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Options
            ...question.options.map((option) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _selectOption(option),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                style:
                                    Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final top = _topCategories;
    final colors = [AppColors.science, AppColors.commerce, AppColors.art];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            // Hero
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology_rounded,
                  size: 48, color: AppColors.success),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Your Top Career Areas',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),

            // Top categories
            ...List.generate(top.length, (i) {
              final tag = top[i].key;
              final careers = _careerMap[tag] ?? [];
              final color = colors[i % colors.length];

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.base),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            '${tag[0].toUpperCase()}${tag.substring(1)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...careers.take(3).map((c) => Padding(
                            padding:
                                const EdgeInsets.only(left: 40, top: 4),
                            child: Text(
                              '- $c',
                              style:
                                  Theme.of(context).textTheme.bodyMedium,
                            ),
                          )),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.xl),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _shareResult,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}

class _Question {
  final String question;
  final List<_Option> options;

  const _Question({required this.question, required this.options});
}

class _Option {
  final String label;
  final List<String> tags;

  const _Option(this.label, this.tags);
}
