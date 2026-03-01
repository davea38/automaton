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

        # -- parallel --
        PARALLEL_ENABLED=$(jq -r '.parallel.enabled // false' "$config_file")
        MAX_BUILDERS=$(jq -r '.parallel.max_builders // 3' "$config_file")
        TMUX_SESSION_NAME=$(jq -r '.parallel.tmux_session_name // "automaton"' "$config_file")
        PARALLEL_STAGGER_SECONDS=$(jq -r '.parallel.stagger_seconds // 15' "$config_file")
        WAVE_TIMEOUT_SECONDS=$(jq -r '.parallel.wave_timeout_seconds // 600' "$config_file")
        PARALLEL_DASHBOARD=$(jq -r '.parallel.dashboard // true' "$config_file")

        # -- budget mode (spec-23) --
        BUDGET_MODE=$(jq -r '.budget.mode // "api"' "$config_file")
        BUDGET_WEEKLY_ALLOWANCE=$(jq -r '.budget.weekly_allowance_tokens // 45000000' "$config_file")
        BUDGET_ALLOWANCE_RESET_DAY=$(jq -r '.budget.allowance_reset_day // "monday"' "$config_file")
        BUDGET_RESERVE_PERCENTAGE=$(jq -r '.budget.reserve_percentage // 20' "$config_file")

        # -- self_build (spec-22) --
        SELF_BUILD_ENABLED=$(jq -r '.self_build.enabled // false' "$config_file")
        SELF_BUILD_MAX_FILES=$(jq -r '.self_build.max_files_per_iteration // 3' "$config_file")
        SELF_BUILD_MAX_LINES=$(jq -r '.self_build.max_lines_changed_per_iteration // 200' "$config_file")
        SELF_BUILD_PROTECTED_FUNCTIONS=$(jq -r '.self_build.protected_functions // ["run_orchestration","_handle_shutdown"] | join(",")' "$config_file")
        SELF_BUILD_REQUIRE_SMOKE=$(jq -r '.self_build.require_smoke_test // true' "$config_file")

        # -- journal (spec-26) --
        JOURNAL_MAX_RUNS=$(jq -r '.journal.max_runs // 50' "$config_file")
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

        # -- parallel --
        PARALLEL_ENABLED="false"
        MAX_BUILDERS=3
        TMUX_SESSION_NAME="automaton"
        PARALLEL_STAGGER_SECONDS=15
        WAVE_TIMEOUT_SECONDS=600
        PARALLEL_DASHBOARD="true"

        # -- budget mode (spec-23) --
        BUDGET_MODE="api"
        BUDGET_WEEKLY_ALLOWANCE=45000000
        BUDGET_ALLOWANCE_RESET_DAY="monday"
        BUDGET_RESERVE_PERCENTAGE=20

        # -- self_build (spec-22) --
        SELF_BUILD_ENABLED="false"
        SELF_BUILD_MAX_FILES=3
        SELF_BUILD_MAX_LINES=200
        SELF_BUILD_PROTECTED_FUNCTIONS="run_orchestration,_handle_shutdown"
        SELF_BUILD_REQUIRE_SMOKE="true"

        # -- journal (spec-26) --
        JOURNAL_MAX_RUNS=50
    fi
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# Appends a timestamped line to session.log and echoes to stdout.
# Usage: log "COMPONENT" "message text"
# In parallel mode (spec-21), callers use structured component tags:
#   CONDUCTOR     — wave management decisions
#   BUILD:WN:BN   — builder N in wave N (e.g., BUILD:W3:B1)
#   MERGE:WN      — merge operations for wave N (e.g., MERGE:W3)
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

    # Build optional wave fields for parallel mode
    local wave_fields=""
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        wave_fields=$(cat <<WAVE
  "wave_number": ${wave_number:-0},
  "wave_history": ${wave_history:-[]},
  "consecutive_wave_failures": ${consecutive_wave_failures:-0},
WAVE
)
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
  "test_failure_count": $test_failure_count,
  "started_at": "$started_at",
  "last_iteration_at": "$now",
  "parallel_builders": ${EXEC_PARALLEL_BUILDERS:-1},
  "resumed_from": $rf_value,
${wave_fields}  "phase_history": ${phase_history:-[]}
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
    test_failure_count=$(echo "$state" | jq '.test_failure_count // 0')
    started_at=$(echo "$state" | jq -r '.started_at')
    resumed_from=$(echo "$state" | jq -r '.last_iteration_at')
    phase_history=$(echo "$state" | jq -c '.phase_history')

    # Restore wave state for parallel mode resume
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        wave_number=$(echo "$state" | jq '.wave_number // 0')
        wave_history=$(echo "$state" | jq -c '.wave_history // []')
        consecutive_wave_failures=$(echo "$state" | jq '.consecutive_wave_failures // 0')
    fi
}

# First-run initialization: create .automaton/ structure, write initial state,
# initialize budget tracking, and create an empty session log.
initialize() {
    mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/worktrees" "$AUTOMATON_DIR/inbox"

    # Create parallel-mode directories and files when parallel is enabled
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        mkdir -p "$AUTOMATON_DIR/wave/results" "$AUTOMATON_DIR/wave-history"

        # Dashboard file — watched by the tmux dashboard window
        cat > "$AUTOMATON_DIR/dashboard.txt" <<'DASH'
╔══════════════════════════════════════════════════════════════╗
║  automaton — parallel build                                  ║
║  Initializing...                                             ║
╚══════════════════════════════════════════════════════════════╝
DASH

        # Rate-tracking file — read by the conductor for pacing decisions
        local now_ts
        now_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        cat > "$AUTOMATON_DIR/rate.json" <<RATE
{
  "window_start": "$now_ts",
  "window_tokens": 0,
  "window_requests": 0,
  "builders_active": 0,
  "last_rate_limit": null,
  "backoff_until": null,
  "history": []
}
RATE
    fi

    # Set initial state variables
    current_phase="research"
    iteration=0
    phase_iteration=0
    stall_count=0
    consecutive_failures=0
    corruption_count=0
    replan_count=0
    test_failure_count=0
    started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    resumed_from="null"
    phase_history="[]"

    # Initialize wave state for parallel mode
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        wave_number=0
        wave_history="[]"
        consecutive_wave_failures=0
    fi

    # Write initial state.json via atomic write
    write_state

    # Create budget.json with limits from config and zeroed counters
    initialize_budget

    # Initialize structured learnings file (spec-34)
    init_learnings

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

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Allowance mode (spec-23): weekly token tracking for Max subscription
        local week_start week_end effective_allowance
        week_start=$(_allowance_week_start)
        week_end=$(_allowance_week_end "$week_start")
        effective_allowance=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')

        jq -n \
            --arg mode "allowance" \
            --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
            --argjson effective_allowance "$effective_allowance" \
            --arg week_start "$week_start" \
            --arg week_end "$week_end" \
            --argjson reserve "$BUDGET_RESERVE_PERCENTAGE" \
            --argjson per_iteration "$BUDGET_PER_ITERATION" \
            '{
                mode: $mode,
                limits: {
                    weekly_allowance_tokens: $weekly_allowance,
                    effective_allowance: $effective_allowance,
                    reserve_percentage: $reserve,
                    per_iteration: $per_iteration,
                    phase_proportions: {
                        research: 0.05,
                        plan: 0.10,
                        build: 0.70,
                        review: 0.15
                    }
                },
                week_start: $week_start,
                week_end: $week_end,
                tokens_used_this_week: 0,
                tokens_remaining: ($effective_allowance | tonumber),
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
                history: [],
                allowance_history: []
            }' > "$tmp"
    else
        # API mode (default): original USD-based budget
        jq -n \
            --arg mode "api" \
            --argjson max_tokens "$BUDGET_MAX_TOKENS" \
            --argjson max_usd "$BUDGET_MAX_USD" \
            --argjson phase_research "$BUDGET_PHASE_RESEARCH" \
            --argjson phase_plan "$BUDGET_PHASE_PLAN" \
            --argjson phase_build "$BUDGET_PHASE_BUILD" \
            --argjson phase_review "$BUDGET_PHASE_REVIEW" \
            --argjson per_iteration "$BUDGET_PER_ITERATION" \
            '{
                mode: $mode,
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
    fi
    mv "$tmp" "$AUTOMATON_DIR/budget.json"
}

# Returns the start of the current allowance week (ISO date) based on reset day.
_allowance_week_start() {
    local reset_day="$BUDGET_ALLOWANCE_RESET_DAY"
    local today today_dow target_dow days_back

    today=$(date +%Y-%m-%d)
    today_dow=$(date +%u)  # 1=Monday, 7=Sunday

    case "$reset_day" in
        monday)    target_dow=1 ;;
        tuesday)   target_dow=2 ;;
        wednesday) target_dow=3 ;;
        thursday)  target_dow=4 ;;
        friday)    target_dow=5 ;;
        saturday)  target_dow=6 ;;
        sunday)    target_dow=7 ;;
        *)         target_dow=1 ;;
    esac

    days_back=$(( (today_dow - target_dow + 7) % 7 ))
    date -d "$today - $days_back days" +%Y-%m-%d 2>/dev/null || \
        date -v-"${days_back}d" +%Y-%m-%d 2>/dev/null || echo "$today"
}

# Returns the end of the current allowance week (ISO date).
_allowance_week_end() {
    local week_start="$1"
    date -d "$week_start + 6 days" +%Y-%m-%d 2>/dev/null || \
        date -v+6d -jf "%Y-%m-%d" "$week_start" +%Y-%m-%d 2>/dev/null || echo "$week_start"
}

# Checks if the current date is past the stored week_end in budget.json.
# If so, archives the current week and resets counters.
# Called during --resume in allowance mode.
_allowance_check_rollover() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ ! -f "$budget_file" ]; then
        return 0
    fi

    local stored_week_end today
    stored_week_end=$(jq -r '.week_end // ""' "$budget_file")
    today=$(date +%Y-%m-%d)

    if [ -z "$stored_week_end" ]; then
        return 0
    fi

    # Compare dates: if today > week_end, rollover needed
    if [[ "$today" > "$stored_week_end" ]]; then
        log "ORCHESTRATOR" "Allowance week rollover: $stored_week_end has passed. Resetting weekly counters."

        local new_week_start new_week_end effective_allowance tmp
        new_week_start=$(_allowance_week_start)
        new_week_end=$(_allowance_week_end "$new_week_start")
        effective_allowance=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')
        tmp="$AUTOMATON_DIR/budget.json.tmp"

        jq \
            --arg ws "$new_week_start" \
            --arg we "$new_week_end" \
            --argjson eff "$effective_allowance" \
            '
            # Archive current week
            .allowance_history += [{
                week_start: .week_start,
                week_end: .week_end,
                tokens_used: .tokens_used_this_week,
                effective_allowance: .limits.effective_allowance
            }] |
            # Reset for new week
            .week_start = $ws |
            .week_end = $we |
            .tokens_used_this_week = 0 |
            .tokens_remaining = $eff |
            .limits.effective_allowance = $eff
            ' "$budget_file" > "$tmp"
        mv "$tmp" "$budget_file"

        log "ORCHESTRATOR" "New allowance week: $new_week_start to $new_week_end ($effective_allowance effective tokens)"
    fi
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

    # Common jq update for both modes
    local jq_filter='
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
        }]'

    # In allowance mode, also update weekly token counters
    if [ "$BUDGET_MODE" = "allowance" ]; then
        jq_filter="${jq_filter}"'
        | .tokens_used_this_week += ($input_tokens + $output_tokens)
        | .tokens_remaining = (.limits.effective_allowance - .tokens_used_this_week)'
    fi

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
        "$jq_filter" "$budget_file" > "$tmp"
    mv "$tmp" "$budget_file"
}

