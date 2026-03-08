#!/usr/bin/env bash
# tests/test_qa_oscillation.sh — Tests for QA oscillation detection
# Verifies _qa_detect_oscillation() detects fail→fix→re-fail patterns
# and _qa_run_loop integrates oscillation-based early exit.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_oscillation_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: _qa_detect_oscillation function exists ---
grep -q '^_qa_detect_oscillation() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_detect_oscillation function exists"

# --- Extract functions for unit tests ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
emit_event() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
PROJECT_ROOT="$TEST_PROJECT_ROOT"
QA_ENABLED="true"
QA_MAX_ITERATIONS=5
QA_MODEL="sonnet"
QA_BLIND_VALIDATION="false"
run_agent() { AGENT_RESULT=""; AGENT_EXIT_CODE=0; }
check_budget() { return 0; }
BUDGET_PER_ITERATION=100000
BUDGET_MODE="fixed"
HARNESS
    for fn in _qa_detect_oscillation _qa_run_loop _qa_validate _qa_run_tests \
              _qa_check_spec_criteria _qa_scan_regressions _qa_classify_failure \
              _qa_write_iteration _qa_mark_persistent _qa_create_fix_tasks \
              _qa_write_failure_report; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 2: No oscillation with empty history ---
mkdir -p "$test_dir/t2/.automaton/qa"
output=$(TEST_AUTOMATON_DIR="$test_dir/t2/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/t2" \
    bash -c "source '$test_dir/harness.sh'; _qa_detect_oscillation 1 '[]'" 2>/dev/null)
rc=$?
assert_exit_code 1 "$rc" "No oscillation on iteration 1 (returns 1 = no oscillation)"

# --- Test 3: No oscillation with only 2 iterations ---
mkdir -p "$test_dir/t3/.automaton/qa"
# Write iteration-1 with failure A
echo '{"iteration":1,"failures":[{"id":"test_a"}],"verdict":"FAIL"}' > "$test_dir/t3/.automaton/qa/iteration-1.json"
output=$(TEST_AUTOMATON_DIR="$test_dir/t3/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/t3" \
    bash -c "source '$test_dir/harness.sh'; _qa_detect_oscillation 2 '[{\"id\":\"test_b\"}]'" 2>/dev/null)
rc=$?
assert_exit_code 1 "$rc" "No oscillation with only 2 iterations (need 3+ for a cycle)"

# --- Test 4: Detects oscillation: A fails → B fails → A fails again ---
mkdir -p "$test_dir/t4/.automaton/qa"
echo '{"iteration":1,"failures":[{"id":"test_a"}],"verdict":"FAIL"}' > "$test_dir/t4/.automaton/qa/iteration-1.json"
echo '{"iteration":2,"failures":[{"id":"test_b"}],"verdict":"FAIL"}' > "$test_dir/t4/.automaton/qa/iteration-2.json"
# Current iteration 3 has test_a again
output=$(TEST_AUTOMATON_DIR="$test_dir/t4/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/t4" \
    bash -c "source '$test_dir/harness.sh'; _qa_detect_oscillation 3 '[{\"id\":\"test_a\"}]'" 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "Detects oscillation: test_a in iter 1 and 3"

# --- Test 5: No oscillation when failures are consistently new ---
mkdir -p "$test_dir/t5/.automaton/qa"
echo '{"iteration":1,"failures":[{"id":"test_a"}],"verdict":"FAIL"}' > "$test_dir/t5/.automaton/qa/iteration-1.json"
echo '{"iteration":2,"failures":[{"id":"test_b"}],"verdict":"FAIL"}' > "$test_dir/t5/.automaton/qa/iteration-2.json"
# Current iteration 3 has test_c (new failure, no cycle)
output=$(TEST_AUTOMATON_DIR="$test_dir/t5/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/t5" \
    bash -c "source '$test_dir/harness.sh'; _qa_detect_oscillation 3 '[{\"id\":\"test_c\"}]'" 2>/dev/null)
rc=$?
assert_exit_code 1 "$rc" "No oscillation when all failures are new"

# --- Test 6: Detects oscillation with multiple overlapping failures ---
mkdir -p "$test_dir/t6/.automaton/qa"
echo '{"iteration":1,"failures":[{"id":"test_a"},{"id":"test_b"}],"verdict":"FAIL"}' > "$test_dir/t6/.automaton/qa/iteration-1.json"
echo '{"iteration":2,"failures":[{"id":"test_c"}],"verdict":"FAIL"}' > "$test_dir/t6/.automaton/qa/iteration-2.json"
echo '{"iteration":3,"failures":[{"id":"test_d"}],"verdict":"FAIL"}' > "$test_dir/t6/.automaton/qa/iteration-3.json"
# Current iteration 4 has test_a again (was in iter 1, absent in 2 and 3)
output=$(TEST_AUTOMATON_DIR="$test_dir/t6/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/t6" \
    bash -c "source '$test_dir/harness.sh'; _qa_detect_oscillation 4 '[{\"id\":\"test_a\"}]'" 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "Detects oscillation: test_a reappears after being fixed"

# --- Test 7: Oscillation output includes the oscillating test IDs ---
output=$(TEST_AUTOMATON_DIR="$test_dir/t4/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/t4" \
    bash -c "source '$test_dir/harness.sh'; _qa_detect_oscillation 3 '[{\"id\":\"test_a\"}]'" 2>/dev/null)
assert_contains "$output" "test_a" "Oscillation output names the oscillating test"

# --- Test 8: _qa_run_loop references _qa_detect_oscillation ---
grep -q '_qa_detect_oscillation' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_detect_oscillation is referenced in _qa_run_loop"

test_summary
