# Spec 46: Self-Validating QA Loop

## Priority

P0 — Critical / Table Stakes. The #1 feature gap across all surveyed competitors. Automaton's review phase (spec-06) does only 2 iterations with no failure taxonomy or targeted remediation.

## Competitive Sources

- **Auto-Claude**: QA reviewer+fixer agent pair, up to 50 iterations, separate reviewer context
- **SWE-AF**: Three nested self-healing loops (implementation, test, review) with independent escalation
- **zeroshot**: Blind validation pattern — validator has no implementation context, reducing confirmation bias

## Purpose

Add a post-build QA loop that validates code against spec acceptance criteria, classifies failures by type, creates targeted fix tasks, and retries with configurable limits. Sits between build (spec-05) and review (spec-06) as a fast inner loop catching mechanical problems before the heavier Opus-powered review.

## Requirements

### 1. QA Loop Phase Position

The QA loop runs as sub-phase 3c, after build and before review:

```
Phase 3: Build
  ├─ Sub-phase 3a: Test Scaffolding (spec-36)
  ├─ Sub-phase 3b: Implementation
  └─ Sub-phase 3c: QA Validation Loop    ← NEW
Phase 4: Review (spec-06)
```

Sub-phase 3c triggers after all tasks are `[x]` in IMPLEMENTATION_PLAN.md. It loops back into targeted fixes if failures are found. Control flows to Phase 4 only when QA passes or exhausts retries.

### 2. Validation Pass

Each QA iteration runs three checks:

1. **Test execution** — run the project test suite (command from AGENTS.md)
2. **Spec criteria check** — verify acceptance criteria are met via codebase search and associated checks
3. **Regression scan** — compare current failures against the previous QA iteration

Results are written to `.automaton/qa/iteration-N.json` with fields: `iteration`, `timestamp`, `failures[]` (each with `id`, `type`, `description`, `source`, `spec`, `first_seen`, `persistent`), `passed`, `failed`, and `verdict`.

### 3. Failure Classification

Every failure is assigned exactly one type:

| Type | Description | Fix Strategy |
|------|-------------|--------------|
| `test_failure` | A test case fails | Fix task targeting the failing function |
| `spec_gap` | Acceptance criterion not implemented | Implementation task for the missing criterion |
| `regression` | A previously passing check now fails | High-priority fix task with diff context |
| `style_issue` | Lint/formatting violations | Single batch fix task for all style issues |

The QA agent classifies via structured JSON output; the orchestrator parses `type` to route fix tasks.

### 4. Targeted Fix Task Creation

The QA loop appends fix tasks to IMPLEMENTATION_PLAN.md:

- `test_failure`: `[ ] QA-fix: [test name] — [error summary]`
- `spec_gap`: `[ ] QA-implement: [spec-NN criterion] — [description]`
- `regression`: `[ ] QA-regression: [what broke] — revert or fix [changed file]`
- `style_issue`: `[ ] QA-style: fix [N] lint/style issues`

The `QA-` prefix distinguishes these from original plan tasks and review tasks.

### 5. Retry Loop

The QA loop retries by returning to sub-phase 3b with only QA-generated fix tasks:

```
3c: validate → failures → create fix tasks → 3b: build fixes → 3c: validate again
```

Default max iterations: 5 (configurable via `execution.qa_max_iterations`). Each iteration uses Sonnet to keep costs low.

### 6. Persistence Tracking

Failures are tracked across iterations by comparing `iteration-N.json` files. A failure is `persistent: true` if its `id` appeared in the previous iteration. After 2 consecutive appearances, the fix task gains an escalation flag:

```
[ ] QA-fix (PERSISTENT): test_budget_pacing — failed 3 consecutive iterations
```

This signals the build agent to try a fundamentally different approach.

### 7. Blind Validation Option

Inspired by zeroshot, the QA agent can optionally run without implementation context — only specs and test output, no source code. This prevents confirmation bias. Controlled by `execution.qa_blind_validation` (default: false).

### 8. Escalation and Failure Report

When `qa_max_iterations` is exhausted: write `.automaton/qa/failure-report.md` listing unresolved failures with types and iteration history, commit it, and proceed to Phase 4 review with the report as context so the review agent sees exactly what QA could not fix.

### 9. Configuration

```json
{
  "execution": {
    "qa_max_iterations": 5,
    "qa_blind_validation": false,
    "qa_model": "sonnet",
    "qa_enabled": true
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `qa_max_iterations` | number | 5 | Maximum QA validation+fix cycles |
| `qa_blind_validation` | boolean | false | Run validator without implementation context |
| `qa_model` | string | "sonnet" | Model for QA pass (keep cheap) |
| `qa_enabled` | boolean | true | Enable the QA loop; false skips to review |

### 10. Budget Considerations

Each QA iteration costs ~one Sonnet invocation (100K-200K input tokens). Worst case at 5 iterations adds ~1M tokens. The orchestrator checks remaining budget (spec-07) before each iteration and skips to Phase 4 if insufficient.

## Acceptance Criteria

- [ ] QA loop runs as sub-phase 3c after build implementation completes
- [ ] Validation pass executes tests and checks spec acceptance criteria
- [ ] Failures classified into exactly one of: test_failure, spec_gap, regression, style_issue
- [ ] Fix tasks appended to IMPLEMENTATION_PLAN.md with QA- prefix
- [ ] Loop retries up to `qa_max_iterations` (default 5)
- [ ] Persistent failures tracked across iterations via `.automaton/qa/iteration-N.json`
- [ ] Failure report written to `.automaton/qa/failure-report.md` on exhaustion
- [ ] Budget check before each QA iteration prevents overspend
- [ ] Blind validation mode toggleable via config flag
- [ ] QA loop skippable via `qa_enabled: false`

## Design Considerations

All QA state lives in `.automaton/qa/` as plain JSON and markdown — cat-able plain text consistent with automaton's file-based state model. The loop is a single `run_qa_loop()` function in automaton.sh (target <100 lines) using claude CLI, jq for JSON parsing, and bash string operations. No new dependencies. The two-tier design is deliberate: cheap Sonnet QA catches mechanical failures; Opus review (Phase 4) catches semantic issues.

## Dependencies

- Depends on: spec-05 (build phase — QA loop is a sub-phase of build)
- Depends on: spec-07 (token tracking — budget check before each QA iteration)
- Depends on: spec-36 (test-first build — QA loop runs the tests scaffolded in 3a)
- Extends: spec-06 (review phase — receives QA failure report as context)
- Extends: spec-09 (error handling — QA failures are a new error category)
- Related: spec-11 (quality gates — QA loop is a programmable quality gate)
- Related: spec-29 (prompt engineering — QA prompt follows structured format)

## Files to Modify

- `automaton.sh` — add `run_qa_loop()` function, wire into build phase after sub-phase 3b
- `PROMPT_qa.md` — new file: QA validation prompt with failure classification instructions
- `automaton.config.json` — add `execution.qa_*` configuration keys
- `.automaton/qa/` — new directory: QA iteration results and failure reports
