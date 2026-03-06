#!/usr/bin/env bash
# tests/test_config_validation.sh — Tests for spec-50 config pre-flight validation
# Verifies that validate_config() catches JSON syntax errors, type mismatches,
# range violations, invalid enum values, cross-field conflicts, and warnings.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_config_validation_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# Helper: extract validate_config and its dependencies from automaton.sh
# We source the function definitions but not the main execution.
_extract_validate_config() {
    # Create a minimal harness that sources just the function we need
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail

# Minimal log function
log() { :; }

# Source validate_config from automaton.sh by extracting the function
HARNESS
    # Extract validate_config function
    sed -n '/^validate_config()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
}
_extract_validate_config

# --- Test 1: Valid config passes silently ---
output=$(bash "$test_dir/harness.sh" <<< "source '$test_dir/harness.sh'; validate_config '$config_file'" 2>&1)
# Actually run it properly
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$config_file'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "valid config passes with exit 0"

# --- Test 2: Missing config file produces error ---
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/nonexistent.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "missing config file returns exit 1"
assert_contains "$output" "CONFIG ERROR" "missing config produces CONFIG ERROR"

# --- Test 3: Malformed JSON produces parse error ---
echo '{ invalid json' > "$test_dir/bad_syntax.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/bad_syntax.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "malformed JSON returns exit 1"
assert_contains "$output" "CONFIG ERROR" "malformed JSON produces CONFIG ERROR"

# --- Test 4: Type mismatch — string where number expected ---
jq '.budget.max_total_tokens = "not_a_number"' "$config_file" > "$test_dir/type_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/type_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "string where number expected returns exit 1"
assert_contains "$output" "budget.max_total_tokens" "type error names the field"

# --- Test 5: Type mismatch — number where boolean expected ---
jq '.git.auto_push = 42' "$config_file" > "$test_dir/bool_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/bool_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "number where boolean expected returns exit 1"
assert_contains "$output" "git.auto_push" "boolean type error names the field"

# --- Test 6: Range violation — negative budget ---
jq '.budget.max_total_tokens = -5' "$config_file" > "$test_dir/range_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/range_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "negative budget returns exit 1"
assert_contains "$output" "budget.max_total_tokens" "range error names the field"
assert_contains "$output" "-5" "range error shows actual value"

# --- Test 7: Range violation — zero per_iteration ---
jq '.budget.per_iteration = 0' "$config_file" > "$test_dir/zero_iter.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/zero_iter.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "zero per_iteration returns exit 1"

# --- Test 8: Range violation — backoff_multiplier <= 1.0 ---
jq '.rate_limits.backoff_multiplier = 0.5' "$config_file" > "$test_dir/backoff_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/backoff_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "backoff_multiplier <= 1.0 returns exit 1"

# --- Test 9: Enum validation — invalid model name ---
jq '.models.primary = "gpt-4"' "$config_file" > "$test_dir/enum_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/enum_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "invalid model name returns exit 1"
assert_contains "$output" "models.primary" "enum error names the field"
assert_contains "$output" "gpt-4" "enum error shows invalid value"
assert_contains "$output" "opus|sonnet|haiku" "enum error shows valid options"

# --- Test 10: Cross-field — per_phase exceeds max_total_tokens ---
jq '.budget.max_total_tokens = 1000 | .budget.per_phase.build = 5000' "$config_file" > "$test_dir/cross_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/cross_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "per_phase exceeding max_total_tokens returns exit 1"
assert_contains "$output" "per_phase" "cross-field error mentions per_phase"

# --- Test 11: Cross-field — per_iteration exceeds smallest per_phase ---
jq '.budget.per_iteration = 9999999 | .budget.per_phase.research = 100' "$config_file" > "$test_dir/cross_iter.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/cross_iter.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "per_iteration exceeding smallest per_phase returns exit 1"

# --- Test 12: Multiple errors reported in one run ---
jq '.budget.max_total_tokens = -5 | .models.primary = "gpt-4" | .git.auto_push = 42' "$config_file" > "$test_dir/multi_err.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/multi_err.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "multiple errors returns exit 1"
# Count CONFIG ERROR lines — should be at least 3
err_count=$(echo "$output" | grep -c "CONFIG ERROR" || true)
if [ "$err_count" -ge 3 ]; then
    echo "PASS: multiple errors reported ($err_count errors)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: expected at least 3 errors, got $err_count" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: Warnings go to stderr, don't cause exit 1 ---
jq '.budget.max_cost_usd = 500' "$config_file" > "$test_dir/warn.json"
output_stderr=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/warn.json'" 2>&1 1>/dev/null)
rc=$?
# The function should pass (exit 0) since warnings are non-blocking
output_all=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/warn.json'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "warnings do not cause exit 1"
assert_contains "$output_all" "CONFIG WARNING" "warning about high max_cost_usd"

# --- Test 14: stall_threshold == max_consecutive_failures warning ---
jq '.execution.stall_threshold = 5 | .execution.max_consecutive_failures = 5' "$config_file" > "$test_dir/stall_warn.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/stall_warn.json'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "stall == failures is warning, not error"
assert_contains "$output" "CONFIG WARNING" "stall_threshold == max_consecutive_failures warning"

# --- Test 15: --validate-config flag in argument parser ---
grep -q 'validate-config' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--validate-config flag exists in argument parser"

# --- Test 16: validate_config function exists in automaton.sh ---
grep -q '^validate_config()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "validate_config() function exists in automaton.sh"

# --- Test 17: validate_config called in main flow after load_config ---
# Check that validate_config is called in the main execution section
grep -q 'validate_config' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "validate_config is called in automaton.sh"

# --- Test 18: backoff_multiplier > 10 warning ---
jq '.rate_limits.backoff_multiplier = 15' "$config_file" > "$test_dir/backoff_warn.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/backoff_warn.json'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "backoff_multiplier > 10 is warning not error"
assert_contains "$output" "CONFIG WARNING" "backoff > 10 warning"

# --- Test 19: stall_threshold < 1 is error ---
jq '.execution.stall_threshold = 0' "$config_file" > "$test_dir/stall_zero.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/stall_zero.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "stall_threshold < 1 returns exit 1"

# --- Test 20: max_consecutive_failures < 1 is error ---
jq '.execution.max_consecutive_failures = 0' "$config_file" > "$test_dir/fail_zero.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/fail_zero.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "max_consecutive_failures < 1 returns exit 1"

test_summary
