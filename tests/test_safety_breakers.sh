#!/usr/bin/env bash
# tests/test_safety_breakers.sh — Tests for spec-45 §2 circuit breaker functions
# Verifies _safety_check_breakers(), _safety_update_breaker(),
# _safety_any_breaker_tripped(), and _safety_reset_breakers() in automaton.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _safety_check_breakers function ---
grep_result=$(grep -c '^_safety_check_breakers()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _safety_check_breakers()"

# --- Test 2: automaton.sh defines _safety_update_breaker function ---
grep_result=$(grep -c '^_safety_update_breaker()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _safety_update_breaker()"

# --- Test 3: automaton.sh defines _safety_any_breaker_tripped function ---
grep_result=$(grep -c '^_safety_any_breaker_tripped()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _safety_any_breaker_tripped()"

# --- Test 4: automaton.sh defines _safety_reset_breakers function ---
grep_result=$(grep -c '^_safety_reset_breakers()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _safety_reset_breakers()"

# --- Test 5: _safety_check_breakers references budget_ceiling breaker ---
grep_result=$(grep -c 'budget_ceiling' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh references budget_ceiling breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference budget_ceiling breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _safety_check_breakers references error_cascade breaker ---
grep_result=$(grep -c 'error_cascade' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh references error_cascade breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference error_cascade breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _safety_check_breakers references regression_cascade breaker ---
grep_result=$(grep -c 'regression_cascade' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh references regression_cascade breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference regression_cascade breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _safety_check_breakers references complexity_ceiling breaker ---
grep_result=$(grep -c 'complexity_ceiling' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh references complexity_ceiling breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference complexity_ceiling breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _safety_check_breakers references test_degradation breaker ---
grep_result=$(grep -c 'test_degradation' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh references test_degradation breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference test_degradation breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _safety_check_breakers references circuit-breakers.json ---
grep_result=$(grep -c 'circuit-breakers.json' "$script_file" || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: automaton.sh references circuit-breakers.json in multiple places"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference circuit-breakers.json in multiple places (breaker functions)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _safety_update_breaker handles consecutive_failures for error_cascade ---
grep_result=$(grep -c 'consecutive_failures' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh tracks consecutive_failures"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should track consecutive_failures for error_cascade" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: _safety_update_breaker handles consecutive_regressions for regression_cascade ---
grep_result=$(grep -c 'consecutive_regressions' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh tracks consecutive_regressions"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should track consecutive_regressions for regression_cascade" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _safety_reset_breakers resets all breakers ---
# Verify reset writes a fresh state with all 5 breakers set to tripped=false
grep_result=$(grep -c 'tripped.*false' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh resets breakers to tripped=false"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reset breakers to tripped=false" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _safety_check_breakers uses SAFETY_MAX_TOTAL_LINES ---
grep_result=$(grep -c 'SAFETY_MAX_TOTAL_LINES' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh uses SAFETY_MAX_TOTAL_LINES (config + default + breaker check)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should use SAFETY_MAX_TOTAL_LINES in breaker check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: _safety_check_breakers uses SAFETY_MAX_TOTAL_FUNCTIONS ---
grep_result=$(grep -c 'SAFETY_MAX_TOTAL_FUNCTIONS' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh uses SAFETY_MAX_TOTAL_FUNCTIONS (config + default + breaker check)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should use SAFETY_MAX_TOTAL_FUNCTIONS in breaker check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: _safety_check_breakers uses SAFETY_MIN_TEST_PASS_RATE ---
grep_result=$(grep -c 'SAFETY_MIN_TEST_PASS_RATE' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh uses SAFETY_MIN_TEST_PASS_RATE (config + default + breaker check)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should use SAFETY_MIN_TEST_PASS_RATE in breaker check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 17: _safety_check_breakers uses SAFETY_MAX_CONSECUTIVE_FAILURES ---
grep_result=$(grep -c 'SAFETY_MAX_CONSECUTIVE_FAILURES' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh uses SAFETY_MAX_CONSECUTIVE_FAILURES (config + default + breaker check)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should use SAFETY_MAX_CONSECUTIVE_FAILURES in breaker check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 18: _safety_check_breakers uses SAFETY_MAX_CONSECUTIVE_REGRESSIONS ---
grep_result=$(grep -c 'SAFETY_MAX_CONSECUTIVE_REGRESSIONS' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh uses SAFETY_MAX_CONSECUTIVE_REGRESSIONS (config + default + breaker check)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should use SAFETY_MAX_CONSECUTIVE_REGRESSIONS in breaker check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 19: Circuit breaker section header exists ---
grep_result=$(grep -c 'Circuit Breakers.*spec-45' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has Circuit Breakers section header"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have Circuit Breakers section header" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 20: _safety_any_breaker_tripped checks for tripped breakers ---
# It should read the breakers file and check if any have tripped=true
grep_result=$(grep -A5 '_safety_any_breaker_tripped' "$script_file" | grep -c 'tripped.*true\|select.*tripped' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_any_breaker_tripped checks for tripped=true"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_any_breaker_tripped should check for tripped=true" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
