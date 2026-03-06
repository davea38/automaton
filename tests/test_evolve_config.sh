#!/usr/bin/env bash
# tests/test_evolve_config.sh — Tests for spec-41 §12 evolution configuration section
# Verifies that automaton.config.json contains the evolution section with correct defaults
# and that automaton.sh loads all evolution config values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"

# --- Test 1: automaton.config.json contains evolution.enabled ---
# Note: jq's // treats false as falsy, so use 'type' to confirm the key exists
val=$(jq -r '.evolution.enabled | type' "$config_file")
assert_equals "boolean" "$val" "evolution.enabled exists as boolean in config"

# --- Test 2: evolution.max_cycles ---
val=$(jq -r '.evolution.max_cycles // "missing"' "$config_file")
assert_equals "0" "$val" "evolution.max_cycles defaults to 0 (unlimited)"

# --- Test 3: evolution.max_cost_per_cycle_usd ---
val=$(jq -r '.evolution.max_cost_per_cycle_usd // "missing"' "$config_file")
assert_equals "5.00" "$val" "evolution.max_cost_per_cycle_usd defaults to 5.00"

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

# --- Test 11-20: load_config() sets EVOLVE_* variables from config ---
(
    source "$_PROJECT_DIR/lib/config.sh"
    CONFIG_FILE="$config_file" load_config
    assert_equals "false" "$EVOLVE_ENABLED" "load_config sets EVOLVE_ENABLED"
    assert_equals "0" "$EVOLVE_MAX_CYCLES" "load_config sets EVOLVE_MAX_CYCLES"
    assert_equals "5.00" "$EVOLVE_MAX_COST_PER_CYCLE" "load_config sets EVOLVE_MAX_COST_PER_CYCLE"
    assert_equals "5" "$EVOLVE_CONVERGENCE_THRESHOLD" "load_config sets EVOLVE_CONVERGENCE_THRESHOLD"
    assert_equals "3" "$EVOLVE_IDLE_GARDEN_THRESHOLD" "load_config sets EVOLVE_IDLE_GARDEN_THRESHOLD"
    assert_equals "automaton/evolve-" "$EVOLVE_BRANCH_PREFIX" "load_config sets EVOLVE_BRANCH_PREFIX"
    assert_equals "true" "$EVOLVE_AUTO_MERGE" "load_config sets EVOLVE_AUTO_MERGE"
    assert_equals "sonnet" "$EVOLVE_REFLECT_MODEL" "load_config sets EVOLVE_REFLECT_MODEL"
    assert_equals "sonnet" "$EVOLVE_IDEATE_MODEL" "load_config sets EVOLVE_IDEATE_MODEL"
    assert_equals "sonnet" "$EVOLVE_OBSERVE_MODEL" "load_config sets EVOLVE_OBSERVE_MODEL"
)

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
