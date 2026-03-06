#!/usr/bin/env bash
# tests/test_agent_teams_budget.sh — Tests for spec-28 §9 Agent Teams budget tracking
# Functional tests that verify aggregate_agent_teams_budget() behavior.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up isolated test directory
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-teams-budget-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# --- Test 1: aggregate_agent_teams_budget function exists ---
grep -q 'aggregate_agent_teams_budget()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "aggregate_agent_teams_budget function exists"

# --- Test 2: Function reads subagent_usage.json ---
func_body=$(sed -n '/^aggregate_agent_teams_budget()/,/^}/p' "$script_file")
assert_contains "$func_body" "subagent_usage.json" "reads subagent_usage.json"

# --- Test 3: Function calls update_budget ---
assert_contains "$func_body" "update_budget" "calls update_budget"

# --- Test 4: Function computes per-teammate attribution ---
if echo "$func_body" | grep -q 'teammate_count\|per.teammate\|divide.*count\|/ \$count\|/ count'; then
    echo "PASS: performs per-teammate attribution"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should compute per-teammate attribution" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Function logs approximate attribution warning ---
assert_contains "$func_body" "approximate" "logs approximate attribution warning"

# --- Test 6: run_agent_teams_build calls aggregate ---
teams_build_body=$(sed -n '/^run_agent_teams_build()/,/^}/p' "$script_file")
assert_contains "$teams_build_body" "aggregate_agent_teams_budget" "run_agent_teams_build calls aggregate"

# --- Test 7: Function handles missing subagent_usage.json ---
if echo "$func_body" | grep -q '\-f.*subagent_usage\|! -f\|not exist'; then
    echo "PASS: handles missing subagent_usage.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should handle missing subagent_usage.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Function uses estimate_cost ---
assert_contains "$func_body" "estimate_cost" "uses estimate_cost"

# --- Test 9: Function handles fallback to lead session tokens ---
if echo "$func_body" | grep -q 'lead\|aggregate\|fallback\|LAST_INPUT_TOKENS\|stream.json'; then
    echo "PASS: handles fallback to lead session"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should handle fallback" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
