#!/usr/bin/env bash
# tests/test_review_confidence.sh — Tests for review confidence scoring
# Verifies parse_review_confidence() extracts scores from review output,
# gate_review_confidence() applies threshold logic, and results are persisted.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_review_confidence_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: parse_review_confidence function exists ---
grep -q '^parse_review_confidence() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "parse_review_confidence function exists"

# --- Test 2: gate_review_confidence function exists ---
grep -q '^gate_review_confidence() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "gate_review_confidence function exists"

# --- Extract functions for unit tests ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
emit_event() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
HARNESS
    for fn in parse_review_confidence gate_review_confidence; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 3: Parses all four confidence dimensions from review output ---
mkdir -p "$test_dir/t3/.automaton"
review_output='Some review text here.
<confidence>
spec_coverage: 5
test_quality: 4
code_quality: 4
regression_risk: 3
</confidence>
More text after.'

result=$(TEST_AUTOMATON_DIR="$test_dir/t3/.automaton" \
    bash -c "source '$test_dir/harness.sh'; parse_review_confidence '$review_output'")
rc=$?
assert_exit_code 0 "$rc" "parse_review_confidence succeeds with valid output"
assert_json_valid "$result" "parse_review_confidence returns valid JSON"
assert_json_field "$result" ".spec_coverage" "5" "spec_coverage parsed correctly"
assert_json_field "$result" ".test_quality" "4" "test_quality parsed correctly"
assert_json_field "$result" ".code_quality" "4" "code_quality parsed correctly"
assert_json_field "$result" ".regression_risk" "3" "regression_risk parsed correctly"

# --- Test 4: Returns error when confidence block is missing ---
result=$(TEST_AUTOMATON_DIR="$test_dir/t3/.automaton" \
    bash -c "source '$test_dir/harness.sh'; parse_review_confidence 'no confidence here'" 2>/dev/null)
rc=$?
assert_exit_code 1 "$rc" "parse_review_confidence fails when no confidence block"

# --- Test 5: gate_review_confidence passes when all scores >= 4 ---
mkdir -p "$test_dir/t5/.automaton"
scores='{"spec_coverage":4,"test_quality":5,"code_quality":4,"regression_risk":4}'
result=$(TEST_AUTOMATON_DIR="$test_dir/t5/.automaton" \
    bash -c "source '$test_dir/harness.sh'; gate_review_confidence '$scores'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "gate passes when all scores >= 4"

# --- Test 6: gate_review_confidence fails when any score < 3 ---
mkdir -p "$test_dir/t6/.automaton"
scores='{"spec_coverage":2,"test_quality":5,"code_quality":4,"regression_risk":4}'
result=$(TEST_AUTOMATON_DIR="$test_dir/t6/.automaton" \
    bash -c "source '$test_dir/harness.sh'; gate_review_confidence '$scores'" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "gate fails when any score < 3"

# --- Test 7: gate_review_confidence warns but passes when score is 3 ---
mkdir -p "$test_dir/t7/.automaton"
scores='{"spec_coverage":3,"test_quality":4,"code_quality":4,"regression_risk":3}'
result=$(TEST_AUTOMATON_DIR="$test_dir/t7/.automaton" \
    bash -c "source '$test_dir/harness.sh'; gate_review_confidence '$scores'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "gate passes when scores are 3 (borderline)"

# --- Test 8: Persists confidence scores to review-confidence.json ---
mkdir -p "$test_dir/t8/.automaton"
review_output='<confidence>
spec_coverage: 5
test_quality: 4
code_quality: 4
regression_risk: 5
</confidence>'
TEST_AUTOMATON_DIR="$test_dir/t8/.automaton" \
    bash -c "source '$test_dir/harness.sh'; parse_review_confidence '$review_output'" > /dev/null
assert_file_exists "$test_dir/t8/.automaton/review-confidence.json" "review-confidence.json created"
stored=$(cat "$test_dir/t8/.automaton/review-confidence.json")
assert_json_valid "$stored" "stored confidence is valid JSON"
assert_json_field "$stored" ".spec_coverage" "5" "stored spec_coverage correct"

# --- Test 9: Handles scores with extra whitespace ---
mkdir -p "$test_dir/t9/.automaton"
review_output='<confidence>
  spec_coverage:  3
  test_quality:   4
  code_quality:   5
  regression_risk:  4
</confidence>'
result=$(TEST_AUTOMATON_DIR="$test_dir/t9/.automaton" \
    bash -c "source '$test_dir/harness.sh'; parse_review_confidence '$review_output'")
rc=$?
assert_exit_code 0 "$rc" "handles extra whitespace"
assert_json_field "$result" ".spec_coverage" "3" "whitespace-padded score parsed"

# --- Test 10: Rejects scores outside 1-5 range ---
mkdir -p "$test_dir/t10/.automaton"
review_output='<confidence>
spec_coverage: 6
test_quality: 4
code_quality: 4
regression_risk: 0
</confidence>'
result=$(TEST_AUTOMATON_DIR="$test_dir/t10/.automaton" \
    bash -c "source '$test_dir/harness.sh'; parse_review_confidence '$review_output'" 2>/dev/null)
rc=$?
assert_exit_code 1 "$rc" "rejects scores outside 1-5 range"

test_summary
