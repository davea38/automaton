#!/usr/bin/env bash
# tests/test_wizard_discovery.sh — Tests for spec-64 Wizard Discovery Stage
# Covers: PROMPT_wizard.md and PROMPT_converse.md discovery stage additions (34.1).
# These tests FAIL initially (no implementation exists yet).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

WIZARD_PROMPT="$_PROJECT_DIR/PROMPT_wizard.md"
CONVERSE_PROMPT="$_PROJECT_DIR/PROMPT_converse.md"
TMPL_WIZARD_PROMPT="$_PROJECT_DIR/templates/PROMPT_wizard.md"
TMPL_CONVERSE_PROMPT="$_PROJECT_DIR/templates/PROMPT_converse.md"

# ============================================================
# 34.1: PROMPT_wizard.md Discovery Stage (Stage 0)
# ============================================================

# AC-64-1: Discovery stage defined in PROMPT_wizard.md
assert_file_exists "$WIZARD_PROMPT" "PROMPT_wizard.md exists"

wizard_content=$(cat "$WIZARD_PROMPT" 2>/dev/null || true)
assert_contains "$wizard_content" "Discovery" \
    "34.1/AC-64-1: PROMPT_wizard.md contains Discovery stage"

# AC-64-1: Vagueness detection heuristics present
grep -q 'vague\|hedging\|vagueness' <<< "$wizard_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-1: PROMPT_wizard.md describes vagueness detection"

# AC-64-2: 3 concrete directions requirement
assert_contains "$wizard_content" "3 " \
    "34.1/AC-64-2: PROMPT_wizard.md instructs suggesting 3 project directions"

# AC-64-3: Transition to Stage 1 after selection
grep -q 'Stage 1\|stage 1' <<< "$wizard_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-3: PROMPT_wizard.md includes transition to Stage 1"

# AC-64-4: Reject-all handling (suggest new directions)
grep -q 'reject\|new directions\|3 more' <<< "$wizard_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-4: PROMPT_wizard.md handles rejection of all directions"

# AC-64-6: Specificity bypass — skip discovery for specific input
grep -q 'specific\|specificty\|bypass\|skip' <<< "$wizard_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-6: PROMPT_wizard.md describes specificity bypass"

# AC-64-7: Educational framing gated on COLLABORATION_MODE
grep -q 'COLLABORATION_MODE\|collaborative\|educational' <<< "$wizard_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-7: PROMPT_wizard.md references collaboration mode for educational framing"

# ============================================================
# 34.1: PROMPT_converse.md Discovery Capability
# ============================================================

assert_file_exists "$CONVERSE_PROMPT" "PROMPT_converse.md exists"

converse_content=$(cat "$CONVERSE_PROMPT" 2>/dev/null || true)
grep -q 'Discovery\|discovery' <<< "$converse_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-9: PROMPT_converse.md contains discovery capability"

# AC-64-1: Vagueness detection in converse prompt
grep -q 'vague\|vagueness\|hedging' <<< "$converse_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1/AC-64-9: PROMPT_converse.md describes vagueness detection"

# ============================================================
# 34.1: Template sync
# ============================================================

assert_file_exists "$TMPL_WIZARD_PROMPT" "34.1: templates/PROMPT_wizard.md exists"
assert_file_exists "$TMPL_CONVERSE_PROMPT" "34.1: templates/PROMPT_converse.md exists"

tmpl_wizard=$(cat "$TMPL_WIZARD_PROMPT" 2>/dev/null || true)
assert_contains "$tmpl_wizard" "Discovery" \
    "34.1: templates/PROMPT_wizard.md has Discovery stage"

tmpl_converse=$(cat "$TMPL_CONVERSE_PROMPT" 2>/dev/null || true)
grep -q 'Discovery\|discovery' <<< "$tmpl_converse" && rc=0 || rc=1
assert_exit_code 0 "$rc" "34.1: templates/PROMPT_converse.md has discovery capability"

test_summary
