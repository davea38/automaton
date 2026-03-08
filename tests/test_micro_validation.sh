#!/usr/bin/env bash
# tests/test_micro_validation.sh — Tests for post-task micro-validation (audit wave 4)
# Verifies that run_micro_validation invokes a lightweight check after build
# iterations and records results.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

setup_test_dir

# --- Stubs ---
log() { :; }
emit_event() { :; }
extract_tokens() { :; }

# Stub run_agent: records calls and simulates JSON verdict output
_micro_validation_calls=0
_micro_validation_model=""
_micro_validation_verdict="PASS"
run_agent() {
    local prompt="$1" model="$2"
    _micro_validation_calls=$((_micro_validation_calls + 1))
    _micro_validation_model="$model"
    AGENT_EXIT_CODE=0
    # Simulate agent output with verdict JSON
    AGENT_RESULT=$(cat <<EOF
{"type":"result","result":"{ \"task\": \"test task\", \"verdict\": \"${_micro_validation_verdict}\", \"test_passed\": true, \"syntax_ok\": true, \"criterion_met\": true, \"reason\": \"\" }"}
EOF
)
}

# Source lifecycle module
source "$_PROJECT_DIR/lib/lifecycle.sh"

# --- Setup for each test ---
setup_micro_test() {
    rm -rf "$TEST_DIR/.automaton"
    mkdir -p "$TEST_DIR/.automaton"
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export AUTOMATON_INSTALL_DIR="$_PROJECT_DIR"
    _micro_validation_calls=0
    _micro_validation_model=""
    _micro_validation_verdict="PASS"
    MICRO_VALIDATION_ENABLED="true"
    AGENT_RESULT=""
    AGENT_EXIT_CODE=0
    current_phase="build"
    phase_iteration=1
}

# ============================================================
# Test 1: run_micro_validation is skipped when disabled
# ============================================================
setup_micro_test
MICRO_VALIDATION_ENABLED="false"

run_micro_validation "test task" "tests/test_example.sh"
rc=$?

assert_equals "0" "$rc" "micro-validation returns 0 when disabled"
assert_equals "0" "$_micro_validation_calls" "no agent invoked when disabled"

# ============================================================
# Test 2: run_micro_validation invokes agent with sonnet model
# ============================================================
setup_micro_test

run_micro_validation "test task" "tests/test_example.sh"
rc=$?

assert_equals "0" "$rc" "micro-validation returns 0 on PASS verdict"
assert_equals "1" "$_micro_validation_calls" "agent invoked once"
assert_equals "sonnet" "$_micro_validation_model" "micro-validation uses sonnet model"

# ============================================================
# Test 3: run_micro_validation records result to file
# ============================================================
setup_micro_test

run_micro_validation "implement feature X" "tests/test_feature_x.sh"

assert_file_exists "$AUTOMATON_DIR/micro_validation_last.json" "result file created"
result_json=$(cat "$AUTOMATON_DIR/micro_validation_last.json")
assert_json_valid "$result_json" "result is valid JSON"
assert_json_field "$result_json" ".verdict" "PASS" "verdict recorded as PASS"

# ============================================================
# Test 4: FAIL verdict returns 1
# ============================================================
setup_micro_test
_micro_validation_verdict="FAIL"

run_micro_validation "broken task" "tests/test_broken.sh"
rc=$?

assert_equals "1" "$rc" "micro-validation returns 1 on FAIL verdict"
result_json=$(cat "$AUTOMATON_DIR/micro_validation_last.json")
assert_json_field "$result_json" ".verdict" "FAIL" "verdict recorded as FAIL"

# ============================================================
# Test 5: UNCERTAIN verdict returns 0 (benefit of the doubt)
# ============================================================
setup_micro_test
_micro_validation_verdict="UNCERTAIN"

run_micro_validation "unclear task" "tests/test_unclear.sh"
rc=$?

assert_equals "0" "$rc" "micro-validation returns 0 on UNCERTAIN verdict"

# ============================================================
# Test 6: run_micro_validation is skipped for non-build phases
# ============================================================
setup_micro_test
current_phase="review"

run_micro_validation "review task" ""
rc=$?

assert_equals "0" "$rc" "micro-validation returns 0 for non-build phase"
assert_equals "0" "$_micro_validation_calls" "no agent invoked for non-build phase"

# ============================================================
# Test 7: micro-validation prompt file content is passed
# ============================================================
setup_micro_test
# Override run_agent to capture prompt content
_captured_prompt=""
_captured_content=""
run_agent() {
    _captured_prompt="$1"
    _captured_content=""
    [ -f "$1" ] && _captured_content=$(cat "$1")
    _micro_validation_calls=$((_micro_validation_calls + 1))
    _micro_validation_model="$2"
    AGENT_EXIT_CODE=0
    AGENT_RESULT='{"type":"result","result":"{ \"task\": \"t\", \"verdict\": \"PASS\", \"test_passed\": true, \"syntax_ok\": true, \"criterion_met\": true, \"reason\": \"\" }"}'
}

run_micro_validation "task" "tests/test_x.sh"

assert_contains "$_captured_content" "Micro-Validation Agent" "prompt contains micro-validation identity"

# ============================================================
# Test 8: consecutive failure count tracking
# ============================================================
setup_micro_test
_micro_validation_verdict="FAIL"

# Restore standard stub
run_agent() {
    local prompt="$1" model="$2"
    _micro_validation_calls=$((_micro_validation_calls + 1))
    _micro_validation_model="$model"
    AGENT_EXIT_CODE=0
    AGENT_RESULT='{"type":"result","result":"{ \"task\": \"t\", \"verdict\": \"FAIL\", \"test_passed\": false, \"syntax_ok\": true, \"criterion_met\": false, \"reason\": \"test failed\" }"}'
}

run_micro_validation "fail1" "tests/t.sh"
count=$(jq -r '.consecutive_failures' "$AUTOMATON_DIR/micro_validation_last.json")
assert_equals "1" "$count" "first failure: consecutive_failures=1"

run_micro_validation "fail2" "tests/t.sh"
count=$(jq -r '.consecutive_failures' "$AUTOMATON_DIR/micro_validation_last.json")
assert_equals "2" "$count" "second failure: consecutive_failures=2"

# ============================================================
# Test 9: PASS resets consecutive failure count
# ============================================================
# Continue from test 8 (consecutive_failures=2)
run_agent() {
    _micro_validation_calls=$((_micro_validation_calls + 1))
    _micro_validation_model="$2"
    AGENT_EXIT_CODE=0
    AGENT_RESULT='{"type":"result","result":"{ \"task\": \"t\", \"verdict\": \"PASS\", \"test_passed\": true, \"syntax_ok\": true, \"criterion_met\": true, \"reason\": \"\" }"}'
}

run_micro_validation "pass_now" "tests/t.sh"
count=$(jq -r '.consecutive_failures' "$AUTOMATON_DIR/micro_validation_last.json")
assert_equals "0" "$count" "PASS resets consecutive_failures to 0"

test_summary
