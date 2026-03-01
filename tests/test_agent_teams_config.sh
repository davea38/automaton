#!/usr/bin/env bash
# tests/test_agent_teams_config.sh — Tests for spec-28 parallel.mode config field
# Verifies that the parallel.mode config field is loaded from automaton.config.json
# and that the parallel dependency check respects the mode value.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# --- Test 1: automaton.config.json contains parallel.mode field ---
config_file="$SCRIPT_DIR/../automaton.config.json"
mode_value=$(jq -r '.parallel.mode // "missing"' "$config_file")
assert_equals "automaton" "$mode_value" "parallel.mode defaults to 'automaton' in config"

# --- Test 2: automaton.config.json contains parallel.teammate_display field ---
display_value=$(jq -r '.parallel.teammate_display // "missing"' "$config_file")
assert_equals "in-process" "$display_value" "parallel.teammate_display defaults to 'in-process' in config"

# --- Test 3: automaton.sh reads PARALLEL_MODE from config ---
# Source just the load_config function and check that PARALLEL_MODE is set
tmpconfig=$(mktemp)
cat > "$tmpconfig" <<'TMPEOF'
{
  "parallel": {
    "enabled": false,
    "mode": "agent-teams",
    "max_builders": 3,
    "teammate_display": "tmux"
  }
}
TMPEOF

# Extract PARALLEL_MODE by grepping the load_config function for the jq line
grep_result=$(grep -c 'PARALLEL_MODE.*jq.*parallel.mode' "$SCRIPT_DIR/../automaton.sh" || true)
assert_equals "1" "$grep_result" "automaton.sh reads PARALLEL_MODE from parallel.mode config"

# --- Test 4: automaton.sh reads PARALLEL_TEAMMATE_DISPLAY from config ---
grep_result=$(grep -c 'PARALLEL_TEAMMATE_DISPLAY.*jq.*parallel.teammate_display' "$SCRIPT_DIR/../automaton.sh" || true)
assert_equals "1" "$grep_result" "automaton.sh reads PARALLEL_TEAMMATE_DISPLAY from parallel.teammate_display config"

# --- Test 5: tmux/worktree deps only required for automaton mode, not agent-teams ---
# The dependency check should reference PARALLEL_MODE to skip tmux check for agent-teams
grep_result=$(grep -c 'PARALLEL_MODE.*automaton' "$SCRIPT_DIR/../automaton.sh" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh checks PARALLEL_MODE for dependency gating"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should check PARALLEL_MODE for dependency gating" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: agent-teams mode validates CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS ---
grep_result=$(grep -c 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$SCRIPT_DIR/../automaton.sh" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh references CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should reference CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Cleanup ---
rm -f "$tmpconfig"

test_summary
