#!/usr/bin/env bash
# tests/test_evolve_evaluate.sh — Tests for spec-41 §5 EVALUATE phase
# Verifies _evolve_evaluate() in automaton.sh selects the highest-priority
# bloom candidate, invokes _quorum_evaluate_bloom(), and writes evaluate.json
# to the cycle directory; skips to OBSERVE if no bloom candidates exist.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_evaluate function ---
grep_result=$(grep -c '^_evolve_evaluate()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_evaluate()"

# --- Test 2: _evolve_evaluate takes a cycle_id parameter ---
grep_result=$(grep -A 5 '^_evolve_evaluate()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate takes cycle_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should take cycle_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_evaluate creates or references the cycle directory ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'mkdir.*cycle\|cycle_dir' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate creates or references cycle directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should create or reference cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_evaluate calls _garden_get_bloom_candidates ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c '_garden_get_bloom_candidates' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate calls _garden_get_bloom_candidates"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should call _garden_get_bloom_candidates" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_evaluate calls _quorum_evaluate_bloom ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c '_quorum_evaluate_bloom' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate calls _quorum_evaluate_bloom"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should call _quorum_evaluate_bloom" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_evaluate writes evaluate.json output ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'evaluate\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate writes evaluate.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should write evaluate.json to cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_evaluate handles no bloom candidates gracefully ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'no.*bloom\|No.*bloom\|skip\|SKIP' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate handles no bloom candidates (skip to OBSERVE)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should handle no bloom candidates gracefully" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_evaluate uses log function for reporting ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'log "EVOLVE"' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_evaluate uses log function for reporting (at least 2 log calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should use log function for reporting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: evaluate.json output includes required fields ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'bloom_candidates_count\|evaluated\|vote_id\|result\|conditions\|tokens_used' || true)
if [ "$grep_result" -ge 4 ]; then
    echo "PASS: evaluate.json includes required output fields"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: evaluate.json should include bloom_candidates_count, evaluated, vote_id, result, conditions, tokens_used" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_evaluate reads ideate.json for bloom candidates context ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'ideate\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate reads ideate.json for bloom candidates context"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should read ideate.json from IDEATE phase" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _evolve_evaluate tracks token usage ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'tokens_used\|_QUORUM_CYCLE_TOKENS' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_evaluate tracks token usage"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should track token usage for budget awareness" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: _evolve_evaluate extracts vote result from quorum ---
grep_result=$(grep -A 120 '^_evolve_evaluate()' "$script_file" | grep -c 'approved\|rejected\|result' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_evaluate extracts vote result"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_evaluate should extract vote result (approved/rejected)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
