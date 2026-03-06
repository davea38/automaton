#!/usr/bin/env bash
# tests/test_state_roundtrip.sh — Verify write_state() -> read_state() round-trip
# Ensures all state fields survive serialization and deserialization intact,
# including the resumed_from fix (was previously reading last_iteration_at).
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"
setup_test_dir

# --- Setup minimal environment ---
AUTOMATON_DIR="$TEST_DIR/.automaton"
AUTOMATON_VERSION="0.1.0"
mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/worktrees" "$AUTOMATON_DIR/inbox" \
         "$AUTOMATON_DIR/run-summaries"
: > "$AUTOMATON_DIR/session.log"

# Source just the state module
source "$_PROJECT_DIR/lib/state.sh"

# --- Test 1: Basic round-trip (non-parallel) ---
PARALLEL_ENABLED="false"
current_phase="build"
iteration=7
phase_iteration=3
stall_count=2
consecutive_failures=1
corruption_count=0
replan_count=1
test_failure_count=4
build_sub_phase="implementation"
scaffold_iterations_done=2
started_at="2025-01-01T00:00:00Z"
resumed_from="2025-01-01T12:00:00Z"
phase_history='[{"phase":"research","completed_at":"2025-01-01T06:00:00Z"}]'

write_state

# Reset all variables to verify read_state restores them
current_phase="" iteration=0 phase_iteration=0 stall_count=0
consecutive_failures=99 corruption_count=0 replan_count=0
test_failure_count=0 build_sub_phase="" scaffold_iterations_done=0
started_at="" resumed_from="" phase_history="[]"

read_state

assert_equals "build" "$current_phase" "round-trip: current_phase"
assert_equals "7" "$iteration" "round-trip: iteration"
assert_equals "3" "$phase_iteration" "round-trip: phase_iteration"
assert_equals "2" "$stall_count" "round-trip: stall_count"
assert_equals "0" "$consecutive_failures" "round-trip: consecutive_failures reset to 0"
assert_equals "0" "$corruption_count" "round-trip: corruption_count"
assert_equals "1" "$replan_count" "round-trip: replan_count"
assert_equals "4" "$test_failure_count" "round-trip: test_failure_count"
assert_equals "implementation" "$build_sub_phase" "round-trip: build_sub_phase"
assert_equals "2" "$scaffold_iterations_done" "round-trip: scaffold_iterations_done"
assert_equals "2025-01-01T00:00:00Z" "$started_at" "round-trip: started_at"
assert_equals "2025-01-01T12:00:00Z" "$resumed_from" "round-trip: resumed_from preserves value"
assert_contains "$phase_history" "research" "round-trip: phase_history preserved"

# --- Test 2: resumed_from=null round-trip ---
resumed_from="null"
write_state
resumed_from="something"
read_state
assert_equals "null" "$resumed_from" "round-trip: resumed_from=null preserved"

# --- Test 3: Parallel mode round-trip ---
PARALLEL_ENABLED="true"
wave_number=3
wave_history='[{"wave":1,"status":"success"},{"wave":2,"status":"success"}]'
consecutive_wave_failures=1

write_state

wave_number=0 wave_history="[]" consecutive_wave_failures=0
read_state

assert_equals "3" "$wave_number" "parallel round-trip: wave_number"
assert_contains "$wave_history" '"wave":1' "parallel round-trip: wave_history"
assert_equals "1" "$consecutive_wave_failures" "parallel round-trip: consecutive_wave_failures"

# --- Test 4: state.json contains correct JSON structure ---
local_json=$(cat "$AUTOMATON_DIR/state.json")
assert_json_valid "$local_json" "state.json is valid JSON"
assert_json_field "$local_json" ".phase" "build" "JSON: phase field"
assert_json_field "$local_json" ".version" "0.1.0" "JSON: version field"

test_summary
