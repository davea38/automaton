#!/usr/bin/env bash
# tests/test_quorum_evaluate.sh — Tests for spec-39 §2 _quorum_evaluate_bloom()
# Verifies that _quorum_evaluate_bloom() exists in automaton.sh with correct
# structure: selects highest-priority bloom candidate, assembles proposal context,
# invokes all 5 voters sequentially, tallies votes, writes vote record to
# .automaton/votes/vote-{NNN}.json, and advances/wilts the idea based on result.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _quorum_evaluate_bloom function exists ---
grep_result=$(grep -c '^_quorum_evaluate_bloom()' "$script_file" || true)
assert_equals "1" "$grep_result" "_quorum_evaluate_bloom() function exists in automaton.sh"

# Extract function body for structural tests
func_body=$(sed -n '/^_quorum_evaluate_bloom()/,/^[^ ]/p' "$script_file")

# --- Test 2: Calls _garden_get_bloom_candidates ---
assert_contains "$func_body" "_garden_get_bloom_candidates" "_quorum_evaluate_bloom calls _garden_get_bloom_candidates"

# --- Test 3: Reads idea file to assemble proposal context ---
assert_contains "$func_body" "idea_file" "_quorum_evaluate_bloom reads idea file for proposal"

# --- Test 4: Assembles proposal JSON with idea details ---
assert_contains "$func_body" "proposal" "_quorum_evaluate_bloom assembles proposal context"

# --- Test 5: Iterates over voters ---
assert_contains "$func_body" "QUORUM_VOTERS" "_quorum_evaluate_bloom iterates over configured voters"

# --- Test 6: Calls _quorum_invoke_voter ---
assert_contains "$func_body" "_quorum_invoke_voter" "_quorum_evaluate_bloom invokes voters"

# --- Test 7: Calls _quorum_tally ---
assert_contains "$func_body" "_quorum_tally" "_quorum_evaluate_bloom tallies votes"

# --- Test 8: Uses bloom_implementation decision type ---
assert_contains "$func_body" "bloom_implementation" "_quorum_evaluate_bloom uses bloom_implementation decision type"

# --- Test 9: Writes vote record to .automaton/votes/ ---
assert_contains "$func_body" "votes_dir" "_quorum_evaluate_bloom writes to votes directory"

# --- Test 10: Vote record is JSON ---
assert_contains "$func_body" "jq" "_quorum_evaluate_bloom produces JSON vote record"

# --- Test 11: Records vote_id ---
assert_contains "$func_body" "vote_id" "_quorum_evaluate_bloom records vote ID"

# --- Test 12: Handles approved result — advances idea ---
assert_contains "$func_body" "_garden_advance_stage" "_quorum_evaluate_bloom advances idea on approval"

# --- Test 13: Handles rejected result — wilts idea ---
assert_contains "$func_body" "_garden_wilt" "_quorum_evaluate_bloom wilts idea on rejection"

# --- Test 14: Logs quorum evaluation ---
assert_contains "$func_body" "log" "_quorum_evaluate_bloom logs the evaluation"

# --- Test 15: Returns when no bloom candidates exist ---
assert_contains "$func_body" "No bloom candidates" "_quorum_evaluate_bloom handles no bloom candidates"

# --- Test 16: Records per-voter votes in the vote record ---
assert_contains "$func_body" "votes" "_quorum_evaluate_bloom records per-voter votes"

test_summary
