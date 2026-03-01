#!/usr/bin/env bash
# tests/test_safety_rollback.sh — Tests for spec-45 §3 _safety_rollback()
# Verifies _safety_rollback() in automaton.sh handles rollback protocol:
#   1. Switches back to working branch (via _safety_branch_abandon)
#   2. Preserves failed evolution branch for debugging
#   3. Wilts the responsible idea
#   4. Emits quality_concern signal
#   5. Logs to self_modifications.json
#   6. Increments circuit breaker counters

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _safety_rollback function ---
grep_result=$(grep -c '^_safety_rollback()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _safety_rollback()"

# --- Test 2: _safety_rollback accepts cycle_id, idea_id, reason parameters ---
grep_result=$(grep -A3 '^_safety_rollback()' "$script_file" | grep -c 'cycle_id\|idea_id\|reason' || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: _safety_rollback accepts cycle_id, idea_id, reason parameters"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should accept cycle_id, idea_id, reason parameters" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _safety_rollback calls _safety_branch_abandon for branch switching ---
grep_result=$(grep -A30 '^_safety_rollback()' "$script_file" | grep -c '_safety_branch_abandon' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback calls _safety_branch_abandon"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should call _safety_branch_abandon to switch back to working branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _safety_rollback calls _garden_wilt to wilt the responsible idea ---
grep_result=$(grep -A30 '^_safety_rollback()' "$script_file" | grep -c '_garden_wilt' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback calls _garden_wilt"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should call _garden_wilt to wilt the responsible idea" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _safety_rollback calls _signal_emit with quality_concern ---
grep_result=$(grep -A30 '^_safety_rollback()' "$script_file" | grep -c '_signal_emit.*quality_concern\|quality_concern.*_signal_emit' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback emits quality_concern signal"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should emit quality_concern signal via _signal_emit" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _safety_rollback logs to self_modifications.json ---
grep_result=$(grep -A40 '^_safety_rollback()' "$script_file" | grep -c 'self_modifications.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback logs to self_modifications.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should log to self_modifications.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _safety_rollback calls _safety_update_breaker ---
grep_result=$(grep -A40 '^_safety_rollback()' "$script_file" | grep -c '_safety_update_breaker' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback calls _safety_update_breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should call _safety_update_breaker to increment circuit breaker counters" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _safety_rollback updates regression_cascade breaker ---
grep_result=$(grep -A40 '^_safety_rollback()' "$script_file" | grep -c 'regression_cascade' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback updates regression_cascade breaker"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should update regression_cascade breaker" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _safety_rollback logs the rollback event ---
grep_result=$(grep -A40 '^_safety_rollback()' "$script_file" | grep -c 'log.*SAFETY.*[Rr]ollback' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback logs rollback event"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should log the rollback event via log function" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _safety_rollback constructs branch name from cycle_id and idea_id ---
grep_result=$(grep -A40 '^_safety_rollback()' "$script_file" | grep -c 'cycle_id.*idea_id\|_safety_branch_get_name\|evolve-.*cycle\|branch_abandon.*cycle' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback uses cycle_id and idea_id for branch identification"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should use cycle_id and idea_id for branch identification" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _safety_rollback includes reason in garden wilt ---
grep_result=$(grep -A40 '^_safety_rollback()' "$script_file" | grep -c '_garden_wilt.*reason\|_garden_wilt.*Rollback' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_rollback includes reason in garden wilt"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_rollback should include reason in garden wilt call" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: _safety_rollback is in the Rollback section ---
grep_result=$(grep -c 'Rollback.*spec-45\|rollback.*protocol' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has Rollback section header"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have a Rollback section header for spec-45" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
