#!/usr/bin/env bash
# tests/test_helpers.sh — minimal bash assertion functions for automaton tests
# Used when bats is not available. Source this file from test scripts.

_TEST_PASS_COUNT=0
_TEST_FAIL_COUNT=0

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

test_summary() {
    local total=$((_TEST_PASS_COUNT + _TEST_FAIL_COUNT))
    echo ""
    echo "Results: $total tests, $_TEST_PASS_COUNT passed, $_TEST_FAIL_COUNT failed"
    if [ "$_TEST_FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}
