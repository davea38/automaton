#!/usr/bin/env bash
# tests/test_safety_preflight.sh — Tests for spec-45 §6 pre-evolution safety preflight
# Verifies _safety_preflight() in automaton.sh validates all preconditions
# before the first evolution cycle begins.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _safety_preflight function ---
grep_result=$(grep -c '^_safety_preflight()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _safety_preflight()"

# --- Test 2: _safety_preflight checks for clean working tree via git diff ---
grep_result=$(grep -A 50 '^_safety_preflight()' "$script_file" | grep -c 'git diff.*--quiet\|git diff --quiet' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight checks for clean working tree (git diff --quiet)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should check for clean working tree using git diff --quiet" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _safety_preflight checks test pass rate ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c 'pass_rate\|test.*rate\|MIN_TEST_PASS_RATE' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight checks test pass rate"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should check test pass rate" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _safety_preflight checks constitution existence ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c 'constitution' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight checks for constitution"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should check for constitution existence" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _safety_preflight checks budget sufficiency ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c 'budget\|remaining.*usd\|cost' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight checks budget sufficiency"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should check budget sufficiency" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _safety_preflight checks circuit breakers ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c '_safety_any_breaker_tripped\|breaker' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight checks circuit breakers"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should check for tripped circuit breakers" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _safety_preflight respects SAFETY_PREFLIGHT_ENABLED flag ---
grep_result=$(grep -A 10 '^_safety_preflight()' "$script_file" | grep -c 'SAFETY_PREFLIGHT_ENABLED' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight respects SAFETY_PREFLIGHT_ENABLED config flag"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should respect SAFETY_PREFLIGHT_ENABLED config flag" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _safety_preflight uses log function for reporting ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c 'log "SAFETY"' || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: _safety_preflight uses log function for reporting (at least 3 log calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should use log function for reporting (expected at least 3 log calls)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _safety_preflight returns non-zero on failure ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c 'return 1' || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: _safety_preflight returns 1 on failure conditions (at least 3 failure paths)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should return 1 on failure conditions (expected at least 3 failure paths)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _safety_preflight returns 0 on success ---
grep_result=$(grep -A 80 '^_safety_preflight()' "$script_file" | grep -c 'return 0' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_preflight returns 0 on success"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_preflight should return 0 on success" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
