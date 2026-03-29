# CareerPath Multi-Agent Development System

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    USER REQUEST                          │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│              ORCHESTRATOR (Main Claude)                   │
│                                                          │
│  ┌──────────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ Task Registry │  │ State    │  │ Permission Check  │  │
│  │ (TaskCreate)  │  │ Manager  │  │ (CLAUDE.md rules) │  │
│  └──────────────┘  └──────────┘  └───────────────────┘  │
└──┬────┬────┬────┬────┬──────────────────────────────────┘
   │    │    │    │    │
   ▼    ▼    ▼    ▼    ▼
┌────┐┌────┐┌────┐┌────┐┌────┐
│ R  ││ D  ││ Dev││ QA ││ Git│  ← Sub-agents (Agent tool)
│ E  ││ E  ││    ││    ││    │
│ Q  ││ S  ││    ││    ││    │
└────┘└────┘└────┘└────┘└────┘
```

## How It Works in Practice

This system uses Claude Code's REAL capabilities:
- **Orchestrator** = Main conversation (you, Claude)
- **Agents** = Sub-agents via `Agent` tool with specialized prompts
- **Task tracking** = `TaskCreate`/`TaskUpdate` tools
- **Background jobs** = `run_in_background` parameter
- **Shared memory** = CLAUDE.md + memory files
- **Permission gate** = settings.local.json + CLAUDE.md rules

## Execution Protocol

### For Large/Multi-Feature Tasks (MANDATORY)
```
Phase 0 — GLOBAL REQUIREMENT (once):
  1. Understand the full vision/goal
  2. Break into independent sub-tasks (each deliverable on its own)
  3. Present sub-task list to user → WAIT for approval before proceeding
  4. Create a task for each sub-task

Phase 1..N — Execute each sub-task sequentially:
  Sub-task N:
    a. Design  → architecture plan for this sub-task
    b. Dev     → implement, run analyze + test
    c. Review  → run QA checklist
    d. Git     → commit with conventional message ✅
  (repeat for each sub-task)

DO NOT start the next sub-task until the current one is committed.
Each sub-task produces its own commit — no giant monolithic commits.
```

### For Small Feature Requests
```
1. Orchestrator receives request
2. Create tasks for each phase
3. Launch Requirement Agent (sub-agent) → outputs spec
4. Launch Design Agent (sub-agent) → outputs plan
5. Present plan to user → wait for approval if >3 files
6. Launch Development Agent (sub-agent, may use worktree)
7. Launch QA Agent in parallel with development completion
8. Launch Git Agent → branch, commit, PR summary
9. Report completion with summary
```

### For Bug Fixes
```
1. Orchestrator receives bug report
2. Launch Explore agent → find root cause
3. Create fix plan (1-2 sentences)
4. Apply fix directly (no sub-agent needed for small fixes)
5. Run flutter analyze + flutter test
6. Commit with `fix: <description>`
```

### For Refactoring
```
1. Orchestrator receives refactor request
2. Launch refactor agent (see .claude/agents/refactor.md)
3. Atomic changes with test verification between each
4. Commit each refactor separately
```

## Agent Communication Protocol

Agents communicate through their return values. Format:

```
AGENT_OUTPUT = {
  status: "success" | "needs_approval" | "blocked",
  artifacts: [list of created/modified files],
  issues: [list of problems found],
  next_action: "what should happen next",
  confidence: 0-100
}
```

All decisions route through the Orchestrator (main conversation).
Agents never directly modify files that another agent is working on.

## Background Quality Gates

After ANY code change, automatically run:
1. `flutter analyze` → must have 0 errors (warnings acceptable)
2. `flutter test` → must not introduce new failures
3. If either fails → fix before proceeding

## Escalation to Human

Require explicit user approval for:
- Adding new dependencies to pubspec.yaml
- Creating new top-level directories
- Changing architecture patterns
- Modifying main.dart DI chain
- Any change affecting >5 files
- Test failures that can't be auto-resolved after 2 attempts
- Security-sensitive changes (auth, API keys, certificates)

## Current Baseline (2026-03-26)
- Analysis: 8 issues (5 info, 1 warning, 1 error in widget_test.dart)
- Tests: 51 passed, 4 failed (pre-existing)
- Files: 23 lib/, 9 test/
