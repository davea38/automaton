#!/usr/bin/env bash
# tests/test_metrics_trends.sh — Tests for spec-43 §2 _metrics_analyze_trends()
# Verifies that trend analysis computes direction, rate of change, and alert
# status for metrics across the configured trend window.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _metrics_analyze_trends function exists ---
grep_result=$(grep -c '^_metrics_analyze_trends()' "$script_file" || true)
assert_equals "1" "$grep_result" "_metrics_analyze_trends() function exists in automaton.sh"

# --- Test 2: _metrics_analyze_trends accepts window parameter ---
grep_result=$(grep -A5 '^_metrics_analyze_trends()' "$script_file" | grep -c 'window' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_analyze_trends accepts window parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_analyze_trends should accept window parameter" >&2
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

# Create metrics file with 5 snapshots showing improving tokens_per_task and test_pass_rate
cat > "$TEST_DIR/.automaton/evolution-metrics.json" << 'EOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1,
      "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.15, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 1, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.05, "self_modification_count": 2}
    },
    {
      "cycle_id": 2,
      "timestamp": "2026-03-01T12:00:00Z",
      "capability": {"total_lines": 5200, "total_functions": 105, "total_specs": 31, "total_tests": 22, "test_assertions": 90, "cli_flags": 6, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 48000, "tokens_per_iteration": 115000, "cache_hit_ratio": 0.63, "stall_rate": 0.13, "prompt_overhead_ratio": 0.39, "bootstrap_time_ms": 390, "avg_iteration_duration_s": 48},
      "quality": {"test_pass_rate": 0.92, "first_pass_success_rate": 0.82, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.09, "constitution_violations": 0},
      "innovation": {"garden_seeds": 3, "garden_sprouts": 2, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 4, "quorum_votes_cast": 1, "ideas_implemented_total": 0, "cycles_since_last_harvest": 2},
      "health": {"budget_utilization": 0.25, "weekly_allowance_remaining": 0.75, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.04, "self_modification_count": 4}
    },
    {
      "cycle_id": 3,
      "timestamp": "2026-03-01T14:00:00Z",
      "capability": {"total_lines": 5400, "total_functions": 110, "total_specs": 32, "total_tests": 24, "test_assertions": 100, "cli_flags": 6, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 46000, "tokens_per_iteration": 110000, "cache_hit_ratio": 0.66, "stall_rate": 0.11, "prompt_overhead_ratio": 0.38, "bootstrap_time_ms": 380, "avg_iteration_duration_s": 46},
      "quality": {"test_pass_rate": 0.94, "first_pass_success_rate": 0.84, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.08, "constitution_violations": 0},
      "innovation": {"garden_seeds": 4, "garden_sprouts": 3, "garden_blooms": 1, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 5, "quorum_votes_cast": 2, "ideas_implemented_total": 0, "cycles_since_last_harvest": 3},
      "health": {"budget_utilization": 0.40, "weekly_allowance_remaining": 0.60, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.03, "self_modification_count": 6}
    },
    {
      "cycle_id": 4,
      "timestamp": "2026-03-01T16:00:00Z",
      "capability": {"total_lines": 5600, "total_functions": 115, "total_specs": 33, "total_tests": 26, "test_assertions": 110, "cli_flags": 7, "agent_definitions": 3, "skills": 3, "hooks": 1},
      "efficiency": {"tokens_per_task": 44000, "tokens_per_iteration": 105000, "cache_hit_ratio": 0.69, "stall_rate": 0.09, "prompt_overhead_ratio": 0.37, "bootstrap_time_ms": 370, "avg_iteration_duration_s": 44},
      "quality": {"test_pass_rate": 0.96, "first_pass_success_rate": 0.86, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.07, "constitution_violations": 0},
      "innovation": {"garden_seeds": 4, "garden_sprouts": 3, "garden_blooms": 2, "garden_harvested": 1, "garden_wilted": 0, "active_signals": 5, "quorum_votes_cast": 3, "ideas_implemented_total": 1, "cycles_since_last_harvest": 0},
      "health": {"budget_utilization": 0.55, "weekly_allowance_remaining": 0.45, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.02, "self_modification_count": 8}
    },
    {
      "cycle_id": 5,
      "timestamp": "2026-03-01T18:00:00Z",
      "capability": {"total_lines": 5800, "total_functions": 120, "total_specs": 34, "total_tests": 28, "test_assertions": 120, "cli_flags": 7, "agent_definitions": 3, "skills": 3, "hooks": 1},
      "efficiency": {"tokens_per_task": 42000, "tokens_per_iteration": 100000, "cache_hit_ratio": 0.72, "stall_rate": 0.07, "prompt_overhead_ratio": 0.36, "bootstrap_time_ms": 360, "avg_iteration_duration_s": 42},
      "quality": {"test_pass_rate": 0.97, "first_pass_success_rate": 0.88, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.06, "constitution_violations": 0},
      "innovation": {"garden_seeds": 4, "garden_sprouts": 3, "garden_blooms": 2, "garden_harvested": 2, "garden_wilted": 1, "active_signals": 5, "quorum_votes_cast": 4, "ideas_implemented_total": 2, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.65, "weekly_allowance_remaining": 0.35, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 10}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20},
    "efficiency": {"tokens_per_task": 50000, "stall_rate": 0.15},
    "quality": {"test_pass_rate": 0.90, "rollback_count": 0}
  }
}
EOF

