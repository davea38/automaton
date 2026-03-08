#!/usr/bin/env bash
# tests/test_scope.sh — Tests for spec-60 --scope PATH flag
# Covers variable separation, path resolution, mutual exclusion, and banner.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Helper: run automaton.sh and capture exit code + output
# Sets: _ra_output, _ra_rc
_run_automaton() {
    _ra_rc=0
    _ra_output=$(bash "$automaton_script" "$@" 2>&1) || _ra_rc=$?
}

# ============================================================
# 60.1 — Variable Separation: AUTOMATON_INSTALL_DIR
# ============================================================

# AUTOMATON_INSTALL_DIR should be set to the directory containing automaton.sh
assert_matches "$(grep -n 'AUTOMATON_INSTALL_DIR=' "$automaton_script" | head -1)" \
    'AUTOMATON_INSTALL_DIR=.*dirname.*BASH_SOURCE' \
    "AUTOMATON_INSTALL_DIR is derived from BASH_SOURCE[0] dirname"

# AUTOMATON_DIR should be set to an absolute path (using $(pwd))
assert_matches "$(grep -n 'AUTOMATON_DIR=' "$automaton_script" | head -1)" \
    'AUTOMATON_DIR=.*pwd.*\.automaton' \
    "AUTOMATON_DIR uses pwd to create absolute path"

# AUTOMATON_INSTALL_DIR should be defined before module loading
install_dir_line=$(grep -n 'AUTOMATON_INSTALL_DIR=' "$automaton_script" | head -1 | cut -d: -f1)
lib_dir_line=$(grep -n 'AUTOMATON_LIB_DIR=' "$automaton_script" | head -1 | cut -d: -f1)
if [ "$install_dir_line" -lt "$lib_dir_line" ]; then
    echo "PASS: AUTOMATON_INSTALL_DIR defined before AUTOMATON_LIB_DIR"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: AUTOMATON_INSTALL_DIR must be defined before AUTOMATON_LIB_DIR" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# 60.1 — Variable Separation: ARG_SCOPE default
# ============================================================

assert_matches "$(grep 'ARG_SCOPE=' "$automaton_script" | head -1)" \
    'ARG_SCOPE=""' \
    "ARG_SCOPE default is empty string"

# ============================================================
# 60.1 — CLI Parsing: --scope case branch
# ============================================================

assert_matches "$(grep -c '\-\-scope)' "$automaton_script")" \
    '^[1-9]' \
    "--scope case branch exists in automaton.sh"

# ============================================================
# 60.1 — Path resolution: error cases
# ============================================================

# --scope with no argument should error
_run_automaton --scope
assert_equals "1" "$_ra_rc" "--scope with no argument exits 1"
assert_contains "$_ra_output" "requires a directory path" "--scope no-arg error message"

# --scope with nonexistent path should error
_run_automaton --scope /nonexistent/path/xyzzy
assert_equals "1" "$_ra_rc" "--scope nonexistent path exits 1"
assert_contains "$_ra_output" "does not exist" "--scope nonexistent path error message"

# --scope with a file (not directory) should error
tmpfile=$(mktemp)
_run_automaton --scope "$tmpfile"
rm -f "$tmpfile"
assert_equals "1" "$_ra_rc" "--scope file path exits 1"
assert_contains "$_ra_output" "not a directory" "--scope file path error message"

# ============================================================
# 60.1 — Mutual exclusion: --scope + --self
# ============================================================

_run_automaton --scope /tmp --self --dry-run
assert_equals "1" "$_ra_rc" "--scope + --self exits 1"
assert_contains "$_ra_output" "mutually exclusive" "--scope + --self error message"

# ============================================================
# 60.2 — get_phase_prompt uses AUTOMATON_INSTALL_DIR prefix
# ============================================================

# get_phase_prompt should prefix paths with AUTOMATON_INSTALL_DIR
assert_matches "$(grep 'AUTOMATON_INSTALL_DIR' "$SCRIPT_DIR/../lib/utilities.sh" | grep -c 'get_phase_prompt\|_install_dir')" \
    '^[1-9]' \
    "get_phase_prompt references AUTOMATON_INSTALL_DIR"

# Verify get_phase_prompt returns absolute paths (not bare filenames)
# by sourcing utilities and checking output
(
    # Set up minimal environment for sourcing
    AUTOMATON_INSTALL_DIR="/fake/install/dir"
    ARG_SELF="false"
    # Source only the function we need
    eval "$(sed -n '/^get_phase_prompt()/,/^}/p' "$SCRIPT_DIR/../lib/utilities.sh")"
    result=$(get_phase_prompt "build")
    if [ "$result" = "/fake/install/dir/PROMPT_build.md" ]; then
        echo "PASS: get_phase_prompt prefixes with AUTOMATON_INSTALL_DIR"
    else
        echo "FAIL: get_phase_prompt returned '$result', expected '/fake/install/dir/PROMPT_build.md'" >&2
        exit 1
    fi
) && ((_TEST_PASS_COUNT++)) || ((_TEST_FAIL_COUNT++))

# ============================================================
# 60.1 — --scope . is a valid no-op (resolves to cwd)
# ============================================================

# --scope . should not error during parsing (may fail later due to missing deps)
_run_automaton --scope . --dry-run
assert_equals "0" "$_ra_rc" "--scope . with --dry-run succeeds"

# ============================================================
# 60.2 — run_agent wraps claude invocation with cd to PROJECT_ROOT
# ============================================================

# Native agent mode: claude invocation should be wrapped in (cd "$PROJECT_ROOT" ...)
assert_matches "$(grep -A2 'cd.*PROJECT_ROOT.*&&.*claude' "$SCRIPT_DIR/../lib/utilities.sh" | head -1)" \
    'cd.*PROJECT_ROOT.*claude' \
    "run_agent native mode wraps claude with cd to PROJECT_ROOT"

# Legacy mode: both invocations should use the subshell cd pattern
_cd_count=$(grep -c 'cd.*PROJECT_ROOT.*&&.*claude' "$SCRIPT_DIR/../lib/utilities.sh")
assert_equals "2" "$_cd_count" "run_agent has cd PROJECT_ROOT wrapper in both native and legacy modes"

test_summary
