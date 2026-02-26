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
# initialize budget tracking, and create an empty session log.
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

    # Create budget.json with limits from config and zeroed counters
    initialize_budget

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

# ---------------------------------------------------------------------------
# Token Tracking & Budget
# ---------------------------------------------------------------------------

# Creates .automaton/budget.json with limits from config and zeroed usage.
# Called once during initialize(). On --resume, the existing file is kept.
initialize_budget() {
    local tmp="$AUTOMATON_DIR/budget.json.tmp"

    jq -n \
        --argjson max_tokens "$BUDGET_MAX_TOKENS" \
        --argjson max_usd "$BUDGET_MAX_USD" \
        --argjson phase_research "$BUDGET_PHASE_RESEARCH" \
        --argjson phase_plan "$BUDGET_PHASE_PLAN" \
        --argjson phase_build "$BUDGET_PHASE_BUILD" \
        --argjson phase_review "$BUDGET_PHASE_REVIEW" \
        --argjson per_iteration "$BUDGET_PER_ITERATION" \
        '{
            limits: {
                max_total_tokens: $max_tokens,
                max_cost_usd: $max_usd,
                per_phase: {
                    research: $phase_research,
                    plan: $phase_plan,
                    build: $phase_build,
                    review: $phase_review
                },
                per_iteration: $per_iteration
            },
            used: {
                total_input: 0,
                total_output: 0,
                total_cache_create: 0,
                total_cache_read: 0,
                by_phase: {
                    research: { input: 0, output: 0 },
                    plan: { input: 0, output: 0 },
                    build: { input: 0, output: 0 },
                    review: { input: 0, output: 0 }
                },
                estimated_cost_usd: 0.00
            },
            history: []
        }' > "$tmp"
    mv "$tmp" "$AUTOMATON_DIR/budget.json"
}

# Extracts token usage from Claude CLI stream-json output.
# Parses the final "type":"result" line for input, output, cache_create, cache_read.
# Sets global variables: LAST_INPUT_TOKENS, LAST_OUTPUT_TOKENS,
#   LAST_CACHE_CREATE, LAST_CACHE_READ
extract_tokens() {
    local result_output="$1"
    local usage_line
    usage_line=$(echo "$result_output" | grep '"type":"result"' | tail -1 || true)

    if [ -z "$usage_line" ]; then
        LAST_INPUT_TOKENS=0
        LAST_OUTPUT_TOKENS=0
        LAST_CACHE_CREATE=0
        LAST_CACHE_READ=0
        return
    fi

    LAST_INPUT_TOKENS=$(echo "$usage_line" | jq -r '.usage.input_tokens // 0')
    LAST_OUTPUT_TOKENS=$(echo "$usage_line" | jq -r '.usage.output_tokens // 0')
    LAST_CACHE_CREATE=$(echo "$usage_line" | jq -r '.usage.cache_creation_input_tokens // 0')
    LAST_CACHE_READ=$(echo "$usage_line" | jq -r '.usage.cache_read_input_tokens // 0')
}

# Returns estimated USD cost for a given model and token counts.
# Uses the pricing table from spec-07.
# Usage: cost=$(estimate_cost "sonnet" 112000 24000 5000 80000)
estimate_cost() {
    local model="$1"
    local input="${2:-0}" output="${3:-0}" cache_create="${4:-0}" cache_read="${5:-0}"

    local input_rate output_rate cache_write_rate cache_read_rate
    case "$model" in
        opus)
            input_rate=15.00
            output_rate=75.00
            cache_write_rate=18.75
            cache_read_rate=1.50
            ;;
        sonnet)
            input_rate=3.00
            output_rate=15.00
            cache_write_rate=3.75
            cache_read_rate=0.30
            ;;
        haiku)
            input_rate=0.80
            output_rate=4.00
            cache_write_rate=1.00
            cache_read_rate=0.08
            ;;
        *)
            input_rate=3.00
            output_rate=15.00
            cache_write_rate=3.75
            cache_read_rate=0.30
            ;;
    esac

    awk -v inp="$input" -v out="$output" -v cc="$cache_create" -v cr="$cache_read" \
        -v ir="$input_rate" -v or_rate="$output_rate" -v cwr="$cache_write_rate" -v crr="$cache_read_rate" \
        'BEGIN { printf "%.4f", (inp*ir + out*or_rate + cc*cwr + cr*crr) / 1000000 }'
}

# Adds iteration token usage to cumulative totals in budget.json.
# Appends a history entry and recalculates estimated_cost_usd.
# Uses atomic write to prevent corruption.
update_budget() {
    local model="$1" input_tokens="$2" output_tokens="$3"
    local cache_create="$4" cache_read="$5"
    local iter_cost="$6" duration="$7" task_desc="$8" status="$9"

    local budget_file="$AUTOMATON_DIR/budget.json"
    local tmp="$AUTOMATON_DIR/budget.json.tmp"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local total_iter_tokens=$((input_tokens + output_tokens))

    jq \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson cache_create "$cache_create" \
        --argjson cache_read "$cache_read" \
        --argjson iter_cost "$iter_cost" \
        --arg phase "$current_phase" \
        --argjson iteration "$iteration" \
        --arg model "$model" \
        --argjson duration "$duration" \
        --arg task "$task_desc" \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        '
        .used.total_input += $input_tokens |
        .used.total_output += $output_tokens |
        .used.total_cache_create += $cache_create |
        .used.total_cache_read += $cache_read |
        .used.by_phase[$phase].input += $input_tokens |
        .used.by_phase[$phase].output += $output_tokens |
        .used.estimated_cost_usd = ((.used.estimated_cost_usd + $iter_cost) * 100 | round / 100) |
        .history += [{
            iteration: $iteration,
            phase: $phase,
            model: $model,
            input_tokens: $input_tokens,
            output_tokens: $output_tokens,
            cache_create: $cache_create,
            cache_read: $cache_read,
            estimated_cost: $iter_cost,
            duration_seconds: $duration,
            task: $task,
            status: $status,
            timestamp: $timestamp
        }]
        ' "$budget_file" > "$tmp"
    mv "$tmp" "$budget_file"
}

