#!/usr/bin/env bash
# tests/test_evolve_ideate.sh — Tests for spec-41 §3 IDEATE phase
# Verifies _evolve_ideate() in automaton.sh processes reflection summary,
# waters existing sprouts, evaluates sprout-to-bloom transitions, creates
# new ideas, links ideas to signals, recomputes priorities, and writes
# ideate.json to the cycle directory.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: automaton.sh defines _evolve_ideate function ---
grep_result=$(grep -c '^_evolve_ideate()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_ideate()"

# --- Test 2: _evolve_ideate takes a cycle_id parameter ---
grep_result=$(grep -A 5 '^_evolve_ideate()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate takes cycle_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should take cycle_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_ideate creates or references the cycle directory ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c 'mkdir.*cycle\|cycle_dir' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate creates or references cycle directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should create or reference cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_ideate reads reflect.json for reflection summary ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c 'reflect\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate reads reflect.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should read reflect.json for reflection summary" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_ideate waters existing ideas via _garden_water ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_garden_water' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate waters existing ideas via _garden_water"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should water existing ideas via _garden_water" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_ideate evaluates sprout-to-bloom via _garden_get_bloom_candidates ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_garden_get_bloom_candidates\|bloom' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate evaluates bloom candidates"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should evaluate sprout-to-bloom transitions" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_ideate can create new ideas via _garden_plant_seed ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_garden_plant_seed' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate creates new ideas via _garden_plant_seed"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should create new ideas via _garden_plant_seed" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_ideate links ideas to signals via _signal_link_idea ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_signal_link_idea' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate links ideas to signals via _signal_link_idea"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should link ideas to signals via _signal_link_idea" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _evolve_ideate recomputes priorities via _garden_recompute_priorities ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_garden_recompute_priorities' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate recomputes priorities via _garden_recompute_priorities"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should call _garden_recompute_priorities" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_ideate writes ideate.json output ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c 'ideate\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate writes ideate.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should write ideate.json to cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _evolve_ideate uses log function for reporting ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c 'log "EVOLVE"' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_ideate uses log function for reporting (at least 2 log calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should use log function for reporting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: ideate.json output includes required fields ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c 'ideas_watered\|ideas_promoted_to_bloom\|ideas_created\|bloom_candidates' || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: ideate.json includes required output fields"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: ideate.json should include ideas_watered, ideas_promoted_to_bloom, ideas_created, bloom_candidates" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _evolve_ideate queries active signals ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_signal_get_active\|active.*signal' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate queries active signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should query active signals" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _evolve_ideate rebuilds garden index ---
grep_result=$(grep -A 200 '^_evolve_ideate()' "$script_file" | grep -c '_garden_rebuild_index' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_ideate rebuilds garden index"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_ideate should rebuild garden index" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