# Enforces budget rules after each iteration. Returns 0 to continue,
# 1 to force phase transition, or exits with code 2 for hard stops.
# In API mode: enforces per-iteration, per-phase, total token, and cost limits.
# In allowance mode (spec-23): enforces weekly token allowance and phase proportions.
check_budget() {
    local input_tokens="$1" output_tokens="$2"
    local budget_file="$AUTOMATON_DIR/budget.json"
    local total_iter_tokens=$((input_tokens + output_tokens))

    # Rule 1: Per-iteration warning (advisory, both modes)
    if [ "$total_iter_tokens" -gt "$BUDGET_PER_ITERATION" ]; then
        log "ORCHESTRATOR" "WARNING: Iteration used ${total_iter_tokens} tokens, exceeding per-iteration limit of ${BUDGET_PER_ITERATION}"
    fi

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # --- Allowance mode enforcement (spec-23) ---
        local tokens_remaining tokens_used effective_allowance week_end
        tokens_remaining=$(jq '.tokens_remaining' "$budget_file")
        tokens_used=$(jq '.tokens_used_this_week' "$budget_file")
        effective_allowance=$(jq '.limits.effective_allowance' "$budget_file")
        week_end=$(jq -r '.week_end' "$budget_file")

        # Hard stop: weekly allowance exhausted
        if [ "$tokens_remaining" -le 0 ]; then
            log "ORCHESTRATOR" "Weekly token allowance exhausted (${tokens_used}/${effective_allowance}). Resets after ${week_end}. Run --resume after reset."
            write_state
            exit 2
        fi

        # Pre-iteration warning: less than one iteration's worth of tokens left
        if [ "$tokens_remaining" -lt "$BUDGET_PER_ITERATION" ]; then
            log "ORCHESTRATOR" "WARNING: Only ${tokens_remaining} tokens remaining in weekly allowance (need ~${BUDGET_PER_ITERATION} per iteration)"
        fi

        # Phase proportioning (soft limits): check if current phase exceeded its share
        local phase_proportion phase_budget phase_input phase_output phase_tokens
        phase_proportion=$(jq --arg p "$current_phase" '.limits.phase_proportions[$p] // 0.25' "$budget_file")
        phase_budget=$(awk -v eff="$effective_allowance" -v prop="$phase_proportion" \
            'BEGIN { printf "%d", eff * prop }')
        phase_input=$(jq --arg p "$current_phase" '.used.by_phase[$p].input' "$budget_file")
        phase_output=$(jq --arg p "$current_phase" '.used.by_phase[$p].output' "$budget_file")
        phase_tokens=$((phase_input + phase_output))

        if [ "$phase_tokens" -gt "$phase_budget" ]; then
            log "ORCHESTRATOR" "Phase token proportion exhausted for ${current_phase} (${phase_tokens}/${phase_budget}). Transitioning to next phase."
            return 1
        fi
    else
        # --- API mode enforcement (original behavior) ---
        local total_input total_output total_cost
        total_input=$(jq '.used.total_input' "$budget_file")
        total_output=$(jq '.used.total_output' "$budget_file")
        total_cost=$(jq '.used.estimated_cost_usd' "$budget_file")
        local cumulative_tokens=$((total_input + total_output))

        # Rule 3: Total token hard stop
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

# Classifies whether agent output indicates a test failure.
# Checks for common test failure patterns across popular test frameworks.
# Usage: if is_test_failure "$agent_output"; then ...
# Returns: 0 if test failure detected, 1 otherwise
is_test_failure() {
    local output="${1:-}"
    echo "$output" | grep -qi 'tests\? failed\|test.*fail\|FAIL:\|failing tests\|assertion.*error\|AssertionError\|expected.*but.*received\|npm test.*exit code\|jest.*failed\|pytest.*failed\|test suite failed'
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

# Repeated test failure detection (spec-09, Error #8): tracks consecutive build
# iterations where the agent output indicates test failures. If the same failure
# pattern persists across 3 iterations, the agent is stuck and we escalate to
# the review phase for independent diagnosis.
#
# Resets test_failure_count on iterations without test failure indicators.
#
# Usage: check_test_failures "$agent_output"
# Returns: 0 = continue normally, 1 = force transition to review phase
check_test_failures() {
    local agent_output="${1:-}"

    if is_test_failure "$agent_output"; then
        test_failure_count=$((test_failure_count + 1))
        log "ORCHESTRATOR" "Test failure detected ($test_failure_count/3). Agent output contains test failure indicators."
    else
        if [ "$test_failure_count" -gt 0 ]; then
            log "ORCHESTRATOR" "Test failures cleared after $test_failure_count iteration(s)."
        fi
        test_failure_count=0
        return 0
    fi

    if [ "$test_failure_count" -ge 3 ]; then
        log "ORCHESTRATOR" "Repeated test failures across 3 iterations. Escalating to review phase."
        test_failure_count=0
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Self-Build Safety (spec-22)
# ---------------------------------------------------------------------------

# List of orchestrator files to track during self-build.
SELF_BUILD_FILES="automaton.sh PROMPT_converse.md PROMPT_research.md PROMPT_plan.md PROMPT_build.md PROMPT_review.md automaton.config.json bin/cli.js"

# Computes sha256 checksums of all orchestrator files and stores them in
# .automaton/self_checksums.json. Called before each build iteration when
# self_build.enabled is true.
#
# Usage: self_build_checkpoint
self_build_checkpoint() {
    if [ "$SELF_BUILD_ENABLED" != "true" ]; then
        return 0
    fi

    local checksums_file="$AUTOMATON_DIR/self_checksums.json"
    local tmp="$AUTOMATON_DIR/self_checksums.json.tmp"
    local backup_dir="$AUTOMATON_DIR/self_backup"
    mkdir -p "$backup_dir"

    # Build checksums JSON and backup files
    local json_entries=""
    local first=true
    for f in $SELF_BUILD_FILES; do
        if [ -f "$f" ]; then
            local hash
            hash=$(sha256sum "$f" | awk '{print $1}')
            # Backup the file for potential restore
            cp "$f" "$backup_dir/$(echo "$f" | tr '/' '_')"
            if [ "$first" = "true" ]; then
                first=false
            else
                json_entries="${json_entries},"
            fi
            json_entries="${json_entries}\"$f\":\"$hash\""
        fi
    done

    echo "{${json_entries}}" | jq '.' > "$tmp"
    mv "$tmp" "$checksums_file"

    log "ORCHESTRATOR" "Self-build checkpoint: checksums saved for orchestrator files"
}

# After a build iteration, compares current file checksums against the
# pre-iteration checkpoint. If any orchestrator file changed, validates the
# change (syntax check + smoke test) and logs to the audit trail.
#
# Usage: self_build_validate
# Returns: 0 = all clear, 1 = file was restored from checkpoint
self_build_validate() {
    if [ "$SELF_BUILD_ENABLED" != "true" ]; then
        return 0
    fi

    local checksums_file="$AUTOMATON_DIR/self_checksums.json"
    local backup_dir="$AUTOMATON_DIR/self_backup"
    local audit_file="$AUTOMATON_DIR/self_modifications.json"
    local changed_files=""
    local any_changed=false

    # Initialize audit log if it doesn't exist
    if [ ! -f "$audit_file" ]; then
        echo '[]' > "$audit_file"
    fi

    if [ ! -f "$checksums_file" ]; then
        return 0
    fi

    # Compare current checksums against checkpoint
    local new_checksums=""
    for f in $SELF_BUILD_FILES; do
        if [ -f "$f" ]; then
            local old_hash new_hash
            old_hash=$(jq -r --arg f "$f" '.[$f] // ""' "$checksums_file")
            new_hash=$(sha256sum "$f" | awk '{print $1}')

            if [ -n "$old_hash" ] && [ "$old_hash" != "$new_hash" ]; then
                any_changed=true
                changed_files="${changed_files} $f"
                log "ORCHESTRATOR" "Self-build: $f was modified during iteration $iteration"
                new_checksums="${new_checksums}{\"file\":\"$f\",\"before\":\"$old_hash\",\"after\":\"$new_hash\"},"
            fi
        fi
    done

    if [ "$any_changed" != "true" ]; then
        return 0
    fi

    # --- Syntax validation for automaton.sh ---
    local syntax_ok="skipped"
    local smoke_ok="skipped"

    if echo "$changed_files" | grep -q "automaton.sh"; then
        # Syntax check
        if bash -n automaton.sh 2>/dev/null; then
            syntax_ok="pass"
            log "ORCHESTRATOR" "Self-build: automaton.sh syntax check PASSED"

            # Smoke test (dry-run in subshell)
            if [ "$SELF_BUILD_REQUIRE_SMOKE" = "true" ]; then
                if (./automaton.sh --dry-run) >/dev/null 2>&1; then
                    smoke_ok="pass"
                    log "ORCHESTRATOR" "Self-build: automaton.sh smoke test PASSED"
                else
                    smoke_ok="fail"
                    log "ORCHESTRATOR" "Self-build: automaton.sh smoke test FAILED — restoring from checkpoint"
                    _self_build_restore "$backup_dir"
                    _self_build_add_fix_task "automaton.sh smoke test (--dry-run) failed after iteration $iteration"
                    _self_build_audit_entry "$changed_files" "$new_checksums" "$syntax_ok" "$smoke_ok"
                    return 1
                fi
            fi
        else
            syntax_ok="fail"
            log "ORCHESTRATOR" "Self-build: automaton.sh syntax check FAILED — restoring from checkpoint"
            _self_build_restore "$backup_dir"
            _self_build_add_fix_task "automaton.sh syntax error introduced in iteration $iteration"
            _self_build_audit_entry "$changed_files" "$new_checksums" "$syntax_ok" "$smoke_ok"
            return 1
        fi
    fi

    # Log audit entry for successful modifications
    _self_build_audit_entry "$changed_files" "$new_checksums" "$syntax_ok" "$smoke_ok"

    log "ORCHESTRATOR" "Self-build: modifications validated. Changes take effect on next --resume or fresh run."
    return 0
}

# Restores orchestrator files from the pre-iteration backup.
_self_build_restore() {
    local backup_dir="$1"

    for f in $SELF_BUILD_FILES; do
        local backup_name
        backup_name="$backup_dir/$(echo "$f" | tr '/' '_')"
        if [ -f "$backup_name" ]; then
            cp "$backup_name" "$f"
        fi
    done

    # Commit the restoration
    git add automaton.sh PROMPT_*.md automaton.config.json bin/cli.js 2>/dev/null || true
    git commit -m "automaton: self-build restore from checkpoint (iteration $iteration)" 2>/dev/null || true

    log "ORCHESTRATOR" "Self-build: files restored from pre-iteration checkpoint"
}

# Adds a fix task to the appropriate plan file for self-build failures.
_self_build_add_fix_task() {
    local description="$1"
    local plan_file="IMPLEMENTATION_PLAN.md"

    # In self-build mode, prefer the backlog
    if [ -f "$AUTOMATON_DIR/backlog.md" ] && [ "${ARG_SELF:-false}" = "true" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    if [ -f "$plan_file" ]; then
        echo "- [ ] Fix: $description" >> "$plan_file"
    fi

    log "ORCHESTRATOR" "Self-build: added fix task to $plan_file: $description"
}

# Appends an entry to the self-modification audit log.
_self_build_audit_entry() {
    local changed_files="$1" checksums_json="$2" syntax_result="$3" smoke_result="$4"
    local audit_file="$AUTOMATON_DIR/self_modifications.json"
    local tmp="$AUTOMATON_DIR/self_modifications.json.tmp"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build files array as JSON
    local files_json
    files_json=$(echo "$changed_files" | tr ' ' '\n' | grep -v '^$' | jq -R -s 'split("\n") | map(select(. != ""))')

    jq --arg ts "$timestamp" \
       --argjson iter "$iteration" \
       --arg phase "$current_phase" \
       --argjson files "$files_json" \
       --arg syntax "$syntax_result" \
       --arg smoke "$smoke_result" \
       '. + [{
           timestamp: $ts,
           iteration: $iter,
           phase: $phase,
           files_changed: $files,
           syntax_check: $syntax,
           smoke_test: $smoke
       }]' "$audit_file" > "$tmp"
    mv "$tmp" "$audit_file"
}

# Checks self-build scope limits (spec-25): max files per iteration,
# max lines changed per iteration, protected function modification.
# Returns: 0 = within limits, logs warnings for violations
self_build_check_scope() {
    if [ "$SELF_BUILD_ENABLED" != "true" ]; then
        return 0
    fi

    # Count files changed in this iteration
    local files_changed_count
    files_changed_count=$(git diff --name-only HEAD~1 2>/dev/null | wc -l || echo 0)

    if [ "$files_changed_count" -gt "$SELF_BUILD_MAX_FILES" ]; then
        log "ORCHESTRATOR" "WARNING: Self-build scope: $files_changed_count files changed (limit: $SELF_BUILD_MAX_FILES)"
    fi

    # Count lines changed
    local lines_changed
    lines_changed=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)

    if [ "$lines_changed" -gt "$SELF_BUILD_MAX_LINES" ]; then
        log "ORCHESTRATOR" "WARNING: Self-build scope: $lines_changed lines changed (limit: $SELF_BUILD_MAX_LINES)"
    fi

    # Check protected functions
    if git diff HEAD~1 -- automaton.sh 2>/dev/null | grep -qE '^\+.*^(run_orchestration|_handle_shutdown)\(' 2>/dev/null; then
        local protected
        IFS=',' read -ra protected <<< "$SELF_BUILD_PROTECTED_FUNCTIONS"
        for func in "${protected[@]}"; do
            if git diff HEAD~1 -- automaton.sh 2>/dev/null | grep -qE "^\+.*${func}\s*\(" 2>/dev/null; then
                log "ORCHESTRATOR" "WARNING: Self-build scope: protected function '$func' was modified"
            fi
        done
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Structured Learnings (spec-34)
# ---------------------------------------------------------------------------

# Initializes .automaton/learnings.json if it does not exist.
# Called from initialize() to ensure the file is present before any phase runs.
init_learnings() {
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ -f "$learnings_file" ]; then
        return 0
    fi

    mkdir -p "$AUTOMATON_DIR"
    cat > "$learnings_file" <<'LEARN'
{
  "version": 1,
  "entries": []
}
LEARN
    log "ORCHESTRATOR" "Initialized structured learnings at $learnings_file"
}

# Adds a new learning entry to learnings.json.
# Args: category summary [detail] [confidence] [source_phase] [tags_csv]
# category: one of convention, architecture, debugging, tooling, performance, safety
# confidence: high, medium, low (default: medium)
# tags_csv: comma-separated tags (default: empty)
# Returns: 0 on success, 1 on error
add_learning() {
    local category="$1"
    local summary="$2"
    local detail="${3:-}"
    local confidence="${4:-medium}"
    local source_phase="${5:-${current_phase:-unknown}}"
    local tags_csv="${6:-}"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    local tmp="$AUTOMATON_DIR/learnings.json.tmp"

    if [ ! -f "$learnings_file" ]; then
        init_learnings
    fi

    # Validate category
    case "$category" in
        convention|architecture|debugging|tooling|performance|safety) ;;
        *)
            log "ORCHESTRATOR" "WARN: Invalid learning category '$category'"
            return 1
            ;;
    esac

    # Validate confidence
    case "$confidence" in
        high|medium|low) ;;
        *)
            log "ORCHESTRATOR" "WARN: Invalid learning confidence '$confidence'"
            return 1
            ;;
    esac

    # Generate next ID
    local next_id
    next_id=$(jq -r '
        .entries | map(.id) | map(ltrimstr("learn-") | tonumber) |
        (if length == 0 then 0 else max end) + 1 |
        "learn-" + (. | tostring | if length < 3 then ("000" + .)[-3:] else . end)
    ' "$learnings_file")

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Convert tags CSV to JSON array
    local tags_json
    if [ -z "$tags_csv" ]; then
        tags_json="[]"
    else
        tags_json=$(echo "$tags_csv" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R -s 'split("\n") | map(select(. != ""))')
    fi

    jq --arg id "$next_id" \
       --arg cat "$category" \
       --arg sum "$summary" \
       --arg det "$detail" \
       --arg conf "$confidence" \
       --arg phase "$source_phase" \
       --argjson iter "${iteration:-0}" \
       --arg ts "$timestamp" \
       --argjson tags "$tags_json" \
       '.entries += [{
           id: $id,
           category: $cat,
           summary: $sum,
           detail: $det,
           confidence: $conf,
           source_phase: $phase,
           source_iteration: $iter,
           created_at: $ts,
           updated_at: $ts,
           tags: $tags,
           active: true
       }]' "$learnings_file" > "$tmp"
    mv "$tmp" "$learnings_file"

    log "ORCHESTRATOR" "Learning added: $next_id ($category) — $summary"
}

# Queries learnings from learnings.json with optional filters.
# Args: [--category CAT] [--confidence CONF] [--tag TAG] [--active-only] [--ids-only]
# Outputs: JSON array of matching entries (or IDs if --ids-only).
query_learnings() {
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ ! -f "$learnings_file" ]; then
        echo "[]"
        return 0
    fi

    local filter_cat="" filter_conf="" filter_tag="" active_only="false" ids_only="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --category)   filter_cat="$2"; shift 2 ;;
            --confidence) filter_conf="$2"; shift 2 ;;
            --tag)        filter_tag="$2"; shift 2 ;;
            --active-only) active_only="true"; shift ;;
            --ids-only)   ids_only="true"; shift ;;
            *) shift ;;
        esac
    done

    jq --arg cat "$filter_cat" \
       --arg conf "$filter_conf" \
       --arg tag "$filter_tag" \
       --arg active "$active_only" \
       --arg ids "$ids_only" \
       '.entries |
        (if $active == "true" then map(select(.active == true)) else . end) |
        (if $cat != "" then map(select(.category == $cat)) else . end) |
        (if $conf != "" then map(select(.confidence == $conf)) else . end) |
        (if $tag != "" then map(select(.tags | index($tag) != null)) else . end) |
        (if $ids == "true" then map(.id) else . end)
       ' "$learnings_file"
}

# Deactivates a learning by ID (sets active to false).
# Args: id [reason]
# Returns: 0 on success, 1 if not found
deactivate_learning() {
    local target_id="$1"
    local reason="${2:-superseded}"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    local tmp="$AUTOMATON_DIR/learnings.json.tmp"

    if [ ! -f "$learnings_file" ]; then
        return 1
    fi

    local found
    found=$(jq --arg id "$target_id" '.entries | map(select(.id == $id)) | length' "$learnings_file")
    if [ "$found" -eq 0 ]; then
        log "ORCHESTRATOR" "WARN: Learning '$target_id' not found"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq --arg id "$target_id" \
       --arg ts "$timestamp" \
       --arg reason "$reason" \
       '.entries |= map(
           if .id == $id then
               .active = false | .updated_at = $ts | .detail = (.detail + " [deactivated: " + $reason + "]")
           else . end
       )' "$learnings_file" > "$tmp"
    mv "$tmp" "$learnings_file"

    log "ORCHESTRATOR" "Learning deactivated: $target_id ($reason)"
}

# Updates a learning's summary, detail, or confidence by ID.
# Args: id field value
# field: one of summary, detail, confidence
# Returns: 0 on success, 1 if not found or invalid field
update_learning() {
    local target_id="$1"
    local field="$2"
    local value="$3"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    local tmp="$AUTOMATON_DIR/learnings.json.tmp"

    if [ ! -f "$learnings_file" ]; then
        return 1
    fi

    # Validate field
    case "$field" in
        summary|detail|confidence) ;;
        *)
            log "ORCHESTRATOR" "WARN: Invalid learning field '$field'"
            return 1
            ;;
    esac

    # Validate confidence value if updating confidence
    if [ "$field" = "confidence" ]; then
        case "$value" in
            high|medium|low) ;;
            *)
                log "ORCHESTRATOR" "WARN: Invalid confidence value '$value'"
                return 1
                ;;
        esac
    fi

    local found
    found=$(jq --arg id "$target_id" '.entries | map(select(.id == $id)) | length' "$learnings_file")
    if [ "$found" -eq 0 ]; then
        log "ORCHESTRATOR" "WARN: Learning '$target_id' not found"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq --arg id "$target_id" \
       --arg field "$field" \
       --arg val "$value" \
       --arg ts "$timestamp" \
       '.entries |= map(
           if .id == $id then
               .[$field] = $val | .updated_at = $ts
           else . end
       )' "$learnings_file" > "$tmp"
    mv "$tmp" "$learnings_file"

    log "ORCHESTRATOR" "Learning updated: $target_id.$field"
}

# Returns count of active learnings, useful for status/dashboard.
count_active_learnings() {
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ ! -f "$learnings_file" ]; then
        echo "0"
        return 0
    fi
    jq '.entries | map(select(.active == true)) | length' "$learnings_file"
}

# ---------------------------------------------------------------------------
# Self-Targeting Mode (spec-25)
# ---------------------------------------------------------------------------

# Initializes the improvement backlog if it doesn't exist.
_self_init_backlog() {
    local backlog="$AUTOMATON_DIR/backlog.md"
    if [ -f "$backlog" ]; then
        return 0
    fi

    mkdir -p "$AUTOMATON_DIR"
    cat > "$backlog" <<'BACKLOG'
# Improvement Backlog

## Prompt Improvements
- [ ] Reduce prompt sizes across all phases for token efficiency

## Architecture Improvements
- [ ] Extract budget functions into sourced module
- [ ] Extract self-build functions into sourced module

## Configuration Improvements
- [ ] Add validation for all config fields at load time

## Performance Improvements
- [ ] Reduce jq invocations by batching reads

## Auto-generated
BACKLOG

    log "ORCHESTRATOR" "Self-build: initialized improvement backlog at $backlog"
}

# Shows --self --continue recommendation: estimates token cost for the
# highest-priority backlog item and shows whether it's safe to run.
_self_continue_recommendation() {
    local backlog="$AUTOMATON_DIR/backlog.md"
    if [ ! -f "$backlog" ]; then
        echo "No backlog found. Run --self first to initialize."
        exit 0
    fi

    local next_task
    next_task=$(grep '^\- \[ \]' "$backlog" | head -1 | sed 's/^- \[ \] //')

    if [ -z "$next_task" ]; then
        echo "Backlog is empty. No improvement tasks remain."
        exit 0
    fi

    echo "Next backlog item: $next_task"
    echo ""

    # Check remaining allowance
    if [ "$BUDGET_MODE" = "allowance" ] && [ -f "$AUTOMATON_DIR/budget.json" ]; then
        local remaining effective pct
        remaining=$(jq '.tokens_remaining // 0' "$AUTOMATON_DIR/budget.json")
        effective=$(jq '.limits.effective_allowance // 1' "$AUTOMATON_DIR/budget.json")
        pct=$(awk -v r="$remaining" -v e="$effective" 'BEGIN { printf "%d", (r/e)*100 }')
        echo "Remaining weekly allowance: $remaining tokens ($pct%)"

        if [ "$pct" -gt 30 ]; then
            echo "Recommendation: Safe to run - $pct% of remaining allowance"
        elif [ "$pct" -gt 10 ]; then
            echo "Recommendation: Proceed with caution - only $pct% remaining"
        else
            echo "Recommendation: Low allowance ($pct%). Consider waiting for reset."
        fi
    else
        echo "Budget mode: api (cost-based). Run at your discretion."
    fi
}

# ---------------------------------------------------------------------------
# Run Journal & Performance Tracking (spec-26)
# ---------------------------------------------------------------------------

# Archives the current run data to .automaton/journal/run-{NNN}/.
# Called at the end of run_orchestration().
archive_run_journal() {
    local journal_dir="$AUTOMATON_DIR/journal"
    mkdir -p "$journal_dir"

    # Determine next run number
    local run_num=1
    if [ -d "$journal_dir" ]; then
        local latest
        latest=$(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | tail -1 || true)
        if [ -n "$latest" ]; then
            run_num=$(( $(basename "$latest" | sed 's/run-//') + 1 ))
        fi
    fi

    local run_dir
    run_dir=$(printf "%s/run-%03d" "$journal_dir" "$run_num")
    mkdir -p "$run_dir"

    # Copy run artifacts
    cp "$AUTOMATON_DIR/budget.json" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/state.json" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/session.log" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/context_summary.md" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/self_modifications.json" "$run_dir/" 2>/dev/null || true

    # Generate performance metrics
    _generate_run_metadata "$run_dir"

    # Auto-generate backlog entries from performance data (spec-26)
    if [ "${ARG_SELF:-false}" = "true" ]; then
        _auto_generate_backlog "$run_dir"
        _check_convergence "$journal_dir"
    fi

    # Enforce journal retention limit
    local max_runs="${JOURNAL_MAX_RUNS:-50}"
    local run_count
    run_count=$(ls -1d "$journal_dir"/run-* 2>/dev/null | wc -l)
    if [ "$run_count" -gt "$max_runs" ]; then
        local to_remove=$((run_count - max_runs))
        ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | head -"$to_remove" | while read -r old_run; do
            rm -rf "$old_run"
        done
        log "ORCHESTRATOR" "Journal: pruned $to_remove old runs (max: $max_runs)"
    fi

    log "ORCHESTRATOR" "Run archived to $run_dir"
}

# Generates run_metadata.json with performance metrics.
_generate_run_metadata() {
    local run_dir="$1"
    local budget_file="$run_dir/budget.json"
    local state_file="$run_dir/state.json"

    if [ ! -f "$budget_file" ]; then
        echo '{}' > "$run_dir/run_metadata.json"
        return
    fi

    local total_input total_output total_tokens history_count
    total_input=$(jq '.used.total_input // 0' "$budget_file")
    total_output=$(jq '.used.total_output // 0' "$budget_file")
    total_tokens=$((total_input + total_output))
    history_count=$(jq '.history | length' "$budget_file")

    # Tasks completed: count successful build iterations
    local tasks_completed
    tasks_completed=$(jq '[.history[] | select(.phase == "build" and .status == "success")] | length' "$budget_file")

    # Tokens per completed task
    local tokens_per_task=0
    if [ "$tasks_completed" -gt 0 ]; then
        tokens_per_task=$((total_tokens / tasks_completed))
    fi

    # Stall rate
    local stall_count total_build_iters stall_rate
    stall_count=$(jq '.stall_count // 0' "$state_file" 2>/dev/null || echo 0)
    total_build_iters=$(jq '[.history[] | select(.phase == "build")] | length' "$budget_file")
    if [ "$total_build_iters" -gt 0 ]; then
        stall_rate=$(awk -v s="$stall_count" -v t="$total_build_iters" 'BEGIN { printf "%.2f", s/t }')
    else
        stall_rate="0.00"
    fi

    # Average iteration duration
    local avg_duration
    if [ "$history_count" -gt 0 ]; then
        avg_duration=$(jq '[.history[].duration_seconds] | add / length | floor' "$budget_file")
    else
        avg_duration=0
    fi

    # Prompt overhead ratio (estimated: prompt tokens are a portion of input)
    local prompt_overhead="0.00"

    # First-pass success rate
    local review_rework_count first_pass_rate
    review_rework_count=$(jq '.replan_count // 0' "$state_file" 2>/dev/null || echo 0)
    if [ "$tasks_completed" -gt 0 ]; then
        local successful=$((tasks_completed - review_rework_count))
        if [ "$successful" -lt 0 ]; then successful=0; fi
        first_pass_rate=$(awk -v s="$successful" -v t="$tasks_completed" 'BEGIN { printf "%.2f", s/t }')
    else
        first_pass_rate="0.00"
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg ts "$timestamp" \
        --argjson total_tokens "$total_tokens" \
        --argjson tasks_completed "$tasks_completed" \
        --argjson tokens_per_task "$tokens_per_task" \
        --arg stall_rate "$stall_rate" \
        --arg first_pass_rate "$first_pass_rate" \
        --argjson avg_duration "$avg_duration" \
        --arg prompt_overhead "$prompt_overhead" \
        --argjson history_count "$history_count" \
        '{
            timestamp: $ts,
            total_tokens: $total_tokens,
            tasks_completed: $tasks_completed,
            tokens_per_task: $tokens_per_task,
            stall_rate: ($stall_rate | tonumber),
            first_pass_success_rate: ($first_pass_rate | tonumber),
            avg_iteration_duration_seconds: $avg_duration,
            prompt_overhead_ratio: ($prompt_overhead | tonumber),
            total_iterations: $history_count
        }' > "$run_dir/run_metadata.json"
}

