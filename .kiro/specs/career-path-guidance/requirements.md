# Requirements Document

## Introduction

Career Path Guidance is a Flutter mobile application that helps students explore career options after 10+2 education. In Phase 1, the app operates entirely offline with no API or database dependencies. Students provide basic profile details (name, 10+2 stream), and the app presents a hierarchical career path exploration experience. All career data is loaded from local JSON files bundled with the app, and user profile data is persisted on-device using SharedPreferences.

## Glossary

- **App**: The Career Path Guidance Flutter application
- **Student**: The end user of the application, a student exploring career paths
- **Profile_Screen**: The screen where the Student enters basic details (name, stream selection)
- **Home_Screen**: The main screen with two tabs displayed after onboarding
- **Suggestions_Tab**: The first tab on the Home_Screen showing career suggestions based on the Student's selected stream
- **Explore_Tab**: The second tab on the Home_Screen allowing the Student to browse all career paths regardless of stream
- **Sub_Option_Screen**: A drill-down screen showing child career options with a breadcrumb navigation trail at the top
- **Breadcrumb_Trail**: An arrow-separated navigation path displayed at the top of the Sub_Option_Screen (e.g., Science → Maths → B.Tech)
- **Stream**: The 10+2 education stream chosen by the Student (Science, Commerce, or Art)
- **Career_Node**: A single entry in the career path hierarchy, identified by a unique ID, containing a name and optional children
- **Streams_JSON**: A JSON file defining the available streams and their top-level career categories, mapped by IDs
- **Career_Paths_JSON**: A JSON file defining the hierarchical sub-options and drill-down paths for each career category, mapped by IDs
- **Local_Storage**: On-device persistence using SharedPreferences for storing Student profile data

## Requirements

### Requirement 1: Student Profile Collection

**User Story:** As a Student, I want to enter my name and select my 10+2 stream, so that the App can personalize career suggestions for me.

#### Acceptance Criteria

1. WHEN the App is launched for the first time, THE App SHALL display the Profile_Screen.
2. THE Profile_Screen SHALL provide a text input field for the Student to enter a name.
3. THE Profile_Screen SHALL provide selectable options for the Student to choose a Stream from: Science, Commerce, and Art.
4. WHEN the Student completes the profile and taps the save button, THE App SHALL persist the name and selected Stream to Local_Storage.
5. WHEN the Student taps the skip button on the Profile_Screen, THE App SHALL navigate to the Home_Screen without saving any profile data.
6. WHEN the Student has previously saved profile data, THE App SHALL skip the Profile_Screen and navigate directly to the Home_Screen on subsequent launches.

### Requirement 2: Home Screen with Tabbed Navigation

**User Story:** As a Student, I want to see a home screen with organized tabs, so that I can access personalized suggestions and explore all career paths.

#### Acceptance Criteria

1. THE Home_Screen SHALL display two tabs: Suggestions_Tab and Explore_Tab.
2. THE Home_Screen SHALL display the Suggestions_Tab as the default selected tab.
3. WHEN the Student taps on a tab, THE Home_Screen SHALL switch to display the content of the selected tab.
4. WHILE the Student has saved profile data, THE Home_Screen SHALL display the Student's name in the app bar or header area.

### Requirement 3: Personalized Suggestions Tab

**User Story:** As a Student, I want to see career suggestions based on my selected stream, so that I can explore relevant career paths.

#### Acceptance Criteria

1. WHEN the Suggestions_Tab is displayed and the Student has a saved Stream, THE Suggestions_Tab SHALL load top-level career categories from the Streams_JSON file matching the saved Stream.
2. WHEN the Suggestions_Tab is displayed and the Student has no saved Stream (skipped profile), THE Suggestions_Tab SHALL display a prompt encouraging the Student to complete the profile with a link back to the Profile_Screen.
3. THE Suggestions_Tab SHALL display each top-level career category as a tappable card or list item showing the category name.
4. WHEN the Student taps a career category on the Suggestions_Tab, THE App SHALL navigate to the Sub_Option_Screen for that category.

### Requirement 4: Explore All Paths Tab

**User Story:** As a Student, I want to browse all available career paths regardless of my stream, so that I can discover options outside my selected stream.

#### Acceptance Criteria

