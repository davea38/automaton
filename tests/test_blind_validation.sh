#!/usr/bin/env bash
# tests/test_blind_validation.sh — Tests for spec-54 blind validation pattern
# Verifies that run_blind_validation() extracts criteria, assembles prompt,
# writes output, handles config, and truncates large diffs.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_blind_validation_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# Extract run_blind_validation and dependencies from automaton.sh
_extract_function() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
PROJECT_ROOT="$TEST_PROJECT_ROOT"
FLAG_BLIND_VALIDATION="true"
BLIND_VALIDATION_MAX_DIFF_LINES=500
# Stub claude CLI to capture prompt and return a verdict
claude() {
    # Save prompt input for inspection
    cat > "$TEST_AUTOMATON_DIR/_claude_input.txt"
    cat "$TEST_AUTOMATON_DIR/_mock_response.txt" 2>/dev/null || echo "VERDICT: PASS
CRITERIA_MET: [all criteria met]
CRITERIA_MISSED: []
ISSUES: []"
}
export -f claude
HARNESS
    sed -n '/^run_blind_validation()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
}
_extract_function

# Helper to set up project structure
_setup_project() {
    local project_dir
    project_dir=$(mktemp -d "$test_dir/project_XXXXXX")
    mkdir -p "$project_dir/specs" "$project_dir/.automaton"

    # Create a spec file with acceptance criteria
    cat > "$project_dir/specs/spec-99-test.md" <<'SPEC'
# Spec 99: Test Feature

## Requirements

### 1. Must do X
The system must do X.

## Acceptance Criteria

- [ ] Feature X is implemented
- [ ] Feature Y handles edge cases
- [ ] Tests pass at 100%
SPEC

    # Create test results file
    echo "All 5 tests passed. 0 failures." > "$project_dir/.automaton/test-results.log"

    echo "$project_dir"
}

# --- Test 1: run_blind_validation produces output file ---
project_dir=$(_setup_project)
# Set up mock response
cat > "$project_dir/.automaton/_mock_response.txt" <<'MOCK'
VERDICT: PASS
CRITERIA_MET: [Feature X is implemented, Feature Y handles edge cases, Tests pass at 100%]
CRITERIA_MISSED: []
ISSUES: []
MOCK

# Initialize a git repo so git diff works
(cd "$project_dir" && git init -q && git add -A && git commit -q -m "init" && echo "change" >> specs/spec-99-test.md && git add -A)

