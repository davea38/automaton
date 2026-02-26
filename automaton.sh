#!/usr/bin/env bash
# automaton.sh — Multi-phase orchestrator for autonomous Claude agent workflows.
# This script manages phase transitions, spawns Claude agents, enforces budgets,
# handles errors, and persists state across the research → plan → build → review lifecycle.
set -euo pipefail

AUTOMATON_VERSION="0.1.0"
AUTOMATON_DIR=".automaton"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Reads automaton.config.json (or a caller-specified file) and populates shell
# variables with every config value.  Missing keys fall back to the spec-12
# defaults so that the config file itself is entirely optional.
load_config() {
    local config_file="${CONFIG_FILE:-automaton.config.json}"

    if [ -f "$config_file" ]; then
        CONFIG_FILE_USED="$config_file"

        # -- models --
        MODEL_PRIMARY=$(jq -r '.models.primary // "opus"' "$config_file")
        MODEL_RESEARCH=$(jq -r '.models.research // "sonnet"' "$config_file")
        MODEL_PLANNING=$(jq -r '.models.planning // "opus"' "$config_file")
        MODEL_BUILDING=$(jq -r '.models.building // "sonnet"' "$config_file")
        MODEL_REVIEW=$(jq -r '.models.review // "opus"' "$config_file")
        MODEL_SUBAGENT_DEFAULT=$(jq -r '.models.subagent_default // "sonnet"' "$config_file")

        # -- budget --
        BUDGET_MAX_TOKENS=$(jq -r '.budget.max_total_tokens // 10000000' "$config_file")
        BUDGET_MAX_USD=$(jq -r '.budget.max_cost_usd // 50' "$config_file")
        BUDGET_PHASE_RESEARCH=$(jq -r '.budget.per_phase.research // 500000' "$config_file")
        BUDGET_PHASE_PLAN=$(jq -r '.budget.per_phase.plan // 1000000' "$config_file")
        BUDGET_PHASE_BUILD=$(jq -r '.budget.per_phase.build // 7000000' "$config_file")
        BUDGET_PHASE_REVIEW=$(jq -r '.budget.per_phase.review // 1500000' "$config_file")
        BUDGET_PER_ITERATION=$(jq -r '.budget.per_iteration // 500000' "$config_file")

        # -- rate_limits --
        RATE_TOKENS_PER_MINUTE=$(jq -r '.rate_limits.tokens_per_minute // 80000' "$config_file")
        RATE_REQUESTS_PER_MINUTE=$(jq -r '.rate_limits.requests_per_minute // 50' "$config_file")
        RATE_COOLDOWN_SECONDS=$(jq -r '.rate_limits.cooldown_seconds // 60' "$config_file")
        RATE_BACKOFF_MULTIPLIER=$(jq -r '.rate_limits.backoff_multiplier // 2' "$config_file")
        RATE_MAX_BACKOFF_SECONDS=$(jq -r '.rate_limits.max_backoff_seconds // 300' "$config_file")

        # -- execution --
        EXEC_MAX_ITER_RESEARCH=$(jq -r '.execution.max_iterations.research // 3' "$config_file")
        EXEC_MAX_ITER_PLAN=$(jq -r '.execution.max_iterations.plan // 2' "$config_file")
        EXEC_MAX_ITER_BUILD=$(jq -r '.execution.max_iterations.build // 0' "$config_file")
        EXEC_MAX_ITER_REVIEW=$(jq -r '.execution.max_iterations.review // 2' "$config_file")
        EXEC_PARALLEL_BUILDERS=$(jq -r '.execution.parallel_builders // 1' "$config_file")
        EXEC_STALL_THRESHOLD=$(jq -r '.execution.stall_threshold // 3' "$config_file")
        EXEC_MAX_CONSECUTIVE_FAILURES=$(jq -r '.execution.max_consecutive_failures // 3' "$config_file")
        EXEC_RETRY_DELAY_SECONDS=$(jq -r '.execution.retry_delay_seconds // 10' "$config_file")
        EXEC_PHASE_TIMEOUT_RESEARCH=$(jq -r '.execution.phase_timeout_seconds.research // 0' "$config_file")
        EXEC_PHASE_TIMEOUT_PLAN=$(jq -r '.execution.phase_timeout_seconds.plan // 0' "$config_file")
        EXEC_PHASE_TIMEOUT_BUILD=$(jq -r '.execution.phase_timeout_seconds.build // 0' "$config_file")
        EXEC_PHASE_TIMEOUT_REVIEW=$(jq -r '.execution.phase_timeout_seconds.review // 0' "$config_file")

        # -- git --
        GIT_AUTO_PUSH=$(jq -r '.git.auto_push // true' "$config_file")
        GIT_AUTO_COMMIT=$(jq -r '.git.auto_commit // true' "$config_file")
        GIT_BRANCH_PREFIX=$(jq -r '.git.branch_prefix // "automaton/"' "$config_file")

        # -- flags --
        FLAG_DANGEROUSLY_SKIP_PERMISSIONS=$(jq -r '.flags.dangerously_skip_permissions // true' "$config_file")
        FLAG_VERBOSE=$(jq -r '.flags.verbose // true' "$config_file")
        FLAG_SKIP_RESEARCH=$(jq -r '.flags.skip_research // false' "$config_file")
        FLAG_SKIP_REVIEW=$(jq -r '.flags.skip_review // false' "$config_file")
    else
        CONFIG_FILE_USED="(defaults)"

        # -- models --
        MODEL_PRIMARY="opus"
        MODEL_RESEARCH="sonnet"
        MODEL_PLANNING="opus"
        MODEL_BUILDING="sonnet"
        MODEL_REVIEW="opus"
        MODEL_SUBAGENT_DEFAULT="sonnet"

        # -- budget --
        BUDGET_MAX_TOKENS=10000000
        BUDGET_MAX_USD=50
        BUDGET_PHASE_RESEARCH=500000
        BUDGET_PHASE_PLAN=1000000
        BUDGET_PHASE_BUILD=7000000
        BUDGET_PHASE_REVIEW=1500000
        BUDGET_PER_ITERATION=500000

        # -- rate_limits --
        RATE_TOKENS_PER_MINUTE=80000
        RATE_REQUESTS_PER_MINUTE=50
        RATE_COOLDOWN_SECONDS=60
        RATE_BACKOFF_MULTIPLIER=2
        RATE_MAX_BACKOFF_SECONDS=300

        # -- execution --
        EXEC_MAX_ITER_RESEARCH=3
        EXEC_MAX_ITER_PLAN=2
        EXEC_MAX_ITER_BUILD=0
        EXEC_MAX_ITER_REVIEW=2
        EXEC_PARALLEL_BUILDERS=1
        EXEC_STALL_THRESHOLD=3
        EXEC_MAX_CONSECUTIVE_FAILURES=3
        EXEC_RETRY_DELAY_SECONDS=10
        EXEC_PHASE_TIMEOUT_RESEARCH=0
        EXEC_PHASE_TIMEOUT_PLAN=0
        EXEC_PHASE_TIMEOUT_BUILD=0
        EXEC_PHASE_TIMEOUT_REVIEW=0

        # -- git --
        GIT_AUTO_PUSH="true"
        GIT_AUTO_COMMIT="true"
        GIT_BRANCH_PREFIX="automaton/"

        # -- flags --
        FLAG_DANGEROUSLY_SKIP_PERMISSIONS="true"
        FLAG_VERBOSE="true"
        FLAG_SKIP_RESEARCH="false"
        FLAG_SKIP_REVIEW="false"
    fi
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# Appends a timestamped line to session.log and echoes to stdout.
# Usage: log "COMPONENT" "message text"
log() {
    local component="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local line="[$timestamp] [$component] $message"
    echo "$line" >> "$AUTOMATON_DIR/session.log"
    echo "$line"
}

# ---------------------------------------------------------------------------
# State Management
# ---------------------------------------------------------------------------

# Atomic write of state.json using temp-file-then-mv.
# Reads from global shell variables set during execution.
write_state() {
    local tmp="$AUTOMATON_DIR/state.json.tmp"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local rf_value
    if [ "$resumed_from" = "null" ]; then
        rf_value="null"
    else
        rf_value="\"$resumed_from\""
    fi

    cat > "$tmp" <<EOF
{
  "version": "$AUTOMATON_VERSION",
  "phase": "$current_phase",
  "iteration": $iteration,
  "phase_iteration": $phase_iteration,
  "stall_count": $stall_count,
  "consecutive_failures": $consecutive_failures,
  "corruption_count": $corruption_count,
  "replan_count": $replan_count,
  "started_at": "$started_at",
  "last_iteration_at": "$now",
  "parallel_builders": ${EXEC_PARALLEL_BUILDERS:-1},
  "resumed_from": $rf_value,
  "phase_history": ${phase_history:-[]}
}
EOF
    mv "$tmp" "$AUTOMATON_DIR/state.json"
}

# Restore shell variables from a saved state.json for --resume.
# Resets consecutive_failures to 0 (human presumably fixed the issue).
read_state() {
    local state_file="$AUTOMATON_DIR/state.json"
    if [ ! -f "$state_file" ]; then
        echo "Error: No state to resume from. Run without --resume."
        exit 1
    fi
    local state
    state=$(cat "$state_file")
    current_phase=$(echo "$state" | jq -r '.phase')
    iteration=$(echo "$state" | jq '.iteration')
    phase_iteration=$(echo "$state" | jq '.phase_iteration')
    stall_count=$(echo "$state" | jq '.stall_count')
    consecutive_failures=0
    corruption_count=$(echo "$state" | jq '.corruption_count')
    replan_count=$(echo "$state" | jq '.replan_count')
    started_at=$(echo "$state" | jq -r '.started_at')
    resumed_from=$(echo "$state" | jq -r '.last_iteration_at')
    phase_history=$(echo "$state" | jq -c '.phase_history')
}

# First-run initialization: create .automaton/ structure, write initial state,
# and create an empty session log.
# Note: initialize_budget() is called separately once budget module is wired in.
initialize() {
    mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/worktrees" "$AUTOMATON_DIR/inbox"

    # Set initial state variables
    current_phase="research"
    iteration=0
    phase_iteration=0
    stall_count=0
    consecutive_failures=0
    corruption_count=0
    replan_count=0
    started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    resumed_from="null"
    phase_history="[]"

    # Write initial state.json via atomic write
    write_state

    # Create empty session.log (log() appends to this)
    : > "$AUTOMATON_DIR/session.log"

    log "ORCHESTRATOR" "Initialized $AUTOMATON_DIR/ directory"
}

# ---------------------------------------------------------------------------
# Agent History
# ---------------------------------------------------------------------------

# Write per-agent iteration history to .automaton/agents/{phase}-{NNN}.json.
# Uses jq for proper JSON escaping of free-text fields (e.g. task description).
# Args: model prompt_file start end duration exit_code
#       input_tokens output_tokens cache_create cache_read
#       cost task status files_changed_json git_commit
write_agent_history() {
    local model="$1" prompt_file="$2" agent_start="$3" agent_end="$4"
    local duration="$5" exit_code="$6"
    local input_tokens="${7:-0}" output_tokens="${8:-0}"
    local cache_create="${9:-0}" cache_read="${10:-0}"
    local cost="${11:-0}" task_desc="${12:-}" status="${13:-unknown}"
    local files_changed="${14:-[]}" git_commit="${15:-null}"

    local padded
    padded=$(printf "%03d" "$phase_iteration")
    local filename="$AUTOMATON_DIR/agents/${current_phase}-${padded}.json"

    jq -n \
        --arg phase "$current_phase" \
        --argjson iteration "$phase_iteration" \
        --arg model "$model" \
        --arg prompt_file "$prompt_file" \
        --arg started_at "$agent_start" \
        --arg completed_at "$agent_end" \
        --argjson duration "$duration" \
        --argjson exit_code "$exit_code" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson cache_create "$cache_create" \
        --argjson cache_read "$cache_read" \
        --argjson cost "$cost" \
        --arg task "$task_desc" \
        --arg status "$status" \
        --argjson files_changed "$files_changed" \
        --arg git_commit "$git_commit" \
        '{
            phase: $phase,
            iteration: $iteration,
            model: $model,
            prompt_file: $prompt_file,
            started_at: $started_at,
            completed_at: $completed_at,
            duration_seconds: $duration,
            exit_code: $exit_code,
            tokens: {
                input: $input_tokens,
                output: $output_tokens,
                cache_create: $cache_create,
                cache_read: $cache_read
            },
            estimated_cost: $cost,
            task: $task,
            status: $status,
            files_changed: $files_changed,
            git_commit: (if $git_commit == "null" then null else $git_commit end)
        }' > "$filename"
}
