#!/usr/bin/env bash
# tests/test_evolve_budget.sh — Tests for spec-41 §9 _evolve_check_budget()
# Verifies per-cycle budget calculation as min(max_cost_per_cycle_usd,
# remaining_allowance / estimated_remaining_cycles) and budget ceiling
# breaker enforcement when exceeded.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_check_budget function ---
grep_result=$(grep -c '^_evolve_check_budget()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_check_budget()"

# --- Test 2: _evolve_check_budget uses EVOLVE_MAX_COST_PER_CYCLE ---
grep_result=$(grep -A 80 '^_evolve_check_budget()' "$script_file" | grep -c 'EVOLVE_MAX_COST_PER_CYCLE' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_budget uses EVOLVE_MAX_COST_PER_CYCLE"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should use EVOLVE_MAX_COST_PER_CYCLE" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_check_budget reads budget.json for cost tracking ---
grep_result=$(grep -A 80 '^_evolve_check_budget()' "$script_file" | grep -c 'budget\.json\|estimated_cost_usd' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_budget reads budget.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should read budget.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_check_budget calculates remaining allowance ---
grep_result=$(grep -A 80 '^_evolve_check_budget()' "$script_file" | grep -c 'remaining\|BUDGET_MAX_USD\|max_cost_usd' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_budget calculates remaining budget"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should calculate remaining budget" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_check_budget calls _safety_update_breaker for budget_ceiling ---
grep_result=$(grep -A 80 '^_evolve_check_budget()' "$script_file" | grep -c '_safety_update_breaker.*budget_ceiling\|budget_ceiling' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_budget enforces budget_ceiling breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should enforce budget_ceiling breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_check_budget outputs per-cycle budget amount ---
grep_result=$(grep -A 80 '^_evolve_check_budget()' "$script_file" | grep -c 'cycle_budget\|per.cycle' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_budget computes per-cycle budget"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should compute per-cycle budget" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_check_budget returns 0 (budget OK) and 1 (exceeded) ---
grep_result=$(grep -A 80 '^_evolve_check_budget()' "$script_file" | grep -c 'return 0\|return 1' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_check_budget has both OK and exceeded return paths"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should return 0 (OK) and 1 (exceeded)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Functional test — budget within limits returns OK ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/evolution"

export AUTOMATON_DIR="$TMPDIR_TEST"
export EVOLVE_MAX_COST_PER_CYCLE="5.00"
export BUDGET_MAX_USD=50
export LOG_FILE="$TMPDIR_TEST/test.log"

# Create a budget.json with plenty of budget remaining
jq -n '{
    mode: "api",
    limits: { max_cost_usd: 50 },
    used: { estimated_cost_usd: 10.00 }
}' > "$TMPDIR_TEST/budget.json"

# Extract function and required stubs
eval "$(sed -n '/^_evolve_check_budget()/,/^}/p' "$script_file")"

# Provide stubs
log() { echo "$@" >> "$LOG_FILE"; }
_safety_update_breaker() { echo "BREAKER: $1" >> "$LOG_FILE"; }
_safety_ensure_breakers_file() { true; }

result=$(_evolve_check_budget 1 5 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: Budget within limits → returns 0 (OK)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Budget within limits should return 0, got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Functional test — budget exhausted returns exceeded ---
jq -n '{
    mode: "api",
    limits: { max_cost_usd: 50 },
    used: { estimated_cost_usd: 49.50 }
}' > "$TMPDIR_TEST/budget.json"

# With only $0.50 remaining and max_cost_per_cycle of $5, budget is effectively exhausted
export EVOLVE_MAX_COST_PER_CYCLE="5.00"

result=$(_evolve_check_budget 1 5 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 1 ]; then
    echo "PASS: Budget exhausted → returns 1 (exceeded)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Budget exhausted should return 1, got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Functional test — budget ceiling breaker is tripped ---
if grep -q 'BREAKER.*budget_ceiling' "$LOG_FILE" 2>/dev/null; then
    echo "PASS: Budget ceiling breaker was tripped"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Budget ceiling breaker should be tripped when exceeded" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Functional test — per-cycle budget is min of max_cost and remaining/cycles ---
jq -n '{
    mode: "api",
    limits: { max_cost_usd: 50 },
    used: { estimated_cost_usd: 30.00 }
}' > "$TMPDIR_TEST/budget.json"
> "$LOG_FILE"

export EVOLVE_MAX_COST_PER_CYCLE="5.00"

# remaining = 20, estimated_remaining_cycles = 10 → per-cycle = min(5, 20/10) = 2.00
result=$(_evolve_check_budget 1 10 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: Budget calculation with remaining/cycles — returns OK"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Budget should be OK when remaining/cycles is valid, got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

# The cycle budget should be output on stdout
if echo "$result" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    echo "PASS: _evolve_check_budget outputs numeric cycle budget"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_budget should output numeric cycle budget, got: '$result'" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Functional test — allowance mode uses effective_allowance ---
jq -n '{
    mode: "allowance",
    limits: { effective_allowance: 36000000 },
    tokens_used_this_week: 10000000,
    used: { estimated_cost_usd: 0 }
}' > "$TMPDIR_TEST/budget.json"

export EVOLVE_MAX_COST_PER_CYCLE="5.00"

result=$(_evolve_check_budget 1 5 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: Allowance mode with remaining tokens → returns OK"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Allowance mode with remaining tokens should return OK, got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
