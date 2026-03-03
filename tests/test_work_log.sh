#!/usr/bin/env bash
# tests/test_work_log.sh — Tests for spec-55 structured work logs (JSONL)
# Verifies emit_event() writes valid JSONL, respects log levels, and call sites exist.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_work_log_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: emit_event function exists ---
grep -q '^emit_event()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "emit_event() function exists in automaton.sh"

# --- Test 2: work_log config loading exists in load_config ---
grep -q 'WORK_LOG_ENABLED' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "WORK_LOG_ENABLED config variable exists"

grep -q 'WORK_LOG_LEVEL' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "WORK_LOG_LEVEL config variable exists"

# --- Test 3: --log-level CLI flag parsing exists ---
grep -q '\-\-log-level' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--log-level CLI flag is parsed"

# --- Test 4: All 9 event call sites exist ---
for event in phase_start phase_end iteration_start iteration_end error gate_check budget_update escalation completion; do
    grep -q "emit_event \"$event\"" "$script_file"
    rc=$?
    assert_exit_code 0 "$rc" "emit_event \"$event\" call site exists"
done

# --- Test 5: Config section in automaton.config.json ---
config_file="$SCRIPT_DIR/../automaton.config.json"
if [ -f "$config_file" ]; then
    jq -e '.work_log' "$config_file" >/dev/null 2>&1
    rc=$?
    assert_exit_code 0 "$rc" "work_log section exists in config"

    enabled_val=$(jq -r '.work_log.enabled' "$config_file")
    assert_equals "true" "$enabled_val" "work_log.enabled defaults to true"

    level_val=$(jq -r '.work_log.log_level' "$config_file")
    assert_equals "normal" "$level_val" "work_log.log_level defaults to normal"
else
    echo "FAIL: automaton.config.json not found" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Extract and test emit_event function ---
cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
mkdir -p "$AUTOMATON_DIR"
touch "$AUTOMATON_DIR/session.log"

# Mock globals that emit_event reads
current_phase="build"
iteration=3
phase_iteration=2
RUN_START_EPOCH=$(date +%s)
WORK_LOG="$AUTOMATON_DIR/work-log-test.jsonl"
WORK_LOG_ENABLED="true"
WORK_LOG_LEVEL="normal"

log() {
    local component="$1" message="$2"
    echo "[$component] $message" >> "$AUTOMATON_DIR/session.log"
}
HARNESS

# Extract emit_event from automaton.sh
sed -n '/^emit_event()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"

# Test 6a: emit_event writes valid JSON line
cat >> "$test_dir/harness.sh" <<'TEST6A'
emit_event "phase_start" '{"phase_config": {}}'
if [ -f "$WORK_LOG" ]; then
    line=$(head -1 "$WORK_LOG")
    echo "$line" | jq -e '.event' >/dev/null 2>&1 && echo "VALID_JSON"
    echo "$line" | jq -r '.event' | grep -q 'phase_start' && echo "HAS_EVENT"
    echo "$line" | jq -r '.phase' | grep -q 'build' && echo "HAS_PHASE"
    echo "$line" | jq -e '.elapsed_s' >/dev/null 2>&1 && echo "HAS_ELAPSED"
    echo "$line" | jq -e '.ts' >/dev/null 2>&1 && echo "HAS_TS"
    echo "$line" | jq -e '.iteration' >/dev/null 2>&1 && echo "HAS_ITERATION"
else
    echo "NO_LOG_FILE"
fi
TEST6A
output=$(bash "$test_dir/harness.sh" "$test_dir/automaton" 2>&1)
assert_contains "$output" "VALID_JSON" "emit_event writes valid JSON"
assert_contains "$output" "HAS_EVENT" "event field is set correctly"
assert_contains "$output" "HAS_PHASE" "phase field is set correctly"
assert_contains "$output" "HAS_ELAPSED" "elapsed_s field is present"
assert_contains "$output" "HAS_TS" "ts field is present"
assert_contains "$output" "HAS_ITERATION" "iteration field is present"

