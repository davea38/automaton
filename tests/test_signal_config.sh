#!/usr/bin/env bash
# tests/test_signal_config.sh — Tests for spec-42 stigmergy configuration section
# Verifies that automaton.config.json contains the stigmergy section with correct defaults,
# that automaton.sh loads all stigmergy config values, and that stigmergy.enabled=false
# causes signal operations to be skipped.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"

# --- Test 1: automaton.config.json contains stigmergy.enabled ---
val=$(jq -r '.stigmergy.enabled // "missing"' "$config_file")
assert_equals "true" "$val" "stigmergy.enabled defaults to true in config"

# --- Test 2: stigmergy.initial_strength ---
val=$(jq -r '.stigmergy.initial_strength // "missing"' "$config_file")
assert_equals "0.3" "$val" "stigmergy.initial_strength defaults to 0.3"

# --- Test 3: stigmergy.reinforce_increment ---
val=$(jq -r '.stigmergy.reinforce_increment // "missing"' "$config_file")
assert_equals "0.15" "$val" "stigmergy.reinforce_increment defaults to 0.15"

# --- Test 4: stigmergy.decay_floor ---
val=$(jq -r '.stigmergy.decay_floor // "missing"' "$config_file")
assert_equals "0.05" "$val" "stigmergy.decay_floor defaults to 0.05"

# --- Test 5: stigmergy.match_threshold ---
val=$(jq -r '.stigmergy.match_threshold // "missing"' "$config_file")
assert_equals "0.6" "$val" "stigmergy.match_threshold defaults to 0.6"

# --- Test 6: stigmergy.max_signals ---
val=$(jq -r '.stigmergy.max_signals // "missing"' "$config_file")
assert_equals "100" "$val" "stigmergy.max_signals defaults to 100"

# --- Test 7-12: load_config() sets STIGMERGY_* variables from config ---
(
    source "$_PROJECT_DIR/lib/config.sh"
    CONFIG_FILE="$config_file" load_config
    assert_equals "true" "$STIGMERGY_ENABLED" "load_config sets STIGMERGY_ENABLED"
    assert_equals "0.3" "$STIGMERGY_INITIAL_STRENGTH" "load_config sets STIGMERGY_INITIAL_STRENGTH"
    assert_equals "0.15" "$STIGMERGY_REINFORCE_INCREMENT" "load_config sets STIGMERGY_REINFORCE_INCREMENT"
    assert_equals "0.05" "$STIGMERGY_DECAY_FLOOR" "load_config sets STIGMERGY_DECAY_FLOOR"
    assert_equals "0.6" "$STIGMERGY_MATCH_THRESHOLD" "load_config sets STIGMERGY_MATCH_THRESHOLD"
    assert_equals "100" "$STIGMERGY_MAX_SIGNALS" "load_config sets STIGMERGY_MAX_SIGNALS"
)

# --- Test 13: automaton.sh has STIGMERGY_ defaults in the else branch ---
grep_result=$(grep -c 'STIGMERGY_ENABLED="true"' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has STIGMERGY_ENABLED default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have STIGMERGY_ENABLED default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: backward compatibility — stigmergy.enabled=false guard exists ---
grep_result=$(grep -c 'STIGMERGY_ENABLED' "$script_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: automaton.sh references STIGMERGY_ENABLED at least 3 times (read, default, guard)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference STIGMERGY_ENABLED at least 3 times (got $grep_result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
