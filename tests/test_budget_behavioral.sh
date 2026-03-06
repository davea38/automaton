#!/usr/bin/env bash
# tests/test_budget_behavioral.sh — Behavioral tests for lib/budget.sh functions.
# Actually executes budget functions and verifies state changes in budget.json.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
setup_test_dir

# Minimal stubs for dependencies
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"
log() { :; }
emit_event() { :; }

# Source the budget module
source "$_PROJECT_DIR/lib/budget.sh"

# --- Config defaults for budget ---
BUDGET_MODE="api"
BUDGET_MAX_TOKENS=10000000
BUDGET_MAX_USD=50
BUDGET_PHASE_RESEARCH=500000
BUDGET_PHASE_PLAN=1000000
BUDGET_PHASE_BUILD=7000000
BUDGET_PHASE_REVIEW=1500000
BUDGET_PER_ITERATION=500000
BUDGET_WEEKLY_ALLOWANCE=45000000
BUDGET_ALLOWANCE_RESET_DAY="monday"
BUDGET_RESERVE_PERCENTAGE=20

# Stubs for cross-project allowance (avoid side effects)
_init_cross_project_allowance() { :; }
BOOTSTRAP_TOKENS_SAVED=0
BOOTSTRAP_TIME_MS=0

# --- Test 1: initialize_budget creates valid budget.json in api mode ---
initialize_budget
assert_file_exists "$AUTOMATON_DIR/budget.json" "initialize_budget creates budget.json"
budget_json=$(cat "$AUTOMATON_DIR/budget.json")
assert_json_valid "$budget_json" "budget.json is valid JSON"
assert_json_field "$budget_json" '.mode' "api" "budget mode is api"
assert_json_field "$budget_json" '.limits.max_cost_usd' "50" "max cost limit is 50"
assert_json_field "$budget_json" '.used.total_input' "0" "initial input tokens is 0"
assert_json_field "$budget_json" '.used.total_output' "0" "initial output tokens is 0"

# --- Test 2: initialize_budget in allowance mode ---
rm -f "$AUTOMATON_DIR/budget.json"
BUDGET_MODE="allowance"
initialize_budget
budget_json=$(cat "$AUTOMATON_DIR/budget.json")
assert_json_field "$budget_json" '.mode' "allowance" "allowance mode set correctly"
effective=$(echo "$budget_json" | jq '.limits.effective_allowance')
assert_equals "36000000" "$effective" "effective allowance is 80% of weekly allowance"
BUDGET_MODE="api"

# --- Test 3: update_budget accumulates token usage ---
rm -f "$AUTOMATON_DIR/budget.json"
initialize_budget
current_phase="build"
phase_iteration=1
iteration=1
# update_budget args: model input output cache_create cache_read cost duration task status
update_budget "sonnet" 1000 2000 500 200 0.05 30 "Task 1" "success"
budget_json=$(cat "$AUTOMATON_DIR/budget.json")
used_input=$(echo "$budget_json" | jq '.used.total_input')
used_output=$(echo "$budget_json" | jq '.used.total_output')
assert_equals "1000" "$used_input" "input tokens accumulated correctly"
assert_equals "2000" "$used_output" "output tokens accumulated correctly"

# --- Test 4: update_budget accumulates across multiple iterations ---
phase_iteration=2
iteration=2
update_budget "sonnet" 3000 4000 100 50 0.10 25 "Task 2" "success"
budget_json=$(cat "$AUTOMATON_DIR/budget.json")
used_input=$(echo "$budget_json" | jq '.used.total_input')
used_output=$(echo "$budget_json" | jq '.used.total_output')
assert_equals "4000" "$used_input" "input tokens accumulated across iterations"
assert_equals "6000" "$used_output" "output tokens accumulated across iterations"

# --- Test 5: check_budget returns 0 when within limits ---
check_budget 1000 2000
assert_exit_code 0 $? "check_budget passes when within limits"

# --- Test 6: budget history tracks iterations ---
history_len=$(jq '.history | length' "$AUTOMATON_DIR/budget.json")
assert_equals "2" "$history_len" "budget history records two iterations"

# --- Test 7: per-phase tracking records build tokens ---
budget_json=$(cat "$AUTOMATON_DIR/budget.json")
phase_input=$(echo "$budget_json" | jq '.used.by_phase.build.input')
if [ "$phase_input" -gt 0 ]; then
    echo "PASS: per-phase tracking records build input tokens"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: per-phase tracking should record build input tokens" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: estimated cost accumulates ---
cost=$(echo "$budget_json" | jq '.used.estimated_cost_usd')
expected_cost="0.15"
assert_equals "$expected_cost" "$cost" "estimated cost accumulates correctly"

test_summary
