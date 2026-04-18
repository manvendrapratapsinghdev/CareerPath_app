# CareerPath Multi-Agent Development Pipeline

## System Architecture — 7 Agents with Strict Gating

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER REQUEST                                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│                 TEAM LEAD / ORCHESTRATOR                              │
│                   (Main Claude Context)                               │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐  │
│  │ Task Registry │  │ Pipeline     │  │ Permission Gate           │  │
│  │ (TaskCreate)  │  │ State        │  │ (CLAUDE.md rules)         │  │
│  └──────────────┘  └──────────────┘  └───────────────────────────┘  │
└──┬─────┬─────┬─────┬─────┬─────┬─────┬─────────────────────────────┘
   │     │     │     │     │     │     │
   ▼     ▼     ▼     ▼     ▼     ▼     ▼
┌─────┐┌─────┐┌─────┐┌──────┐┌────┐┌────┐┌──────┐
│ REQ ││BREAK││ DEV ││REVIEW││ QA ││ GIT││ LEAD │
│     ││DOWN ││     ││      ││    ││    ││      │
└─────┘└─────┘└─────┘└──────┘└────┘└────┘└──────┘
```

```
┌────────────────────────┬─────────────────────────────┬────────────────────────────────────────────────────────────┐
│         Agent          │            Role             │                           Output                           │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ RequirementAgent       │ Raw input → structured spec │ Functional reqs, edge cases, acceptance criteria           │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ TaskBreakdownAgent     │ Spec → atomic tasks         │ Ordered task list with deps, files, complexity             │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ DeveloperAgent         │ Writes/revises code         │ Implementation files (handles review/QA feedback)          │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ ReviewAgent            │ Code quality check          │ PASS or NEEDS_REVISION → loops to Developer                │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ QAAgent                │ Tests + validation          │ PASS or FAIL with bug report → loops to Developer          │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ CommitAgent            │ Gated commit                │ Only when review=PASS AND qa=PASS                          │
├────────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────┤
│ TeamLead (Orchestrator)│ Orchestrates all            │ Retry loops, dependency gating, state tracking             │
└────────────────────────┴─────────────────────────────┴────────────────────────────────────────────────────────────┘
```

## Pipeline Execution Protocol

### Phase 0: Requirement Understanding
```
Input:  Raw user request
Agent:  RequirementAgent (.claude/agents/requirement.md)
Output: REQUIREMENT_SPEC with acceptance criteria
Gate:   status == "success" (if "needs_clarification" → ask user)
```

### Phase 1: Task Breakdown
```
Input:  REQUIREMENT_SPEC
Agent:  TaskBreakdownAgent (.claude/agents/task_breakdown.md)
Output: TASK_BREAKDOWN with ordered task list
Gate:   status == "success"
Action: Create TaskCreate entries for each task
        Present task list to user → WAIT for approval if >3 tasks
```

### Phase 2: Task Execution Loop (repeat for each task)
```
For TASK in EXECUTION_ORDER:
  
  ┌─── 2a. DEVELOP ──────────────────────────────────────┐
  │ Agent:  DeveloperAgent (.claude/agents/feature.md)    │
  │ Input:  Task spec + any revision feedback             │
  │ Output: Created/modified files                        │
  └───────────────────────┬───────────────────────────────┘
                          │
  ┌─── 2b. REVIEW (loop) ┴───────────────────────────────┐
  │ Agent:  ReviewAgent (.claude/agents/review.md)        │
  │ Input:  Files from Developer                          │
  │ Output: PASS or NEEDS_REVISION                        │
  │                                                       │
  │ If NEEDS_REVISION:                                    │
  │   → Send feedback to DeveloperAgent                   │
  │   → Developer revises                                 │
  │   → Re-review                                         │
  │   → Max 3 iterations, then escalate to user           │
  └───────────────────────┬───────────────────────────────┘
                          │ (only on PASS)
  ┌─── 2c. QA (loop) ────┴───────────────────────────────┐
  │ Agent:  QAAgent (.claude/agents/qa.md)                │
  │ Input:  Files + acceptance criteria                   │
  │ Output: PASS or FAIL with bug report                  │
  │                                                       │
  │ If FAIL:                                              │
  │   → Send bug report to DeveloperAgent                 │
  │   → Developer fixes                                   │
  │   → Re-run QA (full cycle)                            │
  │   → Max 3 iterations, then escalate to user           │
  └───────────────────────┬───────────────────────────────┘
                          │ (only on PASS)
  ┌─── 2d. COMMIT ───────┴───────────────────────────────┐
  │ Agent:  CommitAgent (.claude/agents/commit.md)        │
  │ Input:  Task + gate statuses                          │
  │ Gate:   review=PASS AND qa=PASS                       │
  │ Output: Git commit                                    │
  │ Action: Mark task COMPLETED                           │
  └───────────────────────────────────────────────────────┘
