#!/usr/bin/env bash
# tests/test_state_functional.sh — Functional tests for lib/state.sh
# Tests state write/read, atomic persistence, log output, and notification filtering.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR/run-summaries"
AUTOMATON_VERSION="0.1.0"

# Source state module (needs log function)
log() { echo "[$1] $2" >> "$TEST_DIR/test.log"; }

source "$_PROJECT_DIR/lib/state.sh"

# --- Test: log writes to session.log and stdout ---

: > "$AUTOMATON_DIR/session.log"
output=$(log "TEST" "hello world")
assert_contains "$output" "hello world" "log outputs to stdout"

log_content=$(cat "$AUTOMATON_DIR/session.log")
assert_contains "$log_content" "[TEST] hello world" "log writes to session.log"
assert_matches "$log_content" '^\[.*Z\]' "log includes ISO timestamp"

# --- Test: write_state produces valid JSON ---

current_phase="build"
iteration=5
phase_iteration=3
stall_count=1
consecutive_failures=0
corruption_count=0
replan_count=1
test_failure_count=0
build_sub_phase="implementation"
scaffold_iterations_done=2
started_at="2025-01-01T00:00:00Z"
resumed_from="null"
phase_history='[{"phase":"research","completed_at":"2025-01-01T01:00:00Z"}]'
PARALLEL_ENABLED="false"
EXEC_PARALLEL_BUILDERS=1

write_state

assert_file_exists "$AUTOMATON_DIR/state.json" "write_state creates state.json"

state=$(cat "$AUTOMATON_DIR/state.json")
assert_json_valid "$state" "write_state produces valid JSON"
assert_json_field "$state" '.phase' "build" "state.phase is build"
assert_json_field "$state" '.iteration' "5" "state.iteration is 5"
assert_json_field "$state" '.phase_iteration' "3" "state.phase_iteration is 3"
assert_json_field "$state" '.stall_count' "1" "state.stall_count is 1"
assert_json_field "$state" '.replan_count' "1" "state.replan_count is 1"
assert_json_field "$state" '.build_sub_phase' "implementation" "state.build_sub_phase correct"
assert_json_field "$state" '.scaffold_iterations_done' "2" "state.scaffold_iterations_done correct"
assert_json_field "$state" '.resumed_from' "null" "state.resumed_from is null"
assert_json_field "$state" '.version' "0.1.0" "state.version correct"

# Verify phase_history is valid JSON array
ph_len=$(echo "$state" | jq '.phase_history | length')
assert_equals "1" "$ph_len" "phase_history has 1 entry"

# --- Test: write_state atomic (temp file then mv) ---

# Verify no .tmp file left behind
assert_equals "1" "$([ ! -f "$AUTOMATON_DIR/state.json.tmp" ] && echo 1 || echo 0)" "no .tmp file left after write"

# --- Test: write_state with resumed_from as a string ---

resumed_from="2025-01-01T02:00:00Z"
write_state
state=$(cat "$AUTOMATON_DIR/state.json")
assert_json_field "$state" '.resumed_from' "2025-01-01T02:00:00Z" "resumed_from as quoted string"

# --- Test: write_state with parallel mode ---

PARALLEL_ENABLED="true"
wave_number=3
wave_history='[1,2,3]'
consecutive_wave_failures=1

write_state
state=$(cat "$AUTOMATON_DIR/state.json")
assert_json_valid "$state" "parallel state is valid JSON"
assert_json_field "$state" '.wave_number' "3" "wave_number persisted"
assert_json_field "$state" '.consecutive_wave_failures' "1" "consecutive_wave_failures persisted"

wh_len=$(echo "$state" | jq '.wave_history | length')
assert_equals "3" "$wh_len" "wave_history has 3 entries"

PARALLEL_ENABLED="false"

# --- Test: read_state restores variables ---

current_phase="research"
iteration=0
phase_iteration=0
stall_count=0
replan_count=0

# Write a known state first
current_phase="review"
iteration=10
phase_iteration=7
stall_count=2
replan_count=3
test_failure_count=1
resumed_from="null"
write_state

# Reset variables
current_phase=""
iteration=0
phase_iteration=0
stall_count=0
replan_count=0
test_failure_count=99

# Read back
read_state
assert_equals "review" "$current_phase" "read_state restores phase"
assert_equals "10" "$iteration" "read_state restores iteration"
assert_equals "7" "$phase_iteration" "read_state restores phase_iteration"
assert_equals "2" "$stall_count" "read_state restores stall_count"
assert_equals "3" "$replan_count" "read_state restores replan_count"
assert_equals "1" "$test_failure_count" "read_state restores test_failure_count"
assert_equals "0" "$consecutive_failures" "read_state resets consecutive_failures to 0"

# --- Test: send_notification event filtering ---

NOTIFY_WEBHOOK_URL=""
NOTIFY_COMMAND=""

# No notification channels — should be a no-op
rc=0
send_notification "phase_end" "build" "complete" "Build done" || rc=$?
assert_equals "0" "$rc" "send_notification no-op when no channels configured"

# With event filtering
NOTIFY_EVENTS="phase_end,error"
NOTIFY_COMMAND="echo test"
PROJECT_ROOT="$TEST_DIR"

# Matching event — should execute (fire-and-forget)
rc=0
send_notification "phase_end" "build" "complete" "Build done" || rc=$?
assert_equals "0" "$rc" "send_notification allows matching event"

# Non-matching event — should skip
# (This is hard to test since it returns 0 either way, but we verify no crash)
rc=0
send_notification "iteration" "build" "running" "Still going" || rc=$?
assert_equals "0" "$rc" "send_notification skips non-matching event without error"

# --- Test: emit_event filtering by log level ---

WORK_LOG_ENABLED="true"
WORK_LOG="$TEST_DIR/work.jsonl"
WORK_LOG_LEVEL="minimal"
RUN_START_EPOCH=$(date +%s)
current_phase="build"
iteration=1

: > "$WORK_LOG"
emit_event "phase_start" '{"phase":"build"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "1" "$count" "emit_event writes phase_start in minimal mode"

emit_event "iteration_start" '{"iter":1}'
count=$(wc -l < "$WORK_LOG")
assert_equals "1" "$count" "emit_event filters iteration_start in minimal mode"

WORK_LOG_LEVEL="verbose"
emit_event "iteration_start" '{"iter":1}'
count=$(wc -l < "$WORK_LOG")
assert_equals "2" "$count" "emit_event writes iteration_start in verbose mode"

# Verify JSONL format
first_line=$(head -1 "$WORK_LOG")
assert_json_valid "$first_line" "emit_event produces valid JSON line"
assert_json_field "$first_line" '.event' "phase_start" "event field correct"
assert_json_field "$first_line" '.phase' "build" "phase field correct"

test_summary
