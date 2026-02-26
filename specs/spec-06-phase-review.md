# Spec 06: Phase 4 - Review

## Purpose

The review phase is the quality gate that independently verifies the build output against specs. It runs the full test suite, linting, type checking, and checks spec coverage. If everything passes, the project is COMPLETE. If anything fails, it creates new tasks and sends work back to Phase 3.

## How It Runs

```bash
result=$(cat PROMPT_review.md | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model opus \
    --verbose)
```

Uses Opus for review to get the highest quality assessment. The orchestrator runs up to 2 iterations.

## Prompt Behavior (`PROMPT_review.md`)

The review prompt instructs Claude to:

### Phase 0 - Load Context
1. Read `AGENTS.md` for build/test/lint commands and project context
2. Read all `specs/*.md` to understand what was required
3. Read `IMPLEMENTATION_PLAN.md` to see what was built
4. Read `PRD.md` for the original vision

### Phase 1 - Run Validation Suite
Execute all validation commands from AGENTS.md:
1. **Tests:** Run the test command. Capture pass/fail counts.
2. **Linting:** Run the lint command. Capture error/warning counts.
3. **Type Checking:** Run the type check command (if applicable). Capture error count.
4. **Build:** Run the build command (if applicable). Confirm it succeeds.

### Phase 2 - Spec Coverage Analysis
For each spec file:
1. Read the spec's requirements and acceptance criteria
2. Search the codebase for corresponding implementation
3. Verify each acceptance criterion is met
4. Rate coverage: fully covered, partially covered, not covered

### Phase 3 - Code Quality Review
Scan for common issues:
- Orphaned code (files not referenced anywhere)
- Missing error handling on external calls
- Hardcoded values that should be configurable
- Missing test coverage for critical paths
- Security issues (exposed secrets, injection vectors)

### Phase 4 - Verdict

**If all checks pass:**
- Confirm full spec coverage
- Output `<promise>COMPLETE</promise>`

**If checks fail:**
- Create new `[ ]` tasks in `IMPLEMENTATION_PLAN.md` for each failure:
  - `[ ] Fix: [test name] failing - [error description]`
  - `[ ] Fix: lint error in [file] - [description]`
  - `[ ] Missing: [spec requirement] not implemented`
- Do NOT output COMPLETE
- The orchestrator will detect no COMPLETE signal and return to Phase 3

### Rules
1. Be thorough but fair. Minor style issues are warnings, not failures.
2. Every new task must be specific and actionable.
3. Do NOT fix code yourself. Create tasks for the builder.
4. Do NOT rewrite the implementation plan. Only append new tasks.
5. Focus on correctness and spec compliance, not style preferences.

## Iteration Limits

| Setting | Default | Config Key |
|---------|---------|-----------|
| Max iterations | 2 | execution.max_iterations.review |
| Per-iteration token limit | 500K | budget.per_iteration |
| Phase token budget | 1.5M | budget.per_phase.review |

## Quality Gate (Gate 5) Checks

The orchestrator verifies after review:

| Check | Method | On Fail |
|-------|--------|---------|
| Review agent signaled COMPLETE | grep for `COMPLETE</promise>` | Return to BUILD |
| No new `[ ]` tasks added | `grep -c '\[ \]'` == 0 | Return to BUILD |
| Test suite passes | (review agent ran it) | Return to BUILD |

## Review -> Build Loop

If review fails:
1. Review agent has already written new `[ ]` tasks in IMPLEMENTATION_PLAN.md
2. Orchestrator detects no COMPLETE signal
3. Orchestrator transitions back to Phase 3 (build)
4. Build phase picks up the new tasks
5. After build completes again, orchestrator transitions to Phase 4 (review) again
6. Maximum 2 review iterations. If still failing after 2nd review, escalate.

## Skipping Review

If `--skip-review` flag is passed or `flags.skip_review` is true in config, the orchestrator marks COMPLETE after Phase 3's Gate 4 passes. Useful for projects where the human will review manually.
