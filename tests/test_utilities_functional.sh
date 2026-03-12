#!/usr/bin/env bash
# tests/test_utilities_functional.sh — Functional tests for lib/utilities.sh
# Tests output truncation, debt classification, guardrails, agent helpers.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

_log_output=""
log() { _log_output+="[$1] $2"$'\n'; }

# Minimal config stubs
OUTPUT_MAX_LINES=20
OUTPUT_HEAD_LINES=5
OUTPUT_TAIL_LINES=5
DEBT_TRACKING_ENABLED="false"
GUARDRAILS_MODE="warn"
GUARDRAILS_SIZE_CEILING=18000
PROJECT_ROOT="$TEST_DIR"

source "$_PROJECT_DIR/lib/utilities.sh"

# --- Test: _prompt_to_agent_name mapping ---

assert_equals "automaton-research" "$(_prompt_to_agent_name "PROMPT_research.md")" "maps research prompt"
assert_equals "automaton-planner" "$(_prompt_to_agent_name "PROMPT_plan.md")" "maps plan prompt"
assert_equals "automaton-builder" "$(_prompt_to_agent_name "PROMPT_build.md")" "maps build prompt"
assert_equals "automaton-reviewer" "$(_prompt_to_agent_name "PROMPT_review.md")" "maps review prompt"
assert_equals "automaton-self-researcher" "$(_prompt_to_agent_name "PROMPT_self_research.md")" "maps self-research prompt"
assert_equals "automaton-self-planner" "$(_prompt_to_agent_name "PROMPT_self_plan.md")" "maps self-plan prompt"
assert_equals "" "$(_prompt_to_agent_name "PROMPT_unknown.md")" "returns empty for unknown prompt"

# --- Test: truncate_output below threshold ---

small_file="$TEST_DIR/small_output.txt"
seq 1 10 > "$small_file"

result=$(truncate_output "$small_file")
line_count=$(echo "$result" | wc -l)
assert_equals "10" "$line_count" "truncate_output passes small files through"

# --- Test: truncate_output above threshold ---

large_file="$TEST_DIR/large_output.txt"
seq 1 50 > "$large_file"

result=$(truncate_output "$large_file" "build" "1")
assert_contains "$result" "1" "truncated output includes head"
assert_contains "$result" "50" "truncated output includes tail"
assert_contains "$result" "truncated" "truncated output includes marker"

# Verify archive was created
archive_count=$(ls "$AUTOMATON_DIR/logs/"output_build_1_*.log 2>/dev/null | wc -l)
assert_equals "1" "$archive_count" "truncate_output archives full output"

# --- Test: _classify_debt_type ---

assert_equals "error_handling" "$(_classify_debt_type "TODO: add error handling for retry")" "classifies error handling"
assert_equals "hardcoded" "$(_classify_debt_type "FIXME: hardcoded magic number")" "classifies hardcoded"
assert_equals "performance" "$(_classify_debt_type "TODO: slow O(n^2) lookup")" "classifies performance"
assert_equals "test_coverage" "$(_classify_debt_type "TODO: add test coverage")" "classifies test coverage"
assert_equals "cleanup" "$(_classify_debt_type "TODO: clean up this section")" "classifies cleanup"

# --- Test: _scan_technical_debt when disabled ---

DEBT_TRACKING_ENABLED="false"
rc=0
_scan_technical_debt "HEAD~1" || rc=$?
assert_equals "0" "$rc" "scan_technical_debt no-op when disabled"

# --- Test: guardrail_check_size under ceiling ---

# Create a small automaton.sh in the test dir
mkdir -p "$TEST_DIR/lib"
echo '#!/bin/bash' > "$TEST_DIR/automaton.sh"
seq 1 100 | while read -r i; do echo "# line $i"; done >> "$TEST_DIR/automaton.sh"
echo '#!/bin/bash' > "$TEST_DIR/lib/test.sh"

GUARDRAIL_VIOLATIONS=()
cd "$TEST_DIR"
rc=0
guardrail_check_size || rc=$?
assert_equals "0" "$rc" "guardrail_check_size passes under ceiling"

# --- Test: guardrail_check_size over ceiling ---

GUARDRAILS_SIZE_CEILING=50
GUARDRAIL_VIOLATIONS=()
rc=0
guardrail_check_size || rc=$?
assert_equals "1" "$rc" "guardrail_check_size fails over ceiling"
assert_contains "${GUARDRAIL_VIOLATIONS[0]}" "Size Ceiling" "violation mentions size ceiling"

GUARDRAILS_SIZE_CEILING=18000

# --- Test: get_phase_prompt returns correct files ---

