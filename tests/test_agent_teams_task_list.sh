#!/usr/bin/env bash
# tests/test_agent_teams_task_list.sh — Tests for spec-28 task list population
# Verifies that populate_agent_teams_task_list correctly converts unchecked
# IMPLEMENTATION_PLAN.md tasks to Agent Teams shared task list format with
# dependency annotations mapped to blocked tasks.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# --- Setup: create a temporary directory with test fixtures ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

AUTOMATON_DIR="$TMPDIR/.automaton"
mkdir -p "$AUTOMATON_DIR/wave"

# Create a test plan file with various task types
cat > "$TMPDIR/test_plan.md" <<'EOF'
# Test Plan

## Section A

- [x] Completed task one (WHY: already done)
- [ ] Simple unchecked task (WHY: needs implementation)
- [ ] Task with file annotation (WHY: needs implementation)
<!-- files: src/foo.ts, src/bar.ts -->
- [ ] Task with dependency (WHY: depends on another)
<!-- depends: task-1 -->
- [ ] Task with files and dependency (WHY: both annotations)
<!-- files: src/baz.ts -->
<!-- depends: task-2 -->
- [x] Another completed task (WHY: done)
- [ ] Final task no annotations (WHY: last one)
EOF

# --- Test 1: Function exists in automaton.sh ---
grep_result=$(grep -c 'populate_agent_teams_task_list' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh contains populate_agent_teams_task_list function"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should contain populate_agent_teams_task_list function" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: Source the function and run it on test plan ---
# We need to source just the function. Extract it using sed.
# Instead, we'll set up the environment and source automaton.sh with guards.

# Create a minimal config
cat > "$TMPDIR/automaton.config.json" <<'JSON'
{
  "parallel": { "enabled": true, "mode": "agent-teams", "max_builders": 3 }
}
JSON

# Source automaton.sh functions by extracting populate_agent_teams_task_list
# Since sourcing the whole file is complex, we'll test via invocation
# by grepping the function output format.

# Test that the function parses unchecked tasks correctly by calling it
# in a subshell with the necessary variables set.
(
    # Set required variables
    AUTOMATON_DIR="$AUTOMATON_DIR"
    PLAN_FILE="$TMPDIR/test_plan.md"
    MAX_BUILDERS=3

    # Stub log function
    log() { :; }

    # Source just the function from automaton.sh
    eval "$(sed -n '/^populate_agent_teams_task_list()/,/^}/p' "$script_file")"

    # Run the function
    populate_agent_teams_task_list
) 2>/dev/null

task_list_file="$AUTOMATON_DIR/wave/agent_teams_tasks.json"
if [ -f "$task_list_file" ]; then
    echo "PASS: populate_agent_teams_task_list creates agent_teams_tasks.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: populate_agent_teams_task_list should create agent_teams_tasks.json" >&2
    ((_TEST_FAIL_COUNT++))
    # Skip remaining tests
    test_summary
    exit $?
fi

# --- Test 3: Only unchecked tasks are included ---
task_count=$(jq 'length' "$task_list_file")
assert_equals "5" "$task_count" "Only unchecked tasks included (5 of 7)"

# --- Test 4: Task subjects are correct ---
first_subject=$(jq -r '.[0].subject' "$task_list_file")
assert_contains "$first_subject" "Simple unchecked task" "First task subject is correct"

# --- Test 5: File annotations are extracted ---
second_files=$(jq -r '.[1].files | join(", ")' "$task_list_file")
assert_contains "$second_files" "src/foo.ts" "File annotation extracted for task with files"

# --- Test 6: Dependencies are mapped ---
third_deps=$(jq -r '.[2].depends_on // [] | join(", ")' "$task_list_file")
assert_contains "$third_deps" "task-1" "Dependency annotation mapped correctly"

# --- Test 7: Combined file + dependency annotations ---
fourth_files=$(jq -r '.[3].files | join(", ")' "$task_list_file")
fourth_deps=$(jq -r '.[3].depends_on // [] | join(", ")' "$task_list_file")
assert_contains "$fourth_files" "src/baz.ts" "Combined annotation: files extracted"
assert_contains "$fourth_deps" "task-2" "Combined annotation: dependency extracted"

# --- Test 8: Tasks without annotations have empty files/deps ---
fifth_files=$(jq -r '.[4].files | length' "$task_list_file")
fifth_deps=$(jq -r '.[4].depends_on | length' "$task_list_file")
assert_equals "0" "$fifth_files" "Unannotated task has empty files array"
assert_equals "0" "$fifth_deps" "Unannotated task has empty depends_on array"

# --- Test 9: Each task has a sequential task_id ---
first_id=$(jq -r '.[0].task_id' "$task_list_file")
second_id=$(jq -r '.[1].task_id' "$task_list_file")
assert_equals "task-1" "$first_id" "First task has task_id 'task-1'"
assert_equals "task-2" "$second_id" "Second task has task_id 'task-2'"

# --- Test 10: Tasks have line numbers ---
first_line=$(jq -r '.[0].line' "$task_list_file")
if [ "$first_line" -gt 0 ] 2>/dev/null; then
    echo "PASS: Tasks have valid line numbers"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Tasks should have valid line numbers (got '$first_line')" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Blocked tasks are marked ---
# Task 3 depends on task-1, which is not complete, so it should be marked blocked
third_blocked=$(jq -r '.[2].blocked' "$task_list_file")
assert_equals "true" "$third_blocked" "Task with unmet dependency is marked blocked"

# --- Test 12: Tasks without dependencies are not blocked ---
first_blocked=$(jq -r '.[0].blocked' "$task_list_file")
assert_equals "false" "$first_blocked" "Task without dependencies is not blocked"

test_summary
