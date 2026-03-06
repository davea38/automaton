#!/usr/bin/env bash
# tests/test_lifecycle_checkpoint.sh — Tests for self_build_checkpoint JSON safety
cd "$(dirname "$0")/.." || exit 1
source tests/test_helpers.sh
setup_test_dir

# Minimal stubs for lifecycle.sh dependencies
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"
SELF_BUILD_ENABLED="true"
log() { :; }
write_state() { :; }

source lib/lifecycle.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# self_build_checkpoint: JSON construction safety
# ---------------------------------------------------------------------------

echo "=== checkpoint: builds valid JSON from simple filenames ==="
SELF_BUILD_FILES="file1.sh file2.sh"
mkdir -p "$TEST_DIR"
echo "content1" > "$TEST_DIR/file1.sh"
echo "content2" > "$TEST_DIR/file2.sh"
# Override to use test files
cd "$TEST_DIR"
SELF_BUILD_FILES="file1.sh file2.sh"
self_build_checkpoint 2>/dev/null
if [ -f "$AUTOMATON_DIR/self_checksums.json" ]; then
    result=$(cat "$AUTOMATON_DIR/self_checksums.json")
    assert_json_valid "$result" "Checkpoint produces valid JSON"
    # Check both files are present
    key_count=$(echo "$result" | jq 'keys | length')
    assert_equals "2" "$key_count" "Both files have checksum entries"
else
    echo "FAIL: self_checksums.json not created" >&2
    ((_TEST_FAIL_COUNT++))
fi

echo "=== checkpoint: handles filenames with special characters ==="
mkdir -p "$TEST_DIR/sub dir"
echo "special" > "$TEST_DIR/sub dir/my-file.sh"
SELF_BUILD_FILES="sub dir/my-file.sh"
self_build_checkpoint 2>/dev/null
if [ -f "$AUTOMATON_DIR/self_checksums.json" ]; then
    result=$(cat "$AUTOMATON_DIR/self_checksums.json")
    assert_json_valid "$result" "JSON valid with special filename"
fi

echo "=== checkpoint: handles missing files gracefully ==="
SELF_BUILD_FILES="nonexistent.sh"
self_build_checkpoint 2>/dev/null
if [ -f "$AUTOMATON_DIR/self_checksums.json" ]; then
    result=$(cat "$AUTOMATON_DIR/self_checksums.json")
    assert_json_valid "$result" "JSON valid when file missing"
    key_count=$(echo "$result" | jq 'keys | length')
    assert_equals "0" "$key_count" "No entries for missing files"
fi

echo "=== checkpoint: checksum is sha256 ==="
echo "test content" > "$TEST_DIR/hashtest.sh"
SELF_BUILD_FILES="hashtest.sh"
self_build_checkpoint 2>/dev/null
if [ -f "$AUTOMATON_DIR/self_checksums.json" ]; then
    result=$(cat "$AUTOMATON_DIR/self_checksums.json")
    hash_val=$(echo "$result" | jq -r '."hashtest.sh"')
    expected_hash=$(sha256sum "$TEST_DIR/hashtest.sh" | awk '{print $1}')
    assert_equals "$expected_hash" "$hash_val" "Checksum matches sha256sum"
fi

cd - > /dev/null
test_summary
