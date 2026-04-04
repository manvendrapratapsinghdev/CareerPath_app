import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_or.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
    Locale('gu'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('mr'),
    Locale('or'),
    Locale('pa'),
    Locale('ta'),
    Locale('te'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Career Path Guidance'**
  String get appTitle;

  /// No description provided for @home_goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good Morning'**
  String get home_goodMorning;

  /// No description provided for @home_goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good Afternoon'**
  String get home_goodAfternoon;

  /// No description provided for @home_goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good Evening'**
  String get home_goodEvening;

  /// No description provided for @home_searchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get home_searchTooltip;

  /// No description provided for @home_careerQuizTooltip.
  ///
  /// In en, this message translates to:
  /// **'Career Quiz'**
  String get home_careerQuizTooltip;

  /// No description provided for @home_tabForYou.
  ///
  /// In en, this message translates to:
  /// **'For You'**
  String get home_tabForYou;

  /// No description provided for @home_tabExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get home_tabExplore;

  /// No description provided for @home_tabSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get home_tabSaved;

  /// No description provided for @home_rateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Enjoying CareerPath?'**
  String get home_rateDialogTitle;

  /// No description provided for @home_rateDialogContent.
  ///
  /// In en, this message translates to:
  /// **'If you find this app helpful, please take a moment to rate us on the Play Store.'**
  String get home_rateDialogContent;

  /// No description provided for @home_rateDialogDontAskAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Ask Again'**
  String get home_rateDialogDontAskAgain;

  /// No description provided for @home_rateDialogNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get home_rateDialogNotNow;

  /// No description provided for @home_rateDialogRateNow.
  ///
  /// In en, this message translates to:
  /// **'Rate Now'**
  String get home_rateDialogRateNow;

  /// No description provided for @onboarding_skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboarding_skip;

  /// No description provided for @onboarding_next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboarding_next;

  /// No description provided for @onboarding_getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboarding_getStarted;

  /// No description provided for @onboarding_page1Title.
  ///
  /// In en, this message translates to:
  /// **'Explore Career Paths'**
  String get onboarding_page1Title;

  /// No description provided for @onboarding_page1Description.
  ///
  /// In en, this message translates to:
  /// **'Browse through Science, Commerce, and Art streams to discover career options that match your interests.'**
  String get onboarding_page1Description;

  /// No description provided for @onboarding_page2Title.
  ///
  /// In en, this message translates to:
  /// **'Save & Compare'**
  String get onboarding_page2Title;

  /// No description provided for @onboarding_page2Description.
  ///
  /// In en, this message translates to:
  /// **'Bookmark careers you like, search across all paths, and share discoveries with friends.'**
  String get onboarding_page2Description;

  /// No description provided for @onboarding_page3Title.
  ///
  /// In en, this message translates to:
  /// **'Find Your Future'**
  String get onboarding_page3Title;

  /// No description provided for @onboarding_page3Description.
  ///
  /// In en, this message translates to:
  /// **'Get details on top institutes, recommended books, and job sectors for every career endpoint.'**
  String get onboarding_page3Description;

  /// No description provided for @profile_editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profile_editProfileTitle;

  /// No description provided for @profile_welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get profile_welcomeTitle;

  /// No description provided for @profile_updateDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Update your details'**
  String get profile_updateDetailsTitle;

  /// No description provided for @profile_updateDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your profile up to date'**
  String get profile_updateDetailsSubtitle;

  /// No description provided for @profile_welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us a bit about yourself to get\npersonalized career suggestions'**
  String get profile_welcomeSubtitle;

  /// No description provided for @profile_yourName.
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get profile_yourName;

  /// No description provided for @profile_enterYourName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get profile_enterYourName;

  /// No description provided for @profile_nameValidationError.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get profile_nameValidationError;

  /// No description provided for @profile_yourStream.
  ///
  /// In en, this message translates to:
  /// **'Your 10+2 Stream'**
  String get profile_yourStream;

  /// No description provided for @profile_selectStreamError.
  ///
  /// In en, this message translates to:
  /// **'Please select a stream'**
  String get profile_selectStreamError;

  /// No description provided for @profile_streamScience.
  ///
  /// In en, this message translates to:
  /// **'Science'**
  String get profile_streamScience;

  /// No description provided for @profile_streamScienceDesc.
  ///
  /// In en, this message translates to:
  /// **'Physics, Chemistry, Biology, Math'**
  String get profile_streamScienceDesc;

  /// No description provided for @profile_streamCommerce.
  ///
  /// In en, this message translates to:
  /// **'Commerce'**
  String get profile_streamCommerce;

  /// No description provided for @profile_streamCommerceDesc.
  ///
  /// In en, this message translates to:
  /// **'Accounting, Economics, Business'**
  String get profile_streamCommerceDesc;

  /// No description provided for @profile_streamArt.
  ///
  /// In en, this message translates to:
  /// **'Art'**
  String get profile_streamArt;

  /// No description provided for @profile_streamArtDesc.
  ///
  /// In en, this message translates to:
  /// **'Literature, History, Fine Arts'**
  String get profile_streamArtDesc;

  /// No description provided for @profile_appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get profile_appearance;

  /// No description provided for @profile_themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get profile_themeSystem;

  /// No description provided for @profile_themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get profile_themeLight;

  /// No description provided for @profile_themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get profile_themeDark;

  /// No description provided for @profile_language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profile_language;

  /// No description provided for @profile_sendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get profile_sendFeedback;

  /// No description provided for @profile_sendFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bug reports, feature requests & more'**
  String get profile_sendFeedbackSubtitle;

  /// No description provided for @profile_updateProfile.
  ///
  /// In en, this message translates to:
  /// **'Update Profile'**
  String get profile_updateProfile;

  /// No description provided for @profile_getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get profile_getStarted;

  /// No description provided for @profile_skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get profile_skipForNow;

  /// No description provided for @profile_saveError.
  ///
  /// In en, this message translates to:
  /// **'Failed to save profile. Please try again.'**
  String get profile_saveError;

  /// No description provided for @profile_developedBy.
  ///
  /// In en, this message translates to:
  /// **'Developed by '**
  String get profile_developedBy;

  /// No description provided for @profile_under.
  ///
  /// In en, this message translates to:
  /// **' under '**
  String get profile_under;

  /// No description provided for @profile_sola.
  ///
  /// In en, this message translates to:
  /// **' (SoLA)'**
  String get profile_sola;

  /// No description provided for @quiz_title.
  ///
  /// In en, this message translates to:
  /// **'Career Quiz'**
  String get quiz_title;

  /// No description provided for @quiz_resultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Results'**
  String get quiz_resultsTitle;

  /// No description provided for @quiz_topCareerAreas.
  ///
  /// In en, this message translates to:
  /// **'Your Top Career Areas'**
  String get quiz_topCareerAreas;

  /// No description provided for @quiz_retake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get quiz_retake;

  /// No description provided for @quiz_share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get quiz_share;

  /// No description provided for @quiz_shareHeader.
  ///
  /// In en, this message translates to:
  /// **'My CareerPath Quiz Results!\n\n'**
  String get quiz_shareHeader;

  /// No description provided for @quiz_shareFooter.
  ///
  /// In en, this message translates to:
  /// **'\nTake the quiz on CareerPath app!'**
  String get quiz_shareFooter;

  /// No description provided for @quiz_q1.
  ///
  /// In en, this message translates to:
  /// **'What kind of activity excites you most?'**
  String get quiz_q1;

  /// No description provided for @quiz_q1Opt1.
  ///
  /// In en, this message translates to:
  /// **'Experimenting and building things'**
  String get quiz_q1Opt1;

  /// No description provided for @quiz_q1Opt2.
  ///
  /// In en, this message translates to:
  /// **'Solving puzzles and analyzing data'**
  String get quiz_q1Opt2;

  /// No description provided for @quiz_q1Opt3.
  ///
  /// In en, this message translates to:
  /// **'Creating art, music, or stories'**
  String get quiz_q1Opt3;

  /// No description provided for @quiz_q1Opt4.
  ///
  /// In en, this message translates to:
  /// **'Leading teams and organizing events'**
  String get quiz_q1Opt4;

  /// No description provided for @quiz_q2.
  ///
  /// In en, this message translates to:
  /// **'Which subject do you enjoy the most?'**
  String get quiz_q2;

  /// No description provided for @quiz_q2Opt1.
  ///
  /// In en, this message translates to:
  /// **'Physics or Mathematics'**
  String get quiz_q2Opt1;

  /// No description provided for @quiz_q2Opt2.
  ///
  /// In en, this message translates to:
  /// **'Biology or Chemistry'**
  String get quiz_q2Opt2;

  /// No description provided for @quiz_q2Opt3.
  ///
  /// In en, this message translates to:
  /// **'Economics or Business Studies'**
  String get quiz_q2Opt3;

  /// No description provided for @quiz_q2Opt4.
  ///
  /// In en, this message translates to:
  /// **'Languages or Social Studies'**
  String get quiz_q2Opt4;

  /// No description provided for @quiz_q3.
  ///
  /// In en, this message translates to:
  /// **'In a group project, you usually...'**
  String get quiz_q3;

  /// No description provided for @quiz_q3Opt1.
  ///
  /// In en, this message translates to:
  /// **'Do the technical or hands-on work'**
  String get quiz_q3Opt1;

  /// No description provided for @quiz_q3Opt2.
  ///
  /// In en, this message translates to:
  /// **'Research and gather information'**
  String get quiz_q3Opt2;

  /// No description provided for @quiz_q3Opt3.
  ///
  /// In en, this message translates to:
  /// **'Design the presentation or visuals'**
  String get quiz_q3Opt3;

  /// No description provided for @quiz_q3Opt4.
  ///
  /// In en, this message translates to:
  /// **'Coordinate and manage the team'**
  String get quiz_q3Opt4;

  /// No description provided for @quiz_q4.
  ///
  /// In en, this message translates to:
  /// **'What type of work environment appeals to you?'**
  String get quiz_q4;

  /// No description provided for @quiz_q4Opt1.
  ///
  /// In en, this message translates to:
  /// **'Lab, workshop, or tech office'**
  String get quiz_q4Opt1;

  /// No description provided for @quiz_q4Opt2.
  ///
  /// In en, this message translates to:
  /// **'Hospital, clinic, or research center'**
  String get quiz_q4Opt2;

  /// No description provided for @quiz_q4Opt3.
  ///
  /// In en, this message translates to:
  /// **'Studio, agency, or freelance'**
  String get quiz_q4Opt3;

  /// No description provided for @quiz_q4Opt4.
  ///
  /// In en, this message translates to:
  /// **'Corporate office or courtroom'**
  String get quiz_q4Opt4;

  /// No description provided for @quiz_q5.
  ///
  /// In en, this message translates to:
  /// **'Which skill are you most proud of?'**
  String get quiz_q5;

  /// No description provided for @quiz_q5Opt1.
  ///
  /// In en, this message translates to:
  /// **'Problem-solving and logical thinking'**
  String get quiz_q5Opt1;

  /// No description provided for @quiz_q5Opt2.
  ///
  /// In en, this message translates to:
  /// **'Attention to detail and patience'**
  String get quiz_q5Opt2;

  /// No description provided for @quiz_q5Opt3.
  ///
  /// In en, this message translates to:
  /// **'Creativity and imagination'**
  String get quiz_q5Opt3;

  /// No description provided for @quiz_q5Opt4.
  ///
  /// In en, this message translates to:
  /// **'Communication and persuasion'**
  String get quiz_q5Opt4;

  /// No description provided for @quiz_q6.
  ///
  /// In en, this message translates to:
  /// **'What would you watch a documentary about?'**
  String get quiz_q6;

  /// No description provided for @quiz_q6Opt1.
  ///
  /// In en, this message translates to:
  /// **'Space exploration or AI'**
  String get quiz_q6Opt1;

  /// No description provided for @quiz_q6Opt2.
  ///
  /// In en, this message translates to:
  /// **'Medical breakthroughs or nature'**
  String get quiz_q6Opt2;

  /// No description provided for @quiz_q6Opt3.
  ///
  /// In en, this message translates to:
  /// **'Film making or art history'**
  String get quiz_q6Opt3;

  /// No description provided for @quiz_q6Opt4.
  ///
  /// In en, this message translates to:
  /// **'Business empires or legal battles'**
  String get quiz_q6Opt4;

  /// No description provided for @quiz_q7.
  ///
  /// In en, this message translates to:
  /// **'Your ideal weekend project?'**
  String get quiz_q7;

  /// No description provided for @quiz_q7Opt1.
  ///
  /// In en, this message translates to:
  /// **'Building an app or fixing gadgets'**
  String get quiz_q7Opt1;

  /// No description provided for @quiz_q7Opt2.
  ///
  /// In en, this message translates to:
  /// **'Reading research papers or gardening'**
  String get quiz_q7Opt2;

  /// No description provided for @quiz_q7Opt3.
  ///
  /// In en, this message translates to:
  /// **'Painting, writing, or photography'**
  String get quiz_q7Opt3;

  /// No description provided for @quiz_q7Opt4.
  ///
  /// In en, this message translates to:
  /// **'Planning a startup or debating'**
  String get quiz_q7Opt4;

  /// No description provided for @quiz_q8.
  ///
  /// In en, this message translates to:
  /// **'Which impact matters most to you?'**
  String get quiz_q8;

  /// No description provided for @quiz_q8Opt1.
  ///
  /// In en, this message translates to:
  /// **'Innovating technology for the future'**
  String get quiz_q8Opt1;

  /// No description provided for @quiz_q8Opt2.
  ///
  /// In en, this message translates to:
  /// **'Saving lives and improving health'**
  String get quiz_q8Opt2;

  /// No description provided for @quiz_q8Opt3.
  ///
  /// In en, this message translates to:
  /// **'Inspiring people through art and culture'**
  String get quiz_q8Opt3;

  /// No description provided for @quiz_q8Opt4.
  ///
  /// In en, this message translates to:
  /// **'Building businesses and shaping policy'**
  String get quiz_q8Opt4;

  /// No description provided for @quiz_progressLabel.
  ///
  /// In en, this message translates to:
  /// **'{current}/{total}'**
  String quiz_progressLabel(int current, int total);

  /// No description provided for @bookmarks_noSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved paths yet'**
  String get bookmarks_noSavedTitle;

  /// No description provided for @bookmarks_noSavedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bookmark career paths you like\nand they\'ll appear here'**
  String get bookmarks_noSavedSubtitle;

  /// No description provided for @bookmarks_savedCareerPath.
  ///
  /// In en, this message translates to:
  /// **'Saved career path'**
  String get bookmarks_savedCareerPath;

  /// No description provided for @bookmarks_removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get bookmarks_removeBookmark;

  /// No description provided for @bookmarks_selectToCompare.
  ///
  /// In en, this message translates to:
  /// **'Select 2-3 paths to compare'**
  String get bookmarks_selectToCompare;

  /// No description provided for @bookmarks_savedPathsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} saved paths'**
  String bookmarks_savedPathsCount(int count);

  /// No description provided for @bookmarks_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get bookmarks_cancel;

  /// No description provided for @bookmarks_compare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get bookmarks_compare;

  /// No description provided for @bookmarks_compareNPaths.
  ///
  /// In en, this message translates to:
  /// **'Compare {count} paths'**
  String bookmarks_compareNPaths(int count);

  /// No description provided for @explore_failedToLoadData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load data'**
  String get explore_failedToLoadData;

  /// No description provided for @explore_noStreamsTitle.
  ///
  /// In en, this message translates to:
  /// **'No streams available'**
  String get explore_noStreamsTitle;

  /// No description provided for @explore_noStreamsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check back later for career streams'**
  String get explore_noStreamsSubtitle;

  /// No description provided for @explore_categoriesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} categories'**
  String explore_categoriesCount(int count);

  /// No description provided for @explore_subPathsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sub-paths'**
  String explore_subPathsCount(int count);

  /// No description provided for @explore_serverDown.
  ///
  /// In en, this message translates to:
  /// **'Server is down.\nPlease contact admin (9807942950) to start the server.'**
  String get explore_serverDown;

  /// No description provided for @explore_failedToLoadCategories.
  ///
  /// In en, this message translates to:
  /// **'Failed to load categories'**
  String get explore_failedToLoadCategories;

  /// No description provided for @explore_noCategoriesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No categories available'**
  String get explore_noCategoriesAvailable;

  /// No description provided for @suggestions_personalizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalize your feed'**
  String get suggestions_personalizeTitle;

  /// No description provided for @suggestions_personalizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile to see career\nsuggestions tailored just for you'**
  String get suggestions_personalizeSubtitle;

  /// No description provided for @suggestions_setUpProfile.
  ///
  /// In en, this message translates to:
  /// **'Set Up Profile'**
  String get suggestions_setUpProfile;

  /// No description provided for @suggestions_noPathsTitle.
  ///
  /// In en, this message translates to:
  /// **'No paths yet'**
  String get suggestions_noPathsTitle;

  /// No description provided for @suggestions_noPathsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Career categories for your stream\nwill appear here soon'**
  String get suggestions_noPathsSubtitle;

  /// No description provided for @suggestions_refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get suggestions_refresh;

  /// No description provided for @suggestions_recentlyViewed.
  ///
  /// In en, this message translates to:
  /// **'Recently Viewed'**
  String get suggestions_recentlyViewed;

  /// No description provided for @suggestions_streamLabel.
  ///
  /// In en, this message translates to:
  /// **'{stream} Stream'**
  String suggestions_streamLabel(String stream);

  /// No description provided for @suggestions_careerPathsAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} career paths available'**
  String suggestions_careerPathsAvailable(int count);

  /// No description provided for @suggestions_exploredProgress.
  ///
  /// In en, this message translates to:
  /// **'{visited} of {total} explored'**
  String suggestions_exploredProgress(int visited, int total);

  /// No description provided for @suggestions_pathsAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} paths available'**
  String suggestions_pathsAvailable(int count);

  /// No description provided for @suggestions_connectionError.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to server. Check your connection and retry.'**
  String get suggestions_connectionError;

  /// No description provided for @search_hint.
  ///
  /// In en, this message translates to:
  /// **'Search career paths...'**
  String get search_hint;

  /// No description provided for @search_emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Search careers'**
  String get search_emptyTitle;

  /// No description provided for @search_emptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type to search across all\nloaded career paths'**
  String get search_emptySubtitle;

  /// No description provided for @search_noResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get search_noResultsTitle;

  /// No description provided for @search_noResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term\nor explore more paths first'**
  String get search_noResultsSubtitle;

  /// No description provided for @search_careerEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Career endpoint'**
  String get search_careerEndpoint;

  /// No description provided for @search_optionsAhead.
  ///
  /// In en, this message translates to:
  /// **'{count} options ahead'**
  String search_optionsAhead(int count);

  /// No description provided for @sub_careerEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Career endpoint'**
  String get sub_careerEndpoint;

  /// No description provided for @sub_optionsAhead.
  ///
  /// In en, this message translates to:
  /// **'{count} options ahead'**
  String sub_optionsAhead(int count);

  /// No description provided for @sub_removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get sub_removeBookmark;

  /// No description provided for @sub_saveCareerPath.
  ///
  /// In en, this message translates to:
  /// **'Save career path'**
  String get sub_saveCareerPath;

  /// No description provided for @sub_shareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get sub_shareTooltip;

  /// No description provided for @sub_finalCareerOption.
  ///
  /// In en, this message translates to:
  /// **'Final Career Option'**
  String get sub_finalCareerOption;

  /// No description provided for @sub_recommendedBooks.
  ///
  /// In en, this message translates to:
  /// **'Recommended Books'**
  String get sub_recommendedBooks;

  /// No description provided for @sub_noBooksAvailable.
  ///
  /// In en, this message translates to:
  /// **'No books available'**
  String get sub_noBooksAvailable;

  /// No description provided for @sub_booksCount.
  ///
  /// In en, this message translates to:
  /// **'{count} books'**
  String sub_booksCount(int count);

  /// No description provided for @sub_topInstitutes.
  ///
  /// In en, this message translates to:
  /// **'Top Institutes'**
  String get sub_topInstitutes;

  /// No description provided for @sub_noInstitutesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No institutes available'**
  String get sub_noInstitutesAvailable;

  /// No description provided for @sub_institutesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} institutes'**
  String sub_institutesCount(int count);

  /// No description provided for @sub_jobSectors.
  ///
  /// In en, this message translates to:
  /// **'Job Sectors'**
  String get sub_jobSectors;

  /// No description provided for @sub_noSectorsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No sectors available'**
  String get sub_noSectorsAvailable;

  /// No description provided for @sub_sectorsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sectors'**
  String sub_sectorsCount(int count);

  /// No description provided for @sub_moreDetailsSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'More details coming soon!'**
  String get sub_moreDetailsSoonTitle;

  /// No description provided for @sub_moreDetailsSoonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Resources for this career path\nare being curated'**
  String get sub_moreDetailsSoonSubtitle;

  /// No description provided for @sub_serverDownError.
  ///
  /// In en, this message translates to:
  /// **'Server is down.\nPlease contact admin (9807942950) to start the server.'**
  String get sub_serverDownError;

  /// No description provided for @sub_loadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading data.\nCheck your connection and try again.'**
  String get sub_loadError;

  /// No description provided for @sub_shareFooter.
  ///
  /// In en, this message translates to:
  /// **'\nExplore more on CareerPath app!'**
  String get sub_shareFooter;

  /// No description provided for @compare_title.
  ///
  /// In en, this message translates to:
  /// **'Compare Careers'**
  String get compare_title;

  /// No description provided for @compare_careerPath.
  ///
  /// In en, this message translates to:
  /// **'Career Path'**
  String get compare_careerPath;

  /// No description provided for @compare_topInstitutes.
  ///
  /// In en, this message translates to:
  /// **'Top Institutes'**
  String get compare_topInstitutes;

  /// No description provided for @compare_jobSectors.
  ///
  /// In en, this message translates to:
  /// **'Job Sectors'**
  String get compare_jobSectors;

  /// No description provided for @compare_recommendedBooks.
  ///
  /// In en, this message translates to:
  /// **'Recommended Books'**
  String get compare_recommendedBooks;

  /// No description provided for @compare_noInstitutes.
  ///
  /// In en, this message translates to:
  /// **'No institutes'**
  String get compare_noInstitutes;

  /// No description provided for @compare_noSectors.
  ///
  /// In en, this message translates to:
  /// **'No sectors'**
  String get compare_noSectors;

  /// No description provided for @compare_noBooks.
  ///
  /// In en, this message translates to:
  /// **'No books'**
  String get compare_noBooks;

  /// No description provided for @compare_failedToLoadDetails.
  ///
  /// In en, this message translates to:
  /// **'Failed to load details'**
  String get compare_failedToLoadDetails;

  /// No description provided for @feedback_title.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedback_title;

  /// No description provided for @feedback_ratingPrompt.
  ///
  /// In en, this message translates to:
  /// **'How would you rate this app?'**
  String get feedback_ratingPrompt;

  /// No description provided for @feedback_category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get feedback_category;

  /// No description provided for @feedback_yourMessage.
  ///
  /// In en, this message translates to:
  /// **'Your Message'**
  String get feedback_yourMessage;

  /// No description provided for @feedback_messageHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you think...'**
  String get feedback_messageHint;

  /// No description provided for @feedback_messageValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter at least 10 characters'**
  String get feedback_messageValidation;

  /// No description provided for @feedback_submit.
  ///
  /// In en, this message translates to:
  /// **'Submit Feedback'**
  String get feedback_submit;

  /// No description provided for @feedback_selectRating.
  ///
  /// In en, this message translates to:
  /// **'Please select a rating'**
  String get feedback_selectRating;

  /// No description provided for @feedback_thanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your feedback!'**
  String get feedback_thanks;

  /// No description provided for @feedback_noEmailApp.
  ///
  /// In en, this message translates to:
  /// **'No email app found. Please install one or email us directly.'**
  String get feedback_noEmailApp;

  /// No description provided for @feedback_categoryBug.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get feedback_categoryBug;

  /// No description provided for @feedback_categoryFeature.
  ///
  /// In en, this message translates to:
  /// **'Feature Request'**
  String get feedback_categoryFeature;

  /// No description provided for @feedback_categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get feedback_categoryOther;

  /// No description provided for @common_oops.
  ///
  /// In en, this message translates to:
  /// **'Oops!'**
  String get common_oops;

  /// No description provided for @common_somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get common_somethingWentWrong;

  /// No description provided for @common_tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get common_tryAgain;

  /// No description provided for @common_noInternetConnection.
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection'**
  String get common_noInternetConnection;

  /// No description provided for @common_noneAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'None available yet'**
  String get common_noneAvailableYet;

  /// No description provided for @common_byAuthor.
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String common_byAuthor(String author);

  /// No description provided for @common_viewBook.
  ///
  /// In en, this message translates to:
  /// **'View book'**
  String get common_viewBook;

  /// No description provided for @common_visitWebsite.
  ///
  /// In en, this message translates to:
  /// **'Visit website'**
  String get common_visitWebsite;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'bn',
    'en',
    'gu',
    'hi',
    'kn',
    'ml',
    'mr',
    'or',
    'pa',
    'ta',
    'te',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'gu':
      return AppLocalizationsGu();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
    case 'ml':
      return AppLocalizationsMl();
    case 'mr':
      return AppLocalizationsMr();
    case 'or':
      return AppLocalizationsOr();
    case 'pa':
      return AppLocalizationsPa();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
