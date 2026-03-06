#!/usr/bin/env bash
# tests/test_safety_behavioral.sh — Behavioral tests for lib/safety.sh circuit breakers.
# Actually executes safety functions and verifies state changes in breaker files.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
setup_test_dir

# Minimal stubs
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR/evolution"
log() { :; }
emit_event() { :; }
_garden_wilt() { :; }
_signal_emit() { :; }
_metrics_get_latest() { echo ""; }

# Safety config defaults
SAFETY_MAX_CONSECUTIVE_FAILURES=3
SAFETY_MAX_CONSECUTIVE_REGRESSIONS=2
SAFETY_MAX_TOTAL_LINES=15000
SAFETY_MAX_TOTAL_FUNCTIONS=300
SAFETY_MIN_TEST_PASS_RATE="0.80"
SAFETY_PREFLIGHT_ENABLED="true"
SAFETY_SANDBOX_TESTING_ENABLED="true"
SELF_BUILD_PROTECTED_FUNCTIONS="run_orchestration,_handle_shutdown"

# Source the safety module
source "$_PROJECT_DIR/lib/safety.sh"

# --- Test 1: _safety_init_breakers_file creates valid JSON ---
_BREAKERS_FILE="$AUTOMATON_DIR/evolution/circuit-breakers.json"
_safety_init_breakers_file
assert_file_exists "$_BREAKERS_FILE" "init_breakers_file creates breakers file"
breakers=$(cat "$_BREAKERS_FILE")
assert_json_valid "$breakers" "breakers file is valid JSON"
assert_json_field "$breakers" '.budget_ceiling.tripped' "false" "budget_ceiling starts un-tripped"
assert_json_field "$breakers" '.error_cascade.tripped' "false" "error_cascade starts un-tripped"
assert_json_field "$breakers" '.error_cascade.consecutive_failures' "0" "error_cascade starts at 0 failures"

# --- Test 2: _safety_update_breaker increments error_cascade ---
_safety_update_breaker "error_cascade"
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.error_cascade.consecutive_failures' "1" "error_cascade incremented to 1"
assert_json_field "$breakers" '.error_cascade.tripped' "false" "error_cascade not yet tripped at 1"

# --- Test 3: _safety_update_breaker trips error_cascade at threshold ---
_safety_update_breaker "error_cascade"
_safety_update_breaker "error_cascade"
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.error_cascade.consecutive_failures' "3" "error_cascade at 3 failures"
assert_json_field "$breakers" '.error_cascade.tripped' "true" "error_cascade tripped at threshold"

# --- Test 4: _safety_any_breaker_tripped detects tripped breaker ---
_safety_any_breaker_tripped
assert_exit_code 0 $? "any_breaker_tripped returns 0 when breaker is tripped"

# --- Test 5: _safety_reset_breakers clears all ---
_safety_reset_breakers
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.error_cascade.tripped' "false" "reset clears error_cascade"
assert_json_field "$breakers" '.error_cascade.consecutive_failures' "0" "reset zeros error_cascade counter"

_safety_any_breaker_tripped && rc=0 || rc=1
assert_exit_code 1 "$rc" "any_breaker_tripped returns 1 after reset"

# --- Test 6: _safety_update_breaker regression_cascade ---
_safety_reset_breakers
_safety_update_breaker "regression_cascade"
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.regression_cascade.consecutive_regressions' "1" "regression_cascade incremented"
_safety_update_breaker "regression_cascade"
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.regression_cascade.tripped' "true" "regression_cascade tripped at 2"

# --- Test 7: _safety_update_breaker budget_ceiling trips immediately ---
_safety_reset_breakers
_safety_update_breaker "budget_ceiling"
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.budget_ceiling.tripped' "true" "budget_ceiling trips immediately"
assert_json_field "$breakers" '.budget_ceiling.trip_count' "1" "budget_ceiling trip_count is 1"

# --- Test 8: _safety_update_breaker rejects unknown breaker ---
result=$(_safety_update_breaker "nonexistent_breaker" 2>&1) || rc=$?
assert_exit_code 1 "${rc:-0}" "unknown breaker returns 1"

# --- Test 9: _safety_branch_get_name formats correctly ---
name=$(_safety_branch_get_name "001" "42")
assert_equals "automaton/evolve-001-42" "$name" "branch name formatted correctly"

# --- Test 10: _safety_check_breakers detects complexity ceiling ---
_safety_reset_breakers
# Create a fake automaton.sh that exceeds the line limit
SAFETY_MAX_TOTAL_LINES=10
cd "$TEST_DIR"
for i in $(seq 1 20); do echo "line$i" >> automaton.sh; done
_safety_check_breakers
breakers=$(cat "$_BREAKERS_FILE")
assert_json_field "$breakers" '.complexity_ceiling.tripped' "true" "complexity ceiling tripped on oversized file"
SAFETY_MAX_TOTAL_LINES=15000

cd "$SCRIPT_DIR/.."
test_summary
