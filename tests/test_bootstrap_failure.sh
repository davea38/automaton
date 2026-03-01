#!/usr/bin/env bash
# tests/test_bootstrap_failure.sh — tests for bootstrap failure handling (spec-37)
# Verifies: stderr capture/logging, BOOTSTRAP_FAILED flag, fallback notice in context.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

LOG_FILE="$TEMP_DIR/log_messages.txt"
: > "$LOG_FILE"
log() { echo "[$1] $2" >> "$LOG_FILE"; }
read_log() { cat "$LOG_FILE" 2>/dev/null; }

setup_bootstrap_env() {
    : > "$LOG_FILE"
    EXEC_BOOTSTRAP_ENABLED="true"
    EXEC_BOOTSTRAP_SCRIPT="$TEMP_DIR/.automaton/init.sh"
    EXEC_BOOTSTRAP_TIMEOUT_MS=2000
    AUTOMATON_DIR="$TEMP_DIR/.automaton"
    current_phase="build"
    phase_iteration=3
    BOOTSTRAP_FAILED="false"
    BOOTSTRAP_MANIFEST=""
}

# Helper: call _run_bootstrap and set BOOTSTRAP_FAILED from exit code
# (same pattern as run_agent() in automaton.sh)
run_bootstrap_with_flag() {
    BOOTSTRAP_FAILED="false"
    BOOTSTRAP_MANIFEST=$(_run_bootstrap "$@") || BOOTSTRAP_FAILED="true"
}

create_mock_init_sh() {
    mkdir -p "$TEMP_DIR/.automaton"
    cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo '{"project_state":{"phase":"build","iteration":3},"recent_changes":["abc123 test commit"]}'
INITEOF
    chmod +x "$TEMP_DIR/.automaton/init.sh"
}

# Extract functions from automaton.sh
extract_function() {
    local func_name="$1" file="$2"
    awk "/^${func_name}\\(\\)/{found=1; depth=0} found{
        for(i=1;i<=length(\$0);i++){
            c=substr(\$0,i,1)
            if(c==\"{\") depth++
            if(c==\"}\") depth--
        }
        print
        if(found && depth==0) exit
    }" "$file"
}
eval "$(extract_function _run_bootstrap "$PROJECT_ROOT/automaton.sh")"
eval "$(extract_function _format_bootstrap_for_context "$PROJECT_ROOT/automaton.sh")"

# --- Test 1: BOOTSTRAP_FAILED is false on success ---
setup_bootstrap_env
create_mock_init_sh
run_bootstrap_with_flag
assert_equals "false" "$BOOTSTRAP_FAILED" "BOOTSTRAP_FAILED is false on success"

# --- Test 2: BOOTSTRAP_FAILED is true when script errors ---
setup_bootstrap_env
mkdir -p "$TEMP_DIR/.automaton"
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo "Something went wrong in bootstrap" >&2
exit 1
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
run_bootstrap_with_flag
assert_equals "true" "$BOOTSTRAP_FAILED" "BOOTSTRAP_FAILED is true on script error"
assert_equals "" "$BOOTSTRAP_MANIFEST" "manifest is empty on script error"

# --- Test 3: stderr is captured and logged on failure ---
assert_contains "$(read_log)" "Something went wrong in bootstrap" "stderr captured and logged on failure"

# --- Test 4: BOOTSTRAP_FAILED is true when script produces invalid JSON ---
setup_bootstrap_env
mkdir -p "$TEMP_DIR/.automaton"
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo "not json" >&2
echo "definitely not json"
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
run_bootstrap_with_flag
assert_equals "true" "$BOOTSTRAP_FAILED" "BOOTSTRAP_FAILED is true on invalid JSON"

# --- Test 5: BOOTSTRAP_FAILED is true when manifest has error field ---
setup_bootstrap_env
mkdir -p "$TEMP_DIR/.automaton"
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo '{"error": "Missing dependencies: jq"}'
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
run_bootstrap_with_flag
assert_equals "true" "$BOOTSTRAP_FAILED" "BOOTSTRAP_FAILED is true on error in manifest"

# --- Test 6: BOOTSTRAP_FAILED is true when script not found ---
setup_bootstrap_env
EXEC_BOOTSTRAP_SCRIPT="$TEMP_DIR/.automaton/nonexistent.sh"
run_bootstrap_with_flag
assert_equals "true" "$BOOTSTRAP_FAILED" "BOOTSTRAP_FAILED is true when script missing"

# --- Test 7: BOOTSTRAP_FAILED remains false when bootstrap is disabled ---
setup_bootstrap_env
EXEC_BOOTSTRAP_ENABLED="false"
run_bootstrap_with_flag
assert_equals "false" "$BOOTSTRAP_FAILED" "BOOTSTRAP_FAILED is false when bootstrap disabled"

# --- Test 8: Fallback notice includes instruction to read files manually ---
setup_bootstrap_env
BOOTSTRAP_FAILED="true"
formatted=$(_format_bootstrap_for_context "")
assert_contains "$formatted" "Bootstrap" "fallback notice mentions bootstrap"
assert_contains "$formatted" "read" "fallback notice tells agent to read files"

# --- Test 9: No fallback notice when bootstrap succeeds ---
setup_bootstrap_env
create_mock_init_sh
BOOTSTRAP_FAILED="false"
run_bootstrap_with_flag
formatted=$(_format_bootstrap_for_context "$BOOTSTRAP_MANIFEST")
assert_contains "$formatted" "project_state" "success case has manifest data"

# --- Test 10: Stderr from successful script is NOT logged as error ---
setup_bootstrap_env
mkdir -p "$TEMP_DIR/.automaton"
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo "debug info" >&2
echo '{"ok": true}'
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
run_bootstrap_with_flag
assert_equals "false" "$BOOTSTRAP_FAILED" "successful script with stderr does not set failed flag"
log_content="$(read_log)"
if echo "$log_content" | grep -q "Bootstrap failed"; then
    echo "FAIL: successful script should not log 'Bootstrap failed'" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: successful script does not log 'Bootstrap failed'"
    ((_TEST_PASS_COUNT++))
fi

test_summary
