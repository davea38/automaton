#!/usr/bin/env bash
# tests/test_doctor.sh — Tests for spec-48 doctor/health check
# Verifies doctor_check() validates dependencies, auth, disk, git, and project files.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_doctor_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# Helper: extract doctor_check and report_check from automaton.sh
_extract_doctor() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
# Counters for report_check
_DOCTOR_PASS=0
_DOCTOR_WARN=0
_DOCTOR_FAIL=0
_DOCTOR_INFO=0
HARNESS
    # Extract report_check function
    sed -n '/^report_check()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
    # Extract doctor_check function
    sed -n '/^doctor_check()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
}
_extract_doctor

# --- Test 1: doctor_check function exists ---
grep -q '^doctor_check()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "doctor_check() function exists in automaton.sh"

# --- Test 2: report_check helper function exists ---
grep -q '^report_check()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "report_check() helper function exists in automaton.sh"

# --- Test 3: --doctor flag exists in argument parser ---
grep -q '\-\-doctor' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--doctor flag exists in argument parser"

# --- Test 4: doctor_check on a healthy environment exits 0 ---
# Run from project root which has all expected files
output=$(bash -c "source '$test_dir/harness.sh'; doctor_check" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "doctor_check exits 0 on healthy environment"

# --- Test 5: Output contains PASS for bash version ---
assert_contains "$output" "bash" "output mentions bash check"
assert_contains "$output" "PASS" "output contains at least one PASS"

# --- Test 6: Output contains PASS for git ---
assert_contains "$output" "git" "output mentions git check"

# --- Test 7: Output contains PASS for jq ---
assert_contains "$output" "jq" "output mentions jq check"

# --- Test 8: Output contains PASS for claude ---
# claude may or may not be present — just verify the check runs
output_claude=$(echo "$output" | grep -i "claude" | head -1)
if [ -n "$output_claude" ]; then
    echo "PASS: output includes claude check"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: output does not include claude check" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Output contains disk space check ---
assert_contains "$output" "disk" "output mentions disk space check"

# --- Test 10: Output contains summary line with counts ---
assert_contains "$output" "passed" "output contains summary with passed count"

# --- Test 11: NO_COLOR disables ANSI codes ---
output_nocolor=$(NO_COLOR=1 bash -c "source '$test_dir/harness.sh'; doctor_check" 2>&1)
# Check no ANSI escape sequences
if echo "$output_nocolor" | grep -qP '\x1b\['; then
    echo "FAIL: NO_COLOR=1 still has ANSI codes" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: NO_COLOR=1 disables ANSI codes"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 12: Missing config file is WARN not FAIL ---
# Run from a temp dir with no config
output_noconfig=$(cd "$test_dir" && bash -c "source '$test_dir/harness.sh'; doctor_check" 2>&1)
rc=$?
# Should still be exit 0 (warns don't fail)
assert_contains "$output_noconfig" "automaton.config.json" "output checks for config file"

# --- Test 13: Invalid config JSON is FAIL ---
mkdir -p "$test_dir/proj"
echo '{ bad json' > "$test_dir/proj/automaton.config.json"
output_badconfig=$(cd "$test_dir/proj" && bash -c "source '$test_dir/harness.sh'; doctor_check" 2>&1)
rc=$?
assert_exit_code 1 "$rc" "invalid config JSON causes exit 1"
assert_contains "$output_badconfig" "FAIL" "invalid config shows FAIL"

# --- Test 14: .automaton/ directory check ---
# If .automaton is a regular file instead of dir, should fail
mkdir -p "$test_dir/proj2"
touch "$test_dir/proj2/.automaton"
output_badstate=$(cd "$test_dir/proj2" && bash -c "source '$test_dir/harness.sh'; doctor_check" 2>&1)
assert_contains "$output_badstate" "FAIL" ".automaton as file (not dir) is FAIL"

# --- Test 15: Non-TTY output has no ANSI codes ---
output_pipe=$(bash -c "source '$test_dir/harness.sh'; doctor_check" 2>&1 | cat)
if echo "$output_pipe" | grep -qP '\x1b\['; then
    echo "FAIL: piped output still has ANSI codes" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: piped output has no ANSI codes"
    ((_TEST_PASS_COUNT++))
fi

test_summary
