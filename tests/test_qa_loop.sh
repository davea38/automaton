#!/usr/bin/env bash
# tests/test_qa_loop.sh — Tests for spec-46.3 QA retry loop
# Verifies _qa_run_loop() orchestrates validate → fix → build → validate
# cycle up to qa_max_iterations with budget checking.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_loop_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: _qa_run_loop function exists ---
grep -q '^_qa_run_loop() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_run_loop function exists in automaton.sh"

# --- Test 2: _qa_run_loop is called when QA_ENABLED is true ---
# Verify the function is referenced in the build→review transition
grep -q '_qa_run_loop' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_run_loop is referenced in automaton.sh"

# --- Extract functions for unit tests ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
PROJECT_ROOT="$TEST_PROJECT_ROOT"
QA_ENABLED="true"
QA_MAX_ITERATIONS=5
QA_MODEL="sonnet"
QA_BLIND_VALIDATION="false"
# Stub run_agent and budget functions
run_agent() { AGENT_RESULT=""; AGENT_EXIT_CODE=0; }
check_budget() { return 0; }
BUDGET_PER_ITERATION=100000
BUDGET_MODE="fixed"
HARNESS
    for fn in _qa_run_loop _qa_validate _qa_run_tests _qa_check_spec_criteria \
              _qa_scan_regressions _qa_classify_failure _qa_write_iteration \
              _qa_mark_persistent _qa_create_fix_tasks; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 3: _qa_run_loop returns PASS immediately when no failures ---
mkdir -p "$test_dir/pass_project/.automaton/qa"
cat > "$test_dir/pass_project/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
PLAN
output=$(TEST_AUTOMATON_DIR="$test_dir/pass_project/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/pass_project" \
    bash -c "source '$test_dir/harness.sh'; _qa_run_loop 'exit 0' '/nonexistent/specs'" 2>/dev/null) || true
assert_contains "$output" "PASS" "_qa_run_loop returns PASS when no failures"

# --- Test 4: _qa_run_loop creates iteration files ---
if [ -f "$test_dir/pass_project/.automaton/qa/iteration-1.json" ]; then
    assert_exit_code 0 0 "_qa_run_loop creates iteration-1.json"
else
    assert_exit_code 0 1 "_qa_run_loop creates iteration-1.json"
fi

# --- Test 5: _qa_run_loop stops at max iterations ---
mkdir -p "$test_dir/fail_project/.automaton/qa"
cat > "$test_dir/fail_project/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
PLAN
# Use a test command that always fails to trigger max iterations
output=$(TEST_AUTOMATON_DIR="$test_dir/fail_project/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/fail_project" \
    QA_MAX_ITERATIONS=2 \
    bash -c "source '$test_dir/harness.sh'; QA_MAX_ITERATIONS=2; _qa_run_loop 'exit 1' '/nonexistent/specs'" 2>/dev/null) || true
# After max iterations it should return FAIL
assert_contains "$output" "FAIL" "_qa_run_loop returns FAIL after max iterations"

# --- Test 6: _qa_run_loop output includes iteration count ---
assert_contains "$output" "iteration" "_qa_run_loop output includes iteration count"

# --- Test 7: _qa_run_loop creates fix tasks on failure ---
mkdir -p "$test_dir/fix_project/.automaton/qa"
cat > "$test_dir/fix_project/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
PLAN
# Use 2 max iterations with a failing test to trigger fix task creation
# (fix tasks are only created when more iterations remain)
TEST_AUTOMATON_DIR="$test_dir/fix_project/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/fix_project" \
    bash -c "source '$test_dir/harness.sh'; QA_MAX_ITERATIONS=2; _qa_run_loop 'exit 1' '/nonexistent/specs'" 2>/dev/null || true
if grep -q 'QA-' "$test_dir/fix_project/IMPLEMENTATION_PLAN.md" 2>/dev/null; then
    assert_exit_code 0 0 "_qa_run_loop creates QA fix tasks on failure"
else
    assert_exit_code 0 1 "_qa_run_loop creates QA fix tasks on failure"
fi

# --- Test 8: _qa_run_loop output is valid JSON ---
mkdir -p "$test_dir/json_project/.automaton/qa"
cat > "$test_dir/json_project/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
PLAN
output=$(TEST_AUTOMATON_DIR="$test_dir/json_project/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/json_project" \
    bash -c "source '$test_dir/harness.sh'; _qa_run_loop 'exit 0' '/nonexistent/specs'" 2>/dev/null) || true
echo "$output" | jq empty 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "_qa_run_loop output is valid JSON"

echo ""
echo "=== test_qa_loop.sh complete ==="
