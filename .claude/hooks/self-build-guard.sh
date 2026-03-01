#!/usr/bin/env bash
# self-build-guard.sh — PreToolUse hook for Write|Edit
# Blocks writes to orchestrator files unless the current task explicitly targets them.
# WHY: Self-modification safety is currently prompt-enforced (spec-22); this hook
# prevents accidental orchestrator corruption regardless of agent behavior.
# (spec-31, extends spec-22)
#
# Input: JSON on stdin with tool_input.file_path
# Output: exit 0 = allow, exit 2 = block (stderr fed back to agent)
#
# Performance target: <2 seconds (PreToolUse blocks agent progress)

set -euo pipefail

# Orchestrator files that require explicit task targeting to modify
ORCHESTRATOR_FILES=(
    "automaton.sh"
    "automaton.config.json"
    "bin/cli.js"
)
# PROMPT_*.md matched by pattern below

# Read the hook input from stdin — single read, reuse via herestring
input=$(cat)

# Extract the target file path from tool_input (herestring avoids pipe + subshell)
target_file=$(jq -r '.tool_input.file_path // empty' <<< "$input" 2>/dev/null)

# If no file path found, allow (not a file-writing operation we can check)
if [ -z "$target_file" ]; then
    exit 0
fi

# --- Determine project root ---

project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-}}"

# Derive from worktree path if env vars not set
if [ -z "$project_root" ]; then
    cwd="${PWD}"
    if [[ "$cwd" =~ (.*)/.automaton/worktrees/builder-[0-9]+ ]]; then
        project_root="${BASH_REMATCH[1]}"
    fi
fi

# If we can't determine project root, allow gracefully
if [ -z "$project_root" ]; then
    exit 0
fi

# --- Normalize target path to relative ---

relative_target="$target_file"
if [[ "$target_file" == "$project_root"/* ]]; then
    relative_target="${target_file#$project_root/}"
fi
relative_target="${relative_target#./}"

# --- Check if target is an orchestrator file ---

is_orchestrator=false

# Check exact matches
for orch_file in "${ORCHESTRATOR_FILES[@]}"; do
    if [ "$relative_target" = "$orch_file" ]; then
        is_orchestrator=true
        break
    fi
done

# Check PROMPT_*.md pattern
if [[ "$relative_target" =~ ^PROMPT_.*\.md$ ]]; then
    is_orchestrator=true
fi

# If not an orchestrator file, allow
if [ "$is_orchestrator" = "false" ]; then
    exit 0
fi

# --- Check self_build.enabled ---

config_file="$project_root/automaton.config.json"

# If config doesn't exist, block (no self-build config means self-build is not enabled)
if [ ! -f "$config_file" ]; then
    echo "Cannot modify orchestrator file '$relative_target' — self_build not configured" >&2
    exit 2
fi

# Use streaming filter (-e) for fast extraction from config
self_build_enabled=$(jq -r '.self_build.enabled // false' "$config_file" 2>/dev/null || echo "false")

# If self-build is disabled, block all writes to orchestrator files
if [ "$self_build_enabled" != "true" ]; then
    echo "Cannot modify orchestrator file '$relative_target' — self_build.enabled is false" >&2
    exit 2
fi

# --- Self-build is enabled: check if current task targets this file ---

# Read current task from progress.txt (generated each iteration by spec-33)
progress_file="$project_root/.automaton/progress.txt"

if [ ! -f "$progress_file" ]; then
    # No progress file yet — allow in self-build mode (early iterations)
    exit 0
fi

# Get the "Next pending" task description from progress.txt
current_task=$(grep '^Next pending:' "$progress_file" 2>/dev/null | sed 's/^Next pending: //' || true)

# If no task info available, allow (can't determine if targeted)
if [ -z "$current_task" ] || [ "$current_task" = "None" ]; then
    exit 0
fi

# Check if the current task explicitly mentions the target file or related keywords
# Use bash parameter expansion instead of basename command
target_basename="${relative_target##*/}"
target_name_no_ext="${target_basename%.*}"

# Build a combined grep pattern to check in a single process spawn
# This replaces 8 separate grep calls with one, cutting subprocess overhead significantly
patterns="$target_basename|$target_name_no_ext|orchestrat|self.build|self-build"

# Add file-specific patterns
if [[ "$relative_target" =~ ^PROMPT_(.*)\.md$ ]]; then
    prompt_name="${BASH_REMATCH[1]}"
    patterns="$patterns|prompt|$prompt_name"
fi
if [ "$relative_target" = "bin/cli.js" ]; then
    patterns="$patterns|cli|scaffol"
fi

# Single grep with combined pattern (case-insensitive, extended regex)
if grep -qiE "$patterns" <<< "$current_task"; then
    exit 0
fi

# Task does not explicitly target this orchestrator file — block
echo "Cannot modify orchestrator file '$relative_target' — not the assigned task target. Current task: $current_task" >&2
exit 2
