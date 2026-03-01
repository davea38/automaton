#!/usr/bin/env bash
# evolution-safety-guard.sh — PreToolUse hook for Bash
# Enforces branch isolation, constitutional compliance, and scope limits
# during evolution mode commits. Only active when AUTOMATON_EVOLVE=true.
# (spec-45 §5)
#
# Input: JSON on stdin with tool_input.command
# Output: exit 0 = allow, exit 2 = block (stderr fed back to agent)
#
# Checks:
#   1. Branch isolation: commits only on automaton/evolve-* branches
#   2. Constitutional compliance: warns on protected function modifications
#   3. Scope limits: blocks when files changed exceeds max_files_per_iteration

set -euo pipefail

# --- Only active during evolution mode ---
[ "${AUTOMATON_EVOLVE:-false}" = "true" ] || exit 0

# Read hook input from stdin
input=$(cat)

# Extract the command from tool_input
command=$(jq -r '.tool_input.command // empty' <<< "$input" 2>/dev/null)

# Only intercept git commit commands — allow everything else
if [ -z "$command" ] || ! echo "$command" | grep -qE '\bgit\s+commit\b'; then
    exit 0
fi

# --- Check 1: Branch isolation ---
# Evolution commits must only happen on evolution branches
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

if [[ ! "$current_branch" =~ ^automaton/evolve- ]]; then
    echo "SAFETY VIOLATION: Evolution commit attempted on non-evolution branch: $current_branch" >&2
    exit 2
fi

# --- Check 2: Constitutional compliance (warning only) ---
# Detect modifications to protected functions and warn — does not block
config_file="automaton.config.json"

if [ -f "$config_file" ]; then
    protected_functions=$(jq -r '.self_build.protected_functions[]' "$config_file" 2>/dev/null || true)
    if [ -n "$protected_functions" ]; then
        staged_diff=$(git diff --cached 2>/dev/null || true)
        while IFS= read -r func; do
            [ -z "$func" ] && continue
            if echo "$staged_diff" | grep -qE "^[-+].*${func}\(\)"; then
                echo "SAFETY WARNING: Protected function '$func' modified. Requires review." >&2
            fi
        done <<< "$protected_functions"
    fi
fi

# --- Check 3: Scope limits ---
# Block commits that change more files than allowed
files_changed=$(git diff --cached --name-only 2>/dev/null | wc -l)
max_files=$(jq -r '.self_build.max_files_per_iteration // 3' "$config_file" 2>/dev/null || echo "3")

if [ "$files_changed" -gt "$max_files" ]; then
    echo "SAFETY VIOLATION: $files_changed files changed (max: $max_files)" >&2
    exit 2
fi

exit 0
