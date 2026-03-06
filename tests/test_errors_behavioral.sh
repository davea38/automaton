#!/usr/bin/env bash
# tests/test_errors_behavioral.sh — Behavioral tests for lib/errors.sh functions.
# Actually executes error classification, stall detection, and plan integrity checks.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
setup_test_dir

# Minimal stubs
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"
log() { :; }
emit_event() { :; }
write_state() { :; }
escalate() { echo "ESCALATED: $1"; exit 3; }

# Source the errors module
source "$_PROJECT_DIR/lib/errors.sh"

# Config defaults
EXEC_MAX_CONSECUTIVE_FAILURES=3
EXEC_RETRY_DELAY_SECONDS=0
EXEC_STALL_THRESHOLD=3

# --- Test 1: is_rate_limit detects rate limit patterns ---
is_rate_limit "Error: rate_limit exceeded"
assert_exit_code 0 $? "is_rate_limit detects 'rate_limit'"

is_rate_limit "HTTP 429 Too Many Requests"
assert_exit_code 0 $? "is_rate_limit detects '429'"

is_rate_limit "API is overloaded"
assert_exit_code 0 $? "is_rate_limit detects 'overloaded'"

is_rate_limit "Normal success output" && rc=0 || rc=1
assert_exit_code 1 "$rc" "is_rate_limit returns 1 for normal output"

# --- Test 2: is_network_error detects network errors ---
is_network_error "ECONNREFUSED 127.0.0.1:443"
assert_exit_code 0 $? "is_network_error detects ECONNREFUSED"

is_network_error "connection timeout"
assert_exit_code 0 $? "is_network_error detects timeout"

is_network_error "Normal success output" && rc=0 || rc=1
assert_exit_code 1 "$rc" "is_network_error returns 1 for normal output"

# --- Test 3: is_test_failure detects test failures ---
is_test_failure "5 tests failed"
assert_exit_code 0 $? "is_test_failure detects 'tests failed'"

is_test_failure "FAIL: assertion check"
assert_exit_code 0 $? "is_test_failure detects 'FAIL:'"

is_test_failure "jest 3 suites failed"
assert_exit_code 0 $? "is_test_failure detects jest failures"

is_test_failure "All tests passed successfully" && rc=0 || rc=1
assert_exit_code 1 "$rc" "is_test_failure returns 1 for passing output"

# --- Test 4: reset_failure_count resets counter ---
consecutive_failures=5
reset_failure_count
assert_equals "0" "$consecutive_failures" "reset_failure_count sets counter to 0"

# --- Test 5: checkpoint_plan creates checkpoint and counts ---
mkdir -p "$TEST_DIR/specs"
cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'EOF'
- [x] Task 1
- [x] Task 2
- [ ] Task 3
EOF
cd "$TEST_DIR"
checkpoint_plan
assert_file_exists "$AUTOMATON_DIR/plan_checkpoint.md" "checkpoint_plan creates backup"
assert_equals "2" "$PLAN_CHECKPOINT_COMPLETED_COUNT" "checkpoint_plan counts [x] marks"

# --- Test 6: check_plan_integrity passes when count unchanged ---
corruption_count=0
check_plan_integrity
assert_exit_code 0 $? "check_plan_integrity passes when plan intact"

# --- Test 7: check_plan_integrity restores on corruption ---
# Simulate agent removing a completed task
cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'EOF'
- [x] Task 1
- [ ] Task 2
- [ ] Task 3
EOF
# Need git for the restore commit
git init "$TEST_DIR" >/dev/null 2>&1
git -C "$TEST_DIR" add -A >/dev/null 2>&1
git -C "$TEST_DIR" commit -m "init" >/dev/null 2>&1
check_plan_integrity
# Plan should be restored from checkpoint
restored_count=$(grep -c '\[x\]' "$TEST_DIR/IMPLEMENTATION_PLAN.md" 2>/dev/null) || restored_count=0
assert_equals "2" "$restored_count" "check_plan_integrity restores corrupted plan"

# --- Test 8: check_test_failures counts and escalates ---
test_failure_count=0
check_test_failures "All good"
assert_equals "0" "$test_failure_count" "no test failure increments on clean output"

check_test_failures "5 tests failed"
assert_equals "1" "$test_failure_count" "test_failure_count increments on failure"

check_test_failures "jest 2 suites failed"
assert_equals "2" "$test_failure_count" "test_failure_count increments again"

result=$(check_test_failures "FAIL: assertion error" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "3rd consecutive test failure returns 1 (escalate to review)"

# --- Test 9: check_test_failures resets on success ---
test_failure_count=2
check_test_failures "All tests passed"
assert_equals "0" "$test_failure_count" "test_failure_count resets on success"

cd "$SCRIPT_DIR/.."
test_summary
