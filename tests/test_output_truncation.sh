#!/usr/bin/env bash
# tests/test_output_truncation.sh — Tests for spec-49 output truncation (head/tail)
# Verifies that truncate_output() applies head+tail truncation with a marker,
# archives full output, and handles edge cases correctly.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_output_truncation_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# Extract truncate_output and dependencies from automaton.sh
_extract_function() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
OUTPUT_MAX_LINES=200
OUTPUT_HEAD_LINES=50
OUTPUT_TAIL_LINES=150
HARNESS
    sed -n '/^truncate_output()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
}
_extract_function

# --- Test 1: Output below threshold passes through unmodified ---
seq 1 100 > "$test_dir/short_output.txt"
result=$(bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/short_output.txt'
")
expected=$(seq 1 100)
assert_equals "$expected" "$result" "output below threshold passes through unmodified"

# --- Test 2: Output above threshold is truncated with head+tail ---
seq 1 500 > "$test_dir/long_output.txt"
result=$(bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/long_output.txt'
")
# Should contain first 50 lines (1-50)
assert_contains "$result" "1" "head section starts with line 1"
assert_contains "$result" "50" "head section contains line 50"
# Should contain truncation marker
assert_contains "$result" "lines truncated" "truncation marker present"
assert_contains "$result" "300 lines truncated" "correct truncated count (500 - 50 - 150 = 300)"
# Should contain last 150 lines (351-500)
assert_contains "$result" "500" "tail section contains last line"
assert_contains "$result" "351" "tail section starts at correct line"

# --- Test 3: Output exactly at threshold is NOT truncated ---
seq 1 200 > "$test_dir/exact_output.txt"
result=$(bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/exact_output.txt'
")
line_count=$(echo "$result" | wc -l)
assert_equals "200" "$line_count" "output exactly at threshold passes through (200 lines)"

# --- Test 4: Empty output passes through as-is ---
> "$test_dir/empty_output.txt"
result=$(bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/empty_output.txt'
")
assert_equals "" "$result" "empty output passes through as empty"

# --- Test 5: Full output is archived to .automaton/logs/ ---
seq 1 500 > "$test_dir/archive_test.txt"
bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/archive_test.txt' build 3
" > /dev/null
# Check that an archive file was created
archive_count=$(ls "$test_dir/.automaton/logs"/output_build_3_*.log 2>/dev/null | wc -l)
if [ "$archive_count" -ge 1 ]; then
    echo "PASS: archive file created in .automaton/logs/"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: no archive file found in .automaton/logs/" >&2
    ((_TEST_FAIL_COUNT++))
fi
# Verify archived content is untruncated
archive_file=$(ls "$test_dir/.automaton/logs"/output_build_3_*.log 2>/dev/null | head -1)
if [ -n "$archive_file" ]; then
    archive_lines=$(wc -l < "$archive_file")
    assert_equals "500" "$archive_lines" "archive contains full untruncated output"
fi

# --- Test 6: Truncation marker shows correct count ---
seq 1 1000 > "$test_dir/large_output.txt"
result=$(bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/large_output.txt'
")
# 1000 - 50 - 150 = 800 truncated lines
assert_contains "$result" "800 lines truncated" "marker shows correct count for 1000-line output"

# --- Test 7: Custom config values work ---
seq 1 100 > "$test_dir/custom_config.txt"
result=$(bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    OUTPUT_MAX_LINES=50
    OUTPUT_HEAD_LINES=10
    OUTPUT_TAIL_LINES=40
    truncate_output '$test_dir/custom_config.txt'
")
# 100 lines with max=50: should truncate, keeping 10+40=50
assert_contains "$result" "50 lines truncated" "custom config: correct truncated count (100-10-40=50)"

# --- Test 8: No archive when output is below threshold ---
seq 1 50 > "$test_dir/short_noarchive.txt"
rm -f "$test_dir/.automaton/logs"/output_test_1_*.log
bash -c "
    export TEST_AUTOMATON_DIR='$test_dir/.automaton'
    mkdir -p '$test_dir/.automaton/logs'
    source '$test_dir/harness.sh'
    truncate_output '$test_dir/short_noarchive.txt' test 1
" > /dev/null
short_archive=$(ls "$test_dir/.automaton/logs"/output_test_1_*.log 2>/dev/null | wc -l)
assert_equals "0" "$short_archive" "no archive created for output below threshold"

test_summary
