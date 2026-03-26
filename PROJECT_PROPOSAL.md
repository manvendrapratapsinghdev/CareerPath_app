# CareerPath: A Structured Career Guidance Platform for Students


## Abstract

CareerPath is a mobile application designed to guide students — particularly those in rural and semi-urban areas — in making informed decisions about their academic and professional futures. The platform intends to aggregate structured, domain-specific career information across multiple educational streams and present it in a hierarchical, easy-to-navigate format. Unlike general-purpose AI assistants, CareerPath will offer curated data covering career categories, recommended literature, educational institutes, and job sectors — all under one platform.

This document serves as the formal project proposal for the MTP submission, outlining the vision, motivation, planned features, and future enhancement roadmap.

> **[ADDED IN REVISION]** All newly added points in this revision are explicitly marked with the same label so they remain visually distinguishable after Markdown-to-LaTeX conversion.

---

## Introduction & Background

With the rapid expansion of career options after Class 10 and Class 12, students frequently face difficulty in selecting the right educational path. The decision is influenced by a complex mix of factors: stream eligibility, available institutes, future job prospects, recommended study resources, and personal aptitude. A student with limited access to professional guidance is likely to make this decision based on incomplete or incorrect information.

Today, AI-powered tools such as ChatGPT and Google Gemini are highly capable and can answer a wide range of questions. However, there is a fundamental limitation that affects how students use them for career guidance: **the results are shaped entirely by what the student already knows to ask.** Search engines and AI assistants return answers based on the query provided — which means a student who is unaware of a particular career option may not discover it, simply because they did not know to search for it in the first place.

This creates an invisible knowledge gap. Students end up exploring only the paths they have already heard of, while an entire landscape of relevant options remains outside their view. The guidance they receive is not wrong — it is just incomplete, filtered by the boundaries of their existing awareness.

CareerPath is designed to address this problem directly. Rather than responding to queries, it presents a complete and structured map of all available career options within a student's chosen academic stream — ensuring that students are not limited to what they already know, but are instead exposed to the full breadth of possibilities available to them.

---

## Problem Statement

Students in tier-2 and tier-3 cities, as well as rural areas, do not have easy access to career counsellors, orientation programmes, or dedicated guidance infrastructure. They rely heavily on word of mouth or fragmented online content, leading to decisions that may not align with their interests, capabilities, or long-term goals.

Existing solutions suffer from one or more of the following drawbacks:

| Issue | Description |
|---|---|
| **Unstructured Information** | Career information is scattered across multiple websites with no unified view |
| **Generic Guidance** | AI tools provide broad answers rather than domain-specific, structured advice |
| **No Personalization** | Most platforms do not adapt content based on the student's selected academic stream |
| **Lack of Supporting Resources** | Few platforms combine career descriptions with books, institutes, and job sector data |

**[ADDED IN REVISION]** In addition, students from economically weaker backgrounds often need a way to identify affordable pathways early in the exploration process. Existing platforms rarely distinguish institutes run by trusts, institutes with active scholarship schemes, or institutes known for lower-fee access models, making it harder for such students to focus only on financially realistic options.

---

## Motivation

The primary motivation behind this project is the observed disparity in career awareness between students in urban centres and those in remote or semi-urban areas. Students in metropolitan cities typically have access to school counsellors, coaching centres, career fairs, and informed peer networks. They are rarely at a loss for guidance.

However, students in remote areas often proceed through their academic years without a clear understanding of what awaits them after graduation — what courses exist, which institutes offer them, what the job market looks like, or what skills are needed. This information asymmetry has long-term consequences on their professional lives and overall potential.

This application is an attempt to bridge that gap. By providing a free, structured, mobile-accessible platform that brings verified career information directly to the student's device, the project aspires to democratize access to quality career guidance regardless of geographic location.

---

## Vision

To build a comprehensive, structured, and accessible career guidance platform that empowers every student — irrespective of geography, economic background, or access to mentorship — to make informed decisions about their academic and professional future.

The platform is envisioned to grow over time into an ecosystem that connects students not only with information but also with institutes, expert consultants, and peer communities — all under a single, trusted platform.

---

## Aim & Objectives

### Primary Aim

To develop a mobile application that organizes educational and career information in a hierarchical, domain-specific structure and presents it to students in a personalized and accessible manner.

### Specific Objectives

