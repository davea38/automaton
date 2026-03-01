#!/usr/bin/env bash
# tests/test_cli_help.sh — Tests for spec-44 §44.4 _show_help()
# Verifies that _show_help() exists and includes all command categories
# and all CLI flags from the spec.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _show_help function is defined ---
grep_result=$(grep -c '^_show_help()' "$script_file" || true)
assert_equals "1" "$grep_result" "_show_help() function is defined"

# --- Test 2: --help calls _show_help ---
grep_result=$(grep -c '_show_help' "$script_file" || true)
# At least 2: the definition and the call from --help|-h)
[ "$grep_result" -ge 2 ] && result="yes" || result="no"
assert_equals "yes" "$result" "--help case calls _show_help()"

# ============================================================
# Help output content tests
# ============================================================

# Extract and run _show_help to capture its output
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/run_help.sh" << 'WRAPPER'
#!/usr/bin/env bash
set -uo pipefail
WRAPPER

# Extract _show_help function
echo "eval \"\$(sed -n '/^_show_help()/,/^}/p' '$script_file')\"" >> "$TEST_DIR/run_help.sh"
echo '_show_help' >> "$TEST_DIR/run_help.sh"
chmod +x "$TEST_DIR/run_help.sh"

help_output=$(bash "$TEST_DIR/run_help.sh" 2>&1) || true

# --- Test 3: Help output contains all category headers ---
assert_contains "$help_output" "Standard Mode:" "Help contains Standard Mode category"
assert_contains "$help_output" "Evolution Mode:" "Help contains Evolution Mode category"
assert_contains "$help_output" "Garden:" "Help contains Garden category"
assert_contains "$help_output" "Observation:" "Help contains Observation category"
assert_contains "$help_output" "Governance:" "Help contains Governance category"

# --- Test 4: Standard Mode flags ---
assert_contains "$help_output" "--resume" "Help contains --resume"
assert_contains "$help_output" "--skip-research" "Help contains --skip-research"
assert_contains "$help_output" "--skip-review" "Help contains --skip-review"
assert_contains "$help_output" "--config" "Help contains --config"
assert_contains "$help_output" "--dry-run" "Help contains --dry-run"
assert_contains "$help_output" "--self" "Help contains --self"
assert_contains "$help_output" "--stats" "Help contains --stats"
assert_contains "$help_output" "--budget-check" "Help contains --budget-check"
assert_contains "$help_output" "--help" "Help contains --help"

# --- Test 5: Evolution Mode flags ---
assert_contains "$help_output" "--evolve" "Help contains --evolve"
assert_contains "$help_output" "--cycles" "Help contains --cycles"

# --- Test 6: Garden flags ---
assert_contains "$help_output" "--plant" "Help contains --plant"
assert_contains "$help_output" "--garden" "Help contains --garden"
assert_contains "$help_output" "--garden-detail" "Help contains --garden-detail"
assert_contains "$help_output" "--water" "Help contains --water"
assert_contains "$help_output" "--prune" "Help contains --prune"
assert_contains "$help_output" "--promote" "Help contains --promote"

# --- Test 7: Observation flags ---
assert_contains "$help_output" "--health" "Help contains --health"
assert_contains "$help_output" "--signals" "Help contains --signals"
assert_contains "$help_output" "--inspect" "Help contains --inspect"

# --- Test 8: Governance flags ---
assert_contains "$help_output" "--constitution" "Help contains --constitution"
assert_contains "$help_output" "--amend" "Help contains --amend"
assert_contains "$help_output" "--override" "Help contains --override"
assert_contains "$help_output" "--pause-evolution" "Help contains --pause-evolution"

# --- Test 9: Exit codes section ---
assert_contains "$help_output" "Exit codes:" "Help contains Exit codes section"

# ============================================================
# Summary
# ============================================================

test_summary
