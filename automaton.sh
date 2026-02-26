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

# Proactive pacing: calculates token velocity over the last 3 iterations from
# budget.json history and sleeps if velocity exceeds 80% of tokens_per_minute.
# This avoids rate limits by slowing down before hitting them.
# When parallel_builders > 1, the per-builder share of TPM is used as the limit.
#
# Returns: 0 always (pacing is advisory, never fatal)
check_pacing() {
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ ! -f "$budget_file" ]; then
        return 0
    fi

    local history_len
    history_len=$(jq '.history | length' "$budget_file")
    if [ "$history_len" -lt 1 ]; then
        return 0
    fi

    # Use last 3 iterations (or fewer if not enough history)
    local window=3
    if [ "$history_len" -lt "$window" ]; then
        window="$history_len"
    fi

    # Sum tokens and duration over the window
    local recent
    recent=$(jq --argjson w "$window" '
        .history[-$w:] |
        {
            tokens: (map(.input_tokens + .output_tokens) | add),
            duration: (map(.duration_seconds) | add)
        }
    ' "$budget_file")

    local recent_tokens recent_duration
    recent_tokens=$(echo "$recent" | jq '.tokens')
    recent_duration=$(echo "$recent" | jq '.duration')

    # Guard against zero/null duration (avoid division by zero)
    if [ -z "$recent_duration" ] || [ "$recent_duration" = "null" ] || [ "$recent_duration" = "0" ]; then
        return 0
    fi

    # Adjust limit for parallel builders
    local effective_tpm="$RATE_TOKENS_PER_MINUTE"
    if [ "${EXEC_PARALLEL_BUILDERS:-1}" -gt 1 ]; then
        effective_tpm=$((RATE_TOKENS_PER_MINUTE / EXEC_PARALLEL_BUILDERS))
    fi

    # Calculate velocity and 80% threshold using awk for floating-point math
    local should_pace cooldown_secs velocity_display
    read -r should_pace cooldown_secs velocity_display < <(
        awk -v tokens="$recent_tokens" -v dur="$recent_duration" \
            -v tpm="$effective_tpm" \
            'BEGIN {
                velocity = tokens * 60 / dur
                threshold = tpm * 0.80
                if (velocity > threshold) {
                    # Time needed to consume these tokens at the TPM limit
                    needed = tokens * 60 / tpm
                    cooldown = needed - dur
                    if (cooldown < 1) cooldown = 1
                    printf "yes %.0f %.0f\n", cooldown, velocity
                } else {
                    printf "no 0 %.0f\n", velocity
                }
            }'
    )

    if [ "$should_pace" = "yes" ]; then
        log "ORCHESTRATOR" "Proactive pacing: velocity ${velocity_display} TPM, waiting ${cooldown_secs}s."
        sleep "$cooldown_secs"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Error Handling & Recovery
# ---------------------------------------------------------------------------

# Handles a CLI crash (non-zero exit that is NOT a rate limit or network error).
# Increments consecutive_failures counter, sleeps for retry_delay, and returns 0
# to signal "retry this iteration". If max consecutive failures is reached, saves
# state and exits with code 1 (resumable).
#
# The caller is responsible for classifying the error first (is_rate_limit /
# is_network_error) and only calling this function for unclassified CLI failures.
#
# Usage: handle_cli_crash exit_code [agent_output]
# Returns: 0 = retry the iteration
# Exits:   1 = max consecutive failures reached (state saved for --resume)
handle_cli_crash() {
    local exit_code="$1"
    local agent_output="${2:-}"

    consecutive_failures=$((consecutive_failures + 1))
    log "ORCHESTRATOR" "CLI error (exit $exit_code), attempt $consecutive_failures/$EXEC_MAX_CONSECUTIVE_FAILURES"

    if [ "$consecutive_failures" -ge "$EXEC_MAX_CONSECUTIVE_FAILURES" ]; then
        log "ORCHESTRATOR" "Max consecutive failures reached ($EXEC_MAX_CONSECUTIVE_FAILURES). Saving state."
        write_state
        exit 1
    fi

    log "ORCHESTRATOR" "Retrying in ${EXEC_RETRY_DELAY_SECONDS}s..."
    sleep "$EXEC_RETRY_DELAY_SECONDS"
    return 0
}

