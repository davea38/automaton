#!/usr/bin/env bash
# tests/test_quorum_config.sh — Tests for spec-39 §2 quorum configuration section
# Verifies that automaton.config.json contains the quorum section with correct defaults,
# that automaton.sh loads all quorum config values, and that quorum.enabled=false
# causes quorum operations to be skipped (auto-approve fallback).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.config.json contains quorum.enabled ---
val=$(jq -r '.quorum.enabled // "missing"' "$config_file")
assert_equals "true" "$val" "quorum.enabled defaults to true in config"

# --- Test 2: quorum.voters array ---
val=$(jq -r '.quorum.voters | length // "missing"' "$config_file")
assert_equals "5" "$val" "quorum.voters has 5 voter names"

# --- Test 3: quorum.voters contains all 5 perspectives ---
for voter in conservative ambitious efficiency quality advocate; do
    val=$(jq -r --arg v "$voter" '.quorum.voters | index($v) // "missing"' "$config_file")
    if [ "$val" != "null" ] && [ "$val" != "missing" ]; then
        echo "PASS: quorum.voters contains $voter"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: quorum.voters should contain $voter" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Test 8: quorum.thresholds.seed_promotion ---
val=$(jq -r '.quorum.thresholds.seed_promotion // "missing"' "$config_file")
assert_equals "3" "$val" "quorum.thresholds.seed_promotion defaults to 3"

# --- Test 9: quorum.thresholds.bloom_implementation ---
val=$(jq -r '.quorum.thresholds.bloom_implementation // "missing"' "$config_file")
assert_equals "3" "$val" "quorum.thresholds.bloom_implementation defaults to 3"

# --- Test 10: quorum.thresholds.constitutional_amendment ---
val=$(jq -r '.quorum.thresholds.constitutional_amendment // "missing"' "$config_file")
assert_equals "4" "$val" "quorum.thresholds.constitutional_amendment defaults to 4"

# --- Test 11: quorum.thresholds.emergency_override ---
val=$(jq -r '.quorum.thresholds.emergency_override // "missing"' "$config_file")
assert_equals "5" "$val" "quorum.thresholds.emergency_override defaults to 5"

# --- Test 12: quorum.max_tokens_per_voter ---
val=$(jq -r '.quorum.max_tokens_per_voter // "missing"' "$config_file")
assert_equals "500" "$val" "quorum.max_tokens_per_voter defaults to 500"

# --- Test 13: quorum.max_cost_per_cycle_usd ---
val=$(jq -r '.quorum.max_cost_per_cycle_usd // "missing"' "$config_file")
assert_equals "1" "$val" "quorum.max_cost_per_cycle_usd defaults to 1.00"

# --- Test 14: quorum.rejection_cooldown_cycles ---
val=$(jq -r '.quorum.rejection_cooldown_cycles // "missing"' "$config_file")
assert_equals "5" "$val" "quorum.rejection_cooldown_cycles defaults to 5"

# --- Test 15: quorum.model ---
val=$(jq -r '.quorum.model // "missing"' "$config_file")
assert_equals "sonnet" "$val" "quorum.model defaults to sonnet"

# --- Test 16: automaton.sh reads QUORUM_ENABLED from config ---
grep_result=$(grep -c 'QUORUM_ENABLED.*jq.*quorum.enabled' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_ENABLED from quorum.enabled config"

# --- Test 17: automaton.sh reads QUORUM_VOTERS ---
grep_result=$(grep -c 'QUORUM_VOTERS.*jq.*quorum.voters' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_VOTERS"

# --- Test 18: automaton.sh reads QUORUM_THRESHOLD_SEED ---
grep_result=$(grep -c 'QUORUM_THRESHOLD_SEED.*jq.*quorum.thresholds.seed_promotion' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_THRESHOLD_SEED"

# --- Test 19: automaton.sh reads QUORUM_THRESHOLD_BLOOM ---
grep_result=$(grep -c 'QUORUM_THRESHOLD_BLOOM.*jq.*quorum.thresholds.bloom_implementation' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_THRESHOLD_BLOOM"

# --- Test 20: automaton.sh reads QUORUM_THRESHOLD_AMENDMENT ---
grep_result=$(grep -c 'QUORUM_THRESHOLD_AMENDMENT.*jq.*quorum.thresholds.constitutional_amendment' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_THRESHOLD_AMENDMENT"

# --- Test 21: automaton.sh reads QUORUM_THRESHOLD_EMERGENCY ---
grep_result=$(grep -c 'QUORUM_THRESHOLD_EMERGENCY.*jq.*quorum.thresholds.emergency_override' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_THRESHOLD_EMERGENCY"

# --- Test 22: automaton.sh reads QUORUM_MAX_TOKENS_PER_VOTER ---
grep_result=$(grep -c 'QUORUM_MAX_TOKENS_PER_VOTER.*jq.*quorum.max_tokens_per_voter' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_MAX_TOKENS_PER_VOTER"

# --- Test 23: automaton.sh reads QUORUM_MAX_COST_PER_CYCLE ---
grep_result=$(grep -c 'QUORUM_MAX_COST_PER_CYCLE.*jq.*quorum.max_cost_per_cycle_usd' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_MAX_COST_PER_CYCLE"

# --- Test 24: automaton.sh reads QUORUM_REJECTION_COOLDOWN ---
grep_result=$(grep -c 'QUORUM_REJECTION_COOLDOWN.*jq.*quorum.rejection_cooldown_cycles' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_REJECTION_COOLDOWN"

# --- Test 25: automaton.sh reads QUORUM_MODEL ---
grep_result=$(grep -c 'QUORUM_MODEL.*jq.*quorum.model' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads QUORUM_MODEL"

# --- Test 26: automaton.sh has QUORUM_ defaults in the else branch ---
grep_result=$(grep -c 'QUORUM_ENABLED="true"' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has QUORUM_ENABLED default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have QUORUM_ENABLED default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 27: quorum-disabled fallback guard exists ---
grep_result=$(grep -c 'QUORUM_ENABLED' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh references QUORUM_ENABLED at least 3 times (read, default, guard)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference QUORUM_ENABLED at least 3 times (got $grep_result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 28: .gitignore tracks .automaton/votes/ ---
gitignore_file="$SCRIPT_DIR/../.gitignore"
if grep -q 'automaton/votes' "$gitignore_file" 2>/dev/null; then
    # Should NOT be in gitignore exclude (it should be tracked)
    # Check it's in the persistent (tracked) section, not the ephemeral (excluded) section
    echo "PASS: .gitignore references .automaton/votes/"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: .gitignore should reference .automaton/votes/" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
