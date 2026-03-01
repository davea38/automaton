#!/usr/bin/env bash
# tests/test_evolve_resume.sh — Tests for spec-41 §11 evolution resume support
# Verifies that --evolve --resume reads the last cycle directory, determines
# which phase was interrupted, and resumes from that phase.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_resume_state function ---
grep_result=$(grep -c '^_evolve_resume_state()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_resume_state()"

# --- Test 2: _evolve_resume_state reads last cycle directory ---
grep_result=$(grep -A 80 '^_evolve_resume_state()' "$script_file" | grep -c 'cycle-\|cycle_dir\|evolution/' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_resume_state reads cycle directories"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_resume_state should read cycle directories" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_resume_state checks for phase summary files ---
# The function should check for reflect.json, ideate.json, evaluate.json,
# implement.json, observe.json to determine last completed phase
for phase_file in reflect.json ideate.json evaluate.json implement.json observe.json; do
    grep_result=$(grep -A 80 '^_evolve_resume_state()' "$script_file" | grep -c "$phase_file" || true)
    if [ "$grep_result" -ge 1 ]; then
        echo "PASS: _evolve_resume_state checks for $phase_file"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: _evolve_resume_state should check for $phase_file" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Test 4: _evolve_resume_state outputs resume cycle and phase ---
grep_result=$(grep -A 80 '^_evolve_resume_state()' "$script_file" | grep -c 'resume_cycle\|resume_phase' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_resume_state sets resume_cycle and resume_phase"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_resume_state should set resume_cycle and resume_phase (found $grep_result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_resume_state handles no evolution directory ---
grep_result=$(grep -A 80 '^_evolve_resume_state()' "$script_file" | grep -c 'no.*cycle\|no.*evolution\|fresh\|return 1' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_resume_state handles no previous evolution state"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_resume_state should handle no previous evolution state" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_resume_state checks for interrupted IMPLEMENT branch ---
grep_result=$(grep -A 80 '^_evolve_resume_state()' "$script_file" | grep -c 'git.*branch\|evolve-\|evolution.*branch' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_resume_state checks for interrupted evolution branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_resume_state should check for interrupted evolution branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: automaton.sh defines _evolve_run_loop function ---
grep_result=$(grep -c '^_evolve_run_loop()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_run_loop()"

# --- Test 8: _evolve_run_loop calls _evolve_run_cycle in a loop ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c '_evolve_run_cycle' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop calls _evolve_run_cycle"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should call _evolve_run_cycle" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _evolve_run_loop checks convergence ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c '_evolve_check_convergence' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop checks convergence"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should check convergence" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_run_loop checks per-cycle budget ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c '_evolve_check_budget' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop checks per-cycle budget"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should check per-cycle budget" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _evolve_run_loop respects ARG_CYCLES limit ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c 'ARG_CYCLES\|max_cycles' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop respects cycle limit"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should respect cycle limit" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: _evolve_run_loop supports resume with start_cycle parameter ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c 'start_cycle\|resume' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop supports resume via start_cycle"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should support resume via start_cycle" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _evolve_run_loop calls _safety_preflight ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c '_safety_preflight' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop calls _safety_preflight"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should call _safety_preflight" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _evolve_run_loop calls _constitution_create_default ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c '_constitution_create_default' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop initializes constitution"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should initialize constitution" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: --evolve --resume integration at entry point ---
# When ARG_EVOLVE and ARG_RESUME are both true, the entry point should
# call _evolve_resume_state and _evolve_run_loop
grep_result=$(grep -A 20 'ARG_EVOLVE.*true.*ARG_RESUME\|ARG_RESUME.*true.*ARG_EVOLVE\|evolve.*resume\|resume.*evolve' "$script_file" | grep -c '_evolve_resume_state\|_evolve_run_loop' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Entry point handles --evolve --resume combination"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Entry point should handle --evolve --resume combination" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: _evolve_run_loop handles pause flag ---
grep_result=$(grep -A 100 '^_evolve_run_loop()' "$script_file" | grep -c 'pause\|PAUSE' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_run_loop checks for pause flag"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_run_loop should check for pause flag" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
