#!/usr/bin/env bash
# tests/test_transition_to_phase.sh — Verify transition_to_phase() behavior
# Tests phase transition logic: history tracking, counter resets, sub-phase init.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"
setup_test_dir

# --- Verify transition_to_phase function structure ---

# Test 1: Function exists
assert_contains "$(grep -c 'transition_to_phase()' "$script_file")" "1" "transition_to_phase() defined exactly once"

# Test 2: Extract function body
fn_body=$(sed -n '/^transition_to_phase()/,/^[a-z_]*().*{/p' "$script_file" | head -60)

# Test 3: Updates phase_history via jq
assert_contains "$fn_body" "phase_history" "transition_to_phase updates phase_history"
assert_contains "$fn_body" "jq" "transition_to_phase uses jq to update history"

# Test 4: Resets phase_iteration to 0
assert_contains "$fn_body" "phase_iteration=0" "transition_to_phase resets phase_iteration"

# Test 5: Sets current_phase to new value
assert_contains "$fn_body" 'current_phase="$new_phase"' "transition_to_phase sets current_phase"

# Test 6: Calls write_state to persist
assert_contains "$fn_body" "write_state" "transition_to_phase persists state"

# Test 7: Generates context summary (spec-24)
assert_contains "$fn_body" "generate_context_summary" "transition_to_phase generates context summary"

# Test 8: Sends notification (spec-52)
assert_contains "$fn_body" "send_notification" "transition_to_phase sends notification"

# Test 9: Handles test-first build sub-phase (spec-36)
assert_contains "$fn_body" "build_sub_phase" "transition_to_phase initializes build sub-phase"
assert_contains "$fn_body" "scaffold" "transition_to_phase supports scaffold sub-phase"

# Test 10: Commits persistent state (spec-34)
assert_contains "$fn_body" "commit_persistent_state" "transition_to_phase commits persistent state"

# Test 11: Emits structured work log events (spec-55)
assert_contains "$fn_body" "emit_event" "transition_to_phase emits work log events"

# Test 12: Cleans up parallel plan prompt (spec-18)
assert_contains "$fn_body" "cleanup_parallel_plan_prompt" "transition_to_phase cleans up parallel prompt"

test_summary
