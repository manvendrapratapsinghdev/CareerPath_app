import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _PageData(
      icon: Icons.explore_rounded,
      color: AppColors.science,
      title: 'Explore Career Paths',
      description:
          'Browse through Science, Commerce, and Art streams to discover career options that match your interests.',
    ),
    _PageData(
      icon: Icons.bookmark_rounded,
      color: AppColors.commerce,
      title: 'Save & Compare',
      description:
          'Bookmark careers you like, search across all paths, and share discoveries with friends.',
    ),
    _PageData(
      icon: Icons.school_rounded,
      color: AppColors.art,
      title: 'Find Your Future',
      description:
          'Get details on top institutes, recommended books, and job sectors for every career endpoint.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text('Skip'),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (context, index) =>
                    _buildPage(context, _pages[index]),
              ),
            ),

            // Dots + Next button
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: Row(
                children: [
                  // Page dots
                  Row(
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.3),
                          borderRadius: AppRadius.pillAll,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Next / Get Started
                  FilledButton(
                    onPressed: _next,
                    child: Text(isLast ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, _PageData page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 56, color: page.color),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            page.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _PageData({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
