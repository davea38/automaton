#!/usr/bin/env bash
# tests/test_evolve_cycle.sh — Tests for spec-41 §8 _evolve_run_cycle()
# Verifies _evolve_run_cycle() orchestrates the 5-phase sequence
# (REFLECT, IDEATE, EVALUATE, IMPLEMENT, OBSERVE), manages per-cycle
# budget allocation, takes pre/post-cycle metrics snapshots, creates
# the cycle directory, and handles phase failures.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_run_cycle function ---
grep_result=$(grep -c '^_evolve_run_cycle()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_run_cycle()"

# --- Test 2: _evolve_run_cycle takes cycle_id parameter ---
grep_result=$(grep -A 5 '^_evolve_run_cycle()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle takes cycle_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should take cycle_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_run_cycle creates cycle directory ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c 'mkdir.*cycle\|cycle_dir' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle creates or references cycle directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should create cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_run_cycle takes pre-cycle metrics snapshot ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c '_metrics_snapshot' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle takes pre-cycle metrics snapshot"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should take pre-cycle metrics snapshot" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_run_cycle calls all 5 phases ---
for phase_fn in _evolve_reflect _evolve_ideate _evolve_evaluate _evolve_implement _evolve_observe; do
    grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c "$phase_fn" || true)
    if [ "$grep_result" -ge 1 ]; then
        echo "PASS: _evolve_run_cycle calls $phase_fn"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: _evolve_run_cycle should call $phase_fn" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Test 6: _evolve_run_cycle checks circuit breakers ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c '_safety_check_breakers\|_safety_any_breaker_tripped' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle checks circuit breakers"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should check circuit breakers" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_run_cycle handles phase failures ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c 'phase.*fail\|FAIL\|abort\|skip.*OBSERVE\|return 1' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle handles phase failures"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should handle phase failures" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_run_cycle writes cycle summary ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c 'cycle.*json\|summary.*json\|jq.*cycle' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle writes cycle summary"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should write cycle summary" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _evolve_run_cycle logs start and completion ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c 'log.*EVOLVE.*cycle\|log.*EVOLVE.*CYCLE' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_run_cycle logs cycle start and completion"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should log cycle start and completion (found $grep_result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_run_cycle handles evaluate.json for skip-to-observe ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c 'evaluate.*json\|no_candidate\|skipped' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle checks evaluate result for skip scenarios"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should check evaluate result for skip-to-observe" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _evolve_run_cycle persists state at end of cycle ---
grep_result=$(grep -A 300 '^_evolve_run_cycle()' "$script_file" | grep -c '_garden_rebuild_index\|commit.*state\|persist' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_cycle persists state"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_cycle should persist state at end of cycle" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
