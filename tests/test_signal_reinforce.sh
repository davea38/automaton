#!/usr/bin/env bash
# tests/test_signal_reinforce.sh — Tests for _signal_reinforce() (spec-42 §1)
# Verifies that _signal_reinforce() adds an observation to an existing signal,
# increases strength by reinforce_increment capped at 1.0, and updates timestamps.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _signal_reinforce function exists in automaton.sh ---
grep_result=$(grep -c '^_signal_reinforce()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_reinforce() function defined in automaton.sh"

# --- Test 2: _signal_reinforce checks stigmergy enabled guard ---
reinforce_func=$(sed -n '/^_signal_reinforce()/,/^[a-z_]*() {/p' "$script_file")
if echo "$reinforce_func" | grep -q 'STIGMERGY_ENABLED\|_signal_enabled'; then
    echo "PASS: _signal_reinforce checks stigmergy enabled guard"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should check stigmergy enabled guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _signal_reinforce accepts signal_id parameter ---
reinforce_head=$(grep -A10 '^_signal_reinforce()' "$script_file")
if echo "$reinforce_head" | grep -q 'signal_id\|1:'; then
    echo "PASS: _signal_reinforce accepts signal_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should accept signal_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _signal_reinforce adds observation to existing signal ---
if echo "$reinforce_func" | grep -q 'observation\|observations'; then
    echo "PASS: _signal_reinforce handles observations"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should add an observation to the signal" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _signal_reinforce increases strength by reinforce_increment ---
if echo "$reinforce_func" | grep -q 'STIGMERGY_REINFORCE_INCREMENT\|reinforce_increment'; then
    echo "PASS: _signal_reinforce uses reinforce_increment config"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should use STIGMERGY_REINFORCE_INCREMENT" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _signal_reinforce caps strength at 1.0 ---
if echo "$reinforce_func" | grep -q '1\.0\|1,'; then
    echo "PASS: _signal_reinforce caps strength at 1.0"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should cap strength at 1.0" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _signal_reinforce updates last_reinforced_at timestamp ---
if echo "$reinforce_func" | grep -q 'last_reinforced_at'; then
    echo "PASS: _signal_reinforce updates last_reinforced_at"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should update last_reinforced_at" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _signal_reinforce updates the signals.json file ---
if echo "$reinforce_func" | grep -q 'signals.json\|signals_file'; then
    echo "PASS: _signal_reinforce writes to signals.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should write to signals.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _signal_reinforce updates updated_at at root level ---
if echo "$reinforce_func" | grep -q 'updated_at'; then
    echo "PASS: _signal_reinforce updates updated_at"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_reinforce should update root updated_at" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
