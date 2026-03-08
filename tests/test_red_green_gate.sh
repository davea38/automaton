#!/usr/bin/env bash
# tests/test_red_green_gate.sh — Tests for red-before-green gate (audit wave 3)
# Verifies that the orchestrator records pre-build test failures and checks
# that the failure count decreases after build.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

setup_test_dir

# --- Helper: create a minimal .automaton dir for state ---
setup_automaton_dir() {
    rm -rf "$TEST_DIR/.automaton"
    mkdir -p "$TEST_DIR/.automaton"
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
}

# --- Source the qa.sh module for testing ---
# We need log() and emit_event() stubs, and the config variable
log() { :; }
emit_event() { :; }
RED_GREEN_GATE_ENABLED="true"

source "$_PROJECT_DIR/lib/qa.sh"

# ============================================================
# Test 1: red_green_record_baseline creates the baseline file
# ============================================================
setup_automaton_dir
# Create a fake test runner that exits with code 1 and outputs 5 failures
cat > "$TEST_DIR/run_tests.sh" <<'RUNNER'
#!/usr/bin/env bash
echo "Failed:  5"
echo "Passed:  10"
exit 1
RUNNER
chmod +x "$TEST_DIR/run_tests.sh"

red_green_record_baseline "$TEST_DIR/run_tests.sh"
assert_file_exists "$AUTOMATON_DIR/red_green_baseline.json" "baseline file created"

baseline_count=$(jq -r '.failure_count' "$AUTOMATON_DIR/red_green_baseline.json")
assert_equals "5" "$baseline_count" "baseline records 5 failures"

# ============================================================
# Test 2: red_green_record_baseline with 0 failures
# ============================================================
setup_automaton_dir
cat > "$TEST_DIR/run_tests_pass.sh" <<'RUNNER'
#!/usr/bin/env bash
echo "Failed:  0"
echo "Passed:  15"
exit 0
RUNNER
chmod +x "$TEST_DIR/run_tests_pass.sh"

red_green_record_baseline "$TEST_DIR/run_tests_pass.sh"
baseline_count=$(jq -r '.failure_count' "$AUTOMATON_DIR/red_green_baseline.json")
assert_equals "0" "$baseline_count" "baseline records 0 when all pass"

# ============================================================
# Test 3: red_green_check_progress passes when failures decrease
# ============================================================
setup_automaton_dir
# Set baseline to 5 failures
echo '{"failure_count":5,"recorded_at":"2026-01-01T00:00:00Z"}' > "$AUTOMATON_DIR/red_green_baseline.json"

cat > "$TEST_DIR/run_tests_improved.sh" <<'RUNNER'
#!/usr/bin/env bash
echo "Failed:  2"
echo "Passed:  13"
exit 1
RUNNER
chmod +x "$TEST_DIR/run_tests_improved.sh"

rc=0
red_green_check_progress "$TEST_DIR/run_tests_improved.sh" || rc=$?
assert_equals "0" "$rc" "progress check passes when failures decrease (5 -> 2)"

# ============================================================
# Test 4: red_green_check_progress fails when failures increase
# ============================================================
setup_automaton_dir
echo '{"failure_count":2,"recorded_at":"2026-01-01T00:00:00Z"}' > "$AUTOMATON_DIR/red_green_baseline.json"

cat > "$TEST_DIR/run_tests_regressed.sh" <<'RUNNER'
#!/usr/bin/env bash
echo "Failed:  5"
echo "Passed:  10"
exit 1
RUNNER
chmod +x "$TEST_DIR/run_tests_regressed.sh"

rc=0
red_green_check_progress "$TEST_DIR/run_tests_regressed.sh" || rc=$?
assert_equals "1" "$rc" "progress check fails when failures increase (2 -> 5)"

# ============================================================
# Test 5: red_green_check_progress passes when no baseline exists
# ============================================================
setup_automaton_dir
# No baseline file — should pass (no gate to enforce)
rc=0
red_green_check_progress "$TEST_DIR/run_tests_improved.sh" || rc=$?
assert_equals "0" "$rc" "progress check passes when no baseline exists"

# ============================================================
# Test 6: red_green_check_progress passes when failures stay same
# ============================================================
setup_automaton_dir
echo '{"failure_count":3,"recorded_at":"2026-01-01T00:00:00Z"}' > "$AUTOMATON_DIR/red_green_baseline.json"

cat > "$TEST_DIR/run_tests_same.sh" <<'RUNNER'
#!/usr/bin/env bash
echo "Failed:  3"
echo "Passed:  12"
exit 1
RUNNER
chmod +x "$TEST_DIR/run_tests_same.sh"

rc=0
red_green_check_progress "$TEST_DIR/run_tests_same.sh" || rc=$?
assert_equals "0" "$rc" "progress check passes when failures unchanged (not a regression)"

# ============================================================
# Test 7: gate disabled — record and check are no-ops
# ============================================================
RED_GREEN_GATE_ENABLED="false"
setup_automaton_dir

red_green_record_baseline "$TEST_DIR/run_tests.sh"
assert_equals "false" "$([ -f "$AUTOMATON_DIR/red_green_baseline.json" ] && echo true || echo false)" "baseline not created when gate disabled"

rc=0
red_green_check_progress "$TEST_DIR/run_tests_regressed.sh" || rc=$?
assert_equals "0" "$rc" "progress check is no-op when gate disabled"

RED_GREEN_GATE_ENABLED="true"

# ============================================================
# Test 8: _count_test_failures parses run_tests.sh output
# ============================================================
output="$(cat <<'EOF'
========================================
Test Results
========================================
Passed:  10
Failed:  3
Total:   13
========================================
EOF
)"
count=$(_count_test_failures_from_output "$output")
assert_equals "3" "$count" "parses failure count from run_tests.sh output"

# ============================================================
test_summary
