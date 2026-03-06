#!/usr/bin/env bash
# tests/test_quorum_invoke.sh — Tests for spec-39 §2 _quorum_invoke_voter()
# Verifies that _quorum_invoke_voter() exists in automaton.sh with correct
# structure: accepts voter_name and proposal_json, references agent files,
# uses QUORUM_MODEL and QUORUM_MAX_TOKENS_PER_VOTER, and handles invalid
# output as abstain.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _quorum_invoke_voter function exists ---
grep_result=$(grep -c '^_quorum_invoke_voter()' "$script_file" || true)
assert_equals "1" "$grep_result" "_quorum_invoke_voter() function exists in automaton.sh"

# --- Test 2: Function accepts voter_name as first argument ---
grep_result=$(grep -A5 '^_quorum_invoke_voter()' "$script_file" | grep -c 'voter_name' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _quorum_invoke_voter accepts voter_name parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _quorum_invoke_voter should accept voter_name parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Function accepts proposal_json as second argument ---
grep_result=$(grep -A5 '^_quorum_invoke_voter()' "$script_file" | grep -c 'proposal_json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _quorum_invoke_voter accepts proposal_json parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _quorum_invoke_voter should accept proposal_json parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: References .claude/agents/voter- path ---
func_body=$(sed -n '/^_quorum_invoke_voter()/,/^[^ ]/p' "$script_file")
assert_contains "$func_body" "voter-" "_quorum_invoke_voter references voter agent file pattern"

# --- Test 5: Uses QUORUM_MODEL variable ---
assert_contains "$func_body" "QUORUM_MODEL" "_quorum_invoke_voter uses QUORUM_MODEL"

# --- Test 6: Uses QUORUM_MAX_TOKENS_PER_VOTER variable ---
assert_contains "$func_body" "QUORUM_MAX_TOKENS_PER_VOTER" "_quorum_invoke_voter uses QUORUM_MAX_TOKENS_PER_VOTER"

# --- Test 7: Invokes claude CLI ---
assert_contains "$func_body" "claude" "_quorum_invoke_voter invokes claude CLI"

# --- Test 8: Uses --print flag for text output ---
assert_contains "$func_body" "print" "_quorum_invoke_voter uses --print for text output"

# --- Test 9: Uses --max-tokens ---
assert_contains "$func_body" "max-tokens" "_quorum_invoke_voter uses --max-tokens"

# --- Test 10: Handles invalid JSON output as abstain ---
assert_contains "$func_body" "abstain" "_quorum_invoke_voter handles invalid output as abstain"

# --- Test 11: Returns JSON vote structure ---
assert_contains "$func_body" '"vote"' "_quorum_invoke_voter returns vote field"

# --- Test 12: Logs voter invocation ---
assert_contains "$func_body" "log" "_quorum_invoke_voter logs invocation"

# --- Test 13: _quorum_parse_vote function exists ---
grep_result=$(grep -c '^_quorum_parse_vote()' "$script_file" || true)
assert_equals "1" "$grep_result" "_quorum_parse_vote() helper function exists"

# --- Test 14: _quorum_parse_vote handles invalid JSON ---
parse_body=$(sed -n '/^_quorum_parse_vote()/,/^[^ ]/p' "$script_file")
assert_contains "$parse_body" "abstain" "_quorum_parse_vote returns abstain for invalid input"

test_summary
