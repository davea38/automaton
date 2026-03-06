#!/usr/bin/env bash
# tests/test_context_functional.sh — Functional tests for lib/context.sh
# Tests bootstrap execution, dynamic context injection, prompt size logging, and cache threshold checks.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Stubs for dependencies
_log_output=""
log() { _log_output+="[$1] $2"$'\n'; }
EXEC_BOOTSTRAP_ENABLED="false"
EXEC_BOOTSTRAP_SCRIPT="$AUTOMATON_DIR/init.sh"
EXEC_BOOTSTRAP_TIMEOUT_MS=5000
BOOTSTRAP_MANIFEST=""
BOOTSTRAP_FAILED="false"
BOOTSTRAP_TIME_MS=0
BOOTSTRAP_TOKENS_SAVED=0

source "$_PROJECT_DIR/lib/context.sh"

# --- Test: _run_bootstrap returns empty when disabled ---

result=$(_run_bootstrap "build" "1")
assert_equals "" "$result" "_run_bootstrap returns empty when disabled"

# --- Test: _run_bootstrap fails when script missing ---

EXEC_BOOTSTRAP_ENABLED="true"
rc=0
_run_bootstrap "build" "1" || rc=$?
assert_equals "1" "$rc" "_run_bootstrap returns 1 when script missing"

# --- Test: _run_bootstrap with a working script ---

cat > "$AUTOMATON_DIR/init.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo '{"project_state":{"phase":"build","iteration":1}}'
SCRIPT
chmod +x "$AUTOMATON_DIR/init.sh"

result=$(_run_bootstrap "build" "1")
assert_json_valid "$result" "_run_bootstrap returns valid JSON"
assert_json_field "$result" '.project_state.phase' "build" "bootstrap manifest has phase"

# --- Test: _run_bootstrap rejects invalid JSON ---

cat > "$AUTOMATON_DIR/init.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "not json"
SCRIPT
chmod +x "$AUTOMATON_DIR/init.sh"

rc=0
_run_bootstrap "build" "1" || rc=$?
assert_equals "1" "$rc" "_run_bootstrap rejects invalid JSON"

# --- Test: _run_bootstrap detects error field ---

cat > "$AUTOMATON_DIR/init.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo '{"error": "Missing dependencies: jq"}'
SCRIPT
chmod +x "$AUTOMATON_DIR/init.sh"

rc=0
_run_bootstrap "build" "1" || rc=$?
assert_equals "1" "$rc" "_run_bootstrap detects error field in manifest"

# --- Test: _bootstrap_estimate_tokens_saved ---

BOOTSTRAP_TOKENS_SAVED=0
_bootstrap_estimate_tokens_saved '{"small":"manifest"}'
assert_matches "$BOOTSTRAP_TOKENS_SAVED" '^[0-9]+$' "tokens_saved is numeric"
# A small manifest should save close to 30000 tokens
if [ "$BOOTSTRAP_TOKENS_SAVED" -gt 29000 ]; then
    echo "PASS: small manifest saves ~30000 tokens"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: expected ~30000 saved, got $BOOTSTRAP_TOKENS_SAVED"
    ((_TEST_FAIL_COUNT++))
fi

# --- Test: _format_bootstrap_for_context with manifest ---

output=$(_format_bootstrap_for_context '{"phase":"build"}')
assert_contains "$output" "Bootstrap Manifest" "format includes header"
assert_contains "$output" '```json' "format includes json block"
assert_contains "$output" "do NOT re-read" "format includes cache hint"

# --- Test: _format_bootstrap_for_context when bootstrap failed ---

BOOTSTRAP_FAILED="true"
output=$(_format_bootstrap_for_context "")
assert_contains "$output" "Bootstrap Failed" "format shows failure notice"
assert_contains "$output" "read AGENTS.md" "format tells agent to read manually"
BOOTSTRAP_FAILED="false"

# --- Test: _format_bootstrap_for_context with empty manifest (no failure) ---

output=$(_format_bootstrap_for_context "")
assert_equals "" "$output" "format returns empty when no manifest and no failure"

# --- Test: inject_dynamic_context with no dynamic_context tag ---

prompt_file="$TEST_DIR/prompt_no_dc.md"
cat > "$prompt_file" <<'EOF'
# Static prompt
No dynamic context tag here.
EOF

result=$(inject_dynamic_context "$prompt_file")
assert_equals "" "$result" "inject_dynamic_context returns empty when no tag"

# --- Test: inject_dynamic_context with dynamic_context tag ---

current_phase="build"
phase_iteration=3
EXEC_TEST_FIRST_ENABLED="false"
SELF_BUILD_ENABLED="false"
ARG_SELF="false"
COMPACTION_REDUCE_CONTEXT="false"

prompt_file="$TEST_DIR/prompt_with_dc.md"
cat > "$prompt_file" <<'EOF'
# Static Prompt Content
This should be preserved exactly.
<dynamic_context>
placeholder
</dynamic_context>
# Footer content
EOF

result=$(inject_dynamic_context "$prompt_file")
assert_file_exists "$result" "inject_dynamic_context creates augmented file"

augmented=$(cat "$result")
assert_contains "$augmented" "Static Prompt Content" "augmented preserves static prefix"
assert_contains "$augmented" "Phase: build" "augmented includes phase"
assert_contains "$augmented" "Iteration: 3" "augmented includes iteration"
assert_contains "$augmented" "Footer content" "augmented preserves footer"
assert_not_contains "$augmented" "placeholder" "augmented replaces placeholder"

# --- Test: log_prompt_size ---

_log_output=""
prompt_file="$TEST_DIR/test_prompt.md"
printf '%0.s#' {1..400} > "$prompt_file"  # 400 chars

log_prompt_size "$prompt_file"
assert_contains "$_log_output" "400 chars" "log_prompt_size reports char count"
assert_contains "$_log_output" "~100 tokens" "log_prompt_size estimates tokens"

# --- Test: log_prompt_size with missing file ---

_log_output=""
log_prompt_size "$TEST_DIR/nonexistent.md"
assert_equals "" "$_log_output" "log_prompt_size no-op for missing file"

# --- Test: check_cache_prefix_threshold ---

_log_output=""
prompt_file="$TEST_DIR/small_prompt.md"
# Create a prompt with small static prefix (100 chars) and dynamic_context
{
    printf '%0.s#' {1..100}
    echo ""
    echo "<dynamic_context>"
    echo "dynamic stuff"
    echo "</dynamic_context>"
} > "$prompt_file"

check_cache_prefix_threshold "$prompt_file" "opus"
assert_contains "$_log_output" "below the 4096-token minimum" "warns about small static prefix for opus"

_log_output=""
check_cache_prefix_threshold "$prompt_file" "sonnet"
assert_contains "$_log_output" "below the 2048-token minimum" "warns about small static prefix for sonnet"

# --- Test: check_cache_prefix_threshold with large prefix ---

_log_output=""
large_prompt="$TEST_DIR/large_prompt.md"
{
    # 20000 chars = ~5000 tokens, above any threshold
    python3 -c "print('#' * 20000)" 2>/dev/null || printf '%0.s#' $(seq 1 20000)
    echo ""
    echo "<dynamic_context>"
    echo "dynamic"
    echo "</dynamic_context>"
} > "$large_prompt"

check_cache_prefix_threshold "$large_prompt" "opus"
assert_not_contains "$_log_output" "below" "no warning for large static prefix"

test_summary
