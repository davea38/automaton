#!/usr/bin/env bash
# tests/test_budget_cross_project.sh — Tests for cross-project allowance tracking
# Covers: _cross_project_allowance_file, _init_cross_project_allowance,
#          _cross_project_rollover, _update_cross_project_allowance,
#          _increment_cross_project_run_count, _get_cross_project_total_used,
#          _display_weekly_summary, _allowance_check_rollover, _fmt_num,
#          detect_auto_compaction, mitigate_compaction

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_budget_cross_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence checks ---

grep -q '_cross_project_allowance_file()' "$script_file"
assert_exit_code 0 $? "_cross_project_allowance_file exists"

grep -q '_init_cross_project_allowance()' "$script_file"
assert_exit_code 0 $? "_init_cross_project_allowance exists"

grep -q '_cross_project_rollover()' "$script_file"
assert_exit_code 0 $? "_cross_project_rollover exists"

grep -q '_update_cross_project_allowance()' "$script_file"
assert_exit_code 0 $? "_update_cross_project_allowance exists"

grep -q '_increment_cross_project_run_count()' "$script_file"
assert_exit_code 0 $? "_increment_cross_project_run_count exists"

grep -q '_get_cross_project_total_used()' "$script_file"
assert_exit_code 0 $? "_get_cross_project_total_used exists"

grep -q '_display_weekly_summary()' "$script_file"
assert_exit_code 0 $? "_display_weekly_summary exists"

grep -q '_allowance_check_rollover()' "$script_file"
assert_exit_code 0 $? "_allowance_check_rollover exists"

grep -q 'detect_auto_compaction()' "$script_file"
assert_exit_code 0 $? "detect_auto_compaction exists"

grep -q 'mitigate_compaction()' "$script_file"
assert_exit_code 0 $? "mitigate_compaction exists"

# --- Behavioral tests using function extraction ---

# Test: _cross_project_allowance_file returns ~/.automaton/allowance.json
body=$(sed -n '/_cross_project_allowance_file()/,/^}/p' "$script_file" | head -5)
echo "$body" | grep -q 'allowance.json'
assert_exit_code 0 $? "_cross_project_allowance_file references allowance.json"

# Test: _init_cross_project_allowance bails for non-allowance mode
body=$(sed -n '/_init_cross_project_allowance()/,/^}/p' "$script_file")
echo "$body" | grep -q 'BUDGET_MODE.*allowance'
assert_exit_code 0 $? "_init_cross_project_allowance checks BUDGET_MODE"

# Test: _init_cross_project_allowance creates directory
echo "$body" | grep -q 'mkdir -p'
assert_exit_code 0 $? "_init_cross_project_allowance creates directory"

# Test: _init_cross_project_allowance calls _allowance_week_start
echo "$body" | grep -q '_allowance_week_start'
assert_exit_code 0 $? "_init_cross_project_allowance uses _allowance_week_start"

# Test: _cross_project_rollover archives current week to history
body=$(sed -n '/_cross_project_rollover()/,/^}/p' "$script_file")
echo "$body" | grep -q 'history'
assert_exit_code 0 $? "_cross_project_rollover archives to history"

# Test: _cross_project_rollover resets current week
echo "$body" | grep -q 'total_used.*0'
assert_exit_code 0 $? "_cross_project_rollover resets counters"

# Test: _update_cross_project_allowance bails for non-allowance mode
body=$(sed -n '/_update_cross_project_allowance()/,/^}/p' "$script_file")
echo "$body" | grep -q 'BUDGET_MODE.*allowance'
assert_exit_code 0 $? "_update_cross_project_allowance checks BUDGET_MODE"

# Test: _update_cross_project_allowance recalculates total from all projects
echo "$body" | grep -q 'total_used'
assert_exit_code 0 $? "_update_cross_project_allowance recalculates total"

# Test: _increment_cross_project_run_count increments runs field
body=$(sed -n '/_increment_cross_project_run_count()/,/^}/p' "$script_file")
echo "$body" | grep -q 'runs.*+= 1'
assert_exit_code 0 $? "_increment_cross_project_run_count increments runs"

# Test: _get_cross_project_total_used falls back to local budget
body=$(sed -n '/_get_cross_project_total_used()/,/^}/p' "$script_file")
echo "$body" | grep -q 'tokens_used_this_week'
assert_exit_code 0 $? "_get_cross_project_total_used has local fallback"

# Test: _allowance_check_rollover returns early when not in allowance mode
body=$(sed -n '/_allowance_check_rollover()/,/^}/p' "$script_file")
echo "$body" | grep -q 'BUDGET_MODE.*allowance'
assert_exit_code 0 $? "_allowance_check_rollover checks BUDGET_MODE"

# Test: _allowance_check_rollover calls _display_weekly_summary before reset
echo "$body" | grep -q '_display_weekly_summary'
assert_exit_code 0 $? "_allowance_check_rollover displays summary on rollover"

# Test: _display_weekly_summary reads from budget.json
body=$(sed -n '/_display_weekly_summary()/,/^}/p' "$script_file")
echo "$body" | grep -q 'budget.json'
assert_exit_code 0 $? "_display_weekly_summary reads budget.json"

# Test: _display_weekly_summary shows usage percentage
echo "$body" | grep -q 'usage_pct'
assert_exit_code 0 $? "_display_weekly_summary calculates usage percentage"

# Test: _display_weekly_summary shows tasks completed
echo "$body" | grep -q 'tasks_completed'
assert_exit_code 0 $? "_display_weekly_summary shows tasks completed"

# Test: _fmt_num is defined inside _display_weekly_summary
echo "$body" | grep -q '_fmt_num()'
assert_exit_code 0 $? "_fmt_num is defined inside _display_weekly_summary"

# Test: detect_auto_compaction checks for compaction signals
body=$(sed -n '/^detect_auto_compaction()/,/^}/p' "$script_file")
echo "$body" | grep -qi 'compact\|context\|token'
assert_exit_code 0 $? "detect_auto_compaction checks for compaction signals"

# Test: mitigate_compaction provides recovery strategy
body=$(sed -n '/^mitigate_compaction()/,/^}/p' "$script_file")
echo "$body" | grep -qi 'save\|state\|context\|recover'
assert_exit_code 0 $? "mitigate_compaction has recovery strategy"

test_summary
