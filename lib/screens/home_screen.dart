import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/profile_data.dart';
import '../services/analytics_service.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../services/exploration_service.dart';
import '../services/feedback_service.dart';
import '../services/rate_prompt_service.dart';
import '../services/recently_viewed_service.dart';
import '../services/profile_service.dart';
import '../services/theme_service.dart';
import '../widgets/page_transitions.dart';
import 'bookmarks_tab.dart';
import 'explore_tab.dart';
import 'profile_screen.dart';
import 'quiz_screen.dart';
import 'search_screen.dart';
import 'suggestions_tab.dart';

class HomeScreen extends StatefulWidget {
  final ProfileService profileService;
  final BookmarkService bookmarkService;
  final ExplorationService explorationService;
  final RecentlyViewedService? recentlyViewedService;
  final RatePromptService? ratePromptService;
  final FeedbackService? feedbackService;
  final CareerDataService careerDataService;
  final AnalyticsService? analyticsService;
  final ThemeService? themeService;

  const HomeScreen({
    super.key,
    required this.profileService,
    required this.bookmarkService,
    required this.explorationService,
    this.recentlyViewedService,
    this.ratePromptService,
    this.feedbackService,
    required this.careerDataService,
    this.analyticsService,
    this.themeService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProfileData? _profile;
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadProfile();
    widget.analyticsService?.logScreenView('home');
    _checkRatePrompt();
  }

  void _checkRatePrompt() {
    final service = widget.ratePromptService;
    if (service == null || !service.shouldShowPrompt()) return;
    service.markShownThisSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRateDialog();
    });
  }

  void _showRateDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.star_rounded, size: 48, color: colorScheme.primary),
        title: const Text('Enjoying CareerPath?'),
        content: const Text(
          'If you find this app helpful, please take a moment to rate us on the Play Store.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.analyticsService?.logEvent('rate_prompt_dont_ask_again');
              widget.ratePromptService?.recordDontAskAgain();
              Navigator.pop(ctx);
            },
            child: const Text("Don't Ask Again"),
          ),
          TextButton(
            onPressed: () {
              widget.analyticsService?.logEvent('rate_prompt_not_now');
              Navigator.pop(ctx);
            },
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              widget.analyticsService?.logEvent('rate_prompt_rate_now');
              widget.ratePromptService?.recordDontAskAgain();
              Navigator.pop(ctx);
              launchUrl(
                Uri.parse(
                  'https://play.google.com/store/apps/details?id=com.tacrotech.careerpath',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Rate Now'),
          ),
        ],
      ),
    );
    widget.analyticsService?.logEvent('rate_prompt_shown');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await widget.profileService.getProfile();
    if (mounted) setState(() => _profile = profile);
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      SmoothPageRoute(
        page: ProfileScreen(
          profileService: widget.profileService,
          existingProfile: _profile,
          analyticsService: widget.analyticsService,
          feedbackService: widget.feedbackService,
          themeService: widget.themeService,
        ),
      ),
    ).then((_) => _loadProfile());
  }

  void _onTabChanged(int index) {
    const tabNames = ['for_you', 'explore', 'saved'];
    widget.analyticsService?.logTabChanged(tabNames[index]);
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = _profile?.name;
    final hasName = name != null && name.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_greeting${hasName ? ',' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            if (hasName)
              Text(
                name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                SmoothPageRoute(
                  page: SearchScreen(
                    careerDataService: widget.careerDataService,
                    bookmarkService: widget.bookmarkService,
                    analyticsService: widget.analyticsService,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                SmoothPageRoute(page: const QuizScreen()),
              );
            },
            icon: const Icon(Icons.psychology_rounded),
            tooltip: 'Career Quiz',
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: GestureDetector(
              onTap: _navigateToEditProfile,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.soft(AppColors.primaryLight),
                ),
                child: Center(
                  child: Text(
                    hasName ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          const tabNames = ['for_you', 'explore', 'saved'];
          widget.analyticsService?.logTabChanged(tabNames[index]);
          setState(() => _currentIndex = index);
        },
        children: [
          SuggestionsTab(
            profileService: widget.profileService,
            bookmarkService: widget.bookmarkService,
            explorationService: widget.explorationService,
            recentlyViewedService: widget.recentlyViewedService,
            careerDataService: widget.careerDataService,
            analyticsService: widget.analyticsService,
          ),
          ExploreTab(
            careerDataService: widget.careerDataService,
            bookmarkService: widget.bookmarkService,
            explorationService: widget.explorationService,
            analyticsService: widget.analyticsService,
          ),
          BookmarksTab(
            bookmarkService: widget.bookmarkService,
            explorationService: widget.explorationService,
            careerDataService: widget.careerDataService,
            analyticsService: widget.analyticsService,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabChanged,
          elevation: 0,
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          surfaceTintColor: Colors.transparent,
          indicatorColor: colorScheme.primary.withValues(alpha: 0.1),
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.lightbulb_outline_rounded),
              selectedIcon: Icon(Icons.lightbulb_rounded),
              label: 'For You',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_outline_rounded),
              selectedIcon: Icon(Icons.bookmark_rounded),
              label: 'Saved',
            ),
          ],
        ),
      ),
    );
  }
}
