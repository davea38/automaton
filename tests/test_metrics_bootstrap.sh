#!/usr/bin/env bash
# tests/test_metrics_bootstrap.sh — Tests for spec-43 §3 metrics_trend in bootstrap manifest
# Verifies that .automaton/init.sh includes metrics_trend field sourced from evolution-metrics.json
# with improving metrics list, degrading list, alerts, cycles_completed, and last_harvest_cycle.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

init_script="$SCRIPT_DIR/../.automaton/init.sh"

# --- Test 1: init.sh contains metrics_trend code path ---
grep_result=$(grep -c 'metrics_trend' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh contains metrics_trend code path"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should contain metrics_trend code path" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: init.sh reads from evolution-metrics.json ---
grep_result=$(grep -c 'evolution-metrics.json' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh reads evolution-metrics.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should read evolution-metrics.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Helper: set up a temp git repo for functional tests ---
setup_tmpdir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.automaton"
    git -C "$tmpdir" init -q 2>/dev/null
    touch "$tmpdir/README"
    git -C "$tmpdir" add README
    git -C "$tmpdir" commit -q -m "init" 2>/dev/null
    touch "$tmpdir/file2"
    git -C "$tmpdir" add file2
    git -C "$tmpdir" commit -q -m "second" 2>/dev/null
    echo "$tmpdir"
}

# --- Test 3: Functional test — metrics_trend with populated metrics (improving + degrading) ---
tmpdir=$(setup_tmpdir)
trap 'rm -rf "$tmpdir"' EXIT

# Create evolution-metrics.json with 3 snapshots showing trends:
# - tokens_per_task: decreasing (improving, lower is better)
# - test_pass_rate: increasing (improving, higher is better)
# - stall_rate: increasing (degrading, lower is better)
# - cache_hit_ratio: stable
# Also includes a harvest in cycle 2
cat > "$tmpdir/.automaton/evolution-metrics.json" <<'METRICSEOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1,
      "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 80, "total_specs": 30, "total_tests": 20},
      "efficiency": {"tokens_per_task": 50000, "cache_hit_ratio": 0.65, "stall_rate": 0.10},
      "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.75, "rollback_count": 0, "review_rework_rate": 0.10},
      "innovation": {"garden_harvested": 0, "cycles_since_last_harvest": 1},
      "health": {"error_rate": 0.02}
    },
    {
      "cycle_id": 2,
      "timestamp": "2026-03-01T11:00:00Z",
      "capability": {"total_lines": 5200, "total_functions": 85, "total_specs": 32, "total_tests": 22},
      "efficiency": {"tokens_per_task": 45000, "cache_hit_ratio": 0.66, "stall_rate": 0.12},
      "quality": {"test_pass_rate": 0.93, "first_pass_success_rate": 0.78, "rollback_count": 0, "review_rework_rate": 0.10},
      "innovation": {"garden_harvested": 1, "cycles_since_last_harvest": 0},
      "health": {"error_rate": 0.02}
    },
    {
      "cycle_id": 3,
      "timestamp": "2026-03-01T12:00:00Z",
      "capability": {"total_lines": 5400, "total_functions": 90, "total_specs": 34, "total_tests": 25},
      "efficiency": {"tokens_per_task": 42000, "cache_hit_ratio": 0.67, "stall_rate": 0.15},
      "quality": {"test_pass_rate": 0.96, "first_pass_success_rate": 0.80, "rollback_count": 0, "review_rework_rate": 0.10},
      "innovation": {"garden_harvested": 1, "cycles_since_last_harvest": 1},
      "health": {"error_rate": 0.02}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 5000, "total_functions": 80, "total_specs": 30, "total_tests": 20},
    "efficiency": {"tokens_per_task": 50000, "cache_hit_ratio": 0.65, "stall_rate": 0.10},
    "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.75, "rollback_count": 0, "review_rework_rate": 0.10},
    "health": {"error_rate": 0.02}
  }
}
METRICSEOF

