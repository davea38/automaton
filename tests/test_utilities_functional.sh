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
assert_equals "PROMPT_research.md" "$(get_phase_prompt "research")" "get_phase_prompt research"
assert_equals "PROMPT_plan.md" "$(get_phase_prompt "plan")" "get_phase_prompt plan"
assert_equals "PROMPT_build.md" "$(get_phase_prompt "build")" "get_phase_prompt build"
assert_equals "PROMPT_review.md" "$(get_phase_prompt "review")" "get_phase_prompt review"

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
test_summary
