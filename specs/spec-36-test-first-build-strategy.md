# Spec 36: Test-First Build Strategy

## Purpose

Claude Code best practices recommend writing tests first as a structured format in multi-context-window workflows. The current build phase implements tasks end-to-end with no test-first discipline. For a self-building orchestrator that modifies its own code, tests are the only reliable way to verify behavior without human review. This spec defines a test scaffold sub-phase, test annotations in the plan, and test-driven review.

## Requirements

### 1. Test Scaffold Sub-Phase

The build phase gains a test scaffold sub-phase that runs before implementation iterations:

```
Phase 3: Build
  ├─ Sub-phase 3a: Test Scaffolding (iterations 1-3)
  │    ├─ Write test files for planned tasks
  │    ├─ Tests should FAIL initially (no implementation yet)
  │    ├─ Commit test files
  │    └─ Gate: test files exist for all annotated tasks
  ├─ Sub-phase 3b: Implementation (iterations 4+)
  │    ├─ Implement tasks with test-first discipline
  │    ├─ Each task: write test → implement → verify test passes → commit
  │    └─ Loop until all tasks complete
  └─ Gate 4: Build Completion
```

Sub-phase 3a produces test files only — no implementation code. Sub-phase 3b implements against the existing tests. The transition from 3a to 3b is controlled by the orchestrator:

- Default: 1-3 iterations for test scaffolding (configurable via `execution.test_scaffold_iterations`)
- Transition when: test scaffold gate passes (test files exist for annotated tasks)
- If scaffold gate fails after max iterations: proceed to 3b anyway (tests are not a hard requirement)

### 2. Plan Phase Test Annotations

The plan phase (spec-04) annotates tasks with expected test files:

```markdown
## Implementation Plan

- [ ] Add budget pacing logic <!-- test: tests/test_budget_pacing.sh -->
- [ ] Implement daily budget calculation <!-- test: tests/test_daily_budget.sh -->
- [ ] Add --budget-check CLI flag <!-- test: tests/test_cli_budget_check.sh -->
- [ ] Update rate limit presets <!-- test: tests/test_rate_presets.sh -->
- [ ] Refactor config loading (no test needed) <!-- test: none -->
```

The `<!-- test: path -->` annotation tells the test scaffold sub-phase which test file to create for each task. Tasks annotated with `<!-- test: none -->` are exempt from test-first (pure refactoring, documentation, etc.).

The plan prompt (spec-29 format) must include:
```xml
<rules>
Annotate each task with its expected test file using the format:
<!-- test: tests/test_[feature].sh -->
If a task does not need a test (pure refactoring, docs), annotate with:
<!-- test: none -->
</rules>
```

### 3. Build Prompt Test-First Rule

The build prompt gains a test-first rule in its `<rules>` section:

```xml
<rules>
## Test-First Discipline
For each task:
1. Check if a test file exists (from test annotations in the plan)
2. If no test exists: write the test first, commit it, then implement
3. If test exists: read the test to understand expected behavior
4. Implement the feature
5. Run the test — it must pass
6. Commit implementation with test results

Do NOT modify existing tests to make them pass — fix the implementation instead.
If a test is wrong (tests an incorrect assumption), note this and create a fix-test task.
</rules>
```

### 4. Bash Test Framework for automaton.sh

For self-build mode, define a bash test framework. The preferred framework is `bats` (Bash Automated Testing System). If bats is not available, use a minimal assertion library:

```bash
# tests/test_helpers.sh — minimal assertion functions
assert_equals() {
    local expected="$1" actual="$2" msg="${3:-assertion failed}"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $msg (expected '$expected', got '$actual')" >&2
        return 1
    fi
    echo "PASS: $msg"
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="${3:-exit code check}"
    if [ "$expected" -ne "$actual" ]; then
        echo "FAIL: $msg (expected exit $expected, got $actual)" >&2
        return 1
    fi
    echo "PASS: $msg"
}

assert_file_exists() {
    local path="$1" msg="${2:-file exists check}"
    if [ ! -f "$path" ]; then
        echo "FAIL: $msg ($path does not exist)" >&2
        return 1
    fi
    echo "PASS: $msg"
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-contains check}"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "FAIL: $msg (output does not contain '$needle')" >&2
        return 1
    fi
    echo "PASS: $msg"
}
```

Test files for automaton follow this structure:

