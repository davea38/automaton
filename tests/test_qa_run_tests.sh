#!/usr/bin/env bash
# tests/test_qa_run_tests.sh — Functional tests for _qa_run_tests (spec-46)
# Verifies that test commands are run via bash -c (not eval), output is
# captured/truncated, and exit codes are correctly propagated.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Extract _qa_run_tests from qa.sh
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

eval "$(extract_function _qa_run_tests "$PROJECT_DIR/lib/qa.sh")"

# ============================================================
# Test 1: Successful command returns exit_code 0
# ============================================================

result=$(_qa_run_tests "echo hello")
assert_json_valid "$result" "output is valid JSON"
assert_json_field "$result" '.exit_code' "0" "successful command has exit_code=0"
assert_contains "$(echo "$result" | jq -r '.output')" "hello" "output captured"

# ============================================================
# Test 2: Failing command returns non-zero exit_code
# ============================================================

result=$(_qa_run_tests "exit 1")
assert_json_field "$result" '.exit_code' "1" "failing command has exit_code=1"

# ============================================================
# Test 3: Syntax check of valid bash
# ============================================================

result=$(_qa_run_tests "bash -n $PROJECT_DIR/automaton.sh")
assert_json_field "$result" '.exit_code' "0" "bash -n automaton.sh passes"

# ============================================================
# Test 4: Uses bash -c, not eval (security fix)
# ============================================================

# Verify the function source uses bash -c
func_source=$(extract_function _qa_run_tests "$PROJECT_DIR/lib/qa.sh")
assert_contains "$func_source" 'bash -c' "_qa_run_tests uses bash -c"
assert_not_contains "$func_source" 'eval ' "_qa_run_tests does not use eval"

# ============================================================
# Test 5: Output truncation at 100 lines
# ============================================================

result=$(_qa_run_tests "seq 1 200")
output_lines=$(echo "$result" | jq -r '.output' | wc -l)
if [ "$output_lines" -le 101 ]; then
    echo "PASS: output truncated to ~100 lines (got $output_lines)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: output should be truncated to ~100 lines (got $output_lines)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# Test 6: Default test command is bash -n automaton.sh
# ============================================================

func_source=$(extract_function _qa_run_tests "$PROJECT_DIR/lib/qa.sh")
assert_contains "$func_source" 'bash -n automaton.sh' "default test command is bash -n"

# ============================================================
# Test 7: Command with special characters doesn't inject
# ============================================================

result=$(_qa_run_tests 'echo "safe; echo injected"')
output=$(echo "$result" | jq -r '.output')
assert_contains "$output" "safe; echo injected" "special chars passed as literal string"

test_summary
