#!/usr/bin/env bash
# tests/test_garden_config.sh — Tests for spec-38 garden configuration section
# Verifies that automaton.config.json contains the garden section with correct defaults,
# that automaton.sh loads all garden config values, and that garden.enabled=false
# causes garden operations to be skipped (backward compatibility with backlog.md).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"

# --- Test 1: automaton.config.json contains garden.enabled ---
val=$(jq -r '.garden.enabled // "missing"' "$config_file")
assert_equals "true" "$val" "garden.enabled defaults to true in config"

# --- Test 2: garden.seed_ttl_days ---
val=$(jq -r '.garden.seed_ttl_days // "missing"' "$config_file")
assert_equals "14" "$val" "garden.seed_ttl_days defaults to 14"

# --- Test 3: garden.sprout_ttl_days ---
val=$(jq -r '.garden.sprout_ttl_days // "missing"' "$config_file")
assert_equals "30" "$val" "garden.sprout_ttl_days defaults to 30"

# --- Test 4: garden.sprout_threshold ---
val=$(jq -r '.garden.sprout_threshold // "missing"' "$config_file")
assert_equals "2" "$val" "garden.sprout_threshold defaults to 2"

# --- Test 5: garden.bloom_threshold ---
val=$(jq -r '.garden.bloom_threshold // "missing"' "$config_file")
assert_equals "3" "$val" "garden.bloom_threshold defaults to 3"

# --- Test 6: garden.bloom_priority_threshold ---
val=$(jq -r '.garden.bloom_priority_threshold // "missing"' "$config_file")
assert_equals "40" "$val" "garden.bloom_priority_threshold defaults to 40"

# --- Test 7: garden.signal_seed_threshold ---
val=$(jq -r '.garden.signal_seed_threshold // "missing"' "$config_file")
assert_equals "0.7" "$val" "garden.signal_seed_threshold defaults to 0.7"

# --- Test 8: garden.max_active_ideas ---
val=$(jq -r '.garden.max_active_ideas // "missing"' "$config_file")
assert_equals "50" "$val" "garden.max_active_ideas defaults to 50"

# --- Test 9: garden.auto_seed_from_metrics ---
val=$(jq -r '.garden.auto_seed_from_metrics // "missing"' "$config_file")
assert_equals "true" "$val" "garden.auto_seed_from_metrics defaults to true"

# --- Test 10: garden.auto_seed_from_signals ---
val=$(jq -r '.garden.auto_seed_from_signals // "missing"' "$config_file")
assert_equals "true" "$val" "garden.auto_seed_from_signals defaults to true"

# --- Test 11-20: load_config() sets GARDEN_* variables from config ---
(
    source "$_PROJECT_DIR/lib/config.sh"
    CONFIG_FILE="$config_file" load_config
    assert_equals "true" "$GARDEN_ENABLED" "load_config sets GARDEN_ENABLED"
    assert_equals "14" "$GARDEN_SEED_TTL_DAYS" "load_config sets GARDEN_SEED_TTL_DAYS"
    assert_equals "30" "$GARDEN_SPROUT_TTL_DAYS" "load_config sets GARDEN_SPROUT_TTL_DAYS"
    assert_equals "2" "$GARDEN_SPROUT_THRESHOLD" "load_config sets GARDEN_SPROUT_THRESHOLD"
    assert_equals "3" "$GARDEN_BLOOM_THRESHOLD" "load_config sets GARDEN_BLOOM_THRESHOLD"
    assert_equals "40" "$GARDEN_BLOOM_PRIORITY_THRESHOLD" "load_config sets GARDEN_BLOOM_PRIORITY_THRESHOLD"
    assert_equals "0.7" "$GARDEN_SIGNAL_SEED_THRESHOLD" "load_config sets GARDEN_SIGNAL_SEED_THRESHOLD"
    assert_equals "50" "$GARDEN_MAX_ACTIVE_IDEAS" "load_config sets GARDEN_MAX_ACTIVE_IDEAS"
    assert_equals "true" "$GARDEN_AUTO_SEED_METRICS" "load_config sets GARDEN_AUTO_SEED_METRICS"
    assert_equals "true" "$GARDEN_AUTO_SEED_SIGNALS" "load_config sets GARDEN_AUTO_SEED_SIGNALS"
)

# --- Test 21: automaton.sh has GARDEN_ defaults in the else branch ---
grep_result=$(grep -c 'GARDEN_ENABLED="true"' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has GARDEN_ENABLED default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have GARDEN_ENABLED default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 22: backward compatibility — garden.enabled=false skips garden ops ---
# Check that automaton.sh has a guard checking GARDEN_ENABLED before garden operations
grep_result=$(grep -c 'GARDEN_ENABLED.*true\|GARDEN_ENABLED.*false' "$script_file" || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: automaton.sh checks GARDEN_ENABLED for backward compatibility"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should check GARDEN_ENABLED for backward compatibility" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
