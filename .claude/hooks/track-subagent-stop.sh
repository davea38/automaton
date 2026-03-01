#!/usr/bin/env bash
# track-subagent-stop.sh — SubagentStop hook for automaton agents
# Extracts token usage from session data and updates the matching entry in
# .automaton/subagent_usage.json for budget reconciliation.
# WHY: Per-subagent token tracking enables accurate budget attribution across
# parallel builders. Stop hook completes the record started by track-subagent-start.sh.
# (spec-31 §5)
#
# Input: JSON on stdin with session data (token usage, session_id, transcript_path)
# Output: exit 0 always (SubagentStop hooks should not block)
#
# Environment:
#   AUTOMATON_PROJECT_ROOT — project root (fallback: CLAUDE_PROJECT_DIR, pwd)
#
# Performance target: <10 seconds

set -euo pipefail

# ---- Read hook input from stdin ----
input=$(cat)

# ---- Extract agent info and session ID (herestrings avoid pipe + subshell) ----
agent_name=$(jq -r '.agent_name // .name // "unknown"' <<< "$input" 2>/dev/null || echo "unknown")
session_id=$(jq -r '.session_id // .id // empty' <<< "$input" 2>/dev/null || true)

# ---- Determine paths ----
project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
usage_file="$project_root/.automaton/subagent_usage.json"

# If usage file does not exist, nothing to update
if [ ! -f "$usage_file" ]; then
    exit 0
fi

# ---- Extract token usage (single jq call, tab-separated output) ----
IFS=$'\t' read -r input_tokens output_tokens cache_create cache_read < <(
    jq -r '[
        (.usage.input_tokens // .token_usage.input_tokens // 0),
        (.usage.output_tokens // .token_usage.output_tokens // 0),
        (.usage.cache_creation_input_tokens // .token_usage.cache_creation_input_tokens // 0),
        (.usage.cache_read_input_tokens // .token_usage.cache_read_input_tokens // 0)
    ] | @tsv' <<< "$input" 2>/dev/null || echo "0	0	0	0"
)
input_tokens="${input_tokens:-0}"
output_tokens="${output_tokens:-0}"
cache_create="${cache_create:-0}"
cache_read="${cache_read:-0}"

# Try transcript_path fallback if direct usage not available
transcript_path=$(jq -r '.transcript_path // empty' <<< "$input" 2>/dev/null || true)
if [ "$input_tokens" = "0" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    usage_line=$(grep '"type":"result"' "$transcript_path" 2>/dev/null | tail -1 || true)
    if [ -n "$usage_line" ]; then
        input_tokens=$(echo "$usage_line" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo 0)
        output_tokens=$(echo "$usage_line" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo 0)
        cache_create=$(echo "$usage_line" | jq -r '.usage.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)
        cache_read=$(echo "$usage_line" | jq -r '.usage.cache_read_input_tokens // 0' 2>/dev/null || echo 0)
    fi
fi

# ---- Extract exit code ----
exit_code=$(jq -r '.exit_code // 0' <<< "$input" 2>/dev/null || echo 0)

status="completed"
if [ "$exit_code" != "0" ]; then
    status="error"
fi

# ---- Build tokens object ----
stopped_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

tokens_obj=$(jq -n \
    --argjson input "$input_tokens" \
    --argjson output "$output_tokens" \
    --argjson cache_create "$cache_create" \
    --argjson cache_read "$cache_read" \
    '{
        input: $input,
        output: $output,
        cache_create: $cache_create,
        cache_read: $cache_read
    }')

# ---- Update matching entry in subagent_usage.json ----
# Match by session_id if available, otherwise match by agent_name + status "running" (last one)
existing=$(jq '.' "$usage_file" 2>/dev/null || echo '[]')
if ! jq -e 'type == "array"' <<< "$existing" >/dev/null 2>&1; then
    existing='[]'
fi

if [ -n "$session_id" ]; then
    # Update the entry matching this session_id
    updated=$(jq \
        --arg sid "$session_id" \
        --arg stopped_at "$stopped_at" \
        --argjson tokens "$tokens_obj" \
        --arg status "$status" \
        --argjson exit_code "$exit_code" \
        '[.[] | if .session_id == $sid then
            .stopped_at = $stopped_at |
            .tokens = $tokens |
            .status = $status |
            .exit_code = $exit_code
        else . end]' <<< "$existing")
else
    # Fallback: update the last "running" entry matching this agent name
    updated=$(jq \
        --arg agent "$agent_name" \
        --arg stopped_at "$stopped_at" \
        --argjson tokens "$tokens_obj" \
        --arg status "$status" \
        --argjson exit_code "$exit_code" \
        'last(.[] | select(.agent_name == $agent and .status == "running")) as $target |
        if $target then
            [.[] | if (. == $target and .status == "running") then
                .stopped_at = $stopped_at |
                .tokens = $tokens |
                .status = $status |
                .exit_code = $exit_code
            else . end]
        else . end' <<< "$existing")
fi

# Write atomically using temp file
tmp_file="${usage_file}.tmp.$$"
echo "$updated" > "$tmp_file"
mv "$tmp_file" "$usage_file"

exit 0