# Auto-generates backlog entries from performance analysis.
_auto_generate_backlog() {
    local run_dir="$1"
    local metadata="$run_dir/run_metadata.json"
    local backlog="$AUTOMATON_DIR/backlog.md"

    if [ ! -f "$metadata" ] || [ ! -f "$backlog" ]; then
        return
    fi

    local stall_rate tokens_per_task
    stall_rate=$(jq '.stall_rate // 0' "$metadata")
    tokens_per_task=$(jq '.tokens_per_task // 0' "$metadata")

    local new_items=""

    # Stall rate > 20% → improve prompt task
    local stall_high
    stall_high=$(awk -v s="$stall_rate" 'BEGIN { print (s > 0.20) ? "yes" : "no" }')
    if [ "$stall_high" = "yes" ]; then
        new_items="${new_items}\n- [ ] Investigate: stall rate ${stall_rate} exceeds 20% — review build prompt clarity"
    fi

    # Check if previous run exists for regression comparison
    local prev_run
    prev_run=$(ls -1d "$AUTOMATON_DIR/journal"/run-* 2>/dev/null | sort -t- -k2 -n | tail -2 | head -1 || true)
    if [ -n "$prev_run" ] && [ -f "$prev_run/run_metadata.json" ]; then
        local prev_tpt
        prev_tpt=$(jq '.tokens_per_task // 0' "$prev_run/run_metadata.json")
        if [ "$tokens_per_task" -gt 0 ] && [ "$prev_tpt" -gt 0 ]; then
            local regression
            regression=$(awk -v curr="$tokens_per_task" -v prev="$prev_tpt" \
                'BEGIN { print (curr > prev * 1.1) ? "yes" : "no" }')
            if [ "$regression" = "yes" ]; then
                new_items="${new_items}\n- [ ] Investigate: token efficiency regression — ${tokens_per_task} tokens/task vs previous ${prev_tpt}"
            fi
        fi
    fi

    if [ -n "$new_items" ]; then
        echo -e "$new_items" >> "$backlog"
        log "ORCHESTRATOR" "Auto-generated backlog entries from performance analysis"
    fi
}

# Convergence detection: warns if last 3 runs show no improvement.
_check_convergence() {
    local journal_dir="$1"

    local recent_runs
    recent_runs=$(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | tail -3)
    local run_count
    run_count=$(echo "$recent_runs" | grep -c . || echo 0)

    if [ "$run_count" -lt 3 ]; then
        return 0
    fi

    # Compare tokens_per_task across last 3 runs
    local improving=false
    local prev_tpt=0
    while IFS= read -r run; do
        if [ -f "$run/run_metadata.json" ]; then
            local tpt
            tpt=$(jq '.tokens_per_task // 0' "$run/run_metadata.json")
            if [ "$prev_tpt" -gt 0 ] && [ "$tpt" -lt "$prev_tpt" ]; then
                improving=true
            fi
            prev_tpt="$tpt"
        fi
    done <<< "$recent_runs"

    if [ "$improving" = "false" ]; then
        log "ORCHESTRATOR" "WARNING: Self-improvement may have converged. Last 3 runs show no measurable improvement. Consider manual review of backlog priorities."
    fi
}

# Displays run history table and performance trends.
# Called by --stats CLI command.
display_stats() {
    local journal_dir="$AUTOMATON_DIR/journal"

    if [ ! -d "$journal_dir" ] || [ -z "$(ls -d "$journal_dir"/run-* 2>/dev/null)" ]; then
        echo "No run history found. Complete at least one run first."
        exit 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " automaton — Run History"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-8s %-22s %-8s %-12s %-10s %-10s %-8s\n" \
        "Run" "Timestamp" "Tasks" "Tokens/Task" "Stall%" "1stPass%" "AvgSec"
    echo "-------  --------------------  ------  ----------  --------  --------  ------"

    for run_dir in $(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n); do
        local meta="$run_dir/run_metadata.json"
        if [ ! -f "$meta" ]; then
            continue
        fi

        local run_name ts tasks tpt stall fp avg_dur
        run_name=$(basename "$run_dir")
        ts=$(jq -r '.timestamp // "?"' "$meta" | cut -c1-19)
        tasks=$(jq '.tasks_completed // 0' "$meta")
        tpt=$(jq '.tokens_per_task // 0' "$meta")
        stall=$(jq '.stall_rate // 0' "$meta" | awk '{printf "%.0f", $1*100}')
        fp=$(jq '.first_pass_success_rate // 0' "$meta" | awk '{printf "%.0f", $1*100}')
        avg_dur=$(jq '.avg_iteration_duration_seconds // 0' "$meta")

        printf "%-8s %-22s %-8s %-12s %-10s %-10s %-8s\n" \
            "$run_name" "$ts" "$tasks" "$tpt" "${stall}%" "${fp}%" "${avg_dur}s"
    done

    echo ""

    # Trend analysis
    echo "Trends (last 5 runs):"
    local recent_tpts=()
    local recent_stalls=()
    for run_dir in $(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | tail -5); do
        local meta="$run_dir/run_metadata.json"
        if [ -f "$meta" ]; then
            recent_tpts+=($(jq '.tokens_per_task // 0' "$meta"))
            recent_stalls+=($(jq '.stall_rate // 0' "$meta"))
        fi
    done

    if [ "${#recent_tpts[@]}" -ge 2 ]; then
        local first_tpt="${recent_tpts[0]}"
        local last_tpt="${recent_tpts[${#recent_tpts[@]}-1]}"
        if [ "$first_tpt" -gt "$last_tpt" ] 2>/dev/null; then
            echo "  Tokens/task: improving (${first_tpt} -> ${last_tpt})"
        elif [ "$first_tpt" -lt "$last_tpt" ] 2>/dev/null; then
            echo "  Tokens/task: regressing (${first_tpt} -> ${last_tpt})"
        else
            echo "  Tokens/task: stable (${last_tpt})"
        fi
    fi

    echo ""
    exit 0
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
    local plan_file="IMPLEMENTATION_PLAN.md"
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi
    {
        echo ""
        echo "## ESCALATION"
        echo ""
        echo "ESCALATION: $description"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Phase: $current_phase, Iteration: $iteration"
    } >> "$plan_file"

    # Persist current state for --resume
    write_state

    # Commit state and plan so no work is lost on exit
    git add IMPLEMENTATION_PLAN.md "$AUTOMATON_DIR/state.json" "$AUTOMATON_DIR/session.log" "$AUTOMATON_DIR/budget.json" 2>/dev/null || true
    git commit -m "automaton: escalation - $description" 2>/dev/null || true

    exit 3
}

# ---------------------------------------------------------------------------
# Context Efficiency (spec-24)
# ---------------------------------------------------------------------------

# Generates .automaton/context_summary.md at each phase transition.
# Contains: project state, completed tasks, remaining tasks, key decisions,
# recently modified files.
generate_context_summary() {
    local summary_file="$AUTOMATON_DIR/context_summary.md"
    local plan_file="IMPLEMENTATION_PLAN.md"

    # In self-build mode, use backlog
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    {
        echo "# Context Summary"
        echo ""
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Phase: $current_phase | Iteration: $iteration"
        echo ""

        # Completed tasks
        echo "## Completed Tasks"
        if [ -f "$plan_file" ]; then
            grep '\[x\]' "$plan_file" | tail -10 || echo "None yet."
        else
            echo "No plan file found."
        fi
        echo ""

        # Remaining tasks
        echo "## Remaining Tasks"
        if [ -f "$plan_file" ]; then
            grep '\[ \]' "$plan_file" | head -10 || echo "All tasks complete."
        else
            echo "No plan file found."
        fi
        echo ""

        # Recently modified files
        echo "## Recently Modified Files"
        git log --oneline --name-only -5 2>/dev/null | grep -v '^[a-f0-9]' | sort -u | head -15 || echo "No git history."
        echo ""

        # Budget status
        echo "## Budget Status"
        if [ -f "$AUTOMATON_DIR/budget.json" ]; then
            if [ "$BUDGET_MODE" = "allowance" ]; then
                local used remaining
                used=$(jq '.tokens_used_this_week' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                remaining=$(jq '.tokens_remaining' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                echo "Mode: allowance | Used this week: $used | Remaining: $remaining"
            else
                local cost
                cost=$(jq '.used.estimated_cost_usd' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                echo "Mode: api | Cost so far: \$$cost / \$$BUDGET_MAX_USD"
            fi
        fi
    } > "$summary_file"

    log "ORCHESTRATOR" "Context summary generated: $summary_file"
}

# Injects dynamic runtime context into the <dynamic_context> section of a prompt
# file. Replaces placeholder content between <dynamic_context> and </dynamic_context>
# with iteration number, budget remaining, recent diffs, and phase-specific data.
# The static prefix (everything before <dynamic_context>) is preserved byte-for-byte,
# enabling prompt caching (spec-30).
#
# Args: prompt_file
# Outputs: path to augmented prompt file (or empty string if no injection needed)
inject_dynamic_context() {
    local prompt_file="$1"
    local augmented="$AUTOMATON_DIR/prompt_augmented.md"

    # If no <dynamic_context> tag found, skip injection
    if ! grep -q '<dynamic_context>' "$prompt_file"; then
        echo ""
        return 0
    fi

    {
        # Static prefix: everything up to and including <dynamic_context>
        sed -n '1,/<dynamic_context>/p' "$prompt_file"

        # --- Dynamic content injected by orchestrator ---
        echo "## Current State"
        echo ""
        echo "- Phase: $current_phase"
        echo "- Iteration: $phase_iteration"

        # Budget remaining
        if [ -f "$AUTOMATON_DIR/budget.json" ]; then
            local remaining
            remaining=$(jq '.tokens_remaining // "unknown"' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "unknown")
            echo "- Budget remaining: $remaining tokens"
        fi
        echo ""

        # Context summary if available
        if [ -f "$AUTOMATON_DIR/context_summary.md" ]; then
            cat "$AUTOMATON_DIR/context_summary.md"
            echo ""
        fi

        # Build-specific context for iterations after the first
        if [ "$current_phase" = "build" ] && [ "$phase_iteration" -gt 1 ]; then
            local plan_file="IMPLEMENTATION_PLAN.md"
            if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
                plan_file="$AUTOMATON_DIR/backlog.md"
            fi

            echo "## Recent Changes"
            echo '```'
            git diff --stat HEAD~3 2>/dev/null || echo "No recent changes."
            echo '```'
            echo ""

            echo "## Current Focus"
            if [ -f "$plan_file" ]; then
                grep '\[ \]' "$plan_file" | head -5 || echo "All tasks complete."
            fi
            echo ""

            if [ -f "$AUTOMATON_DIR/iteration_memory.md" ]; then
                echo "## Recent Iteration History"
                tail -5 "$AUTOMATON_DIR/iteration_memory.md"
                echo ""
            fi

            if [ "$SELF_BUILD_ENABLED" = "true" ] && [ -f "automaton.sh" ]; then
                echo "## Codebase Overview (automaton.sh)"
                echo '```'
                grep -n '^[a-z_]*()' automaton.sh | head -40 || true
                echo '```'
                echo ""
            fi
        fi

        # Suffix: </dynamic_context> and everything after
        sed -n '/<\/dynamic_context>/,$p' "$prompt_file"
    } > "$augmented"

    echo "$augmented"
}

# Tracks prompt size and logs it. Called before each agent invocation.
# Args: prompt_file
log_prompt_size() {
    local prompt_file="$1"
    if [ ! -f "$prompt_file" ]; then
        return 0
    fi

    local char_count est_tokens
    char_count=$(wc -c < "$prompt_file")
    est_tokens=$((char_count / 4))

    log "ORCHESTRATOR" "Prompt size: ${char_count} chars (~${est_tokens} tokens) from $prompt_file"
}

# Appends a one-line summary to .automaton/iteration_memory.md after each
# build iteration. Included in context for subsequent iterations.
append_iteration_memory() {
    local memory_file="$AUTOMATON_DIR/iteration_memory.md"

    # Get files changed and a short summary
    local files_summary
    files_summary=$(git diff --name-only HEAD~1 2>/dev/null | head -3 | tr '\n' ', ' || echo "none")
    files_summary="${files_summary%, }"

    local line_info
    line_info=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | sed 's/^ *//' || echo "no changes")

    echo "[BUILD $phase_iteration] $files_summary: $line_info" >> "$memory_file"
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

    # Inject dynamic context (iteration, budget, diffs) into <dynamic_context>
    # section at the end of the prompt, preserving the static prefix for
    # prompt caching (spec-29, spec-30)
    local effective_prompt="$prompt_file"
    local augmented
    augmented=$(inject_dynamic_context "$prompt_file")
    if [ -n "$augmented" ] && [ -f "$augmented" ]; then
        effective_prompt="$augmented"
    fi

    # Log prompt size for token efficiency tracking (spec-24)
    log_prompt_size "$effective_prompt"

    local cmd_args=("-p" "--output-format" "stream-json" "--model" "$model")

    if [ "$FLAG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
        cmd_args+=("--dangerously-skip-permissions")
    fi

    if [ "$FLAG_VERBOSE" = "true" ]; then
        cmd_args+=("--verbose")
    fi

    log "ORCHESTRATOR" "Invoking agent: model=$model prompt=$effective_prompt"

    AGENT_RESULT=""
    AGENT_EXIT_CODE=0

    # Capture stdout (stream-json) and stderr (errors, verbose logs) together.
    # extract_tokens() greps for "type":"result" lines so stderr noise is harmless.
    # Error classifiers (is_rate_limit, is_network_error) need stderr to detect failures.
    AGENT_RESULT=$(cat "$effective_prompt" | claude "${cmd_args[@]}" 2>&1) || AGENT_EXIT_CODE=$?

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
ARG_SELF=false
ARG_CONTINUE=false
ARG_STATS=false

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
        --self)
            ARG_SELF=true
            shift
            ;;
        --continue)
            ARG_CONTINUE=true
            shift
            ;;
        --stats)
            ARG_STATS=true
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
  --self            Self-build mode: improve automaton itself (spec-25)
  --self --continue Auto-pick highest-priority backlog item and run (spec-26)
  --stats           Display run history and performance trends (spec-26)
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

# --- Check system dependencies (claude, jq, git) ---
# automaton.sh requires all three; fail fast with install instructions if missing.
_dep_missing=false
for _dep_entry in \
    "claude|Install: https://docs.anthropic.com/en/docs/claude-code" \
    "jq|Install: sudo apt install jq  (Debian/Ubuntu)
           brew install jq      (macOS)" \
    "git|Install: sudo apt install git (Debian/Ubuntu)
           brew install git     (macOS)"; do
    _dep_name="${_dep_entry%%|*}"
    _dep_hint="${_dep_entry#*|}"
    if ! command -v "$_dep_name" >/dev/null 2>&1; then
        echo "Error: '${_dep_name}' is required but not installed." >&2
        echo "  ${_dep_hint}" >&2
        echo "" >&2
        _dep_missing=true
    fi
done
if [ "$_dep_missing" = "true" ]; then
    echo "automaton.sh requires claude, jq, and git. Install missing dependencies and retry." >&2
    exit 1
fi

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

# --- Self-build mode activation (spec-25) ---
if [ "$ARG_SELF" = "true" ]; then
    SELF_BUILD_ENABLED="true"
    BUDGET_MODE="allowance"
    log "ORCHESTRATOR" "Self-build mode activated: self_build.enabled=true, budget.mode=allowance"
fi

# --- Check parallel-mode dependencies (tmux, git worktree support) ---
# When parallel.enabled is true, tmux and git 2.5+ are required.
# Check after load_config so PARALLEL_ENABLED is resolved.
if [ "$PARALLEL_ENABLED" = "true" ]; then
    _par_dep_missing=false

    # tmux is required for multi-window builder management
    if ! command -v tmux >/dev/null 2>&1; then
        echo "Error: 'tmux' is required for parallel mode but not installed." >&2
        echo "  Install: sudo apt install tmux  (Debian/Ubuntu)" >&2
        echo "           brew install tmux      (macOS)" >&2
        echo "" >&2
        _par_dep_missing=true
    fi

    # git worktree requires git 2.5+; each builder needs an isolated worktree
    _git_version=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -n "$_git_version" ]; then
        _git_major="${_git_version%%.*}"
        _git_minor="${_git_version#*.}"
        if [ "$_git_major" -lt 2 ] || { [ "$_git_major" -eq 2 ] && [ "$_git_minor" -lt 5 ]; }; then
            echo "Error: parallel mode requires git 2.5+ for worktree support (found git ${_git_version})." >&2
            echo "  Upgrade: sudo apt install git  (Debian/Ubuntu)" >&2
            echo "           brew install git      (macOS)" >&2
            echo "" >&2
            _par_dep_missing=true
        fi
    else
        echo "Error: could not determine git version." >&2
        _par_dep_missing=true
    fi

    if [ "$_par_dep_missing" = "true" ]; then
        echo "Parallel mode (parallel.enabled=true) requires tmux and git 2.5+. Install missing dependencies and retry." >&2
        echo "Alternatively, set parallel.enabled to false in your config to use single-builder mode." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Signal Handlers
# ---------------------------------------------------------------------------

# Graceful shutdown handler for SIGINT (Ctrl+C) and SIGTERM.
# Saves state so the run can be resumed with --resume, logs the interruption,
# and exits with code 130 (standard for SIGINT-terminated processes).
_handle_shutdown() {
    local signal="$1"
    # Clean up any temp plan prompt file (spec-18)
    cleanup_parallel_plan_prompt 2>/dev/null || true
    # Clean up tmux builder/dashboard windows (spec-15)
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        cleanup_tmux_session 2>/dev/null || true
    fi
    # Guard: only attempt state save if initialization has run (state vars exist)
    if [ -n "${started_at:-}" ]; then
        write_state 2>/dev/null || true
        log "ORCHESTRATOR" "Interrupted by user (SIG${signal}). State saved for --resume." 2>/dev/null || true
    else
        echo "[ORCHESTRATOR] Interrupted before initialization (SIG${signal})." >&2
    fi
    exit 130
}

trap '_handle_shutdown INT' INT
trap '_handle_shutdown TERM' TERM
trap '' HUP

# ---------------------------------------------------------------------------
# Conductor - tmux Session Management (spec-15)
# ---------------------------------------------------------------------------

# Creates a tmux session for parallel builds.  The session hosts the conductor
# in window 0 and optionally a live dashboard in a second window.  If the
# script is already running inside tmux, the existing session is reused.
# Called once after dependency checks when PARALLEL_ENABLED is true.
start_tmux_session() {
    local session="$TMUX_SESSION_NAME"

    # If we are already inside a tmux session, reuse it
    if [ -n "${TMUX:-}" ]; then
        log "CONDUCTOR" "Already in tmux session. Using current session."
    elif tmux has-session -t "$session" 2>/dev/null; then
        log "CONDUCTOR" "Attaching to existing tmux session: $session"
    else
        tmux new-session -d -s "$session" -n "conductor"
        log "CONDUCTOR" "Created tmux session: $session"
    fi

    # Create dashboard window if configured
    if [ "$PARALLEL_DASHBOARD" = "true" ]; then
        # Kill stale dashboard window from a previous run, if any
        tmux kill-window -t "$session:dashboard" 2>/dev/null || true
        tmux new-window -t "$session" -n "dashboard" \
            "watch -n2 cat .automaton/dashboard.txt"
        log "CONDUCTOR" "Dashboard window created (watch -n2)"
    fi
}

