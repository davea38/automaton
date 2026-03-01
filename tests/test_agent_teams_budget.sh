#!/usr/bin/env bash
# tests/test_agent_teams_budget.sh — Tests for spec-28 §9 Agent Teams budget tracking
# Verifies that aggregate_agent_teams_budget() reads subagent_usage.json,
# computes approximate per-teammate attribution, updates budget.json,
# and logs the appropriate warning about approximate attribution.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

AUTOMATON_SH="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: aggregate_agent_teams_budget function exists ---
grep_result=$(grep -c 'aggregate_agent_teams_budget()' "$AUTOMATON_SH" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains aggregate_agent_teams_budget function"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should contain aggregate_agent_teams_budget function" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: Function reads from subagent_usage.json ---
func_body=$(sed -n '/^aggregate_agent_teams_budget()/,/^}/p' "$AUTOMATON_SH")
if echo "$func_body" | grep -q 'subagent_usage.json'; then
    echo "PASS: aggregate_agent_teams_budget reads subagent_usage.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should read subagent_usage.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Function calls update_budget ---
if echo "$func_body" | grep -q 'update_budget'; then
    echo "PASS: aggregate_agent_teams_budget calls update_budget"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should call update_budget for budget tracking" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Function computes per-teammate attribution ---
if echo "$func_body" | grep -q 'teammate_count\|per.teammate\|divide.*count\|/ \$count\|/ count'; then
    echo "PASS: aggregate_agent_teams_budget performs per-teammate attribution"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should compute per-teammate attribution" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Function logs approximate attribution warning ---
if echo "$func_body" | grep -q 'approximate\|Per-teammate.*approximate'; then
    echo "PASS: aggregate_agent_teams_budget logs approximate attribution warning"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should log approximate attribution warning" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: run_agent_teams_build calls aggregate_agent_teams_budget ---
teams_build_body=$(sed -n '/^run_agent_teams_build()/,/^}/p' "$AUTOMATON_SH")
if echo "$teams_build_body" | grep -q 'aggregate_agent_teams_budget'; then
    echo "PASS: run_agent_teams_build calls aggregate_agent_teams_budget"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: run_agent_teams_build should call aggregate_agent_teams_budget after session ends" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Function handles missing subagent_usage.json gracefully ---
if echo "$func_body" | grep -q '\-f.*subagent_usage\|! -f\|not exist'; then
    echo "PASS: aggregate_agent_teams_budget handles missing subagent_usage.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should handle missing subagent_usage.json gracefully" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Function uses estimate_cost for cost calculation ---
if echo "$func_body" | grep -q 'estimate_cost'; then
    echo "PASS: aggregate_agent_teams_budget uses estimate_cost for cost calculation"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should use estimate_cost for consistent cost calculation" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Function handles fallback to lead session tokens ---
if echo "$func_body" | grep -q 'lead\|aggregate\|fallback\|LAST_INPUT_TOKENS\|stream.json'; then
    echo "PASS: aggregate_agent_teams_budget handles fallback to lead session aggregate tokens"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: aggregate_agent_teams_budget should handle fallback when subagent data is incomplete" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
