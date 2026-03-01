#!/usr/bin/env bash
# capture-test-results.sh — PostToolUse hook for Bash
# Detects test/lint commands and captures structured results to .automaton/test_results.json
# WHY: Structured test results enable automated quality gates in review and provide
# test history for regression tracking. (spec-31 §3, used by spec-36)
#
# Input: JSON on stdin with tool_input.command and tool_result
# Output: exit 0 always (PostToolUse hooks should not block)
#
# Performance target: <30 seconds (PostToolUse does not block agent progress)

set -euo pipefail

# Read hook input from stdin
input=$(cat)

# Extract the command that was executed
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# If no command found, exit (nothing to capture)
if [ -z "$command" ]; then
    exit 0
fi

# --- Detect test/lint commands ---
# Match common test runners, linters, and check commands via pattern matching.
# For non-test commands, exit immediately (no-op) per spec.

is_test_command=false
case "$command" in
    *bats\ *|bats\ *)                    is_test_command=true ;;
    *jest\ *|*jest|*jest\ *)              is_test_command=true ;;
    *pytest\ *|*pytest|*pytest\ *)        is_test_command=true ;;
    *mocha\ *|*mocha)                     is_test_command=true ;;
    *vitest\ *|*vitest)                   is_test_command=true ;;
    *cargo\ test*|*go\ test*)             is_test_command=true ;;
    *npm\ test*|*yarn\ test*|*pnpm\ test*) is_test_command=true ;;
    *npx\ test*|*make\ test*)             is_test_command=true ;;
    *eslint\ *|*eslint)                   is_test_command=true ;;
    *shellcheck\ *|*shellcheck)           is_test_command=true ;;
    *tsc\ --noEmit*|*tsc\ -*)            is_test_command=true ;;
    *mypy\ *|*mypy)                       is_test_command=true ;;
    *flake8\ *|*flake8)                   is_test_command=true ;;
    *rubocop\ *|*rubocop)                 is_test_command=true ;;
    *bash\ -n\ *)                         is_test_command=true ;;
    *phpunit\ *|*phpunit)                 is_test_command=true ;;
    *rspec\ *|*rspec)                     is_test_command=true ;;
    *unittest\ *|*python\ -m\ unittest*)  is_test_command=true ;;
    *assert_*|*test_*)                    is_test_command=true ;;
esac

if [ "$is_test_command" = "false" ]; then
    exit 0
fi

# --- Extract result data ---

# Try exitCode (camelCase) first, then exit_code (snake_case)
exit_code=$(echo "$input" | jq -r '.tool_result.exitCode // .tool_result.exit_code // empty' 2>/dev/null)
exit_code="${exit_code:--1}"

passed=false
result="fail"
if [ "$exit_code" = "0" ]; then
    passed=true
    result="pass"
fi

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Read iteration and phase from state.json ---

project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
state_file="$project_root/.automaton/state.json"
results_file="$project_root/.automaton/test_results.json"

iteration=0
phase="unknown"
if [ -f "$state_file" ]; then
    iteration=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null || echo 0)
    phase=$(jq -r '.phase // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
fi

# --- Build result entry ---

new_entry=$(jq -n \
    --arg command "$command" \
    --argjson exit_code "$exit_code" \
    --argjson passed "$passed" \
    --arg result "$result" \
    --arg timestamp "$timestamp" \
    --argjson iteration "$iteration" \
    --arg phase "$phase" \
    '{
        command: $command,
        exit_code: $exit_code,
        passed: $passed,
        result: $result,
        timestamp: $timestamp,
        iteration: $iteration,
        phase: $phase
    }')

# --- Append result to test_results.json ---
# Uses flat array format for compatibility with calculate_test_coverage() reader
# which iterates with .[] and filters on .result == "pass"|"fail".

mkdir -p "$(dirname "$results_file")"

if [ -f "$results_file" ]; then
    existing=$(jq '.' "$results_file" 2>/dev/null || echo '[]')
    if echo "$existing" | jq -e 'type == "array"' >/dev/null 2>&1; then
        # Already a flat array — append
        updated=$(echo "$existing" | jq --argjson entry "$new_entry" '. + [$entry]')
    elif echo "$existing" | jq -e '.results | type == "array"' >/dev/null 2>&1; then
        # Legacy {version, results} format — extract results and convert to flat array
        updated=$(echo "$existing" | jq --argjson entry "$new_entry" '.results + [$entry]')
    else
        # Malformed — start fresh
        updated="[$new_entry]"
    fi
else
    updated="[$new_entry]"
fi

# Write atomically using temp file
tmp_file="${results_file}.tmp.$$"
echo "$updated" > "$tmp_file"
mv "$tmp_file" "$results_file"

exit 0
