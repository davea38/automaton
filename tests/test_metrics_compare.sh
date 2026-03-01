#!/usr/bin/env bash
# tests/test_metrics_compare.sh — Tests for spec-43 §2 _metrics_compare()
# Verifies that snapshot comparison computes per-metric deltas with direction
# indicators for the OBSERVE phase's before/after analysis.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _metrics_compare function exists ---
grep_result=$(grep -c '^_metrics_compare()' "$script_file" || true)
assert_equals "1" "$grep_result" "_metrics_compare() function exists in automaton.sh"

# --- Test 2: _metrics_compare accepts two snapshot arguments ---
grep_result=$(grep -A3 '^_metrics_compare()' "$script_file" | grep -c 'pre_snapshot\|snapshot_a\|snap_pre' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_compare accepts snapshot parameters"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_compare should accept snapshot parameters" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Integration tests ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/.automaton"

# Extract functions from automaton.sh
extract_funcs() {
    local func_name="$1"
    awk "/^${func_name}\\(\\)/{found=1} found{print} found && /^}$/{exit}" "$script_file"
}

# Pre-cycle snapshot: baseline state
PRE_SNAPSHOT='{
  "cycle_id": 5,
  "timestamp": "2026-03-01T10:00:00Z",
  "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
  "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.15, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
  "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 1, "review_rework_rate": 0.10, "constitution_violations": 0},
  "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
  "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.05, "self_modification_count": 2}
}'

# Post-cycle snapshot: improved state
POST_SNAPSHOT='{
  "cycle_id": 5,
  "timestamp": "2026-03-01T12:00:00Z",
  "capability": {"total_lines": 5200, "total_functions": 105, "total_specs": 31, "total_tests": 22, "test_assertions": 90, "cli_flags": 6, "agent_definitions": 3, "skills": 2, "hooks": 1},
  "efficiency": {"tokens_per_task": 45000, "tokens_per_iteration": 110000, "cache_hit_ratio": 0.68, "stall_rate": 0.12, "prompt_overhead_ratio": 0.38, "bootstrap_time_ms": 380, "avg_iteration_duration_s": 45},
  "quality": {"test_pass_rate": 0.95, "first_pass_success_rate": 0.85, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.08, "constitution_violations": 0},
  "innovation": {"garden_seeds": 3, "garden_sprouts": 2, "garden_blooms": 1, "garden_harvested": 1, "garden_wilted": 0, "active_signals": 4, "quorum_votes_cast": 1, "ideas_implemented_total": 1, "cycles_since_last_harvest": 0},
  "health": {"budget_utilization": 0.30, "weekly_allowance_remaining": 0.70, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.03, "self_modification_count": 5}
}'

# --- Test 3: _metrics_compare produces valid JSON output ---
result=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_compare)"
    _metrics_compare "$PRE_SNAPSHOT" "$POST_SNAPSHOT"
)

is_valid=$(echo "$result" | jq 'type' 2>/dev/null || echo "error")
assert_equals '"object"' "$is_valid" "_metrics_compare returns a JSON object"

# --- Test 4: Output has 'deltas' array ---
has_deltas=$(echo "$result" | jq 'has("deltas")' 2>/dev/null || echo "false")
assert_equals "true" "$has_deltas" "Output contains 'deltas' array"

# --- Test 5: Each delta has required fields ---
has_fields=$(echo "$result" | jq '[.deltas[] | has("category", "metric", "before", "after", "delta", "direction")] | all' 2>/dev/null || echo "false")
assert_equals "true" "$has_fields" "Each delta has category, metric, before, after, delta, direction fields"

# --- Test 6: tokens_per_task shows as improved (lower is better, went from 50000 to 45000) ---
tpt_dir=$(echo "$result" | jq -r '[.deltas[] | select(.metric == "tokens_per_task")][0].direction // "unknown"' 2>/dev/null)
assert_equals "improved" "$tpt_dir" "tokens_per_task direction is improved (50000 -> 45000)"

# --- Test 7: test_pass_rate shows as improved (higher is better, went from 0.90 to 0.95) ---
tpr_dir=$(echo "$result" | jq -r '[.deltas[] | select(.metric == "test_pass_rate")][0].direction // "unknown"' 2>/dev/null)
assert_equals "improved" "$tpr_dir" "test_pass_rate direction is improved (0.90 -> 0.95)"

