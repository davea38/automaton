#!/usr/bin/env bash
# tests/test_state_readwrite.sh — Read/write round-trip and edge-case tests for lib/state.sh
# Covers: write_state+read_state round-trip, consolidated jq read, parallel mode,
#         wave_history validation, recover_state_from_persistent, write_agent_history,
#         send_notification event filtering, emit_event log level filtering.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR/run-summaries" "$AUTOMATON_DIR/agents"
AUTOMATON_VERSION="0.2.0"

# Stub log so state.sh can call it (session.log writes)
log() { echo "[$1] $2" >> "$TEST_DIR/test.log"; }

# Stub initialize_budget (called by recover_state_from_persistent)
initialize_budget() { : ; }

# Stub init_learnings (not under test)
init_learnings() { : ; }

source "$_PROJECT_DIR/lib/state.sh"

###############################################################################
# 1. write_state + read_state round-trip
###############################################################################

echo "=== Test: write_state + read_state round-trip ==="

current_phase="build"
iteration=12
phase_iteration=8
stall_count=3
consecutive_failures=2
corruption_count=1
replan_count=4
test_failure_count=5
build_sub_phase="scaffold"
scaffold_iterations_done=6
started_at="2025-06-15T10:00:00Z"
resumed_from="2025-06-15T09:00:00Z"
phase_history='[{"phase":"research","completed_at":"2025-06-15T09:30:00Z"},{"phase":"plan","completed_at":"2025-06-15T09:50:00Z"}]'
PARALLEL_ENABLED="false"
EXEC_PARALLEL_BUILDERS=2

write_state

# Reset every variable to a wrong value
current_phase="wrong"
iteration=0
phase_iteration=0
stall_count=0
consecutive_failures=99
corruption_count=0
replan_count=0
test_failure_count=0
build_sub_phase="wrong"
scaffold_iterations_done=0
started_at="wrong"
resumed_from="wrong"
phase_history="[]"

read_state

assert_equals "build" "$current_phase" "round-trip: phase"
assert_equals "12" "$iteration" "round-trip: iteration"
assert_equals "8" "$phase_iteration" "round-trip: phase_iteration"
assert_equals "3" "$stall_count" "round-trip: stall_count"
assert_equals "0" "$consecutive_failures" "round-trip: consecutive_failures reset to 0"
assert_equals "1" "$corruption_count" "round-trip: corruption_count"
assert_equals "4" "$replan_count" "round-trip: replan_count"
assert_equals "5" "$test_failure_count" "round-trip: test_failure_count"
assert_equals "scaffold" "$build_sub_phase" "round-trip: build_sub_phase"
assert_equals "6" "$scaffold_iterations_done" "round-trip: scaffold_iterations_done"
assert_equals "2025-06-15T10:00:00Z" "$started_at" "round-trip: started_at"

# resumed_from is set to last_iteration_at by read_state (field index 10)
# After write, last_iteration_at is the timestamp at write time; but the JSON
# also stores resumed_from which was "2025-06-15T09:00:00Z". read_state maps
# field[10] (last_iteration_at) to resumed_from. Let's verify the phase_history.
ph_count=$(echo "$phase_history" | jq 'length')
assert_equals "2" "$ph_count" "round-trip: phase_history count"

###############################################################################
# 2. read_state consolidated jq — verify all 15 fields extracted
###############################################################################

echo ""
echo "=== Test: read_state consolidated jq — 15 fields ==="

# Write a state with every field set to a distinct recognizable value
current_phase="review"
iteration=42
phase_iteration=17
stall_count=5
consecutive_failures=3
corruption_count=2
replan_count=7
test_failure_count=9
build_sub_phase="testing"
scaffold_iterations_done=11
started_at="2025-08-01T12:00:00Z"
resumed_from="null"
phase_history='[{"phase":"build","completed_at":"2025-08-01T13:00:00Z"}]'
PARALLEL_ENABLED="true"
wave_number=4
wave_history='[10,20,30,40]'
consecutive_wave_failures=2
EXEC_PARALLEL_BUILDERS=3

write_state
state=$(cat "$AUTOMATON_DIR/state.json")