1. To collect, structure, and maintain a comprehensive database of career paths across academic streams (Science, Commerce, Arts).
2. To provide a personalized experience by surfacing relevant career categories based on the student's self-declared educational stream.
3. To present leaf-level career nodes with associated resources including recommended books, relevant educational institutes, and applicable job sectors.
4. **[ADDED IN REVISION]** To capture institute affordability metadata such as trust-run status, scholarship availability, and related financial-support notes so students can identify economically accessible options.
5. **[ADDED IN REVISION]** To provide a profile-level preference that allows users to enable affordability-focused filtering and view only institutes or paths matching trust-based or scholarship-supported criteria.
6. To develop a backend administration panel enabling authorized data managers to add, update, and organize career information without developer intervention.
7. To integrate intelligent search capabilities in Phase 2, enabling users to discover career paths using natural language queries and semantic matching.
8. To design the application for extensibility, with clear provision for future stakeholder modules (institute self-registration, expert consulting).

---

## About the Application

CareerPath is a cross-platform mobile application built using the Flutter framework. It communicates with a RESTful backend API that serves structured career data organized in a tree-based hierarchy.

### Core Concept

Career information is organized as a navigable tree:

```
Stream (e.g., Science)
  └── Category (e.g., Engineering)
        └── Sub-Category (e.g., Computer Science)
              └── Specialization (e.g., Artificial Intelligence)
                    └── Leaf Node — Full Details
                          ├── Introduction / Description
                          ├── Recommended Books
                          ├── Relevant Institutes (with city & website)
                          └── Job Sectors
```

This structure allows students to start broad — at a stream level — and drill down progressively until they reach highly specific career paths with all supporting information in one place.

**[ADDED IN REVISION]** The tree is not limited to naming the stream alone; each stream opens into multiple meaningful categories and sub-categories. For example:
- **[ADDED IN REVISION] Science** may branch into Engineering, Medical, and Pure Sciences, with further options such as B.Tech, MBBS, Biotechnology, Data Science, or Research-oriented careers.
- **[ADDED IN REVISION] Commerce** may branch into Accounting, Finance, Business, and Economics, with options such as CA, B.Com, Economics, Banking, and Management.
- **[ADDED IN REVISION] Arts / Humanities** may branch into Social Sciences, Law, Design, Languages, and Public Services, with options such as Psychology, Sociology, Journalism, Civil Services, and related humanities careers.

**[ADDED IN REVISION]** This clarification is important because the platform helps students discover multiple categories inside each stream rather than treating each stream as a single fixed destination.

### Key Screens and Features

#### Onboarding & Profile
- On first launch, users are prompted to create a profile by entering their name and selecting their educational stream (Science, Commerce, or Arts).
- This stream selection personalizes the entire experience — the application surfaces relevant career categories immediately.
- The profile is stored locally on the device and can be edited at any time.
- **[ADDED IN REVISION]** The profile will also include an optional affordability preference that users can enable if they want the platform to prioritize institutes that are trust-run or provide scholarship support for economically weaker students.

#### Suggestions Tab
- Displays career categories relevant to the user's selected stream.
- Acts as the primary personalized feed — a curated starting point for exploring careers aligned with the student's academic background.
- **[ADDED IN REVISION]** When the affordability preference is enabled in the profile, this tab can further filter suggestions to emphasize career paths and institutes associated with trust-supported or scholarship-friendly opportunities.

#### Explore Tab
- Provides a full view of all available streams and their associated career categories.
- Users who wish to explore beyond their own stream can do so freely through this tab.
- Streams are presented as expandable accordion sections for clean navigation.
- **[ADDED IN REVISION]** Each stream section will clearly expose multiple categories within it so students can understand that Science, Commerce, and Arts each open into several distinct branches rather than one generic list.

#### Hierarchical Career Drill-Down
- Tapping any career category enters a drill-down flow where users can navigate progressively deeper into sub-categories and specializations.
- A breadcrumb trail at the top of each screen indicates the user's current position in the knowledge hierarchy.
- Users can jump to any ancestor level using the breadcrumb navigation.

#### Leaf Node Detail View
- When a user reaches the final (leaf) level of any career path, the application fetches and displays comprehensive details including an introductory description, recommended books, educational institutes, and job sectors.
- **[ADDED IN REVISION]** The same detail view will also surface affordability indicators such as trust-run institute tags, scholarship availability, and other financial-support notes where available.

#### Network Awareness
- The application gracefully handles offline scenarios, presenting meaningful error states with retry options rather than crashing.
- An HTTP response cache with a configurable TTL (30 minutes by default) reduces unnecessary network calls and ensures a smooth experience on slow connections.

