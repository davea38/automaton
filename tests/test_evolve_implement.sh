#!/usr/bin/env bash
# tests/test_evolve_implement.sh — Tests for spec-41 §6 IMPLEMENT phase
# Verifies _evolve_implement() in automaton.sh creates an evolution branch,
# generates an implementation plan from the approved idea, runs the build
# pipeline with self-build safety, runs review and constitutional compliance
# check, and writes implement.json; abandons branch and wilts idea on failure.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_implement function ---
grep_result=$(grep -c '^_evolve_implement()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_implement()"

# --- Test 2: _evolve_implement takes cycle_id parameter ---
grep_result=$(grep -A 5 '^_evolve_implement()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement takes cycle_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should take cycle_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_implement creates or references the cycle directory ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'mkdir.*cycle\|cycle_dir' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement creates or references cycle directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should create or reference cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_implement reads evaluate.json for approved idea ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'evaluate\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement reads evaluate.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should read evaluate.json from EVALUATE phase" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_implement creates an evolution branch ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c '_safety_branch_create' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement creates evolution branch via _safety_branch_create"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should create evolution branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_implement generates an implementation plan ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'IMPLEMENTATION_PLAN\|implementation.*plan\|plan.*idea' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement generates an implementation plan"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should generate an implementation plan from the approved idea" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_implement runs the build pipeline ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'run_agent\|build.*pipeline\|PROMPT_build' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement runs the build pipeline"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should run the build pipeline" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_implement runs constitutional compliance check ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c '_constitution_check' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement runs constitutional compliance check"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should run _constitution_check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _evolve_implement handles compliance failure (abandon + wilt) ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c '_safety_rollback\|_safety_branch_abandon\|_garden_wilt' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement handles compliance failure (rollback/abandon and wilt)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should handle compliance failure with rollback and wilt" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_implement writes implement.json output ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'implement\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement writes implement.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should write implement.json to cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: implement.json includes required fields ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'idea_id\|branch\|iterations\|files_changed\|lines_changed\|syntax_check\|constitution_check\|tokens_used' || true)
if [ "$grep_result" -ge 6 ]; then
    echo "PASS: implement.json includes required output fields"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: implement.json should include idea_id, branch, iterations, files_changed, lines_changed, syntax_check, constitution_check, tokens_used" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: _evolve_implement uses log function for reporting ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'log "EVOLVE"' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_implement uses log function for reporting (at least 2 log calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should use log function for reporting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: _evolve_implement handles skipped evaluation (no approved idea) ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c 'skipped\|no.*approved\|No.*approved\|result.*!=.*approved\|result.*skipped' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement handles skipped/rejected evaluation"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should handle case when no idea was approved" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _evolve_implement emits signal on compliance failure ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c '_signal_emit\|quality_concern' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement emits signal on compliance failure"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should emit quality_concern signal on compliance failure" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: _evolve_implement runs sandbox testing ---
grep_result=$(grep -A 200 '^_evolve_implement()' "$script_file" | grep -c '_safety_sandbox_test\|sandbox' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_implement runs sandbox testing"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_implement should run sandbox testing" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
