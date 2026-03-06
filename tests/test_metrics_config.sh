#!/usr/bin/env bash
# tests/test_metrics_config.sh — Tests for spec-43 §1 metrics configuration section
# Verifies that automaton.config.json contains the metrics section with correct defaults
# and that automaton.sh loads all metrics config values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"

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

# --- Test 5-8: load_config() sets METRICS_* variables from config ---
(
    source "$_PROJECT_DIR/lib/config.sh"
    CONFIG_FILE="$config_file" load_config
    assert_equals "true" "$METRICS_ENABLED" "load_config sets METRICS_ENABLED"
    assert_equals "5" "$METRICS_TREND_WINDOW" "load_config sets METRICS_TREND_WINDOW"
    assert_equals "3" "$METRICS_DEGRADATION_ALERT_THRESHOLD" "load_config sets METRICS_DEGRADATION_ALERT_THRESHOLD"
    assert_equals "100" "$METRICS_SNAPSHOT_RETENTION" "load_config sets METRICS_SNAPSHOT_RETENTION"
)

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