result=$(bash -c "
    export TEST_AUTOMATON_DIR='$project_dir/.automaton'
    export TEST_PROJECT_ROOT='$project_dir'
    cd '$project_dir'
    source '$test_dir/harness.sh'
    run_blind_validation 'specs/spec-99-test.md'
    echo \$?
")
exit_code=$(echo "$result" | tail -1)
assert_equals "0" "$exit_code" "run_blind_validation exits 0 on PASS verdict"
assert_file_exists "$project_dir/.automaton/blind-validation.md" "blind-validation.md is created"

# --- Test 2: Output contains VERDICT and timestamp ---
content=$(cat "$project_dir/.automaton/blind-validation.md")
assert_contains "$content" "VERDICT: PASS" "output contains VERDICT line"
assert_contains "$content" "Spec:" "output contains spec reference"

# --- Test 3: Prompt contains only spec criteria, test results, and diff ---
prompt_input=$(cat "$project_dir/.automaton/_claude_input.txt")
assert_contains "$prompt_input" "Feature X is implemented" "prompt contains acceptance criteria"
assert_contains "$prompt_input" "All 5 tests passed" "prompt contains test results"
assert_contains "$prompt_input" "change" "prompt contains git diff"

# --- Test 4: Prompt does NOT contain excluded context ---
# The prompt should not reference implementation plan or commit messages
if echo "$prompt_input" | grep -qi "IMPLEMENTATION_PLAN"; then
    echo "FAIL: prompt contains IMPLEMENTATION_PLAN (should be excluded)" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: prompt does not contain IMPLEMENTATION_PLAN"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 5: FAIL verdict returns non-zero ---
project_dir2=$(_setup_project)
cat > "$project_dir2/.automaton/_mock_response.txt" <<'MOCK'
VERDICT: FAIL
CRITERIA_MET: [Feature X is implemented]
CRITERIA_MISSED: [Feature Y handles edge cases - not implemented, Tests pass at 100% - only 80%]
ISSUES: [Missing error handling for edge case Z]
MOCK
(cd "$project_dir2" && git init -q && git add -A && git commit -q -m "init" && echo "change" >> specs/spec-99-test.md && git add -A)

result=$(bash -c "
    export TEST_AUTOMATON_DIR='$project_dir2/.automaton'
    export TEST_PROJECT_ROOT='$project_dir2'
    cd '$project_dir2'
    source '$test_dir/harness.sh'
    run_blind_validation 'specs/spec-99-test.md'
    echo \$?
")
exit_code=$(echo "$result" | tail -1)
assert_equals "1" "$exit_code" "run_blind_validation exits 1 on FAIL verdict"
content2=$(cat "$project_dir2/.automaton/blind-validation.md")
assert_contains "$content2" "VERDICT: FAIL" "FAIL verdict is written to output"
assert_contains "$content2" "CRITERIA_MISSED" "output contains missed criteria"

# --- Test 6: Skipped when FLAG_BLIND_VALIDATION is false ---
project_dir3=$(_setup_project)
(cd "$project_dir3" && git init -q && git add -A && git commit -q -m "init" && echo "change" >> specs/spec-99-test.md && git add -A)

result=$(bash -c "
    export TEST_AUTOMATON_DIR='$project_dir3/.automaton'
    export TEST_PROJECT_ROOT='$project_dir3'
    cd '$project_dir3'
    source '$test_dir/harness.sh'
    FLAG_BLIND_VALIDATION='false'
    run_blind_validation 'specs/spec-99-test.md'
    echo \$?
")
exit_code=$(echo "$result" | tail -1)
assert_equals "0" "$exit_code" "exits 0 when blind validation is disabled"
if [ -f "$project_dir3/.automaton/blind-validation.md" ]; then
    echo "FAIL: blind-validation.md should not exist when disabled" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: no blind-validation.md when disabled"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 7: Diff truncation for large diffs ---
project_dir4=$(_setup_project)
cat > "$project_dir4/.automaton/_mock_response.txt" <<'MOCK'
VERDICT: PASS
CRITERIA_MET: [all]
CRITERIA_MISSED: []
ISSUES: []
MOCK
(cd "$project_dir4" && git init -q && git add -A && git commit -q -m "init")
# Generate a large diff (600+ lines)
for i in $(seq 1 700); do echo "line $i of large change" >> "$project_dir4/bigfile.txt"; done
(cd "$project_dir4" && git add -A)

result=$(bash -c "
    export TEST_AUTOMATON_DIR='$project_dir4/.automaton'
    export TEST_PROJECT_ROOT='$project_dir4'
    cd '$project_dir4'
    source '$test_dir/harness.sh'
    BLIND_VALIDATION_MAX_DIFF_LINES=100
    run_blind_validation 'specs/spec-99-test.md'
    echo \$?
")
prompt_input4=$(cat "$project_dir4/.automaton/_claude_input.txt")
# The diff in the prompt should contain a truncation note
assert_contains "$prompt_input4" "truncated" "large diff is truncated in prompt"

# --- Test 8: Missing test results handled gracefully ---
project_dir5=$(_setup_project)
rm -f "$project_dir5/.automaton/test-results.log"
cat > "$project_dir5/.automaton/_mock_response.txt" <<'MOCK'
VERDICT: PASS
CRITERIA_MET: [all]
CRITERIA_MISSED: []
ISSUES: []
MOCK
(cd "$project_dir5" && git init -q && git add -A && git commit -q -m "init" && echo "change" >> specs/spec-99-test.md && git add -A)

result=$(bash -c "
    export TEST_AUTOMATON_DIR='$project_dir5/.automaton'
    export TEST_PROJECT_ROOT='$project_dir5'
    cd '$project_dir5'
    source '$test_dir/harness.sh'
    run_blind_validation 'specs/spec-99-test.md'
    echo \$?
")
exit_code=$(echo "$result" | tail -1)
assert_equals "0" "$exit_code" "handles missing test results gracefully"
prompt_input5=$(cat "$project_dir5/.automaton/_claude_input.txt")
assert_contains "$prompt_input5" "No test results" "notes missing test results in prompt"

# --- Test 9: Spec without Acceptance Criteria falls back to Requirements ---
project_dir6=$(_setup_project)
cat > "$project_dir6/specs/spec-99-test.md" <<'SPEC'
# Spec 99: Test Feature

## Requirements

### 1. Must do X
The system must do X.

### 2. Must handle Y
The system must handle Y edge cases.
SPEC
cat > "$project_dir6/.automaton/_mock_response.txt" <<'MOCK'
VERDICT: PASS
CRITERIA_MET: [all]
CRITERIA_MISSED: []
ISSUES: []
MOCK
(cd "$project_dir6" && git init -q && git add -A && git commit -q -m "init" && echo "change" >> specs/spec-99-test.md && git add -A)

result=$(bash -c "
    export TEST_AUTOMATON_DIR='$project_dir6/.automaton'
    export TEST_PROJECT_ROOT='$project_dir6'
    cd '$project_dir6'
    source '$test_dir/harness.sh'
    run_blind_validation 'specs/spec-99-test.md'
    echo \$?
")
prompt_input6=$(cat "$project_dir6/.automaton/_claude_input.txt")
assert_contains "$prompt_input6" "Must do X" "falls back to Requirements section"

test_summary
