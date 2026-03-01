#!/usr/bin/env bash
# Tests for .claude/hooks/enforce-file-ownership.sh
# WHY: Verify file ownership enforcement blocks writes to unowned files
# and allows writes to owned files during parallel build waves.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

HOOK="$PROJECT_ROOT/.claude/hooks/enforce-file-ownership.sh"
TEST_DIR=""

setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.automaton/wave"
    cat > "$TEST_DIR/.automaton/wave/assignments.json" << 'EOF'
{
  "wave": 1,
  "created_at": "2026-03-01T10:00:00Z",
  "assignments": [
    {
      "builder": 1,
      "task": "Implement feature A",
      "task_line": 10,
      "files_owned": ["src/feature_a.sh", "lib/utils.sh"],
      "worktree": ".automaton/worktrees/builder-1",
      "branch": "automaton/wave-1-builder-1"
    },
    {
      "builder": 2,
      "task": "Implement feature B",
      "task_line": 15,
      "files_owned": ["src/feature_b.sh", "docs/readme.md"],
      "worktree": ".automaton/worktrees/builder-2",
      "branch": "automaton/wave-1-builder-2"
    }
  ]
}
EOF
}

teardown() {
    [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
    TEST_DIR=""
}

# Run the hook and capture exit code without set -e leaking
run_hook() {
    local input="$1"
    local builder="${2:-}"
    local project="${3:-$TEST_DIR}"
    local ec
    ec=$(echo "$input" | AUTOMATON_PROJECT_ROOT="$project" AUTOMATON_BUILDER_NUM="$builder" bash "$HOOK" 2>/dev/null; echo $?)
    echo "$ec"
}

# --- Tests ---

test_allows_owned_file() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"src/feature_a.sh","content":"hello"}}' 1)
    assert_exit_code 0 "$ec" "Allow write to owned file"
    teardown
}

test_blocks_unowned_file() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"src/feature_b.sh","content":"hello"}}' 1)
    assert_exit_code 2 "$ec" "Block write to unowned file"
    teardown
}

test_allows_test_file_for_owned_source() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"tests/test_feature_a.sh","content":"test"}}' 1)
    assert_exit_code 0 "$ec" "Allow test file for owned source"
    teardown
}

test_allows_when_no_assignments_file() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local ec
    ec=$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"anything.sh","content":"hello"}}' 1 "$tmp_dir")
    assert_exit_code 0 "$ec" "Allow when assignments.json is missing"
    rm -rf "$tmp_dir"
}

test_allows_when_no_builder_num() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"src/feature_a.sh","content":"hello"}}' "")
    assert_exit_code 0 "$ec" "Allow when builder number is unknown"
    teardown
}

test_allows_when_no_file_path_in_input() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 1)
    assert_exit_code 0 "$ec" "Allow when no file_path in input"
    teardown
}

test_builder2_owns_different_files() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Edit","tool_input":{"file_path":"docs/readme.md","old_string":"a","new_string":"b"}}' 2)
    assert_exit_code 0 "$ec" "Builder 2 allowed to write its owned file"
    teardown
}

test_builder2_blocked_from_builder1_files() {
    setup
    local ec
    ec=$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"src/feature_a.sh","content":"steal"}}' 2)
    assert_exit_code 2 "$ec" "Builder 2 blocked from builder 1 files"
    teardown
}

test_absolute_path_normalization() {
    setup
    local ec
    ec=$(run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/src/feature_a.sh\",\"content\":\"hello\"}}" 1)
    assert_exit_code 0 "$ec" "Normalize absolute paths against project root"
    teardown
}

test_worktree_path_detection() {
    setup
    local worktree_dir="$TEST_DIR/.automaton/worktrees/builder-1"
    mkdir -p "$worktree_dir"
    local ec
    ec=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/feature_a.sh","content":"hello"}}' | \
        (cd "$worktree_dir" && AUTOMATON_PROJECT_ROOT="" AUTOMATON_BUILDER_NUM="" bash "$HOOK" 2>/dev/null; echo $?))
    assert_exit_code 0 "$ec" "Detect builder number from worktree path"
    teardown
}

test_error_message_on_block() {
    setup
    local stderr_output
    stderr_output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"forbidden.sh","content":"x"}}' | \
        AUTOMATON_PROJECT_ROOT="$TEST_DIR" AUTOMATON_BUILDER_NUM=1 bash "$HOOK" 2>&1 >/dev/null || true)
    assert_contains "$stderr_output" "not in builder-1's ownership list" "Error message mentions builder and ownership"
    teardown
}

# --- Run all tests ---
echo "=== enforce-file-ownership.sh tests ==="
test_allows_owned_file
test_blocks_unowned_file
test_allows_test_file_for_owned_source
test_allows_when_no_assignments_file
test_allows_when_no_builder_num
test_allows_when_no_file_path_in_input
test_builder2_owns_different_files
test_builder2_blocked_from_builder1_files
test_absolute_path_normalization
test_worktree_path_detection
test_error_message_on_block
echo ""
test_summary
