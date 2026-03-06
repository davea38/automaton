#!/usr/bin/env bash
# tests/test_safety_breakers_behavioral.sh — Behavioral tests for circuit breakers
# Covers _safety_update_breaker, _safety_any_breaker_tripped, _safety_reset_breakers,
# and _safety_preflight including edge cases: corrupted files, threshold boundaries.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

setup_test_dir
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR/evolution"

log() { :; }
_metrics_get_latest() { echo ""; }

source "$_PROJECT_DIR/lib/config.sh"
source "$_PROJECT_DIR/lib/safety.sh"

# Override breakers file path to use test dir
_BREAKERS_FILE="$AUTOMATON_DIR/evolution/circuit-breakers.json"

# --- Test 1: init creates valid breakers file ---
_safety_init_breakers_file
assert_file_exists "$_BREAKERS_FILE" "breakers file created by init"
result=$(jq -r '.budget_ceiling.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$result" "budget_ceiling starts un-tripped"

# --- Test 2: no breakers tripped initially ---
if _safety_any_breaker_tripped; then
    echo "FAIL: no breakers should be tripped initially" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: no breakers tripped initially"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 3: update budget_ceiling trips immediately ---
_safety_update_breaker "budget_ceiling"
result=$(jq -r '.budget_ceiling.tripped' "$_BREAKERS_FILE")
assert_equals "true" "$result" "budget_ceiling trips after update"

# --- Test 4: _safety_any_breaker_tripped detects tripped breaker ---
if _safety_any_breaker_tripped; then
    echo "PASS: _safety_any_breaker_tripped detects budget_ceiling"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_any_breaker_tripped should detect budget_ceiling" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: reset clears all breakers ---
_safety_reset_breakers
if _safety_any_breaker_tripped; then
    echo "FAIL: breakers should be clear after reset" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: all breakers clear after reset"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 6: error_cascade needs threshold failures to trip ---
_safety_reset_breakers
SAFETY_MAX_CONSECUTIVE_FAILURES=3
_safety_update_breaker "error_cascade"
result=$(jq -r '.error_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$result" "error_cascade not tripped after 1 failure"

_safety_update_breaker "error_cascade"
result=$(jq -r '.error_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$result" "error_cascade not tripped after 2 failures"

_safety_update_breaker "error_cascade"
result=$(jq -r '.error_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "true" "$result" "error_cascade trips at threshold (3)"

# --- Test 7: regression_cascade threshold ---
_safety_reset_breakers
SAFETY_MAX_CONSECUTIVE_REGRESSIONS=2
_safety_update_breaker "regression_cascade"
result=$(jq -r '.regression_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$result" "regression_cascade not tripped after 1"

_safety_update_breaker "regression_cascade"
result=$(jq -r '.regression_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "true" "$result" "regression_cascade trips at threshold (2)"

# --- Test 8: unknown breaker name returns error ---
if _safety_update_breaker "nonexistent_breaker" 2>/dev/null; then
    echo "FAIL: unknown breaker should return error" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: unknown breaker returns error"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 9: trip_count increments ---
_safety_reset_breakers
_safety_update_breaker "budget_ceiling"
_safety_update_breaker "budget_ceiling"
count=$(jq -r '.budget_ceiling.trip_count' "$_BREAKERS_FILE")
assert_equals "2" "$count" "budget_ceiling trip_count increments"

# --- Test 10: last_trip timestamp is set ---
result=$(jq -r '.budget_ceiling.last_trip' "$_BREAKERS_FILE")
assert_matches "$result" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "last_trip contains ISO timestamp"

# --- Test 11: breakers file recreated if missing ---
rm -f "$_BREAKERS_FILE"
_safety_ensure_breakers_file
assert_file_exists "$_BREAKERS_FILE" "breakers file recreated when missing"

# --- Test 12: corrupted breakers file is handled ---
echo "not json" > "$_BREAKERS_FILE"
# _safety_ensure_breakers_file only checks existence, but _safety_any_breaker_tripped
# should handle the jq failure gracefully via the || echo 0 fallback
if _safety_any_breaker_tripped 2>/dev/null; then
    echo "FAIL: corrupted breakers should not report tripped" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: corrupted breakers file handled gracefully"
    ((_TEST_PASS_COUNT++))
fi

test_summary