# Test 6b: emit_event is no-op when disabled
cat > "$test_dir/harness_disabled.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
mkdir -p "$AUTOMATON_DIR"
touch "$AUTOMATON_DIR/session.log"
current_phase="build"
iteration=1
phase_iteration=1
RUN_START_EPOCH=$(date +%s)
WORK_LOG="$AUTOMATON_DIR/work-log-disabled.jsonl"
WORK_LOG_ENABLED="false"
WORK_LOG_LEVEL="normal"
log() { :; }
HARNESS
sed -n '/^emit_event()/,/^}/p' "$script_file" >> "$test_dir/harness_disabled.sh"
cat >> "$test_dir/harness_disabled.sh" <<'TEST6B'
emit_event "phase_start" '{"phase_config": {}}'
if [ -f "$WORK_LOG" ]; then
    echo "FILE_CREATED"
else
    echo "NO_FILE_CREATED"
fi
TEST6B
output=$(bash "$test_dir/harness_disabled.sh" "$test_dir/automaton_disabled" 2>&1)
assert_contains "$output" "NO_FILE_CREATED" "emit_event is no-op when disabled"

# Test 6c: Log level filtering — minimal should skip iteration_start
cat > "$test_dir/harness_minimal.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
mkdir -p "$AUTOMATON_DIR"
touch "$AUTOMATON_DIR/session.log"
current_phase="build"
iteration=1
phase_iteration=1
RUN_START_EPOCH=$(date +%s)
WORK_LOG="$AUTOMATON_DIR/work-log-minimal.jsonl"
WORK_LOG_ENABLED="true"
WORK_LOG_LEVEL="minimal"
log() { :; }
HARNESS
sed -n '/^emit_event()/,/^}/p' "$script_file" >> "$test_dir/harness_minimal.sh"
cat >> "$test_dir/harness_minimal.sh" <<'TEST6C'
emit_event "phase_start" '{}'
emit_event "iteration_start" '{"task":"test"}'
emit_event "gate_check" '{"gate":"test","passed":true}'
line_count=$(wc -l < "$WORK_LOG")
echo "LINES=$line_count"
# minimal should only include phase_start (iteration_start and gate_check are excluded)
TEST6C
output=$(bash "$test_dir/harness_minimal.sh" "$test_dir/automaton_minimal" 2>&1)
assert_contains "$output" "LINES=1" "minimal log level filters out non-minimal events"

# Test 6d: Log level filtering — verbose should include gate_check
cat > "$test_dir/harness_verbose.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
mkdir -p "$AUTOMATON_DIR"
touch "$AUTOMATON_DIR/session.log"
current_phase="build"
iteration=1
phase_iteration=1
RUN_START_EPOCH=$(date +%s)
WORK_LOG="$AUTOMATON_DIR/work-log-verbose.jsonl"
WORK_LOG_ENABLED="true"
WORK_LOG_LEVEL="verbose"
log() { :; }
HARNESS
sed -n '/^emit_event()/,/^}/p' "$script_file" >> "$test_dir/harness_verbose.sh"
cat >> "$test_dir/harness_verbose.sh" <<'TEST6D'
emit_event "phase_start" '{}'
emit_event "iteration_start" '{"task":"test"}'
emit_event "gate_check" '{"gate":"test","passed":true}'
line_count=$(wc -l < "$WORK_LOG")
echo "LINES=$line_count"
TEST6D
output=$(bash "$test_dir/harness_verbose.sh" "$test_dir/automaton_verbose" 2>&1)
assert_contains "$output" "LINES=3" "verbose log level includes all events"

# --- Test 7: Line count check ---
func_lines=$(sed -n '/^emit_event()/,/^}/p' "$script_file" | wc -l)
if [ "$func_lines" -le 40 ]; then
    echo "PASS: emit_event is $func_lines lines (within 40-line limit)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: emit_event is $func_lines lines (exceeds 40-line limit)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
exit $?