```

### Phase 3: Completion
```
All tasks COMPLETED → Report summary to user
Include: files created/modified, commits made, test results
```

## Pipeline State

The orchestrator tracks this state throughout execution:

```json
{
  "feature": "<feature name>",
  "phase": "requirements | breakdown | execution | complete",
  "tasks": [
    {
      "id": "TASK-1",
      "title": "<title>",
      "status": "pending | in_progress | completed | blocked",
      "dev_iterations": 0,
      "review_status": "pending | pass | needs_revision",
      "review_iterations": 0,
      "qa_status": "pending | pass | fail",
      "qa_iterations": 0,
      "commit_hash": null
    }
  ],
  "current_task": "TASK-1",
  "history": [
    {"timestamp": "<time>", "event": "<what happened>"}
  ]
}
```

## Control Logic

### Strict Gating Rules
1. **No task starts until previous task is COMMITTED**
2. **Review cannot start until Dev is complete**
3. **QA cannot start until Review = PASS**
4. **Commit cannot happen until Review = PASS AND QA = PASS**
5. **If Review or QA fails 3 times → escalate to user**

### Retry Protocol
```
REVIEW LOOP:
  attempt = 1
  while review != PASS and attempt <= 3:
    if attempt > 1:
      DeveloperAgent.revise(review_feedback)
    ReviewAgent.review(files)
    attempt++
  if review != PASS:
    ESCALATE("Review failed after 3 attempts", feedback)

QA LOOP:
  attempt = 1
  while qa != PASS and attempt <= 3:
    if attempt > 1:
      DeveloperAgent.fix(bug_report)
    QAAgent.validate(files, acceptance_criteria)
    attempt++
  if qa != PASS:
    ESCALATE("QA failed after 3 attempts", bug_report)
```

### Escalation to User
Require user approval for:
- Adding new dependencies to pubspec.yaml
- Creating new top-level directories
- Changing architecture patterns
- Modifying main.dart DI chain
- Any change affecting >5 files
- Review/QA failure after 3 retry loops
- Security-sensitive changes

## Agent Prompt Templates

Each agent is invoked as a Claude Code sub-agent with:
```
Agent(
  subagent_type: "general-purpose",
  prompt: "<agent prompt from .claude/agents/{agent}.md> + <task-specific context>",
  description: "<AgentName>: <task title>"
)
```

Agent files:
- `.claude/agents/requirement.md` — RequirementAgent
- `.claude/agents/task_breakdown.md` — TaskBreakdownAgent
- `.claude/agents/feature.md` — DeveloperAgent
- `.claude/agents/review.md` — ReviewAgent (Code Review)
- `.claude/agents/qa.md` — QAAgent
- `.claude/agents/commit.md` — CommitAgent
- `.claude/agents/system.md` — This file (Orchestrator reference)
- `.claude/agents/refactor.md` — RefactorAgent (standalone)

## Quality Baseline
- Analysis: Run `flutter analyze` — track error/warning count
- Tests: Run `flutter test` — track pass/fail count
- Baseline is established at pipeline start and verified at each commit
