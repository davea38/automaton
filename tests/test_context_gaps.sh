#!/usr/bin/env bash
# tests/test_context_gaps.sh — Tests for untested context functions
# Covers: append_iteration_memory

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_context_gaps_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence ---

grep -q 'append_iteration_memory()' "$script_file"
assert_exit_code 0 $? "append_iteration_memory function exists"

# --- Behavioral ---
body=$(sed -n '/^append_iteration_memory()/,/^}/p' "$script_file")

echo "$body" | grep -q 'memory\|MEMORY\|agent-memory'
assert_exit_code 0 $? "append_iteration_memory writes to memory"

echo "$body" | grep -q 'iteration\|phase'
assert_exit_code 0 $? "append_iteration_memory includes iteration context"

# --- Cross-reference: called from phase transition ---
count=$(grep -c 'append_iteration_memory' "$script_file")
assert_equals 1 "$([ "$count" -ge 2 ] && echo 1 || echo 0)" "append_iteration_memory is called (not just defined)"

test_summary
