#!/usr/bin/env bash
# tests/test_budget_pacing.sh — Tests for budget pacing functions (spec-35)
# Covers _allowance_week_start, _allowance_week_end, _calculate_daily_budget,
# and _check_daily_budget_pacing.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

setup_test_dir
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Stub log to prevent missing function errors
log() { :; }

source "$_PROJECT_DIR/lib/config.sh"
source "$_PROJECT_DIR/lib/budget.sh"

# --- Test 1: _allowance_week_start returns a valid date ---
BUDGET_ALLOWANCE_RESET_DAY="monday"
week_start=$(_allowance_week_start)
assert_matches "$week_start" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "_allowance_week_start returns ISO date"

# --- Test 2: _allowance_week_start returns a Monday when reset=monday ---
BUDGET_ALLOWANCE_RESET_DAY="monday"
week_start=$(_allowance_week_start)
dow=$(date -d "$week_start" +%u 2>/dev/null || date -jf "%Y-%m-%d" "$week_start" +%u 2>/dev/null)
assert_equals "1" "$dow" "_allowance_week_start with monday returns a Monday"

# --- Test 3: _allowance_week_start returns a Friday when reset=friday ---
BUDGET_ALLOWANCE_RESET_DAY="friday"
week_start=$(_allowance_week_start)
dow=$(date -d "$week_start" +%u 2>/dev/null || date -jf "%Y-%m-%d" "$week_start" +%u 2>/dev/null)
assert_equals "5" "$dow" "_allowance_week_start with friday returns a Friday"

# --- Test 4: _allowance_week_end is 6 days after start ---
BUDGET_ALLOWANCE_RESET_DAY="monday"
week_start=$(_allowance_week_start)
week_end=$(_allowance_week_end "$week_start")
start_epoch=$(date -d "$week_start" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_start" +%s)
end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s)
diff_days=$(( (end_epoch - start_epoch) / 86400 ))
assert_equals "6" "$diff_days" "_allowance_week_end is 6 days after week_start"

# --- Test 5: _allowance_week_start handles invalid reset day gracefully ---
BUDGET_ALLOWANCE_RESET_DAY="invalid"
week_start=$(_allowance_week_start)
assert_matches "$week_start" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "_allowance_week_start handles invalid reset day"

# --- Test 6: _calculate_daily_budget returns a positive number ---
BUDGET_ALLOWANCE_RESET_DAY="monday"
BUDGET_WEEKLY_ALLOWANCE=45000000
BUDGET_RESERVE_PERCENTAGE=20
BUDGET_MODE="allowance"
# Create a budget.json for the function
week_start=$(_allowance_week_start)
week_end=$(_allowance_week_end "$week_start")
cat > "$AUTOMATON_DIR/budget.json" <<EOF
{
    "mode": "allowance",
    "weekly_allowance": $BUDGET_WEEKLY_ALLOWANCE,
    "tokens_used": 0,
    "week_start": "$week_start",
    "week_end": "$week_end",
    "tokens_remaining": 36000000
}
EOF
daily=$(_calculate_daily_budget)
if [ "$daily" -gt 0 ] 2>/dev/null; then
    echo "PASS: _calculate_daily_budget returns positive number ($daily)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _calculate_daily_budget should return positive number (got '$daily')" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _calculate_daily_budget with zero remaining returns at least 1-day pace ---
cat > "$AUTOMATON_DIR/budget.json" <<EOF
{
    "mode": "allowance",
    "weekly_allowance": $BUDGET_WEEKLY_ALLOWANCE,
    "tokens_used": 45000000,
    "week_start": "$week_start",
    "week_end": "$week_end",
    "tokens_remaining": 0
}
EOF
daily=$(_calculate_daily_budget)
# With 0 remaining, daily budget should be 0 (not negative or error)
if [ "$daily" -ge 0 ] 2>/dev/null; then
    echo "PASS: _calculate_daily_budget with zero remaining returns non-negative ($daily)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _calculate_daily_budget with zero remaining should return non-negative (got '$daily')" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _check_daily_budget_pacing exits early for non-allowance mode ---
BUDGET_MODE="api"
_check_daily_budget_pacing
rc=$?
assert_equals "0" "$rc" "_check_daily_budget_pacing exits 0 for non-allowance mode"

# --- Test 9: _check_daily_budget_pacing runs for allowance mode ---
BUDGET_MODE="allowance"
cat > "$AUTOMATON_DIR/budget.json" <<EOF
{
    "mode": "allowance",
    "weekly_allowance": $BUDGET_WEEKLY_ALLOWANCE,
    "tokens_used": 0,
    "week_start": "$week_start",
    "week_end": "$week_end",
    "tokens_remaining": 36000000
}
EOF
_check_daily_budget_pacing
rc=$?
assert_equals "0" "$rc" "_check_daily_budget_pacing runs successfully for allowance mode"

test_summary
