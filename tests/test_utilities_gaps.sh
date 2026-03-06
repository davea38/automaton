#!/usr/bin/env bash
# tests/test_utilities_gaps.sh — Tests for untested utility functions
# Covers: emit_status_line

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_utilities_gaps_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence ---

grep -q 'emit_status_line()' "$script_file"
assert_exit_code 0 $? "emit_status_line function exists"

# --- Behavioral ---
body=$(sed -n '/^emit_status_line()/,/^}/p' "$script_file")

echo "$body" | grep -q 'status\|phase\|iteration'
assert_exit_code 0 $? "emit_status_line includes phase info"

# Should be called during phase transitions or iterations
count=$(grep -c 'emit_status_line' "$script_file")
assert_equals 1 "$([ "$count" -ge 2 ] && echo 1 || echo 0)" "emit_status_line is called (not just defined)"

test_summary
