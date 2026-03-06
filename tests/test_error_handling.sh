#!/usr/bin/env bash
# tests/test_error_handling.sh — Functional tests for lib/errors.sh
# Tests error classification, failure counting, stall detection, plan integrity.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up isolated test directory
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-errors-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Mock dependencies
LOG_OUTPUT=""
log() { LOG_OUTPUT+="[$1] $2"$'\n'; }
write_state() { :; }
escalate() { echo "ESCALATED: $1" >&2; return 1; }

# Extract functions from errors.sh
extract_function() {
    local func_name="$1" file="$2"
    awk "/^${func_name}\\(\\)/{found=1; depth=0} found{
        for(i=1;i<=length(\$0);i++){
            c=substr(\$0,i,1)
            if(c==\"{\") depth++
            if(c==\"}\") depth--
        }
        print
        if(found && depth==0) exit
    }" "$file"
}

for fn in is_rate_limit is_network_error is_test_failure reset_failure_count checkpoint_plan check_plan_integrity check_test_failures; do
    eval "$(extract_function "$fn" "$PROJECT_DIR/lib/errors.sh")"
done

# ============================================================
# is_rate_limit classification
# ============================================================

if is_rate_limit "Error: rate_limit exceeded"; then
    echo "PASS: rate_limit detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect rate_limit" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_rate_limit "HTTP 429 Too Many Requests"; then
    echo "PASS: 429 status detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect 429" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_rate_limit "Server overloaded, please retry"; then
    echo "PASS: overloaded detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect overloaded" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_rate_limit "Normal successful output"; then
    echo "FAIL: should not detect rate limit in normal output" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: normal output is not rate limit"
    ((_TEST_PASS_COUNT++))
fi

# ============================================================
# is_network_error classification
# ============================================================

if is_network_error "ECONNREFUSED: connection refused"; then
    echo "PASS: ECONNREFUSED detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect ECONNREFUSED" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_network_error "Error: connection timeout"; then
    echo "PASS: timeout detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect timeout" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_network_error "getaddrinfo ENOTFOUND api.anthropic.com"; then
    echo "PASS: DNS failure detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect DNS failure" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_network_error "Build completed successfully"; then
    echo "FAIL: should not detect network error in success output" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: success output is not network error"
    ((_TEST_PASS_COUNT++))
fi

# ============================================================
# is_test_failure classification
# ============================================================

if is_test_failure "3 tests failed"; then
    echo "PASS: 'tests failed' detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect 'tests failed'" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_test_failure "FAIL: expected 5, got 3"; then
    echo "PASS: 'FAIL:' detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect 'FAIL:'" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_test_failure "jest: 2 test suites failed"; then
    echo "PASS: jest failure detected"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should detect jest failure" >&2
    ((_TEST_FAIL_COUNT++))
fi

if is_test_failure "All tests passed."; then
    echo "FAIL: should not match 'All tests passed'" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: passing tests not flagged"
    ((_TEST_PASS_COUNT++))
fi

# ============================================================
# reset_failure_count
# ============================================================

consecutive_failures=3
LOG_OUTPUT=""
reset_failure_count
assert_equals "0" "$consecutive_failures" "reset_failure_count zeroes counter"
assert_contains "$LOG_OUTPUT" "Recovered after 3 failure(s)" "recovery logged"

# No log when already at 0
consecutive_failures=0
LOG_OUTPUT=""
reset_failure_count
assert_equals "" "$LOG_OUTPUT" "no log when already at 0"

# ============================================================
# checkpoint_plan + check_plan_integrity
# ============================================================

cd "$TEST_DIR"
mkdir -p "$AUTOMATON_DIR"

# Create a plan with 5 completed items
cat > IMPLEMENTATION_PLAN.md << 'EOF'
- [x] Task 1
- [x] Task 2
- [x] Task 3
- [x] Task 4
- [x] Task 5
- [ ] Task 6
EOF

# Initialize git for plan integrity
git init -q
git add -A
git commit -q -m "init"

checkpoint_plan
assert_equals "5" "$PLAN_CHECKPOINT_COMPLETED_COUNT" "checkpoint captures 5 completed tasks"

# Simulate corruption: agent removes completed tasks
cat > IMPLEMENTATION_PLAN.md << 'EOF'
- [x] Task 1
- [ ] Task 2
- [ ] Task 3
- [ ] Task 4
- [ ] Task 5
- [ ] Task 6
EOF

corruption_count=0
LOG_OUTPUT=""
check_plan_integrity
assert_contains "$LOG_OUTPUT" "PLAN CORRUPTION" "corruption detected when completed count drops"

# Plan should be restored
restored_count=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md)
assert_equals "5" "$restored_count" "plan restored from checkpoint"

# ============================================================
# check_test_failures — repeated test failure escalation
# ============================================================

test_failure_count=0

# First failure: returns 0 (continue)
rc=0
check_test_failures "3 tests failed" || rc=$?
assert_equals "0" "$rc" "first test failure returns 0"
assert_equals "1" "$test_failure_count" "test_failure_count incremented to 1"

# Second failure
check_test_failures "2 tests failed" || true
assert_equals "2" "$test_failure_count" "test_failure_count incremented to 2"

# Third failure: returns 1 (force review)
rc=0
check_test_failures "1 test failed" || rc=$?
assert_equals "1" "$rc" "3rd consecutive test failure returns 1 (force review)"
assert_equals "0" "$test_failure_count" "test_failure_count resets after escalation"

# Success clears counter
test_failure_count=2
check_test_failures "All tests passed" || true
assert_equals "0" "$test_failure_count" "success clears test_failure_count"

test_summary
