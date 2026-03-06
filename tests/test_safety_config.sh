#!/usr/bin/env bash
# tests/test_safety_config.sh — Tests for spec-45 §2 safety configuration section
# Verifies that automaton.config.json contains the safety section with correct defaults
# and that automaton.sh loads all safety config values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"

# --- Test 1: automaton.config.json contains safety.max_total_lines ---
val=$(jq -r '.safety.max_total_lines // "missing"' "$config_file")
assert_equals "15000" "$val" "safety.max_total_lines defaults to 15000 in config"

# --- Test 2: safety.max_total_functions ---
val=$(jq -r '.safety.max_total_functions // "missing"' "$config_file")
assert_equals "300" "$val" "safety.max_total_functions defaults to 300"

# --- Test 3: safety.min_test_pass_rate ---
val=$(jq -r '.safety.min_test_pass_rate // "missing"' "$config_file")
assert_equals "0.8" "${val%0}" "safety.min_test_pass_rate defaults to 0.80"

# --- Test 4: safety.max_consecutive_failures ---
val=$(jq -r '.safety.max_consecutive_failures // "missing"' "$config_file")
assert_equals "3" "$val" "safety.max_consecutive_failures defaults to 3"

# --- Test 5: safety.max_consecutive_regressions ---
val=$(jq -r '.safety.max_consecutive_regressions // "missing"' "$config_file")
assert_equals "2" "$val" "safety.max_consecutive_regressions defaults to 2"

# --- Test 6: safety.preserve_failed_branches ---
val=$(jq -r '.safety.preserve_failed_branches // "missing"' "$config_file")
assert_equals "true" "$val" "safety.preserve_failed_branches defaults to true"

# --- Test 7: safety.preflight_enabled ---
val=$(jq -r '.safety.preflight_enabled // "missing"' "$config_file")
assert_equals "true" "$val" "safety.preflight_enabled defaults to true"

# --- Test 8: safety.sandbox_testing_enabled ---
val=$(jq -r '.safety.sandbox_testing_enabled // "missing"' "$config_file")
assert_equals "true" "$val" "safety.sandbox_testing_enabled defaults to true"

# --- Test 9-16: load_config() sets SAFETY_* variables from config ---
(
    source "$_PROJECT_DIR/lib/config.sh"
    CONFIG_FILE="$config_file" load_config
    assert_equals "15000" "$SAFETY_MAX_TOTAL_LINES" "load_config sets SAFETY_MAX_TOTAL_LINES"
    assert_equals "300" "$SAFETY_MAX_TOTAL_FUNCTIONS" "load_config sets SAFETY_MAX_TOTAL_FUNCTIONS"
    assert_equals "0.8" "${SAFETY_MIN_TEST_PASS_RATE%0}" "load_config sets SAFETY_MIN_TEST_PASS_RATE"
    assert_equals "3" "$SAFETY_MAX_CONSECUTIVE_FAILURES" "load_config sets SAFETY_MAX_CONSECUTIVE_FAILURES"
    assert_equals "2" "$SAFETY_MAX_CONSECUTIVE_REGRESSIONS" "load_config sets SAFETY_MAX_CONSECUTIVE_REGRESSIONS"
    assert_equals "true" "$SAFETY_PRESERVE_FAILED_BRANCHES" "load_config sets SAFETY_PRESERVE_FAILED_BRANCHES"
    assert_equals "true" "$SAFETY_PREFLIGHT_ENABLED" "load_config sets SAFETY_PREFLIGHT_ENABLED"
    assert_equals "true" "$SAFETY_SANDBOX_TESTING_ENABLED" "load_config sets SAFETY_SANDBOX_TESTING_ENABLED"
)

# --- Test 17: automaton.sh has SAFETY_MAX_TOTAL_LINES default in else branch ---
grep_result=$(grep -c 'SAFETY_MAX_TOTAL_LINES=15000' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: automaton.sh has SAFETY_MAX_TOTAL_LINES default in else branch"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: automaton.sh should have SAFETY_MAX_TOTAL_LINES default in else branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 18: .gitignore references .automaton/evolution/ as ephemeral state ---
gitignore_file="$SCRIPT_DIR/../.gitignore"
if grep -q '.automaton/evolution/' "$gitignore_file" 2>/dev/null; then
    echo "PASS: .gitignore references .automaton/evolution/"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: .gitignore should reference .automaton/evolution/" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 19: .gitignore references circuit-breakers.json ---
if grep -q 'circuit-breakers.json' "$gitignore_file" 2>/dev/null; then
    echo "PASS: .gitignore references circuit-breakers.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: .gitignore should reference circuit-breakers.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
