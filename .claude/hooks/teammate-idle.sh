#!/usr/bin/env bash
# teammate-idle.sh — TeammateIdle hook for Agent Teams mode
# Checks if unclaimed tasks remain in the shared task list.
# WHY: Prevents teammates from going idle while claimable work remains.
# Replaces stall detection from spec-16's wave polling. (spec-28 §5)
#
# Input: JSON on stdin with teammate_name, team_name
# Output: exit 0 = allow idle, exit 2 = keep working (stderr feedback)
#
# TeammateIdle only supports command hooks.
# Performance target: <2 seconds

set -euo pipefail

# ---- Read hook input from stdin ----
input=$(cat)

# ---- Determine project root ----
project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
task_list_file="$project_root/.automaton/wave/agent_teams_tasks.json"

# If task list doesn't exist, allow idle (no work defined)
if [ ! -f "$task_list_file" ]; then
    exit 0
fi

# ---- Count claimable tasks (pending + not blocked) ----
claimable=$(jq '[.[] | select(.status == "pending" and .blocked != true)] | length' \
    "$task_list_file" 2>/dev/null || echo 0)

if [ "$claimable" -gt 0 ]; then
    echo "Unclaimed tasks remain ($claimable available) — pick up the next available task" >&2
    exit 2
fi

exit 0
