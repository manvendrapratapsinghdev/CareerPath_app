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

*(Source: [TASK_LIST.md](TASK_LIST.md) Phase 2 and Future Scope — verified against the codebase.)*

### 11. AI Guide — Voice Conversation (in progress, `feature/ai-guide-voice`)
- Gemini Live voice session, mic streaming, barge-in, spoken welcome: built and committed
- Still missing: transcript revealed in step with audio playback (currently delivered as one block per turn), rotating landing titles, animated "Ask me about…" hint text, Lottie loaders, auto-start voice after welcome
- Search by meaning (semantic index) built but still backfilling on-device at the Gemini key's quota rate; keyword search covers the gap

### 12. Backend Admin Panel (P1)
- React-based admin project, authentication and role-based access control
- CRUD interfaces for streams, categories/nodes, books, institutes, job sectors
- Form validation and audit logging for data changes
- Not started — no admin panel exists yet

### 13. Personalized Recommendation Engine (P1)
- Local interaction tracking (browsed paths, viewed nodes) beyond what ExplorationService already records
- Scoring model combining behavior + profile signals
- Surface recommendations in the Suggestions Tab
- Not started

### 14. Analytics & Usage Insights Dashboard (P2)
- Firebase Analytics event tracking is live in the app
- Still missing: backend pipeline and admin dashboard panels (most-browsed paths, stream engagement, geographic distribution, search trend analysis)

### 15. NLP Query Interface for Explore/Search (P2)
- The AI Guide already does intent routing and grounded answers in chat form
- Still missing: a dedicated entity-recognition → query-to-node mapping pipeline wired into the Explore tab's own search results UI (as opposed to the conversational AI Guide)

### Future Scope (not started)
- **F1 — Institute Self-Registration**: registration form, admin review/approval, course-to-node mapping
- **F2 — Expert & Consultant Registration**: profile creation, expertise-to-node linking, LinkedIn display, admin verification
- **F3 — Fee Structure & Affordability**: fee data model, admin entry UI, display in leaf detail view
- **F4 — Peer Community & Discussion Forums**: topic threads per career node, moderation tools
