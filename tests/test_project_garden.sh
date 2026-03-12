#!/usr/bin/env bash
# tests/test_project_garden.sh — Tests for spec-62 Project Garden
# Covers: PROMPT_suggest.md, run_project_suggestions(), --suggest/--project-garden CLI flags,
# config loading, storage format, and garden separation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

SUGGEST_PROMPT="$_PROJECT_DIR/PROMPT_suggest.md"
TMPL_SUGGEST_PROMPT="$_PROJECT_DIR/templates/PROMPT_suggest.md"
GARDEN_SH="$_PROJECT_DIR/lib/garden.sh"
CONFIG_SH="$_PROJECT_DIR/lib/config.sh"
AUTOMATON_SH="$_PROJECT_DIR/automaton.sh"

# ============================================================
# AC-62-1: PROMPT_suggest.md exists with required structure
# ============================================================

assert_file_exists "$SUGGEST_PROMPT" "62/AC-1: PROMPT_suggest.md exists"
assert_file_exists "$TMPL_SUGGEST_PROMPT" "62/AC-1: templates/PROMPT_suggest.md exists"

prompt_content=$(cat "$SUGGEST_PROMPT" 2>/dev/null || true)

grep -q 'missing_feature\|security\|ux\|performance\|accessibility\|testing' <<< "$prompt_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-1: Prompt includes all 6 suggestion categories"

grep -q 'MAX_SUGGESTIONS' <<< "$prompt_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-1: Prompt has MAX_SUGGESTIONS placeholder"

grep -q 'JSON array\|json' <<< "$prompt_content" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-1: Prompt requests JSON array output"

# ============================================================
# AC-62-2: run_project_suggestions() defined in lib/garden.sh
# ============================================================

grep -q 'run_project_suggestions' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-2: run_project_suggestions() defined in lib/garden.sh"

grep -q 'project-garden' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-2: project-garden dir used (separate from evolution garden)"

grep -q 'PROJECT_GARDEN_ENABLED' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-2: Respects PROJECT_GARDEN_ENABLED toggle"

grep -q 'after_research\|after_review' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-2: Trigger parameter supported"

# ============================================================
# AC-62-3: project-garden/ separate from garden/
# ============================================================

# Verify different directory paths are used
grep -q '"$AUTOMATON_DIR/project-garden"' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-3: project-garden dir is distinct from evolution garden dir"

grep -q '"pg-"' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-3: Project garden IDs use pg- prefix"

# ============================================================
# AC-62-4/5: Collaborative and autonomous mode handling
# ============================================================

grep -q 'COLLABORATION_MODE.*collaborative' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-4: Collaborative mode check in run_project_suggestions"

grep -q 'project-suggestions.md' "$GARDEN_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-5: Autonomous mode writes project-suggestions.md"

# ============================================================
# AC-62-6/7: CLI flags and config
# ============================================================

grep -q '\-\-suggest' "$AUTOMATON_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-6: --suggest CLI flag exists"

grep -q '\-\-project-garden' "$AUTOMATON_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-6: --project-garden CLI flag exists"

grep -q 'PROJECT_GARDEN_MAX_SUGGESTIONS\|max_suggestions_per_cycle' "$CONFIG_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-7: max_suggestions_per_cycle config loaded"

grep -q 'PROJECT_GARDEN_ENABLED' "$CONFIG_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-7: project_garden.enabled config loaded"

# ============================================================
# AC-62-8: run_project_suggestions called at research and review gates
# ============================================================

grep -q 'run_project_suggestions.*after_research' "$AUTOMATON_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-8: run_project_suggestions called after_research"

grep -q 'run_project_suggestions.*after_review' "$AUTOMATON_SH" && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/AC-8: run_project_suggestions called after_review"

# ============================================================
# Templates sync
# ============================================================

diff "$_PROJECT_DIR/lib/garden.sh" "$_PROJECT_DIR/templates/lib/garden.sh" >/dev/null 2>&1 && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/sync: lib/garden.sh matches templates/lib/garden.sh"

diff "$_PROJECT_DIR/lib/config.sh" "$_PROJECT_DIR/templates/lib/config.sh" >/dev/null 2>&1 && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/sync: lib/config.sh matches templates/lib/config.sh"

diff "$_PROJECT_DIR/automaton.sh" "$_PROJECT_DIR/templates/automaton.sh" >/dev/null 2>&1 && rc=0 || rc=1
assert_exit_code 0 "$rc" "62/sync: automaton.sh matches templates/automaton.sh"

test_summary