# Resets the consecutive failure counter after a successful agent iteration.
# Should be called at the end of every successful iteration so that subsequent
# failures start counting from zero. Only logs when recovering from prior failures.
#
# Usage: reset_failure_count
reset_failure_count() {
    if [ "$consecutive_failures" -gt 0 ]; then
        log "ORCHESTRATOR" "Recovered after $consecutive_failures failure(s). Resetting counter."
    fi
    consecutive_failures=0
}

# Classifies whether agent output indicates an API rate limit error.
# Checks for known Anthropic rate limit signatures in the output text.
# Usage: if is_rate_limit "$agent_output"; then ...
# Returns: 0 if rate limit detected, 1 otherwise
is_rate_limit() {
    local output="${1:-}"
    echo "$output" | grep -qi 'rate_limit\|rate limit\|429\|overloaded'
}

# Classifies whether agent output indicates a network/connectivity error.
# Checks for known network failure signatures in the output text.
# Usage: if is_network_error "$agent_output"; then ...
# Returns: 0 if network error detected, 1 otherwise
is_network_error() {
    local output="${1:-}"
    echo "$output" | grep -qi 'network\|connection\|timeout\|ECONNREFUSED\|ETIMEDOUT\|ENOTFOUND\|EHOSTUNREACH\|getaddrinfo'
}

# Plan corruption guard: checkpoint IMPLEMENTATION_PLAN.md before each iteration
# so we can detect if an agent rewrites the plan and destroys completed work.
# Sets PLAN_CHECKPOINT_COMPLETED_COUNT for post-iteration comparison.
#
# Usage: checkpoint_plan   (call before each iteration)
checkpoint_plan() {
    if [ ! -f "IMPLEMENTATION_PLAN.md" ]; then
        PLAN_CHECKPOINT_COMPLETED_COUNT=0
        return 0
    fi

    cp IMPLEMENTATION_PLAN.md "$AUTOMATON_DIR/plan_checkpoint.md"
    PLAN_CHECKPOINT_COMPLETED_COUNT=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
}

# Plan corruption guard: verify that the [x] count did not decrease after an
# iteration. If it did, the agent rewrote the plan and lost completed tasks —
# restore from the pre-iteration checkpoint.
#
# After 2 corruption events, escalates to human (exit 3).
#
# Usage: check_plan_integrity   (call after each iteration)
# Returns: 0 = plan is intact or was restored successfully
# Exits:   3 via escalate() if corruption_count reaches 2
check_plan_integrity() {
    if [ ! -f "IMPLEMENTATION_PLAN.md" ]; then
        return 0
    fi

    local completed_after
    completed_after=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)

    if [ "$completed_after" -lt "$PLAN_CHECKPOINT_COMPLETED_COUNT" ]; then
        log "ORCHESTRATOR" "PLAN CORRUPTION: completed count dropped from $PLAN_CHECKPOINT_COMPLETED_COUNT to $completed_after"

        # Restore from checkpoint
        cp "$AUTOMATON_DIR/plan_checkpoint.md" IMPLEMENTATION_PLAN.md
        git add IMPLEMENTATION_PLAN.md 2>/dev/null || true
        git commit -m "automaton: restore plan from corruption" 2>/dev/null || true
        log "ORCHESTRATOR" "Plan restored from checkpoint."

        corruption_count=$((corruption_count + 1))
        if [ "$corruption_count" -ge 2 ]; then
            escalate "Plan corruption detected twice. Agent may be rewriting the plan."
            # escalate() exits — control never reaches here
        fi
    fi

    return 0
}

# Stall detection: checks whether the last build iteration produced any code
# changes by inspecting `git diff --stat HEAD~1`. If the diff is empty, the
# agent claimed progress without modifying files — a "stall".
#
# After stall_threshold consecutive stalls, forces a re-plan (return 1).
# After 2 re-plans that still lead to stalls, escalates to human (exit 3).
# Resets stall_count on any detected change.
#
# Usage: check_stall
# Returns: 0 = continue normally, 1 = force re-plan (transition to plan phase)
# Exits:   3 via escalate() if re-planning has failed twice
check_stall() {
    local diff_stat
    diff_stat=$(git diff --stat HEAD~1 2>/dev/null || true)

    if [ -z "$diff_stat" ]; then
        stall_count=$((stall_count + 1))
        log "ORCHESTRATOR" "Stall detected ($stall_count/$EXEC_STALL_THRESHOLD). No code changes."
    else
        stall_count=0
        return 0
    fi

    if [ "$stall_count" -ge "$EXEC_STALL_THRESHOLD" ]; then
        # Check if we've already re-planned too many times
        if [ "$replan_count" -ge 2 ]; then
            escalate "Agent stalled after $replan_count re-plans. Manual intervention required."
            # escalate() exits — control never reaches here
        fi

        log "ORCHESTRATOR" "$EXEC_STALL_THRESHOLD consecutive stalls. Forcing re-plan."
        stall_count=0
        replan_count=$((replan_count + 1))
        return 1
    fi

    return 0
}

