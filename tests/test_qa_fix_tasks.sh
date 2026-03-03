#!/usr/bin/env bash
# tests/test_qa_fix_tasks.sh — Tests for spec-46.3 targeted QA fix task creation
# Verifies _qa_create_fix_tasks() appends QA-prefixed tasks to
# IMPLEMENTATION_PLAN.md based on failure type with PERSISTENT escalation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_fix_tasks_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Extract functions from automaton.sh ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
PROJECT_ROOT="$TEST_PROJECT_ROOT"
HARNESS
    for fn in _qa_create_fix_tasks _qa_classify_failure; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 1: _qa_create_fix_tasks function exists ---
grep -q '^_qa_create_fix_tasks() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_create_fix_tasks function exists in automaton.sh"

# --- Test 2: Creates QA-fix task for test_failure ---
mkdir -p "$test_dir/p1/.automaton/qa"
cat > "$test_dir/p1/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"test_budget_pacing","type":"test_failure","description":"assertion error on line 42","source":"tests/test_budget.sh:42","spec":"spec-07","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p1/.automaton" TEST_PROJECT_ROOT="$test_dir/p1" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
if grep -q 'QA-fix:' "$test_dir/p1/IMPLEMENTATION_PLAN.md"; then
    assert_exit_code 0 0 "Creates QA-fix task for test_failure"
else
    assert_exit_code 0 1 "Creates QA-fix task for test_failure"
fi

# --- Test 3: Creates QA-implement task for spec_gap ---
mkdir -p "$test_dir/p2/.automaton/qa"
cat > "$test_dir/p2/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"spec-07_budget_check","type":"spec_gap","description":"Function budget_check not found","source":"specs/spec-07.md","spec":"spec-07","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p2/.automaton" TEST_PROJECT_ROOT="$test_dir/p2" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
if grep -q 'QA-implement:' "$test_dir/p2/IMPLEMENTATION_PLAN.md"; then
    assert_exit_code 0 0 "Creates QA-implement task for spec_gap"
else
    assert_exit_code 0 1 "Creates QA-implement task for spec_gap"
fi

# --- Test 4: Creates QA-regression task for regression ---
mkdir -p "$test_dir/p3/.automaton/qa"
cat > "$test_dir/p3/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"test_config_load","type":"regression","description":"previously passing test now fails","source":"tests/test_config.sh:10","spec":"spec-12","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p3/.automaton" TEST_PROJECT_ROOT="$test_dir/p3" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
if grep -q 'QA-regression:' "$test_dir/p3/IMPLEMENTATION_PLAN.md"; then
    assert_exit_code 0 0 "Creates QA-regression task for regression"
else
    assert_exit_code 0 1 "Creates QA-regression task for regression"
fi

# --- Test 5: Creates QA-style task for style_issue ---
mkdir -p "$test_dir/p4/.automaton/qa"
cat > "$test_dir/p4/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"lint_trailing_space","type":"style_issue","description":"trailing whitespace on 3 lines","source":"automaton.sh:100","spec":"","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p4/.automaton" TEST_PROJECT_ROOT="$test_dir/p4" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
if grep -q 'QA-style:' "$test_dir/p4/IMPLEMENTATION_PLAN.md"; then
    assert_exit_code 0 0 "Creates QA-style task for style_issue"
else
    assert_exit_code 0 1 "Creates QA-style task for style_issue"
fi

# --- Test 6: Adds (PERSISTENT) flag for failures seen in 2+ consecutive iterations ---
mkdir -p "$test_dir/p5/.automaton/qa"
cat > "$test_dir/p5/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"test_budget_pacing","type":"test_failure","description":"assertion error on line 42","source":"tests/test_budget.sh:42","spec":"spec-07","first_seen":1,"persistent":true}]'
TEST_AUTOMATON_DIR="$test_dir/p5/.automaton" TEST_PROJECT_ROOT="$test_dir/p5" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
if grep -q '(PERSISTENT)' "$test_dir/p5/IMPLEMENTATION_PLAN.md"; then
    assert_exit_code 0 0 "Adds (PERSISTENT) flag for persistent failures"
else
    assert_exit_code 0 1 "Adds (PERSISTENT) flag for persistent failures"
fi

# --- Test 7: All QA tasks use [ ] checkbox format ---
mkdir -p "$test_dir/p6/.automaton/qa"
cat > "$test_dir/p6/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"test_x","type":"test_failure","description":"fails","source":"test.sh","spec":"","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p6/.automaton" TEST_PROJECT_ROOT="$test_dir/p6" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
if grep -q '^\- \[ \] QA-' "$test_dir/p6/IMPLEMENTATION_PLAN.md"; then
    assert_exit_code 0 0 "QA tasks use [ ] checkbox format"
else
    assert_exit_code 0 1 "QA tasks use [ ] checkbox format"
fi

# --- Test 8: Does not duplicate existing QA tasks ---
mkdir -p "$test_dir/p7/.automaton/qa"
cat > "$test_dir/p7/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
- [ ] QA-fix: test_x — fails
PLAN
failures='[{"id":"test_x","type":"test_failure","description":"fails","source":"test.sh","spec":"","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p7/.automaton" TEST_PROJECT_ROOT="$test_dir/p7" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
count=$(grep -c 'QA-fix: test_x' "$test_dir/p7/IMPLEMENTATION_PLAN.md")
assert_equals "1" "$count" "Does not duplicate existing QA tasks"

# --- Test 9: Handles multiple failures in one call ---
mkdir -p "$test_dir/p8/.automaton/qa"
cat > "$test_dir/p8/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"test_a","type":"test_failure","description":"fails a","source":"test.sh","spec":"","first_seen":1,"persistent":false},{"id":"spec_b","type":"spec_gap","description":"missing fn","source":"spec.md","spec":"spec-01","first_seen":1,"persistent":false}]'
TEST_AUTOMATON_DIR="$test_dir/p8/.automaton" TEST_PROJECT_ROOT="$test_dir/p8" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null || true
fix_count=$(grep -c 'QA-fix:' "$test_dir/p8/IMPLEMENTATION_PLAN.md")
impl_count=$(grep -c 'QA-implement:' "$test_dir/p8/IMPLEMENTATION_PLAN.md")
total=$((fix_count + impl_count))
if [ "$total" -eq 2 ]; then
    assert_exit_code 0 0 "Handles multiple failures (2 tasks created)"
else
    assert_exit_code 0 1 "Handles multiple failures (expected 2, got $total)"
fi

# --- Test 10: Returns count of created tasks ---
mkdir -p "$test_dir/p9/.automaton/qa"
cat > "$test_dir/p9/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan

- [x] First task
PLAN
failures='[{"id":"test_z","type":"test_failure","description":"fails z","source":"test.sh","spec":"","first_seen":1,"persistent":false}]'
output=$(TEST_AUTOMATON_DIR="$test_dir/p9/.automaton" TEST_PROJECT_ROOT="$test_dir/p9" \
    bash -c "source '$test_dir/harness.sh'; _qa_create_fix_tasks '$failures'" 2>/dev/null) || true
assert_contains "$output" "1" "Returns count of created tasks"

test_summary