manifest=$(bash "$init_script" "$tmpdir" "build" "1" 2>/dev/null)

# Check metrics_trend.cycles_completed (3 snapshots)
val=$(echo "$manifest" | jq -r '.metrics_trend.cycles_completed // empty')
assert_equals "3" "$val" "metrics_trend.cycles_completed is 3"

# Check metrics_trend.last_harvest_cycle (cycle 2 had a harvest)
val=$(echo "$manifest" | jq -r '.metrics_trend.last_harvest_cycle // empty')
assert_equals "2" "$val" "metrics_trend.last_harvest_cycle is 2"

# Check improving metrics list contains tokens_per_task and test_pass_rate
val=$(echo "$manifest" | jq -r '.metrics_trend.improving | sort | join(",")' 2>/dev/null)
assert_contains "$val" "tokens_per_task" "improving list contains tokens_per_task"
assert_contains "$val" "test_pass_rate" "improving list contains test_pass_rate"

# Check degrading metrics list contains stall_rate
val=$(echo "$manifest" | jq -r '.metrics_trend.degrading | join(",")' 2>/dev/null)
assert_contains "$val" "stall_rate" "degrading list contains stall_rate"

# Check alerts is an array (may be empty since we only have 3 cycles, not enough for alert threshold)
val=$(echo "$manifest" | jq -r '.metrics_trend.alerts | type' 2>/dev/null)
assert_equals "array" "$val" "metrics_trend.alerts is an array"

# --- Test 4: No evolution-metrics.json means no metrics_trend ---
tmpdir2=$(setup_tmpdir)
trap 'rm -rf "$tmpdir" "$tmpdir2"' EXIT

manifest2=$(bash "$init_script" "$tmpdir2" "build" "1" 2>/dev/null)
val=$(echo "$manifest2" | jq -r '.metrics_trend // "absent"')
assert_equals "absent" "$val" "No metrics_trend when evolution-metrics.json absent"

# --- Test 5: Single snapshot — no trends but cycles_completed still reported ---
tmpdir3=$(setup_tmpdir)
trap 'rm -rf "$tmpdir" "$tmpdir2" "$tmpdir3"' EXIT

cat > "$tmpdir3/.automaton/evolution-metrics.json" <<'METRICSEOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1,
      "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 80, "total_specs": 30, "total_tests": 20},
      "efficiency": {"tokens_per_task": 50000, "cache_hit_ratio": 0.65, "stall_rate": 0.10},
      "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.75, "rollback_count": 0, "review_rework_rate": 0.10},
      "innovation": {"garden_harvested": 0, "cycles_since_last_harvest": 0},
      "health": {"error_rate": 0.02}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 5000, "total_functions": 80, "total_specs": 30, "total_tests": 20},
    "efficiency": {"tokens_per_task": 50000, "cache_hit_ratio": 0.65, "stall_rate": 0.10},
    "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.75, "rollback_count": 0, "review_rework_rate": 0.10},
    "health": {"error_rate": 0.02}
  }
}
METRICSEOF

manifest3=$(bash "$init_script" "$tmpdir3" "build" "1" 2>/dev/null)

val=$(echo "$manifest3" | jq -r '.metrics_trend.cycles_completed // empty')
assert_equals "1" "$val" "metrics_trend.cycles_completed is 1 for single snapshot"

# With only 1 snapshot, improving/degrading should be empty
val=$(echo "$manifest3" | jq -r '.metrics_trend.improving | length')
assert_equals "0" "$val" "metrics_trend.improving empty with single snapshot"

val=$(echo "$manifest3" | jq -r '.metrics_trend.degrading | length')
assert_equals "0" "$val" "metrics_trend.degrading empty with single snapshot"

# No harvest ever
val=$(echo "$manifest3" | jq -r '.metrics_trend.last_harvest_cycle // "null"')
assert_equals "null" "$val" "metrics_trend.last_harvest_cycle null when no harvests"

test_summary