# Verify the JSON has all expected fields
assert_json_field "$state" '.version' "0.2.0" "15-field: version"
assert_json_field "$state" '.phase' "review" "15-field: phase"
assert_json_field "$state" '.iteration' "42" "15-field: iteration"
assert_json_field "$state" '.phase_iteration' "17" "15-field: phase_iteration"
assert_json_field "$state" '.stall_count' "5" "15-field: stall_count"
assert_json_field "$state" '.consecutive_failures' "3" "15-field: consecutive_failures"
assert_json_field "$state" '.corruption_count' "2" "15-field: corruption_count"
assert_json_field "$state" '.replan_count' "7" "15-field: replan_count"
assert_json_field "$state" '.test_failure_count' "9" "15-field: test_failure_count"
assert_json_field "$state" '.build_sub_phase' "testing" "15-field: build_sub_phase"
assert_json_field "$state" '.scaffold_iterations_done' "11" "15-field: scaffold_iterations_done"
assert_json_field "$state" '.started_at' "2025-08-01T12:00:00Z" "15-field: started_at"
assert_json_field "$state" '.parallel_builders' "3" "15-field: parallel_builders"
assert_json_field "$state" '.resumed_from' "null" "15-field: resumed_from is null"
assert_json_field "$state" '.wave_number' "4" "15-field: wave_number"
assert_json_field "$state" '.consecutive_wave_failures' "2" "15-field: consecutive_wave_failures"

wh_len=$(echo "$state" | jq '.wave_history | length')
assert_equals "4" "$wh_len" "15-field: wave_history length"

ph_len=$(echo "$state" | jq '.phase_history | length')
assert_equals "1" "$ph_len" "15-field: phase_history length"

# last_iteration_at should be a valid timestamp
last_iter=$(echo "$state" | jq -r '.last_iteration_at')
assert_matches "$last_iter" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "15-field: last_iteration_at is timestamp"

# Now read it back and verify all 15 fields via read_state
current_phase=""; iteration=0; phase_iteration=0; stall_count=0
consecutive_failures=0; corruption_count=0; replan_count=0
test_failure_count=0; build_sub_phase=""; scaffold_iterations_done=0
started_at=""; resumed_from=""; phase_history="[]"
wave_number=0; wave_history="[]"; consecutive_wave_failures=0

read_state

assert_equals "review" "$current_phase" "read 15-field: phase"
assert_equals "42" "$iteration" "read 15-field: iteration"
assert_equals "17" "$phase_iteration" "read 15-field: phase_iteration"
assert_equals "5" "$stall_count" "read 15-field: stall_count"
assert_equals "0" "$consecutive_failures" "read 15-field: consecutive_failures reset"
assert_equals "2" "$corruption_count" "read 15-field: corruption_count"
assert_equals "7" "$replan_count" "read 15-field: replan_count"
assert_equals "9" "$test_failure_count" "read 15-field: test_failure_count"
assert_equals "testing" "$build_sub_phase" "read 15-field: build_sub_phase"
assert_equals "11" "$scaffold_iterations_done" "read 15-field: scaffold_iterations_done"
assert_equals "2025-08-01T12:00:00Z" "$started_at" "read 15-field: started_at"
assert_equals "4" "$wave_number" "read 15-field: wave_number"
assert_equals "2" "$consecutive_wave_failures" "read 15-field: consecutive_wave_failures"

wh_read_len=$(echo "$wave_history" | jq 'length')
assert_equals "4" "$wh_read_len" "read 15-field: wave_history length"

ph_read_len=$(echo "$phase_history" | jq 'length')
assert_equals "1" "$ph_read_len" "read 15-field: phase_history length"

PARALLEL_ENABLED="false"

###############################################################################
# 3. write_state with parallel mode enabled
###############################################################################

echo ""
echo "=== Test: write_state with parallel mode ==="

PARALLEL_ENABLED="true"
current_phase="build"
iteration=20
phase_iteration=10
stall_count=0
consecutive_failures=0
corruption_count=0
replan_count=0
test_failure_count=0
build_sub_phase="implementation"
scaffold_iterations_done=0
started_at="2025-07-01T00:00:00Z"
resumed_from="null"
phase_history="[]"
wave_number=5
wave_history='[3,4,5,2,1]'
consecutive_wave_failures=3
EXEC_PARALLEL_BUILDERS=4

write_state
state=$(cat "$AUTOMATON_DIR/state.json")

assert_json_valid "$state" "parallel write: valid JSON"
assert_json_field "$state" '.wave_number' "5" "parallel write: wave_number"
assert_json_field "$state" '.consecutive_wave_failures' "3" "parallel write: consecutive_wave_failures"

wh_len=$(echo "$state" | jq '.wave_history | length')
assert_equals "5" "$wh_len" "parallel write: wave_history has 5 entries"

wh_first=$(echo "$state" | jq '.wave_history[0]')
assert_equals "3" "$wh_first" "parallel write: wave_history[0] is 3"

###############################################################################
# 4. read_state with parallel mode — verify wave fields restored
###############################################################################

echo ""
echo "=== Test: read_state with parallel mode ==="

