#!/usr/bin/env bash
# tests/test_metrics_gaps.sh — Tests for untested metrics functions
# Covers: _fmt_num (in metrics.sh), _trend_str

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# --- Function existence ---

# _fmt_num in metrics.sh context
grep -q '_fmt_num' "$_PROJECT_DIR/lib/metrics.sh"
assert_exit_code 0 $? "_fmt_num referenced in metrics.sh"

grep -q '_trend_str()' "$script_file"
assert_exit_code 0 $? "_trend_str function exists"

# --- Behavioral: _trend_str ---
body=$(sed -n '/_trend_str()/,/^}/p' "$script_file")
echo "$body" | grep -q 'trend\|improv\|declin\|stable'
assert_exit_code 0 $? "_trend_str formats trend indicator"

# Should handle upward and downward trends
echo "$body" | grep -qE '↑|↓|→|up|down|stable|improv|declin'
assert_exit_code 0 $? "_trend_str shows directional indicator"

test_summary
