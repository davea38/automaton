#!/usr/bin/env bash
# tests/test_bootstrap_init.sh — tests for .automaton/init.sh bootstrap script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Create a temporary project directory for isolated testing
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

setup_test_project() {
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR/.automaton"
    cd "$TEMP_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create a minimal IMPLEMENTATION_PLAN.md
    cat > "$TEMP_DIR/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

- [x] Task one completed
- [x] Task two completed
- [ ] Task three pending
- [ ] Task four pending
EOF

    # Create minimal budget.json
    cat > "$TEMP_DIR/.automaton/budget.json" <<'EOF'
{
  "limits": { "max_total_tokens": 10000000, "max_cost_usd": 50 },
  "used": { "estimated_cost_usd": 12.50 }
}
EOF

    # Create minimal learnings.json
    cat > "$TEMP_DIR/.automaton/learnings.json" <<'EOF'
{
  "version": 1,
  "entries": [
    {"id": "l1", "summary": "Use jq for JSON", "confidence": "high", "active": true},
    {"id": "l2", "summary": "Low confidence tip", "confidence": "low", "active": true},
    {"id": "l3", "summary": "Inactive learning", "confidence": "high", "active": false}
  ]
}
EOF

    # Initial commit so git log works
    git add -A
    git commit -q -m "Initial test setup"
    echo "change" >> "$TEMP_DIR/file.txt"
    git add -A
    git commit -q -m "Second commit for diff"
}

INIT_SCRIPT="$PROJECT_ROOT/.automaton/init.sh"

# --- Test 1: Script exists and is executable ---
assert_file_exists "$INIT_SCRIPT" "init.sh exists"

# --- Test 2: Script produces valid JSON ---
setup_test_project
output=$("$INIT_SCRIPT" "$TEMP_DIR" "build" "3" 2>/dev/null)
echo "$output" | jq empty 2>/dev/null
assert_exit_code 0 $? "init.sh produces valid JSON"

# --- Test 3: Manifest contains project_state ---
phase=$(echo "$output" | jq -r '.project_state.phase')
assert_equals "build" "$phase" "project_state.phase is build"

iteration=$(echo "$output" | jq -r '.project_state.iteration')
assert_equals "3" "$iteration" "project_state.iteration is 3"

# --- Test 4: Task counting ---
total=$(echo "$output" | jq '.project_state.tasks_total')
assert_equals "4" "$total" "tasks_total counts all tasks"

done_count=$(echo "$output" | jq '.project_state.tasks_done')
assert_equals "2" "$done_count" "tasks_done counts completed tasks"

# --- Test 5: Next task extraction ---
next_task=$(echo "$output" | jq -r '.project_state.next_task')
assert_contains "$next_task" "Task three pending" "next_task is first unchecked item"

# --- Test 6: Recent commits present ---
commits_count=$(echo "$output" | jq '.recent_changes | length')
# Should have at least 2 commits
if [ "$commits_count" -ge 2 ]; then
    echo "PASS: recent_changes has commits"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: recent_changes should have at least 2 commits (got $commits_count)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Budget data ---
budget_used=$(echo "$output" | jq '.budget.used_usd')
assert_equals "12.5" "$budget_used" "budget.used_usd is 12.50"

budget_limit=$(echo "$output" | jq '.budget.limit_usd')
assert_equals "50" "$budget_limit" "budget.limit_usd is 50"

budget_remaining=$(echo "$output" | jq '.budget.remaining_usd')
assert_equals "37.5" "$budget_remaining" "budget.remaining_usd is calculated"

# --- Test 8: Modified files ---
has_modified=$(echo "$output" | jq 'has("modified_files")')
assert_equals "true" "$has_modified" "manifest has modified_files field"

# --- Test 9: Learnings filter (high confidence, active only) ---
learnings_count=$(echo "$output" | jq '.learnings | length')
assert_equals "1" "$learnings_count" "learnings filters to high-confidence active only"

first_learning=$(echo "$output" | jq -r '.learnings[0]')
assert_equals "Use jq for JSON" "$first_learning" "learnings contains correct summary"

# --- Test 10: Test status field present when test_results.json exists ---
cat > "$TEMP_DIR/.automaton/test_results.json" <<'EOF'
[
  {"test": "test_a.sh", "status": "passed", "timestamp": "2026-03-01T10:30:00Z"},
  {"test": "test_b.sh", "status": "failed", "timestamp": "2026-03-01T10:30:00Z"}
]
EOF
output_with_tests=$("$INIT_SCRIPT" "$TEMP_DIR" "build" "1" 2>/dev/null)
has_tests=$(echo "$output_with_tests" | jq 'has("test_status")')
assert_equals "true" "$has_tests" "manifest has test_status when test_results.json exists"

# --- Test 11: Missing IMPLEMENTATION_PLAN.md handled gracefully ---
rm "$TEMP_DIR/IMPLEMENTATION_PLAN.md"
output_no_plan=$("$INIT_SCRIPT" "$TEMP_DIR" "research" "1" 2>/dev/null)
echo "$output_no_plan" | jq empty 2>/dev/null
assert_exit_code 0 $? "valid JSON even without IMPLEMENTATION_PLAN.md"

# --- Test 12: Default arguments ---
cd "$TEMP_DIR"
git add -A 2>/dev/null; git commit -q -m "cleanup" --allow-empty 2>/dev/null
output_defaults=$("$INIT_SCRIPT" 2>/dev/null)
default_phase=$(echo "$output_defaults" | jq -r '.project_state.phase')
assert_equals "build" "$default_phase" "default phase is build"

test_summary