# Tears down builder and dashboard windows inside the tmux session.
# The session itself is preserved because the conductor may still be running
# in window 0.  Called from _handle_shutdown() and on clean exit.
cleanup_tmux_session() {
    local session="$TMUX_SESSION_NAME"

    # Kill any remaining builder windows
    for i in $(seq 1 "$MAX_BUILDERS"); do
        tmux kill-window -t "$session:builder-$i" 2>/dev/null || true
    done

    # Kill dashboard window
    tmux kill-window -t "$session:dashboard" 2>/dev/null || true

    log "CONDUCTOR" "Cleaned up tmux session: $session"
}

# ---------------------------------------------------------------------------
# Conductor - Builder Spawning and Monitoring (spec-15)
# ---------------------------------------------------------------------------

# Spawns builder processes in tmux windows, one per assignment.
# For each assignment: creates an isolated git worktree, then launches a tmux
# window running builder-wrapper.sh with the builder number, wave number, and
# project root as arguments.  Staggers starts by PARALLEL_STAGGER_SECONDS to
# distribute API load.
# WHY: spawning is the step that launches parallel work; staggered timing
# distributes API load across the rate limit window. (spec-15, spec-20)
# Usage: spawn_builders <wave>
spawn_builders() {
    local wave=$1
    local session="$TMUX_SESSION_NAME"
    local builder_count
    builder_count=$(jq '.assignments | length' "$AUTOMATON_DIR/wave/assignments.json")
    local stagger="$PARALLEL_STAGGER_SECONDS"
    local project_root
    project_root=$(pwd)

    log "CONDUCTOR" "Wave $wave: spawning $builder_count builders (stagger: ${stagger}s)"

    local i
    for ((i = 1; i <= builder_count; i++)); do
        # Create an isolated worktree for this builder
        create_worktree "$i" "$wave"

        local worktree="$AUTOMATON_DIR/worktrees/builder-$i"

        # Spawn a tmux window running the builder wrapper
        # The wrapper reads its assignment, invokes claude, and writes results
        tmux new-window -t "$session" -n "builder-$i" \
            "cd $worktree && bash ${project_root}/.automaton/wave/builder-wrapper.sh $i $wave $project_root; exit"

        log "CONDUCTOR" "Wave $wave: spawned builder-$i (worktree: $worktree)"

        # Stagger starts to distribute API load (skip after last builder)
        if [ "$i" -lt "$builder_count" ] && [ "$stagger" -gt 0 ]; then
            sleep "$stagger"
        fi
    done
}

# Polls for builder result files every 5 seconds until all builders complete or
# the wave timeout is reached.  Updates the dashboard on each poll cycle to show
# real-time progress.
# WHY: polling is how the conductor detects builder completion; the 5s interval
# balances responsiveness with file-system overhead. (spec-15, spec-16)
# Usage: poll_builders <wave>
# Returns: 0 = all builders completed, 1 = timeout
poll_builders() {
    local wave=$1
    local builder_count
    builder_count=$(jq '.assignments | length' "$AUTOMATON_DIR/wave/assignments.json")
    local timeout="$WAVE_TIMEOUT_SECONDS"
    local start_time
    start_time=$(date +%s)
    local completed=0

    log "CONDUCTOR" "Wave $wave: polling $builder_count builders (timeout: ${timeout}s)"

    while [ "$completed" -lt "$builder_count" ]; do
        completed=0

        local i
        for ((i = 1; i <= builder_count; i++)); do
            if [ -f "$AUTOMATON_DIR/wave/results/builder-${i}.json" ]; then
                completed=$((completed + 1))
            fi
        done

        # Update dashboard with current progress
        write_dashboard

        # Check for timeout (0 = disabled)
        if [ "$timeout" -gt 0 ]; then
            local now elapsed
            now=$(date +%s)
            elapsed=$((now - start_time))
            if [ "$elapsed" -ge "$timeout" ]; then
                log "CONDUCTOR" "Wave $wave: timeout after ${elapsed}s ($completed/$builder_count complete)"
                handle_wave_timeout "$wave"
                return 1
            fi
        fi

        # Wait before next poll (skip if all done)
        if [ "$completed" -lt "$builder_count" ]; then
            sleep 5
        fi
    done

    log "CONDUCTOR" "Wave $wave: all $builder_count builders complete"
    return 0
}

# Handles wave timeout by terminating builders that haven't written result files.
# Sends SIGINT (C-c) to give builders 10 seconds for graceful shutdown, then
# kills the tmux window.  Writes a timeout result file for each incomplete
# builder so the conductor has complete data for all builders.
# WHY: timed-out builders must be terminated to prevent infinite waves; writing
# timeout results ensures the conductor has complete data. (spec-15)
# Usage: handle_wave_timeout <wave>
handle_wave_timeout() {
    local wave=$1
    local session="$TMUX_SESSION_NAME"
    local builder_count
    builder_count=$(jq '.assignments | length' "$AUTOMATON_DIR/wave/assignments.json")

    local i
    for ((i = 1; i <= builder_count; i++)); do
        # Only handle builders that haven't written a result file
        if [ ! -f "$AUTOMATON_DIR/wave/results/builder-${i}.json" ]; then
            log "CONDUCTOR" "Wave $wave: builder-$i timed out. Terminating."

            # Send SIGINT for graceful shutdown
            tmux send-keys -t "$session:builder-$i" C-c 2>/dev/null || true

            # Wait for graceful shutdown
            sleep 10

            # Force-kill the window if still alive
            tmux kill-window -t "$session:builder-$i" 2>/dev/null || true

            # Write a timeout result file so the conductor has complete data
            local task
            task=$(jq -r ".assignments[$((i - 1))].task" "$AUTOMATON_DIR/wave/assignments.json")

            cat > "$AUTOMATON_DIR/wave/results/builder-${i}.json" << TIMEOUT_EOF
{
  "builder": $i,
  "wave": $wave,
  "status": "timeout",
  "task": $(jq ".assignments[$((i - 1))].task" "$AUTOMATON_DIR/wave/assignments.json"),
  "exit_code": -1,
  "tokens": {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0},
  "estimated_cost_usd": 0,
  "duration_seconds": $WAVE_TIMEOUT_SECONDS,
  "files_changed": [],
  "git_commit": null
}
TIMEOUT_EOF
        fi
    done
}

# ---------------------------------------------------------------------------
# Parallel Planning Prompt Extension (spec-18)
# ---------------------------------------------------------------------------

# When parallel.enabled is true, the planning agent needs to annotate tasks
# with file-ownership hints (<!-- files: ... -->).  This function creates a
# temp copy of PROMPT_plan.md with the annotation instructions appended so that
# the planner produces the annotations the conductor needs for task partitioning.
#
# Sets PARALLEL_PLAN_PROMPT to the temp file path (caller must clean up).
# If parallel is disabled, sets PARALLEL_PLAN_PROMPT="" (no-op).
prepare_parallel_plan_prompt() {
    PARALLEL_PLAN_PROMPT=""
    if [ "${PARALLEL_ENABLED:-false}" != "true" ]; then
        return 0
    fi

    PARALLEL_PLAN_PROMPT=$(mktemp "${TMPDIR:-/tmp}/automaton-plan-XXXXXX.md")
    cat PROMPT_plan.md > "$PARALLEL_PLAN_PROMPT"

    cat >> "$PARALLEL_PLAN_PROMPT" <<'PLAN_EXT'

---

## File Ownership Annotations (for parallel builds)

For each task in the implementation plan, add a file ownership annotation on the
line immediately below the task. Use this format:

  - [ ] Task description (WHY: rationale)
    <!-- files: path/to/file1.ts, path/to/file2.ts -->

List all files that this task will create or modify, including test files. Be
specific — use actual file paths, not directories. If you're unsure which files
a task will touch, omit the annotation.

These annotations enable parallel builders to work on non-conflicting tasks
simultaneously. Better annotations = more parallelism = faster builds.
PLAN_EXT

    log "ORCHESTRATOR" "Parallel mode: augmented plan prompt with file-ownership annotations"
}

# Cleans up the temp plan prompt file created by prepare_parallel_plan_prompt().
cleanup_parallel_plan_prompt() {
    if [ -n "${PARALLEL_PLAN_PROMPT:-}" ] && [ -f "$PARALLEL_PLAN_PROMPT" ]; then
        rm -f "$PARALLEL_PLAN_PROMPT"
        PARALLEL_PLAN_PROMPT=""
    fi
}

# ---------------------------------------------------------------------------
# Task Partitioning (spec-18)
# ---------------------------------------------------------------------------

# Builds a conflict graph from IMPLEMENTATION_PLAN.md by extracting all
# incomplete ([ ]) tasks with their <!-- files: ... --> annotations.
# Produces .automaton/wave/tasks.json as a JSON array of {line, task, files[]}.
# WHY: The conflict graph is the input to task selection; it must be rebuilt
# before each wave since completed tasks change the set.
build_conflict_graph() {
    local plan="IMPLEMENTATION_PLAN.md"
    local tasks_file=".automaton/wave/tasks.json"

    awk '
    /^- \[ \]/ {
        task_line = NR
        task_text = $0
        sub(/^- \[ \] /, "", task_text)
        # Read next line for annotation
        getline
        if ($0 ~ /<!-- files:/) {
            files = $0
            gsub(/.*<!-- files: /, "", files)
            gsub(/ -->.*/, "", files)
        } else {
            files = ""
        }
        print task_line "\t" task_text "\t" files
    }
    ' "$plan" | jq -R -s '
        split("\n") | map(select(. != "")) | map(
            split("\t") | {
                line: (.[0] | tonumber),
                task: .[1],
                files: (.[2] | split(", ") | map(select(. != "")))
            }
        )
    ' > "$tasks_file"

    log "CONDUCTOR" "Conflict graph built: $(jq length "$tasks_file") incomplete tasks"
}

# Checks whether two tasks conflict based on their file lists.
# Takes two comma-separated file lists. Returns 0 (conflict) if they share
# any file or if either list is empty (unannotated). Returns 1 (no conflict).
# WHY: Pairwise conflict check is the core predicate used by select_wave_tasks.
tasks_conflict() {
    local task1_files="$1"
    local task2_files="$2"

    # Empty files list = unannotated = conflicts with everything
    if [ -z "$task1_files" ] || [ -z "$task2_files" ]; then
        return 0  # conflict
    fi

    # Check for any shared file
    local f1 f2
    for f1 in $(echo "$task1_files" | tr ',' ' '); do
        for f2 in $(echo "$task2_files" | tr ',' ' '); do
            if [ "$f1" = "$f2" ]; then
                return 0  # conflict
            fi
        done
    done

    return 1  # no conflict
}

# Selects non-conflicting tasks for a wave using greedy plan-order algorithm.
# Reads .automaton/wave/tasks.json, selects up to MAX_BUILDERS tasks that don't
# share files. Unannotated tasks can only run alone. Writes selected tasks to
# .automaton/wave/selected.json and outputs the JSON to stdout.
# WHY: This determines how many tasks can run in parallel per wave.
select_wave_tasks() {
    local tasks_file=".automaton/wave/tasks.json"
    local selected_file=".automaton/wave/selected.json"
    local max="${MAX_BUILDERS:-3}"

    if [ ! -f "$tasks_file" ]; then
        echo "[]"
        return 0
    fi

    local task_count
    task_count=$(jq 'length' "$tasks_file")

    if [ "$task_count" -eq 0 ]; then
        echo "[]" > "$selected_file"
        echo "[]"
        return 0
    fi

    # Use jq to implement the greedy selection algorithm:
    # - Iterate tasks in plan order
    # - Skip if files overlap with already-selected tasks
    # - Unannotated tasks (empty files) can only run alone
    # - Stop at max_builders
    jq --argjson max "$max" '
        def files_overlap(a; b):
            any(a[]; . as $f | any(b[]; . == $f));

        reduce .[] as $task (
            {selected: [], used_files: []};

            if (.selected | length) >= $max then
                .
            elif ($task.files | length) == 0 then
                # Unannotated task — can only run alone
                if (.selected | length) == 0 then
                    .selected = [$task] | .done = true
                else
                    .
                end
            elif .done then
                .
            else
                # Capture used_files as a variable to avoid jq scoping issues
                # inside the files_overlap filter arguments
                .used_files as $uf |
                if files_overlap($task.files; $uf) then
                    .
                else
                    .selected += [$task] |
                    .used_files += $task.files
                end
            end
        ) | .selected
    ' "$tasks_file" > "$selected_file"

    local selected_count
    selected_count=$(jq 'length' "$selected_file")
    log "CONDUCTOR" "Wave task selection: $selected_count/$task_count tasks selected (max $max builders)"

    cat "$selected_file"
}

# Logs annotation coverage to help assess partition quality.
# Calculates the percentage of incomplete tasks that have file annotations.
# Emits a warning if coverage is below 50%.
# WHY: Low annotation coverage means limited parallelism; the warning helps
# humans understand why builds are slow.
log_partition_quality() {
    local total
    local annotated

    total=$(grep -c '^\- \[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$total" -eq 0 ]; then
        log "CONDUCTOR" "Task annotations: 0/0 (no incomplete tasks)"
        return 0
    fi

    # Count annotation lines that follow a [ ] task line
    # We count <!-- files: lines in the plan as proxy for annotated tasks
    annotated=$(grep -c '<!-- files:' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    local coverage=$((annotated * 100 / total))

    log "CONDUCTOR" "Task annotations: $annotated/$total ($coverage% coverage)"

    if [ "$coverage" -lt 50 ]; then
        log "CONDUCTOR" "WARN: Low annotation coverage. Parallelism will be limited."
    fi
}

# ---------------------------------------------------------------------------
# Wave Execution Lifecycle (spec-16)
# ---------------------------------------------------------------------------

# Creates .automaton/wave/assignments.json from selected tasks.
# Takes the wave number and the selected tasks JSON (output of select_wave_tasks)
# as arguments. Transforms each task into a builder assignment with sequential
# builder numbers, worktree paths, and branch names.
# WHY: assignments.json is the contract between conductor and builders; builders
# read it to get their task; spec-16
write_assignments() {
    local wave=$1
    local selected_json="$2"

    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"
    local tmp="${assignments_file}.tmp"

    # Transform the selected tasks array into the assignments format:
    # Input:  [{line, task, files}, ...]
    # Output: {wave, created_at, assignments: [{builder, task, task_line, files_owned, worktree, branch}, ...]}
    echo "$selected_json" | jq \
        --argjson wave "$wave" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg automaton_dir "$AUTOMATON_DIR" \
        '{
            wave: $wave,
            created_at: $created_at,
            assignments: [
                to_entries[] | {
                    builder: (.key + 1),
                    task: .value.task,
                    task_line: .value.line,
                    files_owned: .value.files,
                    worktree: ($automaton_dir + "/worktrees/builder-" + ((.key + 1) | tostring)),
                    branch: ("automaton/wave-" + ($wave | tostring) + "-builder-" + ((.key + 1) | tostring))
                }
            ]
        }' > "$tmp"

    mv "$tmp" "$assignments_file"

    local count
    count=$(echo "$selected_json" | jq 'length')
    log "CONDUCTOR" "Wave $wave: wrote assignments for $count builders"

    # Log each assignment
    local i
    for ((i=1; i<=count; i++)); do
        local task
        task=$(jq -r ".assignments[$((i - 1))].task" "$assignments_file")
        log "CONDUCTOR" "Wave $wave: builder-$i assigned \"$task\""
    done
}

# Reads and validates all builder result files from .automaton/wave/results/.
# Checks for required fields (builder, wave, status, tokens, exit_code) in each
# result file. Returns aggregated results as JSON to stdout, including a summary
# with counts by status and total tokens.
# WHY: result collection is the handoff point between builder execution and merge;
# validation catches corrupt or missing result files. (spec-16)
collect_results() {
    local wave=$1
    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"
    local results_dir="$AUTOMATON_DIR/wave/results"

    if [ ! -f "$assignments_file" ]; then
        log "CONDUCTOR" "Wave $wave: ERROR — assignments.json not found"
        echo '{"wave":'"$wave"',"results":[],"summary":{"total":0,"success":0,"error":0,"rate_limited":0,"timeout":0,"partial":0,"missing":0}}'
        return 1
    fi

    local builder_count
    builder_count=$(jq '.assignments | length' "$assignments_file")

    local results="[]"
    local success_count=0
    local error_count=0
    local rate_limited_count=0
    local timeout_count=0
    local partial_count=0
    local missing_count=0

    for ((i=1; i<=builder_count; i++)); do
        local result_file="$results_dir/builder-${i}.json"

        if [ ! -f "$result_file" ]; then
            log "CONDUCTOR" "Wave $wave: builder-$i result file missing"
            missing_count=$((missing_count + 1))
            # Add a synthetic missing result so downstream consumers have complete data
            results=$(echo "$results" | jq \
                --argjson builder "$i" \
                --argjson wave "$wave" \
                '. + [{
                    "builder": $builder,
                    "wave": $wave,
                    "status": "missing",
                    "task": "",
                    "task_line": 0,
                    "started_at": "",
                    "completed_at": "",
                    "duration_seconds": 0,
                    "exit_code": -1,
                    "tokens": {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0},
                    "estimated_cost": 0,
                    "git_commit": "none",
                    "files_changed": [],
                    "promise_complete": false,
                    "valid": false,
                    "validation_error": "result file missing"
                }]')
            continue
        fi

        # Validate required fields
        local valid=true
        local validation_error=""

        # Check JSON is parseable
        if ! jq '.' "$result_file" >/dev/null 2>&1; then
            valid=false
            validation_error="invalid JSON"
        else
            # Check required fields exist and have correct types
            local has_builder has_wave has_status has_tokens has_exit_code
            has_builder=$(jq 'has("builder") and (.builder | type == "number")' "$result_file")
            has_wave=$(jq 'has("wave") and (.wave | type == "number")' "$result_file")
            has_status=$(jq 'has("status") and (.status | type == "string")' "$result_file")
            has_tokens=$(jq 'has("tokens") and (.tokens | type == "object")' "$result_file")
            has_exit_code=$(jq 'has("exit_code") and (.exit_code | type == "number")' "$result_file")

            if [ "$has_builder" != "true" ]; then
                valid=false
                validation_error="missing or invalid 'builder' field"
            elif [ "$has_wave" != "true" ]; then
                valid=false
                validation_error="missing or invalid 'wave' field"
            elif [ "$has_status" != "true" ]; then
                valid=false
                validation_error="missing or invalid 'status' field"
            elif [ "$has_tokens" != "true" ]; then
                valid=false
                validation_error="missing or invalid 'tokens' field"
            elif [ "$has_exit_code" != "true" ]; then
                valid=false
                validation_error="missing or invalid 'exit_code' field"
            fi
        fi

        if [ "$valid" = "false" ]; then
            log "CONDUCTOR" "Wave $wave: builder-$i result INVALID — $validation_error"
            error_count=$((error_count + 1))
            results=$(echo "$results" | jq \
                --argjson builder "$i" \
                --argjson wave "$wave" \
                --arg verr "$validation_error" \
                '. + [{
                    "builder": $builder,
                    "wave": $wave,
                    "status": "error",
                    "task": "",
                    "task_line": 0,
                    "started_at": "",
                    "completed_at": "",
                    "duration_seconds": 0,
                    "exit_code": -1,
                    "tokens": {"input": 0, "output": 0, "cache_create": 0, "cache_read": 0},
                    "estimated_cost": 0,
                    "git_commit": "none",
                    "files_changed": [],
                    "promise_complete": false,
                    "valid": false,
                    "validation_error": $verr
                }]')
            continue
        fi

        # Valid result — add it with validation metadata
        local status
        status=$(jq -r '.status' "$result_file")
        results=$(echo "$results" | jq \
            --slurpfile r "$result_file" \
            '. + [$r[0] + {"valid": true, "validation_error": ""}]')

        # Count by status
        case "$status" in
            success)      success_count=$((success_count + 1)) ;;
            error)        error_count=$((error_count + 1)) ;;
            rate_limited) rate_limited_count=$((rate_limited_count + 1)) ;;
            timeout)      timeout_count=$((timeout_count + 1)) ;;
            partial)      partial_count=$((partial_count + 1)) ;;
            *)            error_count=$((error_count + 1)) ;;
        esac

        local duration
        duration=$(jq '.duration_seconds // 0' "$result_file")
        log "CONDUCTOR" "Wave $wave: builder-$i result collected (status: $status, ${duration}s)"
    done

    # Build the aggregated output
    local total=$((success_count + error_count + rate_limited_count + timeout_count + partial_count + missing_count))
    echo "$results" | jq \
        --argjson wave "$wave" \
        --argjson total "$total" \
        --argjson success "$success_count" \
        --argjson error "$error_count" \
        --argjson rate_limited "$rate_limited_count" \
        --argjson timeout "$timeout_count" \
        --argjson partial "$partial_count" \
        --argjson missing "$missing_count" \
        '{
            "wave": $wave,
            "results": .,
            "summary": {
                "total": $total,
                "success": $success,
                "error": $error,
                "rate_limited": $rate_limited,
                "timeout": $timeout,
                "partial": $partial,
                "missing": $missing
            }
        }'

    log "CONDUCTOR" "Wave $wave: collected $total results ($success_count success, $partial_count partial, $error_count error, $rate_limited_count rate_limited, $timeout_count timeout, $missing_count missing)"
}

