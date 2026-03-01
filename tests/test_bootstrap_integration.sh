#!/usr/bin/env bash
# tests/test_bootstrap_integration.sh — tests for bootstrap integration in run_agent() (spec-37)
# Tests _run_bootstrap() function and dynamic context injection of bootstrap manifest.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Create a temporary project directory for isolated testing
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# --- Helper: extract _run_bootstrap function from automaton.sh ---
# We source the function definition directly to test it in isolation.
# Also define minimal stubs for dependencies (log, config vars).

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
}

# Create a working init.sh mock that outputs known JSON
create_mock_init_sh() {
    mkdir -p "$TEMP_DIR/.automaton"
    cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo '{"project_state":{"phase":"build","iteration":3},"recent_changes":["abc123 test commit"],"budget":{"used_usd":10,"limit_usd":50,"remaining_usd":40}}'
INITEOF
    chmod +x "$TEMP_DIR/.automaton/init.sh"
}

# Extract _run_bootstrap and _format_bootstrap_for_context from automaton.sh
# Use awk to properly handle nested braces
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

# --- Test 1: Bootstrap produces valid JSON when enabled ---
setup_bootstrap_env
create_mock_init_sh
manifest=$(_run_bootstrap)
echo "$manifest" | jq empty 2>/dev/null
assert_exit_code 0 $? "bootstrap produces valid JSON when enabled"

# --- Test 2: Manifest contains expected fields ---
phase=$(echo "$manifest" | jq -r '.project_state.phase')
assert_equals "build" "$phase" "bootstrap manifest has correct phase"

# --- Test 3: Bootstrap disabled returns empty ---
setup_bootstrap_env
EXEC_BOOTSTRAP_ENABLED="false"
manifest=$(_run_bootstrap)
assert_equals "" "$manifest" "bootstrap returns empty when disabled"

# --- Test 4: Missing init.sh returns empty and logs warning ---
setup_bootstrap_env
EXEC_BOOTSTRAP_SCRIPT="$TEMP_DIR/.automaton/nonexistent.sh"
manifest=$(_run_bootstrap)
assert_equals "" "$manifest" "bootstrap returns empty when script missing"
assert_contains "$(read_log)" "not found" "logs warning when script missing"

# --- Test 5: init.sh that exits with error returns empty ---
setup_bootstrap_env
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
exit 1
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
manifest=$(_run_bootstrap)
assert_equals "" "$manifest" "bootstrap returns empty on script error"
assert_contains "$(read_log)" "Bootstrap failed" "logs fallback on script error"

# --- Test 6: init.sh that outputs invalid JSON returns empty ---
setup_bootstrap_env
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo "not valid json at all"
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
manifest=$(_run_bootstrap)
assert_equals "" "$manifest" "bootstrap returns empty on invalid JSON"
assert_contains "$(read_log)" "invalid JSON" "logs warning on invalid JSON"

# --- Test 7: init.sh that outputs error field returns empty ---
setup_bootstrap_env
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
echo '{"error": "Missing dependencies: jq"}'
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
manifest=$(_run_bootstrap)
assert_equals "" "$manifest" "bootstrap returns empty on error in manifest"
assert_contains "$(read_log)" "Bootstrap error" "logs error from manifest"

# --- Test 8: Bootstrap manifest formatted for dynamic context ---
setup_bootstrap_env
create_mock_init_sh
manifest=$(_run_bootstrap)
formatted=$(_format_bootstrap_for_context "$manifest")
assert_contains "$formatted" "Bootstrap Manifest" "formatted context has header"
assert_contains "$formatted" "project_state" "formatted context has manifest data"

# --- Test 9: Empty manifest produces no formatted output ---
formatted=$(_format_bootstrap_for_context "")
assert_equals "" "$formatted" "empty manifest produces no formatted output"

# --- Test 10: Phase and iteration arguments are passed to init.sh ---
setup_bootstrap_env
cat > "$TEMP_DIR/.automaton/init.sh" <<'INITEOF'
#!/usr/bin/env bash
# Echo back the arguments we received
echo "{\"received_phase\":\"$2\",\"received_iteration\":$3}"
INITEOF
chmod +x "$TEMP_DIR/.automaton/init.sh"
manifest=$(_run_bootstrap "research" "5")
recv_phase=$(echo "$manifest" | jq -r '.received_phase')
assert_equals "research" "$recv_phase" "phase argument passed to init.sh"
recv_iter=$(echo "$manifest" | jq -r '.received_iteration')
assert_equals "5" "$recv_iter" "iteration argument passed to init.sh"

test_summary
