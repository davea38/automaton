#!/usr/bin/env bash
# tests/test_evolve_reflect.sh — Tests for spec-41 §3 REFLECT phase
# Verifies _evolve_reflect() in automaton.sh processes metrics trends,
# emits signals, auto-seeds garden ideas, prunes expired items, decays signals,
# and writes reflect.json to the cycle directory.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_reflect function ---
grep_result=$(grep -c '^_evolve_reflect()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_reflect()"

# --- Test 2: _evolve_reflect takes a cycle_id parameter ---
grep_result=$(grep -A 5 '^_evolve_reflect()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect takes cycle_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should take cycle_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_reflect creates the cycle directory ---
grep_result=$(grep -A 80 '^_evolve_reflect()' "$script_file" | grep -c 'mkdir.*cycle\|cycle_dir' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect creates or references cycle directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should create or reference cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_reflect calls _metrics_analyze_trends ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_metrics_analyze_trends' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect calls _metrics_analyze_trends"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should call _metrics_analyze_trends" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_reflect calls _signal_emit for metric alerts ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_signal_emit' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect emits signals via _signal_emit"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should emit signals via _signal_emit" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_reflect calls _garden_plant_seed for auto-seeding ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_garden_plant_seed' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect auto-seeds garden ideas via _garden_plant_seed"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should auto-seed garden ideas via _garden_plant_seed" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_reflect calls _garden_prune_expired ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_garden_prune_expired' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect prunes expired garden items"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should call _garden_prune_expired" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_reflect calls _signal_decay_all ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_signal_decay_all' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect decays all signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should call _signal_decay_all" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _evolve_reflect writes reflect.json output ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c 'reflect\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect writes reflect.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should write reflect.json to cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_reflect checks _signal_get_unlinked for auto-seeding from strong signals ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_signal_get_unlinked\|unlinked' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect checks for unlinked signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should check for unlinked strong signals for auto-seeding" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _evolve_reflect uses log function for reporting ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c 'log "EVOLVE"' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_reflect uses log function for reporting (at least 2 log calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should use log function for reporting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: reflect.json output includes required fields ---
# Check that the jq template for reflect.json includes cycle_id, signals_emitted, ideas_seeded
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c 'signals_emitted\|ideas_seeded\|ideas_pruned\|signals_decayed' || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: reflect.json includes required output fields (signals_emitted, ideas_seeded, etc.)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: reflect.json should include signals_emitted, ideas_seeded, ideas_pruned, signals_decayed" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _evolve_reflect links signals to seeded ideas ---
grep_result=$(grep -A 120 '^_evolve_reflect()' "$script_file" | grep -c '_signal_link_idea' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_reflect links signals to seeded ideas"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_reflect should link signals to seeded garden ideas" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