# ---------------------------------------------------------------------------
# Builder Wrapper Script (spec-17)
# ---------------------------------------------------------------------------

# Generates .automaton/wave/builder-wrapper.sh before each wave.
# The wrapper is the executable that runs in each tmux builder window.
# It reads its assignment from assignments.json, generates a task-specific
# prompt header prepended to PROMPT_build.md, runs claude -p, extracts tokens
# from stream-json output, determines status (success/error/rate_limited/partial),
# captures git commit and files_changed, calculates duration, and writes a result
# JSON to .automaton/wave/results/builder-N.json.
# WHY: The builder wrapper must be generated fresh each wave because assignments
# change and config values are baked in at generation time.
generate_builder_wrapper() {
    local wrapper="$AUTOMATON_DIR/wave/builder-wrapper.sh"

    # Determine optional claude CLI flags at generation time
    local skip_perms_flag=""
    local verbose_flag=""
    if [ "$FLAG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
        skip_perms_flag="--dangerously-skip-permissions"
    fi
    if [ "$FLAG_VERBOSE" = "true" ]; then
        verbose_flag="--verbose"
    fi

    # Write the script template (single-quoted heredoc = no variable expansion).
    # Config values are injected via sed after the heredoc.
    cat > "$wrapper" << 'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

# ---- Arguments from conductor ----
BUILDER_NUM="$1"
WAVE_NUM="$2"
PROJECT_ROOT="$3"

# ---- Config values (baked in at generation time via sed) ----
BUILDER_MODEL="__CLAUDE_MODEL__"
SKIP_PERMS_FLAG="__SKIP_PERMS_FLAG__"
VERBOSE_FLAG="__VERBOSE_FLAG__"
PER_BUILDER_TPM="__PER_BUILDER_TPM__"
PER_BUILDER_RPM="__PER_BUILDER_RPM__"

# ---- Derived paths ----
ASSIGNMENTS_FILE="$PROJECT_ROOT/.automaton/wave/assignments.json"
RESULT_FILE="$PROJECT_ROOT/.automaton/wave/results/builder-${BUILDER_NUM}.json"

# ---- Read assignment from assignments.json ----
assignment=$(jq ".assignments[$((BUILDER_NUM - 1))]" "$ASSIGNMENTS_FILE")
task=$(echo "$assignment" | jq -r '.task')
task_line=$(echo "$assignment" | jq -r '.task_line')
files_owned=$(echo "$assignment" | jq -r '.files_owned | join(", ")')

# ---- Generate task-specific prompt header (spec-17) ----
HEADER=$(cat <<PROMPT_HEADER
# Builder $BUILDER_NUM — Wave $WAVE_NUM

## Your Assignment
You are builder $BUILDER_NUM in a parallel build wave. You have ONE task:

**Task:** $task

## File Ownership
You may ONLY create or modify these files (and their test files):
$files_owned

Do NOT modify any other files. If your task requires changes to files outside your ownership, note this in your commit message with the prefix "NEEDS:" and complete what you can.

## Rules
- Complete this ONE task fully. No placeholders, no TODOs, no stubs.
- Only modify files in your ownership list.
- Run tests for the files you changed.
- Mark the task as [x] in IMPLEMENTATION_PLAN.md.
- Commit all changes with a descriptive message.
- Output <promise>COMPLETE</promise> when done.

---
PROMPT_HEADER
)

# ---- Prepend header to the standard build prompt ----
PROMPT_FILE=$(mktemp)
echo "$HEADER" > "$PROMPT_FILE"
cat "$PROJECT_ROOT/PROMPT_build.md" >> "$PROMPT_FILE"

# ---- Record start time ----
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- Build claude command flags ----
claude_args=("-p" "--output-format" "stream-json" "--model" "$BUILDER_MODEL")
if [ -n "$SKIP_PERMS_FLAG" ]; then
    claude_args+=("$SKIP_PERMS_FLAG")
fi
if [ -n "$VERBOSE_FLAG" ]; then
    claude_args+=("$VERBOSE_FLAG")
fi

# ---- Run Claude agent in the worktree ----
set +e
AGENT_RESULT=$(claude "${claude_args[@]}" < "$PROMPT_FILE" 2>&1)
exit_code=$?
set -e

completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- Extract token usage from stream-json output ----
usage=$(echo "$AGENT_RESULT" | grep '"type":"result"' | tail -1 || echo '{}')
input_tokens=$(echo "$usage" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo 0)
output_tokens=$(echo "$usage" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo 0)
cache_create=$(echo "$usage" | jq -r '.usage.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)
cache_read=$(echo "$usage" | jq -r '.usage.cache_read_input_tokens // 0' 2>/dev/null || echo 0)

# ---- Determine status ----
status="success"
if [ "$exit_code" -ne 0 ]; then
    if echo "$AGENT_RESULT" | grep -qi 'rate_limit\|429\|overloaded'; then
        status="rate_limited"
    else
        status="error"
    fi
elif ! echo "$AGENT_RESULT" | grep -q '<promise>COMPLETE</promise>'; then
    status="partial"
fi

# ---- Get git info from the worktree ----
git_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")
files_changed=$(git diff --name-only HEAD~1 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')

# ---- Calculate duration ----
start_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || echo 0)
end_epoch=$(date -d "$completed_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$completed_at" +%s 2>/dev/null || echo 0)
duration=$((end_epoch - start_epoch))

# ---- Calculate cost estimate (simplified — conductor recalculates with correct pricing) ----
estimated_cost=$(echo "scale=4; ($input_tokens * 3 + $output_tokens * 15) / 1000000" | bc 2>/dev/null || echo "0")

# ---- Write result file (this signals completion to the conductor) ----
cat > "$RESULT_FILE" << RESULT_EOF
{
  "builder": $BUILDER_NUM,
  "wave": $WAVE_NUM,
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
  "promise_complete": $(echo "$AGENT_RESULT" | grep -q '<promise>COMPLETE</promise>' && echo "true" || echo "false")
}
RESULT_EOF

# ---- Clean up temp prompt file ----
rm -f "$PROMPT_FILE"
WRAPPER

    # Bake in config values by replacing placeholders
    sed -i "s|__CLAUDE_MODEL__|${MODEL_BUILDING}|g" "$wrapper"
    sed -i "s|__SKIP_PERMS_FLAG__|${skip_perms_flag}|g" "$wrapper"
    sed -i "s|__VERBOSE_FLAG__|${verbose_flag}|g" "$wrapper"
    sed -i "s|__PER_BUILDER_TPM__|${PER_BUILDER_TPM:-0}|g" "$wrapper"
    sed -i "s|__PER_BUILDER_RPM__|${PER_BUILDER_RPM:-0}|g" "$wrapper"

    chmod +x "$wrapper"
    log "CONDUCTOR" "Generated builder wrapper: $wrapper"
}

# Checks whether a builder modified files outside its assigned ownership list.
# Compares files_changed from the builder's result file against files_owned
# from assignments.json.
# Returns 0 if no violations, 1 if violations found.
# WHY: File ownership is a soft constraint enforced by prompt; post-build
# checking catches violations before merge.
check_ownership() {
    local builder=$1
    local assignment owned changed violations

    assignment=$(jq ".assignments[$((builder - 1))]" "$AUTOMATON_DIR/wave/assignments.json")
    owned=$(echo "$assignment" | jq -r '.files_owned[]')
    changed=$(jq -r '.files_changed[]' "$AUTOMATON_DIR/wave/results/builder-${builder}.json")

    violations=""
    for file in $changed; do
        if ! echo "$owned" | grep -qF "$file"; then
            violations="$violations $file"
        fi
    done

    if [ -n "$violations" ]; then
        log "CONDUCTOR" "Builder $builder ownership violation:$violations"
        return 1
    fi
    return 0
}

# Handles ownership violations for a builder by checking whether violated files
# conflict with other builders' actual changes in the same wave.
# If no conflict: allows the change (builder needed a file not in initial estimate).
# If conflict: identifies conflicting files and signals re-queue.
# Sets global REQUEUE_BUILDER (true/false) and VIOLATION_CONFLICT_FILES (space-separated).
# Returns 0 if no conflicting violations, 1 if conflicts require re-queue.
# WHY: Ownership violations must be handled gracefully to avoid silent merge
# corruption; the policy preserves the assigned owner's version on conflict.
handle_ownership_violations() {
    local builder=$1
    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"
    local result_file="$AUTOMATON_DIR/wave/results/builder-${builder}.json"

    REQUEUE_BUILDER=false
    VIOLATION_CONFLICT_FILES=""

    # Get this builder's owned and changed files
    local owned changed
    owned=$(jq -r ".assignments[$((builder - 1))].files_owned[]" "$assignments_file" 2>/dev/null)
    changed=$(jq -r '.files_changed[]' "$result_file" 2>/dev/null)

    # Find violations (files changed but not owned)
    local violations=""
    for file in $changed; do
        if ! echo "$owned" | grep -qF "$file"; then
            violations="$violations $file"
        fi
    done

    # Trim leading space
    violations="${violations# }"
    if [ -z "$violations" ]; then
        return 0
    fi

    log "CONDUCTOR" "Builder $builder ownership violations: $violations"

    # Check each violated file against other builders' actual changes in this wave
    local builder_count has_conflicts=false
    builder_count=$(jq '.assignments | length' "$assignments_file")

    for file in $violations; do
        for ((other=1; other<=builder_count; other++)); do
            [ "$other" -eq "$builder" ] && continue
            local other_result="$AUTOMATON_DIR/wave/results/builder-${other}.json"
            [ ! -f "$other_result" ] && continue

            # Check if the other builder also modified this file
            if jq -e --arg f "$file" '.files_changed[] | select(. == $f)' "$other_result" >/dev/null 2>&1; then
                log "CONDUCTOR" "Conflict: builder $builder and builder $other both modified $file"
                VIOLATION_CONFLICT_FILES="$VIOLATION_CONFLICT_FILES $file"
                has_conflicts=true
            fi
        done
    done

    VIOLATION_CONFLICT_FILES="${VIOLATION_CONFLICT_FILES# }"

    if [ "$has_conflicts" = true ]; then
        log "CONDUCTOR" "Builder $builder has conflicting ownership violations — task will be re-queued"
        REQUEUE_BUILDER=true
        return 1
    fi

    log "CONDUCTOR" "Builder $builder ownership violations are non-conflicting — allowing changes"
    return 0
}

# ---------------------------------------------------------------------------
# Merge Protocol (spec-19)
# ---------------------------------------------------------------------------

# Creates an isolated git worktree for a builder.
# Each builder works in its own worktree to enable parallel builds.
# Cleans up stale worktrees/branches from interrupted previous runs.
# WHY: each builder needs an isolated working copy; stale cleanup prevents
# errors from interrupted previous runs; spec-19
create_worktree() {
    local builder=$1
    local wave=$2
    local worktree_path="$AUTOMATON_DIR/worktrees/builder-$builder"
    local branch="automaton/wave-${wave}-builder-${builder}"

    # Remove stale worktree if exists
    if [ -d "$worktree_path" ]; then
        git worktree remove "$worktree_path" --force 2>/dev/null || true
    fi

    # Remove stale branch if exists
    git branch -D "$branch" 2>/dev/null || true

    # Create worktree from current HEAD
    git worktree add "$worktree_path" -b "$branch" HEAD

    log "CONDUCTOR" "Created worktree: $worktree_path (branch: $branch)"
}

# Removes a builder's worktree and branch after a wave completes.
# WHY: worktrees and branches must be cleaned up after each wave to avoid
# disk/ref accumulation; spec-19
cleanup_worktree() {
    local builder=$1
    local wave=$2
    local worktree_path="$AUTOMATON_DIR/worktrees/builder-$builder"
    local branch="automaton/wave-${wave}-builder-${builder}"

    # Remove worktree
    git worktree remove "$worktree_path" --force 2>/dev/null || true

    # Delete the builder branch (it's been merged or abandoned)
    git branch -D "$branch" 2>/dev/null || true

    # Prune stale worktree references
    git worktree prune
}

# Auto-resolves merge conflicts in coordination files that multiple builders
# are expected to modify concurrently (IMPLEMENTATION_PLAN.md, AGENTS.md).
# For IMPLEMENTATION_PLAN.md: takes ours, then applies [x] checkbox changes from builder.
# For AGENTS.md: takes ours, then appends builder's new additions.
# Returns 0 if file was handled (coordination file), 1 if not a coordination file.
# WHY: multiple builders marking different tasks [x] is the most common merge
# conflict; auto-resolving it is essential for parallelism; spec-19
handle_coordination_conflict() {
    local file="$1"
    local wave=$2
    local builder=$3
    local builder_branch="automaton/wave-${wave}-builder-${builder}"

    case "$file" in
        IMPLEMENTATION_PLAN.md)
            # Strategy: take ours, then apply their checkbox changes
            git checkout --ours "$file"

            # Extract tasks marked [x] by this builder (from their branch)
            local their_completed
            their_completed=$(git show "$builder_branch:$file" | grep '\[x\]' || true)

            # For each task they completed, mark it in ours
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                # Extract the task text (everything after "[x] ")
                local task_text="${line#*\[x\] }"
                # Find the matching [ ] line by fixed-string search (no regex escaping needed)
                local line_num
                line_num=$(grep -nF "[ ] $task_text" "$file" | head -1 | cut -d: -f1)
                if [ -n "$line_num" ]; then
                    # Replace only on the matched line — simple and safe
                    sed -i "${line_num}s/\[ \]/[x]/" "$file"
                fi
            done <<< "$their_completed"

            git add "$file"
            log "CONDUCTOR" "Wave $wave: auto-resolved IMPLEMENTATION_PLAN.md conflict (builder-$builder)"
            return 0
            ;;
        AGENTS.md)
            # Strategy: take ours, then append builder's new additions
            git checkout --ours "$file"

            # Find what the builder added relative to the merge base
            local merge_base their_additions
            merge_base=$(git merge-base HEAD "$builder_branch" 2>/dev/null || echo "HEAD")
            their_additions=$(git diff "$merge_base" "$builder_branch" -- "$file" \
                | grep '^+' | grep -v '^+++' | sed 's/^+//' || true)

            if [ -n "$their_additions" ]; then
                printf '%s\n' "$their_additions" >> "$file"
                git add "$file"
            fi

            log "CONDUCTOR" "Wave $wave: auto-resolved AGENTS.md conflict (builder-$builder)"
            return 0
            ;;
    esac

    return 1  # not a coordination file
}

# Handles real source file conflicts by aborting the merge and marking the
# builder's task for re-queue. Re-queued tasks run as single-builder waves
# in the next iteration to avoid the conflict.
# WHY: real source conflicts mean the task partitioning missed a file overlap;
# the task must be re-queued for single-builder execution to resolve it; spec-19
handle_source_conflict() {
    local wave=$1
    local builder=$2
    local conflicting_files="$3"

    log "CONDUCTOR" "Wave $wave: builder-$builder has source conflicts: $conflicting_files"

    # Abort this builder's merge
    git merge --abort

    # Mark this builder's task for re-queue in assignments.json
    jq ".assignments[$((builder - 1))].requeue = true" \
        "$AUTOMATON_DIR/wave/assignments.json" > "$AUTOMATON_DIR/wave/assignments.json.tmp" \
        && mv "$AUTOMATON_DIR/wave/assignments.json.tmp" "$AUTOMATON_DIR/wave/assignments.json"

    log "CONDUCTOR" "Wave $wave: builder-$builder task re-queued for single-builder execution"
    return 0
}

# Implements the three-tier merge strategy for all builders in a wave.
# Tier 1: Clean merge (no conflicts) — auto-proceed.
# Tier 2: Coordination file conflicts (IMPLEMENTATION_PLAN.md, AGENTS.md) — auto-resolve.
# Tier 3: Source file conflicts — abort and re-queue task for single-builder execution.
# Merges builders in order (builder-1 first); only merges success/partial builders.
# Uses --no-ff to preserve builder commit history for debugging.
# WHY: merge_wave is called after every wave and is the highest-risk operation;
# the three tiers ensure maximal work preservation; spec-19
merge_wave() {
    local wave=$1
    local builder_count
    builder_count=$(jq '.assignments | length' "$AUTOMATON_DIR/wave/assignments.json")
    local merged=0
    local failed=0
    local skipped=0

    # Track per-tier merge counts for wave history (read by update_wave_state)
    MERGE_TIER1_COUNT=0
    MERGE_TIER2_COUNT=0
    MERGE_TIER3_COUNT=0

    for ((i=1; i<=builder_count; i++)); do
        local status result_file branch
        result_file="$AUTOMATON_DIR/wave/results/builder-${i}.json"

        # Check result file exists
        if [ ! -f "$result_file" ]; then
            log "CONDUCTOR" "Wave $wave: skipping builder-$i (no result file)"
            skipped=$((skipped + 1))
            continue
        fi

        status=$(jq -r '.status' "$result_file")
        branch="automaton/wave-${wave}-builder-${i}"

        # Skip failed/timed-out builders
        if [ "$status" != "success" ] && [ "$status" != "partial" ]; then
            log "CONDUCTOR" "Wave $wave: skipping builder-$i (status: $status)"
            skipped=$((skipped + 1))
            continue
        fi

        # Verify branch exists before attempting merge
        if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
            log "CONDUCTOR" "Wave $wave: skipping builder-$i (branch $branch not found)"
            skipped=$((skipped + 1))
            continue
        fi

        # Tier 1: Attempt clean merge
        if git merge --no-ff "$branch" -m "automaton: merge wave $wave builder $i" 2>/dev/null; then
            merged=$((merged + 1))
            MERGE_TIER1_COUNT=$((MERGE_TIER1_COUNT + 1))
            log "CONDUCTOR" "Wave $wave: builder-$i merged (tier 1: clean)"
            continue
        fi

        # Merge had conflicts — check which files conflict
        local conflicting
        conflicting=$(git diff --name-only --diff-filter=U)
        local tier2_resolved=true

        for file in $conflicting; do
            if handle_coordination_conflict "$file" "$wave" "$i"; then
                continue  # Tier 2 handled this file
            else
                tier2_resolved=false
                break
            fi
        done

        if $tier2_resolved; then
            # All conflicts were coordination files — complete the merge
            git commit --no-edit
            merged=$((merged + 1))
            MERGE_TIER2_COUNT=$((MERGE_TIER2_COUNT + 1))
            log "CONDUCTOR" "Wave $wave: builder-$i merged (tier 2: coordination files)"
        else
            # Real source conflict — Tier 3
            handle_source_conflict "$wave" "$i" "$conflicting"
            failed=$((failed + 1))
            MERGE_TIER3_COUNT=$((MERGE_TIER3_COUNT + 1))
        fi
    done

    log "CONDUCTOR" "Wave $wave: merge complete ($merged merged, $failed conflicts, $skipped skipped)"
}