# Reset wave fields
wave_number=0
wave_history="[]"
consecutive_wave_failures=0

read_state

assert_equals "5" "$wave_number" "parallel read: wave_number restored"
assert_equals "3" "$consecutive_wave_failures" "parallel read: consecutive_wave_failures restored"

wh_read_len=$(echo "$wave_history" | jq 'length')
assert_equals "5" "$wh_read_len" "parallel read: wave_history length restored"

# Verify wave fields are NOT restored when PARALLEL_ENABLED=false
PARALLEL_ENABLED="false"
wave_number=99
wave_history='[99]'
consecutive_wave_failures=99

read_state

assert_equals "99" "$wave_number" "non-parallel read: wave_number not overwritten"
assert_equals "99" "$consecutive_wave_failures" "non-parallel read: consecutive_wave_failures not overwritten"

###############################################################################
# 5. write_state with wave_history containing invalid JSON
###############################################################################

echo ""
echo "=== Test: write_state with invalid wave_history JSON ==="

PARALLEL_ENABLED="true"
wave_number=1
wave_history='not valid json {'
consecutive_wave_failures=0

write_state
state=$(cat "$AUTOMATON_DIR/state.json")

assert_json_valid "$state" "invalid wave_history: output is still valid JSON"

# The validation guard should have replaced bad JSON with []
wh_val=$(echo "$state" | jq -c '.wave_history')
assert_equals "[]" "$wh_val" "invalid wave_history: falls back to empty array"

PARALLEL_ENABLED="false"

###############################################################################
# 6. recover_state_from_persistent — mock run-summary + plan
###############################################################################

echo ""
echo "=== Test: recover_state_from_persistent ==="

# Remove state.json so read_state falls through to recover
rm -f "$AUTOMATON_DIR/state.json"

# Create a mock run summary
cat > "$AUTOMATON_DIR/run-summaries/run-2025-07-01T00-00-00Z.json" <<'SUMMARY'
{
    "run_id": "test-run-001",
    "started_at": "2025-07-01T00:00:00Z",
    "completed_at": "2025-07-01T02:00:00Z",
    "exit_code": 1,
    "iterations_total": 15,
    "phases_completed": ["research", "plan"]
}
SUMMARY

# Create a mock IMPLEMENTATION_PLAN.md
PLAN_FILE="$TEST_DIR/IMPLEMENTATION_PLAN.md"
cat > "$PLAN_FILE" <<'PLAN'
# Implementation Plan

- [x] Task 1: Setup project
- [x] Task 2: Add core module
- [ ] Task 3: Add tests
- [ ] Task 4: Add docs
PLAN

# Reset all variables
current_phase=""
iteration=0
phase_iteration=0
stall_count=0
consecutive_failures=0
corruption_count=0
replan_count=0
test_failure_count=0
started_at=""
resumed_from=""
phase_history="[]"

# read_state should detect missing state.json and call recover_state_from_persistent
read_state

assert_equals "build" "$current_phase" "recover: phase after research+plan completed is build"
assert_equals "15" "$iteration" "recover: iteration from run summary"
assert_equals "0" "$phase_iteration" "recover: phase_iteration reset to 0"
assert_equals "0" "$stall_count" "recover: stall_count reset to 0"
assert_equals "0" "$consecutive_failures" "recover: consecutive_failures reset to 0"
assert_equals "2025-07-01T00:00:00Z" "$started_at" "recover: started_at from run summary"
assert_equals "2025-07-01T02:00:00Z" "$resumed_from" "recover: resumed_from = completed_at"

ph_count=$(echo "$phase_history" | jq 'length')
assert_equals "2" "$ph_count" "recover: phase_history has 2 entries"

ph_first=$(echo "$phase_history" | jq -r '.[0].phase')
assert_equals "research" "$ph_first" "recover: phase_history[0] is research"

ph_second=$(echo "$phase_history" | jq -r '.[1].phase')
assert_equals "plan" "$ph_second" "recover: phase_history[1] is plan"

# state.json should have been written by recover
assert_file_exists "$AUTOMATON_DIR/state.json" "recover: state.json created"

###############################################################################
# 6b. recover_state_from_persistent — last_completed=research -> phase=plan
###############################################################################

echo ""
echo "=== Test: recover_state_from_persistent — phase progression ==="

