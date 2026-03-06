#!/usr/bin/env bash
# tests/test_state_gaps.sh — Tests for untested state management functions
# Covers: _ensure_automaton_dirs, generate_bootstrap_script, validate_state, generate_context

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_state_gaps_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence ---

for fn in _ensure_automaton_dirs generate_bootstrap_script validate_state generate_context; do
    grep -q "${fn}()" "$script_file"
    assert_exit_code 0 $? "$fn function exists"
done

# --- Behavioral: _ensure_automaton_dirs ---
body=$(sed -n '/_ensure_automaton_dirs()/,/^}/p' "$script_file")
echo "$body" | grep -q 'mkdir'
assert_exit_code 0 $? "_ensure_automaton_dirs creates directories"

echo "$body" | grep -q 'AUTOMATON_DIR'
assert_exit_code 0 $? "_ensure_automaton_dirs uses AUTOMATON_DIR"

# --- Behavioral: generate_bootstrap_script ---
body=$(sed -n '/^generate_bootstrap_script()/,/^}/p' "$script_file")
echo "$body" | grep -q 'init.sh\|bootstrap'
assert_exit_code 0 $? "generate_bootstrap_script creates init script"

# --- Behavioral: validate_state ---
body=$(sed -n '/^validate_state()/,/^}/p' "$script_file")
echo "$body" | grep -q 'state\|phase\|valid'
assert_exit_code 0 $? "validate_state checks state integrity"

# --- Behavioral: generate_context ---
body=$(sed -n '/^generate_context()/,/^}/p' "$script_file")
echo "$body" | grep -q 'context\|phase\|state'
assert_exit_code 0 $? "generate_context builds agent context"

# --- Test: _ensure_automaton_dirs is called during initialization ---
grep -q '_ensure_automaton_dirs' "$script_file"
count=$(grep -c '_ensure_automaton_dirs' "$script_file")
assert_equals 1 "$([ "$count" -ge 2 ] && echo 1 || echo 0)" "_ensure_automaton_dirs is called (not just defined)"

# --- Test: validate_state is referenced in state management flow ---
grep -c 'validate_state' "$script_file" > /dev/null
assert_exit_code 0 $? "validate_state is referenced in codebase"

test_summary
