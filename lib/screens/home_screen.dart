import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/profile_data.dart';
import '../services/analytics_service.dart';
import '../services/bookmark_service.dart';
import '../services/career_data_service.dart';
import '../services/exploration_service.dart';
import '../services/feedback_service.dart';
import '../services/locale_service.dart';
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
  final LocaleService? localeService;

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
    this.localeService,
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
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.star_rounded, size: 48, color: colorScheme.primary),
        title: Text(l.home_rateDialogTitle),
        content: Text(l.home_rateDialogContent),
        actions: [
          TextButton(
            onPressed: () {
              widget.analyticsService?.logEvent('rate_prompt_dont_ask_again');
              widget.ratePromptService?.recordDontAskAgain();
              Navigator.pop(ctx);
            },
            child: Text(l.home_rateDialogDontAskAgain),
          ),
          TextButton(
            onPressed: () {
              widget.analyticsService?.logEvent('rate_prompt_not_now');
              Navigator.pop(ctx);
            },
            child: Text(l.home_rateDialogNotNow),
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
            child: Text(l.home_rateDialogRateNow),
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
          localeService: widget.localeService,
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

  String _greeting(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final hour = DateTime.now().hour;
    if (hour < 12) return l.home_goodMorning;
    if (hour < 17) return l.home_goodAfternoon;
    return l.home_goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
              '${_greeting(context)}${hasName ? ',' : ''}',
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
            tooltip: l.home_searchTooltip,
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                SmoothPageRoute(page: QuizScreen(analyticsService: widget.analyticsService)),
              );
            },
            icon: const Icon(Icons.psychology_rounded),
            tooltip: l.home_careerQuizTooltip,
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
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.lightbulb_outline_rounded),
              selectedIcon: const Icon(Icons.lightbulb_rounded),
              label: l.home_tabForYou,
            ),
            NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore_rounded),
              label: l.home_tabExplore,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmark_outline_rounded),
              selectedIcon: const Icon(Icons.bookmark_rounded),
              label: l.home_tabSaved,
            ),
          ],
        ),
      ),
    );
  }
}
