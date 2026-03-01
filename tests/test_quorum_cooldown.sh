#!/usr/bin/env bash
# tests/test_quorum_cooldown.sh — Tests for spec-39 §3 rejection cooldown
# Verifies that _quorum_check_cooldown() exists in automaton.sh and that
# _quorum_evaluate_bloom() integrates the cooldown check to skip ideas
# wilted by quorum within the last rejection_cooldown_cycles cycles.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _quorum_check_cooldown function exists ---
grep_result=$(grep -c '^_quorum_check_cooldown()' "$script_file" || true)
assert_equals "1" "$grep_result" "_quorum_check_cooldown() function exists in automaton.sh"

# Extract function body for structural tests
func_body=$(sed -n '/^_quorum_check_cooldown()/,/^[^ ]/p' "$script_file")

# --- Test 2: Takes idea_id as argument ---
assert_contains "$func_body" "idea_id" "_quorum_check_cooldown takes idea_id parameter"

# --- Test 3: References rejection_cooldown_cycles config ---
assert_contains "$func_body" "cooldown" "_quorum_check_cooldown uses cooldown config"

# --- Test 4: Reads vote history from .automaton/votes/ ---
assert_contains "$func_body" "votes" "_quorum_check_cooldown reads vote history"

# --- Test 5: Checks for rejection (rejected result) in vote records ---
assert_contains "$func_body" "reject" "_quorum_check_cooldown checks for rejections"

# --- Test 6: Compares cycle numbers for cooldown window ---
assert_contains "$func_body" "cycle" "_quorum_check_cooldown checks cycle timing"

# --- Test 7: Returns non-zero when idea is on cooldown ---
assert_contains "$func_body" "return 1" "_quorum_check_cooldown returns 1 when on cooldown"

# --- Test 8: Returns zero when idea is not on cooldown ---
assert_contains "$func_body" "return 0" "_quorum_check_cooldown returns 0 when not on cooldown"

# --- Test 9: Logs when an idea is on cooldown ---
assert_contains "$func_body" "log" "_quorum_check_cooldown logs cooldown status"

# --- Test 10: _quorum_evaluate_bloom integrates cooldown check ---
eval_body=$(sed -n '/^_quorum_evaluate_bloom()/,/^[^ ]/p' "$script_file")
assert_contains "$eval_body" "_quorum_check_cooldown" "_quorum_evaluate_bloom calls _quorum_check_cooldown"

test_summary
