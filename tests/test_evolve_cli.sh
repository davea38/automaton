#!/usr/bin/env bash
# tests/test_evolve_cli.sh — Tests for spec-41 §1 --evolve and --cycles CLI flags
# Verifies that --evolve sets ARG_EVOLVE=true and implies --self,
# --cycles N sets ARG_CYCLES=N, and help text includes new flags.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: ARG_EVOLVE variable exists and defaults to false ---
grep_result=$(grep -c '^ARG_EVOLVE=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_EVOLVE defaults to false"

# --- Test 2: ARG_CYCLES variable exists and defaults to 0 ---
grep_result=$(grep -c '^ARG_CYCLES=0' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_CYCLES defaults to 0"

# --- Test 3: --evolve case exists in argument parser ---
grep_result=$(grep -c '^\s*--evolve)' "$script_file" || true)
assert_equals "1" "$grep_result" "--evolve case exists in argument parser"

# --- Test 4: --evolve sets ARG_EVOLVE=true ---
grep_result=$(grep -A3 '^\s*--evolve)' "$script_file" | grep -c 'ARG_EVOLVE=true' || true)
assert_equals "1" "$grep_result" "--evolve sets ARG_EVOLVE=true"

# --- Test 5: --evolve implies --self (sets ARG_SELF=true) ---
grep_result=$(grep -A5 '^\s*--evolve)' "$script_file" | grep -c 'ARG_SELF=true' || true)
assert_equals "1" "$grep_result" "--evolve implies --self (ARG_SELF=true)"

# --- Test 6: --cycles case exists in argument parser ---
grep_result=$(grep -c '^\s*--cycles)' "$script_file" || true)
assert_equals "1" "$grep_result" "--cycles case exists in argument parser"

# --- Test 7: --cycles sets ARG_CYCLES ---
grep_result=$(grep -A5 '^\s*--cycles)' "$script_file" | grep -c 'ARG_CYCLES=' || true)
assert_equals "1" "$grep_result" "--cycles sets ARG_CYCLES"

# --- Test 8: --cycles requires a numeric argument ---
grep_result=$(grep -A8 '^\s*--cycles)' "$script_file" | grep -c 'requires' || true)
assert_equals "1" "$grep_result" "--cycles validates that argument is provided"

# --- Test 9: Help text includes --evolve ---
grep_result=$(grep -c '\-\-evolve' "$script_file" | head -1 || true)
[ "$grep_result" -ge 2 ] && help_has_evolve="1" || help_has_evolve="0"
assert_equals "1" "$help_has_evolve" "Help text mentions --evolve"

# --- Test 10: Help text includes --cycles ---
grep_result=$(grep -c '\-\-cycles' "$script_file" || true)
[ "$grep_result" -ge 2 ] && help_has_cycles="1" || help_has_cycles="0"
assert_equals "1" "$help_has_cycles" "Help text mentions --cycles"

# --- Test 11: Post-parse evolve mode handling exists ---
grep_result=$(grep -c 'ARG_EVOLVE.*true' "$script_file" || true)
[ "$grep_result" -ge 2 ] && evolve_handled="1" || evolve_handled="0"
assert_equals "1" "$evolve_handled" "ARG_EVOLVE is checked after parsing"

test_summary
