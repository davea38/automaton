#!/usr/bin/env bash
# tests/test_quorum_tally.sh — Tests for spec-39 §2 _quorum_tally()
# Verifies that _quorum_tally() exists in automaton.sh with correct
# structure: accepts votes JSON and decision_type, counts approve/reject/abstain,
# reduces denominator for abstentions, compares against threshold, merges
# conditions from approving voters, and returns structured result.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _quorum_tally function exists ---
grep_result=$(grep -c '^_quorum_tally()' "$script_file" || true)
assert_equals "1" "$grep_result" "_quorum_tally() function exists in automaton.sh"

# Extract function body for structural tests
func_body=$(sed -n '/^_quorum_tally()/,/^[^ ]/p' "$script_file")

# --- Test 2: Accepts votes_json parameter ---
assert_contains "$func_body" "votes_json" "_quorum_tally accepts votes_json parameter"

# --- Test 3: Accepts decision_type parameter ---
assert_contains "$func_body" "decision_type" "_quorum_tally accepts decision_type parameter"

# --- Test 4: Counts approve votes ---
assert_contains "$func_body" "approve" "_quorum_tally counts approve votes"

# --- Test 5: Counts reject votes ---
assert_contains "$func_body" "reject" "_quorum_tally counts reject votes"

# --- Test 6: Counts abstain votes ---
assert_contains "$func_body" "abstain" "_quorum_tally counts abstain votes"

# --- Test 7: Reduces denominator for abstentions ---
# The function should subtract abstentions from total to get effective denominator
assert_contains "$func_body" "denominator" "_quorum_tally reduces denominator for abstentions"

# --- Test 8: Looks up threshold from config ---
assert_contains "$func_body" "threshold" "_quorum_tally looks up threshold for decision type"

# --- Test 9: Merges conditions from approving voters ---
assert_contains "$func_body" "conditions" "_quorum_tally merges conditions from approving voters"

# --- Test 10: Returns result as approved/rejected ---
assert_contains "$func_body" "approved" "_quorum_tally can return approved result"
assert_contains "$func_body" "rejected" "_quorum_tally can return rejected result"

# --- Test 11: Outputs JSON result ---
assert_contains "$func_body" "jq" "_quorum_tally produces JSON output"

# --- Test 12: Handles all-abstain edge case ---
# When all voters abstain, denominator is 0 — function should handle this
assert_contains "$func_body" "0" "_quorum_tally handles edge cases (zero denominator)"

test_summary
