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

## Multi-Agent Development Pipeline

Full pipeline definition: `.claude/agents/system.md`

### 7 Agents with Strict Gating + Retry Loops

| Agent | Prompt File | Role |
|-------|-------------|------|
| RequirementAgent | `.claude/agents/requirement.md` | Raw input → structured spec |
| TaskBreakdownAgent | `.claude/agents/task_breakdown.md` | Spec → atomic tasks |
| DeveloperAgent | `.claude/agents/feature.md` | Writes/revises code |
| ReviewAgent | `.claude/agents/review.md` | Code quality check (loop until PASS) |
| QAAgent | `.claude/agents/qa.md` | Tests + validation (loop until PASS) |
| CommitAgent | `.claude/agents/commit.md` | Gated commit (review=PASS AND qa=PASS) |
| TeamLead | Orchestrator (main context) | Retry loops, gating, state tracking |

### Execution Flow

```
User Request
  → RequirementAgent → structured spec
  → TaskBreakdownAgent → ordered task list
  → For each task:
      → DeveloperAgent → code
      → ReviewAgent → loop until PASS (max 3)
      → QAAgent → loop until PASS (max 3)
      → CommitAgent → commit ✅
  → Next task (only after previous committed)
  → All done → summary report
```

### Control Rules
1. **No task starts until previous task is COMMITTED**
2. **Review must PASS before QA runs**
3. **QA must PASS before Commit runs**
4. **3 retry failures → escalate to user**
5. **Each task gets its own commit — no monolithic commits**

### Git Phase
- Branch naming: `feature/<name>`, `fix/<name>`, `refactor/<name>`
- Commit messages: conventional commits (feat:, fix:, refactor:, test:, chore:)
- One logical change per commit
- PR summary with changes list and test plan
