# Implementation Plan: Career Path Guidance

## Overview

Build a Flutter mobile app that helps 10+2 students explore career paths offline. Implementation follows a bottom-up approach: data models and parsers first, then services, then UI screens. All data comes from local JSON assets, profile persistence uses SharedPreferences, and navigation uses Flutter's Navigator stack with breadcrumb state passed as route arguments.

## Tasks

- [x] 1. Create data models and JSON asset files
  - [x] 1.1 Create `StreamModel`, `CareerNode`, `ProfileData`, and `BreadcrumbEntry` data model classes
    - Create `lib/models/stream_model.dart` with `StreamModel` class including `id`, `name`, `categoryIds` fields, `fromJson` factory, and `toJson` method
    - Create `lib/models/career_node.dart` with `CareerNode` class including `id`, `name`, `parentId`, `childIds` fields, `isLeaf` getter, `fromJson` factory, and `toJson` method
    - Create `lib/models/profile_data.dart` with `ProfileData` class including `name` and `stream` fields
    - Create `lib/models/breadcrumb_entry.dart` with `BreadcrumbEntry` class including `nodeId` and `label` fields
    - _Requirements: 6.4, 6.5, 8.1_

  - [x] 1.2 Create local JSON asset files
    - Create `assets/data/streams.json` with stream definitions for Science, Commerce, and Art, each with unique IDs and top-level category ID references
    - Create `assets/data/career_paths.json` with hierarchical career node definitions including IDs, names, parent IDs, and child IDs
    - Register both files in `pubspec.yaml` under `flutter > assets`
    - _Requirements: 6.1, 6.4, 6.5_

- [x] 2. Implement JSON parsers (Data Layer)
  - [x] 2.1 Implement `StreamsJsonParser`
    - Create `lib/data/streams_json_parser.dart`
    - Implement `parse(String jsonString)` returning `List<StreamModel>`
    - Implement `serialize(List<StreamModel> streams)` returning JSON string
    - Implement `loadFromAssets()` that reads `assets/data/streams.json` via `rootBundle` and calls `parse`
    - _Requirements: 6.2, 6.4, 7.3_

  - [ ]* 2.2 Write property test for `StreamsJsonParser` round-trip consistency
    - **Property 1: Streams round-trip parsing**
    - For all valid streams JSON content, parsing into `StreamModel` objects and serializing back to JSON and parsing again produces equivalent `StreamModel` objects
    - **Validates: Requirements 7.1**

  - [x] 2.3 Implement `CareerPathsJsonParser`
    - Create `lib/data/career_paths_json_parser.dart`
    - Implement `parse(String jsonString)` returning `Map<String, CareerNode>`
    - Implement `serialize(Map<String, CareerNode> nodes)` returning JSON string
    - Implement `loadFromAssets()` that reads `assets/data/career_paths.json` via `rootBundle` and calls `parse`
    - _Requirements: 6.3, 6.5, 7.3_

  - [ ]* 2.4 Write property test for `CareerPathsJsonParser` round-trip consistency
    - **Property 2: Career nodes round-trip parsing**
    - For all valid career paths JSON content, parsing into `CareerNode` objects and serializing back to JSON and parsing again produces equivalent `CareerNode` objects
    - **Validates: Requirements 7.2**

- [x] 3. Implement profile persistence (Data Layer)
  - [x] 3.1 Implement `ProfileRepository`
    - Create `lib/data/profile_repository.dart`
    - Implement `saveProfile(String name, String stream)` writing to SharedPreferences using keys `profile_name` and `profile_stream`
    - Implement `loadProfile()` returning `ProfileData?` (null if no profile saved)
    - Implement `hasProfile()` returning `bool`
    - Handle SharedPreferences read failures gracefully by returning null/false
    - Add `shared_preferences` package to `pubspec.yaml` dependencies
    - _Requirements: 8.1, 8.2, 8.5_

  - [ ]* 3.2 Write unit tests for `ProfileRepository`
    - Test saving and loading profile data round-trip
    - Test `hasProfile` returns false when no data saved
    - Test `loadProfile` returns null when SharedPreferences is empty or fails
    - _Requirements: 8.1, 8.2, 8.5_

