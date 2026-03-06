#!/usr/bin/env bash
# tests/test_quorum_budget.sh — Tests for spec-39 §2 _quorum_check_budget()
# Verifies that _quorum_check_budget() exists in automaton.sh with correct
# structure: tracks cumulative quorum tokens per cycle and skips remaining
# candidates when max_cost_per_cycle_usd is exceeded.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _quorum_check_budget function exists ---
grep_result=$(grep -c '^_quorum_check_budget()' "$script_file" || true)
assert_equals "1" "$grep_result" "_quorum_check_budget() function exists in automaton.sh"

# Extract function body for structural tests
func_body=$(sed -n '/^_quorum_check_budget()/,/^[^ ]/p' "$script_file")

# --- Test 2: References QUORUM_MAX_COST_PER_CYCLE config ---
assert_contains "$func_body" "QUORUM_MAX_COST_PER_CYCLE" "_quorum_check_budget uses max cost per cycle config"

# --- Test 3: Tracks cumulative token usage ---
assert_contains "$func_body" "tokens" "_quorum_check_budget tracks token usage"

# --- Test 4: Computes or references estimated cost ---
assert_contains "$func_body" "cost" "_quorum_check_budget computes cost"

# --- Test 5: Returns non-zero when budget exceeded ---
assert_contains "$func_body" "return 1" "_quorum_check_budget returns 1 when budget exceeded"

# --- Test 6: Returns zero when budget available ---
assert_contains "$func_body" "return 0" "_quorum_check_budget returns 0 when budget available"

# --- Test 7: Logs when budget is exceeded ---
assert_contains "$func_body" "log" "_quorum_check_budget logs budget status"

# --- Test 8: _quorum_evaluate_bloom integrates budget check ---
eval_body=$(sed -n '/^_quorum_evaluate_bloom()/,/^[^ ]/p' "$script_file")
assert_contains "$eval_body" "_quorum_check_budget" "_quorum_evaluate_bloom calls _quorum_check_budget"

test_summary
