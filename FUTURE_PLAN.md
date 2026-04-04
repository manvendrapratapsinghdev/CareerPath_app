# CareerPath — Future Plan

## Priority Roadmap

| Priority | Feature | Status | Commit |
|----------|---------|--------|--------|
| P0 | Bookmarks / Save Paths | Done | `26a99f8` |
| P0 | Search | Done | `99c85e5` |
| P1 | Share Career Paths | Done | `d6ae7c7` |
| P1 | Exploration Progress | Done | `5bc23bc` |
| P1 | Push Notifications | Pending | Needs FCM backend |
| P2 | Better Onboarding Tour | Done | `91df906` |
| P2 | Career Comparison | Done | `47e2f76` |
| P2 | Career Quiz | Done | `fbbaad5` |
| P3 | Dark Mode Toggle | Done | `2790117` |
| P3 | Offline Saved Paths | Pending | — |

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

---

## Remaining Features

### Push Notifications (P1)
- Requires Firebase Cloud Messaging backend setup
- "New career paths added in Science!"
- Weekly digest: "Career of the Week"

### Offline Access for Saved Paths (P3)
- Cache bookmarked career leaf details locally
- Important for unreliable connectivity areas
