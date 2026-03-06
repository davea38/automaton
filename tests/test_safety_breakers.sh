#!/usr/bin/env bash
# tests/test_safety_breakers.sh — Functional tests for spec-45 §2 circuit breakers
# Actually invokes breaker functions and verifies JSON state changes.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Set up isolated test directory
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-breakers-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"
_BREAKERS_FILE="$AUTOMATON_DIR/circuit-breakers.json"

# Mock log and _metrics_get_latest
LOG_OUTPUT=""
log() { LOG_OUTPUT+="[$1] $2"$'\n'; }
_metrics_get_latest() { echo ""; }

# Safety config defaults
SAFETY_MAX_CONSECUTIVE_FAILURES=3
SAFETY_MAX_CONSECUTIVE_REGRESSIONS=2
SAFETY_MAX_TOTAL_LINES=15000
SAFETY_MAX_TOTAL_FUNCTIONS=300
SAFETY_MIN_TEST_PASS_RATE=0.80

# Extract breaker functions from lib/safety.sh
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source_funcs() {
    local file="$PROJECT_DIR/lib/safety.sh"
    # We need these specific functions - extract them carefully
    eval "$(awk '
        /^_safety_init_breakers_file\(\)|^_safety_ensure_breakers_file\(\)|^_safety_check_breakers\(\)|^_safety_update_breaker\(\)|^_safety_any_breaker_tripped\(\)|^_safety_reset_breakers\(\)/ { found=1; depth=0 }
        found {
            for(i=1;i<=length($0);i++){
                c=substr($0,i,1)
                if(c=="{") depth++
                if(c=="}") depth--
            }
            print
            if(found && depth==0) { found=0; print "" }
        }
    ' "$file")"
}
source_funcs

# ============================================================
# Test _safety_init_breakers_file
# ============================================================

_safety_init_breakers_file
assert_file_exists "$_BREAKERS_FILE" "init creates breakers file"

content=$(cat "$_BREAKERS_FILE")
assert_json_valid "$content" "breakers file is valid JSON"
assert_json_field "$content" '.budget_ceiling.tripped' "false" "budget_ceiling starts un-tripped"
assert_json_field "$content" '.error_cascade.tripped' "false" "error_cascade starts un-tripped"
assert_json_field "$content" '.error_cascade.consecutive_failures' "0" "error_cascade starts at 0 failures"
assert_json_field "$content" '.regression_cascade.consecutive_regressions' "0" "regression_cascade starts at 0"
assert_json_field "$content" '.test_degradation.tripped' "false" "test_degradation starts un-tripped"

# ============================================================
# Test _safety_update_breaker — error_cascade increments
# ============================================================

LOG_OUTPUT=""
_safety_update_breaker "error_cascade"
failures=$(jq -r '.error_cascade.consecutive_failures' "$_BREAKERS_FILE")
assert_equals "1" "$failures" "first error_cascade update sets failures=1"

tripped=$(jq -r '.error_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$tripped" "1 failure does not trip error_cascade (threshold=3)"

_safety_update_breaker "error_cascade"
_safety_update_breaker "error_cascade"
tripped=$(jq -r '.error_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "true" "$tripped" "3 failures trips error_cascade"
assert_contains "$LOG_OUTPUT" "BREAKER TRIPPED: error_cascade" "trip logged"

# ============================================================
# Test _safety_any_breaker_tripped
# ============================================================

if _safety_any_breaker_tripped; then
    echo "PASS: _safety_any_breaker_tripped returns 0 when breaker is tripped"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_any_breaker_tripped should return 0 when a breaker is tripped" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# Test _safety_reset_breakers
# ============================================================

_safety_reset_breakers
tripped=$(jq -r '.error_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$tripped" "reset clears error_cascade"
failures=$(jq -r '.error_cascade.consecutive_failures' "$_BREAKERS_FILE")
assert_equals "0" "$failures" "reset zeroes failure count"

if _safety_any_breaker_tripped; then
    echo "FAIL: no breakers should be tripped after reset" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: no breakers tripped after reset"
    ((_TEST_PASS_COUNT++))
fi

# ============================================================
# Test _safety_update_breaker — budget_ceiling trips immediately
# ============================================================

_safety_reset_breakers
LOG_OUTPUT=""
_safety_update_breaker "budget_ceiling"
tripped=$(jq -r '.budget_ceiling.tripped' "$_BREAKERS_FILE")
assert_equals "true" "$tripped" "budget_ceiling trips on first update"
assert_contains "$LOG_OUTPUT" "BREAKER TRIPPED: budget_ceiling" "budget trip logged"

# ============================================================
# Test _safety_update_breaker — regression_cascade
# ============================================================

_safety_reset_breakers
_safety_update_breaker "regression_cascade"
tripped=$(jq -r '.regression_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "false" "$tripped" "1 regression does not trip (threshold=2)"

_safety_update_breaker "regression_cascade"
tripped=$(jq -r '.regression_cascade.tripped' "$_BREAKERS_FILE")
assert_equals "true" "$tripped" "2 regressions trips regression_cascade"

# ============================================================
# Test _safety_update_breaker — unknown breaker returns error
# ============================================================

rc=0
_safety_update_breaker "nonexistent_breaker" || rc=$?
assert_equals "1" "$rc" "unknown breaker name returns 1"

# ============================================================
# Test _safety_update_breaker — trip_count increments
# ============================================================

_safety_reset_breakers
_safety_update_breaker "complexity_ceiling"
_safety_update_breaker "complexity_ceiling"
count=$(jq -r '.complexity_ceiling.trip_count' "$_BREAKERS_FILE")
assert_equals "2" "$count" "complexity_ceiling trip_count increments"

test_summary