# --- Test 3: _metrics_analyze_trends produces valid JSON output ---
result=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_analyze_trends)"
    _metrics_analyze_trends 5
)

is_valid=$(echo "$result" | jq 'type' 2>/dev/null || echo "error")
assert_equals '"array"' "$is_valid" "_metrics_analyze_trends returns a JSON array"

# --- Test 4: Output contains trend entries with required fields ---
has_direction=$(echo "$result" | jq '[.[] | has("direction")] | all' 2>/dev/null || echo "false")
assert_equals "true" "$has_direction" "Each trend entry has a 'direction' field"

has_rate=$(echo "$result" | jq '[.[] | has("rate")] | all' 2>/dev/null || echo "false")
assert_equals "true" "$has_rate" "Each trend entry has a 'rate' field"

has_alert=$(echo "$result" | jq '[.[] | has("alert")] | all' 2>/dev/null || echo "false")
assert_equals "true" "$has_alert" "Each trend entry has an 'alert' field"

has_metric=$(echo "$result" | jq '[.[] | has("metric")] | all' 2>/dev/null || echo "false")
assert_equals "true" "$has_metric" "Each trend entry has a 'metric' field"

# --- Test 5: tokens_per_task (lower-is-better) shows as improving ---
tpt_direction=$(echo "$result" | jq -r '[.[] | select(.metric == "tokens_per_task")][0].direction // "unknown"' 2>/dev/null)
assert_equals "improving" "$tpt_direction" "tokens_per_task direction is improving (values decreased)"

# --- Test 6: test_pass_rate (higher-is-better) shows as improving ---
tpr_direction=$(echo "$result" | jq -r '[.[] | select(.metric == "test_pass_rate")][0].direction // "unknown"' 2>/dev/null)
assert_equals "improving" "$tpr_direction" "test_pass_rate direction is improving (values increased)"

# --- Test 7: No alerts when metrics are improving ---
alert_count=$(echo "$result" | jq '[.[] | select(.alert == true)] | length' 2>/dev/null || echo "0")
assert_equals "0" "$alert_count" "No alerts when all metrics are improving"

# --- Test 8: Degradation alert after threshold consecutive cycles ---
# Create metrics with degrading test_pass_rate for 4 consecutive cycles
cat > "$TEST_DIR/.automaton/evolution-metrics.json" << 'EOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1, "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.97, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 2}
    },
    {
      "cycle_id": 2, "timestamp": "2026-03-01T12:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.95, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 2},
      "health": {"budget_utilization": 0.20, "weekly_allowance_remaining": 0.80, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 3}
    },
    {
      "cycle_id": 3, "timestamp": "2026-03-01T14:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.92, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 3},
      "health": {"budget_utilization": 0.30, "weekly_allowance_remaining": 0.70, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 4}
    },
    {
      "cycle_id": 4, "timestamp": "2026-03-01T16:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.88, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 4},
      "health": {"budget_utilization": 0.40, "weekly_allowance_remaining": 0.60, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 5}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20},
    "efficiency": {"tokens_per_task": 50000, "stall_rate": 0.10},
    "quality": {"test_pass_rate": 0.97, "rollback_count": 0}
  }
}
EOF

result_degrade=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_analyze_trends)"
    _metrics_analyze_trends 4
)

tpr_degrade=$(echo "$result_degrade" | jq -r '[.[] | select(.metric == "test_pass_rate")][0].direction // "unknown"' 2>/dev/null)
assert_equals "degrading" "$tpr_degrade" "test_pass_rate shows as degrading (values decreased)"

tpr_alert=$(echo "$result_degrade" | jq -r '[.[] | select(.metric == "test_pass_rate")][0].alert // false' 2>/dev/null)
assert_equals "true" "$tpr_alert" "test_pass_rate triggers alert after 3+ consecutive degrading cycles"

# --- Test 9: Stable metrics detected (within 5% of baseline) ---
cat > "$TEST_DIR/.automaton/evolution-metrics.json" << 'EOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1, "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.95, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 2}
    },
    {
      "cycle_id": 2, "timestamp": "2026-03-01T12:00:00Z",
      "capability": {"total_lines": 5010, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50100, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.95, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 2},
      "health": {"budget_utilization": 0.20, "weekly_allowance_remaining": 0.80, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 3}
    },
    {
      "cycle_id": 3, "timestamp": "2026-03-01T14:00:00Z",
      "capability": {"total_lines": 5020, "total_functions": 101, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 49900, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.10, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.96, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 3},
      "health": {"budget_utilization": 0.30, "weekly_allowance_remaining": 0.70, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 4}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20},
    "efficiency": {"tokens_per_task": 50000, "stall_rate": 0.10},
    "quality": {"test_pass_rate": 0.95, "rollback_count": 0}
  }
}
EOF

