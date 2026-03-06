#!/usr/bin/env bash
# tests/test_state_behavioral.sh — Behavioral tests for lib/state.sh write/read state.
# Actually executes state read/write and verifies round-trip fidelity.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
setup_test_dir

# Minimal stubs
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/run-summaries"
log() { :; }
emit_event() { :; }
init_learnings() { :; }
migrate_learnings_to_agent_memory() { :; }
initialize_budget() { :; }
AUTOMATON_VERSION="1.0.0"
PARALLEL_ENABLED="false"
GARDEN_ENABLED="false"
QUORUM_ENABLED="false"
EVOLVE_ENABLED="false"
ARG_EVOLVE="false"
WORK_LOG_ENABLED="false"
EXEC_BOOTSTRAP_ENABLED="false"
AGENTS_USE_NATIVE_DEFINITIONS="false"

# Source the state module
source "$_PROJECT_DIR/lib/state.sh"

# --- Test 1: write_state creates valid JSON ---
current_phase="build"
iteration=5
phase_iteration=3
stall_count=1
consecutive_failures=0
corruption_count=0
replan_count=0
test_failure_count=0
build_sub_phase="implementation"
scaffold_iterations_done=0
started_at="2024-01-01T00:00:00Z"
resumed_from="null"
phase_history='[{"phase":"research","completed_at":"2024-01-01T01:00:00Z"}]'

write_state
assert_file_exists "$AUTOMATON_DIR/state.json" "write_state creates state.json"
state_json=$(cat "$AUTOMATON_DIR/state.json")
assert_json_valid "$state_json" "state.json is valid JSON"
assert_json_field "$state_json" '.phase' "build" "phase written correctly"
assert_json_field "$state_json" '.iteration' "5" "iteration written correctly"
assert_json_field "$state_json" '.stall_count' "1" "stall_count written correctly"

# --- Test 2: read_state restores variables ---
current_phase=""
iteration=0
phase_iteration=0
stall_count=0

read_state
assert_equals "build" "$current_phase" "read_state restores phase"
assert_equals "5" "$iteration" "read_state restores iteration"
assert_equals "3" "$phase_iteration" "read_state restores phase_iteration"
assert_equals "1" "$stall_count" "read_state restores stall_count"
assert_equals "0" "$consecutive_failures" "read_state resets consecutive_failures to 0"

# --- Test 3: write_state round-trips with parallel mode ---
PARALLEL_ENABLED="true"
wave_number=3
wave_history='[{"wave":1,"status":"complete"},{"wave":2,"status":"complete"}]'
consecutive_wave_failures=1

write_state
state_json=$(cat "$AUTOMATON_DIR/state.json")
assert_json_field "$state_json" '.wave_number' "3" "wave_number written in parallel mode"
assert_json_field "$state_json" '.consecutive_wave_failures' "1" "wave failures written"

# Read it back
wave_number=0
consecutive_wave_failures=0
read_state
assert_equals "3" "$wave_number" "read_state restores wave_number"
assert_equals "1" "$consecutive_wave_failures" "read_state restores wave failures"
PARALLEL_ENABLED="false"

# --- Test 4: write_state handles resumed_from string value ---
resumed_from="2024-01-01T02:00:00Z"
write_state
state_json=$(cat "$AUTOMATON_DIR/state.json")
assert_json_field "$state_json" '.resumed_from' "2024-01-01T02:00:00Z" "resumed_from written as string"

# --- Test 5: log() appends to session.log ---
: > "$AUTOMATON_DIR/session.log"
log "TEST" "hello world"
line_count=$(wc -l < "$AUTOMATON_DIR/session.log")
assert_equals "1" "$line_count" "log appends one line"
assert_contains "$(cat "$AUTOMATON_DIR/session.log")" "[TEST]" "log includes component tag"
assert_contains "$(cat "$AUTOMATON_DIR/session.log")" "hello world" "log includes message"

# --- Test 6: emit_event respects WORK_LOG_ENABLED ---
WORK_LOG_ENABLED="false"
emit_event "test_event" '{"foo":"bar"}'
# Should not create any file
if [ ! -f "${WORK_LOG:-/nonexistent}" ]; then
    echo "PASS: emit_event does nothing when work log disabled"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: emit_event should not write when disabled" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: emit_event writes JSONL when enabled ---
WORK_LOG_ENABLED="true"
WORK_LOG="$TEST_DIR/test-worklog.jsonl"
WORK_LOG_LEVEL="verbose"
RUN_START_EPOCH=$(date +%s)
: > "$WORK_LOG"
emit_event "phase_start" '{"phase":"build"}'
line=$(cat "$WORK_LOG")
assert_json_valid "$line" "work log entry is valid JSON"
assert_contains "$line" "phase_start" "work log contains event type"

# --- Test 8: emit_event filters by log level ---
WORK_LOG_LEVEL="minimal"
: > "$WORK_LOG"
emit_event "gate_check" '{"gate":"test"}'
line_count=$(wc -l < "$WORK_LOG")
assert_equals "0" "$line_count" "minimal level filters out gate_check events"

emit_event "phase_start" '{"phase":"build"}'
line_count=$(wc -l < "$WORK_LOG")
assert_equals "1" "$line_count" "minimal level allows phase_start events"

# --- Test 9: write_agent_history creates per-agent JSON ---
current_phase="build"
phase_iteration=1
write_agent_history "sonnet" "PROMPT_build.md" "2024-01-01T00:00:00Z" "2024-01-01T00:01:00Z" \
    60 0 1000 2000 500 200 0.05 "Add auth middleware" "success" '["src/auth.ts"]' "abc1234" "false"
assert_file_exists "$AUTOMATON_DIR/agents/build-001.json" "write_agent_history creates agent file"
agent_json=$(cat "$AUTOMATON_DIR/agents/build-001.json")
assert_json_valid "$agent_json" "agent history is valid JSON"
assert_json_field "$agent_json" '.model' "sonnet" "agent history records model"
assert_json_field "$agent_json" '.task' "Add auth middleware" "agent history records task"

test_summary
