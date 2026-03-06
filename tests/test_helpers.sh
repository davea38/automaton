#!/usr/bin/env bash
# tests/test_helpers.sh — minimal bash assertion functions for automaton tests
# Used when bats is not available. Source this file from test scripts.

_TEST_PASS_COUNT=0
_TEST_FAIL_COUNT=0

# Resolve the project root from the test directory
_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_DIR="$(cd "$_HELPERS_DIR/.." && pwd)"

# script_file: a combined temp file containing automaton.sh + all lib/*.sh
# modules. Tests use sed/grep on this file to extract function bodies.
_COMBINED_SOURCE=$(mktemp "${TMPDIR:-/tmp}/automaton-combined-XXXXXX.sh")
cat "$_PROJECT_DIR/automaton.sh" "$_PROJECT_DIR"/lib/*.sh > "$_COMBINED_SOURCE" 2>/dev/null || true
script_file="$_COMBINED_SOURCE"
# automaton_script: the real automaton.sh entry point (for execution tests)
automaton_script="$_PROJECT_DIR/automaton.sh"
_cleanup_combined() { rm -f "$_COMBINED_SOURCE"; }
trap '_cleanup_combined' EXIT

assert_equals() {
    local expected="$1" actual="$2" msg="${3:-assertion failed}"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $msg (expected '$expected', got '$actual')" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="${3:-exit code check}"
    if [ "$expected" -ne "$actual" ]; then
        echo "FAIL: $msg (expected exit $expected, got $actual)" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_file_exists() {
    local path="$1" msg="${2:-file exists check}"
    if [ ! -f "$path" ]; then
        echo "FAIL: $msg ($path does not exist)" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-contains check}"
    if ! echo "$haystack" | grep -qF -- "$needle"; then
        echo "FAIL: $msg (output does not contain '$needle')" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-not-contains check}"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "FAIL: $msg (output contains '$needle' but should not)" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_matches() {
    local haystack="$1" pattern="$2" msg="${3:-regex match check}"
    if ! echo "$haystack" | grep -qE -- "$pattern"; then
        echo "FAIL: $msg (output does not match pattern '$pattern')" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_json_valid() {
    local json="$1" msg="${2:-valid JSON check}"
    if ! echo "$json" | jq empty 2>/dev/null; then
        echo "FAIL: $msg (invalid JSON)" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

assert_json_field() {
    local json="$1" field="$2" expected="$3" msg="${4:-JSON field check}"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $msg (field $field: expected '$expected', got '$actual')" >&2
        ((_TEST_FAIL_COUNT++))
        return 1
    fi
    echo "PASS: $msg"
    ((_TEST_PASS_COUNT++))
}

# Create a temp directory for test isolation, cleaned up on exit
setup_test_dir() {
    TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-test-XXXXXX")
    _old_cleanup=$(trap -p EXIT | sed "s/^trap -- '//; s/' EXIT$//")
    trap "rm -rf '$TEST_DIR'; $_old_cleanup; _cleanup_combined" EXIT
}

test_summary() {
    local total=$((_TEST_PASS_COUNT + _TEST_FAIL_COUNT))
    echo ""
    echo "Results: $total tests, $_TEST_PASS_COUNT passed, $_TEST_FAIL_COUNT failed"
    if [ "$_TEST_FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}