### Technology Stack

| Layer | Technology |
|---|---|
| **Mobile App** | Flutter (Dart) |
| **Backend** | Python |
| **Admin Panel** | React |
| **Backend API** | RESTful API (external, managed separately) |
| **Platforms** | Android, iOS |

---

## Phased Development Plan

### Phase 1 — Semester 1 (Foundation)

This phase focuses on establishing the core data model, the student-facing mobile application, and the backend infrastructure required to serve structured career data.

---

**Deliverable 1 — Data Architecture & Backend API Design**

Define and implement the hierarchical data model (Streams → Categories → Nodes → Leaf Details) and expose it via a RESTful API. The API to serve streams, career categories, child nodes, and detailed leaf-node information including books, institutes, and job sectors.

*Scope: Data schema design, API endpoint definition, backend data seeding and validation.*

---

**Deliverable 2 — Student Profile, Personalized Suggestions & Full Explore Experience**

Implement the user profile module where students enter their name and select their academic stream (Science, Commerce, Arts). This selection personalizes the entire experience. The two core navigation tabs will be developed alongside:
- **Suggestions Tab** — surfaces career categories aligned with the user's selected stream.
- **Explore Tab** — presents all available streams and their categories in an expandable layout, allowing free exploration irrespective of stream selection.

**[ADDED IN REVISION]** The profile module will additionally support an optional affordability toggle. When enabled, the application will prioritize and filter content toward institutes identified as trust-run or offering scholarship schemes for poor or economically weaker students.

Profile data will be persisted locally on the device.

*Scope: Profile creation screen, stream selection UI, local storage, tab navigation, stream-based filtering, accordion UI for explore, pull-to-refresh.*

**[ADDED IN REVISION]** Additional scope in this deliverable includes the affordability preference toggle and trust/scholarship filter logic.

---

**Deliverable 3 — Hierarchical Career Drill-Down with Breadcrumb Navigation**

Implement the recursive navigation flow that allows users to drill from a career category progressively down to specific career paths. Each screen will display the current node's children. A breadcrumb trail will be maintained to show the user's path and allow backward navigation to any ancestor level.

*Scope: Sub-option screen, breadcrumb model & rendering, recursive API fetching, navigation stack management.*

---

**Deliverable 4 — Leaf Node Detail View with Resource Aggregation**

When a user reaches a terminal career node (a leaf), the application will fetch and display a comprehensive detail view containing: an introductory description of the career path, a curated list of recommended books (with author and reference links), relevant educational institutes (with city and website), and applicable job sectors with descriptions.

**[ADDED IN REVISION]** Where data is available, the institute section will also show whether an institute is trust-managed, whether scholarships are available, and whether the course path is comparatively affordable for students who need financial support.

*Scope: Leaf-details API integration, expandable section UI for books/institutes/job sectors, URL launching, network-aware loading states.*

**[ADDED IN REVISION]** Additional scope in this deliverable includes institute affordability metadata display.

---

### Phase 2 — Semester 2 (Intelligence & Administration)

This phase focuses on making the platform smarter, more manageable, and more scalable. It introduces intelligent search, natural language interfaces, administrative tooling, and richer data visualizations.

---

**Deliverable 5 — Backend Administration Panel**

A web-based administration panel for authorized users to manage all career data without requiring developer access. Admins will be able to create, update, and delete streams, categories, career nodes, books, institutes, and job sectors through a secure interface.

*Scope: Admin authentication and role-based access, CRUD interfaces for all data entities, data validation, audit logging.*

---

**Deliverable 6 — Neural Search & NLP Query Interface**

Integrate a semantic/neural search capability into the application. Unlike keyword-based search, neural search will understand the intent behind a student's query (e.g., "I like working with computers and want to help people") and surface the most relevant career paths by matching against vector embeddings of career descriptions.

Alongside neural search, a natural language processing layer will allow students to describe their interests, strengths, or goals in plain text and receive structured career recommendations — going beyond simple keyword matching to understand nuanced query intent.

*Scope: Vector embedding generation for career node descriptions, similarity search index, NLP query parsing, intent extraction, entity recognition for academic streams and career domains, query-to-node mapping pipeline, search API endpoint, search results UI.*

---

**Deliverable 7 — Personalized Career Recommendation Engine Enhancement**

Extend the existing stream-based personalization with a more sophisticated recommendation engine that considers user behavior (browsed paths, bookmarked nodes) and profile signals to surface progressively more relevant suggestions.

*Scope: User interaction tracking (local), recommendation scoring model, enhanced suggestions tab.*

