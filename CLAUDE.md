# CareerPath Flutter App — Development System

## Project Profile

- **Architecture**: Layered service-based (screens → services → data → models)
- **State Management**: Vanilla StatefulWidget + setState()
- **Routing**: Basic Navigator.push() with MaterialPageRoute
- **DI Pattern**: Manual constructor injection from main.dart
- **API Pattern**: Custom ApiClient with 30-min in-memory cache, ngrok backend
- **Testing**: flutter_test, 9 test files covering data/services/screens
- **Linting**: flutter_lints standard rules
- **CI/CD**: None configured
- **Dart files**: 23 in lib/, 9 in test/

## Code Conventions

- Models in `lib/models/` — plain Dart classes with fromJson/toJson
- Services in `lib/services/` — business logic, injected via constructor
- Data layer in `lib/data/` — repositories and JSON parsers
- Screens in `lib/screens/` — StatefulWidget with service dependencies
- API URLs centralized in `lib/config/api_urls.dart`
- Tests mirror lib/ structure under `test/`

## Development Rules

1. **Never introduce new state management** (no Bloc/Riverpod/Provider) without explicit approval
2. **Maintain manual DI pattern** — instantiate in main.dart, pass via constructors
3. **All new services must have corresponding tests** in test/services/
4. **All new models must have fromJson/toJson** and parser tests
5. **Follow existing naming**: snake_case files, PascalCase classes, camelCase methods
6. **API endpoints go in ApiUrls class** — never hardcode URLs in services
7. **Run `flutter analyze` before committing** — zero warnings policy
8. **Run `flutter test` before committing** — all tests must pass

## Agent Workflows

### Large Tasks (multi-feature, broad requests)

1. **GLOBAL REQUIREMENT** (once) → understand full vision → break into sub-tasks → present to user → WAIT for approval
2. **Sub-task 1**: Design → Dev → Review → Git ✅
3. **Sub-task 2**: Design → Dev → Review → Git ✅
4. **Sub-task N**: Design → Dev → Review → Git ✅

Each sub-task gets its own commit. Never start the next until the current one is committed.

### Small Tasks (single feature/fix)

When asked to implement a feature, follow this sequence:

### 1. Requirements Phase
- Clarify ambiguous requirements before writing code
- Define acceptance criteria as testable assertions
- Identify which existing files will be modified vs new files needed

### 2. Design Phase
- Determine which layer(s) are affected (model/data/service/screen/widget)
- Plan API endpoint additions (if any) in ApiUrls
- Plan navigation changes (if any)
- Ensure design follows existing patterns

### 3. Implementation Phase
- Models first → Data layer → Services → Screens (bottom-up)
- Generate tests alongside implementation
- Run `flutter analyze` after each file change
- Run `flutter test` after implementation complete

### 4. Review Phase
- Check for large widgets (>200 lines) — extract sub-widgets
- Check for deep nesting (>5 levels) — flatten
- Check for missing error handling on API calls
- Check for missing null safety
- Verify test coverage for new code

### 5. Git Phase
- Branch naming: `feature/<name>`, `fix/<name>`, `refactor/<name>`
- Commit messages: conventional commits (feat:, fix:, refactor:, test:, chore:)
- One logical change per commit
- PR summary with changes list and test plan
