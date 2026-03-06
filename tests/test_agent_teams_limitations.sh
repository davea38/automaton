#!/usr/bin/env bash
# tests/test_agent_teams_limitations.sh — Tests for spec-28 §8 Agent Teams limitations mitigations
# Verifies that save_agent_teams_state, restore_agent_teams_state,
# verify_agent_teams_completions, and document_agent_teams_limitations
# exist and have the correct behavior documented in their function bodies.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

AUTOMATON_SH="$script_file"

# --- Test 1: save_agent_teams_state function exists ---
grep_result=$(grep -c 'save_agent_teams_state()' "$AUTOMATON_SH" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains save_agent_teams_state function"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: automaton.sh should contain save_agent_teams_state function" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 2: save_agent_teams_state writes agent_teams_state.json ---
func_body=$(sed -n '/^save_agent_teams_state()/,/^}/p' "$AUTOMATON_SH")
if echo "$func_body" | grep -q 'agent_teams_state.json'; then
    echo "PASS: save_agent_teams_state writes agent_teams_state.json"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: save_agent_teams_state should write agent_teams_state.json" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 3: save_agent_teams_state adds saved_at timestamp ---
if echo "$func_body" | grep -q 'saved_at'; then
    echo "PASS: save_agent_teams_state adds saved_at timestamp"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: save_agent_teams_state should add saved_at timestamp" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 4: restore_agent_teams_state function exists ---
grep_result=$(grep -c 'restore_agent_teams_state()' "$AUTOMATON_SH" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains restore_agent_teams_state function"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: automaton.sh should contain restore_agent_teams_state function" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 5: restore_agent_teams_state returns empty array when no state ---
restore_body=$(sed -n '/^restore_agent_teams_state()/,/^}/p' "$AUTOMATON_SH")
if echo "$restore_body" | grep -q '\[\]'; then
    echo "PASS: restore_agent_teams_state returns empty array when no state file"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: restore_agent_teams_state should return [] when no state file" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 6: verify_agent_teams_completions function exists ---
grep_result=$(grep -c 'verify_agent_teams_completions()' "$AUTOMATON_SH" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains verify_agent_teams_completions function"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: automaton.sh should contain verify_agent_teams_completions function" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 7: verify_agent_teams_completions uses git diff ---
verify_body=$(sed -n '/^verify_agent_teams_completions()/,/^}/p' "$AUTOMATON_SH")
if echo "$verify_body" | grep -q 'git diff'; then
    echo "PASS: verify_agent_teams_completions uses git diff for verification"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: verify_agent_teams_completions should use git diff" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 8: verify_agent_teams_completions marks verified/unverifiable ---
if echo "$verify_body" | grep -q 'verified' && echo "$verify_body" | grep -q 'unverifiable'; then
    echo "PASS: verify_agent_teams_completions marks tasks as verified or unverifiable"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: verify_agent_teams_completions should mark verified and unverifiable tasks" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 9: document_agent_teams_limitations function exists ---
grep_result=$(grep -c 'document_agent_teams_limitations()' "$AUTOMATON_SH" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains document_agent_teams_limitations function"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: automaton.sh should contain document_agent_teams_limitations function" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 10: document_agent_teams_limitations covers all 7 limitations from spec ---
limit_body=$(sed -n '/^document_agent_teams_limitations()/,/^}/p' "$AUTOMATON_SH")
missing=0
for limitation in "no session resumption" "task status lag" "no nested teams" \
    "One team per session" "Lead is fixed" "Permissions at spawn" "shared working tree"; do
    if ! echo "$limit_body" | grep -qi "$limitation"; then
        echo "FAIL: document_agent_teams_limitations missing '$limitation'" >&2
        missing=1
    fi
done
if [ "$missing" -eq 0 ]; then
    echo "PASS: document_agent_teams_limitations covers all 7 limitations"
    ((_TEST_PASS_COUNT++)) || true
else
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 11: run_agent_teams_build calls save_agent_teams_state ---
build_body=$(sed -n '/^run_agent_teams_build()/,/^}/p' "$AUTOMATON_SH")
if echo "$build_body" | grep -q 'save_agent_teams_state'; then
    echo "PASS: run_agent_teams_build calls save_agent_teams_state"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: run_agent_teams_build should call save_agent_teams_state after session" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 12: run_agent_teams_build calls verify_agent_teams_completions ---
if echo "$build_body" | grep -q 'verify_agent_teams_completions'; then
    echo "PASS: run_agent_teams_build calls verify_agent_teams_completions"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: run_agent_teams_build should call verify_agent_teams_completions" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 13: run_agent_teams_build calls restore_agent_teams_state ---
if echo "$build_body" | grep -q 'restore_agent_teams_state'; then
    echo "PASS: run_agent_teams_build calls restore_agent_teams_state for resume"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: run_agent_teams_build should call restore_agent_teams_state for resume" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 14: run_agent_teams_build calls document_agent_teams_limitations ---
if echo "$build_body" | grep -q 'document_agent_teams_limitations'; then
    echo "PASS: run_agent_teams_build logs Agent Teams limitations at startup"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: run_agent_teams_build should log limitations at startup" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

# --- Test 15: run_agent_teams_build records pre-build HEAD for verification ---
if echo "$build_body" | grep -q 'pre_build_head'; then
    echo "PASS: run_agent_teams_build records pre-build HEAD for post-build verification"
    ((_TEST_PASS_COUNT++)) || true
else
    echo "FAIL: run_agent_teams_build should record pre-build HEAD" >&2
    ((_TEST_FAIL_COUNT++)) || true
fi

test_summary
