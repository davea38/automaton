#!/usr/bin/env bash
# enforce-file-ownership.sh — PreToolUse hook for Write|Edit
# Blocks writes to files outside a builder's ownership list during parallel waves.
# WHY: Prompt-based file ownership is advisory; this hook guarantees enforcement.
# (spec-31, extends spec-17)
#
# Input: JSON on stdin with tool_input.file_path
# Output: exit 0 = allow, exit 2 = block (stderr fed back to agent)
#
# Performance target: <2 seconds (PreToolUse blocks agent progress)

set -euo pipefail

# Read the hook input from stdin
input=$(cat)

# Extract the target file path from tool_input
target_file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# If no file path found, allow (not a file-writing operation we can check)
if [ -z "$target_file" ]; then
    exit 0
fi

# --- Determine project root and builder number ---

# Method 1: Environment variables (set by builder wrapper)
project_root="${AUTOMATON_PROJECT_ROOT:-}"
builder_num="${AUTOMATON_BUILDER_NUM:-}"

# Method 2: Derive from worktree path pattern (.automaton/worktrees/builder-N)
if [ -z "$project_root" ] || [ -z "$builder_num" ]; then
    cwd="${PWD}"
    if [[ "$cwd" =~ (.*)/.automaton/worktrees/builder-([0-9]+) ]]; then
        project_root="${project_root:-${BASH_REMATCH[1]}}"
        builder_num="${builder_num:-${BASH_REMATCH[2]}}"
    fi
fi

# Method 3: Fall back to CLAUDE_PROJECT_DIR
project_root="${project_root:-${CLAUDE_PROJECT_DIR:-}}"

# If we still can't determine builder number or project root, allow gracefully
# (hook may be active outside parallel mode or in an unexpected environment)
if [ -z "$project_root" ] || [ -z "$builder_num" ]; then
    exit 0
fi

# --- Read assignments ---

assignments_file="$project_root/.automaton/wave/assignments.json"

# If assignments file doesn't exist, allow (wave may not have started yet)
if [ ! -f "$assignments_file" ]; then
    exit 0
fi

# Extract files_owned for this builder (0-indexed in the assignments array)
builder_index=$((builder_num - 1))
files_owned=$(jq -r ".assignments[$builder_index].files_owned[]?" "$assignments_file" 2>/dev/null)

# If no ownership data found, allow (assignment may not have files_owned)
if [ -z "$files_owned" ]; then
    exit 0
fi

# --- Normalize target path for comparison ---

# Strip project root prefix to get relative path
relative_target="$target_file"
if [[ "$target_file" == "$project_root"/* ]]; then
    relative_target="${target_file#$project_root/}"
fi
# Also strip leading ./
relative_target="${relative_target#./}"

# --- Check ownership ---

while IFS= read -r owned_file; do
    # Normalize owned file path
    owned_file="${owned_file#./}"

    # Direct match
    if [ "$relative_target" = "$owned_file" ]; then
        exit 0
    fi

    # Allow test files for owned files (e.g., tests/test_foo.sh for foo.sh)
    base=$(basename "$owned_file" | sed 's/\.[^.]*$//')
    if [[ "$relative_target" == tests/test_"$base"* ]] || [[ "$relative_target" == tests/"$base"* ]]; then
        exit 0
    fi
done <<< "$files_owned"

# File is NOT in ownership list — block the write
echo "Cannot modify '$relative_target' — not in builder-$builder_num's ownership list. Owned files: $(echo "$files_owned" | tr '\n' ', ' | sed 's/,$//')" >&2
exit 2
