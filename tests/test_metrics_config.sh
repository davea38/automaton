#!/usr/bin/env bash
# tests/test_metrics_config.sh — Tests for spec-43 §1 metrics configuration section
# Verifies that automaton.config.json contains the metrics section with correct defaults
# and that automaton.sh loads all metrics config values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.config.json contains metrics.enabled ---
val=$(jq -r '.metrics.enabled // "missing"' "$config_file")
assert_equals "true" "$val" "metrics.enabled defaults to true in config"

# --- Test 2: metrics.trend_window ---
val=$(jq -r '.metrics.trend_window // "missing"' "$config_file")
assert_equals "5" "$val" "metrics.trend_window defaults to 5"

# --- Test 3: metrics.degradation_alert_threshold ---
val=$(jq -r '.metrics.degradation_alert_threshold // "missing"' "$config_file")
assert_equals "3" "$val" "metrics.degradation_alert_threshold defaults to 3"

# --- Test 4: metrics.snapshot_retention ---
val=$(jq -r '.metrics.snapshot_retention // "missing"' "$config_file")
assert_equals "100" "$val" "metrics.snapshot_retention defaults to 100"

# --- Test 5: automaton.sh reads METRICS_ENABLED from config ---
grep_result=$(grep -c 'METRICS_ENABLED.*jq.*metrics.enabled' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads METRICS_ENABLED from metrics.enabled config"

# --- Test 6: automaton.sh reads METRICS_TREND_WINDOW ---
grep_result=$(grep -c 'METRICS_TREND_WINDOW.*jq.*metrics.trend_window' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads METRICS_TREND_WINDOW"

# --- Test 7: automaton.sh reads METRICS_DEGRADATION_ALERT_THRESHOLD ---
grep_result=$(grep -c 'METRICS_DEGRADATION_ALERT_THRESHOLD.*jq.*metrics.degradation_alert_threshold' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads METRICS_DEGRADATION_ALERT_THRESHOLD"

# --- Test 8: automaton.sh reads METRICS_SNAPSHOT_RETENTION ---
grep_result=$(grep -c 'METRICS_SNAPSHOT_RETENTION.*jq.*metrics.snapshot_retention' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh reads METRICS_SNAPSHOT_RETENTION"

# --- Test 9: automaton.sh has METRICS_ENABLED default in else branch ---
grep_result=$(grep -c 'METRICS_ENABLED="true"' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has METRICS_ENABLED default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have METRICS_ENABLED default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: .gitignore references .automaton/evolution-metrics.json as persistent ---
gitignore_file="$SCRIPT_DIR/../.gitignore"
if grep -q 'evolution-metrics.json' "$gitignore_file" 2>/dev/null; then
    echo "PASS: .gitignore references .automaton/evolution-metrics.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: .gitignore should reference .automaton/evolution-metrics.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
