#!/usr/bin/env bash
# tests/test_agent_teams_env_setup.sh — Tests for spec-28 Agent Teams environment setup
# Verifies that setup_agent_teams_environment() sets the experimental flag,
# validates Claude Code version, and configures display mode.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# --- Test 1: setup_agent_teams_environment function exists ---
grep_result=$(grep -c 'setup_agent_teams_environment()' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains setup_agent_teams_environment function"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should contain setup_agent_teams_environment function" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: Function sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS ---
func_body=$(sed -n '/^setup_agent_teams_environment()/,/^}/p' "$script_file")
if echo "$func_body" | grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'; then
    echo "PASS: setup_agent_teams_environment sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: setup_agent_teams_environment should set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Function validates Claude Code version ---
if echo "$func_body" | grep -q 'claude.*--version\|version.*check\|_claude_version'; then
    echo "PASS: setup_agent_teams_environment validates Claude Code version"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: setup_agent_teams_environment should validate Claude Code version" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Function handles display mode (in-process or tmux) ---
if echo "$func_body" | grep -q 'PARALLEL_TEAMMATE_DISPLAY\|display.*mode\|in-process\|tmux'; then
    echo "PASS: setup_agent_teams_environment handles display mode configuration"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: setup_agent_teams_environment should configure display mode" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Function is called from startup section (parallel deps check) ---
# It should be called where parallel mode dependencies are checked
startup_section=$(sed -n '/Check parallel-mode dependencies/,/Signal Handlers/p' "$script_file")
if echo "$startup_section" | grep -q 'setup_agent_teams_environment'; then
    echo "PASS: setup_agent_teams_environment is called during startup parallel checks"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: setup_agent_teams_environment should be called from startup parallel checks" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Function logs Agent Teams mode activation ---
if echo "$func_body" | grep -q 'log.*Agent Teams\|Agent Teams mode'; then
    echo "PASS: setup_agent_teams_environment logs activation"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: setup_agent_teams_environment should log Agent Teams activation" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Function warns on unsupported version instead of hard-failing ---
# Agent Teams is experimental; version check should warn, not abort
if echo "$func_body" | grep -qE 'warn|Warning|WARNING|log.*warn'; then
    echo "PASS: setup_agent_teams_environment warns on version issues"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: setup_agent_teams_environment should warn on version issues" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: run_agent_teams_build still exports the flag as redundant safety ---
build_func=$(sed -n '/^run_agent_teams_build()/,/^[^ ]/p' "$script_file")
if echo "$build_func" | grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'; then
    echo "PASS: run_agent_teams_build still exports env var as safety net"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: run_agent_teams_build should keep env var export as safety net" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