```bash
#!/usr/bin/env bash
# tests/test_budget_pacing.sh
source "$(dirname "$0")/test_helpers.sh"

# Setup
export TEST_MODE=1
source automaton.sh  # Source functions without executing main

# Test: daily budget calculation
test_daily_budget_basic() {
    local result=$(calculate_daily_budget 45000000 12000000 3)
    assert_equals "11000000" "$result" "daily budget with 3 days remaining"
}

# Test: daily budget minimum 1 day
test_daily_budget_last_day() {
    local result=$(calculate_daily_budget 45000000 40000000 0)
    assert_equals "5000000" "$result" "daily budget on reset day"
}

# Run tests
test_daily_budget_basic
test_daily_budget_last_day
```

### 5. Test-Driven Review

The review agent uses test results as primary verification evidence. The review prompt (spec-29 format) gains:

```xml
<instructions>
## Verification Priority
1. Run all tests — test results are the primary quality signal
2. Check test coverage: are there tests for each completed task?
3. Review test quality: do tests verify behavior, not just pass trivially?
4. Only after tests pass: review code for correctness and style
5. If tests fail: create fix tasks, do NOT pass the review gate
</instructions>
```

Test results from spec-31's `PostToolUse` hook (`.automaton/test_results.json`) provide structured data for the review agent.

### 6. Test Coverage Metric

Track test coverage as a metric in run metadata:

```json
{
  "test_coverage": {
    "tasks_with_tests": 8,
    "tasks_without_tests": 2,
    "tasks_exempt": 3,
    "coverage_ratio": 0.80,
    "tests_passing": 7,
    "tests_failing": 1
  }
}
```

Append to `.automaton/run-summaries/` (spec-34) at run completion.

Coverage ratio = `tasks_with_tests / (tasks_with_tests + tasks_without_tests)`

Log a summary after the test scaffold sub-phase:
```
[ORCHESTRATOR] Test scaffold complete: 8/10 tasks have tests (2 exempt). Proceeding to implementation.
```

### 7. Configuration

```json
{
  "execution": {
    "test_scaffold_iterations": 2,
    "test_first_enabled": true,
    "test_framework": "bats"
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `test_scaffold_iterations` | number | 2 | Max iterations for test scaffold sub-phase |
| `test_first_enabled` | boolean | true | Enable test-first build strategy |
| `test_framework` | string | "bats" | Bash test framework ("bats" or "assertions") |

When `test_first_enabled` is `false`, the build phase skips sub-phase 3a and runs implementation directly (v1 behavior).

### 8. Test File Organization

```
tests/
  test_helpers.sh          ← assertion functions (always created)
  test_budget_pacing.sh    ← per-feature test files
  test_daily_budget.sh
  test_cli_budget_check.sh
  test_rate_presets.sh
  skills/                  ← skill tests (spec-32)
    test-spec-reader.sh
    test-validation-suite.sh
```

Test files follow the naming convention `test_[feature].sh` matching the plan annotations.

## Acceptance Criteria

- [ ] Build phase has test scaffold sub-phase (3a) before implementation (3b)
- [ ] Plan phase annotates tasks with `<!-- test: path -->` markers
- [ ] Build prompt includes test-first discipline rules
- [ ] `tests/test_helpers.sh` provides minimal bash assertion functions
- [ ] Review agent prioritizes test results over code review
- [ ] Test coverage metric tracked in run summaries
- [ ] `execution.test_first_enabled` config flag controls the feature
- [ ] Test scaffold sub-phase configurable via `execution.test_scaffold_iterations`

## Dependencies

- Depends on: spec-29 (prompt format for test-first rules in `<rules>` section)
- Extends: spec-05 (build phase gains test scaffold sub-phase)
- Extends: spec-04 (plan phase gains test annotations)
- Extends: spec-06 (review phase uses test-driven verification)
- Extends: spec-26 (test coverage metric in run summaries)
- Uses: spec-31 (test result capture via PostToolUse hook)
- Uses: spec-34 (run summaries for coverage metric storage)

## Files to Modify

- `automaton.sh` — add test scaffold sub-phase to build loop, test coverage tracking
- `PROMPT_plan.md` — add test annotation rules
- `PROMPT_build.md` — add test-first discipline rules
- `PROMPT_review.md` — add test-driven verification priority
- `automaton.config.json` — add `execution.test_scaffold_iterations`, `test_first_enabled`, `test_framework`
- `tests/test_helpers.sh` — new file: bash assertion functions
