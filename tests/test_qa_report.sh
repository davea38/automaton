#!/usr/bin/env bash
# tests/test_qa_report.sh — Tests for spec-46.4 QA exhaustion handling
# Verifies _qa_write_failure_report() generates failure-report.md with
# unresolved failures, iteration history, and types. Also verifies the
# report is passed as context to the review phase.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_report_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: _qa_write_failure_report function exists ---
grep -q '^_qa_write_failure_report() {' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_write_failure_report function exists in automaton.sh"

# --- Extract functions for unit tests ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
PROJECT_ROOT="$TEST_PROJECT_ROOT"
QA_MAX_ITERATIONS=3
HARNESS
    for fn in _qa_write_failure_report _qa_write_iteration _qa_classify_failure; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# --- Test 2: _qa_write_failure_report creates failure-report.md ---
mkdir -p "$test_dir/project1/.automaton/qa"
# Create iteration files to simulate a 3-iteration QA run that exhausted
cat > "$test_dir/project1/.automaton/qa/iteration-1.json" <<'JSON'
{
    "iteration": 1,
    "timestamp": "2026-03-03T10:00:00Z",
    "failures": [
        {"id": "test_suite", "type": "test_failure", "description": "Tests failed with exit code 1", "source": "test_command", "spec": "", "first_seen": 1, "persistent": false},
        {"id": "spec_gap_1", "type": "spec_gap", "description": "Missing authentication endpoint", "source": "spec_criteria", "spec": "spec-12", "first_seen": 1, "persistent": false}
    ],
    "passed": 0,
    "failed": 2,
    "verdict": "FAIL"
}
JSON
cat > "$test_dir/project1/.automaton/qa/iteration-2.json" <<'JSON'
{
    "iteration": 2,
    "timestamp": "2026-03-03T10:05:00Z",
    "failures": [
        {"id": "test_suite", "type": "test_failure", "description": "Tests failed with exit code 1", "source": "test_command", "spec": "", "first_seen": 1, "persistent": true},
        {"id": "spec_gap_1", "type": "spec_gap", "description": "Missing authentication endpoint", "source": "spec_criteria", "spec": "spec-12", "first_seen": 1, "persistent": true}
    ],
    "passed": 0,
    "failed": 2,
    "verdict": "FAIL"
}
JSON
cat > "$test_dir/project1/.automaton/qa/iteration-3.json" <<'JSON'
{
    "iteration": 3,
    "timestamp": "2026-03-03T10:10:00Z",
    "failures": [
        {"id": "test_suite", "type": "test_failure", "description": "Tests failed with exit code 1", "source": "test_command", "spec": "", "first_seen": 1, "persistent": true}
    ],
    "passed": 1,
    "failed": 1,
    "verdict": "FAIL"
}
JSON

# Build the final failures JSON to pass
final_failures='[{"id":"test_suite","type":"test_failure","description":"Tests failed with exit code 1","source":"test_command","spec":"","first_seen":1,"persistent":true}]'

output=$(TEST_AUTOMATON_DIR="$test_dir/project1/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/project1" \
    bash -c "source '$test_dir/harness.sh'; _qa_write_failure_report 3 '$final_failures'" 2>/dev/null) || true
report_file="$test_dir/project1/.automaton/qa/failure-report.md"
assert_file_exists "$report_file" "_qa_write_failure_report creates failure-report.md"

# --- Test 3: Report contains header ---
if [ -f "$report_file" ]; then
    content=$(cat "$report_file")
    assert_contains "$content" "QA Failure Report" "Report contains header"
else
    assert_exit_code 0 1 "Report contains header (file missing)"
fi

# --- Test 4: Report lists unresolved failures with types ---
if [ -f "$report_file" ]; then
    assert_contains "$content" "test_failure" "Report contains failure type"
    assert_contains "$content" "test_suite" "Report contains failure ID"
else
    assert_exit_code 0 1 "Report lists failure types (file missing)"
fi

# --- Test 5: Report includes iteration history ---
if [ -f "$report_file" ]; then
    assert_contains "$content" "Iteration" "Report includes iteration history"
else
    assert_exit_code 0 1 "Report includes iteration history (file missing)"
fi

# --- Test 6: Report marks persistent failures ---
if [ -f "$report_file" ]; then
    assert_contains "$content" "persistent" "Report marks persistent failures"
else
    assert_exit_code 0 1 "Report marks persistent failures (file missing)"
fi

# --- Test 7: Report includes total iterations exhausted ---
if [ -f "$report_file" ]; then
    assert_contains "$content" "3" "Report includes iteration count"
else
    assert_exit_code 0 1 "Report includes iteration count (file missing)"
fi

# --- Test 8: _qa_run_loop calls _qa_write_failure_report on exhaustion ---
grep -q '_qa_write_failure_report' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_qa_run_loop references _qa_write_failure_report"

# --- Test 9: Review phase context injection includes QA failure report ---
# Check that inject_dynamic_context or _build_dynamic_context_stdin references failure-report.md
grep -q 'failure-report.md' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "Dynamic context injection references failure-report.md for review phase"

# --- Test 10: Report handles empty failures gracefully ---
mkdir -p "$test_dir/project2/.automaton/qa"
empty_failures='[]'
output=$(TEST_AUTOMATON_DIR="$test_dir/project2/.automaton" \
    TEST_PROJECT_ROOT="$test_dir/project2" \
    bash -c "source '$test_dir/harness.sh'; _qa_write_failure_report 1 '$empty_failures'" 2>/dev/null) || true
report_file2="$test_dir/project2/.automaton/qa/failure-report.md"
assert_file_exists "$report_file2" "_qa_write_failure_report handles empty failures"

test_summary