# Enforces four budget rules after each iteration. Returns 0 to continue,
# 1 to force phase transition, or exits with code 2 for hard stops.
# Logs the appropriate message for each triggered rule.
check_budget() {
    local input_tokens="$1" output_tokens="$2"
    local budget_file="$AUTOMATON_DIR/budget.json"
    local total_iter_tokens=$((input_tokens + output_tokens))

    # Rule 1: Per-iteration warning (advisory only)
    if [ "$total_iter_tokens" -gt "$BUDGET_PER_ITERATION" ]; then
        log "ORCHESTRATOR" "WARNING: Iteration used ${total_iter_tokens} tokens, exceeding per-iteration limit of ${BUDGET_PER_ITERATION}"
    fi

    # Read cumulative totals from budget.json
    local total_input total_output total_cost
    total_input=$(jq '.used.total_input' "$budget_file")
    total_output=$(jq '.used.total_output' "$budget_file")
    total_cost=$(jq '.used.estimated_cost_usd' "$budget_file")
    local cumulative_tokens=$((total_input + total_output))

    # Rule 3: Total token hard stop (check before phase limit so hard stop takes priority)
    if [ "$cumulative_tokens" -gt "$BUDGET_MAX_TOKENS" ]; then
        log "ORCHESTRATOR" "Total token budget exhausted (${cumulative_tokens}/${BUDGET_MAX_TOKENS}). Run --resume after adjusting budget."
        write_state
        exit 2
    fi

    # Rule 4: Cost hard stop
    local cost_exceeded
    cost_exceeded=$(awk -v cost="$total_cost" -v limit="$BUDGET_MAX_USD" \
        'BEGIN { print (cost > limit) ? "yes" : "no" }')
    if [ "$cost_exceeded" = "yes" ]; then
        log "ORCHESTRATOR" "Cost budget exhausted (\$${total_cost}/\$${BUDGET_MAX_USD}). Run --resume after adjusting budget."
        write_state
        exit 2
    fi

    # Rule 2: Per-phase force transition
    local phase_limit_var="BUDGET_PHASE_$(echo "$current_phase" | tr '[:lower:]' '[:upper:]')"
    local phase_limit="${!phase_limit_var}"
    local phase_input phase_output
    phase_input=$(jq --arg p "$current_phase" '.used.by_phase[$p].input' "$budget_file")
    phase_output=$(jq --arg p "$current_phase" '.used.by_phase[$p].output' "$budget_file")
    local phase_tokens=$((phase_input + phase_output))

    if [ "$phase_tokens" -gt "$phase_limit" ]; then
        log "ORCHESTRATOR" "Phase budget exhausted for ${current_phase} (${phase_tokens}/${phase_limit}). Transitioning to next phase."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------

# Implements exponential backoff when a rate limit is detected.
# Retries the agent invocation up to 5 times with increasing delays.
# After 5 consecutive failures, saves state and pauses for 10 minutes.
#
# Usage: handle_rate_limit retry_function [args...]
#   The retry function must set AGENT_RESULT and AGENT_EXIT_CODE globals
#   and must not exit on failure (capture errors internally).
#
# Returns: 0 = successful retry, 1 = all retries exhausted
handle_rate_limit() {
    local delay="$RATE_COOLDOWN_SECONDS"

    for ((attempt = 1; attempt <= 5; attempt++)); do
        log "ORCHESTRATOR" "Rate limit detected. Backing off ${delay}s (attempt ${attempt}/5)"
        sleep "$delay"

        # Retry — the called function sets AGENT_RESULT and AGENT_EXIT_CODE
        "$@"

        if [ "${AGENT_EXIT_CODE:-1}" -eq 0 ]; then
            log "ORCHESTRATOR" "Rate limit retry succeeded."
            return 0
        fi

        # If the error is no longer rate-limit-related, stop retrying here
        if ! echo "${AGENT_RESULT:-}" | grep -qi 'rate_limit\|429\|overloaded\|rate limit'; then
            log "ORCHESTRATOR" "Retry failed with non-rate-limit error (exit ${AGENT_EXIT_CODE})."
            return 1
        fi

        # Exponential backoff capped at max_backoff_seconds
        delay=$(awk -v d="$delay" -v m="$RATE_BACKOFF_MULTIPLIER" -v cap="$RATE_MAX_BACKOFF_SECONDS" \
            'BEGIN { nd = int(d * m); print (nd > cap) ? cap : nd }')
    done

    # All 5 retries exhausted — enter extended pause
    log "ORCHESTRATOR" "Persistent rate limiting. Pausing for 10 minutes."
    write_state
    sleep 600

    return 1
}
