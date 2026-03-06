#!/usr/bin/env bash
# tests/test_qa_config.sh — Tests for spec-46 QA loop configuration
# Verifies that QA config keys exist in automaton.config.json and that
# validate_config() handles QA-specific fields correctly.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_config_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: execution.qa_enabled exists and is boolean ---
val=$(jq -r '.execution.qa_enabled | type' "$config_file")
assert_equals "boolean" "$val" "execution.qa_enabled is boolean"

# --- Test 2: execution.qa_enabled defaults to true ---
val=$(jq -r '.execution.qa_enabled' "$config_file")
assert_equals "true" "$val" "execution.qa_enabled defaults to true"

# --- Test 3: execution.qa_max_iterations exists and is number ---
val=$(jq -r '.execution.qa_max_iterations | type' "$config_file")
assert_equals "number" "$val" "execution.qa_max_iterations is number"

# --- Test 4: execution.qa_max_iterations defaults to 5 ---
val=$(jq -r '.execution.qa_max_iterations' "$config_file")
assert_equals "5" "$val" "execution.qa_max_iterations defaults to 5"

# --- Test 5: execution.qa_blind_validation exists and is boolean ---
val=$(jq -r '.execution.qa_blind_validation | type' "$config_file")
assert_equals "boolean" "$val" "execution.qa_blind_validation is boolean"

# --- Test 6: execution.qa_blind_validation defaults to false ---
val=$(jq -r '.execution.qa_blind_validation' "$config_file")
assert_equals "false" "$val" "execution.qa_blind_validation defaults to false"

# --- Test 7: execution.qa_model exists and is string ---
val=$(jq -r '.execution.qa_model | type' "$config_file")
assert_equals "string" "$val" "execution.qa_model is string"

# --- Test 8: execution.qa_model defaults to sonnet ---
val=$(jq -r '.execution.qa_model' "$config_file")
assert_equals "sonnet" "$val" "execution.qa_model defaults to sonnet"

# --- Test 9: validate_config accepts config with QA fields ---
# Extract validate_config from automaton.sh
cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
HARNESS
sed -n '/^validate_config()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"

output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$config_file'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "validate_config passes with QA config fields"

# --- Test 10: validate_config catches invalid qa_model enum ---
cp "$config_file" "$test_dir/bad_qa_model.json"
jq '.execution.qa_model = "gpt4"' "$test_dir/bad_qa_model.json" > "$test_dir/tmp.json" && mv "$test_dir/tmp.json" "$test_dir/bad_qa_model.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/bad_qa_model.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "validate_config rejects invalid qa_model"
assert_contains "$output" "qa_model" "error message mentions qa_model"

# --- Test 11: validate_config catches qa_max_iterations < 1 ---
cp "$config_file" "$test_dir/bad_qa_iters.json"
jq '.execution.qa_max_iterations = 0' "$test_dir/bad_qa_iters.json" > "$test_dir/tmp.json" && mv "$test_dir/tmp.json" "$test_dir/bad_qa_iters.json"
output=$(bash -c "source '$test_dir/harness.sh'; validate_config '$test_dir/bad_qa_iters.json'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "validate_config rejects qa_max_iterations=0"
assert_contains "$output" "qa_max_iterations" "error message mentions qa_max_iterations"

test_summary
