#!/usr/bin/env bash
# tests/test_evolve_convergence.sh — Tests for spec-41 §8 _evolve_check_convergence()
# Verifies convergence detection when consecutive_no_improvement >= convergence_threshold
# or no bloom candidates for idle_garden_threshold consecutive cycles.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_check_convergence function ---
grep_result=$(grep -c '^_evolve_check_convergence()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_check_convergence()"

# --- Test 2: _evolve_check_convergence reads cycle summaries from evolution dir ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'cycle-summary\|evolution.*cycle' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_convergence reads cycle summaries"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should read cycle summaries" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_check_convergence uses EVOLVE_CONVERGENCE_THRESHOLD ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'EVOLVE_CONVERGENCE_THRESHOLD' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_convergence uses EVOLVE_CONVERGENCE_THRESHOLD"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should use EVOLVE_CONVERGENCE_THRESHOLD" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_check_convergence uses EVOLVE_IDLE_GARDEN_THRESHOLD ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'EVOLVE_IDLE_GARDEN_THRESHOLD' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_convergence uses EVOLVE_IDLE_GARDEN_THRESHOLD"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should use EVOLVE_IDLE_GARDEN_THRESHOLD" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_check_convergence checks observe_outcome for harvest ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'harvest\|observe_outcome' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_convergence checks observe_outcome for improvement"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should check observe_outcome for improvement" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_check_convergence checks bloom candidates ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'bloom\|eval_result\|no_bloom' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_convergence checks bloom candidate availability"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should check bloom candidate availability" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_check_convergence returns convergence reason ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'no_improvement\|idle_garden\|reason\|converged' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_check_convergence outputs convergence reason"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should output convergence reason" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_check_convergence returns 0 for converged, 1 for not converged ---
grep_result=$(grep -A 100 '^_evolve_check_convergence()' "$script_file" | grep -c 'return 0\|return 1' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_check_convergence has both converged and not-converged return paths"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_check_convergence should return 0 (converged) and 1 (not converged)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Functional test — no cycles means not converged ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/evolution"

# Source minimal config
export AUTOMATON_DIR="$TMPDIR_TEST"
export EVOLVE_CONVERGENCE_THRESHOLD=3
export EVOLVE_IDLE_GARDEN_THRESHOLD=2
export LOG_FILE="$TMPDIR_TEST/test.log"

# Extract and test the function
eval "$(sed -n '/^_evolve_check_convergence()/,/^}/p' "$script_file")"

# Provide stub for log function
log() { echo "$@" >> "$LOG_FILE"; }

result=$(_evolve_check_convergence 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 1 ]; then
    echo "PASS: No cycles → not converged (rc=1)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: No cycles should return not converged (rc=1), got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Functional test — consecutive no-improvement triggers convergence ---
for i in 1 2 3; do
    padded=$(printf "%03d" "$i")
    mkdir -p "$TMPDIR_TEST/evolution/cycle-${padded}"
    jq -n --argjson cid "$i" '{
        cycle_id: $cid,
        status: "completed",
        eval_result: "approved",
        observe_outcome: "wilt"
    }' > "$TMPDIR_TEST/evolution/cycle-${padded}/cycle-summary.json"
done

result=$(_evolve_check_convergence 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: 3 consecutive no-improvement cycles → converged (threshold=3)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: 3 consecutive no-improvement cycles should converge (threshold=3), got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

# Check the reason
if echo "$result" | grep -q 'no_improvement'; then
    echo "PASS: Convergence reason includes no_improvement"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Convergence reason should include no_improvement, got: $result" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Functional test — harvest breaks the consecutive streak ---
rm -rf "$TMPDIR_TEST/evolution/cycle-"*
for i in 1 2; do
    padded=$(printf "%03d" "$i")
    mkdir -p "$TMPDIR_TEST/evolution/cycle-${padded}"
    jq -n --argjson cid "$i" '{
        cycle_id: $cid,
        status: "completed",
        eval_result: "approved",
        observe_outcome: "wilt"
    }' > "$TMPDIR_TEST/evolution/cycle-${padded}/cycle-summary.json"
done
# Cycle 3 has a harvest
mkdir -p "$TMPDIR_TEST/evolution/cycle-003"
jq -n '{cycle_id: 3, status: "completed", eval_result: "approved", observe_outcome: "harvest"}' \
    > "$TMPDIR_TEST/evolution/cycle-003/cycle-summary.json"

result=$(_evolve_check_convergence 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 1 ]; then
    echo "PASS: Harvest breaks no-improvement streak → not converged"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Harvest should break the streak, got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Functional test — idle garden triggers convergence ---
rm -rf "$TMPDIR_TEST/evolution/cycle-"*
for i in 1 2; do
    padded=$(printf "%03d" "$i")
    mkdir -p "$TMPDIR_TEST/evolution/cycle-${padded}"
    jq -n --argjson cid "$i" '{
        cycle_id: $cid,
        status: "completed",
        eval_result: "skipped",
        observe_outcome: "none"
    }' > "$TMPDIR_TEST/evolution/cycle-${padded}/cycle-summary.json"
done

result=$(_evolve_check_convergence 2>/dev/null) && rc=$? || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: 2 consecutive idle garden cycles → converged (threshold=2)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: 2 consecutive idle garden cycles should converge (threshold=2), got rc=$rc" >&2
    ((_TEST_FAIL_COUNT++))
fi

if echo "$result" | grep -q 'idle_garden'; then
    echo "PASS: Convergence reason includes idle_garden"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Convergence reason should include idle_garden, got: $result" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