# Escalation: when automated recovery fails, stop cleanly and hand off to human.
# Logs the escalation, marks it in IMPLEMENTATION_PLAN.md for visibility,
# saves state, commits everything, and exits with code 3.
#
# Usage: escalate "description of what went wrong"
# Exits: always exits with code 3 (human intervention required)
escalate() {
    local description="$1"
    log "ORCHESTRATOR" "ESCALATION: $description"

    # Mark the escalation in the plan file for human visibility
    {
        echo ""
        echo "## ESCALATION"
        echo ""
        echo "ESCALATION: $description"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Phase: $current_phase, Iteration: $iteration"
    } >> IMPLEMENTATION_PLAN.md

    # Persist current state for --resume
    write_state

    # Commit state and plan so no work is lost on exit
    git add IMPLEMENTATION_PLAN.md "$AUTOMATON_DIR/state.json" "$AUTOMATON_DIR/session.log" "$AUTOMATON_DIR/budget.json" 2>/dev/null || true
    git commit -m "automaton: escalation - $description" 2>/dev/null || true

    exit 3
}

# ---------------------------------------------------------------------------
# Quality Gates
# ---------------------------------------------------------------------------

# Uniform gate invocation wrapper. Calls the named gate function (gate_$name),
# logs PASS/FAIL, and returns the gate's exit code. The orchestrator uses this
# at every phase transition to enforce quality requirements.
#
# Usage: gate_check "spec_completeness"
# Returns: 0 if gate passes, 1 if gate fails
gate_check() {
    local gate_name="$1"
    log "ORCHESTRATOR" "Gate: $gate_name..."

    if "gate_$gate_name"; then
        log "ORCHESTRATOR" "Gate: $gate_name... PASS"
        return 0
    else
        log "ORCHESTRATOR" "Gate: $gate_name... FAIL"
        return 1
    fi
}

