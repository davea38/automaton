#!/usr/bin/env bash
# tests/test_teammate_idle_hook.sh — Tests for spec-28 TeammateIdle hook
# Verifies that teammate-idle.sh correctly checks for unclaimed tasks and
# returns exit 2 (keep working) or exit 0 (allow idle) accordingly.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

HOOK_SCRIPT="$SCRIPT_DIR/../.claude/hooks/teammate-idle.sh"

# --- Setup: create a temporary directory with test fixtures ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

AUTOMATON_DIR="$TMPDIR/.automaton"
mkdir -p "$AUTOMATON_DIR/wave"

# --- Test 1: Hook script exists and is executable ---
assert_file_exists "$HOOK_SCRIPT" "teammate-idle.sh exists"
if [ -x "$HOOK_SCRIPT" ]; then
    echo "PASS: teammate-idle.sh is executable"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: teammate-idle.sh should be executable" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: Exit 2 when unclaimed tasks remain ---
# Create task list with unclaimed (status=pending) tasks
cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" <<'JSON'
[
  {"task_id": "task-1", "subject": "Implement feature A", "status": "completed", "blocked": false},
  {"task_id": "task-2", "subject": "Implement feature B", "status": "pending", "blocked": false},
  {"task_id": "task-3", "subject": "Implement feature C", "status": "pending", "blocked": false}
]
JSON

exit_code=0
stderr_output=$(echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>&1 >/dev/null) || exit_code=$?
assert_exit_code 2 "$exit_code" "Exit 2 when unclaimed tasks remain"
assert_contains "$stderr_output" "task" "Stderr mentions tasks when keeping teammate working"

# --- Test 3: Exit 0 when all tasks are completed ---
cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" <<'JSON'
[
  {"task_id": "task-1", "subject": "Implement feature A", "status": "completed", "blocked": false},
  {"task_id": "task-2", "subject": "Implement feature B", "status": "completed", "blocked": false}
]
JSON

exit_code=0
echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "Exit 0 when all tasks completed"

# --- Test 4: Exit 0 when all remaining tasks are blocked ---
cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" <<'JSON'
[
  {"task_id": "task-1", "subject": "Feature A", "status": "completed", "blocked": false},
  {"task_id": "task-2", "subject": "Feature B", "status": "pending", "blocked": true},
  {"task_id": "task-3", "subject": "Feature C", "status": "pending", "blocked": true}
]
JSON

exit_code=0
echo '{"teammate_name": "builder-2", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "Exit 0 when remaining tasks are all blocked"

# --- Test 5: Exit 2 when mix of blocked and available tasks ---
cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" <<'JSON'
[
  {"task_id": "task-1", "subject": "Feature A", "status": "completed", "blocked": false},
  {"task_id": "task-2", "subject": "Feature B", "status": "pending", "blocked": true},
  {"task_id": "task-3", "subject": "Feature C", "status": "pending", "blocked": false}
]
JSON

exit_code=0
echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 2 "$exit_code" "Exit 2 when available (non-blocked, pending) tasks exist"

# --- Test 6: Exit 0 when task list file does not exist ---
rm -f "$AUTOMATON_DIR/wave/agent_teams_tasks.json"

exit_code=0
echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "Exit 0 when task list file does not exist"

# --- Test 7: Exit 0 when task list is empty ---
echo '[]' > "$AUTOMATON_DIR/wave/agent_teams_tasks.json"

exit_code=0
echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "Exit 0 when task list is empty"

# --- Test 8: Handles in-progress tasks correctly (not claimable) ---
cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" <<'JSON'
[
  {"task_id": "task-1", "subject": "Feature A", "status": "in_progress", "blocked": false},
  {"task_id": "task-2", "subject": "Feature B", "status": "completed", "blocked": false}
]
JSON

exit_code=0
echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | AUTOMATON_PROJECT_ROOT="$TMPDIR" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 0 "$exit_code" "Exit 0 when remaining tasks are in_progress (already claimed)"

# --- Test 9: Falls back to CLAUDE_PROJECT_DIR ---
mkdir -p "$TMPDIR/alt/.automaton/wave"
cat > "$TMPDIR/alt/.automaton/wave/agent_teams_tasks.json" <<'JSON'
[{"task_id": "task-1", "subject": "Feature A", "status": "pending", "blocked": false}]
JSON

exit_code=0
# Explicitly unset AUTOMATON_PROJECT_ROOT so the fallback to CLAUDE_PROJECT_DIR is exercised.
# (When running inside an automaton self-build session, AUTOMATON_PROJECT_ROOT is exported
# into the environment and would otherwise shadow the fallback.)
echo '{"teammate_name": "builder-1", "team_name": "automaton-build"}' \
    | env -u AUTOMATON_PROJECT_ROOT CLAUDE_PROJECT_DIR="$TMPDIR/alt" bash "$HOOK_SCRIPT" 2>/dev/null || exit_code=$?
assert_exit_code 2 "$exit_code" "Falls back to CLAUDE_PROJECT_DIR when AUTOMATON_PROJECT_ROOT unset"

test_summary
