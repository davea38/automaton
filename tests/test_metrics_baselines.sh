#!/usr/bin/env bash
# tests/test_metrics_baselines.sh — Tests for spec-43 §1 _metrics_set_baselines() and _metrics_get_latest()
# Verifies that baselines are recorded from the first snapshot and _metrics_get_latest returns
# the most recent snapshot from evolution-metrics.json.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _metrics_set_baselines function exists ---
grep_result=$(grep -c '^_metrics_set_baselines()' "$script_file" || true)
assert_equals "1" "$grep_result" "_metrics_set_baselines() function exists in automaton.sh"

# --- Test 2: _metrics_get_latest function exists ---
grep_result=$(grep -c '^_metrics_get_latest()' "$script_file" || true)
assert_equals "1" "$grep_result" "_metrics_get_latest() function exists in automaton.sh"

# --- Test 3: _metrics_set_baselines reads from evolution-metrics.json ---
grep_result=$(grep -A30 '^_metrics_set_baselines()' "$script_file" | grep -c 'evolution-metrics' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_set_baselines references evolution-metrics.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_set_baselines should reference evolution-metrics.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _metrics_set_baselines writes baselines object ---
grep_result=$(grep -A30 '^_metrics_set_baselines()' "$script_file" | grep -c 'baselines' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_set_baselines writes baselines"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_set_baselines should write baselines" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _metrics_get_latest returns snapshot JSON ---
grep_result=$(grep -A20 '^_metrics_get_latest()' "$script_file" | grep -c 'snapshots' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_get_latest reads from snapshots array"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_get_latest should read from snapshots array" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Integration tests ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/.automaton"

# Create a metrics file with two snapshots and empty baselines
cat > "$TEST_DIR/.automaton/evolution-metrics.json" << 'EOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1,
      "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 5000, "total_functions": 100, "total_specs": 30, "total_tests": 20, "test_assertions": 80, "cli_flags": 5, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.60, "stall_rate": 0.15, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 400, "avg_iteration_duration_s": 50},
      "quality": {"test_pass_rate": 0.93, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 1, "review_rework_rate": 0.10, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.01, "self_modification_count": 2}
    },
    {
      "cycle_id": 2,
      "timestamp": "2026-03-01T12:00:00Z",
      "capability": {"total_lines": 5200, "total_functions": 105, "total_specs": 32, "total_tests": 22, "test_assertions": 90, "cli_flags": 6, "agent_definitions": 3, "skills": 2, "hooks": 1},
      "efficiency": {"tokens_per_task": 45000, "tokens_per_iteration": 110000, "cache_hit_ratio": 0.65, "stall_rate": 0.12, "prompt_overhead_ratio": 0.38, "bootstrap_time_ms": 380, "avg_iteration_duration_s": 45},
      "quality": {"test_pass_rate": 0.95, "first_pass_success_rate": 0.85, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.08, "constitution_violations": 0},
      "innovation": {"garden_seeds": 3, "garden_sprouts": 2, "garden_blooms": 1, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 4, "quorum_votes_cast": 1, "ideas_implemented_total": 0, "cycles_since_last_harvest": 2},
      "health": {"budget_utilization": 0.25, "weekly_allowance_remaining": 0.75, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.02, "self_modification_count": 4}
    }
  ],
  "baselines": {}
}
EOF

# Extract functions from automaton.sh
extract_funcs() {
    local func_name="$1"
    awk "/^${func_name}\\(\\)/{found=1} found{print} found && /^}$/{exit}" "$script_file"
}

# --- Test 6: _metrics_set_baselines records first snapshot as baselines ---
result=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_set_baselines)"
    _metrics_set_baselines
    jq '.baselines' "$AUTOMATON_DIR/evolution-metrics.json"
)

has_capability=$(echo "$result" | jq 'has("capability")' 2>/dev/null || echo "false")
assert_equals "true" "$has_capability" "_metrics_set_baselines records capability baselines"

# --- Test 7: Baselines use first snapshot values ---
baseline_lines=$(echo "$result" | jq '.capability.total_lines // 0' 2>/dev/null || echo "0")
assert_equals "5000" "$baseline_lines" "Baseline total_lines matches first snapshot (5000)"

# --- Test 8: Baselines include efficiency metrics ---
has_efficiency=$(echo "$result" | jq 'has("efficiency")' 2>/dev/null || echo "false")
assert_equals "true" "$has_efficiency" "_metrics_set_baselines records efficiency baselines"

# --- Test 9: Baselines include quality metrics ---
has_quality=$(echo "$result" | jq 'has("quality")' 2>/dev/null || echo "false")
assert_equals "true" "$has_quality" "_metrics_set_baselines records quality baselines"

# --- Test 10: _metrics_set_baselines does NOT overwrite existing baselines ---
# Reset: put baselines with a known value
jq '.baselines = {"capability": {"total_lines": 9999}}' "$TEST_DIR/.automaton/evolution-metrics.json" > "$TEST_DIR/.automaton/evolution-metrics.json.tmp" && mv "$TEST_DIR/.automaton/evolution-metrics.json.tmp" "$TEST_DIR/.automaton/evolution-metrics.json"

result2=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_set_baselines)"
    _metrics_set_baselines
    jq '.baselines.capability.total_lines' "$AUTOMATON_DIR/evolution-metrics.json"
)
assert_equals "9999" "$result2" "_metrics_set_baselines does not overwrite existing baselines"

# --- Test 11: _metrics_get_latest returns the most recent snapshot ---
# Reset baselines to empty so it doesn't affect other tests
jq '.baselines = {}' "$TEST_DIR/.automaton/evolution-metrics.json" > "$TEST_DIR/.automaton/evolution-metrics.json.tmp" && mv "$TEST_DIR/.automaton/evolution-metrics.json.tmp" "$TEST_DIR/.automaton/evolution-metrics.json"

result3=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_get_latest)"
    _metrics_get_latest
)

latest_cycle=$(echo "$result3" | jq '.cycle_id // 0' 2>/dev/null || echo "0")
assert_equals "2" "$latest_cycle" "_metrics_get_latest returns the most recent snapshot (cycle 2)"

# --- Test 12: _metrics_get_latest returns empty object when no snapshots ---
echo '{"version":1,"snapshots":[],"baselines":{}}' > "$TEST_DIR/.automaton/evolution-metrics.json"

result4=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_get_latest)"
    _metrics_get_latest
)

is_null=$(echo "$result4" | jq 'type == "null" or . == {}' 2>/dev/null || echo "true")
if [ "$is_null" = "true" ] || [ -z "$result4" ] || [ "$result4" = "null" ] || [ "$result4" = "{}" ]; then
    echo "PASS: _metrics_get_latest returns empty/null when no snapshots exist"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_get_latest should return empty/null when no snapshots (got: $result4)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _metrics_get_latest returns empty when file doesn't exist ---
result5=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton/nonexistent"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_get_latest)"
    _metrics_get_latest
)

if [ -z "$result5" ] || [ "$result5" = "null" ] || [ "$result5" = "{}" ]; then
    echo "PASS: _metrics_get_latest returns empty when metrics file doesn't exist"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_get_latest should return empty when metrics file doesn't exist (got: $result5)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _metrics_set_baselines skips when METRICS_ENABLED is false ---
result6=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="false"
    log() { true; }
    eval "$(extract_funcs _metrics_set_baselines)"
    _metrics_set_baselines
    echo $?
)
assert_equals "0" "$result6" "_metrics_set_baselines returns 0 when METRICS_ENABLED is false"

test_summary
