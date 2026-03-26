# CareerPath — Project Task List

---

## Phase 1 — Semester 1 (Foundation)

### Task 1 — Data Architecture & Backend API Design
- [x] Design hierarchical data schema (Streams → Categories → Nodes → Leaf Details)
- [x] Define and implement all REST API endpoints
  - [x] `GET /api/streams` — list all streams
  - [x] `GET /api/streams/{id}/categories` — stream categories
  - [x] `GET /api/nodes/{id}/children` — child nodes
  - [x] `GET /api/nodes/{id}/leaf-details` — leaf details (books, institutes, job sectors)
- [x] Seed initial career data into the database
- [x] Validate and test all API responses

---

### Task 2 — Student Profile, Personalized Suggestions & Full Explore Experience
- [x] **Profile Module**
  - [x] Design and build profile creation screen
  - [x] Implement stream selection UI (Science, Commerce, Arts)
  - [x] Persist profile data to local storage
  - [x] Load saved profile on app launch
- [x] **Suggestions Tab**
  - [x] Fetch and display career categories filtered by user's selected stream
  - [x] Handle loading and error states
  - [x] Implement pull-to-refresh
- [x] **Explore Tab**
  - [x] Display all available streams in expandable accordion sections
  - [x] Lazy-load categories when a stream is expanded
  - [x] Implement pull-to-refresh

---

### Task 3 — Hierarchical Career Drill-Down with Breadcrumb Navigation
- [x] Build sub-option screen to display children of a selected career node
- [x] Implement recursive API fetching for each navigation level
- [x] Build and render breadcrumb trail
  - [x] Track breadcrumb history as user drills down
  - [x] Allow tap-to-navigate on any breadcrumb ancestor
- [x] Manage navigation stack correctly across levels

---

### Task 4 — Leaf Node Detail View with Resource Aggregation
- [x] Detect leaf nodes (nodes with no children) and switch to detail view
- [x] Fetch and display leaf-level details from API
  - [x] Introductory description
  - [x] Recommended Books (title, author, reference link)
  - [x] Educational Institutes (name, city, website link)
  - [x] Job Sectors (name, description)
- [x] Implement expandable/collapsible sections for each resource group
- [x] Enable URL launching for book links and institute websites
- [x] Handle network-aware loading and error states

---

## Phase 2 — Semester 2 (Intelligence & Administration)

### Task 5 — Backend Administration Panel
- [ ] Set up React-based admin panel project
- [ ] Implement admin authentication and role-based access control
- [ ] Build CRUD interfaces for all data entities
  - [ ] Streams
  - [ ] Career categories and nodes
  - [ ] Books
  - [ ] Institutes
  - [ ] Job Sectors
- [ ] Add data validation on all forms
- [ ] Implement audit logging for data changes

---

### Task 6 — Neural Search & NLP Query Interface
- [ ] **Neural Search**
  - [ ] Generate vector embeddings for all career node descriptions
  - [ ] Build and index a similarity search index
  - [ ] Implement search API endpoint returning ranked results
  - [ ] Design and build search results UI in the app
- [ ] **NLP Query Interface**
  - [ ] Implement NLP query parsing layer
  - [ ] Build intent extraction for academic streams and career domains
  - [ ] Implement entity recognition and query-to-node mapping pipeline
  - [ ] Connect NLP output to the search results UI

---

### Task 7 — Personalized Career Recommendation Engine Enhancement
- [ ] Implement local user interaction tracking (browsed paths, viewed nodes)
- [ ] Build recommendation scoring model based on behavior and profile signals
- [ ] Integrate recommendations into the Suggestions Tab
- [ ] Test and tune recommendation relevance

---

### Task 8 — Offline Mode & Local Data Caching
- [ ] Integrate local database (SQLite or Hive)
- [ ] Define cache storage strategy for browsed career paths
- [ ] Implement data sync on connectivity restoration
- [ ] Add offline indicator in the UI
- [ ] Define and implement cache invalidation policy

---

### Task 9 — Analytics & Usage Insights Dashboard
- [ ] Instrument event tracking in the app (page views, career node visits, searches)
- [ ] Build analytics data pipeline on the backend
- [ ] Build admin dashboard panels
  - [ ] Most browsed career paths
  - [ ] Stream engagement metrics
  - [ ] Geographic user distribution
  - [ ] Search query trend analysis

---

## Future Scope

### Task F1 — Institute Self-Registration & Course Upload
- [ ] Build institute registration form (web)
- [ ] Implement admin review and approval workflow
- [ ] Build institute profile management interface
- [ ] Allow institutes to map their courses to career nodes on the platform
- [ ] Display institute-provided courses within leaf-detail view

---

### Task F2 — Expert & Consultant Registration
- [ ] Build expert registration and profile creation flow
- [ ] Link expertise areas to specific career nodes or streams
- [ ] Display LinkedIn profile links within relevant career node detail views
- [ ] Implement admin verification workflow for expert profiles

---

### Task F3 — Fee Structure & Affordability Information
- [ ] Define data model for course fee ranges per institute
- [ ] Build admin interface to enter and update fee data
- [ ] Explore integration with external data sources for fee information
- [ ] Display fee information within leaf node detail views

---

### Task F4 — Peer Community & Discussion Forums
- [ ] Design moderated discussion forum structure
- [ ] Implement topic threads linked to career nodes
- [ ] Build moderation tools for administrators

---

### Task F5 — Scholarship & Entrance Examination Integration
- [ ] Define data model for entrance exams and scholarships
- [ ] Link exam/scholarship data to relevant career nodes
- [ ] Display actionable exam and scholarship information in detail views

---

### Task F6 — Regional Language Support
- [ ] Implement localization/i18n framework in the app
- [ ] Translate core career content into target regional languages
- [ ] Build language selection in user profile