ARG_SELF="false"
AUTOMATON_INSTALL_DIR="/test/install/dir"
assert_equals "/test/install/dir/PROMPT_research.md" "$(get_phase_prompt "research")" "get_phase_prompt research"
assert_equals "/test/install/dir/PROMPT_plan.md" "$(get_phase_prompt "plan")" "get_phase_prompt plan"
assert_equals "/test/install/dir/PROMPT_build.md" "$(get_phase_prompt "build")" "get_phase_prompt build"
assert_equals "/test/install/dir/PROMPT_review.md" "$(get_phase_prompt "review")" "get_phase_prompt review"

# --- Test: get_phase_model returns configured models ---

MODEL_RESEARCH="opus"
MODEL_PLANNING="sonnet"
MODEL_BUILDING="opus"
MODEL_REVIEW="sonnet"

assert_equals "opus" "$(get_phase_model "research")" "get_phase_model research"
assert_equals "sonnet" "$(get_phase_model "plan")" "get_phase_model plan"
assert_equals "opus" "$(get_phase_model "build")" "get_phase_model build"
assert_equals "sonnet" "$(get_phase_model "review")" "get_phase_model review"

# --- Test: get_phase_max_iterations ---

EXEC_MAX_ITER_RESEARCH=3
EXEC_MAX_ITER_PLAN=2
EXEC_MAX_ITER_BUILD=0
EXEC_MAX_ITER_REVIEW=5

assert_equals "3" "$(get_phase_max_iterations "research")" "max_iterations research"
assert_equals "2" "$(get_phase_max_iterations "plan")" "max_iterations plan"
assert_equals "0" "$(get_phase_max_iterations "build")" "max_iterations build (unlimited)"
assert_equals "5" "$(get_phase_max_iterations "review")" "max_iterations review"

# --- Test: agent_signaled_complete ---

AGENT_RESULT="some output <result status=\"complete\">done</result>"
assert_equals "0" "$(agent_signaled_complete && echo 0 || echo 1)" "detects result status=complete"

AGENT_RESULT="some output COMPLETE</promise>"
assert_equals "0" "$(agent_signaled_complete && echo 0 || echo 1)" "detects legacy COMPLETE signal"

AGENT_RESULT="still working..."
assert_equals "1" "$(agent_signaled_complete && echo 0 || echo 1)" "rejects non-complete output"

cd "$_PROJECT_DIR"

# --- Test: 25.1 self-build codebase overview block removed ---
# This block greps automaton.sh function signatures and injects ~40 lines into
# build context on every self-build iteration — redundant since builder has tools.
# After implementation: lib/utilities.sh must NOT contain this block.
assert_not_contains \
    "$(grep -n 'Codebase Overview (automaton.sh)' lib/utilities.sh 2>/dev/null || true)" \
    "Codebase Overview" \
    "25.1: self-build codebase overview block removed from lib/utilities.sh"