1. WHEN the Explore_Tab is displayed, THE Explore_Tab SHALL load and display all available Streams from the Streams_JSON file.
2. THE Explore_Tab SHALL display each Stream as a tappable card or list item.
3. WHEN the Student taps a Stream on the Explore_Tab, THE App SHALL navigate to the Sub_Option_Screen showing the top-level career categories for that Stream.

### Requirement 5: Hierarchical Sub-Option Navigation with Breadcrumb Trail

**User Story:** As a Student, I want to drill down into career sub-options with a clear navigation trail, so that I can explore detailed career paths and know where I am in the hierarchy.

#### Acceptance Criteria

1. WHEN the Sub_Option_Screen is opened for a Career_Node, THE Sub_Option_Screen SHALL display the Breadcrumb_Trail showing the full path from the root Stream to the current Career_Node, separated by arrow symbols.
2. WHEN the Sub_Option_Screen is opened for a Career_Node that has children, THE Sub_Option_Screen SHALL load child Career_Nodes from the Career_Paths_JSON file using the parent Career_Node ID.
3. THE Sub_Option_Screen SHALL display each child Career_Node as a tappable list item.
4. WHEN the Student taps a child Career_Node that has further children, THE App SHALL navigate to a new Sub_Option_Screen for that child, appending the child name to the Breadcrumb_Trail.
5. WHEN the Student taps a child Career_Node that has no further children (leaf node), THE Sub_Option_Screen SHALL display that node as the final option without further navigation.
6. WHEN the Student taps a segment in the Breadcrumb_Trail, THE App SHALL navigate back to the Sub_Option_Screen corresponding to that segment.
7. WHEN the Student presses the device back button on the Sub_Option_Screen, THE App SHALL navigate to the previous level in the hierarchy.

### Requirement 6: Local JSON Data Loading

**User Story:** As a Student, I want the app to work completely offline, so that I can explore career paths without an internet connection.

#### Acceptance Criteria

1. THE App SHALL bundle the Streams_JSON file and the Career_Paths_JSON file as local assets.
2. WHEN the App starts, THE App SHALL load and parse the Streams_JSON file from local assets into an in-memory data structure.
3. WHEN the App starts, THE App SHALL load and parse the Career_Paths_JSON file from local assets into an in-memory data structure.
4. THE Streams_JSON file SHALL define each Stream with a unique ID, a name, and a list of top-level career category IDs.
5. THE Career_Paths_JSON file SHALL define each Career_Node with a unique ID, a name, a parent ID, and an optional list of child Career_Node IDs.
6. IF the Streams_JSON file or Career_Paths_JSON file fails to load or parse, THEN THE App SHALL display an error message to the Student indicating that career data is unavailable.

### Requirement 7: JSON Data Integrity via Round-Trip Parsing

**User Story:** As a developer, I want to ensure JSON data parsing is reliable, so that career path data is accurately represented in the app.

#### Acceptance Criteria

1. FOR ALL valid Streams_JSON content, parsing into Stream objects and then serializing back to JSON and parsing again SHALL produce equivalent Stream objects (round-trip property).
2. FOR ALL valid Career_Paths_JSON content, parsing into Career_Node objects and then serializing back to JSON and parsing again SHALL produce equivalent Career_Node objects (round-trip property).
3. THE App SHALL use a dedicated JSON parser class for Streams_JSON and a dedicated JSON parser class for Career_Paths_JSON.

### Requirement 8: Profile Data Persistence

**User Story:** As a Student, I want my profile data to be saved on my device, so that I do not have to re-enter my details every time I open the app.

#### Acceptance Criteria

1. WHEN the Student saves profile data, THE App SHALL write the name and Stream selection to Local_Storage using SharedPreferences.
2. WHEN the App launches, THE App SHALL read profile data from Local_Storage to determine whether to show the Profile_Screen or the Home_Screen.
3. WHEN the Student wants to update the profile, THE App SHALL provide an option accessible from the Home_Screen to navigate back to the Profile_Screen with pre-filled current values.
4. WHEN the Student updates and saves the profile, THE App SHALL overwrite the existing profile data in Local_Storage with the new values.
5. IF Local_Storage read fails, THEN THE App SHALL treat the Student as a first-time user and display the Profile_Screen.
