#!/usr/bin/env bash
# tests/test_signal_emit.sh — Tests for _signal_emit() (spec-42 §1)
# Verifies that _signal_emit() creates new signals with correct schema,
# reinforces existing signals when a match is found, and lazy-initializes
# .automaton/signals.json on first emission.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _signal_emit function exists in automaton.sh ---
grep_result=$(grep -c '^_signal_emit()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_emit() function defined in automaton.sh"

# --- Test 2: _signal_emit checks stigmergy enabled guard ---
# The function should return early if STIGMERGY_ENABLED is false
grep_result=$(grep -A5 '^_signal_emit()' "$script_file" | grep -c 'STIGMERGY_ENABLED\|_signal_enabled' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _signal_emit checks stigmergy enabled guard"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should check stigmergy enabled guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _signal_emit references required parameters ---
# Should accept type, title, description, agent, cycle, detail
emit_body=$(sed -n '/^_signal_emit()/,/^[^ ]/p' "$script_file" | head -20)
params_found=0
for param in "type" "title" "description"; do
    if echo "$emit_body" | grep -q "$param"; then
        ((params_found++))
    fi
done
if [ "$params_found" -ge 3 ]; then
    echo "PASS: _signal_emit accepts type, title, description parameters"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should accept type, title, description (found $params_found/3)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _signal_emit creates signals.json lazily ---
# Should create the signals file if it doesn't exist (lazy init per spec-42 §10)
emit_func=$(sed -n '/^_signal_emit()/,/^[a-z_]*() {/p' "$script_file")
if echo "$emit_func" | grep -q 'signals.json'; then
    echo "PASS: _signal_emit references signals.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should reference signals.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _signal_emit creates signal with correct ID format (SIG-NNN) ---
if echo "$emit_func" | grep -q 'SIG-'; then
    echo "PASS: _signal_emit uses SIG- ID prefix"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should use SIG-NNN ID format" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _signal_emit sets initial_strength from config ---
if echo "$emit_func" | grep -q 'STIGMERGY_INITIAL_STRENGTH\|initial_strength'; then
    echo "PASS: _signal_emit uses initial_strength config"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should use STIGMERGY_INITIAL_STRENGTH" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _signal_emit calls _signal_find_match for dedup ---
if echo "$emit_func" | grep -q '_signal_find_match'; then
    echo "PASS: _signal_emit calls _signal_find_match for dedup"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should call _signal_find_match for duplicate detection" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _signal_emit calls _signal_reinforce when match found ---
if echo "$emit_func" | grep -q '_signal_reinforce'; then
    echo "PASS: _signal_emit calls _signal_reinforce for matching signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should call _signal_reinforce when match found" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _signal_emit uses decay_rate from signal type defaults ---
if echo "$emit_func" | grep -q 'decay_rate'; then
    echo "PASS: _signal_emit handles decay_rate"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should set decay_rate from signal type defaults" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _signal_emit updates next_id in signals.json ---
if echo "$emit_func" | grep -q 'next_id'; then
    echo "PASS: _signal_emit manages next_id"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_emit should update next_id" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Lazy init — signals.json should NOT be created in initialize_state ---
init_func=$(sed -n '/^initialize_state()/,/^[a-z_]*() {/p' "$script_file")
if echo "$init_func" | grep -q 'signals.json'; then
    echo "FAIL: signals.json should NOT be created in initialize_state (lazy init)" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: signals.json is not created in initialize_state (lazy init)"
    ((_TEST_PASS_COUNT++))
fi

test_summary