# --- Test: 25.2 assess_complexity strips markdown code fences from Claude output ---
# The haiku model sometimes wraps JSON in ```json ... ``` fences which breaks jq.
# After implementation: the assess_complexity() function body in lib/qa.sh must
# include fence-stripping (sed or jq -r '.') before parsing .tier.
assess_body=$(sed -n '/^assess_complexity()/,/^}/p' lib/qa.sh 2>/dev/null || true)
# Fence-stripping uses: sed to remove ``` lines, OR jq -r '.' to unwrap (no field access), OR --raw-input
fence_strip_in_assess=$(echo "$assess_body" | grep -cE "sed.*\`\`\`|jq -r '\.'|jq --raw-input|strip_markdown_fence" 2>/dev/null; true)
assert_equals "1" "$([ "${fence_strip_in_assess:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "25.2: assess_complexity() body has fence-stripping logic in lib/qa.sh"

# --- Test: 27.2 budget.json history is populated by update_budget() ---
# Implementation decision: budget.json history is already populated inline by
# update_budget() in lib/budget.sh (via .history += [{...}] jq filter at line ~920).
# No separate append_budget_history() helper is needed.
history_append_line=$(grep -c '\.history += \[' "$script_file" 2>/dev/null || echo 0)
assert_equals "1" "$([ "${history_append_line:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "27.2: update_budget() populates budget.json history array (via .history += [{...}])"

# Verify update_budget() appends entries with required fields
history_fields=$(grep -A20 '\.history += \[' "$script_file" 2>/dev/null | grep -cE 'phase|iteration|input_tokens|output_tokens'; true)
assert_equals "1" "$([ "${history_fields:-0}" -ge 4 ] && echo 1 || echo 0)" \
    "27.2: update_budget() history entries include required token/phase/iteration fields"


# --- Test: 28.1 budget.sh uses batched jq reads in hot-path functions ---
# After implementation: functions like check_budget_remaining() should use a
# single jq call with @tsv or array output to read multiple fields at once.
# Before: multiple `jq -r '.field'` calls on the same file.
# After: `jq -r '[.f1,.f2,.f3] | @tsv'` or `jq -r '.f1, .f2, .f3'` patterns.
budget_tsv_count=$(grep -cE '@tsv|read.*<<.*jq' \
    "$_PROJECT_DIR/lib/budget.sh" 2>/dev/null; true)
assert_equals "1" "$([ "${budget_tsv_count:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "28.1: lib/budget.sh uses batched jq reads (@tsv or read-from-jq pattern)"

# --- Test: 28.2 qa.sh uses batched jq reads in hot-path functions ---
# After implementation: check_qa_gate(), detect_oscillation(), assess_complexity()
# should consolidate jq field reads from the same JSON file.
qa_tsv_count=$(grep -cE '@tsv|read.*<<.*jq' \
    "$_PROJECT_DIR/lib/qa.sh" 2>/dev/null; true)
assert_equals "1" "$([ "${qa_tsv_count:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "28.2: lib/qa.sh uses batched jq reads (@tsv or read-from-jq pattern)"

# --- Test: 28.3 evolution.sh uses batched jq reads in hot-path functions ---
# After implementation: evolve_reflect(), evolve_observe() should batch
# multiple field extractions from garden.json and metrics files.
evolution_tsv_count=$(grep -cE '@tsv|read.*<<.*jq' \
    "$_PROJECT_DIR/lib/evolution.sh" 2>/dev/null; true)
assert_equals "1" "$([ "${evolution_tsv_count:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "28.3: lib/evolution.sh uses batched jq reads (@tsv or read-from-jq pattern)"

# --- Test: 29.1 parallel_core.sh exists after split ---
# After implementation: lib/parallel.sh is split into two focused modules.
assert_file_exists "$_PROJECT_DIR/lib/parallel_core.sh" \
    "29.1: lib/parallel_core.sh exists after parallel.sh split"

# --- Test: 29.1 parallel_teams.sh exists after split ---
assert_file_exists "$_PROJECT_DIR/lib/parallel_teams.sh" \
    "29.1: lib/parallel_teams.sh exists after parallel.sh split"

# --- Test: 29.2 automaton.sh sources both parallel modules ---
# After implementation: the source block in automaton.sh must include both
# parallel_core.sh and parallel_teams.sh (or parallel.sh must not be the only entry).
sources_core=$(grep -c 'parallel_core\.sh' "$_PROJECT_DIR/automaton.sh" 2>/dev/null; true)
sources_teams=$(grep -c 'parallel_teams\.sh' "$_PROJECT_DIR/automaton.sh" 2>/dev/null; true)
assert_equals "1" "$([ "${sources_core:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "29.2: automaton.sh sources parallel_core.sh"
assert_equals "1" "$([ "${sources_teams:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "29.2: automaton.sh sources parallel_teams.sh"

# --- Test: 31.2 assess_complexity prompt uses concrete tier example, not pipe-delimited ---
# Before fix: {"tier": "SIMPLE|MODERATE|COMPLEX"} causes Haiku to return the literal
# pipe-delimited string, which fails bash case matching (| is OR in case patterns).
# After fix: the prompt must use a single concrete example like {"tier": "MODERATE", ...}
# and must NOT use the pipe-delimited format in the JSON example.
assess_prompt=$(grep -A 40 'assess_complexity()' "$_PROJECT_DIR/lib/qa.sh" 2>/dev/null | head -60 || true)
pipe_format_count=$(echo "$assess_prompt" | grep -cF 'SIMPLE|MODERATE|COMPLEX' 2>/dev/null; true)
assert_equals "0" "${pipe_format_count:-0}" \
    "31.2: assess_complexity() prompt must NOT use SIMPLE|MODERATE|COMPLEX pipe-delimited example"

# The prompt must use a single concrete tier value (e.g. "MODERATE") in its JSON example
single_tier_count=$(echo "$assess_prompt" | grep -cE '"tier"[[:space:]]*:[[:space:]]*"(SIMPLE|MODERATE|COMPLEX)"' 2>/dev/null; true)
assert_equals "1" "$([ "${single_tier_count:-0}" -ge 1 ] && echo 1 || echo 0)" \
    "31.2: assess_complexity() prompt uses a single concrete tier value in JSON example"

test_summary
