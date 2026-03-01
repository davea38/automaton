#!/usr/bin/env bash
# tests/test_evolve_config.sh — Tests for spec-41 §12 evolution configuration section
# Verifies that automaton.config.json contains the evolution section with correct defaults
# and that automaton.sh loads all evolution config values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.config.json contains evolution.enabled ---
val=$(jq -r '.evolution.enabled // "missing"' "$config_file")
assert_equals "false" "$val" "evolution.enabled defaults to false in config"

# --- Test 2: evolution.max_cycles ---
val=$(jq -r '.evolution.max_cycles // "missing"' "$config_file")
assert_equals "0" "$val" "evolution.max_cycles defaults to 0 (unlimited)"

# --- Test 3: evolution.max_cost_per_cycle_usd ---
val=$(jq -r '.evolution.max_cost_per_cycle_usd // "missing"' "$config_file")
assert_equals "5" "$val" "evolution.max_cost_per_cycle_usd defaults to 5.00"

# --- Test 4: evolution.convergence_threshold ---
val=$(jq -r '.evolution.convergence_threshold // "missing"' "$config_file")
assert_equals "5" "$val" "evolution.convergence_threshold defaults to 5"

# --- Test 5: evolution.idle_garden_threshold ---
val=$(jq -r '.evolution.idle_garden_threshold // "missing"' "$config_file")
assert_equals "3" "$val" "evolution.idle_garden_threshold defaults to 3"

# --- Test 6: evolution.branch_prefix ---
val=$(jq -r '.evolution.branch_prefix // "missing"' "$config_file")
assert_equals "automaton/evolve-" "$val" "evolution.branch_prefix defaults to automaton/evolve-"

# --- Test 7: evolution.auto_merge ---
val=$(jq -r '.evolution.auto_merge // "missing"' "$config_file")
assert_equals "true" "$val" "evolution.auto_merge defaults to true"

# --- Test 8: evolution.reflect_model ---
val=$(jq -r '.evolution.reflect_model // "missing"' "$config_file")
assert_equals "sonnet" "$val" "evolution.reflect_model defaults to sonnet"

# --- Test 9: evolution.ideate_model ---
val=$(jq -r '.evolution.ideate_model // "missing"' "$config_file")
assert_equals "sonnet" "$val" "evolution.ideate_model defaults to sonnet"

# --- Test 10: evolution.observe_model ---
val=$(jq -r '.evolution.observe_model // "missing"' "$config_file")
assert_equals "sonnet" "$val" "evolution.observe_model defaults to sonnet"

# --- Test 11: automaton.sh reads EVOLVE_ENABLED from config ---
grep_result=$(grep -c 'EVOLVE_ENABLED.*jq.*evolution.enabled' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_ENABLED from evolution.enabled config"

# --- Test 12: automaton.sh reads EVOLVE_MAX_CYCLES ---
grep_result=$(grep -c 'EVOLVE_MAX_CYCLES.*jq.*evolution.max_cycles' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_MAX_CYCLES"

# --- Test 13: automaton.sh reads EVOLVE_MAX_COST_PER_CYCLE ---
grep_result=$(grep -c 'EVOLVE_MAX_COST_PER_CYCLE.*jq.*evolution.max_cost_per_cycle_usd' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_MAX_COST_PER_CYCLE"

# --- Test 14: automaton.sh reads EVOLVE_CONVERGENCE_THRESHOLD ---
grep_result=$(grep -c 'EVOLVE_CONVERGENCE_THRESHOLD.*jq.*evolution.convergence_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_CONVERGENCE_THRESHOLD"

# --- Test 15: automaton.sh reads EVOLVE_IDLE_GARDEN_THRESHOLD ---
grep_result=$(grep -c 'EVOLVE_IDLE_GARDEN_THRESHOLD.*jq.*evolution.idle_garden_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_IDLE_GARDEN_THRESHOLD"

# --- Test 16: automaton.sh reads EVOLVE_BRANCH_PREFIX ---
grep_result=$(grep -c 'EVOLVE_BRANCH_PREFIX.*jq.*evolution.branch_prefix' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_BRANCH_PREFIX"

# --- Test 17: automaton.sh reads EVOLVE_AUTO_MERGE ---
grep_result=$(grep -c 'EVOLVE_AUTO_MERGE.*jq.*evolution.auto_merge' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_AUTO_MERGE"

# --- Test 18: automaton.sh reads EVOLVE_REFLECT_MODEL ---
grep_result=$(grep -c 'EVOLVE_REFLECT_MODEL.*jq.*evolution.reflect_model' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_REFLECT_MODEL"

# --- Test 19: automaton.sh reads EVOLVE_IDEATE_MODEL ---
grep_result=$(grep -c 'EVOLVE_IDEATE_MODEL.*jq.*evolution.ideate_model' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_IDEATE_MODEL"

# --- Test 20: automaton.sh reads EVOLVE_OBSERVE_MODEL ---
grep_result=$(grep -c 'EVOLVE_OBSERVE_MODEL.*jq.*evolution.observe_model' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads EVOLVE_OBSERVE_MODEL"

# --- Test 21: automaton.sh has EVOLVE_ENABLED default in else branch ---
grep_result=$(grep -c 'EVOLVE_ENABLED="false"' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has EVOLVE_ENABLED default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have EVOLVE_ENABLED default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 22: automaton.sh has EVOLVE_MAX_CYCLES default in else branch ---
grep_result=$(grep -c 'EVOLVE_MAX_CYCLES=0' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has EVOLVE_MAX_CYCLES default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have EVOLVE_MAX_CYCLES default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 23: automaton.sh has EVOLVE_CONVERGENCE_THRESHOLD default ---
grep_result=$(grep -c 'EVOLVE_CONVERGENCE_THRESHOLD=5' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has EVOLVE_CONVERGENCE_THRESHOLD default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have EVOLVE_CONVERGENCE_THRESHOLD default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
