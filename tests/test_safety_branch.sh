#!/usr/bin/env bash
# tests/test_safety_branch.sh — Tests for spec-45 §1 branch-based isolation
# Verifies that automaton.sh contains the branch isolation functions for
# the evolution IMPLEMENT phase: create, merge, abandon, and detection.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _safety_branch_create() function exists ---
grep_result=$(grep -c '^_safety_branch_create()' "$script_file" || true)
assert_equals "1" "$grep_result" "_safety_branch_create() function exists in automaton.sh"

# --- Test 2: _safety_branch_create() uses the correct branch naming pattern ---
grep_result=$(grep -c 'automaton/evolve-.*cycle.*idea' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_create uses automaton/evolve-{cycle}-{idea} pattern"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_create should use automaton/evolve-{cycle}-{idea} branch pattern" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _safety_branch_create() does git checkout -b ---
grep_result=$(grep -A 20 '^_safety_branch_create()' "$script_file" | grep -c 'git checkout -b' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_create uses git checkout -b to create evolution branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_create should use git checkout -b for branch creation" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _safety_branch_create() saves the working branch ---
grep_result=$(grep -c 'WORKING_BRANCH' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_create tracks the WORKING_BRANCH"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_create should track the working branch before switching" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _safety_branch_merge() function exists ---
grep_result=$(grep -c '^_safety_branch_merge()' "$script_file" || true)
assert_equals "1" "$grep_result" "_safety_branch_merge() function exists in automaton.sh"

# --- Test 6: _safety_branch_merge() switches back to working branch ---
# The merge function should checkout the working branch first, then merge
grep_result=$(grep -A 20 '^_safety_branch_merge()' "$script_file" | grep -c 'git checkout.*WORKING_BRANCH' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_merge switches to working branch before merge"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_merge should switch to working branch before merging" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _safety_branch_merge() does git merge ---
grep_result=$(grep -A 30 '^_safety_branch_merge()' "$script_file" | grep -c 'git merge' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_merge performs git merge"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_merge should perform git merge" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _safety_branch_abandon() function exists ---
grep_result=$(grep -c '^_safety_branch_abandon()' "$script_file" || true)
assert_equals "1" "$grep_result" "_safety_branch_abandon() function exists in automaton.sh"

# --- Test 9: _safety_branch_abandon() switches back to working branch without deleting ---
grep_result=$(grep -A 20 '^_safety_branch_abandon()' "$script_file" | grep -c 'git checkout.*WORKING_BRANCH' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_abandon switches back to working branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_abandon should switch back to working branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _safety_branch_abandon() does NOT delete the branch ---
grep_result=$(grep -A 20 '^_safety_branch_abandon()' "$script_file" | grep -c 'git branch -[dD]' || true)
assert_equals "0" "$grep_result" "_safety_branch_abandon does NOT delete the evolution branch (preserved for debugging)"

# --- Test 11: _safety_branch_is_evolution() function exists ---
grep_result=$(grep -c '^_safety_branch_is_evolution()' "$script_file" || true)
assert_equals "1" "$grep_result" "_safety_branch_is_evolution() function exists in automaton.sh"

# --- Test 12: _safety_branch_is_evolution() checks for automaton/evolve- prefix ---
grep_result=$(grep -A 10 '^_safety_branch_is_evolution()' "$script_file" | grep -c 'automaton/evolve-' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_is_evolution checks for automaton/evolve- prefix"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_is_evolution should check for automaton/evolve- prefix" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _safety_branch_create() logs the branch creation ---
grep_result=$(grep -A 15 '^_safety_branch_create()' "$script_file" | grep -c 'log.*SAFETY' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_create logs branch creation with SAFETY prefix"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_create should log with SAFETY prefix" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _safety_branch_abandon() logs the abandonment with preservation message ---
grep_result=$(grep -A 20 '^_safety_branch_abandon()' "$script_file" | grep -c 'preserv' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_abandon logs preservation message"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_abandon should log that the branch is preserved for debugging" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: _safety_branch_merge() logs the merge result ---
grep_result=$(grep -A 30 '^_safety_branch_merge()' "$script_file" | grep -c 'log.*SAFETY' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _safety_branch_merge logs with SAFETY prefix"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _safety_branch_merge should log with SAFETY prefix" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: _safety_branch_get_name() helper exists ---
grep_result=$(grep -c '^_safety_branch_get_name()' "$script_file" || true)
assert_equals "1" "$grep_result" "_safety_branch_get_name() helper exists for building branch names"

test_summary
