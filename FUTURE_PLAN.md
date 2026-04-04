# CareerPath — Future Plan

## Current State

The app is a solid career exploration tool — clean UI, smooth navigation, hierarchical browsing, and personalized suggestions. But it's essentially a read-only information viewer with no reason for users to come back after their first session. The features below aim to fix that.

---

## Priority Roadmap

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P0 | Bookmarks / Save Paths | Small | High |
| P0 | Search | Medium | High |
| P1 | Share Career Paths | Small | High |
| P1 | Exploration Progress | Small | Medium |
| P1 | Push Notifications | Medium | High |
| P2 | Career Quiz | Large | Very High |
| P2 | Career Comparison | Medium | Medium |
| P2 | Better Onboarding Tour | Small | Medium |
| P3 | Dark Mode Toggle | Small | Low |
| P3 | Offline Saved Paths | Medium | Medium |

---

## P0 — Must Have

### 1. Bookmarks / Save Career Paths

Users discover a career path they like but have no way to save it. Next time they open the app, they have to navigate the whole tree again.

- Add a bookmark icon on leaf nodes
- "Saved Paths" section on the home screen
- Local storage (SharedPreferences) — no backend changes needed

### 2. Search

Users currently must drill through 3-5 levels of hierarchy to find anything. A search bar on the home screen that searches across all career nodes, institutes, and books would dramatically improve usability.

- Search by career name, institute, or book title
- Show results grouped by type
- Uses existing `/api/` endpoints or client-side filtering

---

## P1 — High Value

### 3. Share Career Paths

Let users share a career path summary (name + intro + top institutes) via WhatsApp, Instagram, etc. This is free organic marketing — students share with friends.

- Share button on leaf detail view
- Use Flutter's `share_plus` package
- Generate a formatted text snippet

### 4. Exploration Progress Tracker

Show users how much of their stream they've explored.

- "You've explored 4/18 Science careers"
- Progress bar per stream on the home screen
- Track visited leaf nodes locally
- Encourages completionist behavior

### 5. Push Notifications

- "New career paths added in Science!"
- "Did you know about Marine Biology? Explore now"
- Weekly digest: "Career of the Week"
- Uses Firebase Cloud Messaging (Firebase already integrated)

---

## P2 — Differentiators

### 6. Career Quiz / Assessment

A short personality/interest quiz that recommends career paths. Quizzes are inherently shareable — "I got Data Scientist! What did you get?"

- 5-10 questions
- Map answers to career leaf nodes
- Shareable result card

### 7. Career Comparison

Let users select 2-3 career paths and compare them side-by-side — institutes, job sectors, required skills. No competing app does this well for Indian students.

### 8. Better Onboarding Tour

Current onboarding is name + stream only. Improve with:

- A quick 3-screen app tour (swipeable) showing key features
- "What interests you?" tags (technology, healthcare, creative arts) for better personalization beyond just stream

---

## P3 — Nice to Have

### 9. Dark Mode Toggle

The app follows system theme but has no manual toggle. Many students prefer dark mode — give them control in the profile screen.

### 10. Offline Access for Saved Paths

Cache bookmarked career details locally so users can read them without internet. Important for students in areas with unreliable connectivity.

---

## How We Work

Pick one feature at a time. For each:

1. Finalize requirements
2. Design and implement
3. Test and commit
4. Move on to the next
