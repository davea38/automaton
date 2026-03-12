#!/usr/bin/env bash
# tests/test_errors_ratelimit.sh — Tests for handle_rate_limit, check_pacing,
# and error classification in lib/errors.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-errors-rl-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Mock log
LOG_OUTPUT=""
log() { LOG_OUTPUT+="[$1] $2"$'\n'; }

# Mock write_state, send_notification, emit_event
write_state() { :; }
send_notification() { :; }
emit_event() { :; }

# Source errors functions
source "$PROJECT_DIR/lib/errors.sh"

# ============================================================
# is_rate_limit — detects various rate limit patterns
# ============================================================
assert_equals "0" "$(is_rate_limit "Error: rate_limit exceeded" && echo 0 || echo 1)" "detects rate_limit"
assert_equals "0" "$(is_rate_limit "HTTP 429 Too Many Requests" && echo 0 || echo 1)" "detects 429"
assert_equals "0" "$(is_rate_limit "server overloaded" && echo 0 || echo 1)" "detects overloaded"
assert_equals "0" "$(is_rate_limit "Rate limit hit" && echo 0 || echo 1)" "detects Rate limit"
assert_equals "1" "$(is_rate_limit "normal output" && echo 0 || echo 1)" "no false positive"
assert_equals "1" "$(is_rate_limit "" && echo 0 || echo 1)" "empty string not rate limit"

# ============================================================
# is_network_error — detects network issues
# ============================================================
assert_equals "0" "$(is_network_error "ECONNREFUSED" && echo 0 || echo 1)" "detects ECONNREFUSED"
assert_equals "0" "$(is_network_error "connection timeout" && echo 0 || echo 1)" "detects connection timeout"
assert_equals "0" "$(is_network_error "getaddrinfo failed" && echo 0 || echo 1)" "detects getaddrinfo"
assert_equals "1" "$(is_network_error "syntax error" && echo 0 || echo 1)" "no false positive"

# ============================================================
# is_test_failure — detects test failure patterns
# ============================================================
assert_equals "0" "$(is_test_failure "5 tests failed" && echo 0 || echo 1)" "detects 'tests failed'"
assert_equals "0" "$(is_test_failure "FAIL: test_something" && echo 0 || echo 1)" "detects 'FAIL:'"
assert_equals "0" "$(is_test_failure "pytest: 3 failed" && echo 0 || echo 1)" "detects 'pytest.*failed'"
assert_equals "0" "$(is_test_failure "jest test suite failed" && echo 0 || echo 1)" "detects 'jest.*failed'"
assert_equals "1" "$(is_test_failure "all tests passed" && echo 0 || echo 1)" "passed tests no false positive"

# ============================================================
# checkpoint_plan / check_plan_integrity — plan corruption guard
# ============================================================
cat > "$TEST_DIR/IMPLEMENTATION_PLAN.md" <<'EOF'
- [x] Task 1 completed
- [x] Task 2 completed
- [ ] Task 3 todo
EOF
# Simulate running from project dir
cd "$TEST_DIR"
AUTOMATON_DIR=".automaton"
mkdir -p "$AUTOMATON_DIR"

checkpoint_plan
assert_equals "2" "$PLAN_CHECKPOINT_COMPLETED_COUNT" "checkpoint captures 2 completed tasks"
assert_file_exists "$AUTOMATON_DIR/plan_checkpoint.md" "checkpoint file created"

# No corruption case
LOG_OUTPUT=""
corruption_count=0
check_plan_integrity
result=$?
assert_equals "0" "$result" "no corruption returns 0"

# Simulate corruption: reduce completed count
cat > "IMPLEMENTATION_PLAN.md" <<'EOF'
- [x] Task 1 completed
- [ ] Task 2 now unchecked
- [ ] Task 3 todo
EOF

# Mock git and escalate
git() { :; }
export -f git
escalate() { echo "ESCALATED: $1"; }

LOG_OUTPUT=""
corruption_count=0
check_plan_integrity
assert_contains "$LOG_OUTPUT" "PLAN CORRUPTION" "corruption detected and logged"

# Check restored
restored_count=$(grep -c '\[x\]' "IMPLEMENTATION_PLAN.md")
assert_equals "2" "$restored_count" "plan restored from checkpoint"

# ============================================================
# check_stall — stall detection
# ============================================================
stall_count=0
replan_count=0
EXEC_STALL_THRESHOLD=3

# Mock git diff to return empty (stall)
git() {
    if [ "$1" = "diff" ]; then
        echo ""
    fi
}
export -f git

LOG_OUTPUT=""
check_stall
assert_equals "1" "$stall_count" "first stall increments counter"
check_stall
assert_equals "2" "$stall_count" "second stall increments counter"

result=0
check_stall || result=$?
assert_equals "1" "$result" "third stall triggers re-plan"
assert_equals "1" "$replan_count" "replan_count incremented"

# Restore real git
unset -f git

# ============================================================
# check_stall — bookkeeping-only diffs should still count as stall
# ============================================================
stall_count=0
replan_count=0

# Mock git diff to return bookkeeping-only files when pathspec is used,
# but simulate real git behavior: with exclusion pathspecs, bookkeeping
# files are excluded so the output is empty → stall detected.
git() {
    if [ "$1" = "diff" ]; then
        # If pathspec exclusions are present (contains ':!'), return empty
        # (bookkeeping files filtered out, no real changes)
        local args="$*"
        if echo "$args" | grep -q ':!'; then
            echo ""
        else
            # Without exclusions, would show bookkeeping files
            echo " AGENTS.md | 2 +-"
        fi
        return 0
    fi
}
export -f git

LOG_OUTPUT=""
check_stall
assert_equals "1" "$stall_count" "bookkeeping-only diff still triggers stall"

# Unset mock
unset -f git

# ============================================================
# check_test_failures — test failure escalation
# ============================================================
test_failure_count=0
current_phase="build"

result=0
check_test_failures "some test failed output" || result=$?
assert_equals "0" "$result" "first test failure returns 0 (continue)"
assert_equals "1" "$test_failure_count" "test_failure_count incremented"

check_test_failures "test still failing" || true
result=0
check_test_failures "tests failed again 3rd time" || result=$?
assert_equals "1" "$result" "3rd consecutive test failure returns 1 (escalate to review)"

# Reset after success
test_failure_count=2
check_test_failures "all tests passed, no failures"
assert_equals "0" "$test_failure_count" "test_failure_count reset on success"

# ============================================================
# reset_failure_count — clears consecutive failures
# ============================================================
consecutive_failures=3
LOG_OUTPUT=""
reset_failure_count
assert_equals "0" "$consecutive_failures" "consecutive_failures reset to 0"
assert_contains "$LOG_OUTPUT" "Recovered" "recovery logged"

# No log when already 0
LOG_OUTPUT=""
consecutive_failures=0
reset_failure_count
assert_not_contains "$LOG_OUTPUT" "Recovered" "no log when already 0"

# ============================================================
# check_pacing — budget file required
# ============================================================
rm -f "$AUTOMATON_DIR/budget.json"
result=0
check_pacing || result=$?
assert_equals "0" "$result" "check_pacing returns 0 when no budget file"

# ============================================================
# check_pacing — not enough history
# ============================================================
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{"history": []}
EOF
result=0
check_pacing || result=$?
assert_equals "0" "$result" "check_pacing returns 0 with empty history"

cd "$SCRIPT_DIR/.."

test_summary