# ---------------------------------------------------------------------------
# Parallel Budget Management (spec-20)
# ---------------------------------------------------------------------------

# Calculates per-builder TPM/RPM allocations and injects them into the
# builder wrapper as environment variables. Called by generate_builder_wrapper()
# or by the conductor before spawning builders.
# The builder wrapper itself doesn't enforce these (the API does), but they
# are available for logging and the wrapper's cost estimate.
# Sets: PER_BUILDER_TPM, PER_BUILDER_RPM (global variables for the conductor
# to pass to builders via environment or baked-in wrapper values).
calculate_builder_rate_allocation() {
    local active_builders=$1

    if [ "$active_builders" -le 0 ]; then
        active_builders=1
    fi

    PER_BUILDER_TPM=$((RATE_TOKENS_PER_MINUTE / active_builders))
    PER_BUILDER_RPM=$((RATE_REQUESTS_PER_MINUTE / active_builders))

    log "CONDUCTOR" "Rate allocation: ${PER_BUILDER_TPM} TPM, ${PER_BUILDER_RPM} RPM per builder ($active_builders builders)"
}

# Pre-wave budget checkpoint. Verifies the budget can sustain N builders.
# Echoes the actual number of builders to spawn (may be reduced).
# Returns 0 if at least 1 builder is affordable, 1 if budget is exhausted.
# WHY: launching a wave that will exhaust the budget wastes tokens and leaves
# partial work; pre-wave checks prevent this. (spec-20, spec-16)
check_wave_budget() {
    local builder_count=$1
    local budget_file="$AUTOMATON_DIR/budget.json"

    # Read current budget state
    local total_input total_output total_cost
    total_input=$(jq '.used.total_input' "$budget_file")
    total_output=$(jq '.used.total_output' "$budget_file")
    total_cost=$(jq '.used.estimated_cost_usd' "$budget_file")
    local cumulative_tokens=$((total_input + total_output))
    local remaining_tokens=$((BUDGET_MAX_TOKENS - cumulative_tokens))

    # Estimate tokens per builder (use per-iteration budget as estimate)
    local estimated_tokens_per_builder=$BUDGET_PER_ITERATION
    local wave_tokens=$((builder_count * estimated_tokens_per_builder))

    # Check token budget
    if [ "$wave_tokens" -gt "$remaining_tokens" ]; then
        local affordable=$((remaining_tokens / estimated_tokens_per_builder))
        if [ "$affordable" -ge 2 ]; then
            log "CONDUCTOR" "Budget: reducing wave to $affordable builders (token limit)"
            echo "$affordable"
            return 0
        fi
        if [ "$affordable" -ge 1 ]; then
            log "CONDUCTOR" "Budget: single-builder only (token limit)"
            echo "1"
            return 0
        fi
        log "CONDUCTOR" "Budget: insufficient for any builder (${remaining_tokens} tokens remaining, need ${estimated_tokens_per_builder} per builder)"
        return 1
    fi

    # Estimate cost per builder
    local estimated_cost_per_builder
    estimated_cost_per_builder=$(estimate_cost "$MODEL_BUILDING" "$estimated_tokens_per_builder" 0 0 0)
    local wave_cost
    wave_cost=$(awk -v n="$builder_count" -v c="$estimated_cost_per_builder" 'BEGIN { printf "%.4f", n * c }')

    # Check cost budget
    local remaining_usd
    remaining_usd=$(awk -v total="$total_cost" -v limit="$BUDGET_MAX_USD" 'BEGIN { printf "%.4f", limit - total }')
    local cost_exceeded
    cost_exceeded=$(awk -v wc="$wave_cost" -v rem="$remaining_usd" 'BEGIN { print (wc > rem) ? "yes" : "no" }')

    if [ "$cost_exceeded" = "yes" ]; then
        local affordable
        affordable=$(awk -v rem="$remaining_usd" -v c="$estimated_cost_per_builder" 'BEGIN { printf "%d", rem / c }')
        if [ "$affordable" -ge 2 ]; then
            log "CONDUCTOR" "Budget: reducing wave to $affordable builders (cost limit)"
            echo "$affordable"
            return 0
        fi
        if [ "$affordable" -ge 1 ]; then
            log "CONDUCTOR" "Budget: single-builder only (cost limit)"
            echo "1"
            return 0
        fi
        log "CONDUCTOR" "Budget: insufficient for any builder (\$${remaining_usd} remaining, need \$${estimated_cost_per_builder} per builder)"
        return 1
    fi

    echo "$builder_count"
    return 0
}

# Handles rate-limit events detected from builder result files.
# Updates rate.json with backoff_until, sleeps for cooldown, then clears.
# WHY: rate limits during a wave affect the entire API account; the next wave
# must wait for the backoff period. (spec-20)
handle_wave_rate_limit() {
    local wave=$1
    local builder=$2

    log "CONDUCTOR" "Wave $wave: builder-$builder hit rate limit. Pausing before next wave."

    local backoff="$RATE_COOLDOWN_SECONDS"

    # Calculate backoff_until (portable across GNU and BSD date)
    local backoff_until
    backoff_until=$(date -u -d "+${backoff} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
        date -u -v "+${backoff}S" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
        date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update rate state
    local rate_file="$AUTOMATON_DIR/rate.json"
    local tmp="${rate_file}.tmp"
    jq --arg until "$backoff_until" \
       '.backoff_until = $until | .last_rate_limit = (now | todate)' \
       "$rate_file" > "$tmp"
    mv "$tmp" "$rate_file"

    # Wait for the backoff period
    log "CONDUCTOR" "Rate limit backoff: waiting ${backoff}s"
    sleep "$backoff"

    # Clear backoff
    jq '.backoff_until = null' "$rate_file" > "$tmp"
    mv "$tmp" "$rate_file"

    log "CONDUCTOR" "Rate limit backoff complete."
}

# Handles budget exhaustion detected while builders are running.
# Lets running builders finish, then saves state and exits with code 2.
# WHY: already-spent tokens should not be wasted; collecting completed work
# before stopping preserves maximum value. (spec-20)
handle_midwave_budget_exhaustion() {
    local wave=$1

    log "CONDUCTOR" "Wave $wave: budget exhaustion detected mid-wave"

    # Do NOT kill running builders — they've already consumed tokens.
    # Let them finish their current work.
    # The caller (poll_builders/run_parallel_build) should wait for builders
    # to complete, then collect and merge results normally.

    # After all builders complete, collect and merge their results
    # (same as normal wave completion — handled by caller before we reach here)

    # Then stop — don't start another wave
    log "CONDUCTOR" "Budget exhausted. Saving state for resume."
    write_state
    exit 2
}

# Proactive velocity limiting between waves. Sums tokens from the last wave
# and sleeps if aggregate TPM exceeds 80% of the configured limit.
# WHY: inter-wave pacing prevents rate limits across consecutive waves; this
# is the wave-level equivalent of per-iteration check_pacing. (spec-20)
check_wave_pacing() {
    local rate_file="$AUTOMATON_DIR/rate.json"

    # Read last wave's aggregate token usage from rate.json history
    local wave_tokens wave_duration
    wave_tokens=$(jq '[.history[].tokens] | add // 0' "$rate_file" 2>/dev/null || echo 0)
    wave_duration=$(jq '
        if (.history | length) > 0
        then ((.history | last).duration_seconds // 60)
        else 60
        end' "$rate_file" 2>/dev/null || echo 60)

    # Ensure non-zero duration to avoid division by zero
    if [ "$wave_duration" -le 0 ]; then
        wave_duration=1
    fi

    # Calculate aggregate TPM
    local velocity=$((wave_tokens * 60 / wave_duration))
    local threshold=$((RATE_TOKENS_PER_MINUTE * 80 / 100))

    if [ "$velocity" -gt "$threshold" ]; then
        local cooldown=$((60 - wave_duration))
        if [ "$cooldown" -gt 0 ]; then
            log "CONDUCTOR" "Proactive pacing: aggregate velocity ${velocity} TPM exceeds 80% threshold (${threshold}), waiting ${cooldown}s"
            sleep "$cooldown"
        fi
    fi
}

# Aggregates token usage from all builder result files into budget.json
# after a wave completes. Each builder's tokens count against the shared
# phase and total budgets.
# WHY: builder tokens must be aggregated into the shared budget.json so
# total/phase budget enforcement works correctly. (spec-20)
aggregate_wave_budget() {
    local wave=$1
    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"
    local builder_count
    builder_count=$(jq '.assignments | length' "$assignments_file")

    local rate_file="$AUTOMATON_DIR/rate.json"
    local rate_history="[]"

    for i in $(seq 1 "$builder_count"); do
        local result="$AUTOMATON_DIR/wave/results/builder-${i}.json"
        if [ ! -f "$result" ]; then continue; fi

        local input output cache_create cache_read cost duration task_text status_val
        input=$(jq '.tokens.input // 0' "$result")
        output=$(jq '.tokens.output // 0' "$result")
        cache_create=$(jq '.tokens.cache_create // 0' "$result")
        cache_read=$(jq '.tokens.cache_read // 0' "$result")
        duration=$(jq '.duration_seconds // 0' "$result")
        task_text=$(jq -r '.task // "unknown"' "$result")
        status_val=$(jq -r '.status // "unknown"' "$result")

        # Recalculate cost with correct pricing (builder estimate is simplified)
        cost=$(estimate_cost "$MODEL_BUILDING" "$input" "$output" "$cache_create" "$cache_read")

        # Update shared budget.json via the existing update_budget function
        update_budget "$MODEL_BUILDING" "$input" "$output" \
            "$cache_create" "$cache_read" \
            "$cost" "$duration" "wave-${wave} builder-${i}: ${task_text}" "$status_val"

        # Copy result to agent history directory
        local history_num
        history_num=$(printf '%03d' "$iteration")
        cp "$result" "$AUTOMATON_DIR/agents/build-${history_num}-builder-${i}.json"

        # Accumulate rate history entry
        local total_builder_tokens=$((input + output))
        rate_history=$(echo "$rate_history" | jq \
            --argjson builder "$i" \
            --argjson tokens "$total_builder_tokens" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + [{"timestamp": $ts, "builder": $builder, "tokens": $tokens, "requests": 1}]')
    done

    # Update rate.json with this wave's consumption history
    local tmp="${rate_file}.tmp"
    jq --argjson hist "$rate_history" \
       --arg ws "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.window_start = $ws | .history = $hist | .window_tokens = ($hist | map(.tokens) | add // 0) | .window_requests = ($hist | length)' \
       "$rate_file" > "$tmp"
    mv "$tmp" "$rate_file"

    log "CONDUCTOR" "Wave $wave: budget aggregated from $builder_count builders"
}

# Runs post-merge verification checks to ensure the wave produced valid results.
# Checks: (1) build command passes if configured, (2) no unresolved merge conflict
# markers in source files, (3) plan integrity (completed count did not decrease).
# Takes $1=wave number. Expects COMPLETED_BEFORE_WAVE to be set by caller before
# the wave's merge step. Returns 0 on pass, 1 on failure.
# WHY: post-wave verification catches merge corruption before the next wave builds
# on top of it; spec-16
verify_wave() {
    local wave=$1
    local pass=true

    # Check 1: Build check (if BUILD_COMMAND configured)
    if [ -n "${BUILD_COMMAND:-}" ]; then
        if ! eval "$BUILD_COMMAND" >/dev/null 2>&1; then
            log "CONDUCTOR" "Wave $wave: post-merge build failed"
            pass=false
        fi
    fi

    # Check 2: No unresolved merge conflict markers in source files
    # Search common source extensions, exclude node_modules and .automaton
    if grep -r '<<<<<<< ' \
        --include='*.ts' --include='*.js' --include='*.py' \
        --include='*.sh' --include='*.rb' --include='*.go' \
        --include='*.java' --include='*.rs' --include='*.c' --include='*.h' \
        --include='*.cpp' --include='*.hpp' --include='*.css' --include='*.html' \
        . 2>/dev/null | grep -v node_modules | grep -v .automaton | grep -q .; then
        log "CONDUCTOR" "Wave $wave: unresolved merge conflict markers found"
        pass=false
    fi

    # Check 3: Plan integrity (completed count didn't decrease)
    local completed_after
    completed_after=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$completed_after" -lt "${COMPLETED_BEFORE_WAVE:-0}" ]; then
        log "CONDUCTOR" "Wave $wave: plan corruption detected post-merge ($completed_after < $COMPLETED_BEFORE_WAVE)"
        pass=false
    fi

    if ! $pass; then
        log "CONDUCTOR" "Wave $wave: verification FAILED — will re-run failed tasks"
        return 1
    fi

    log "CONDUCTOR" "Wave $wave: verification PASS"
    return 0
}

# Removes builder worktrees, archives wave data for debugging, clears the wave
# directory, and kills tmux builder windows. Takes $1=wave number.
# WHY: cleanup prevents disk accumulation and stale tmux windows; archived data
# enables post-run debugging; spec-16
cleanup_wave() {
    local wave=$1
    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"

    # Guard against missing assignments file (wave may not have fully started)
    if [ ! -f "$assignments_file" ]; then
        log "CONDUCTOR" "Wave $wave: cleanup skipped — no assignments.json"
        return
    fi

    local builder_count
    builder_count=$(jq '.assignments | length' "$assignments_file")

    # Step 1: Remove worktrees via existing cleanup_worktree()
    for ((i=1; i<=builder_count; i++)); do
        cleanup_worktree "$i" "$wave"
    done

    # Step 2: Archive wave data (keep for post-run debugging)
    mkdir -p "$AUTOMATON_DIR/wave-history"
    cp "$assignments_file" "$AUTOMATON_DIR/wave-history/wave-${wave}-assignments.json" 2>/dev/null || true
    if [ -d "$AUTOMATON_DIR/wave/results" ]; then
        cp -r "$AUTOMATON_DIR/wave/results" "$AUTOMATON_DIR/wave-history/wave-${wave}-results" 2>/dev/null || true
    fi

    # Step 3: Clear current wave directory for next wave
    rm -rf "$AUTOMATON_DIR/wave/results"
    mkdir -p "$AUTOMATON_DIR/wave/results"
    rm -f "$AUTOMATON_DIR/wave/assignments.json"

    # Step 4: Kill tmux builder windows (suppress errors for non-tmux runs)
    local session="${TMUX_SESSION_NAME:-automaton}"
    for ((i=1; i<=builder_count; i++)); do
        tmux kill-window -t "$session:builder-$i" 2>/dev/null || true
    done

    log "CONDUCTOR" "Wave $wave: cleanup complete"
}

# Updates IMPLEMENTATION_PLAN.md after a successful merge: marks tasks completed
# by successful builders as [x], then commits the updated plan.
# Takes $1=wave number, $2=collected results JSON (from collect_results).
# WHY: the plan is the single source of truth for progress; it must reflect
# merged work before the next wave selects tasks; spec-16
update_plan_after_wave() {
    local wave=$1
    local results_json="$2"
    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"
    local plan_file="IMPLEMENTATION_PLAN.md"

    if [ ! -f "$assignments_file" ] || [ ! -f "$plan_file" ]; then
        log "CONDUCTOR" "Wave $wave: plan update skipped — missing files"
        return 1
    fi

    local success_count=0
    local total_builders
    total_builders=$(jq '.assignments | length' "$assignments_file")

    # For each builder with success or partial status, mark its task [x]
    for ((i=0; i<total_builders; i++)); do
        local builder_num=$((i + 1))
        local status
        status=$(echo "$results_json" | jq -r ".results[$i].status // \"unknown\"")

        # Only mark tasks for successful or partial completions
        if [ "$status" != "success" ] && [ "$status" != "partial" ]; then
            continue
        fi

        local task_line
        task_line=$(jq ".assignments[$i].task_line" "$assignments_file")

        if [ -z "$task_line" ] || [ "$task_line" = "null" ] || [ "$task_line" -le 0 ] 2>/dev/null; then
            log "CONDUCTOR" "Wave $wave: builder-$builder_num has invalid task_line, skipping plan update"
            continue
        fi

        # Read the current content at that line to verify it's still an unchecked task
        local line_content
        line_content=$(sed -n "${task_line}p" "$plan_file")

        if echo "$line_content" | grep -q '\[ \]'; then
            # Replace [ ] with [x] on this specific line
            sed -i "${task_line}s/\[ \]/[x]/" "$plan_file"
            success_count=$((success_count + 1))
            log "CONDUCTOR" "Wave $wave: marked builder-$builder_num task complete (line $task_line)"
        elif echo "$line_content" | grep -q '\[x\]'; then
            # Already marked (perhaps by the builder during merge)
            success_count=$((success_count + 1))
        else
            log "CONDUCTOR" "Wave $wave: builder-$builder_num task_line $task_line is not a checkbox line, skipping"
        fi
    done

    # Commit the plan update if any tasks were marked
    if [ "$success_count" -gt 0 ]; then
        git add "$plan_file"
        git commit -m "automaton: wave $wave complete ($success_count/$total_builders tasks)" 2>/dev/null || true
        log "CONDUCTOR" "Wave $wave: plan updated and committed ($success_count/$total_builders tasks)"
    else
        log "CONDUCTOR" "Wave $wave: no tasks to mark complete"
    fi

    return 0
}

# Updates state.json after each wave: increments iteration by the number of
# successful builders, updates phase_iteration, records wave summary in
# wave_history array with builder count, success/fail counts, tasks completed,
# duration, token/cost totals, and merge tier breakdown.
# Also aggregates budget and persists state via write_state().
#
# Args: $1=wave number, $2=collected results JSON (from collect_results),
#       $3=wave start epoch (seconds since epoch, captured before spawning)
#
# Expects MERGE_TIER1_COUNT, MERGE_TIER2_COUNT, MERGE_TIER3_COUNT to be set
# by merge_wave() before this function is called.
#
# WHY: wave state enables resume and post-run analysis of parallelism
# effectiveness; spec-15, spec-21
update_wave_state() {
    local wave=$1
    local results_json="$2"
    local wave_start_epoch="$3"

    local wave_end_epoch
    wave_end_epoch=$(date +%s)
    local wave_duration=$((wave_end_epoch - wave_start_epoch))

    # Count builders and outcomes from collected results
    local total_builders success_count partial_count failed_count usable_count
    total_builders=$(echo "$results_json" | jq '.results | length')
    success_count=$(echo "$results_json" | jq '.summary.success // 0')
    partial_count=$(echo "$results_json" | jq '.summary.partial // 0')
    failed_count=$(echo "$results_json" | jq '(.summary.error // 0) + (.summary.rate_limited // 0) + (.summary.timeout // 0) + (.summary.missing // 0)')
    usable_count=$((success_count + partial_count))

    # Sum tokens from all builder results (input + output + cache tokens)
    local tokens_total
    tokens_total=$(echo "$results_json" | jq '[.results[] | .tokens | ((.input // 0) + (.output // 0) + (.cache_create // 0) + (.cache_read // 0))] | add // 0')

    # Sum estimated cost from all builder results
    local cost_total
    cost_total=$(echo "$results_json" | jq '[.results[].estimated_cost // 0] | add // 0')

    # Increment global iteration counters by number of usable builders
    # (each successful/partial builder counts as one iteration of forward progress)
    iteration=$((iteration + usable_count))
    phase_iteration=$((phase_iteration + usable_count))

    # Aggregate builder tokens into shared budget.json
    aggregate_wave_budget "$wave"

    # Build the wave history entry with full metrics
    local wave_entry
    wave_entry=$(jq -n \
        --argjson wave "$wave" \
        --argjson builders "$total_builders" \
        --argjson succeeded "$usable_count" \
        --argjson failed "$failed_count" \
        --argjson tasks "$usable_count" \
        --argjson duration "$wave_duration" \
        --argjson tokens "$tokens_total" \
        --argjson cost "$cost_total" \
        --argjson t1 "${MERGE_TIER1_COUNT:-0}" \
        --argjson t2 "${MERGE_TIER2_COUNT:-0}" \
        --argjson t3 "${MERGE_TIER3_COUNT:-0}" \
        '{
            wave: $wave,
            builders: $builders,
            succeeded: $succeeded,
            failed: $failed,
            tasks_completed: $tasks,
            duration_seconds: $duration,
            tokens_total: $tokens,
            cost_total: $cost,
            merge_tier1: $t1,
            merge_tier2: $t2,
            merge_tier3: $t3
        }')

    # Append to wave_history array (used by write_state and dashboard)
    wave_history=$(echo "${wave_history:-[]}" | jq -c --argjson entry "$wave_entry" '. + [$entry]')

    # Advance wave_number for the next wave
    wave_number=$((wave + 1))

    # Persist all state changes atomically
    write_state

    # Git push if configured
    if [ "${GIT_AUTO_PUSH:-false}" = "true" ]; then
        git push 2>/dev/null || log "CONDUCTOR" "WARN: git push failed"
    fi

    log "CONDUCTOR" "Wave $wave: state updated (iteration=$iteration, ${usable_count}/${total_builders} succeeded, ${wave_duration}s, ~\$${cost_total})"
}

# ---------------------------------------------------------------------------
# Observability — Dashboard, progress estimation, wave status (spec-21)
# ---------------------------------------------------------------------------

# The existing log() function already supports the parallel component tag format:
#   log "CONDUCTOR" "Wave 3: starting with 3 builders"
#   log "BUILD:W3:B1" "Task: Implement JWT auth"
#   log "MERGE:W3" "builder-1 merged cleanly"
# No code change is needed — callers just pass the appropriate tag string.

# Estimates the number of remaining waves based on incomplete tasks and max builders.
# WHY: gives humans a sense of progress and expected completion; +1 accounts for
# rounding and re-queued tasks. (spec-21)
estimate_remaining_waves() {
    local remaining_tasks
    remaining_tasks=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)

    if [ "$remaining_tasks" -eq 0 ]; then
        echo "0"
        return
    fi

    # Estimate: tasks_per_wave ≈ max_builders (optimistic)
    # Add 1 for rounding and re-queued tasks
    local estimated=$(( remaining_tasks / MAX_BUILDERS + 1 ))
    echo "$estimated"
}

# Formats per-builder status lines for the dashboard.
# Reads the current wave's assignments.json and any available result files to
# produce formatted status lines for each builder (running with elapsed time,
# DONE with duration, ERROR, etc.).
# WHY: builder status bars are the core visual element of the dashboard. (spec-21)
format_builder_status() {
    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"

    if [ ! -f "$assignments_file" ]; then
        echo "  (no active wave)"
        return
    fi

    local builder_count
    builder_count=$(jq '.assignments | length' "$assignments_file" 2>/dev/null || echo 0)

    if [ "$builder_count" -eq 0 ]; then
        echo "  (no builders assigned)"
        return
    fi

    local now_epoch
    now_epoch=$(date +%s)
    local wave_created
    wave_created=$(jq -r '.created_at // ""' "$assignments_file")

    for i in $(seq 1 "$builder_count"); do
        local task_text
        task_text=$(jq -r ".assignments[$((i-1))].task // \"unknown\"" "$assignments_file")
        # Truncate task text for display (max 25 chars)
        if [ "${#task_text}" -gt 25 ]; then
            task_text="${task_text:0:22}..."
        fi

        local result_file="$AUTOMATON_DIR/wave/results/builder-${i}.json"

        if [ -f "$result_file" ]; then
            # Builder has completed — show status and duration
            local status duration
            status=$(jq -r '.status // "unknown"' "$result_file")
            duration=$(jq '.duration_seconds // 0' "$result_file")

            local duration_display
            duration_display="$((duration / 60))m$((duration % 60))s"

            local status_upper
            status_upper=$(echo "$status" | tr '[:lower:]' '[:upper:]')

            printf "  builder-%-2d  %-7s  %6s  %s\n" "$i" "$status_upper" "$duration_display" "$task_text"
        else
            # Builder still running — show elapsed time
            local elapsed="?"
            if [ -n "$wave_created" ] && [ "$wave_created" != "null" ]; then
                local wave_epoch
                wave_epoch=$(date -d "$wave_created" +%s 2>/dev/null || echo "$now_epoch")
                local elapsed_sec=$((now_epoch - wave_epoch))
                elapsed="$((elapsed_sec / 60))m$((elapsed_sec % 60))s"
            fi

            printf "  builder-%-2d  running  %6s  %s\n" "$i" "$elapsed" "$task_text"
        fi
    done
}

# Generates .automaton/dashboard.txt with box-drawing format showing: phase, wave
# number, estimated total waves, budget remaining, per-builder status bars, task
# completion counts, token and cost summary, and the 6 most recent session.log events.
# WHY: the dashboard is the primary human interface during parallel builds; it must
# be updated after every significant event. (spec-21)
write_dashboard() {
    local dash="$AUTOMATON_DIR/dashboard.txt"
    local tmp="${dash}.tmp"

    # Collect current state
    local phase
    phase=$(echo "${current_phase:-build}" | tr '[:lower:]' '[:upper:]')
    local wave="${wave_number:-0}"
    local estimated_waves
    estimated_waves=$(estimate_remaining_waves)

    # Budget info from budget.json
    local budget_file="$AUTOMATON_DIR/budget.json"
    local remaining_usd="?" cost_used="?" cost_limit="?" tokens_used="?"
    if [ -f "$budget_file" ]; then
        remaining_usd=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
            "$budget_file" 2>/dev/null || echo "?")
        cost_used=$(jq -r '.used.estimated_cost_usd * 100 | floor / 100' \
            "$budget_file" 2>/dev/null || echo "?")
        cost_limit=$(jq -r '.limits.max_cost_usd' "$budget_file" 2>/dev/null || echo "?")

        local total_tokens
        total_tokens=$(jq '(.used.total_input + .used.total_output)' "$budget_file" 2>/dev/null || echo 0)
        if [ "$total_tokens" -ge 1000000 ] 2>/dev/null; then
            tokens_used="$(awk -v t="$total_tokens" 'BEGIN{printf "%.1fM", t/1000000}')"
        elif [ "$total_tokens" -ge 1000 ] 2>/dev/null; then
            tokens_used="$(awk -v t="$total_tokens" 'BEGIN{printf "%.1fK", t/1000}')"
        else
            tokens_used="$total_tokens"
        fi
    fi

    # Task counts from IMPLEMENTATION_PLAN.md
    local total_tasks completed_tasks
    total_tasks=$(grep -c '\[ \]\|\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    completed_tasks=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)

    # Remaining waves
    local remaining_waves=0
    if [ "$estimated_waves" -gt "$wave" ] 2>/dev/null; then
        remaining_waves=$((estimated_waves - wave))
    fi

    # Builder status lines
    local builder_status
    builder_status=$(format_builder_status)

    # Recent events (last 6 lines of session.log, reversed for newest-first)
    local recent_events=""
    if [ -f "$AUTOMATON_DIR/session.log" ]; then
        recent_events=$(tail -6 "$AUTOMATON_DIR/session.log" 2>/dev/null | tac | while IFS= read -r line; do
            # Extract time (HH:MM:SS) and rest of line after timestamp+component
            local time_part rest
            time_part=$(echo "$line" | sed -n 's/^\[\([^]]*\)T\([0-9:]*\)Z\].*/\2/p')
            rest=$(echo "$line" | sed 's/^\[[^]]*\] //')
            if [ -n "$time_part" ]; then
                printf "  %s  %s\n" "$time_part" "$rest"
            fi
        done)
    fi
    [ -z "$recent_events" ] && recent_events="  (no events yet)"

    # Generate the dashboard with box-drawing separators
    local sep
    sep=$(printf '═%.0s' $(seq 1 62))

    cat > "$tmp" <<EOF
╔${sep}╗
  automaton v${AUTOMATON_VERSION} — parallel build
╠${sep}╣
  Phase: ${phase}  │  Wave: ${wave}/~${estimated_waves}  │  Budget: \$${remaining_usd} remaining
╠${sep}╣

  Wave ${wave} Progress
  $(printf '─%.0s' $(seq 1 14))
${builder_status}

╠${sep}╣
  Tasks: ${completed_tasks}/${total_tasks} complete  │  Waves: ${wave} done, ~${remaining_waves} remaining
  Tokens: ${tokens_used} used  │  Cost: \$${cost_used} / \$${cost_limit}
╠${sep}╣
  Recent Events
  $(printf '─%.0s' $(seq 1 13))
${recent_events}
╚${sep}╝
EOF

    mv "$tmp" "$dash"
}

# Emits a one-line wave status to stdout for non-tmux mode.
# Called by the conductor after builder completion and wave completion events.
# WHY: users not in tmux still need progress visibility; this is the wave-level
# equivalent of per-iteration stdout output. (spec-21)
#
# Usage:
#   emit_wave_status "spawn"           — after all builders spawned
#   emit_wave_status "builder_done" N  — after builder N completes
#   emit_wave_status "complete"        — after wave completes
emit_wave_status() {
    local event="$1"
    local wave="${wave_number:-0}"
    local estimated_waves
    estimated_waves=$(estimate_remaining_waves)

    local remaining_budget
    remaining_budget=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
        "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")

    local assignments_file="$AUTOMATON_DIR/wave/assignments.json"
    local builder_count
    builder_count=$(jq '.assignments | length' "$assignments_file" 2>/dev/null || echo 0)

    case "$event" in
        spawn)
            # Show all builder assignments
            local summaries=""
            for i in $(seq 1 "$builder_count"); do
                local task
                task=$(jq -r ".assignments[$((i-1))].task // \"unknown\"" "$assignments_file")
                # Truncate to 20 chars
                if [ "${#task}" -gt 20 ]; then
                    task="${task:0:17}..."
                fi
                if [ -n "$summaries" ]; then
                    summaries="${summaries} | builder-${i}: ${task}"
                else
                    summaries="builder-${i}: ${task}"
                fi
            done
            echo "[WAVE ${wave}/~${estimated_waves}] ${builder_count} builders | ${summaries}"
            ;;

        builder_done)
            local builder_num="${2:-?}"
            local result_file="$AUTOMATON_DIR/wave/results/builder-${builder_num}.json"
            local status="?" duration="?" cost="?"
            if [ -f "$result_file" ]; then
                status=$(jq -r '.status // "?"' "$result_file")
                duration=$(jq '.duration_seconds // 0' "$result_file")
                cost=$(jq -r '.cost // "0.00"' "$result_file")
                duration="${duration}s"
            fi

            # Count remaining running builders
            local done_count=0
            for i in $(seq 1 "$builder_count"); do
                [ -f "$AUTOMATON_DIR/wave/results/builder-${i}.json" ] && done_count=$((done_count + 1))
            done
            local remaining=$((builder_count - done_count))

            local status_upper
            status_upper=$(echo "$status" | tr '[:lower:]' '[:upper:]')
            echo "[WAVE ${wave}/~${estimated_waves}] builder-${builder_num} ${status_upper} (${duration}, ~\$${cost}) | ${remaining} remaining"
            ;;

        complete)
            # Show wave completion summary
            local success_count=0 total_cost=0
            for i in $(seq 1 "$builder_count"); do
                local rf="$AUTOMATON_DIR/wave/results/builder-${i}.json"
                if [ -f "$rf" ]; then
                    local s
                    s=$(jq -r '.status // ""' "$rf")
                    [ "$s" = "success" ] || [ "$s" = "partial" ] && success_count=$((success_count + 1))
                    local c
                    c=$(jq '.cost // 0' "$rf" 2>/dev/null || echo 0)
                    total_cost=$(awk -v a="$total_cost" -v b="$c" 'BEGIN{printf "%.2f", a+b}')
                fi
            done
            echo "[WAVE ${wave}/~${estimated_waves}] COMPLETE: ${success_count}/${builder_count} merged | ~\$${total_cost} | budget: \$${remaining_budget} remaining"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Conductor - Wave Error Handling (spec-15, spec-09)
