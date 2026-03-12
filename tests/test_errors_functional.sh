#!/usr/bin/env bash
# tests/test_errors_functional.sh — Functional tests for lib/errors.sh
# Tests error classification, crash handling, stall detection, plan integrity, and test failure tracking.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

# --- Setup: extract and source functions with required dependencies ---

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Minimal stubs for dependencies
log() { echo "[$1] $2" >> "$TEST_DIR/test.log"; }
write_state() { echo "state_written" >> "$TEST_DIR/actions.log"; }
escalate() { echo "ESCALATED: $1" >> "$TEST_DIR/actions.log"; exit 3; }

# Source the module
source "$_PROJECT_DIR/lib/errors.sh"

# --- Test: is_rate_limit classification ---

output_rate="Error: rate_limit exceeded"
output_429="HTTP 429 Too Many Requests"
output_overloaded="API overloaded"
output_normal="Build completed successfully"

assert_equals "0" "$(is_rate_limit "$output_rate" && echo 0 || echo 1)" "is_rate_limit detects rate_limit"
assert_equals "0" "$(is_rate_limit "$output_429" && echo 0 || echo 1)" "is_rate_limit detects 429"
assert_equals "0" "$(is_rate_limit "$output_overloaded" && echo 0 || echo 1)" "is_rate_limit detects overloaded"
assert_equals "1" "$(is_rate_limit "$output_normal" && echo 0 || echo 1)" "is_rate_limit rejects normal output"
assert_equals "1" "$(is_rate_limit "" && echo 0 || echo 1)" "is_rate_limit handles empty string"

# --- Test: is_network_error classification ---

assert_equals "0" "$(is_network_error "ECONNREFUSED" && echo 0 || echo 1)" "is_network_error detects ECONNREFUSED"
assert_equals "0" "$(is_network_error "connection timeout" && echo 0 || echo 1)" "is_network_error detects timeout"
assert_equals "0" "$(is_network_error "getaddrinfo ENOTFOUND" && echo 0 || echo 1)" "is_network_error detects DNS failure"
assert_equals "1" "$(is_network_error "syntax error" && echo 0 || echo 1)" "is_network_error rejects non-network error"

# --- Test: is_test_failure classification ---

assert_equals "0" "$(is_test_failure "3 tests failed" && echo 0 || echo 1)" "is_test_failure detects 'tests failed'"
assert_equals "0" "$(is_test_failure "FAIL: test_foo" && echo 0 || echo 1)" "is_test_failure detects FAIL:"
assert_equals "0" "$(is_test_failure "jest failed" && echo 0 || echo 1)" "is_test_failure detects jest failed"
assert_equals "0" "$(is_test_failure "pytest failed" && echo 0 || echo 1)" "is_test_failure detects pytest failed"
assert_equals "1" "$(is_test_failure "all tests passed" && echo 0 || echo 1)" "is_test_failure rejects passing output"

# --- Test: is_environment_error classification ---

assert_equals "0" "$(is_environment_error "Error: Claude Code cannot be launched inside another Claude Code session." && echo 0 || echo 1)" "is_environment_error detects nested session"
assert_equals "0" "$(is_environment_error "Nested sessions share runtime resources" && echo 0 || echo 1)" "is_environment_error detects nested sessions message"
assert_equals "0" "$(is_environment_error "unset the CLAUDECODE environment variable" && echo 0 || echo 1)" "is_environment_error detects CLAUDECODE hint"
assert_equals "0" "$(is_environment_error "bash: claude: command not found" && echo 0 || echo 1)" "is_environment_error detects command not found"
assert_equals "1" "$(is_environment_error "normal output" && echo 0 || echo 1)" "is_environment_error rejects normal output"
assert_equals "1" "$(is_environment_error "" && echo 0 || echo 1)" "is_environment_error handles empty string"

# --- Test: handle_cli_crash increments failures and escalates at max ---

consecutive_failures=0
EXEC_MAX_CONSECUTIVE_FAILURES=3
EXEC_RETRY_DELAY_SECONDS=0

handle_cli_crash 1 "some error" 2>/dev/null
assert_equals "1" "$consecutive_failures" "handle_cli_crash increments failure count"

handle_cli_crash 1 "another error" 2>/dev/null
assert_equals "2" "$consecutive_failures" "handle_cli_crash increments to 2"

# Third failure should escalate (exit 3) via escalate()
rc=0
(handle_cli_crash 1 "fatal" 2>/dev/null) || rc=$?
assert_equals "3" "$rc" "handle_cli_crash escalates (exit 3) at max failures"

# --- Test: reset_failure_count ---

consecutive_failures=5
reset_failure_count
assert_equals "0" "$consecutive_failures" "reset_failure_count zeros the counter"

# --- Test: checkpoint_plan and check_plan_integrity ---

cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'EOF'
- [x] Task one completed
- [x] Task two completed
- [ ] Task three pending
EOF
cd "$TEST_DIR"
PLAN_CHECKPOINT_COMPLETED_COUNT=0

checkpoint_plan
assert_equals "2" "$PLAN_CHECKPOINT_COMPLETED_COUNT" "checkpoint_plan counts [x] items"
assert_file_exists "$AUTOMATON_DIR/plan_checkpoint.md" "checkpoint creates backup"

# Simulate plan integrity (no corruption)
rc=0
corruption_count=0
check_plan_integrity || rc=$?
assert_equals "0" "$rc" "check_plan_integrity passes when plan is intact"

# Simulate corruption: remove a completed task
cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'EOF'
- [x] Task one completed
- [ ] Task two now unchecked
- [ ] Task three pending
EOF

# Need git for the restore (mock it)
git() {
    if [ "$1" = "add" ] || [ "$1" = "commit" ]; then
        return 0
    fi
}
export -f git

rc=0
check_plan_integrity || rc=$?
assert_equals "0" "$rc" "check_plan_integrity restores and returns 0 on first corruption"
assert_equals "1" "$corruption_count" "corruption_count incremented"

# Verify plan was restored
restored_count=$(grep -c '\[x\]' "$TEST_DIR/IMPLEMENTATION_PLAN.md")
assert_equals "2" "$restored_count" "plan restored from checkpoint"

# --- Test: check_stall detection ---

stall_count=0
replan_count=0
EXEC_STALL_THRESHOLD=3

# Mock git to return empty diff (stall)
git() {
    if [ "$1" = "diff" ]; then
        echo ""
        return 0
    fi
}
export -f git

rc=0
check_stall || rc=$?
assert_equals "0" "$rc" "check_stall returns 0 on first stall"
assert_equals "1" "$stall_count" "stall_count incremented to 1"

check_stall || true
check_stall || rc=$?
# After 3 stalls, should return 1 (force re-plan)
assert_equals "1" "$rc" "check_stall returns 1 at threshold"

# --- Test: check_test_failures escalation ---

test_failure_count=0

check_test_failures "3 tests failed" || true
assert_equals "1" "$test_failure_count" "test_failure_count incremented on failure"

check_test_failures "all tests passed"
assert_equals "0" "$test_failure_count" "test_failure_count reset on success"

# Escalate after 3 consecutive failures
check_test_failures "test failed" || true
check_test_failures "test failed" || true
rc=0
check_test_failures "test failed" || rc=$?
assert_equals "1" "$rc" "check_test_failures returns 1 after 3 consecutive failures"

cd "$_PROJECT_DIR"
test_summary
