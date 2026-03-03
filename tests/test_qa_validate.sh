#!/usr/bin/env bash
# tests/test_qa_validate.sh — Tests for spec-46.2 QA validation pass
# Verifies _qa_validate() runs three checks: test execution, spec criteria,
# and regression scan, returning structured results.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_validate_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Extract functions from automaton.sh ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
CONFIG_FILE_USED=""
QA_ENABLED="true"
QA_MAX_ITERATIONS=5
QA_MODEL="sonnet"
QA_BLIND_VALIDATION="false"
HARNESS
    # Extract QA functions
    for fn in _qa_validate _qa_run_tests _qa_check_spec_criteria _qa_scan_regressions _qa_classify_failure _qa_write_iteration; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 1: _qa_validate function exists ---
grep -q '^_qa_validate() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_validate function exists in automaton.sh"

# --- Test 2: _qa_run_tests function exists ---
grep -q '^_qa_run_tests() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_run_tests function exists in automaton.sh"

# --- Test 3: _qa_check_spec_criteria function exists ---
grep -q '^_qa_check_spec_criteria() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_check_spec_criteria function exists in automaton.sh"

# --- Test 4: _qa_scan_regressions function exists ---
grep -q '^_qa_scan_regressions() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_scan_regressions function exists in automaton.sh"

# --- Test 5: _qa_validate creates .automaton/qa/ directory ---
mkdir -p "$test_dir/project/.automaton"
TEST_AUTOMATON_DIR="$test_dir/project/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_validate 1 '' 'bash -n /dev/null' ''" 2>/dev/null || true
if [ -d "$test_dir/project/.automaton/qa" ]; then
    assert_exit_code 0 0 "_qa_validate creates .automaton/qa/ directory"
else
    assert_exit_code 0 1 "_qa_validate creates .automaton/qa/ directory"
fi

# --- Test 6: _qa_run_tests captures exit code ---
mkdir -p "$test_dir/project2/.automaton/qa"
output=$(TEST_AUTOMATON_DIR="$test_dir/project2/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_run_tests 'exit 0'; echo \$?" 2>/dev/null)
# The last line should be 0 or contain the exit code
assert_contains "$output" "0" "_qa_run_tests captures successful exit code"

# --- Test 7: _qa_run_tests captures failure exit code ---
output=$(TEST_AUTOMATON_DIR="$test_dir/project2/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_run_tests 'exit 1'; echo \$?" 2>/dev/null)
assert_contains "$output" "1" "_qa_run_tests captures failed exit code"

# --- Test 8: _qa_validate produces JSON output ---
mkdir -p "$test_dir/project3/.automaton/qa"
output=$(TEST_AUTOMATON_DIR="$test_dir/project3/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_validate 1 '' 'exit 0' ''" 2>/dev/null) || true
# Check that it produced valid JSON output
if echo "$output" | jq empty 2>/dev/null; then
    assert_exit_code 0 0 "_qa_validate produces valid JSON output"
else
    assert_exit_code 0 1 "_qa_validate produces valid JSON output"
fi

# --- Test 9: _qa_validate output contains required fields ---
if echo "$output" | jq -e '.iteration and .checks and .verdict' >/dev/null 2>&1; then
    assert_exit_code 0 0 "_qa_validate output has iteration, checks, verdict fields"
else
    assert_exit_code 0 1 "_qa_validate output has iteration, checks, verdict fields"
fi

# --- Test 10: _qa_validate with passing tests returns PASS verdict ---
output=$(TEST_AUTOMATON_DIR="$test_dir/project3/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_validate 1 '' 'exit 0' ''" 2>/dev/null) || true
verdict=$(echo "$output" | jq -r '.verdict' 2>/dev/null)
assert_equals "PASS" "$verdict" "_qa_validate returns PASS with passing tests"

# --- Test 11: _qa_validate with failing tests returns FAIL verdict ---
output=$(TEST_AUTOMATON_DIR="$test_dir/project3/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_validate 1 '' 'echo FAIL; exit 1' ''" 2>/dev/null) || true
verdict=$(echo "$output" | jq -r '.verdict' 2>/dev/null)
assert_equals "FAIL" "$verdict" "_qa_validate returns FAIL with failing tests"

# --- Test 12: _qa_validate writes iteration file ---
mkdir -p "$test_dir/project4/.automaton/qa"
TEST_AUTOMATON_DIR="$test_dir/project4/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_validate 1 '' 'exit 0' ''" >/dev/null 2>&1 || true
if [ -f "$test_dir/project4/.automaton/qa/iteration-1.json" ]; then
    assert_exit_code 0 0 "_qa_validate writes iteration-1.json"
else
    assert_exit_code 0 1 "_qa_validate writes iteration-1.json"
fi

test_summary
