# CareerPath — Future Plan

## Priority Roadmap

| Priority | Feature | Status | Commit |
|----------|---------|--------|--------|
| P0 | Bookmarks / Save Paths | Done | `26a99f8` |
| P0 | Search | Done | `99c85e5` |
| P1 | Share Career Paths | Done | `d6ae7c7` |
| P1 | Exploration Progress | Done | `5bc23bc` |
| ~P1~ | ~Push Notifications~ | Dropped | — |
| P2 | Better Onboarding Tour | Done | `91df906` |
| P2 | Career Comparison | Done | `47e2f76` |
| P2 | Career Quiz | Done | `fbbaad5` |
| P3 | Dark Mode Toggle | Done | `2790117` |
| P3 | Offline Saved Paths | Done | `10d7ff2` |
| P3 | Offline-First SQLite DB | Done | `fca2d96` |
| P1 | Firebase Analytics | Done | `889548d` |
| P2 | Rate the App Prompt | Done | `33f7497` |
| P2 | Feedback Form | Done | `a13c972` |
| P2 | Career Path Depth Indicator | Done | `2806f80` |
| P2 | Recently Viewed | Done | `34ffeb1` |
| P3 | App Localization (10 Indian Languages) | Done | `6d49478` |

---

## Completed Features

### 1. Bookmarks / Save Career Paths
- Bookmark icon on leaf career nodes in AppBar
- "Saved" tab in bottom navigation
- SharedPreferences persistence via BookmarkRepository + BookmarkService
- ChangeNotifier pattern for real-time UI updates

### 2. Search
- SearchScreen with debounced text input (300ms)
- Client-side search across all loaded CareerNode objects
- 50-result cap, accessible from search icon in AppBar

### 3. Share Career Paths
- Share icon on leaf detail screens (next to bookmark)
- Formats career name, intro, top institutes, and job sectors
- Uses share_plus for native sharing

### 4. Exploration Progress Tracker
- ExplorationRepository + ExplorationService tracking visited nodes
- Progress bar on SuggestionsTab dashboard ("X of Y explored")
- Auto-marks nodes visited when SubOptionScreen opens

### 5. Better Onboarding Tour
- 3-screen swipeable intro on first launch
- Explore Paths → Save & Compare → Find Your Future
- Skip button, animated page indicators
- Persists onboarding_seen flag

### 6. Career Comparison
- Compare mode in Saved tab (checkbox selection, 2-3 paths)
- Side-by-side CompareScreen showing institutes, job sectors, books
- Loads leaf details in parallel

### 7. Career Quiz / Assessment
- 8-question personality/interest quiz
- Maps answers to 14 career categories via weighted scoring
- Top 3 results with specific career suggestions
- Shareable results, retake option
- Accessible from brain icon in AppBar

### 8. Dark Mode Toggle
- ThemeService backed by SharedPreferences
- System / Light / Dark segmented button in profile edit screen
- Reactive theme switching via ListenableBuilder

### 9. Offline Access for Saved Paths
- LeafDetailsCache stores details JSON in SharedPreferences
- Auto-caches when details load for bookmarked nodes
- Falls back to cache when API fails (offline)

### 10. Offline-First SQLite DB
- Bundled 2MB career_path.db in assets
- LocalDatabase + LocalDataSource replaces API calls
- Eager-loads all 380 nodes on startup
- DataSource abstraction for API/local swap

---

## Remaining Features

### Firebase Analytics (P1)
- Re-add firebase_core + firebase_analytics packages
- Configure google-services.json for Android
- AnalyticsService already stubbed — just needs real Firebase instance
- Track: screen views, navigation, bookmarks, search, quiz, share events

### Rate the App Prompt (P2)
- Show "Rate us" dialog after 5+ sessions or 3+ days of use
- Track session count in SharedPreferences
- Link to Play Store listing
- "Not now" and "Don't ask again" options

### Feedback Form (P2)
- In-app feedback form accessible from profile/settings
- Fields: rating (stars), category (bug/feature/other), message
- Submit via email intent or backend API
- Optional screenshot attachment

### Career Path Depth Indicator (P2)
- Visual indicator showing current depth in the career tree
- Breadcrumb enhancement: show "Level 3 of 5" or step dots
- Helps users understand how deep the exploration goes

### Recently Viewed (P2)
- Track last 10-15 visited career nodes
- "Recently Viewed" section on home screen (horizontal scroll)
- Persisted in SharedPreferences
- Quick access to resume exploration

### App Localization — Hindi (P3)
- Use Flutter's intl/l10n system
- Translate: UI labels, onboarding text, quiz questions
- Career data stays in English (from backend)
- Language toggle in profile/settings
