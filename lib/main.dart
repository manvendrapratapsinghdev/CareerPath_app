import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'data/bookmark_repository.dart';
import 'data/exploration_repository.dart';
import 'data/recently_viewed_repository.dart';
import 'data/leaf_details_cache.dart';
import 'data/local_database.dart';
import 'data/local_data_source.dart';
import 'data/profile_repository.dart';
import 'data/rate_prompt_repository.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'services/analytics_service.dart';
import 'services/ai_chat_repository.dart';
import 'services/ai_http_client_factory.dart';
import 'services/bookmark_service.dart';
import 'services/career_data_service.dart';
import 'services/exploration_service.dart';
import 'services/feedback_service.dart';
import 'services/network_service.dart';
import 'services/profile_service.dart';
import 'services/rate_prompt_service.dart';
import 'services/recently_viewed_service.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';
import 'services/guided_ai_chat_repository.dart';
import 'services/ai_gemini_json.dart';
import 'services/ai_guide_extras.dart';
import 'services/ai_voice_services.dart';
import 'services/gemini_key_service.dart';
import 'services/institute_catalog_service.dart';
import 'services/semantic_index_service.dart';
import 'services/voice_preview_service.dart';
import 'services/voice_settings_service.dart';
import 'services/local_ai_grounding_service.dart';
import 'widgets/network_aware_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured — analytics will be no-op.
  }

  final prefs = await SharedPreferences.getInstance();
  final profileRepo = ProfileRepository(prefs);
  final profileService = ProfileService(profileRepo);
  final leafDetailsCache = LeafDetailsCache(prefs);
  final bookmarkService = BookmarkService(
    BookmarkRepository(prefs),
    leafDetailsCache,
  );
  final explorationService = ExplorationService(ExplorationRepository(prefs));
  final recentlyViewedService = RecentlyViewedService(
    RecentlyViewedRepository(prefs),
  );
  final ratePromptService = RatePromptService(RatePromptRepository(prefs));
  await ratePromptService.recordSession();

  final localDb = LocalDatabase();
  await localDb.init();
  final careerDataService = CareerDataService(LocalDataSource(localDb));
  final geminiKeyService = GeminiKeyService(
    client: await AiHttpClientFactory.create(),
  );
  unawaited(geminiKeyService.preload().catchError((_) {}));
  final instituteCatalog = InstituteCatalogService(localDb.getInstituteCatalog);
  final groundingService = LocalAiGroundingService(
    careerDataService,
    catalog: instituteCatalog,
  );
  final semanticIndex = SemanticIndexService(
    keyService: geminiKeyService,
    directory: getApplicationSupportDirectory,
    client: await AiHttpClientFactory.create(),
  );
  // Builds in the background, paced to the key's quota; search by meaning
  // joins keyword grounding as vectors become available.
  unawaited(
    SemanticIndexService.itemsFrom(
      careerDataService,
      instituteCatalog,
    ).then(semanticIndex.build).catchError((_) {}),
  );
  final aiChatRepository = GuidedAiChatRepository(
    keyService: geminiKeyService,
    groundingService: groundingService,
    loadAppHelp: () => rootBundle.loadString('assets/data/ai_guide_help.txt'),
    extraGrounding: semanticIndex.search,
    client: await AiHttpClientFactory.create(),
  );
  final aiGemini = AiGeminiJson(
    keyService: geminiKeyService,
    client: await AiHttpClientFactory.create(),
  );
  final aiGuideExtras = AiGuideExtras(
    trending: AiTrendingService(
      gemini: aiGemini,
      careers: careerDataService,
      catalog: instituteCatalog,
      prefs: prefs,
    ),
    deepDive: AiDeepDiveService(gemini: aiGemini, grounding: groundingService),
    feedback: AiFeedbackService(prefs),
  );
  final aiVoiceServices = AiVoiceServices(
    keyService: geminiKeyService,
    grounding: groundingService,
    settings: VoiceSettingsService(prefs),
    preview: VoicePreviewService(
      keyService: geminiKeyService,
      client: await AiHttpClientFactory.create(),
    ),
    httpClientFactory: await AiHttpClientFactory.createIoFactory(),
    extraGrounding: semanticIndex.search,
  );
  final networkService = NetworkService();
  final analyticsService = AnalyticsService();
  final feedbackService = FeedbackService();
  final themeService = ThemeService(prefs);
  final localeService = LocaleService(prefs);

  // Check profile and onboarding from local storage — no network call here.
  final hasProfile = await profileService.isProfileComplete();
  final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;

  runApp(
    CareerPathApp(
      prefs: prefs,
      profileService: profileService,
      bookmarkService: bookmarkService,
      explorationService: explorationService,
      recentlyViewedService: recentlyViewedService,
      ratePromptService: ratePromptService,
      careerDataService: careerDataService,
      aiChatRepository: aiChatRepository,
      aiVoiceServices: aiVoiceServices,
      aiGuideExtras: aiGuideExtras,
      networkService: networkService,
      analyticsService: analyticsService,
      feedbackService: feedbackService,
      themeService: themeService,
      localeService: localeService,
      hasProfile: hasProfile,
      onboardingSeen: onboardingSeen,
    ),
  );
}

