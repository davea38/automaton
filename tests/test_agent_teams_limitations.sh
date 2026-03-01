#!/usr/bin/env bash
# tests/test_agent_teams_limitations.sh — tests for Agent Teams limitations mitigations (spec-28 §8)
# Tests: save_agent_teams_state, restore_agent_teams_state, verify_agent_teams_completions

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Setup temp directory for each test
setup() {
    TEST_DIR=$(mktemp -d)
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    mkdir -p "$AUTOMATON_DIR/wave"
    export PROJECT_ROOT="$TEST_DIR"
    export PLAN_FILE="$TEST_DIR/IMPLEMENTATION_PLAN.md"
    export LOG_FILE="$TEST_DIR/automaton.log"

    # Minimal automaton.sh sourcing — extract only needed functions
    # Create a shim that sources the target functions
    cat > "$TEST_DIR/shim.sh" << 'SHIM'
#!/usr/bin/env bash
AUTOMATON_DIR="${AUTOMATON_DIR:-.automaton}"
LOG_FILE="${LOG_FILE:-/dev/null}"
log() { echo "[$1] $2" >> "$LOG_FILE"; }
SHIM
    source "$TEST_DIR/shim.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ── Test: save_agent_teams_state writes state file ──
test_save_state_creates_file() {
    setup

    # Create a task list
    cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" << 'EOF'
[
  {"task_id": "task-1", "subject": "Add feature A", "status": "pending", "blocked": false},
  {"task_id": "task-2", "subject": "Add feature B", "status": "pending", "blocked": true}
]
EOF

    # Source the function from automaton.sh
    source_function save_agent_teams_state

    save_agent_teams_state

    assert_file_exists "$AUTOMATON_DIR/agent_teams_state.json" \
        "save_agent_teams_state creates state file"

    # Verify state file contains tasks
    local task_count
    task_count=$(jq 'length' "$AUTOMATON_DIR/agent_teams_state.json")
    assert_equals "2" "$task_count" "state file contains all tasks"

    # Verify timestamp is present
    local has_timestamp
    has_timestamp=$(jq '.[0] | has("saved_at")' "$AUTOMATON_DIR/agent_teams_state.json")
    assert_equals "true" "$has_timestamp" "state entries have saved_at timestamp"

    teardown
}

# ── Test: restore_agent_teams_state reads saved state ──
test_restore_state_reads_file() {
    setup

    # Create saved state
    cat > "$AUTOMATON_DIR/agent_teams_state.json" << 'EOF'
[
  {"task_id": "task-1", "subject": "Add feature A", "status": "completed", "blocked": false, "saved_at": "2026-01-01T00:00:00Z"},
  {"task_id": "task-2", "subject": "Add feature B", "status": "pending", "blocked": false, "saved_at": "2026-01-01T00:00:00Z"}
]
EOF

    source_function restore_agent_teams_state

    local restored
    restored=$(restore_agent_teams_state)

    local completed_count
    completed_count=$(echo "$restored" | jq '[.[] | select(.status == "completed")] | length')
    assert_equals "1" "$completed_count" "restore returns 1 completed task"

    local pending_count
    pending_count=$(echo "$restored" | jq '[.[] | select(.status == "pending")] | length')
    assert_equals "1" "$pending_count" "restore returns 1 pending task"

    teardown
}

# ── Test: restore returns empty when no saved state ──
test_restore_state_empty_when_missing() {
    setup

    source_function restore_agent_teams_state

    local restored
    restored=$(restore_agent_teams_state)
    assert_equals "[]" "$restored" "restore returns empty array when no state file"

    teardown
}

# ── Test: verify_agent_teams_completions detects completed tasks via git diff ──
test_verify_completions_detects_changes() {
    setup

    # Initialize git repo
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > file_a.txt
    echo "initial" > file_b.txt
    git add -A && git commit -q -m "initial"

    # Simulate changes made by teammates
    echo "modified" > file_a.txt
    git add -A && git commit -q -m "Implement feature A"

    # Create task list with file associations
    cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" << 'EOF'
[
  {"task_id": "task-1", "subject": "Add feature A", "files": ["file_a.txt"], "status": "completed", "blocked": false},
  {"task_id": "task-2", "subject": "Add feature B", "files": ["file_b.txt"], "status": "completed", "blocked": false}
]
EOF

    source_function verify_agent_teams_completions

    local result
    result=$(verify_agent_teams_completions "HEAD~1")

    # task-1 should be verified (file_a.txt was changed)
    local verified_count
    verified_count=$(echo "$result" | jq '[.[] | select(.verified == true)] | length')
    assert_equals "1" "$verified_count" "one task verified via git diff"

    # task-2 should be unverified (file_b.txt was NOT changed)
    local unverified_count
    unverified_count=$(echo "$result" | jq '[.[] | select(.verified == false)] | length')
    assert_equals "1" "$unverified_count" "one task unverified (no matching diff)"

    teardown
}

# ── Test: verify_agent_teams_completions handles tasks without file lists ──
test_verify_completions_no_files() {
    setup

    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > file_a.txt
    git add -A && git commit -q -m "initial"
    echo "changed" > file_a.txt
    git add -A && git commit -q -m "change"

    cat > "$AUTOMATON_DIR/wave/agent_teams_tasks.json" << 'EOF'
[
  {"task_id": "task-1", "subject": "Refactor code", "files": [], "status": "completed", "blocked": false}
]
EOF

    source_function verify_agent_teams_completions

    local result
    result=$(verify_agent_teams_completions "HEAD~1")

    # Tasks without file lists should still be reported but marked as unverifiable
    local count
    count=$(echo "$result" | jq '[.[] | select(.verified == "unverifiable")] | length')
    assert_equals "1" "$count" "task without files is unverifiable"

    teardown
}

# ── Test: document_agent_teams_limitations outputs limitation details ──
test_document_limitations_outputs_info() {
    setup

    source_function document_agent_teams_limitations

    local output
    output=$(document_agent_teams_limitations)

    assert_contains "$output" "no session resumption" \
        "documents session resumption limitation"
    assert_contains "$output" "task status lag" \
        "documents task status lag"
    assert_contains "$output" "no nested teams" \
        "documents no nested teams"
    assert_contains "$output" "shared working tree" \
        "documents shared working tree risk"

    teardown
}

# ── Helper: source a single function from automaton.sh ──
source_function() {
    local func_name="$1"
    local automaton_sh="$SCRIPT_DIR/../automaton.sh"

    # Extract the function definition using awk
    eval "$(awk "/^${func_name}\\(\\)/ { found=1 } found { print } found && /^}$/ { exit }" "$automaton_sh")"
}

# ── Run all tests ──
test_save_state_creates_file
test_restore_state_reads_file
test_restore_state_empty_when_missing
test_verify_completions_detects_changes
test_verify_completions_no_files
test_document_limitations_outputs_info

test_summary
