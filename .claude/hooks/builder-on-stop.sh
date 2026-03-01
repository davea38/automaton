#!/usr/bin/env bash
# builder-on-stop.sh — Stop hook for build agents
# Extracts token usage, writes builder result JSON, stages and commits changes,
# and signals completion to the conductor by writing the result file.
# WHY: Stop hook replaces builder wrapper cleanup logic; runs guaranteed even
# if agent crashes or times out. (spec-31 §4, replaces spec-16 wrapper cleanup)
#
# Input: JSON on stdin with session data (transcript_path, token usage)
# Output: exit 0 always (Stop hooks should not block)
#
# Environment:
#   AUTOMATON_BUILDER_NUM  — builder number (1-based)
#   AUTOMATON_WAVE_NUM     — current wave number
#   AUTOMATON_PROJECT_ROOT — project root path (fallback: CLAUDE_PROJECT_DIR, pwd)
#
# Performance target: <30 seconds (Stop hooks do not block agent progress)

set -euo pipefail

# ---- Read hook input from stdin ----
input=$(cat)

# ---- Determine builder and wave context ----
builder_num="${AUTOMATON_BUILDER_NUM:-0}"
wave_num="${AUTOMATON_WAVE_NUM:-0}"
project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# If builder_num is not set via env, try to detect from worktree path
if [ "$builder_num" = "0" ]; then
    cwd="${PWD}"
    if [[ "$cwd" =~ builder-([0-9]+) ]]; then
        builder_num="${BASH_REMATCH[1]}"
    fi
fi

# If we can't determine builder number, exit gracefully
if [ "$builder_num" = "0" ]; then
    exit 0
fi

# ---- Derived paths ----
automaton_dir="$project_root/.automaton"
assignments_file="$automaton_dir/wave/assignments.json"
results_dir="$automaton_dir/wave/results"
result_file="$results_dir/builder-${builder_num}.json"

mkdir -p "$results_dir"

# ---- Read assignment from assignments.json ----
task=""
task_line=0
if [ -f "$assignments_file" ]; then
    assignment=$(jq ".assignments[$((builder_num - 1))] // {}" "$assignments_file" 2>/dev/null || echo '{}')
    task=$(echo "$assignment" | jq -r '.task // ""')
    task_line=$(echo "$assignment" | jq -r '.task_line // 0')
fi

# ---- Extract token usage from stdin session data ----
# Stop hooks receive session-level data including token usage
input_tokens=$(echo "$input" | jq -r '.usage.input_tokens // .token_usage.input_tokens // 0' 2>/dev/null || echo 0)
output_tokens=$(echo "$input" | jq -r '.usage.output_tokens // .token_usage.output_tokens // 0' 2>/dev/null || echo 0)
cache_create=$(echo "$input" | jq -r '.usage.cache_creation_input_tokens // .token_usage.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)
cache_read=$(echo "$input" | jq -r '.usage.cache_read_input_tokens // .token_usage.cache_read_input_tokens // 0' 2>/dev/null || echo 0)

# Try to extract from transcript_path if direct usage not available
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [ "$input_tokens" = "0" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # Extract from the last result message in the transcript
    usage_line=$(grep '"type":"result"' "$transcript_path" 2>/dev/null | tail -1 || true)
    if [ -n "$usage_line" ]; then
        input_tokens=$(echo "$usage_line" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo 0)
        output_tokens=$(echo "$usage_line" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo 0)
        cache_create=$(echo "$usage_line" | jq -r '.usage.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)
        cache_read=$(echo "$usage_line" | jq -r '.usage.cache_read_input_tokens // 0' 2>/dev/null || echo 0)
    fi
fi

# ---- Extract exit code and determine status ----
exit_code=$(echo "$input" | jq -r '.exit_code // 0' 2>/dev/null || echo 0)

# Determine agent output for status detection
agent_output=$(echo "$input" | jq -r '.output // .result // ""' 2>/dev/null || true)

status="success"
if [ "$exit_code" != "0" ]; then
    if echo "$agent_output" | grep -qi 'rate_limit\|429\|overloaded' 2>/dev/null; then
        status="rate_limited"
    else
        status="error"
    fi
elif ! echo "$agent_output" | grep -q '<result status="complete">' 2>/dev/null; then
    status="partial"
fi

# ---- Timestamps ----
completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
started_at=$(echo "$input" | jq -r '.started_at // empty' 2>/dev/null || true)
started_at="${started_at:-$completed_at}"

# Calculate duration
start_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || echo 0)
end_epoch=$(date -d "$completed_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$completed_at" +%s 2>/dev/null || echo 0)
duration=$((end_epoch - start_epoch))

# ---- Get git info ----
git_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")
files_changed=$(git diff --name-only HEAD~1 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')

# ---- Calculate cost estimate ----
estimated_cost=$(echo "scale=4; ($input_tokens * 3 + $output_tokens * 15) / 1000000" | bc 2>/dev/null || echo "0")

# ---- Check for completion signal in agent output ----
promise_complete=false
if echo "$agent_output" | grep -q '<result status="complete">' 2>/dev/null; then
    promise_complete=true
fi

# ---- Write result file (signals completion to the conductor) ----
tmp_result="${result_file}.tmp.$$"
cat > "$tmp_result" << RESULT_EOF
{
  "builder": $builder_num,
  "wave": $wave_num,
  "status": "$status",
  "task": $(echo "$task" | jq -R .),
  "task_line": $task_line,
  "started_at": "$started_at",
  "completed_at": "$completed_at",
  "duration_seconds": $duration,
  "exit_code": $exit_code,
  "tokens": {
    "input": $input_tokens,
    "output": $output_tokens,
    "cache_create": $cache_create,
    "cache_read": $cache_read
  },
  "estimated_cost": $estimated_cost,
  "git_commit": "$git_commit",
  "files_changed": $files_changed,
  "promise_complete": $promise_complete
}
RESULT_EOF

mv "$tmp_result" "$result_file"

# ---- Stage and commit changes if any files were modified ----
if git diff --quiet && git diff --cached --quiet 2>/dev/null; then
    # No changes to commit
    :
else
    git add -A 2>/dev/null || true
    git commit -m "builder-${builder_num}: wave ${wave_num} — ${task:-unknown task}" 2>/dev/null || true
    # Update git_commit in result file after committing
    new_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")
    new_files=$(git diff --name-only HEAD~1 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')
    if [ "$new_commit" != "$git_commit" ]; then
        jq --arg commit "$new_commit" --argjson files "$new_files" \
            '.git_commit = $commit | .files_changed = $files' \
            "$result_file" > "$tmp_result" 2>/dev/null && mv "$tmp_result" "$result_file"
    fi
fi

exit 0
