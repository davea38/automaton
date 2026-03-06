#!/usr/bin/env bash
# tests/test_atomic_write.sh — Tests for the atomic_write utility function
cd "$(dirname "$0")/.." || exit 1
source tests/test_helpers.sh
setup_test_dir

# Source only utilities.sh (it has no dependencies on other modules)
source lib/utilities.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# atomic_write: basic functionality
# ---------------------------------------------------------------------------

echo "=== atomic_write: basic write ==="
echo "hello world" | atomic_write "$TEST_DIR/basic.txt"
assert_equals "hello world" "$(cat "$TEST_DIR/basic.txt")" "atomic_write creates file with correct content"

echo "=== atomic_write: overwrite ==="
echo "first" | atomic_write "$TEST_DIR/overwrite.txt"
echo "second" | atomic_write "$TEST_DIR/overwrite.txt"
assert_equals "second" "$(cat "$TEST_DIR/overwrite.txt")" "atomic_write overwrites existing file"

echo "=== atomic_write: creates parent directories ==="
echo "nested" | atomic_write "$TEST_DIR/a/b/c/deep.txt"
assert_file_exists "$TEST_DIR/a/b/c/deep.txt" "atomic_write creates nested directories"
assert_equals "nested" "$(cat "$TEST_DIR/a/b/c/deep.txt")" "nested file has correct content"

echo "=== atomic_write: no temp file left behind ==="
echo "clean" | atomic_write "$TEST_DIR/clean.txt"
local_tmp_files=$(find "$TEST_DIR" -name '.tmp.*' 2>/dev/null | wc -l)
assert_equals "0" "$local_tmp_files" "No temp files left after successful write"

echo "=== atomic_write: multiline content ==="
printf "line1\nline2\nline3\n" | atomic_write "$TEST_DIR/multi.txt"
line_count=$(wc -l < "$TEST_DIR/multi.txt")
assert_equals "3" "$line_count" "Multiline content preserved"

echo "=== atomic_write: empty content ==="
echo -n "" | atomic_write "$TEST_DIR/empty.txt"
assert_file_exists "$TEST_DIR/empty.txt" "Empty file created"
assert_equals "0" "$(wc -c < "$TEST_DIR/empty.txt")" "Empty file has 0 bytes"

echo "=== atomic_write: JSON content ==="
echo '{"key":"value","num":42}' | atomic_write "$TEST_DIR/data.json"
result=$(jq -r '.key' "$TEST_DIR/data.json" 2>/dev/null)
assert_equals "value" "$result" "JSON content is valid and readable"

echo "=== atomic_write: binary-safe (special chars) ==="
printf 'tab\there\nnewline\nquote"end' | atomic_write "$TEST_DIR/special.txt"
assert_file_exists "$TEST_DIR/special.txt" "File with special chars created"
assert_contains "$(cat "$TEST_DIR/special.txt")" 'quote"end' "Special characters preserved"

echo "=== atomic_write: file with spaces in path ==="
echo "spaced" | atomic_write "$TEST_DIR/path with spaces/file.txt"
assert_equals "spaced" "$(cat "$TEST_DIR/path with spaces/file.txt")" "Handles spaces in path"

echo "=== atomic_write: preserves permissions of target dir ==="
mkdir -p "$TEST_DIR/perm_test"
echo "data" | atomic_write "$TEST_DIR/perm_test/out.txt"
assert_file_exists "$TEST_DIR/perm_test/out.txt" "File written in existing dir"

test_summary
