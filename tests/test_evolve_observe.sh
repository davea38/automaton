#!/usr/bin/env bash
# tests/test_evolve_observe.sh — Tests for spec-41 §7 OBSERVE phase
# Verifies _evolve_observe() in automaton.sh takes a post-cycle metrics
# snapshot, compares against the pre-cycle snapshot, runs sandbox testing,
# and decides the outcome: harvest (merge branch, mark idea as harvested,
# emit promising_approach signal), wilt (rollback, emit quality_concern signal),
# or neutral (merge with attention_needed signal); writes observe.json.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: automaton.sh defines _evolve_observe function ---
grep_result=$(grep -c '^_evolve_observe()' "$script_file" || true)
assert_equals "1" "$grep_result" "automaton.sh defines _evolve_observe()"

# --- Test 2: _evolve_observe takes cycle_id parameter ---
grep_result=$(grep -A 5 '^_evolve_observe()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe takes cycle_id parameter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should take cycle_id parameter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _evolve_observe creates or references the cycle directory ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'mkdir.*cycle\|cycle_dir' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe creates or references cycle directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should create or reference cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _evolve_observe reads implement.json for idea and branch ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'implement\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe reads implement.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should read implement.json from IMPLEMENT phase" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _evolve_observe takes a post-cycle metrics snapshot ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c '_metrics_snapshot' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe takes a post-cycle metrics snapshot"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should call _metrics_snapshot for post-cycle data" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _evolve_observe compares pre and post metrics ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c '_metrics_compare' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe compares pre and post metrics"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should call _metrics_compare for before/after comparison" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _evolve_observe runs sandbox testing ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c '_safety_sandbox_test\|sandbox' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe runs sandbox testing"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should run _safety_sandbox_test" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _evolve_observe handles harvest outcome (merge + harvest stage) ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'harvest\|_safety_branch_merge\|_garden_advance_stage' || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: _evolve_observe handles harvest outcome (merge + advance to harvest)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should handle harvest: merge branch and advance idea to harvest" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: _evolve_observe handles regression outcome (rollback + wilt) ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c '_safety_rollback\|quality_concern\|regression' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_observe handles regression outcome (rollback)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should handle regression: rollback and emit quality_concern" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _evolve_observe handles neutral outcome (merge + attention signal) ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'neutral\|attention_needed' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_observe handles neutral outcome (merge with attention signal)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should handle neutral: merge with attention_needed signal" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _evolve_observe emits promising_approach signal on harvest ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'promising_approach' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe emits promising_approach signal on harvest"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should emit promising_approach signal when improvement detected" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: _evolve_observe writes observe.json output ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'observe\.json' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe writes observe.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should write observe.json to cycle directory" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: observe.json includes required fields ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'idea_id\|pre_metrics\|post_metrics\|delta\|test_pass_rate\|outcome\|signals_emitted' || true)
if [ "$grep_result" -ge 5 ]; then
    echo "PASS: observe.json includes required output fields"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: observe.json should include idea_id, pre_metrics, post_metrics, delta, test_pass_rate, outcome, signals_emitted" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _evolve_observe uses log function for reporting ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'log "EVOLVE"' || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: _evolve_observe uses log function for reporting (at least 2 log calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should use log function for reporting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: _evolve_observe handles skipped implementation ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c 'skipped\|no.*implement\|No.*implement\|status.*!=.*completed' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe handles skipped/failed implementation"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should handle case when implementation was skipped or failed" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: _evolve_observe rebuilds garden index ---
grep_result=$(grep -A 200 '^_evolve_observe()' "$script_file" | grep -c '_garden_rebuild_index' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _evolve_observe rebuilds garden index"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _evolve_observe should call _garden_rebuild_index after outcome" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
