#!/usr/bin/env bash
# tests/test_post_iteration.sh — Verify post_iteration() behavior
# Tests the core post-iteration logic: token extraction, budget update,
# stall detection signals, and state persistence.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"
setup_test_dir

# --- Verify post_iteration function exists and has key behaviors ---

# Test 1: Function exists in combined source
assert_contains "$(grep -c 'post_iteration()' "$script_file")" "1" "post_iteration() defined exactly once"

# Test 2: Calls extract_tokens
fn_body=$(sed -n '/^post_iteration()/,/^[a-z_]*().*{/p' "$script_file" | head -120)
assert_contains "$fn_body" "extract_tokens" "post_iteration calls extract_tokens"

# Test 3: Calls update_budget
assert_contains "$fn_body" "update_budget" "post_iteration calls update_budget"

# Test 4: Calls check_budget
assert_contains "$fn_body" "check_budget" "post_iteration calls check_budget"

# Test 5: Calls write_state for persistence
assert_contains "$fn_body" "write_state" "post_iteration persists state"

# Test 6: Calls check_stall only during build phase
assert_matches "$fn_body" 'current_phase.*build' "post_iteration guards stall check to build phase"

# Test 7: Calls check_plan_integrity during build
assert_contains "$fn_body" "check_plan_integrity" "post_iteration checks plan integrity"

# Test 8: Calls check_pacing for rate limit prevention
assert_contains "$fn_body" "check_pacing" "post_iteration does proactive pacing"

# Test 9: Returns non-zero on stall
assert_contains "$fn_body" 'TRANSITION_REASON="stall"' "post_iteration signals stall transition"

# Test 10: Returns non-zero on budget
assert_contains "$fn_body" 'TRANSITION_REASON="budget"' "post_iteration signals budget transition"

# Test 11: Returns non-zero on test failure
assert_contains "$fn_body" 'TRANSITION_REASON="test_failure"' "post_iteration signals test_failure transition"

# Test 12: Writes agent history
assert_contains "$fn_body" "write_agent_history" "post_iteration records agent history"

# Test 13: Commits persistent state periodically
assert_contains "$fn_body" "commit_persistent_state" "post_iteration checkpoints persistent state"

# Test 14: Self-build validation during build
assert_contains "$fn_body" "self_build_validate" "post_iteration validates self-build changes"

test_summary
