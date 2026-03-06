#!/usr/bin/env bash
# tests/test_safety_sandbox.sh — Tests for spec-45 §1 sandbox testing
# Verifies that automaton.sh contains the _safety_sandbox_test() function
# with the 4-step validation sequence: syntax check, smoke test, full test
# suite, and test pass rate comparison against pre-cycle baseline.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _safety_sandbox_test() function exists ---
grep_result=$(grep -c '^_safety_sandbox_test()' "$script_file" || true)
assert_equals "1" "$grep_result" "_safety_sandbox_test() function exists in automaton.sh"

# --- Test 2: Function accepts a branch parameter ---
grep_result=$(grep -A 5 '^_safety_sandbox_test()' "$script_file" | grep -c 'local branch' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test accepts a branch parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should accept a branch parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Step 1 — Syntax check with bash -n ---
grep_result=$(grep -A 40 '^_safety_sandbox_test()' "$script_file" | grep -c 'bash -n' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test includes syntax check (bash -n)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should include syntax check (bash -n automaton.sh)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Step 2 — Smoke test with --dry-run ---
grep_result=$(grep -A 60 '^_safety_sandbox_test()' "$script_file" | grep -c '\-\-dry-run' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test includes smoke test (--dry-run)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should include smoke test (--dry-run)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Step 3 — Runs test suite ---
grep_result=$(grep -A 80 '^_safety_sandbox_test()' "$script_file" | grep -c 'test.*\.sh' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test runs test suite files"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should run test suite (test_*.sh files)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Step 4 — Compares pass rate against baseline ---
grep_result=$(grep -A 100 '^_safety_sandbox_test()' "$script_file" | grep -c 'baseline' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test compares test pass rate against baseline"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should compare pass rate against baseline" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Checks for protected function modifications ---
grep_result=$(grep -A 120 '^_safety_sandbox_test()' "$script_file" | grep -c 'SELF_BUILD_PROTECTED_FUNCTIONS\|protected' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test checks for protected function modifications"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should check for protected function modifications" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Logs with SAFETY prefix ---
grep_result=$(grep -A 120 '^_safety_sandbox_test()' "$script_file" | grep -c 'log.*SAFETY' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test logs with SAFETY prefix"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should log with SAFETY prefix" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Respects SAFETY_SANDBOX_TESTING_ENABLED flag ---
grep_result=$(grep -A 10 '^_safety_sandbox_test()' "$script_file" | grep -c 'SAFETY_SANDBOX_TESTING_ENABLED' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test respects SAFETY_SANDBOX_TESTING_ENABLED config"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should check SAFETY_SANDBOX_TESTING_ENABLED flag" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Returns non-zero on failure ---
grep_result=$(grep -A 120 '^_safety_sandbox_test()' "$script_file" | grep -c 'return 1' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test returns non-zero on failure"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should return 1 on validation failure" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Returns 0 on success ---
grep_result=$(grep -A 120 '^_safety_sandbox_test()' "$script_file" | grep -c 'return 0' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test returns 0 on success"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should return 0 on success" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Uses _metrics_get_latest for baseline comparison ---
grep_result=$(grep -A 120 '^_safety_sandbox_test()' "$script_file" | grep -c '_metrics_get_latest' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_sandbox_test uses _metrics_get_latest for baseline"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_sandbox_test should use _metrics_get_latest for baseline rate" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