# Gate 1: Spec Completeness — runs before Phase 1 (research).
# Validates that the conversation phase produced usable specs:
#   - At least one spec file in specs/
#   - PRD.md exists and is non-empty
#   - AGENTS.md does not still contain the template placeholder
#
# On fail: orchestrator should refuse to start autonomous work.
# Returns: 0 (pass) or 1 (fail)
gate_spec_completeness() {
    local pass=true

    # Check: at least one spec file exists
    if ! ls specs/*.md >/dev/null 2>&1; then
        log "ORCHESTRATOR" "  FAIL: No spec files found in specs/"
        pass=false
    fi

    # Check: PRD.md exists and is non-empty
    if [ ! -s "PRD.md" ]; then
        log "ORCHESTRATOR" "  FAIL: PRD.md missing or empty"
        pass=false
    fi

    # Check: AGENTS.md has a real project name (not the template placeholder)
    if grep -q "(to be determined)" AGENTS.md 2>/dev/null; then
        log "ORCHESTRATOR" "  FAIL: AGENTS.md still has placeholder project name"
        pass=false
    fi

    $pass
}

# Gate 2: Research Completeness — runs after Phase 1 (research).
# Validates that research enriched the specs and resolved unknowns:
#   - AGENTS.md grew beyond the ~22-line template (warning only)
#   - No TBD/TODO markers remaining in specs/ (hard fail)
#
# On fail: orchestrator should retry research (up to max iterations),
# then warn and continue to planning if max reached.
# Returns: 0 (pass) or 1 (fail)
gate_research_completeness() {
    local pass=true
    local warnings=0

    # Check: AGENTS.md was updated (grew from template size)
    local agents_lines
    agents_lines=$(wc -l < AGENTS.md)
    if [ "$agents_lines" -le 22 ]; then  # template is ~22 lines
        log "ORCHESTRATOR" "  WARN: AGENTS.md unchanged from template"
        warnings=$((warnings + 1))
    fi

    # Check: no TBD/TODO remaining in specs
    local tbds
    tbds=$(grep -ri 'TBD\|TODO' specs/ 2>/dev/null | wc -l)
    if [ "$tbds" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: $tbds TBD/TODO markers remaining in specs"
        pass=false
    fi

    $pass
}

# Gate 3: Plan Validity — runs after Phase 2 (plan).
# Validates that the planning phase produced a usable task list:
#   - At least 5 unchecked tasks in IMPLEMENTATION_PLAN.md
#   - Plan is longer than 10 lines
#   - Tasks reference specs (heuristic, warning only)
#
# On fail: orchestrator should retry planning (up to max iterations),
# then escalate if max reached.
# Returns: 0 (pass) or 1 (fail)
gate_plan_validity() {
    local pass=true

    # Check: at least 5 unchecked tasks
    local unchecked
    unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$unchecked" -lt 5 ]; then
        log "ORCHESTRATOR" "  FAIL: Only $unchecked unchecked tasks (minimum 5)"
        pass=false
    fi

    # Check: plan is non-trivial
    local plan_lines
    plan_lines=$(wc -l < IMPLEMENTATION_PLAN.md)
    if [ "$plan_lines" -le 10 ]; then
        log "ORCHESTRATOR" "  FAIL: Plan too short ($plan_lines lines)"
        pass=false
    fi

    # Check: tasks reference specs (heuristic, warning only)
    local spec_refs
    spec_refs=$(grep -ci 'spec' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$spec_refs" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No spec references found in plan"
        # Warning only, don't fail
    fi

    $pass
}

# Gate 4: Build Completion — runs after Phase 3 (build).
# Validates that all tasks are complete and code was actually produced:
#   - Zero unchecked tasks in IMPLEMENTATION_PLAN.md (hard fail)
#   - Git commits exist during the run (warning only)
#   - Test files exist (warning only)
#
# On fail: orchestrator should continue building (return to build loop).
# Returns: 0 (pass) or 1 (fail)
gate_build_completion() {
    local pass=true

    # Check: all tasks complete
    local unchecked
    unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$unchecked" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: $unchecked tasks still incomplete"
        pass=false
    fi

    # Check: code changes exist (uses run_started_at set by orchestrator)
    local total_changes
    total_changes=$(git log --oneline --since="${run_started_at:-1970-01-01}" | wc -l)
    if [ "$total_changes" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No git commits during build phase"
    fi

    # Check: tests exist (heuristic)
    local test_files
    test_files=$(find . -name "*test*" -o -name "*spec*" | grep -v node_modules | grep -v .automaton | wc -l)
    if [ "$test_files" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No test files found"
    fi

    $pass
}

# Gate 5: Review Pass — runs after Phase 4 (review).
# Validates that the review agent found no remaining issues:
#   - No unchecked tasks in IMPLEMENTATION_PLAN.md (reviewer may have added new ones)
#   - No ESCALATION markers in IMPLEMENTATION_PLAN.md
#
# On fail: orchestrator should return to Phase 3 (build) to address new tasks.
# After 2 review iterations that both fail, escalate.
# Returns: 0 (pass) or 1 (fail)
gate_review_pass() {
    local pass=true

    # Check: no new unchecked tasks were added by reviewer
    local unchecked
    unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$unchecked" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: Review created $unchecked new tasks"
        pass=false
    fi

    # Check: no ESCALATION markers
    if grep -q 'ESCALATION:' IMPLEMENTATION_PLAN.md 2>/dev/null; then
        log "ORCHESTRATOR" "  FAIL: Escalation marker found"
        pass=false
    fi

    $pass
}

# ---------------------------------------------------------------------------
# Phase Timeout
# ---------------------------------------------------------------------------

# Optional phase timeout check: compares elapsed wallclock time against
# phase_timeout_seconds from config. If the timeout is exceeded, logs
# the event and returns 1 to signal the orchestrator to force a phase
# transition. A timeout of 0 means "no timeout" (the default).
#
# Requires PHASE_START_TIME to be set (epoch seconds) when a phase begins.
#
# Usage: check_phase_timeout
# Returns: 0 = within time limit, 1 = timeout exceeded
check_phase_timeout() {
    # Look up the timeout for the current phase
    local timeout_var="EXEC_PHASE_TIMEOUT_$(echo "$current_phase" | tr '[:lower:]' '[:upper:]')"
    local timeout="${!timeout_var:-0}"

    # 0 means no timeout configured
    if [ "$timeout" -eq 0 ] 2>/dev/null; then
        return 0
    fi

    # PHASE_START_TIME must be set by the orchestrator when entering a phase
    if [ -z "${PHASE_START_TIME:-}" ]; then
        return 0
    fi

    local now elapsed
    now=$(date +%s)
    elapsed=$((now - PHASE_START_TIME))

    if [ "$elapsed" -ge "$timeout" ]; then
        log "ORCHESTRATOR" "Phase timeout: ${current_phase} exceeded ${timeout}s (elapsed: ${elapsed}s). Forcing transition."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Agent Invocation
# ---------------------------------------------------------------------------

# Centralized agent invocation. Pipes the given prompt file into `claude -p`
# with stream-json output, the specified model, and configured flags.
# Captures all output and the exit code in global variables for downstream
# processing (token extraction, error classification, budget tracking).
#
# Sets global variables:
#   AGENT_RESULT    — full output from the agent (stream-json lines + stderr)
#   AGENT_EXIT_CODE — the claude CLI exit code (0 = success)
#
# Always returns 0 so callers can safely use this with set -e and as the
# retry function for handle_rate_limit(). Check AGENT_EXIT_CODE for the
# actual result.
#
# Usage: run_agent "PROMPT_research.md" "sonnet"
run_agent() {
    local prompt_file="$1"
    local model="$2"

    if [ ! -f "$prompt_file" ]; then
        log "ORCHESTRATOR" "ERROR: Prompt file not found: $prompt_file"
        AGENT_RESULT=""
        AGENT_EXIT_CODE=1
        return 0
    fi

    local cmd_args=("-p" "--output-format" "stream-json" "--model" "$model")

    if [ "$FLAG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
        cmd_args+=("--dangerously-skip-permissions")
    fi

    if [ "$FLAG_VERBOSE" = "true" ]; then
        cmd_args+=("--verbose")
    fi

    log "ORCHESTRATOR" "Invoking agent: model=$model prompt=$prompt_file"

    AGENT_RESULT=""
    AGENT_EXIT_CODE=0

    # Capture stdout (stream-json) and stderr (errors, verbose logs) together.
    # extract_tokens() greps for "type":"result" lines so stderr noise is harmless.
    # Error classifiers (is_rate_limit, is_network_error) need stderr to detect failures.
    AGENT_RESULT=$(cat "$prompt_file" | claude "${cmd_args[@]}" 2>&1) || AGENT_EXIT_CODE=$?

    log "ORCHESTRATOR" "Agent finished: exit_code=$AGENT_EXIT_CODE"

    return 0
}

# ---------------------------------------------------------------------------
# CLI Argument Parsing & Main Entry Point
# ---------------------------------------------------------------------------

# Defaults for CLI flags (may be overridden by arguments below)
ARG_RESUME=false
ARG_SKIP_RESEARCH=false
ARG_SKIP_REVIEW=false
ARG_CONFIG_FILE=""
ARG_DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --resume)
            ARG_RESUME=true
            shift
            ;;
        --skip-research)
            ARG_SKIP_RESEARCH=true
            shift
            ;;
        --skip-review)
            ARG_SKIP_REVIEW=true
            shift
            ;;
        --config)
            if [ -z "${2:-}" ]; then
                echo "Error: --config requires a file path argument." >&2
                exit 1
            fi
            if [ ! -f "$2" ]; then
                echo "Error: Config file not found: $2" >&2
                exit 1
            fi
            ARG_CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            ARG_DRY_RUN=true
            shift
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: automaton.sh [OPTIONS]

Multi-phase orchestrator for autonomous Claude agent workflows.

Options:
  --resume          Resume from saved state (.automaton/state.json)
  --skip-research   Skip Phase 1 (research), start at Phase 2 (plan)
  --skip-review     Skip Phase 4 (review), mark COMPLETE after build
  --config FILE     Use an alternate config file (default: automaton.config.json)
  --dry-run         Load config, run Gate 1, show settings, then exit
  --help, -h        Show this help message

Exit codes:
  0   All phases complete, review passed
  1   General error or max consecutive failures
  2   Budget exhausted (resumable with --resume)
  3   Escalation required (human intervention needed)
  130 Interrupted by user (resumable with --resume)
USAGE
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Run './automaton.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

# --- Apply --config before loading configuration ---
if [ -n "$ARG_CONFIG_FILE" ]; then
    CONFIG_FILE="$ARG_CONFIG_FILE"
fi

# --- Load configuration (uses CONFIG_FILE if set, else automaton.config.json) ---
load_config

# --- Override config flags with CLI arguments ---
if [ "$ARG_SKIP_RESEARCH" = "true" ]; then
    FLAG_SKIP_RESEARCH="true"
fi
if [ "$ARG_SKIP_REVIEW" = "true" ]; then
    FLAG_SKIP_REVIEW="true"
fi

# ---------------------------------------------------------------------------
# Phase Sequence Controller
# ---------------------------------------------------------------------------

# Returns the prompt file for a given phase.
get_phase_prompt() {
    case "$1" in
        research) echo "PROMPT_research.md" ;;
        plan)     echo "PROMPT_plan.md" ;;
        build)    echo "PROMPT_build.md" ;;
        review)   echo "PROMPT_review.md" ;;
    esac
}

# Returns the configured model for a given phase.
get_phase_model() {
    case "$1" in
        research) echo "$MODEL_RESEARCH" ;;
        plan)     echo "$MODEL_PLANNING" ;;
        build)    echo "$MODEL_BUILDING" ;;
        review)   echo "$MODEL_REVIEW" ;;
    esac
}

# Returns max iterations for a given phase (0 = unlimited).
get_phase_max_iterations() {
    case "$1" in
        research) echo "$EXEC_MAX_ITER_RESEARCH" ;;
        plan)     echo "$EXEC_MAX_ITER_PLAN" ;;
        build)    echo "$EXEC_MAX_ITER_BUILD" ;;
        review)   echo "$EXEC_MAX_ITER_REVIEW" ;;
    esac
}

# Checks whether the agent output contains the COMPLETE signal.
agent_signaled_complete() {
    echo "$AGENT_RESULT" | grep -q 'COMPLETE</promise>'
}

# Emits a one-line inter-iteration status per spec-01 format.
emit_status_line() {
    local model="$1" iter_cost="$2"
    local phase_upper max_iter iter_display remaining_budget

    phase_upper=$(echo "$current_phase" | tr '[:lower:]' '[:upper:]')
    max_iter=$(get_phase_max_iterations "$current_phase")

    if [ "$max_iter" -eq 0 ]; then
        iter_display="${phase_iteration}"
    else
        iter_display="${phase_iteration}/${max_iter}"
    fi

    remaining_budget=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
        "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")

    echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ${LAST_INPUT_TOKENS:-0} input / ${LAST_OUTPUT_TOKENS:-0} output (~\$${iter_cost}) | budget: \$${remaining_budget} remaining"
}

# Set by post_iteration to communicate why a forced phase transition occurred.
# Values: "" (normal), "budget" (phase budget exceeded), "stall" (re-plan needed)
TRANSITION_REASON=""

# Post-iteration pipeline: runs after every agent invocation. Extracts tokens,
# updates budget, checks limits, detects stalls/corruption, writes state/history,
# emits status, and pushes to git if configured.
#
# Args: model prompt_file iter_start_epoch
# Returns: 0 = continue normally, 1 = force phase transition (see TRANSITION_REASON)
post_iteration() {
    local model="$1" prompt_file="$2" iter_start_epoch="$3"
    local iter_end_epoch duration
    iter_end_epoch=$(date +%s)
    duration=$((iter_end_epoch - iter_start_epoch))
    TRANSITION_REASON=""

    # 1. Extract tokens from stream-json output
    extract_tokens "$AGENT_RESULT"

    # 2. Estimate cost for this iteration
    local iter_cost
    iter_cost=$(estimate_cost "$model" "$LAST_INPUT_TOKENS" "$LAST_OUTPUT_TOKENS" \
        "$LAST_CACHE_CREATE" "$LAST_CACHE_READ")

    # 3. Task description and status
    local task_desc status
    task_desc="${current_phase} iteration ${phase_iteration}"
    if [ "$AGENT_EXIT_CODE" -eq 0 ]; then
        status="success"
    else
        status="error"
    fi

    # 4. Update budget tracking
    update_budget "$model" "$LAST_INPUT_TOKENS" "$LAST_OUTPUT_TOKENS" \
        "$LAST_CACHE_CREATE" "$LAST_CACHE_READ" \
        "$iter_cost" "$duration" "$task_desc" "$status"

    # 5. Check budget limits (may exit 2 for hard stops, return 1 for phase force)
    local budget_rc=0
    check_budget "$LAST_INPUT_TOKENS" "$LAST_OUTPUT_TOKENS" || budget_rc=$?

    # 6. Proactive pacing (may sleep to avoid rate limits)
    check_pacing

    # 7. Build-phase-only: stall detection and plan corruption guard
    local stall_rc=0
    if [ "$current_phase" = "build" ]; then
        check_stall || stall_rc=$?
        check_plan_integrity
    fi

    # 8. Persist state
    write_state

    # 9. Write per-agent history file
    local agent_start_ts agent_end_ts files_changed git_commit
    agent_start_ts=$(date -u -d "@$iter_start_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    agent_end_ts=$(date -u -d "@$iter_end_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    files_changed=$(git diff --name-only HEAD~1 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')
    git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "null")

    write_agent_history "$model" "$prompt_file" "$agent_start_ts" "$agent_end_ts" \
        "$duration" "$AGENT_EXIT_CODE" \
        "$LAST_INPUT_TOKENS" "$LAST_OUTPUT_TOKENS" \
        "$LAST_CACHE_CREATE" "$LAST_CACHE_READ" \
        "$iter_cost" "$task_desc" "$status" "$files_changed" "$git_commit"

    # 10. Emit one-line status to stdout
    emit_status_line "$model" "$iter_cost"

    # 11. Git push if configured
    if [ "${GIT_AUTO_PUSH:-false}" = "true" ]; then
        git push 2>/dev/null || log "ORCHESTRATOR" "WARN: git push failed"
    fi

    # Signal forced transition if needed
    if [ "$stall_rc" -ne 0 ]; then
        TRANSITION_REASON="stall"
        return 1
    fi
    if [ "$budget_rc" -ne 0 ]; then
        TRANSITION_REASON="budget"
        return 1
    fi
    return 0
}

# Records a completed phase in phase_history and transitions to a new one.
transition_to_phase() {
    local new_phase="$1"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    phase_history=$(echo "$phase_history" | jq -c \
        --arg p "$current_phase" --arg t "$now" \
        '. + [{"phase": $p, "completed_at": $t}]')

    current_phase="$new_phase"
    phase_iteration=0
    PHASE_START_TIME=$(date +%s)

    log "ORCHESTRATOR" "Phase transition → $new_phase"
    write_state
}

# Main orchestration loop: drives the research → plan → build → review
# phase sequence with gate checks at every transition, error recovery,
# budget enforcement, stall detection, and the review→build feedback loop.
run_orchestration() {
    # --- Gate 1: specs must exist before autonomous work ---
    if ! gate_check "spec_completeness"; then
        echo "Gate 1 (spec completeness) failed. Run the conversation phase first."
        exit 1
    fi

    # --- Determine starting state (fresh or resumed) ---
    if [ "$ARG_RESUME" = "true" ]; then
        read_state
        log "ORCHESTRATOR" "RESUMED: phase=$current_phase iteration=$iteration"
    else
        initialize
        if [ "$FLAG_SKIP_RESEARCH" = "true" ]; then
            current_phase="plan"
            log "ORCHESTRATOR" "Skipping research (--skip-research)"
        fi
    fi

    # Used by gate_build_completion to check for commits during this run
    run_started_at="$started_at"
    PHASE_START_TIME=$(date +%s)
    log "ORCHESTRATOR" "Starting: phase=$current_phase"

    # Track review iterations for the review→build feedback loop (spec-06)
    local review_attempts=0

    # === Outer phase loop ===
    while [ "$current_phase" != "COMPLETE" ]; do
        local prompt_file model max_iter
        prompt_file=$(get_phase_prompt "$current_phase")
        model=$(get_phase_model "$current_phase")
        max_iter=$(get_phase_max_iterations "$current_phase")

        # Handle --skip-review
        if [ "$current_phase" = "review" ] && [ "$FLAG_SKIP_REVIEW" = "true" ]; then
            log "ORCHESTRATOR" "Skipping review (--skip-review)"
            transition_to_phase "COMPLETE"
            continue
        fi

        log "ORCHESTRATOR" "Phase: $current_phase (max: $([ "$max_iter" -eq 0 ] && echo 'unlimited' || echo "$max_iter"))"

        # === Inner iteration loop ===
        while true; do
            phase_iteration=$((phase_iteration + 1))
            iteration=$((iteration + 1))

            # Enforce max iterations for this phase
            if [ "$max_iter" -gt 0 ] && [ "$phase_iteration" -gt "$max_iter" ]; then
                log "ORCHESTRATOR" "Max iterations reached for $current_phase ($max_iter)"
                phase_iteration=$((phase_iteration - 1))
                iteration=$((iteration - 1))
                break
            fi

            # Phase timeout check
            if ! check_phase_timeout; then
                break
            fi

            # Checkpoint plan before each build iteration (corruption guard)
            if [ "$current_phase" = "build" ]; then
                checkpoint_plan
            fi

            # --- Invoke the agent ---
            local iter_start_epoch
            iter_start_epoch=$(date +%s)
            run_agent "$prompt_file" "$model"

            # --- Error classification and recovery ---
            if [ "$AGENT_EXIT_CODE" -ne 0 ]; then
                if is_rate_limit "$AGENT_RESULT" || is_network_error "$AGENT_RESULT"; then
                    if ! handle_rate_limit run_agent "$prompt_file" "$model"; then
                        # All retries exhausted (inc. 10-min pause); retry iteration
                        phase_iteration=$((phase_iteration - 1))
                        iteration=$((iteration - 1))
                        continue
                    fi
                    # Successful retry — AGENT_RESULT/AGENT_EXIT_CODE updated
                else
                    # Generic CLI crash — retry with backoff
                    handle_cli_crash "$AGENT_EXIT_CODE" "$AGENT_RESULT"
                    # Returns 0 to retry, or exits 1 on max failures
                    phase_iteration=$((phase_iteration - 1))
                    iteration=$((iteration - 1))
                    continue
                fi
            fi

            reset_failure_count

            # --- Post-iteration pipeline ---
            if ! post_iteration "$model" "$prompt_file" "$iter_start_epoch"; then
                case "$TRANSITION_REASON" in
                    stall)
                        # Stall-triggered re-plan: jump to plan phase
                        transition_to_phase "plan"
                        continue 2
                        ;;
                    budget)
                        # Phase budget exceeded: force to next phase (spec-07)
                        case "$current_phase" in
                            research) transition_to_phase "plan" ;;
                            plan)     transition_to_phase "build" ;;
                            build)    transition_to_phase "review" ;;
                            review)   transition_to_phase "COMPLETE" ;;
                        esac
                        continue 2
                        ;;
                esac
            fi

            # Check if agent signaled COMPLETE
            if agent_signaled_complete; then
                log "ORCHESTRATOR" "Agent signaled COMPLETE for $current_phase"
                break
            fi
        done
        # === End inner iteration loop ===

        # --- Gate checks and phase transitions ---
        case "$current_phase" in
            research)
                # Gate 2: research completeness. On fail: warn, proceed to plan (spec-03)
                if gate_check "research_completeness"; then
                    transition_to_phase "plan"
                else
                    log "ORCHESTRATOR" "Research gate failed after max iterations. Proceeding to plan."
                    transition_to_phase "plan"
                fi
                ;;

            plan)
                # Gate 3: plan validity. On fail: escalate (spec-04)
                if gate_check "plan_validity"; then
                    transition_to_phase "build"
                else
                    escalate "Plan phase failed to produce a valid implementation plan."
                fi
                ;;

            build)
                # Gate 4: build completion. On fail: continue building (spec-05)
                if gate_check "build_completion"; then
                    transition_to_phase "review"
                else
                    if [ "$max_iter" -gt 0 ] && [ "$phase_iteration" -ge "$max_iter" ]; then
                        escalate "Build exhausted $max_iter iterations with incomplete tasks."
                    fi
                    log "ORCHESTRATOR" "Build incomplete. Continuing."
                    phase_iteration=0
                fi
                ;;

            review)
                # Gate 5: review pass. On fail: back to build. After 2 failures: escalate (spec-06)
                if gate_check "review_pass"; then
                    transition_to_phase "COMPLETE"
                else
                    review_attempts=$((review_attempts + 1))
                    if [ "$review_attempts" -ge 2 ]; then
                        escalate "Review failed after $review_attempts attempts."
                    fi
                    log "ORCHESTRATOR" "Review failed ($review_attempts/2). Returning to build."
                    stall_count=0
                    transition_to_phase "build"
                fi
                ;;
        esac
    done
    # === End outer phase loop ===

    write_state
    log "ORCHESTRATOR" "Run complete."
    exit 0
}

# --- Dry-run guard (full implementation deferred to task 9.9) ---
if [ "$ARG_DRY_RUN" = "true" ]; then
    echo "Dry-run mode not yet fully implemented (see task 9.9)."
    exit 0
fi

run_orchestration