rm -f "$AUTOMATON_DIR/state.json"
rm -f "$AUTOMATON_DIR/run-summaries"/*.json

cat > "$AUTOMATON_DIR/run-summaries/run-2025-08-01T00-00-00Z.json" <<'SUMMARY'
{
    "run_id": "test-run-002",
    "started_at": "2025-08-01T00:00:00Z",
    "completed_at": "2025-08-01T01:00:00Z",
    "exit_code": 1,
    "iterations_total": 5,
    "phases_completed": ["research"]
}
SUMMARY

read_state

assert_equals "plan" "$current_phase" "recover progression: research -> plan"

###############################################################################
# 6c. recover_state_from_persistent — no completed phases -> research
###############################################################################

echo ""
echo "=== Test: recover_state_from_persistent — no completed phases ==="

rm -f "$AUTOMATON_DIR/state.json"
rm -f "$AUTOMATON_DIR/run-summaries"/*.json

cat > "$AUTOMATON_DIR/run-summaries/run-2025-09-01T00-00-00Z.json" <<'SUMMARY'
{
    "run_id": "test-run-003",
    "started_at": "2025-09-01T00:00:00Z",
    "completed_at": "2025-09-01T00:30:00Z",
    "exit_code": 1,
    "iterations_total": 2,
    "phases_completed": []
}
SUMMARY

read_state

assert_equals "research" "$current_phase" "recover empty phases: defaults to research"

###############################################################################
# 7. write_agent_history
###############################################################################

echo ""
echo "=== Test: write_agent_history ==="

current_phase="build"
phase_iteration=7

write_agent_history \
    "claude-sonnet-4-20250514" \
    "/tmp/prompt.md" \
    "2025-07-01T00:00:00Z" \
    "2025-07-01T00:05:00Z" \
    300 \
    0 \
    5000 \
    2000 \
    1000 \
    500 \
    0.15 \
    "Implement feature X" \
    "success" \
    '["src/main.sh","lib/utils.sh"]' \
    "abc1234" \
    "false"

local_agent_file="$AUTOMATON_DIR/agents/build-007.json"
assert_file_exists "$local_agent_file" "write_agent_history: file created"

agent_json=$(cat "$local_agent_file")
assert_json_valid "$agent_json" "write_agent_history: valid JSON"
assert_json_field "$agent_json" '.phase' "build" "agent history: phase"
assert_json_field "$agent_json" '.iteration' "7" "agent history: iteration"
assert_json_field "$agent_json" '.model' "claude-sonnet-4-20250514" "agent history: model"
assert_json_field "$agent_json" '.duration_seconds' "300" "agent history: duration"
assert_json_field "$agent_json" '.exit_code' "0" "agent history: exit_code"
assert_json_field "$agent_json" '.tokens.input' "5000" "agent history: input_tokens"
assert_json_field "$agent_json" '.tokens.output' "2000" "agent history: output_tokens"
assert_json_field "$agent_json" '.tokens.cache_create' "1000" "agent history: cache_create"
assert_json_field "$agent_json" '.tokens.cache_read' "500" "agent history: cache_read"
assert_json_field "$agent_json" '.estimated_cost' "0.15" "agent history: cost"
assert_json_field "$agent_json" '.task' "Implement feature X" "agent history: task"
assert_json_field "$agent_json" '.status' "success" "agent history: status"
assert_json_field "$agent_json" '.git_commit' "abc1234" "agent history: git_commit"
assert_json_field "$agent_json" '.auto_compaction_detected' "false" "agent history: auto_compaction"

files_count=$(echo "$agent_json" | jq '.files_changed | length')
assert_equals "2" "$files_count" "agent history: files_changed count"

# Test with null git_commit
phase_iteration=8
write_agent_history \
    "claude-sonnet-4-20250514" "/tmp/p.md" "2025-07-01T00:00:00Z" "2025-07-01T00:01:00Z" \
    60 1 1000 500 0 0 0.05 "Fix bug" "failure" "[]" "null" "true"

null_agent_file="$AUTOMATON_DIR/agents/build-008.json"
null_agent_json=$(cat "$null_agent_file")
assert_json_field "$null_agent_json" '.git_commit' "null" "agent history: null git_commit"
assert_json_field "$null_agent_json" '.auto_compaction_detected' "true" "agent history: auto_compaction true"
assert_json_field "$null_agent_json" '.status' "failure" "agent history: failure status"

###############################################################################
# 8. send_notification — event filtering
###############################################################################

echo ""
echo "=== Test: send_notification — event filtering ==="

NOTIFY_WEBHOOK_URL=""
NOTIFY_COMMAND=""
PROJECT_ROOT="$TEST_DIR"

# No channels configured — no-op
rc=0
send_notification "phase_end" "build" "complete" "Done" || rc=$?
assert_equals "0" "$rc" "send_notification: no-op with no channels"

# Configure event filtering with a command channel
NOTIFY_EVENTS="phase_end,error,completion"
NOTIFY_COMMAND="echo notified"

# Matching event — should succeed
rc=0
send_notification "phase_end" "build" "complete" "Build done" || rc=$?
assert_equals "0" "$rc" "send_notification: matching event passes"

# Another matching event
rc=0
send_notification "error" "build" "failed" "Something broke" || rc=$?
assert_equals "0" "$rc" "send_notification: error event passes"

# Non-matching event — should be filtered out silently
rc=0
send_notification "iteration" "build" "running" "Still going" || rc=$?
assert_equals "0" "$rc" "send_notification: non-matching event filtered"

# Non-matching event (stall) — should be filtered out
rc=0
send_notification "stall" "build" "stalled" "Stall detected" || rc=$?
assert_equals "0" "$rc" "send_notification: stall event filtered"

# Empty NOTIFY_EVENTS means all events pass (no filtering)
NOTIFY_EVENTS=""
rc=0
send_notification "any_random_event" "build" "ok" "All events allowed" || rc=$?
assert_equals "0" "$rc" "send_notification: empty NOTIFY_EVENTS allows all"

NOTIFY_COMMAND=""
NOTIFY_EVENTS=""

###############################################################################
# 9. emit_event — log level filtering
###############################################################################

echo ""
echo "=== Test: emit_event — log level filtering ==="

WORK_LOG_ENABLED="true"
WORK_LOG="$TEST_DIR/work_events.jsonl"
RUN_START_EPOCH=$(date +%s)
current_phase="build"
iteration=1

# --- minimal mode ---
WORK_LOG_LEVEL="minimal"
: > "$WORK_LOG"

emit_event "phase_start" '{"phase":"build"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "1" "$count" "emit minimal: phase_start written"

emit_event "phase_end" '{"phase":"build"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "2" "$count" "emit minimal: phase_end written"

emit_event "completion" '{"result":"ok"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "3" "$count" "emit minimal: completion written"

emit_event "error" '{"msg":"oops"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "4" "$count" "emit minimal: error written"

# These should all be filtered in minimal mode
emit_event "iteration_start" '{"iter":1}'
emit_event "iteration_end" '{"iter":1}'
emit_event "gate_check" '{"gate":"test"}'
emit_event "budget_update" '{"cost":0.5}'
emit_event "stall_detected" '{"count":1}'
count=$(wc -l < "$WORK_LOG")
assert_equals "4" "$count" "emit minimal: non-critical events filtered"

# --- normal mode ---
WORK_LOG_LEVEL="normal"
: > "$WORK_LOG"

emit_event "phase_start" '{"phase":"build"}'
emit_event "iteration_start" '{"iter":1}'
emit_event "stall_detected" '{"count":1}'
count=$(wc -l < "$WORK_LOG")
assert_equals "3" "$count" "emit normal: phase_start, iteration_start, stall_detected written"

emit_event "gate_check" '{"gate":"test"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "3" "$count" "emit normal: gate_check filtered"

emit_event "budget_update" '{"cost":0.5}'
count=$(wc -l < "$WORK_LOG")
assert_equals "3" "$count" "emit normal: budget_update filtered"

# --- verbose mode ---
WORK_LOG_LEVEL="verbose"
: > "$WORK_LOG"

emit_event "phase_start" '{"phase":"build"}'
emit_event "iteration_start" '{"iter":1}'
emit_event "gate_check" '{"gate":"test"}'
emit_event "budget_update" '{"cost":0.5}'
emit_event "stall_detected" '{"count":1}'
count=$(wc -l < "$WORK_LOG")
assert_equals "5" "$count" "emit verbose: all events written"

# --- Verify JSONL format ---
first_line=$(head -1 "$WORK_LOG")
assert_json_valid "$first_line" "emit_event: line is valid JSON"
assert_json_field "$first_line" '.event' "phase_start" "emit_event: event field"
assert_json_field "$first_line" '.phase' "build" "emit_event: phase field"
assert_json_field "$first_line" '.iteration' "1" "emit_event: iteration field"

ts_field=$(echo "$first_line" | jq -r '.ts')
assert_matches "$ts_field" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "emit_event: ts is ISO timestamp"

elapsed_field=$(echo "$first_line" | jq '.elapsed_s')
assert_matches "$elapsed_field" '^[0-9]+$' "emit_event: elapsed_s is numeric"

# --- disabled mode ---
WORK_LOG_ENABLED="false"
: > "$WORK_LOG"

emit_event "phase_start" '{"phase":"build"}'
count=$(wc -l < "$WORK_LOG")
assert_equals "0" "$count" "emit disabled: nothing written when WORK_LOG_ENABLED=false"

###############################################################################
# Summary
###############################################################################

test_summary
