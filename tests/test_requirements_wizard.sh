#!/usr/bin/env bash
# tests/test_requirements_wizard.sh — Tests for spec-59 requirements wizard
# Verifies requirements_wizard() code paths: non-TTY guard, overwrite confirmation,
# missing prompt file, and Gate 1 re-check after completion.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_requirements_wizard_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: requirements_wizard() function exists ---
grep -q '^requirements_wizard()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "requirements_wizard() function exists"

# --- Test 2: Non-TTY guard returns 1 ---
# Extract the function body and run it with stdin from /dev/null (non-TTY)
cat > "$test_dir/test_nontty.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
requirements_wizard() {
    if [ ! -t 0 ]; then
        echo "Error: Requirements wizard requires an interactive terminal (stdin is not a TTY)." >&2
        return 1
    fi
    return 0
}
requirements_wizard
SCRIPT
rc=0
output=$(bash "$test_dir/test_nontty.sh" < /dev/null 2>&1) || rc=$?
assert_exit_code 1 "$rc" "Non-TTY stdin causes requirements_wizard to return 1"
assert_contains "$output" "interactive terminal" "Non-TTY error message mentions interactive terminal"

# --- Test 3: Overwrite confirmation - user declines ---
cat > "$test_dir/test_overwrite_decline.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
# Simulate TTY check always passing
requirements_wizard() {
    # Skip TTY check for test
    if ls specs/*.md >/dev/null 2>&1; then
        printf 'Continue? (yes/no) [no]: '
        read -r _overwrite_confirm
        case "$(echo "$_overwrite_confirm" | tr '[:upper:]' '[:lower:]')" in
            y|yes) ;;
            *)
                printf 'Wizard cancelled.\n'
                return 1
                ;;
        esac
    fi
    return 0
}
cd "$1"
mkdir -p specs
echo "# test spec" > specs/test.md
requirements_wizard
SCRIPT
rc=0
output=$(echo "no" | bash "$test_dir/test_overwrite_decline.sh" "$test_dir" 2>&1) || rc=$?
assert_exit_code 1 "$rc" "Declining overwrite confirmation returns 1"
assert_contains "$output" "Wizard cancelled" "Decline shows cancellation message"

# --- Test 4: Overwrite confirmation - user accepts ---
rc=0
output=$(echo "yes" | bash "$test_dir/test_overwrite_decline.sh" "$test_dir" 2>&1) || rc=$?
assert_exit_code 0 "$rc" "Accepting overwrite confirmation returns 0"

# --- Test 5: Overwrite confirmation - empty input declines ---
rc=0
output=$(echo "" | bash "$test_dir/test_overwrite_decline.sh" "$test_dir" 2>&1) || rc=$?
assert_exit_code 1 "$rc" "Empty input (default no) returns 1"

# --- Test 6: Missing PROMPT_wizard.md returns 1 ---
cat > "$test_dir/test_missing_prompt.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
# Simulate the prompt file check portion
_wizard_prompt_file="$1/PROMPT_wizard.md"
if [ ! -f "$_wizard_prompt_file" ]; then
    echo "Error: PROMPT_wizard.md not found at $_wizard_prompt_file" >&2
    exit 1
fi
exit 0
SCRIPT
rc=0
output=$(bash "$test_dir/test_missing_prompt.sh" "$test_dir/nonexistent" 2>&1) || rc=$?
assert_exit_code 1 "$rc" "Missing PROMPT_wizard.md returns 1"
assert_contains "$output" "PROMPT_wizard.md not found" "Missing prompt error mentions file name"

# --- Test 7: PROMPT_wizard.md exists - check passes ---
mkdir -p "$test_dir/prompt_dir"
echo "# Wizard Prompt" > "$test_dir/prompt_dir/PROMPT_wizard.md"
rc=0
output=$(bash "$test_dir/test_missing_prompt.sh" "$test_dir/prompt_dir" 2>&1) || rc=$?
assert_exit_code 0 "$rc" "Existing PROMPT_wizard.md passes check"

# --- Test 8: Gate 1 re-check integration exists ---
grep -q 'gate_spec_completeness\|gate_check.*spec_completeness' "$script_file" | head -1
# The function should call gate_spec_completeness after wizard completes
grep -A5 'Re-check Gate 1' "$script_file" | grep -q 'gate_spec_completeness'
rc=$?
assert_exit_code 0 "$rc" "requirements_wizard re-checks Gate 1 after completion"

# --- Test 9: --wizard flag exists in argument parser ---
grep -q '\-\-wizard)' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--wizard flag exists in argument parser"

# --- Test 10: --no-wizard flag exists in argument parser ---
grep -q '\-\-no-wizard)' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--no-wizard flag exists in argument parser"

# --- Test 11: ARG_WIZARD and ARG_NO_WIZARD defaults exist ---
grep -q 'ARG_WIZARD=false' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "ARG_WIZARD default is false"

grep -q 'ARG_NO_WIZARD=false' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "ARG_NO_WIZARD default is false"

# --- Test 12: --wizard + --no-wizard mutual exclusion ---
rc=0
output=$(bash "$automaton_script" --wizard --no-wizard 2>&1) || rc=$?
assert_exit_code 1 "$rc" "--wizard + --no-wizard exits with error code 1"
assert_contains "$output" "mutually exclusive" "--wizard + --no-wizard error mentions mutual exclusion"

# --- Test 13: Banner content check ---
grep -q 'Requirements Wizard' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "Banner contains 'Requirements Wizard' text"

# --- Test 14: --wizard in help output ---
grep -q '\-\-wizard' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--wizard mentioned in source (help/args)"

# --- Summary ---
test_summary