result_stable=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_analyze_trends)"
    _metrics_analyze_trends 3
)

tpt_stable=$(echo "$result_stable" | jq -r '[.[] | select(.metric == "tokens_per_task")][0].direction // "unknown"' 2>/dev/null)
assert_equals "stable" "$tpt_stable" "tokens_per_task shows stable when within 5% of baseline"

# --- Test 10: Rate of change is computed as percentage ---
rate=$(echo "$result" | jq '[.[] | select(.metric == "tokens_per_task")][0].rate // 0' 2>/dev/null)
is_number=$(echo "$rate" | awk '{print ($1 == $1+0) ? "true" : "false"}')
assert_equals "true" "$is_number" "Rate of change is a number (percentage per cycle)"

# --- Test 11: Returns empty array when fewer than 2 snapshots ---
echo '{"version":1,"snapshots":[{"cycle_id":1,"timestamp":"2026-03-01T10:00:00Z","capability":{"total_lines":5000,"total_functions":100,"total_specs":30,"total_tests":20,"test_assertions":80,"cli_flags":5,"agent_definitions":3,"skills":2,"hooks":1},"efficiency":{"tokens_per_task":50000,"tokens_per_iteration":120000,"cache_hit_ratio":0.60,"stall_rate":0.10,"prompt_overhead_ratio":0.40,"bootstrap_time_ms":400,"avg_iteration_duration_s":50},"quality":{"test_pass_rate":0.95,"first_pass_success_rate":0.80,"rollback_count":0,"syntax_errors_caught":0,"review_rework_rate":0.10,"constitution_violations":0},"innovation":{"garden_seeds":2,"garden_sprouts":1,"garden_blooms":0,"garden_harvested":0,"garden_wilted":0,"active_signals":3,"quorum_votes_cast":0,"ideas_implemented_total":0,"cycles_since_last_harvest":1},"health":{"budget_utilization":0.10,"weekly_allowance_remaining":0.90,"convergence_risk":"low","circuit_breaker_trips":0,"consecutive_no_improvement":0,"error_rate":0.01,"self_modification_count":2}}],"baselines":{}}' > "$TEST_DIR/.automaton/evolution-metrics.json"

result_single=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_analyze_trends)"
    _metrics_analyze_trends 5
)

single_len=$(echo "$result_single" | jq 'length' 2>/dev/null || echo "error")
assert_equals "0" "$single_len" "Returns empty array when fewer than 2 snapshots"

# --- Test 12: Returns empty when METRICS_ENABLED is false ---
result_disabled=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="false"
    log() { true; }
    eval "$(extract_funcs _metrics_analyze_trends)"
    _metrics_analyze_trends 5
)

if [ -z "$result_disabled" ] || [ "$result_disabled" = "[]" ]; then
    echo "PASS: Returns empty when METRICS_ENABLED is false"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should return empty when METRICS_ENABLED is false (got: $result_disabled)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: Each entry has category field ---
# Restore the 5-snapshot file for this test
cat > "$TEST_DIR/.automaton/evolution-metrics.json" << 'EOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1, "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.15, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.90, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 1, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.05, "self_modification_count": 2}
    },
    {
      "cycle_id": 2, "timestamp": "2026-03-01T12:00:00Z",
      "capability": {"total_lines": 5800, "total_functions": 120, "total_specs": 34, "total_tests": 28, "test_assertions": 120, "cli_flags": 7, "agent_definitions": 3, "skills": 3, "hooks": 1},
      "efficiency": {"tokens_per_task": 42000, "tokens_per_iteration": 100000, "cache_hit_ratio": 0.72, "stall_rate": 0.07, "prompt_overhead_ratio": 0.36, "bootstrap_time_ms": 360, "avg_iteration_duration_s": 42},
      "quality": {"test_pass_rate": 0.97, "first_pass_success_rate": 0.88, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.06, "constitution_violations": 0},
      "innovation": {"garden_seeds": 4, "garden_sprouts": 3, "garden_blooms": 2, "garden_harvested": 2, "garden_wilted": 1, "active_signals": 5, "quorum_votes_cast": 4, "ideas_implemented_total": 2, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.65, "weekly_allowance_remaining": 0.35, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 10}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20},
    "efficiency": {"tokens_per_task": 50000, "stall_rate": 0.15},
    "quality": {"test_pass_rate": 0.90, "rollback_count": 0}
  }
}
EOF

result_cat=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_analyze_trends)"
    _metrics_analyze_trends 5
)

has_category=$(echo "$result_cat" | jq '[.[] | has("category")] | all' 2>/dev/null || echo "false")
assert_equals "true" "$has_category" "Each trend entry has a 'category' field"

# Check that categories include efficiency and quality
has_eff=$(echo "$result_cat" | jq '[.[] | select(.category == "efficiency")] | length > 0' 2>/dev/null || echo "false")
assert_equals "true" "$has_eff" "Results include efficiency category trends"

has_qual=$(echo "$result_cat" | jq '[.[] | select(.category == "quality")] | length > 0' 2>/dev/null || echo "false")
assert_equals "true" "$has_qual" "Results include quality category trends"

test_summary
