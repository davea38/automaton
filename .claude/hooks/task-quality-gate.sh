#!/usr/bin/env bash
# task-quality-gate.sh — TaskCompleted hook for Agent Teams mode
# Runs task-specific validation before allowing a task to be marked complete.
# WHY: Prevents tasks from being marked complete when tests fail or syntax errors
# exist. Ensures quality standards are enforced automatically. (spec-31 §6)
#
# Input: JSON on stdin with task_id, task_subject, task_description
# Output: exit 0 = task accepted, exit 2 = task rejected (stderr feedback to teammate)
#
# TaskCompleted only supports command hooks.
# Performance target: <60 seconds (includes test execution)

set -euo pipefail

# ---- Read hook input from stdin ----
input=$(cat)

task_id=$(echo "$input" | jq -r '.task_id // empty' 2>/dev/null)
task_subject=$(echo "$input" | jq -r '.task_subject // empty' 2>/dev/null)
task_description=$(echo "$input" | jq -r '.task_description // empty' 2>/dev/null)

# If no task info available, accept gracefully
if [ -z "$task_id" ] && [ -z "$task_subject" ]; then
    exit 0
fi

# Combine subject and description for pattern matching
task_text="${task_subject:-} ${task_description:-}"

# ---- Determine project root ----
project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
automaton_dir="$project_root/.automaton"

errors=""

# ---- 1. Check for recent test failures ----
# Read test_results.json and check if the most recent test run failed
results_file="$automaton_dir/test_results.json"
if [ -f "$results_file" ]; then
    # Get the most recent test result
    last_result=$(jq -r '.[-1].result // empty' "$results_file" 2>/dev/null)
    last_command=$(jq -r '.[-1].command // empty' "$results_file" 2>/dev/null)

    if [ "$last_result" = "fail" ]; then
        errors="${errors}Most recent test failed: $last_command\n"
    fi
fi

# ---- 2. Check syntax of modified files ----
# Get files changed since last commit (staged + unstaged)
changed_files=$(git diff --name-only HEAD 2>/dev/null || true)
staged_files=$(git diff --cached --name-only 2>/dev/null || true)
all_changed=$(printf '%s\n%s' "$changed_files" "$staged_files" | sort -u | grep -v '^$' || true)

if [ -n "$all_changed" ]; then
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        [ ! -f "$project_root/$file" ] && continue

        case "$file" in
            *.sh)
                # Bash syntax check
                if ! bash -n "$project_root/$file" 2>/dev/null; then
                    errors="${errors}Syntax error in $file\n"
                fi
                ;;
            *.js|*.mjs)
                # Node.js syntax check
                if command -v node >/dev/null 2>&1; then
                    if ! node --check "$project_root/$file" 2>/dev/null; then
                        errors="${errors}Syntax error in $file\n"
                    fi
                fi
                ;;
            *.json)
                # JSON syntax check
                if ! jq empty "$project_root/$file" 2>/dev/null; then
                    errors="${errors}Invalid JSON in $file\n"
                fi
                ;;
            *.py)
                # Python syntax check
                if command -v python3 >/dev/null 2>&1; then
                    if ! python3 -c "import py_compile; py_compile.compile('$project_root/$file', doraise=True)" 2>/dev/null; then
                        errors="${errors}Syntax error in $file\n"
                    fi
                fi
                ;;
        esac
    done <<< "$all_changed"
fi

# ---- 3. Check for test annotation match ----
# Look for a test file associated with this task in IMPLEMENTATION_PLAN.md
plan_file="$project_root/IMPLEMENTATION_PLAN.md"
if [ -f "$plan_file" ]; then
    # Search for a task line matching the subject, followed by a test annotation
    # Test annotations look like: <!-- test: tests/test_feature.sh -->
    test_file=""

    # Try to find the task in the plan and extract its test annotation
    if [ -n "$task_subject" ]; then
        # Escape special regex characters in subject for grep
        escaped_subject=$(printf '%s' "$task_subject" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
        # Look for the test annotation on the same line or nearby
        match_line=$(grep -n "$escaped_subject" "$plan_file" 2>/dev/null | head -1 | cut -d: -f1 || true)
        if [ -n "$match_line" ]; then
            # Check the line itself and the next line for test annotation
            test_file=$(sed -n "${match_line},$((match_line+1))p" "$plan_file" 2>/dev/null \
                | grep -oP '<!-- test: \K[^ ]+(?= -->)' 2>/dev/null || true)
        fi
    fi

    # If a test file is annotated and it exists, run it
    if [ -n "$test_file" ] && [ "$test_file" != "none" ] && [ -f "$project_root/$test_file" ]; then
        case "$test_file" in
            *.sh)
                if ! bash "$project_root/$test_file" >/dev/null 2>&1; then
                    errors="${errors}Task test failed: $test_file\n"
                fi
                ;;
            *.js)
                if command -v node >/dev/null 2>&1; then
                    if ! node "$project_root/$test_file" >/dev/null 2>&1; then
                        errors="${errors}Task test failed: $test_file\n"
                    fi
                fi
                ;;
            *.py)
                if command -v python3 >/dev/null 2>&1; then
                    if ! python3 "$project_root/$test_file" >/dev/null 2>&1; then
                        errors="${errors}Task test failed: $test_file\n"
                    fi
                fi
                ;;
        esac
    fi
fi

# ---- 4. Check automaton.sh syntax if it was modified ----
# This is critical for self-build mode
if echo "$all_changed" | grep -q 'automaton.sh' 2>/dev/null; then
    if [ -f "$project_root/automaton.sh" ]; then
        if ! bash -n "$project_root/automaton.sh" 2>/dev/null; then
            errors="${errors}automaton.sh has syntax errors — must be fixed before marking complete\n"
        fi
    fi
fi

# ---- Decision ----
if [ -n "$errors" ]; then
    printf "Quality gate failed for task '%s':\n%b" "${task_subject:-$task_id}" "$errors" >&2
    echo "Fix these issues before marking the task complete." >&2
    exit 2
fi

exit 0