# --- Test 8: Delta values are correct ---
tpt_delta=$(echo "$result" | jq '[.deltas[] | select(.metric == "tokens_per_task")][0].delta // 0' 2>/dev/null)
assert_equals "-5000" "$tpt_delta" "tokens_per_task delta is -5000 (50000 -> 45000)"

# --- Test 9: Percentage change is included ---
tpt_pct=$(echo "$result" | jq '[.deltas[] | select(.metric == "tokens_per_task")][0].percent_change // 0' 2>/dev/null)
assert_equals "-10" "$tpt_pct" "tokens_per_task percent_change is -10%"

# --- Test 10: Overall summary includes improved/degraded/unchanged counts ---
has_summary=$(echo "$result" | jq 'has("summary")' 2>/dev/null || echo "false")
assert_equals "true" "$has_summary" "Output contains 'summary' object"

improved_count=$(echo "$result" | jq '.summary.improved // 0' 2>/dev/null)
if [ "$improved_count" -gt 0 ]; then
    echo "PASS: Summary reports improved count > 0"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Summary should report improved count > 0 (got: $improved_count)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Degraded metric detection ---
# Post-cycle with degraded test_pass_rate
POST_DEGRADED='{
  "cycle_id": 5,
  "timestamp": "2026-03-01T12:00:00Z",
  "capability": {"total_lines": 5200, "total_functions": 105, "total_specs": 31, "total_tests": 22, "test_assertions": 90, "cli_flags": 6, "agent_definitions": 3, "skills": 2, "hooks": 1},
  "efficiency": {"tokens_per_task": 55000, "tokens_per_iteration": 130000, "cache_hit_ratio": 0.55, "stall_rate": 0.18, "prompt_overhead_ratio": 0.42, "bootstrap_time_ms": 420, "avg_iteration_duration_s": 55},
  "quality": {"test_pass_rate": 0.85, "first_pass_success_rate": 0.75, "rollback_count": 1, "syntax_errors_caught": 2, "review_rework_rate": 0.15, "constitution_violations": 0},
  "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 2},
  "health": {"budget_utilization": 0.30, "weekly_allowance_remaining": 0.70, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.08, "self_modification_count": 5}
}'

result_degraded=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_compare)"
    _metrics_compare "$PRE_SNAPSHOT" "$POST_DEGRADED"
)

tpr_degraded_dir=$(echo "$result_degraded" | jq -r '[.deltas[] | select(.metric == "test_pass_rate")][0].direction // "unknown"' 2>/dev/null)
assert_equals "degraded" "$tpr_degraded_dir" "test_pass_rate direction is degraded (0.90 -> 0.85)"

tpt_degraded_dir=$(echo "$result_degraded" | jq -r '[.deltas[] | select(.metric == "tokens_per_task")][0].direction // "unknown"' 2>/dev/null)
assert_equals "degraded" "$tpt_degraded_dir" "tokens_per_task direction is degraded (50000 -> 55000, lower is better)"

# --- Test 12: Unchanged metric detection ---
POST_SAME='{
  "cycle_id": 5,
  "timestamp": "2026-03-01T12:00:00Z",
  "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
  "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.15, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
  "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 1, "review_rework_rate": 0.10, "constitution_violations": 0},
  "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
  "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.05, "self_modification_count": 2}
}'

result_same=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_compare)"
    _metrics_compare "$PRE_SNAPSHOT" "$POST_SAME"
)

unchanged_count=$(echo "$result_same" | jq '.summary.unchanged // 0' 2>/dev/null)
if [ "$unchanged_count" -gt 0 ]; then
    echo "PASS: Summary reports unchanged count > 0 for identical snapshots"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Summary should report unchanged > 0 for identical snapshots (got: $unchanged_count)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: Returns empty result when disabled ---
result_disabled=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="false"
    log() { true; }
    eval "$(extract_funcs _metrics_compare)"
    _metrics_compare "$PRE_SNAPSHOT" "$POST_SNAPSHOT"
)

disabled_deltas=$(echo "$result_disabled" | jq '.deltas | length // 0' 2>/dev/null || echo "0")
assert_equals "0" "$disabled_deltas" "Returns empty deltas when METRICS_ENABLED is false"

test_summary
