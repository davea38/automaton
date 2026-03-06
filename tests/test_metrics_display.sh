#!/usr/bin/env bash
# tests/test_metrics_display.sh — Tests for spec-43 §3 _metrics_display_health()
# Verifies that the health dashboard renders all 5 categories with trend indicators,
# current/baseline/trend columns, and bar charts for utilization metrics.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _metrics_display_health function exists ---
grep_result=$(grep -c '^_metrics_display_health()' "$script_file" || true)
assert_equals "1" "$grep_result" "_metrics_display_health() function exists in automaton.sh"

# --- Integration tests ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/.automaton"

# Extract functions from automaton.sh
extract_funcs() {
    local func_name="$1"
    awk "/^${func_name}\\(\\)/{found=1} found{print} found && /^}$/{exit}" "$script_file"
}

# Create metrics file with representative data
cat > "$TEST_DIR/.automaton/evolution-metrics.json" << 'EOF'
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 1, "timestamp": "2026-03-01T10:00:00Z",
      "capability": {"total_lines": 8610, "total_functions": 142, "total_specs": 37, "total_tests": 28, "test_assertions": 156, "cli_flags": 8, "agent_definitions": 3, "skills": 0, "hooks": 1},
      "efficiency": {"tokens_per_task": 50000, "tokens_per_iteration": 120000, "cache_hit_ratio": 0.68, "stall_rate": 0.15, "prompt_overhead_ratio": 0.48, "bootstrap_time_ms": 380, "avg_iteration_duration_s": 45},
      "quality": {"test_pass_rate": 0.93, "first_pass_success_rate": 0.80, "rollback_count": 0, "syntax_errors_caught": 1, "review_rework_rate": 0.15, "constitution_violations": 0},
      "innovation": {"garden_seeds": 2, "garden_sprouts": 1, "garden_blooms": 0, "garden_harvested": 0, "garden_wilted": 0, "active_signals": 3, "quorum_votes_cast": 0, "ideas_implemented_total": 0, "cycles_since_last_harvest": 1},
      "health": {"budget_utilization": 0.10, "weekly_allowance_remaining": 0.90, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.05, "self_modification_count": 2}
    },
    {
      "cycle_id": 12, "timestamp": "2026-03-02T14:30:00Z",
      "capability": {"total_lines": 9240, "total_functions": 156, "total_specs": 45, "total_tests": 35, "test_assertions": 200, "cli_flags": 12, "agent_definitions": 5, "skills": 3, "hooks": 4},
      "efficiency": {"tokens_per_task": 42000, "tokens_per_iteration": 100000, "cache_hit_ratio": 0.72, "stall_rate": 0.08, "prompt_overhead_ratio": 0.40, "bootstrap_time_ms": 350, "avg_iteration_duration_s": 40},
      "quality": {"test_pass_rate": 0.97, "first_pass_success_rate": 0.88, "rollback_count": 0, "syntax_errors_caught": 0, "review_rework_rate": 0.08, "constitution_violations": 0},
      "innovation": {"garden_seeds": 4, "garden_sprouts": 3, "garden_blooms": 2, "garden_harvested": 7, "garden_wilted": 1, "active_signals": 5, "quorum_votes_cast": 10, "ideas_implemented_total": 7, "cycles_since_last_harvest": 0},
      "health": {"budget_utilization": 0.65, "weekly_allowance_remaining": 0.42, "convergence_risk": "low", "circuit_breaker_trips": 0, "consecutive_no_improvement": 0, "error_rate": 0.02, "self_modification_count": 15}
    }
  ],
  "baselines": {
    "capability": {"total_lines": 8610, "total_functions": 142, "total_specs": 37, "total_tests": 28},
    "efficiency": {"tokens_per_task": 50000, "stall_rate": 0.15},
    "quality": {"test_pass_rate": 0.93, "rollback_count": 0}
  }
}
EOF

# Capture display output
output=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_get_latest)"
    eval "$(extract_funcs _metrics_display_health)"
    _metrics_display_health
)

# --- Test 2: Output contains CAPABILITY section ---
assert_contains "$output" "CAPABILITY" "Dashboard includes CAPABILITY section"

# --- Test 3: Output contains EFFICIENCY section ---
assert_contains "$output" "EFFICIENCY" "Dashboard includes EFFICIENCY section"

# --- Test 4: Output contains QUALITY section ---
assert_contains "$output" "QUALITY" "Dashboard includes QUALITY section"

# --- Test 5: Output contains INNOVATION section ---
assert_contains "$output" "INNOVATION" "Dashboard includes INNOVATION section"

# --- Test 6: Output contains HEALTH section ---
assert_contains "$output" "HEALTH" "Dashboard includes HEALTH section"

# --- Test 7: Output contains Current column header ---
assert_contains "$output" "Current" "Dashboard has Current column"

# --- Test 8: Output contains Baseline column header ---
assert_contains "$output" "Baseline" "Dashboard has Baseline column"

# --- Test 9: Output contains Trend column header ---
assert_contains "$output" "Trend" "Dashboard has Trend column"

# --- Test 10: Shows actual metric values from latest snapshot ---
assert_contains "$output" "9,240" "Shows formatted total_lines value"

# --- Test 11: Shows trend indicators ---
# The output should contain either up/down arrow or stable indicator
if echo "$output" | grep -qE '(▲|▼|—)'; then
    echo "PASS: Dashboard includes trend indicators"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Dashboard should include trend indicators (▲/▼/—)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Shows budget bar chart ---
assert_contains "$output" "65%" "Shows budget utilization percentage"

# --- Test 13: Shows convergence risk ---
assert_contains "$output" "LOW" "Shows convergence risk status"

# --- Test 14: Shows last snapshot info ---
assert_contains "$output" "cycle 12" "Shows last cycle number"

# --- Test 15: Returns empty when no metrics file exists ---
no_output=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton/nonexistent"
    export METRICS_ENABLED="true"
    log() { true; }
    eval "$(extract_funcs _metrics_get_latest)"
    eval "$(extract_funcs _metrics_display_health)"
    _metrics_display_health 2>&1
)

if echo "$no_output" | grep -qi "no metrics"; then
    echo "PASS: Shows 'no metrics' message when no data exists"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should show 'no metrics' message when no data exists (got: $no_output)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: Returns early when METRICS_ENABLED is false ---
disabled_output=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="false"
    log() { true; }
    eval "$(extract_funcs _metrics_get_latest)"
    eval "$(extract_funcs _metrics_display_health)"
    _metrics_display_health 2>&1
)

if [ -z "$disabled_output" ] || echo "$disabled_output" | grep -qi "disabled"; then
    echo "PASS: Returns empty or disabled message when METRICS_ENABLED=false"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should return empty or disabled message when METRICS_ENABLED=false (got: $disabled_output)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 17: Innovation section shows garden counts ---
assert_contains "$output" "seeds" "Innovation section shows seed count"
assert_contains "$output" "sprouts" "Innovation section shows sprout count"
assert_contains "$output" "blooms" "Innovation section shows bloom count"

# --- Test 18: Health section shows circuit breaker status ---
assert_contains "$output" "Circuit" "Health section shows circuit breaker info"

test_summary