# ---------------------------------------------------------------------------

# V1 single-builder fallback for when parallel wave dispatch fails.
# Runs one build iteration using PROMPT_build.md with MODEL_BUILDING, identical
# to the v1 inner iteration loop body: invoke agent, handle errors (rate limit,
# network, CLI crash), run post-iteration pipeline (tokens, budget, stall,
# plan integrity, state, history).
#
# WHY: when parallelism fails, the system must still make forward progress;
# this is the proven single-builder path. (spec-15)
#
# Returns: 0 = iteration succeeded, 1 = iteration failed or forced transition
# May exit: 1 via handle_cli_crash, 2 via check_budget
run_single_builder_iteration() {
    local prompt_file="PROMPT_build.md"
    local model="$MODEL_BUILDING"

    phase_iteration=$((phase_iteration + 1))
    iteration=$((iteration + 1))

    log "CONDUCTOR" "Single-builder fallback: iteration $phase_iteration"

    # Checkpoint plan before build iteration (corruption guard)
    checkpoint_plan

    # Invoke the agent
    local iter_start_epoch
    iter_start_epoch=$(date +%s)
    run_agent "$prompt_file" "$model"

    # Error classification and recovery
    if [ "$AGENT_EXIT_CODE" -ne 0 ]; then
        if is_rate_limit "$AGENT_RESULT" || is_network_error "$AGENT_RESULT"; then
            if ! handle_rate_limit run_agent "$prompt_file" "$model"; then
                # All retries exhausted
                phase_iteration=$((phase_iteration - 1))
                iteration=$((iteration - 1))
                return 1
            fi
            # Successful retry — AGENT_RESULT/AGENT_EXIT_CODE updated
        else
            # Generic CLI crash — handle_cli_crash may exit 1 on max failures
            handle_cli_crash "$AGENT_EXIT_CODE" "$AGENT_RESULT"
            phase_iteration=$((phase_iteration - 1))
            iteration=$((iteration - 1))
            return 1
        fi
    fi

    reset_failure_count

    # Post-iteration pipeline (may exit 2 for budget hard stop)
    local post_rc=0
    post_iteration "$model" "$prompt_file" "$iter_start_epoch" || post_rc=$?

    if [ "$post_rc" -ne 0 ]; then
        log "CONDUCTOR" "Single-builder fallback: forced transition (reason: $TRANSITION_REASON)"
        return 1
    fi

    # Check if agent signaled COMPLETE
    if agent_signaled_complete; then
        log "CONDUCTOR" "Single-builder fallback: agent signaled COMPLETE"
    fi

    return 0
}

# Analyzes wave results and handles error conditions per the wave error taxonomy.
# Handles three scenarios:
#   1. At least one builder succeeded → reset consecutive_wave_failures, proceed to merge
#   2. All builders failed → fall back to single-builder for 1 iteration
#   3. Three consecutive wave failures → escalate to human (exit 3)
#
# Rate-limited builders trigger a backoff pause regardless of which scenario applies.
#
# WHY: wave errors are distinct from v1 iteration errors; the system must
# degrade gracefully from parallel to single-builder before escalating. (spec-15, spec-09)
#
# Args: $1=wave number, $2=collected results JSON (from collect_results)
# Returns: 0 = at least one builder succeeded; proceed to merge
#          1 = all builders failed; single-builder fallback also failed
#          2 = all builders failed; single-builder fallback succeeded; retry wave
# Exits:   3 via escalate() after 3 consecutive wave failures
handle_wave_errors() {
    local wave=$1
    local results_json="$2"

    # Read summary counts from collected results
    local success_count error_count rate_limited_count timeout_count partial_count
    success_count=$(echo "$results_json" | jq '.summary.success')
    error_count=$(echo "$results_json" | jq '.summary.error')
    rate_limited_count=$(echo "$results_json" | jq '.summary.rate_limited')
    timeout_count=$(echo "$results_json" | jq '.summary.timeout')
    partial_count=$(echo "$results_json" | jq '.summary.partial')

    # Builders that produced usable work (success or partial)
    local usable_count=$((success_count + partial_count))

    # Handle rate limits from any builder (pause before next wave)
    if [ "$rate_limited_count" -gt 0 ]; then
        local rl_builder
        rl_builder=$(echo "$results_json" | jq -r '[.results[] | select(.status == "rate_limited")][0].builder')
        handle_wave_rate_limit "$wave" "$rl_builder"
    fi

    # Case 1: At least one builder produced usable work
    if [ "$usable_count" -gt 0 ]; then
        consecutive_wave_failures=0
        log "CONDUCTOR" "Wave $wave: $usable_count builder(s) succeeded, proceeding to merge"
        return 0
    fi

    # Case 2: All builders failed
    consecutive_wave_failures=$((consecutive_wave_failures + 1))
    log "CONDUCTOR" "Wave $wave: ALL builders failed (consecutive: $consecutive_wave_failures/3)"
    log "CONDUCTOR" "Wave $wave: breakdown — $error_count error, $rate_limited_count rate_limited, $timeout_count timeout"

    # Escalate after 3 consecutive wave failures (spec-09)
    if [ "$consecutive_wave_failures" -ge 3 ]; then
        escalate "3 consecutive wave failures. Parallel build cannot make progress."
        # escalate() exits — control never reaches here
    fi

    # Fall back to single-builder for 1 iteration to verify codebase sanity
    log "CONDUCTOR" "Falling back to single-builder iteration to verify codebase health"
    if run_single_builder_iteration; then
        log "CONDUCTOR" "Single-builder fallback succeeded. Resetting wave failure counter."
        consecutive_wave_failures=0
        return 2  # signal caller to retry wave dispatch
    else
        log "CONDUCTOR" "Single-builder fallback also failed."
        return 1  # signal caller that no progress was made
    fi
}

