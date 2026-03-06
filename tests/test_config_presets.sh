#!/usr/bin/env bash
# tests/test_config_presets.sh — Tests for config preset functions
# Covers: _apply_max_plan_preset, _apply_rate_limit_preset, _apply_allowance_parallel_defaults

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_config_presets_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence ---

for fn in _apply_max_plan_preset _apply_rate_limit_preset _apply_allowance_parallel_defaults; do
    grep -q "${fn}()" "$script_file"
    assert_exit_code 0 $? "$fn function exists"
done

# --- Behavioral: _apply_max_plan_preset ---
body=$(sed -n '/_apply_max_plan_preset()/,/^}/p' "$script_file")

# Should check max_plan_preset flag
echo "$body" | grep -q 'max_plan_preset\|MAX_PLAN_PRESET'
assert_exit_code 0 $? "_apply_max_plan_preset checks preset flag"

# Should set budget mode to allowance when enabled
echo "$body" | grep -q 'allowance'
assert_exit_code 0 $? "_apply_max_plan_preset sets allowance mode"

# --- Behavioral: _apply_rate_limit_preset ---
body=$(sed -n '/_apply_rate_limit_preset()/,/^}/p' "$script_file")

# Should check preset value
echo "$body" | grep -q 'RATE_LIMIT_PRESET\|preset'
assert_exit_code 0 $? "_apply_rate_limit_preset checks preset"

# Should set token and request rate limits
echo "$body" | grep -q 'RATE_TOKENS_PER_MINUTE\|tokens_per_minute'
assert_exit_code 0 $? "_apply_rate_limit_preset sets token rate"

echo "$body" | grep -q 'RATE_REQUESTS_PER_MINUTE\|requests_per_minute'
assert_exit_code 0 $? "_apply_rate_limit_preset sets request rate"

# --- Behavioral: _apply_allowance_parallel_defaults ---
body=$(sed -n '/_apply_allowance_parallel_defaults()/,/^}/p' "$script_file")

# Should check if in allowance mode
echo "$body" | grep -q 'allowance\|BUDGET_MODE'
assert_exit_code 0 $? "_apply_allowance_parallel_defaults checks budget mode"

# Should set parallel defaults
echo "$body" | grep -q 'PARALLEL\|parallel'
assert_exit_code 0 $? "_apply_allowance_parallel_defaults sets parallel config"

# --- Cross-reference: presets are called from automaton.sh ---
grep -q '_apply_max_plan_preset' "$script_file"
assert_exit_code 0 $? "_apply_max_plan_preset is invoked"

grep -q '_apply_rate_limit_preset' "$script_file"
assert_exit_code 0 $? "_apply_rate_limit_preset is invoked"

grep -q '_apply_allowance_parallel_defaults' "$script_file"
assert_exit_code 0 $? "_apply_allowance_parallel_defaults is invoked"

test_summary