class CareerPathApp extends StatelessWidget {
  final SharedPreferences prefs;
  final ProfileService profileService;
  final BookmarkService bookmarkService;
  final ExplorationService explorationService;
  final RecentlyViewedService recentlyViewedService;
  final RatePromptService ratePromptService;
  final CareerDataService careerDataService;
  final AiChatRepository aiChatRepository;
  final AiVoiceServices? aiVoiceServices;
  final AiGuideExtras? aiGuideExtras;
  final NetworkService networkService;
  final AnalyticsService analyticsService;
  final FeedbackService feedbackService;
  final ThemeService themeService;
  final LocaleService localeService;
  final bool hasProfile;
  final bool onboardingSeen;

  const CareerPathApp({
    super.key,
    required this.prefs,
    required this.profileService,
    required this.bookmarkService,
    required this.explorationService,
    required this.recentlyViewedService,
    required this.ratePromptService,
    required this.careerDataService,
    required this.aiChatRepository,
    this.aiVoiceServices,
    this.aiGuideExtras,
    required this.networkService,
    required this.analyticsService,
    required this.feedbackService,
    required this.themeService,
    required this.localeService,
    required this.hasProfile,
    required this.onboardingSeen,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeService, localeService]),
      builder: (context, _) => MaterialApp(
        title: 'Career Path Guidance',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeService.themeMode,
        locale: localeService.locale,
        supportedLocales: LocaleService.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          AppLocalizations.delegate,
        ],
        navigatorObservers: analyticsService.observers,
        routes: {
          '/home': (_) => HomeScreen(
            profileService: profileService,
            bookmarkService: bookmarkService,
            explorationService: explorationService,
            recentlyViewedService: recentlyViewedService,
            ratePromptService: ratePromptService,
            feedbackService: feedbackService,
            careerDataService: careerDataService,
            aiChatRepository: aiChatRepository,
            aiVoiceServices: aiVoiceServices,
            aiGuideExtras: aiGuideExtras,
            analyticsService: analyticsService,
            themeService: themeService,
            localeService: localeService,
          ),
          '/profile': (_) => ProfileScreen(
            profileService: profileService,
            analyticsService: analyticsService,
          ),
        },
        home: NetworkAwareWrapper(
          networkService: networkService,
          child: _buildInitialScreen(),
        ),
      ),
    );
  }

  Widget _buildInitialScreen() {
    if (hasProfile) {
      return HomeScreen(
        profileService: profileService,
        bookmarkService: bookmarkService,
        explorationService: explorationService,
        careerDataService: careerDataService,
        aiChatRepository: aiChatRepository,
        aiVoiceServices: aiVoiceServices,
        aiGuideExtras: aiGuideExtras,
        analyticsService: analyticsService,
        themeService: themeService,
      );
    }
    if (!onboardingSeen) {
      return _OnboardingWrapper(
        prefs: prefs,
        analyticsService: analyticsService,
      );
    }
    return ProfileScreen(
      profileService: profileService,
      analyticsService: analyticsService,
    );
  }
}

class _OnboardingWrapper extends StatelessWidget {
  final SharedPreferences prefs;
  final AnalyticsService analyticsService;

  const _OnboardingWrapper({
    required this.prefs,
    required this.analyticsService,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      onComplete: () async {
        analyticsService.logOnboardingCompleted();
        await prefs.setBool('onboarding_seen', true);
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/profile');
        }
      },
    );
  }
}