# Implements the 10-step wave dispatch loop for parallel builds.
# Replaces the v1 single-builder iteration loop during the build phase when
# PARALLEL_ENABLED=true. Orchestrates: task selection → assignment → budget
# check → builder spawn → poll → collect → merge → verify → state update →
# cleanup, looping until all tasks are complete or limits are reached.
# Falls back to run_single_builder_iteration() when no parallelizable tasks
# remain or when wave errors prevent parallel progress.
#
# WHY: this is the core conductor loop that replaces the v1 build loop;
# it ties together all parallel subsystems. (spec-15)
#
# Returns: 0 on completion (all tasks done or orderly exit)
# May exit: 2 via check_budget (hard stop), 3 via escalate (unrecoverable)
run_parallel_build() {
    # Initialize wave state (may already be set from resume via read_state)
    wave_number=${wave_number:-1}
    consecutive_wave_failures=${consecutive_wave_failures:-0}
    wave_history="${wave_history:-[]}"

    log "CONDUCTOR" "Starting parallel build (max_builders=$MAX_BUILDERS, wave_timeout=${WAVE_TIMEOUT_SECONDS}s)"

    while true; do
        # --- Pre-wave checks ---

        # Phase timeout check
        if ! check_phase_timeout; then
            log "CONDUCTOR" "Phase timeout reached during parallel build"
            break
        fi

        # Max iterations check
        local max_iter
        max_iter=$(get_phase_max_iterations "build")
        if [ "$max_iter" -gt 0 ] && [ "$phase_iteration" -ge "$max_iter" ]; then
            log "CONDUCTOR" "Max iterations reached for build phase ($max_iter)"
            break
        fi

        log "CONDUCTOR" "--- Wave $wave_number ---"

        # --- Step 1: Build conflict graph and select non-conflicting tasks ---
        build_conflict_graph
        log_partition_quality
        local selected
        selected=$(select_wave_tasks)

        # --- Step 2: Check completion or fall back to single-builder ---
        local selected_count
        selected_count=$(echo "$selected" | jq 'length')

        if [ "$selected_count" -eq 0 ]; then
            local remaining
            remaining=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
            if [ "$remaining" -eq 0 ]; then
                log "CONDUCTOR" "All tasks complete."
                break
            fi
            # No parallelizable tasks remain — fall back to single-builder
            log "CONDUCTOR" "Wave $wave_number: no parallelizable tasks, falling back to single-builder"
            if ! run_single_builder_iteration; then
                log "CONDUCTOR" "Single-builder fallback failed for non-parallelizable tasks"
                break
            fi
            continue
        fi

        # --- Step 3: Budget checkpoint (may reduce builder count) ---
        local affordable
        affordable=$(check_wave_budget "$selected_count") || {
            log "CONDUCTOR" "Budget exhausted. Stopping parallel build."
            break
        }

        # Trim selected tasks if budget can only support fewer builders
        if [ "$affordable" -lt "$selected_count" ]; then
            log "CONDUCTOR" "Budget reduced wave from $selected_count to $affordable builders"
            selected=$(echo "$selected" | jq --argjson n "$affordable" '.[:$n]')
            selected_count=$affordable
        fi

        # --- Step 4: Write assignments ---
        write_assignments "$wave_number" "$selected"

        # --- Step 5: Generate builder wrapper script ---
        generate_builder_wrapper

        # Capture pre-wave plan state for verify_wave integrity check
        COMPLETED_BEFORE_WAVE=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)

        # --- Step 6: Spawn builders (staggered starts) ---
        local wave_start_epoch
        wave_start_epoch=$(date +%s)
        spawn_builders "$wave_number"
        emit_wave_status "spawn"
        write_dashboard

        # --- Step 7: Poll for completion (blocks until all done or timeout) ---
        poll_builders "$wave_number"

        # --- Step 8: Collect and validate results ---
        local results
        results=$(collect_results "$wave_number")

        # --- Step 9: Handle wave-level errors ---
        local error_rc=0
        handle_wave_errors "$wave_number" "$results" || error_rc=$?

        if [ "$error_rc" -eq 1 ]; then
            # All builders failed AND single-builder fallback also failed
            log "CONDUCTOR" "Wave $wave_number: no progress possible"
            cleanup_wave "$wave_number"
            wave_number=$((wave_number + 1))
            continue
        elif [ "$error_rc" -eq 2 ]; then
            # All builders failed BUT single-builder fallback succeeded — retry wave
            log "CONDUCTOR" "Wave $wave_number: single-builder recovery succeeded, retrying wave dispatch"
            cleanup_wave "$wave_number"
            wave_number=$((wave_number + 1))
            continue
        fi
        # error_rc == 0: at least one builder succeeded → proceed to merge

        # --- Step 10: Merge builder worktrees into main branch ---
        merge_wave "$wave_number"

        # Update plan: mark successful builders' tasks as [x] and commit
        update_plan_after_wave "$wave_number" "$results"

        # Post-merge verification (build command, merge markers, plan integrity)
        if ! verify_wave "$wave_number"; then
            log "CONDUCTOR" "Wave $wave_number: verification failed, recovering with single-builder"
            cleanup_wave "$wave_number"
            wave_number=$((wave_number + 1))
            if run_single_builder_iteration; then
                log "CONDUCTOR" "Post-verification single-builder recovery succeeded"
            fi
            continue
        fi

        # Emit wave completion status to stdout (for non-tmux visibility)
        emit_wave_status "complete"

        # Save current wave number before update_wave_state advances it
        local completed_wave=$wave_number

        # Update state: increment iteration/phase_iteration, aggregate budget,
        # persist state.json, write wave history (also advances wave_number)
        update_wave_state "$completed_wave" "$results" "$wave_start_epoch"
        write_dashboard

        # Cleanup: remove worktrees, archive wave data, kill builder windows
        cleanup_wave "$completed_wave"

        # Global budget check (may exit 2 for hard stops, returns 1 for phase budget)
        # Pass 0,0 — per-iteration warning is not applicable at wave level;
        # Rules 2-4 read cumulative totals from budget.json directly.
        check_budget 0 0 || {
            log "CONDUCTOR" "Budget limit reached. Exiting parallel build."
            break
        }

        # Inter-wave pacing (may sleep if token velocity exceeds 80% of TPM limit)
        check_wave_pacing

        # wave_number already advanced by update_wave_state
    done

    write_state
    log "CONDUCTOR" "Parallel build phase complete."
    return 0
}

# ---------------------------------------------------------------------------
# Phase Sequence Controller
# ---------------------------------------------------------------------------

# Returns the prompt file for a given phase.
get_phase_prompt() {
    case "$1" in
        research)
            # Self-build mode uses specialized research prompt (spec-25)
            if [ "${ARG_SELF:-false}" = "true" ] && [ -f "PROMPT_self_research.md" ]; then
                echo "PROMPT_self_research.md"
            else
                echo "PROMPT_research.md"
            fi
            ;;
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

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Allowance mode: show remaining tokens instead of USD
        local tokens_remaining tokens_display
        tokens_remaining=$(jq '.tokens_remaining' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
        if [ "$tokens_remaining" != "?" ] && [ "$tokens_remaining" -ge 1000000 ] 2>/dev/null; then
            tokens_display="$((tokens_remaining / 1000000))M"
        elif [ "$tokens_remaining" != "?" ] && [ "$tokens_remaining" -ge 1000 ] 2>/dev/null; then
            tokens_display="$((tokens_remaining / 1000))K"
        else
            tokens_display="$tokens_remaining"
        fi
        echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ${LAST_INPUT_TOKENS:-0} input / ${LAST_OUTPUT_TOKENS:-0} output (~\$${iter_cost}) | allowance: ${tokens_display} tokens remaining"
    else
        remaining_budget=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
            "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
        echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ${LAST_INPUT_TOKENS:-0} input / ${LAST_OUTPUT_TOKENS:-0} output (~\$${iter_cost}) | budget: \$${remaining_budget} remaining"
    fi
}

# Prints the startup banner showing version, phase, budget, config, and branch.
# Called once at the start of run_orchestration() after state is determined.
print_banner() {
    local phase="$1"
    local git_branch budget_display

    # Get the current git branch
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    # Determine mode display string
    local mode_display
    if [ "${ARG_SELF:-false}" = "true" ]; then
        mode_display="self-build"
    elif [ "$PARALLEL_ENABLED" = "true" ]; then
        mode_display="parallel (${MAX_BUILDERS} builders)"
    else
        mode_display="single-builder"
    fi

    # Format budget display based on mode
    if [ "$BUDGET_MODE" = "allowance" ]; then
        local allowance_display effective_display
        if [ "$BUDGET_WEEKLY_ALLOWANCE" -ge 1000000 ] 2>/dev/null; then
            allowance_display="$((BUDGET_WEEKLY_ALLOWANCE / 1000000))M"
        else
            allowance_display="$BUDGET_WEEKLY_ALLOWANCE"
        fi
        local effective
        effective=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')
        if [ "$effective" -ge 1000000 ] 2>/dev/null; then
            effective_display="$((effective / 1000000))M"
        else
            effective_display="$effective"
        fi
        budget_display="weekly ${allowance_display} (${effective_display} effective, ${BUDGET_RESERVE_PERCENTAGE}% reserve)"
    else
        local max_tokens_display max_cost_display
        if [ "$BUDGET_MAX_TOKENS" -ge 1000000 ] 2>/dev/null; then
            max_tokens_display="$((BUDGET_MAX_TOKENS / 1000000))M"
        elif [ "$BUDGET_MAX_TOKENS" -ge 1000 ] 2>/dev/null; then
            max_tokens_display="$((BUDGET_MAX_TOKENS / 1000))K"
        else
            max_tokens_display="$BUDGET_MAX_TOKENS"
        fi
        max_cost_display=$(printf '%.2f' "$BUDGET_MAX_USD")
        budget_display="\$${max_cost_display} max | ${max_tokens_display} tokens max"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " automaton v${AUTOMATON_VERSION}"
    echo " Phase:   ${phase}"
    echo " Mode:    ${mode_display}"
    echo " Budget:  ${budget_display}"
    echo " Config:  ${CONFIG_FILE_USED}"
    echo " Branch:  ${git_branch}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

    # 7. Build-phase-only: stall detection, test failure tracking, plan corruption guard
    local stall_rc=0 test_fail_rc=0
    if [ "$current_phase" = "build" ]; then
        check_stall || stall_rc=$?
        check_test_failures "$AGENT_RESULT" || test_fail_rc=$?
        check_plan_integrity
        # Self-build safety: validate orchestrator file modifications (spec-22)
        self_build_validate
        self_build_check_scope
        # Append iteration memory for incremental context (spec-24)
        append_iteration_memory
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
    if [ "$test_fail_rc" -ne 0 ]; then
        TRANSITION_REASON="test_failure"
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

    # Clean up temp plan prompt if leaving the plan phase (spec-18)
    cleanup_parallel_plan_prompt

    # Generate context summary at phase transition (spec-24)
    generate_context_summary

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
    # In self-build mode (spec-25), skip Gate 1 — specs already exist
    if [ "${ARG_SELF:-false}" = "true" ]; then
        log "ORCHESTRATOR" "Self-build mode: skipping Gate 1 (specs exist)"
        # Initialize backlog if it doesn't exist
        _self_init_backlog
    else
        if ! gate_check "spec_completeness"; then
            echo "Gate 1 (spec completeness) failed. Run the conversation phase first."
            exit 1
        fi
    fi

    # --- Determine starting state (fresh or resumed) ---
    if [ "$ARG_RESUME" = "true" ]; then
        read_state
        # Check for allowance week rollover on resume (spec-23)
        _allowance_check_rollover
        log "ORCHESTRATOR" "RESUMED: phase=$current_phase iteration=$iteration"
    else
        initialize
        if [ "$FLAG_SKIP_RESEARCH" = "true" ]; then
            current_phase="plan"
            log "ORCHESTRATOR" "Skipping research (--skip-research)"
        fi
    fi

    # --- Display startup banner ---
    print_banner "$current_phase"

    # Used by gate_build_completion to check for commits during this run
    run_started_at="$started_at"
    PHASE_START_TIME=$(date +%s)
    log "ORCHESTRATOR" "Starting: phase=$current_phase"

    # Start tmux session for parallel builds (spec-15)
    if [ "$PARALLEL_ENABLED" = "true" ]; then
        start_tmux_session
    fi

    # Track review iterations for the review→build feedback loop (spec-06)
    local review_attempts=0

    # === Outer phase loop ===
    while [ "$current_phase" != "COMPLETE" ]; do
        local prompt_file model max_iter
        prompt_file=$(get_phase_prompt "$current_phase")
        model=$(get_phase_model "$current_phase")
        max_iter=$(get_phase_max_iterations "$current_phase")

        # Parallel mode: augment plan prompt with file-ownership annotations (spec-18)
        if [ "$current_phase" = "plan" ]; then
            prepare_parallel_plan_prompt
            if [ -n "${PARALLEL_PLAN_PROMPT:-}" ]; then
                prompt_file="$PARALLEL_PLAN_PROMPT"
            fi
        fi

        # Handle --skip-review
        if [ "$current_phase" = "review" ] && [ "$FLAG_SKIP_REVIEW" = "true" ]; then
            log "ORCHESTRATOR" "Skipping review (--skip-review)"
            transition_to_phase "COMPLETE"
            continue
        fi

        log "ORCHESTRATOR" "Phase: $current_phase (max: $([ "$max_iter" -eq 0 ] && echo 'unlimited' || echo "$max_iter"))"

        # === Build phase: parallel vs single-builder (spec-14, spec-15) ===
        # When parallel.enabled is true and the current phase is build, use the
        # wave-based conductor loop instead of the v1 single-builder iteration loop.
        # When parallel.enabled is false, behavior is identical to v1.
        if [ "$current_phase" = "build" ] && [ "$PARALLEL_ENABLED" = "true" ]; then
            run_parallel_build
        else

        # === Inner iteration loop (v1 single-builder) ===
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
                # Self-build checkpoint: save orchestrator file checksums (spec-22)
                self_build_checkpoint
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
                    test_failure)
                        # Repeated test failure (spec-09, Error #8): escalate to review
                        transition_to_phase "review"
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

        fi  # end parallel vs single-builder conditional

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

    # Clean up tmux session on normal exit (spec-15)
    if [ "$PARALLEL_ENABLED" = "true" ]; then
        cleanup_tmux_session 2>/dev/null || true
    fi

    write_state

    # Archive run to journal (spec-26)
    archive_run_journal

    log "ORCHESTRATOR" "Run complete."
    exit 0
}

# --- Stats mode (spec-26) ---
if [ "$ARG_STATS" = "true" ]; then
    display_stats
fi

# --- Self-continue mode (spec-26) ---
if [ "$ARG_SELF" = "true" ] && [ "$ARG_CONTINUE" = "true" ]; then
    _self_continue_recommendation
    echo ""
    echo "Proceeding with self-build..."
    echo ""
fi

# --- Dry-run mode ---
# Loads config, runs Gate 1, displays resolved settings and phase plan, exits 0.
# No agents are invoked and no state files are created.
if [ "$ARG_DRY_RUN" = "true" ]; then
    # Determine starting phase based on flags
    local_start_phase="research"
    if [ "$FLAG_SKIP_RESEARCH" = "true" ]; then
        local_start_phase="plan"
    fi

    # Print banner
    print_banner "$local_start_phase"

    # Run Gate 1
    echo ""
    echo "Gate 1 (spec completeness):"
    if gate_spec_completeness; then
        echo "  PASS"
    else
        echo "  FAIL — Run the conversation phase first."
    fi

    # Show resolved settings
    echo ""
    echo "Resolved settings:"
    echo "  Config file:     ${CONFIG_FILE_USED}"
    echo "  Models:"
    echo "    research:      ${MODEL_RESEARCH}"
    echo "    planning:      ${MODEL_PLANNING}"
    echo "    building:      ${MODEL_BUILDING}"
    echo "    review:        ${MODEL_REVIEW}"
    echo "    subagent:      ${MODEL_SUBAGENT_DEFAULT}"
    echo "  Budget:"
    echo "    mode:          ${BUDGET_MODE}"
    if [ "$BUDGET_MODE" = "allowance" ]; then
        echo "    weekly tokens: ${BUDGET_WEEKLY_ALLOWANCE}"
        echo "    reset day:     ${BUDGET_ALLOWANCE_RESET_DAY}"
        echo "    reserve:       ${BUDGET_RESERVE_PERCENTAGE}%"
    else
        echo "    max tokens:    ${BUDGET_MAX_TOKENS}"
        echo "    max cost:      \$${BUDGET_MAX_USD}"
    fi
    echo "    per-iteration: ${BUDGET_PER_ITERATION} tokens (warning)"
    echo "    per-phase:     research=${BUDGET_PHASE_RESEARCH}, plan=${BUDGET_PHASE_PLAN}, build=${BUDGET_PHASE_BUILD}, review=${BUDGET_PHASE_REVIEW}"
    echo "  Self-build:"
    echo "    enabled:       ${SELF_BUILD_ENABLED}"
    echo "    max files:     ${SELF_BUILD_MAX_FILES}"
    echo "    max lines:     ${SELF_BUILD_MAX_LINES}"
    echo "    smoke test:    ${SELF_BUILD_REQUIRE_SMOKE}"
    echo "  Rate limits:"
    echo "    tokens/min:    ${RATE_TOKENS_PER_MINUTE}"
    echo "    cooldown:      ${RATE_COOLDOWN_SECONDS}s (backoff: x${RATE_BACKOFF_MULTIPLIER}, max: ${RATE_MAX_BACKOFF_SECONDS}s)"
    echo "  Execution:"
    echo "    max iterations: research=${EXEC_MAX_ITER_RESEARCH}, plan=${EXEC_MAX_ITER_PLAN}, build=${EXEC_MAX_ITER_BUILD}, review=${EXEC_MAX_ITER_REVIEW}"
    echo "  Parallel:"
    if [ "$PARALLEL_ENABLED" = "true" ]; then
        echo "    enabled:        true"
        echo "    max_builders:   ${MAX_BUILDERS}"
        echo "    tmux_session:   ${TMUX_SESSION_NAME}"
        echo "    stagger:        ${PARALLEL_STAGGER_SECONDS}s"
        echo "    wave_timeout:   ${WAVE_TIMEOUT_SECONDS}s"
        echo "    dashboard:      ${PARALLEL_DASHBOARD}"
        # Check tmux availability
        if command -v tmux >/dev/null 2>&1; then
            echo "    tmux:           $(tmux -V 2>/dev/null || echo "available")"
        else
            echo "    tmux:           NOT FOUND (required)"
        fi
        # Check git worktree support (git 2.5+)
        _dr_git_ver=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$_dr_git_ver" ]; then
            _dr_git_major="${_dr_git_ver%%.*}"
            _dr_git_minor="${_dr_git_ver#*.}"
            if [ "$_dr_git_major" -gt 2 ] || { [ "$_dr_git_major" -eq 2 ] && [ "$_dr_git_minor" -ge 5 ]; }; then
                echo "    git worktree:   supported (git ${_dr_git_ver})"
            else
                echo "    git worktree:   NOT SUPPORTED (git ${_dr_git_ver}, need 2.5+)"
            fi
        else
            echo "    git worktree:   unknown (cannot determine git version)"
        fi
    else
        echo "    enabled:        false"
    fi

    # Show phase plan
    echo ""
    echo "Phase sequence:"
    phases_to_run=""
    if [ "$FLAG_SKIP_RESEARCH" = "true" ]; then
        phases_to_run="  1. plan (research skipped)"
    else
        phases_to_run="  1. research (max ${EXEC_MAX_ITER_RESEARCH} iterations)"
        phases_to_run="${phases_to_run}
  2. plan (max ${EXEC_MAX_ITER_PLAN} iterations)"
    fi
    if [ "$FLAG_SKIP_RESEARCH" = "true" ]; then
        next_num=2
    else
        next_num=3
    fi
    build_max_display=$([ "$EXEC_MAX_ITER_BUILD" -eq 0 ] && echo "unlimited" || echo "${EXEC_MAX_ITER_BUILD}")
    phases_to_run="${phases_to_run}
  ${next_num}. build (max ${build_max_display} iterations)"
    next_num=$((next_num + 1))
    if [ "$FLAG_SKIP_REVIEW" = "true" ]; then
        phases_to_run="${phases_to_run}
  ${next_num}. (review skipped)"
    else
        phases_to_run="${phases_to_run}
  ${next_num}. review (max ${EXEC_MAX_ITER_REVIEW} iterations)"
    fi
    echo "$phases_to_run"

    echo ""
    echo "Dry run complete. No agents were invoked."
    exit 0
fi

run_orchestration