---

**Deliverable 8 — Offline Mode & Local Data Caching**

Extend offline capabilities so that previously browsed career paths remain accessible without an internet connection. Data synchronization will occur automatically when connectivity is restored.

*Scope: Local database (SQLite or Hive), sync strategy, offline indicator UI, cache invalidation policy.*

---

**Deliverable 9 — Analytics & Usage Insights Dashboard**

Develop an analytics dashboard within the admin panel showing which career paths are most browsed, which streams see the highest engagement, geographic distribution of users, and search query trends. This data will guide future content priorities.

*Scope: Event tracking instrumentation in the app, analytics data pipeline, admin dashboard visualizations.*

---

## Future Scope

Beyond the two planned phases, the platform has significant long-term expansion potential:

---

### Institute Self-Registration & Course Upload

Educational institutes will be able to register themselves on the platform, submit their details (name, location, website, offered courses), and have their profiles reviewed and published by administrators. Once registered, institutes will be able to associate their courses with specific career nodes on the platform — giving students a direct link between a career path they are exploring and the real institutes that offer programs leading to it.

---

### Expert & Consultant Registration

Career consultants, mentors, and domain professionals will be able to register on the platform and create verified expert profiles. Each expert profile will display:
- Area of expertise (linked to specific career nodes or streams)
- Brief professional background
- LinkedIn profile link for students to connect directly

Expert profiles will surface within the relevant career node detail views, offering students a direct pathway to human guidance when they need it most.

---

### Fee Structure & Affordability Information

One of the most critical — yet commonly missing — pieces of information for students is the actual cost of pursuing a particular course. In a future iteration, the platform plans to include:
- Course fee ranges per institute
- Scholarship and financial aid information
- Integration with external data sources or direct institute-provided data for up-to-date figures
- **[ADDED IN REVISION]** Trust-run institute identification and filtering support
- **[ADDED IN REVISION]** Profile-based filtering so students can view only affordability-aligned options when required

This feature will allow students to make decisions that are not only aspirationally aligned but also financially realistic.

---

### Peer Community & Discussion Forums

A moderated peer discussion layer will allow students to ask questions, share experiences, and learn from others who are on similar academic paths. This community dimension will make the platform more engaging and create a self-reinforcing knowledge network.

---

### Integration with Scholarship & Entrance Examination Databases

Future versions may integrate data on relevant entrance examinations, eligibility criteria, and available scholarships for each career path — giving students a complete, actionable roadmap rather than just directional guidance.

---

### Regional Language Support

To serve students in remote areas more effectively, the platform plans to introduce content in regional languages, making the guidance accessible to students who are more comfortable in their native language than in English.

---

### Institutional Partnerships

Tie-ups with recognized educational boards, universities, and career guidance organizations to ensure that data on the platform is verified, regularly updated, and carries institutional credibility.

---

## Target Stakeholders

| Stakeholder | Role |
|---|---|
| **Students** | Primary users — explore career paths, access resources, receive personalized suggestions |
| **Administrators** | Manage and curate career data through the admin panel; ensure content quality |
| **Educational Institutes** | Register on the platform, upload course offerings, reach prospective students |
| **Career Consultants & Experts** | Showcase expertise, link LinkedIn profiles, guide students through the platform *(Future Scope)* |
| **Parents & Guardians** | Secondary audience who may use the platform to better understand career options *(Future Scope)* |

---

## Conclusion

CareerPath addresses a genuine and underserved need — structured, accessible, and personalized career guidance for students who lack access to conventional mentoring resources. By organizing career information in a navigable hierarchy and enriching it with books, institutes, and job sector data, the platform aims to be the most complete reference a student needs when making one of the most consequential decisions of their life.

**[ADDED IN REVISION]** The revised proposal further strengthens this vision by explicitly recognizing affordability as a first-class decision factor. By identifying trust-run institutes, scholarship-supported options, and stream-specific category branches in a clearer way, the platform becomes more practical for students who need both academic clarity and financial feasibility.

The phased approach ensures that the foundation is robust before intelligence is layered on top. Phase 1 establishes the data model, the user-facing application, and the backend infrastructure. Phase 2 transforms the platform with neural search, NLP capabilities, and administrative tooling. The future roadmap — experts, fee structures, and regional language support — positions CareerPath not merely as an app but as an evolving ecosystem.

The project represents a commitment to equity in education: ensuring that a student in a remote village has access to the same quality of career guidance as a student in a metropolitan city.

---