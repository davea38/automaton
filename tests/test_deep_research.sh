#!/usr/bin/env bash
# tests/test_deep_research.sh — Tests for spec-63 Deep Research Mode
# Covers: PROMPT_deep_research.md creation (34.2), --research CLI flag (34.3),
# and plan phase context inclusion of research docs (34.4).
# These tests FAIL initially (no implementation exists yet).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

DEEP_RESEARCH_PROMPT="$_PROJECT_DIR/PROMPT_deep_research.md"
TMPL_DEEP_RESEARCH_PROMPT="$_PROJECT_DIR/templates/PROMPT_deep_research.md"

# ============================================================
# 34.2: PROMPT_deep_research.md exists with required structure
# ============================================================

# AC-63-1: Prompt file exists
assert_file_exists "$DEEP_RESEARCH_PROMPT" "34.2/AC-63-1: PROMPT_deep_research.md exists"

prompt_content=$(cat "$DEEP_RESEARCH_PROMPT" 2>/dev/null || true)

# AC-63-2: Instructs researching 3-5 approaches
assert_contains "$prompt_content" "3\|approaches" \
    "34.2/AC-63-2: Prompt instructs researching 3-5 approaches"

# AC-63-3: Comparative matrix required
assert_contains "$prompt_content" "matrix\|comparative\|Comparative" \
    "34.2/AC-63-3: Prompt requires comparative matrix"

# AC-63-4: Recommendation section required
assert_contains "$prompt_content" "Recommendation\|recommendation\|recommend" \
    "34.2/AC-63-4: Prompt requires recommendation with reasoning"

# Output format: deep research title
assert_contains "$prompt_content" "Deep Research\|deep research" \
    "34.2: Prompt specifies 'Deep Research' document title format"

# AC-63-8: Standalone mode — works without PRD/specs
assert_contains "$prompt_content" "standalone\|without PRD\|no project\|PRD.*if.*exist\|if.*exist.*PRD" \
    "34.2/AC-63-8: Prompt handles standalone mode (no PRD/specs)"

# Template sync
assert_file_exists "$TMPL_DEEP_RESEARCH_PROMPT" \
    "34.2: templates/PROMPT_deep_research.md exists"

# ============================================================
# 34.3: --research CLI flag and dispatch in automaton.sh
# ============================================================

# AC-63-1: --research flag exists in argument parser
grep -q '\-\-research)' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3/AC-63-1: --research flag exists in automaton.sh argument parser"

# ARG_RESEARCH_TOPIC variable initialized
grep -q 'ARG_RESEARCH_TOPIC' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3: ARG_RESEARCH_TOPIC variable initialized in automaton.sh"

# run_deep_research() function defined
grep -q 'run_deep_research' "$_PROJECT_DIR/automaton.sh" "$_PROJECT_DIR/lib/collaborate.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3: run_deep_research() function defined"

# AC-63-6: Output written to .automaton/research/ directory
grep -q '\.automaton/research' "$_PROJECT_DIR/automaton.sh" "$_PROJECT_DIR/lib/collaborate.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3/AC-63-6: .automaton/research/ output directory referenced"

# Topic sanitization present (spaces to hyphens)
grep -q 'sanitize\|s/ /-/\|tr.*spaces\|sed.*space' \
    "$_PROJECT_DIR/automaton.sh" "$_PROJECT_DIR/lib/collaborate.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3: topic sanitization logic present"

# AC-63-5: budget enforcement for deep research
grep -q 'deep_research_budget\|DEEP_RESEARCH_BUDGET' \
    "$_PROJECT_DIR/automaton.sh" "$_PROJECT_DIR/lib/collaborate.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3/AC-63-5: deep_research_budget enforced"

# Config: research.deep_research_budget in automaton.config.json
budget_val=$(jq -r '.research.deep_research_budget' "$_PROJECT_DIR/automaton.config.json" 2>/dev/null || echo "null")
assert_not_contains "$budget_val" "null" \
    "34.3: automaton.config.json has research.deep_research_budget"

# Config: research.deep_research_model in automaton.config.json
model_val=$(jq -r '.research.deep_research_model' "$_PROJECT_DIR/automaton.config.json" 2>/dev/null || echo "null")
assert_not_contains "$model_val" "null" \
    "34.3: automaton.config.json has research.deep_research_model"

# Help text includes --research
help_output=$(bash "$automaton_script" --help 2>&1) || true
assert_contains "$help_output" "--research" "34.3: help text includes --research"

# Empty topic string errors
output=$(bash "$automaton_script" --research "" 2>&1) || rc=$?
assert_contains "$output" "requires a topic\|topic.*required\|requires.*topic" \
    "34.3: --research with empty topic shows error"

# Templates: automaton.sh template has --research flag
grep -q '\-\-research)' "$_PROJECT_DIR/templates/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.3: templates/automaton.sh has --research flag"

# ============================================================
# 34.4: Plan phase context includes research documents
# ============================================================

# AC-63-7: lib/context.sh checks for .automaton/research/ files
grep -q '\.automaton/research\|RESEARCH-.*\.md' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.4/AC-63-7: lib/context.sh checks .automaton/research/ for plan phase"

# AC-63-7: research documents included in plan phase context
grep -q 'plan.*research\|research.*plan\|RESEARCH' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.4/AC-63-7: lib/context.sh includes research docs in plan context"

# Templates sync
grep -q '\.automaton/research\|RESEARCH-.*\.md' "$_PROJECT_DIR/templates/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.4: templates/lib/context.sh includes research docs in plan context"

test_summary
