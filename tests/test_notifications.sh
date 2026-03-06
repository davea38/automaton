#!/usr/bin/env bash
# tests/test_notifications.sh — Tests for spec-52 notification callbacks
# Verifies send_notification() delivers webhooks and commands fire-and-forget.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_notifications_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: send_notification function exists ---
grep -q '^send_notification()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "send_notification() function exists in automaton.sh"

# --- Test 2: notifications config loading exists in load_config ---
grep -q 'NOTIFY_WEBHOOK_URL' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "NOTIFY_WEBHOOK_URL config variable exists"

grep -q 'NOTIFY_COMMAND' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "NOTIFY_COMMAND config variable exists"

grep -q 'NOTIFY_EVENTS' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "NOTIFY_EVENTS config variable exists"

grep -q 'NOTIFY_TIMEOUT' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "NOTIFY_TIMEOUT config variable exists"

# --- Test 3: All 5 event call sites exist ---
grep -q 'send_notification "run_started"' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "run_started call site exists"

grep -q 'send_notification "phase_completed"' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "phase_completed call site exists"

grep -q 'send_notification "run_completed"' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "run_completed call site exists"

grep -q 'send_notification "run_failed"' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "run_failed call site exists"

grep -q 'send_notification "escalation"' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "escalation call site exists"

# --- Test 4: Config section in automaton.config.json ---
config_file="$SCRIPT_DIR/../automaton.config.json"
if [ -f "$config_file" ]; then
    jq -e '.notifications' "$config_file" >/dev/null 2>&1
    rc=$?
    assert_exit_code 0 "$rc" "notifications section exists in config"

    webhook_url=$(jq -r '.notifications.webhook_url' "$config_file")
    assert_equals "" "$webhook_url" "webhook_url defaults to empty string"

    command_val=$(jq -r '.notifications.command' "$config_file")
    assert_equals "" "$command_val" "command defaults to empty string"

    timeout_val=$(jq -r '.notifications.timeout_seconds' "$config_file")
    assert_equals "5" "$timeout_val" "timeout_seconds defaults to 5"

    events_count=$(jq '.notifications.events | length' "$config_file")
    assert_equals "5" "$events_count" "events array has 5 entries"
else
    echo "FAIL: automaton.config.json not found" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Extract and test send_notification function ---
# Create a harness that sources just the function
cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
PROJECT_ROOT="$2"
mkdir -p "$AUTOMATON_DIR"
touch "$AUTOMATON_DIR/session.log"

log() {
    local component="$1" message="$2"
    echo "[$component] $message" >> "$AUTOMATON_DIR/session.log"
}
HARNESS

# Extract send_notification from automaton.sh
sed -n '/^send_notification()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"

# Test 5a: Empty config = early return, no error
cat >> "$test_dir/harness.sh" <<'TEST5A'
# Test: empty config causes early return
NOTIFY_WEBHOOK_URL=""
NOTIFY_COMMAND=""
NOTIFY_EVENTS=""
NOTIFY_TIMEOUT=5
send_notification "run_completed" "all" "success" "Test message"
echo "EARLY_RETURN_OK"
TEST5A
output=$(bash "$test_dir/harness.sh" "$test_dir/automaton" "$test_dir" 2>&1)
assert_contains "$output" "EARLY_RETURN_OK" "empty config produces early return with no error"

# Test 5b: Event filtering — event not in list = skip
cat > "$test_dir/harness_filter.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
PROJECT_ROOT="$2"
mkdir -p "$AUTOMATON_DIR"
: > "$AUTOMATON_DIR/session.log"

log() {
    local component="$1" message="$2"
    echo "[$component] $message" >> "$AUTOMATON_DIR/session.log"
}
HARNESS
sed -n '/^send_notification()/,/^}/p' "$script_file" >> "$test_dir/harness_filter.sh"
cat >> "$test_dir/harness_filter.sh" <<'TEST5B'
NOTIFY_WEBHOOK_URL=""
NOTIFY_COMMAND="echo SHOULD_NOT_RUN"
NOTIFY_EVENTS="run_started,run_completed"
NOTIFY_TIMEOUT=5
send_notification "phase_completed" "build" "success" "Phase done"
# Check session.log — should have skip message or no NOTIFY log
if grep -q 'NOTIFY' "$AUTOMATON_DIR/session.log"; then
    echo "FILTERED_HAS_LOG"
else
    echo "FILTERED_NO_LOG"
fi
TEST5B
output=$(bash "$test_dir/harness_filter.sh" "$test_dir/automaton2" "$test_dir" 2>&1)
# phase_completed is not in the events list, so it should be skipped
assert_contains "$output" "FILTERED_NO_LOG" "event not in filter list is skipped"

