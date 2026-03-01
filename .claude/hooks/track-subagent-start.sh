#!/usr/bin/env bash
# track-subagent-start.sh — SubagentStart hook for automaton agents
# Records agent name and start timestamp to .automaton/subagent_usage.json
# WHY: Per-subagent token tracking enables accurate budget attribution across
# parallel builders. Start hook records the session ID for correlation with
# the stop hook. (spec-31 §5)
#
# Input: JSON on stdin with agent name, session_id
# Output: exit 0 always (SubagentStart hooks should not block)
#
# Environment:
#   AUTOMATON_PROJECT_ROOT — project root (fallback: CLAUDE_PROJECT_DIR, pwd)
#
# Performance target: <5 seconds (must not delay agent startup)

set -euo pipefail

# ---- Read hook input from stdin ----
input=$(cat)

# ---- Extract agent info (herestrings avoid pipe + subshell) ----
agent_name=$(jq -r '.agent_name // .name // "unknown"' <<< "$input" 2>/dev/null || echo "unknown")
session_id=$(jq -r '.session_id // .id // empty' <<< "$input" 2>/dev/null || true)

# Generate a session ID if none provided
if [ -z "$session_id" ]; then
    session_id="subagent-$(date +%s)-$$"
fi

# ---- Determine paths ----
project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
usage_file="$project_root/.automaton/subagent_usage.json"

mkdir -p "$(dirname "$usage_file")"

# ---- Read iteration and phase from state.json ----
state_file="$project_root/.automaton/state.json"
iteration=0
phase="unknown"
wave=0
if [ -f "$state_file" ]; then
    iteration=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null || echo 0)
    phase=$(jq -r '.phase // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
    wave=$(jq -r '.wave // 0' "$state_file" 2>/dev/null || echo 0)
fi

# ---- Build start entry ----
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

new_entry=$(jq -n \
    --arg session_id "$session_id" \
    --arg agent_name "$agent_name" \
    --arg started_at "$timestamp" \
    --argjson iteration "$iteration" \
    --arg phase "$phase" \
    --argjson wave "$wave" \
    '{
        session_id: $session_id,
        agent_name: $agent_name,
        started_at: $started_at,
        stopped_at: null,
        iteration: $iteration,
        phase: $phase,
        wave: $wave,
        tokens: null,
        status: "running"
    }')

# ---- Append to subagent_usage.json (with idempotency guard) ----
if [ -f "$usage_file" ]; then
    existing=$(jq '.' "$usage_file" 2>/dev/null || echo '[]')
    if ! jq -e 'type == "array"' <<< "$existing" >/dev/null 2>&1; then
        existing='[]'
    fi
    # Idempotency: skip if an entry with this session_id already exists
    already_exists=$(jq --arg sid "$session_id" \
        'any(.[]; .session_id == $sid)' <<< "$existing" 2>/dev/null || echo "false")
    if [ "$already_exists" = "true" ]; then
        exit 0
    fi
    updated=$(jq --argjson entry "$new_entry" '. + [$entry]' <<< "$existing")
else
    updated="[$new_entry]"
fi

# Write atomically using temp file
tmp_file="${usage_file}.tmp.$$"
echo "$updated" > "$tmp_file"
mv "$tmp_file" "$usage_file"

exit 0
