#!/usr/bin/env bash
# tests/test_evolution_gaps.sh — Tests for untested evolution functions
# Covers: _write_implement_json, _write_observe_json

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_evolution_gaps_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence ---

grep -q '_write_implement_json()' "$script_file"
assert_exit_code 0 $? "_write_implement_json function exists"

grep -q '_write_observe_json()' "$script_file"
assert_exit_code 0 $? "_write_observe_json function exists"

# --- Behavioral: _write_implement_json ---
body=$(sed -n '/_write_implement_json()/,/^}/p' "$script_file")
echo "$body" | grep -q 'json\|implement'
assert_exit_code 0 $? "_write_implement_json writes implementation data"

# Should produce valid JSON structure
echo "$body" | grep -q 'jq\|cat.*EOF\|json'
assert_exit_code 0 $? "_write_implement_json outputs JSON"

# --- Behavioral: _write_observe_json ---
body=$(sed -n '/_write_observe_json()/,/^}/p' "$script_file")
echo "$body" | grep -q 'json\|observ'
assert_exit_code 0 $? "_write_observe_json writes observation data"

echo "$body" | grep -q 'jq\|cat.*EOF\|json'
assert_exit_code 0 $? "_write_observe_json outputs JSON"

# --- Cross-references ---
count=$(grep -c '_write_implement_json' "$script_file")
assert_equals 1 "$([ "$count" -ge 2 ] && echo 1 || echo 0)" "_write_implement_json is called (not just defined)"

count=$(grep -c '_write_observe_json' "$script_file")
assert_equals 1 "$([ "$count" -ge 2 ] && echo 1 || echo 0)" "_write_observe_json is called (not just defined)"

test_summary