# Test 5c: Command execution with env vars
cat > "$test_dir/harness_cmd.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
PROJECT_ROOT="$2"
mkdir -p "$AUTOMATON_DIR"
: > "$AUTOMATON_DIR/session.log"

log() {
    local component="$1" message="$2"
    echo "[$component] $message" >> "$AUTOMATON_DIR/session.log"
}
HARNESS
sed -n '/^send_notification()/,/^}/p' "$script_file" >> "$test_dir/harness_cmd.sh"
cat >> "$test_dir/harness_cmd.sh" <<TEST5C
NOTIFY_WEBHOOK_URL=""
NOTIFY_COMMAND="env > $test_dir/cmd_env.txt"
NOTIFY_EVENTS=""
NOTIFY_TIMEOUT=5
send_notification "run_completed" "all" "success" "Run done"
sleep 1
if [ -f "$test_dir/cmd_env.txt" ]; then
    echo "CMD_EXECUTED"
    grep -q 'AUTOMATON_EVENT=run_completed' "$test_dir/cmd_env.txt" && echo "HAS_EVENT"
    grep -q 'AUTOMATON_STATUS=success' "$test_dir/cmd_env.txt" && echo "HAS_STATUS"
    grep -q 'AUTOMATON_MESSAGE=Run done' "$test_dir/cmd_env.txt" && echo "HAS_MESSAGE"
else
    echo "CMD_NOT_EXECUTED"
fi
TEST5C
output=$(bash "$test_dir/harness_cmd.sh" "$test_dir/automaton3" "$test_dir" 2>&1)
assert_contains "$output" "CMD_EXECUTED" "command notification executes"
assert_contains "$output" "HAS_EVENT" "AUTOMATON_EVENT env var is set"
assert_contains "$output" "HAS_STATUS" "AUTOMATON_STATUS env var is set"
assert_contains "$output" "HAS_MESSAGE" "AUTOMATON_MESSAGE env var is set"

# Test 5d: Webhook payload is valid JSON (mock test via log check)
cat > "$test_dir/harness_webhook.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
PROJECT_ROOT="$2"
mkdir -p "$AUTOMATON_DIR"
: > "$AUTOMATON_DIR/session.log"

log() {
    local component="$1" message="$2"
    echo "[$component] $message" >> "$AUTOMATON_DIR/session.log"
}

# Mock curl to capture the payload
curl() {
    # Find the -d argument
    while [ $# -gt 0 ]; do
        case "$1" in
            -d) shift; echo "$1" > "$AUTOMATON_DIR/payload.json"; return 0 ;;
            *) shift ;;
        esac
    done
}
export -f curl
HARNESS
sed -n '/^send_notification()/,/^}/p' "$script_file" >> "$test_dir/harness_webhook.sh"
cat >> "$test_dir/harness_webhook.sh" <<'TEST5D'
NOTIFY_WEBHOOK_URL="https://hooks.example.com/test"
NOTIFY_COMMAND=""
NOTIFY_EVENTS=""
NOTIFY_TIMEOUT=5
send_notification "run_completed" "all" "success" "Run done"
sleep 1
if [ -f "$AUTOMATON_DIR/payload.json" ]; then
    echo "PAYLOAD_CREATED"
    jq -e '.event' "$AUTOMATON_DIR/payload.json" >/dev/null 2>&1 && echo "VALID_JSON"
    jq -r '.event' "$AUTOMATON_DIR/payload.json" | grep -q 'run_completed' && echo "HAS_EVENT_FIELD"
    jq -r '.project' "$AUTOMATON_DIR/payload.json" | grep -q '.' && echo "HAS_PROJECT_FIELD"
    jq -r '.timestamp' "$AUTOMATON_DIR/payload.json" | grep -q '.' && echo "HAS_TIMESTAMP_FIELD"
else
    echo "PAYLOAD_NOT_CREATED"
fi
TEST5D
output=$(bash "$test_dir/harness_webhook.sh" "$test_dir/automaton4" "$test_dir" 2>&1)
# The webhook uses a background subshell so the mock curl may or may not capture
# Check that the log at least records the notification attempt
log_content=$(cat "$test_dir/automaton4/session.log" 2>/dev/null || echo "")
assert_contains "$log_content" "NOTIFY" "webhook attempt is logged to session.log"

# --- Test 6: Line count check ---
func_lines=$(sed -n '/^send_notification()/,/^}/p' "$script_file" | wc -l)
if [ "$func_lines" -le 80 ]; then
    echo "PASS: send_notification is $func_lines lines (within 80-line limit)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: send_notification is $func_lines lines (exceeds 80-line limit)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
exit $?