- [x] 4. Checkpoint - Ensure data layer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement domain services
  - [x] 5.1 Implement `ProfileService`
    - Create `lib/services/profile_service.dart`
    - Accept `ProfileRepository` as a constructor dependency
    - Implement `saveProfile(String name, String stream)` delegating to repository and returning success/failure
    - Implement `getProfile()` returning `ProfileData?`
    - Implement `isProfileComplete()` returning `bool`
    - _Requirements: 1.4, 1.6, 8.1, 8.2_

  - [x] 5.2 Implement `CareerDataService`
    - Create `lib/services/career_data_service.dart`
    - Accept `StreamsJsonParser` and `CareerPathsJsonParser` as constructor dependencies
    - Implement `initialize()` that loads both JSON files into memory; store parsed data in private fields
    - Implement `getAllStreams()` returning `List<StreamModel>`
    - Implement `getCategoriesForStream(String streamId)` returning `List<CareerNode>` for the stream's category IDs
    - Implement `getChildrenOf(String nodeId)` returning `List<CareerNode>` for a parent node's child IDs
    - Implement `getNodeById(String nodeId)` returning `CareerNode?`
    - Handle load/parse failures by throwing or returning empty data with error state
    - _Requirements: 3.1, 4.1, 5.2, 6.2, 6.3, 6.6_

  - [ ]* 5.3 Write unit tests for `CareerDataService`
    - Test `getCategoriesForStream` returns correct nodes for a given stream
    - Test `getChildrenOf` returns correct child nodes
    - Test `getNodeById` returns null for unknown IDs
    - Test `getAllStreams` returns all parsed streams
    - _Requirements: 3.1, 4.1, 5.2_

- [x] 6. Checkpoint - Ensure domain layer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement ProfileScreen (UI Layer)
  - [x] 7.1 Create `ProfileScreen` widget
    - Create `lib/screens/profile_screen.dart`
    - Add a `TextFormField` for name input
    - Add stream selector (radio buttons or segmented control) for Science, Commerce, Art
    - Add a Save button that calls `ProfileService.saveProfile` and navigates to `HomeScreen`
    - Add a Skip button that navigates to `HomeScreen` without saving
    - When opened for editing, pre-fill name and stream from existing `ProfileData`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 8.3, 8.4_

- [ ] 8. Implement HomeScreen with tabs (UI Layer)
  - [x] 8.1 Create `HomeScreen` widget with `TabBar`
    - Create `lib/screens/home_screen.dart`
    - Add a `TabBar` with two tabs: Suggestions and Explore
    - Set Suggestions tab as the default selected tab
    - Display the student's name in the app bar if profile data exists (via `ProfileService`)
    - Add an edit/settings icon in the app bar that navigates to `ProfileScreen` with pre-filled values
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 8.3_

  - [-] 8.2 Implement `SuggestionsTab`
    - Create `lib/screens/suggestions_tab.dart`
    - If student has a saved stream: load top-level career categories from `CareerDataService.getCategoriesForStream` and display as tappable cards
    - If student has no saved stream (skipped profile): display a prompt with a link to `ProfileScreen`
    - On card tap: navigate to `SubOptionScreen` passing the category node ID and initial breadcrumb
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ] 8.3 Implement `ExploreTab`
    - Create `lib/screens/explore_tab.dart`
    - Load all streams from `CareerDataService.getAllStreams` and display as tappable cards
    - On stream card tap: navigate to `SubOptionScreen` showing top-level categories for that stream
    - _Requirements: 4.1, 4.2, 4.3_

- [ ] 9. Implement SubOptionScreen with breadcrumb navigation (UI Layer)
  - [ ] 9.1 Create `SubOptionScreen` widget
    - Create `lib/screens/sub_option_screen.dart`
    - Accept breadcrumb path (`List<BreadcrumbEntry>`) and current node ID as route arguments
    - Display `BreadcrumbTrail` widget at the top showing arrow-separated path segments
    - Load child career nodes from `CareerDataService.getChildrenOf` and display as tappable list items
    - For leaf nodes (no children): display as final option without navigation affordance
    - On child node tap (non-leaf): push a new `SubOptionScreen` route with updated breadcrumb
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ] 9.2 Implement breadcrumb tap navigation and back button handling
    - Make each breadcrumb segment tappable; on tap, pop routes back to the corresponding `SubOptionScreen`
    - Handle device back button to navigate to the previous hierarchy level (default Navigator pop behavior)
    - _Requirements: 5.6, 5.7_

- [ ] 10. Wire app entry point and navigation flow
  - [ ] 10.1 Set up `main.dart` and app initialization
    - Create or update `lib/main.dart`
    - Initialize `SharedPreferences`, `ProfileRepository`, `ProfileService`
    - Initialize `StreamsJsonParser`, `CareerPathsJsonParser`, `CareerDataService` and call `initialize()`
    - Handle initialization errors by showing an error message screen
    - _Requirements: 6.2, 6.3, 6.6_

  - [ ] 10.2 Implement startup routing logic
    - On app launch, check `ProfileService.isProfileComplete()`
    - If profile exists: navigate to `HomeScreen`
    - If no profile: navigate to `ProfileScreen`
    - Wire all screen navigation routes together
    - _Requirements: 1.1, 1.6, 8.2, 8.5_

- [ ] 11. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests (2.2, 2.4) validate JSON round-trip correctness per Requirement 7
- Implementation follows bottom-up order: data models → parsers → repository → services → UI → wiring
- All data is local/offline — no network code needed in Phase 1
