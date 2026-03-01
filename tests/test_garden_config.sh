#!/usr/bin/env bash
# tests/test_garden_config.sh — Tests for spec-38 garden configuration section
# Verifies that automaton.config.json contains the garden section with correct defaults,
# that automaton.sh loads all garden config values, and that garden.enabled=false
# causes garden operations to be skipped (backward compatibility with backlog.md).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
script_file="$SCRIPT_DIR/../automaton.sh"

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

# --- Test 11: automaton.sh reads GARDEN_ENABLED from config ---
grep_result=$(grep -c 'GARDEN_ENABLED.*jq.*garden.enabled' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_ENABLED from garden.enabled config"

# --- Test 12: automaton.sh reads GARDEN_SEED_TTL_DAYS ---
grep_result=$(grep -c 'GARDEN_SEED_TTL_DAYS.*jq.*garden.seed_ttl_days' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_SEED_TTL_DAYS"

# --- Test 13: automaton.sh reads GARDEN_SPROUT_TTL_DAYS ---
grep_result=$(grep -c 'GARDEN_SPROUT_TTL_DAYS.*jq.*garden.sprout_ttl_days' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_SPROUT_TTL_DAYS"

# --- Test 14: automaton.sh reads GARDEN_SPROUT_THRESHOLD ---
grep_result=$(grep -c 'GARDEN_SPROUT_THRESHOLD.*jq.*garden.sprout_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_SPROUT_THRESHOLD"

# --- Test 15: automaton.sh reads GARDEN_BLOOM_THRESHOLD ---
grep_result=$(grep -c 'GARDEN_BLOOM_THRESHOLD.*jq.*garden.bloom_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_BLOOM_THRESHOLD"

# --- Test 16: automaton.sh reads GARDEN_BLOOM_PRIORITY_THRESHOLD ---
grep_result=$(grep -c 'GARDEN_BLOOM_PRIORITY_THRESHOLD.*jq.*garden.bloom_priority_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_BLOOM_PRIORITY_THRESHOLD"

# --- Test 17: automaton.sh reads GARDEN_SIGNAL_SEED_THRESHOLD ---
grep_result=$(grep -c 'GARDEN_SIGNAL_SEED_THRESHOLD.*jq.*garden.signal_seed_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_SIGNAL_SEED_THRESHOLD"

# --- Test 18: automaton.sh reads GARDEN_MAX_ACTIVE_IDEAS ---
grep_result=$(grep -c 'GARDEN_MAX_ACTIVE_IDEAS.*jq.*garden.max_active_ideas' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_MAX_ACTIVE_IDEAS"

# --- Test 19: automaton.sh reads GARDEN_AUTO_SEED_METRICS ---
grep_result=$(grep -c 'GARDEN_AUTO_SEED_METRICS.*jq.*garden.auto_seed_from_metrics' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_AUTO_SEED_METRICS"

# --- Test 20: automaton.sh reads GARDEN_AUTO_SEED_SIGNALS ---
grep_result=$(grep -c 'GARDEN_AUTO_SEED_SIGNALS.*jq.*garden.auto_seed_from_signals' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads GARDEN_AUTO_SEED_SIGNALS"

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
