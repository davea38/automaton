#!/usr/bin/env bash
# tests/test_qa_classify.sh — Tests for spec-46.2 QA failure classification
# Verifies _qa_classify_failure() assigns types and _qa_write_iteration()
# writes structured iteration JSON with persistence tracking.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_classify_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Extract functions from automaton.sh ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
HARNESS
    for fn in _qa_classify_failure _qa_write_iteration _qa_mark_persistent; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 1: _qa_classify_failure function exists ---
grep -q '^_qa_classify_failure() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_classify_failure function exists in automaton.sh"

# --- Test 2: _qa_write_iteration function exists ---
grep -q '^_qa_write_iteration() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_write_iteration function exists in automaton.sh"

# --- Test 3: _qa_classify_failure assigns test_failure type ---
output=$(TEST_AUTOMATON_DIR="$test_dir" \
    bash -c "source '$test_dir/harness.sh'; _qa_classify_failure 'test_budget_pacing' 'assertion error on line 42' 'tests/test_budget.sh:42' 'spec-07' 'test_failure'" 2>/dev/null) || true
type_val=$(echo "$output" | jq -r '.type' 2>/dev/null)
assert_equals "test_failure" "$type_val" "_qa_classify_failure assigns test_failure type"

# --- Test 4: _qa_classify_failure assigns spec_gap type ---
output=$(TEST_AUTOMATON_DIR="$test_dir" \
    bash -c "source '$test_dir/harness.sh'; _qa_classify_failure 'missing_budget_check' 'acceptance criterion not met' 'automaton.sh' 'spec-07' 'spec_gap'" 2>/dev/null) || true
type_val=$(echo "$output" | jq -r '.type' 2>/dev/null)
assert_equals "spec_gap" "$type_val" "_qa_classify_failure assigns spec_gap type"

# --- Test 5: _qa_classify_failure assigns regression type ---
output=$(TEST_AUTOMATON_DIR="$test_dir" \
    bash -c "source '$test_dir/harness.sh'; _qa_classify_failure 'test_config_load' 'previously passing test now fails' 'tests/test_config.sh:10' 'spec-12' 'regression'" 2>/dev/null) || true
type_val=$(echo "$output" | jq -r '.type' 2>/dev/null)
assert_equals "regression" "$type_val" "_qa_classify_failure assigns regression type"

# --- Test 6: _qa_classify_failure assigns style_issue type ---
output=$(TEST_AUTOMATON_DIR="$test_dir" \
    bash -c "source '$test_dir/harness.sh'; _qa_classify_failure 'lint_trailing_space' 'trailing whitespace' 'automaton.sh:100' '' 'style_issue'" 2>/dev/null) || true
type_val=$(echo "$output" | jq -r '.type' 2>/dev/null)
assert_equals "style_issue" "$type_val" "_qa_classify_failure assigns style_issue type"

# --- Test 7: _qa_classify_failure output has required fields ---
output=$(TEST_AUTOMATON_DIR="$test_dir" \
    bash -c "source '$test_dir/harness.sh'; _qa_classify_failure 'test_x' 'desc' 'file:1' 'spec-01' 'test_failure'" 2>/dev/null) || true
if echo "$output" | jq -e '.id and .type and .description and .source' >/dev/null 2>&1; then
    assert_exit_code 0 0 "_qa_classify_failure output has id, type, description, source"
else
    assert_exit_code 0 1 "_qa_classify_failure output has id, type, description, source"
fi

# --- Test 8: _qa_write_iteration writes iteration JSON file ---
mkdir -p "$test_dir/project/.automaton/qa"
TEST_AUTOMATON_DIR="$test_dir/project/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_write_iteration 1 '[]' 5 0 'PASS'" 2>/dev/null || true
if [ -f "$test_dir/project/.automaton/qa/iteration-1.json" ]; then
    assert_exit_code 0 0 "_qa_write_iteration creates iteration-1.json"
else
    assert_exit_code 0 1 "_qa_write_iteration creates iteration-1.json"
fi

# --- Test 9: Iteration JSON has correct structure ---
if [ -f "$test_dir/project/.automaton/qa/iteration-1.json" ]; then
    iter_json="$test_dir/project/.automaton/qa/iteration-1.json"
    has_fields=$(jq -e '.iteration and .timestamp and .failures != null and .passed != null and .failed != null and .verdict' "$iter_json" 2>/dev/null)
    if [ $? -eq 0 ]; then
        assert_exit_code 0 0 "iteration JSON has all required fields"
    else
        assert_exit_code 0 1 "iteration JSON has all required fields"
    fi
else
    assert_exit_code 0 1 "iteration JSON has all required fields (file missing)"
fi

# --- Test 10: _qa_mark_persistent flags repeated failures ---
grep -q '^_qa_mark_persistent() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_mark_persistent function exists in automaton.sh"

# --- Test 11: Persistence tracking marks failures seen in previous iteration ---
# Create a previous iteration file with a known failure
mkdir -p "$test_dir/project2/.automaton/qa"
cat > "$test_dir/project2/.automaton/qa/iteration-1.json" <<'JSON'
{
  "iteration": 1,
  "timestamp": "2026-03-03T12:00:00Z",
  "failures": [{"id": "test_budget", "type": "test_failure", "persistent": false, "first_seen": 1}],
  "passed": 4,
  "failed": 1,
  "verdict": "FAIL"
}
JSON
# Mark persistent for iteration 2 with same failure
output=$(TEST_AUTOMATON_DIR="$test_dir/project2/.automaton" \
    bash -c "source '$test_dir/harness.sh'; _qa_mark_persistent '[{\"id\":\"test_budget\",\"type\":\"test_failure\",\"persistent\":false,\"first_seen\":2}]' 1" 2>/dev/null) || true
persistent_val=$(echo "$output" | jq -r '.[0].persistent' 2>/dev/null)
assert_equals "true" "$persistent_val" "_qa_mark_persistent flags repeated failures"

# --- Test 12: Persistence tracking preserves first_seen from earlier iteration ---
first_seen_val=$(echo "$output" | jq -r '.[0].first_seen' 2>/dev/null)
assert_equals "1" "$first_seen_val" "_qa_mark_persistent preserves original first_seen"

test_summary
