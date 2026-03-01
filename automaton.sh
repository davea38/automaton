#!/usr/bin/env bash
# automaton.sh — Multi-phase orchestrator for autonomous Claude agent workflows.
# This script manages phase transitions, spawns Claude agents, enforces budgets,
# handles errors, and persists state across the research → plan → build → review lifecycle.
set -euo pipefail

AUTOMATON_VERSION="0.1.0"
AUTOMATON_DIR=".automaton"

# Safety ceiling for unlimited build iterations. When max_iterations.build=0
# (unlimited), the build phase can run indefinitely. This constant prevents
# unbounded execution by triggering a review transition after this many
# iterations, even if budget hasn't been exhausted.
BUILD_SAFETY_CEILING=100

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
        RATE_LIMIT_PRESET=$(jq -r '.rate_limits.preset // "auto"' "$config_file")

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

        # -- test-first build strategy (spec-36) --
        EXEC_TEST_FIRST_ENABLED=$(jq -r '.execution.test_first_enabled // true' "$config_file")
        EXEC_TEST_SCAFFOLD_ITERATIONS=$(jq -r '.execution.test_scaffold_iterations // 2' "$config_file")
        EXEC_TEST_FRAMEWORK=$(jq -r '.execution.test_framework // "assertions"' "$config_file")

        # -- bootstrap (spec-37) --
        EXEC_BOOTSTRAP_ENABLED=$(jq -r '.execution.bootstrap_enabled // true' "$config_file")
        EXEC_BOOTSTRAP_SCRIPT=$(jq -r '.execution.bootstrap_script // ".automaton/init.sh"' "$config_file")
        EXEC_BOOTSTRAP_TIMEOUT_MS=$(jq -r '.execution.bootstrap_timeout_ms // 2000' "$config_file")

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
        PARALLEL_MODE=$(jq -r '.parallel.mode // "automaton"' "$config_file")
        MAX_BUILDERS=$(jq -r '.parallel.max_builders // 3' "$config_file")
        TMUX_SESSION_NAME=$(jq -r '.parallel.tmux_session_name // "automaton"' "$config_file")
        PARALLEL_STAGGER_SECONDS=$(jq -r '.parallel.stagger_seconds // 15' "$config_file")
        WAVE_TIMEOUT_SECONDS=$(jq -r '.parallel.wave_timeout_seconds // 600' "$config_file")
        PARALLEL_DASHBOARD=$(jq -r '.parallel.dashboard // true' "$config_file")
        PARALLEL_TEAMMATE_DISPLAY=$(jq -r '.parallel.teammate_display // "in-process"' "$config_file")

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

        # -- max_plan_preset (spec-35) --
        MAX_PLAN_PRESET=$(jq -r '.max_plan_preset // false' "$config_file")

        # -- agents (spec-27) --
        AGENTS_USE_NATIVE_DEFINITIONS=$(jq -r '.agents.use_native_definitions // false' "$config_file")

        # -- garden (spec-38) --
        GARDEN_ENABLED=$(jq -r '.garden.enabled // true' "$config_file")
        GARDEN_SEED_TTL_DAYS=$(jq -r '.garden.seed_ttl_days // 14' "$config_file")
        GARDEN_SPROUT_TTL_DAYS=$(jq -r '.garden.sprout_ttl_days // 30' "$config_file")
        GARDEN_SPROUT_THRESHOLD=$(jq -r '.garden.sprout_threshold // 2' "$config_file")
        GARDEN_BLOOM_THRESHOLD=$(jq -r '.garden.bloom_threshold // 3' "$config_file")
        GARDEN_BLOOM_PRIORITY_THRESHOLD=$(jq -r '.garden.bloom_priority_threshold // 40' "$config_file")
        GARDEN_SIGNAL_SEED_THRESHOLD=$(jq -r '.garden.signal_seed_threshold // 0.7' "$config_file")
        GARDEN_MAX_ACTIVE_IDEAS=$(jq -r '.garden.max_active_ideas // 50' "$config_file")
        GARDEN_AUTO_SEED_METRICS=$(jq -r '.garden.auto_seed_from_metrics // true' "$config_file")
        GARDEN_AUTO_SEED_SIGNALS=$(jq -r '.garden.auto_seed_from_signals // true' "$config_file")

        # -- stigmergy (spec-42) --
        STIGMERGY_ENABLED=$(jq -r '.stigmergy.enabled // true' "$config_file")
        STIGMERGY_INITIAL_STRENGTH=$(jq -r '.stigmergy.initial_strength // 0.3' "$config_file")
        STIGMERGY_REINFORCE_INCREMENT=$(jq -r '.stigmergy.reinforce_increment // 0.15' "$config_file")
        STIGMERGY_DECAY_FLOOR=$(jq -r '.stigmergy.decay_floor // 0.05' "$config_file")
        STIGMERGY_MATCH_THRESHOLD=$(jq -r '.stigmergy.match_threshold // 0.6' "$config_file")
        STIGMERGY_MAX_SIGNALS=$(jq -r '.stigmergy.max_signals // 100' "$config_file")

        # -- quorum (spec-39) --
        QUORUM_ENABLED=$(jq -r '.quorum.enabled // true' "$config_file")
        QUORUM_VOTERS=$(jq -r '.quorum.voters // ["conservative","ambitious","efficiency","quality","advocate"] | join(",")' "$config_file")
        QUORUM_THRESHOLD_SEED=$(jq -r '.quorum.thresholds.seed_promotion // 3' "$config_file")
        QUORUM_THRESHOLD_BLOOM=$(jq -r '.quorum.thresholds.bloom_implementation // 3' "$config_file")
        QUORUM_THRESHOLD_AMENDMENT=$(jq -r '.quorum.thresholds.constitutional_amendment // 4' "$config_file")
        QUORUM_THRESHOLD_EMERGENCY=$(jq -r '.quorum.thresholds.emergency_override // 5' "$config_file")
        QUORUM_MAX_TOKENS_PER_VOTER=$(jq -r '.quorum.max_tokens_per_voter // 500' "$config_file")
        QUORUM_MAX_COST_PER_CYCLE=$(jq -r '.quorum.max_cost_per_cycle_usd // 1.00' "$config_file")
        QUORUM_REJECTION_COOLDOWN=$(jq -r '.quorum.rejection_cooldown_cycles // 5' "$config_file")
        QUORUM_MODEL=$(jq -r '.quorum.model // "sonnet"' "$config_file")

        # -- metrics (spec-43) --
        METRICS_ENABLED=$(jq -r '.metrics.enabled // true' "$config_file")
        METRICS_TREND_WINDOW=$(jq -r '.metrics.trend_window // 5' "$config_file")
        METRICS_DEGRADATION_ALERT_THRESHOLD=$(jq -r '.metrics.degradation_alert_threshold // 3' "$config_file")
        METRICS_SNAPSHOT_RETENTION=$(jq -r '.metrics.snapshot_retention // 100' "$config_file")

        # -- evolution (spec-41) --
        EVOLVE_ENABLED=$(jq -r '.evolution.enabled // false' "$config_file")
        EVOLVE_MAX_CYCLES=$(jq -r '.evolution.max_cycles // 0' "$config_file")
        EVOLVE_MAX_COST_PER_CYCLE=$(jq -r '.evolution.max_cost_per_cycle_usd // 5.00' "$config_file")
        EVOLVE_CONVERGENCE_THRESHOLD=$(jq -r '.evolution.convergence_threshold // 5' "$config_file")
        EVOLVE_IDLE_GARDEN_THRESHOLD=$(jq -r '.evolution.idle_garden_threshold // 3' "$config_file")
        EVOLVE_BRANCH_PREFIX=$(jq -r '.evolution.branch_prefix // "automaton/evolve-"' "$config_file")
        EVOLVE_AUTO_MERGE=$(jq -r '.evolution.auto_merge // true' "$config_file")
        EVOLVE_REFLECT_MODEL=$(jq -r '.evolution.reflect_model // "sonnet"' "$config_file")
        EVOLVE_IDEATE_MODEL=$(jq -r '.evolution.ideate_model // "sonnet"' "$config_file")
        EVOLVE_OBSERVE_MODEL=$(jq -r '.evolution.observe_model // "sonnet"' "$config_file")

        # -- safety (spec-45) --
        SAFETY_MAX_TOTAL_LINES=$(jq -r '.safety.max_total_lines // 15000' "$config_file")
        SAFETY_MAX_TOTAL_FUNCTIONS=$(jq -r '.safety.max_total_functions // 300' "$config_file")
        SAFETY_MIN_TEST_PASS_RATE=$(jq -r '.safety.min_test_pass_rate // 0.80' "$config_file")
        SAFETY_MAX_CONSECUTIVE_FAILURES=$(jq -r '.safety.max_consecutive_failures // 3' "$config_file")
        SAFETY_MAX_CONSECUTIVE_REGRESSIONS=$(jq -r '.safety.max_consecutive_regressions // 2' "$config_file")
        SAFETY_PRESERVE_FAILED_BRANCHES=$(jq -r '.safety.preserve_failed_branches // true' "$config_file")
        SAFETY_PREFLIGHT_ENABLED=$(jq -r '.safety.preflight_enabled // true' "$config_file")
        SAFETY_SANDBOX_TESTING_ENABLED=$(jq -r '.safety.sandbox_testing_enabled // true' "$config_file")
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
        RATE_LIMIT_PRESET="auto"

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

        # -- test-first build strategy (spec-36) --
        EXEC_TEST_FIRST_ENABLED="true"
        EXEC_TEST_SCAFFOLD_ITERATIONS=2
        EXEC_TEST_FRAMEWORK="assertions"

        # -- bootstrap (spec-37) --
        EXEC_BOOTSTRAP_ENABLED="true"
        EXEC_BOOTSTRAP_SCRIPT=".automaton/init.sh"
        EXEC_BOOTSTRAP_TIMEOUT_MS=2000

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

        # -- max_plan_preset (spec-35) --
        MAX_PLAN_PRESET="false"

        # -- agents (spec-27) --
        AGENTS_USE_NATIVE_DEFINITIONS="false"

        # -- garden (spec-38) --
        GARDEN_ENABLED="true"
        GARDEN_SEED_TTL_DAYS=14
        GARDEN_SPROUT_TTL_DAYS=30
        GARDEN_SPROUT_THRESHOLD=2
        GARDEN_BLOOM_THRESHOLD=3
        GARDEN_BLOOM_PRIORITY_THRESHOLD=40
        GARDEN_SIGNAL_SEED_THRESHOLD="0.7"
        GARDEN_MAX_ACTIVE_IDEAS=50
        GARDEN_AUTO_SEED_METRICS="true"
        GARDEN_AUTO_SEED_SIGNALS="true"

        # -- stigmergy (spec-42) --
        STIGMERGY_ENABLED="true"
        STIGMERGY_INITIAL_STRENGTH="0.3"
        STIGMERGY_REINFORCE_INCREMENT="0.15"
        STIGMERGY_DECAY_FLOOR="0.05"
        STIGMERGY_MATCH_THRESHOLD="0.6"
        STIGMERGY_MAX_SIGNALS=100

        # -- quorum (spec-39) --
        QUORUM_ENABLED="true"
        QUORUM_VOTERS="conservative,ambitious,efficiency,quality,advocate"
        QUORUM_THRESHOLD_SEED=3
        QUORUM_THRESHOLD_BLOOM=3
        QUORUM_THRESHOLD_AMENDMENT=4
        QUORUM_THRESHOLD_EMERGENCY=5
        QUORUM_MAX_TOKENS_PER_VOTER=500
        QUORUM_MAX_COST_PER_CYCLE="1.00"
        QUORUM_REJECTION_COOLDOWN=5
        QUORUM_MODEL="sonnet"

        # -- metrics (spec-43) --
        METRICS_ENABLED="true"
        METRICS_TREND_WINDOW=5
        METRICS_DEGRADATION_ALERT_THRESHOLD=3
        METRICS_SNAPSHOT_RETENTION=100

        # -- evolution (spec-41) --
        EVOLVE_ENABLED="false"
        EVOLVE_MAX_CYCLES=0
        EVOLVE_MAX_COST_PER_CYCLE="5.00"
        EVOLVE_CONVERGENCE_THRESHOLD=5
        EVOLVE_IDLE_GARDEN_THRESHOLD=3
        EVOLVE_BRANCH_PREFIX="automaton/evolve-"
        EVOLVE_AUTO_MERGE="true"
        EVOLVE_REFLECT_MODEL="sonnet"
        EVOLVE_IDEATE_MODEL="sonnet"
        EVOLVE_OBSERVE_MODEL="sonnet"

        # -- safety (spec-45) --
        SAFETY_MAX_TOTAL_LINES=15000
        SAFETY_MAX_TOTAL_FUNCTIONS=300
        SAFETY_MIN_TEST_PASS_RATE="0.80"
        SAFETY_MAX_CONSECUTIVE_FAILURES=3
        SAFETY_MAX_CONSECUTIVE_REGRESSIONS=2
        SAFETY_PRESERVE_FAILED_BRANCHES="true"
        SAFETY_PREFLIGHT_ENABLED="true"
        SAFETY_SANDBOX_TESTING_ENABLED="true"
    fi
}

# Applies Max Plan preset defaults when max_plan_preset is true (spec-35).
# Sets budget mode to allowance and models to opus, enabling cascading
# optimizations: rate limits and parallel defaults trigger from allowance mode.
# Only overrides values that still match their non-preset defaults, so
# individual config overrides take precedence.
_apply_max_plan_preset() {
    if [ "$MAX_PLAN_PRESET" != "true" ]; then
        return 0
    fi

    local changed=""

    if [ "$BUDGET_MODE" = "api" ]; then
        BUDGET_MODE="allowance"
        changed="${changed}budget.mode=allowance "
    fi

    if [ "$MODEL_RESEARCH" = "sonnet" ]; then
        MODEL_RESEARCH="opus"
        changed="${changed}models.research=opus "
    fi

    if [ "$MODEL_BUILDING" = "sonnet" ]; then
        MODEL_BUILDING="opus"
        changed="${changed}models.building=opus "
    fi

    if [ -n "$changed" ]; then
        log "ORCHESTRATOR" "Max Plan preset: defaults applied (${changed% })"
    fi
}

# Applies rate limit presets based on budget mode (spec-35).
# When budget.mode is "allowance", Max Plan subscribers have higher rate limits.
# The preset field controls behavior:
#   "auto"        — use max_plan in allowance mode, api_default otherwise (default)
#   "max_plan"    — always use Max Plan rate limits
#   "api_default" — always use API-tier rate limits
_apply_rate_limit_preset() {
    local apply_preset=""

    case "$RATE_LIMIT_PRESET" in
        max_plan)
            apply_preset="max_plan"
            ;;
        api_default)
            apply_preset="api_default"
            ;;
        auto|"")
            if [ "$BUDGET_MODE" = "allowance" ]; then
                apply_preset="max_plan"
            else
                apply_preset="api_default"
            fi
            ;;
        *)
            log "ORCHESTRATOR" "WARNING: Unknown rate_limits.preset '$RATE_LIMIT_PRESET', using api_default"
            apply_preset="api_default"
            ;;
    esac

    if [ "$apply_preset" = "max_plan" ]; then
        RATE_TOKENS_PER_MINUTE=200000
        RATE_REQUESTS_PER_MINUTE=100
        RATE_COOLDOWN_SECONDS=30
        RATE_BACKOFF_MULTIPLIER=1.5
        RATE_MAX_BACKOFF_SECONDS=120
        log "ORCHESTRATOR" "Rate limit preset: max_plan (200K tpm, 100 rpm, 30s cooldown)"
    fi
    # api_default: values already loaded from config/defaults — nothing to override
}

# Applies higher parallel defaults when in allowance mode (spec-35).
# Max Plan subscribers have no per-token cost, so more parallelism is free.
# Only overrides values that the user has NOT explicitly set in their config.
# Defaults applied: max_builders=5, stagger_seconds=5, research iterations=5.
_apply_allowance_parallel_defaults() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    # Upgrade API-default values to Max Plan defaults.
    # Only override when the current value matches the API default,
    # meaning the user hasn't explicitly customized it.
    local changed=""

    if [ "$MAX_BUILDERS" -eq 3 ]; then
        MAX_BUILDERS=5
        changed="${changed}max_builders=5 "
    fi

    if [ "$PARALLEL_STAGGER_SECONDS" -eq 15 ]; then
        PARALLEL_STAGGER_SECONDS=5
        changed="${changed}stagger=5s "
    fi

    if [ "$EXEC_MAX_ITER_RESEARCH" -eq 3 ]; then
        EXEC_MAX_ITER_RESEARCH=5
        changed="${changed}research_iters=5 "
    fi

    if [ -n "$changed" ]; then
        log "ORCHESTRATOR" "Allowance mode: parallel defaults applied (${changed% })"
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
  "build_sub_phase": "${build_sub_phase:-implementation}",
  "scaffold_iterations_done": ${scaffold_iterations_done:-0},
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
# Falls back to recover_state_from_persistent() if state.json is missing.
read_state() {
    local state_file="$AUTOMATON_DIR/state.json"
    if [ ! -f "$state_file" ]; then
        recover_state_from_persistent
        return $?
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
    build_sub_phase=$(echo "$state" | jq -r '.build_sub_phase // "implementation"')
    scaffold_iterations_done=$(echo "$state" | jq '.scaffold_iterations_done // 0')
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

# Best-effort reconstruction of state.json from persistent state (spec-34).
# Called when --resume is used but ephemeral state.json is missing.
# Reads: latest run summary, IMPLEMENTATION_PLAN.md checkboxes, budget-history.json, git log.
# WHY: users who lose .automaton/state.json can resume from git-tracked persistent
# state instead of starting over.
recover_state_from_persistent() {
    local summaries_dir="$AUTOMATON_DIR/run-summaries"
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"

    # Find latest run summary by filename (timestamps sort lexicographically)
    local latest_summary=""
    if [ -d "$summaries_dir" ]; then
        latest_summary=$(ls -1 "$summaries_dir"/run-*.json 2>/dev/null | sort | tail -1)
    fi

    if [ -z "$latest_summary" ] && [ ! -f "$plan_file" ]; then
        echo "Error: No persistent state to recover from (no run summaries or plan file). Run without --resume."
        exit 1
    fi

    log "ORCHESTRATOR" "Ephemeral state missing. Reconstructing from persistent state and git history."

    # --- Extract data from latest run summary ---
    local summary_phases="[]" summary_iterations=0 summary_exit=0
    local summary_started="" summary_completed=""
    if [ -n "$latest_summary" ]; then
        summary_phases=$(jq -c '.phases_completed // []' "$latest_summary")
        summary_iterations=$(jq '.iterations_total // 0' "$latest_summary")
        summary_exit=$(jq '.exit_code // 0' "$latest_summary")
        summary_started=$(jq -r '.started_at // ""' "$latest_summary")
        summary_completed=$(jq -r '.completed_at // ""' "$latest_summary")
    fi

    # --- Determine resume phase from completed phases ---
    # Phase order: research → plan → build → review → COMPLETE
    local last_completed=""
    if [ "$summary_phases" != "[]" ]; then
        last_completed=$(echo "$summary_phases" | jq -r '.[-1]')
    fi

    case "$last_completed" in
        "")       current_phase="research" ;;
        research) current_phase="plan" ;;
        plan)     current_phase="build" ;;
        build)    current_phase="review" ;;
        review)
            # All phases completed in previous run — start a fresh build cycle
            # since the user is explicitly asking to resume (likely new tasks added)
            current_phase="build"
            ;;
        *)        current_phase="build" ;;
    esac

    # If the previous run completed successfully (exit 0) and all phases finished,
    # check if there's remaining work in the plan
    if [ "$summary_exit" = "0" ] && [ "$last_completed" = "review" ]; then
        local remaining=0
        if [ -f "$plan_file" ]; then
            remaining=$(grep -c '^\- \[ \]' "$plan_file" 2>/dev/null || echo 0)
        fi
        if [ "$remaining" = "0" ]; then
            echo "Previous run completed successfully with no remaining tasks. Run without --resume to start fresh."
            exit 0
        fi
    fi

    # --- Reconstruct phase_history from run summary ---
    phase_history="[]"
    if [ "$summary_phases" != "[]" ]; then
        # Build phase_history array with phase names (timestamps unavailable)
        phase_history=$(echo "$summary_phases" | jq -c '[.[] | {phase: ., completed_at: "recovered"}]')
    fi

    # --- Set state variables with safe defaults ---
    iteration=$summary_iterations
    phase_iteration=0
    stall_count=0
    consecutive_failures=0
    corruption_count=0
    replan_count=0
    test_failure_count=0
    resumed_from="${summary_completed:-null}"

    # Use the original run's start time if available, otherwise now
    if [ -n "$summary_started" ] && [ "$summary_started" != "null" ]; then
        started_at="$summary_started"
    else
        started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    fi

    # Parallel mode: reset wave state (cannot be recovered)
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        wave_number=0
        wave_history="[]"
        consecutive_wave_failures=0
    fi

    # --- Ensure directory structure exists ---
    mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/worktrees" "$AUTOMATON_DIR/inbox" \
             "$AUTOMATON_DIR/run-summaries"

    # --- Write reconstructed state ---
    write_state

    # --- Reconstruct budget.json if also missing ---
    if [ ! -f "$AUTOMATON_DIR/budget.json" ]; then
        initialize_budget
        # Seed budget usage from budget-history.json if available
        local history_file="$AUTOMATON_DIR/budget-history.json"
        if [ -f "$history_file" ] && [ -n "$latest_summary" ]; then
            local run_id
            run_id=$(jq -r '.run_id // ""' "$latest_summary")
            if [ -n "$run_id" ]; then
                local prev_tokens
                prev_tokens=$(jq --arg rid "$run_id" '
                    .runs[] | select(.run_id == $rid) | .tokens_used // 0
                ' "$history_file" 2>/dev/null || echo 0)
                if [ "$prev_tokens" -gt 0 ] 2>/dev/null; then
                    log "ORCHESTRATOR" "Previous run used $prev_tokens tokens (from budget history)"
                fi
            fi
        fi
    fi

    # --- Create session.log if missing ---
    if [ ! -f "$AUTOMATON_DIR/session.log" ]; then
        : > "$AUTOMATON_DIR/session.log"
    fi

    # --- Log recovery summary with git context ---
    local recent_commit=""
    recent_commit=$(git log --oneline -1 --format="%h %s" 2>/dev/null || true)
    local task_info=""
    if [ -f "$plan_file" ]; then
        local done remaining
        done=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null || echo 0)
        remaining=$(grep -c '^\- \[ \]' "$plan_file" 2>/dev/null || echo 0)
        task_info="tasks=${done} done/${remaining} remaining"
    fi

    log "ORCHESTRATOR" "State recovered: phase=$current_phase iteration=$iteration ${task_info:+$task_info }${recent_commit:+latest_commit=$recent_commit}"
}

# Generates .automaton/init.sh bootstrap script if it doesn't already exist.
# On fresh projects (first `initialize()` call), the bootstrap script must be
# created so that `_run_bootstrap()` can assemble context manifests. Without
# this, the bootstrap is configured but has no script to run, causing empty
# manifests on fresh runs. (spec-37, gap fix)
generate_bootstrap_script() {
    local script_path="$EXEC_BOOTSTRAP_SCRIPT"

    # Don't overwrite an existing bootstrap script (user may have customized it)
    if [ -f "$script_path" ]; then
        # Ensure it's executable
        chmod +x "$script_path" 2>/dev/null || true
        return 0
    fi

    if [ "$EXEC_BOOTSTRAP_ENABLED" != "true" ]; then
        return 0
    fi

    # Ensure parent directory exists
    local script_dir
    script_dir=$(dirname "$script_path")
    mkdir -p "$script_dir"

    cat > "$script_path" <<'BOOTSTRAP_SCRIPT'
#!/usr/bin/env bash
# .automaton/init.sh — Session Bootstrap (spec-37)
# Runs BEFORE each agent invocation. Outputs JSON manifest to stdout.
# The manifest provides pre-assembled context so agents skip Phase 0 file reads.
#
# Usage: .automaton/init.sh [PROJECT_ROOT] [PHASE] [ITERATION]
# Defaults: PROJECT_ROOT=., PHASE=build, ITERATION=1
set -euo pipefail

PROJECT_ROOT="${1:-.}"
PHASE="${2:-build}"
ITERATION="${3:-1}"
AUTOMATON_DIR="$PROJECT_ROOT/.automaton"

# Dependency check — jq and git are required
check_dependencies() {
    local missing=""
    for cmd in jq git; do
        command -v "$cmd" &>/dev/null || missing="$missing $cmd"
    done
    if [ -n "$missing" ]; then
        echo "{\"error\": \"Missing dependencies:$missing\"}"
        exit 1
    fi
}

# Validate state.json if it exists
validate_state() {
    local state_file="$AUTOMATON_DIR/state.json"
    if [ -f "$state_file" ]; then
        jq empty "$state_file" 2>/dev/null || {
            echo "{\"error\": \"state.json is invalid JSON\"}"
            exit 1
        }
    fi
}

# Assemble the JSON manifest from project files and git state
generate_context() {
    local manifest="{}"

    # --- Project state ---
    manifest=$(echo "$manifest" | jq --arg phase "$PHASE" --argjson iter "$ITERATION" \
        '. + {project_state: {phase: $phase, iteration: $iter}}')

    # Task progress from IMPLEMENTATION_PLAN.md (or .automaton/backlog.md)
    local plan_file="$PROJECT_ROOT/IMPLEMENTATION_PLAN.md"
    if [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    if [ -f "$plan_file" ]; then
        local next_task total_tasks done_tasks
        next_task=$(grep -m1 '^\- \[ \]' "$plan_file" | sed 's/^- \[ \] //' || echo "")
        total_tasks=$(grep -c '^\- \[' "$plan_file" 2>/dev/null || echo 0)
        done_tasks=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null || echo 0)
        manifest=$(echo "$manifest" | jq \
            --arg next "$next_task" \
            --argjson total "$total_tasks" \
            --argjson done "$done_tasks" \
            '.project_state += {next_task: $next, tasks_total: $total, tasks_done: $done}')
    fi

    # --- Recent changes (last 5 commits) ---
    local recent_commits
    recent_commits=$(git -C "$PROJECT_ROOT" log --oneline -5 2>/dev/null \
        | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')
    manifest=$(echo "$manifest" | jq --argjson commits "$recent_commits" \
        '. + {recent_changes: $commits}')

    # --- Budget ---
    if [ -f "$AUTOMATON_DIR/budget.json" ]; then
        local budget_used budget_limit
        budget_used=$(jq '.used.estimated_cost_usd // 0' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo 0)
        budget_limit=$(jq '.limits.max_cost_usd // 50' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo 50)
        manifest=$(echo "$manifest" | jq \
            --argjson used "$budget_used" \
            --argjson limit "$budget_limit" \
            '. + {budget: {used_usd: $used, limit_usd: $limit, remaining_usd: ($limit - $used)}}')
    fi

    # --- Modified files since last commit ---
    local modified_files
    modified_files=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~1 2>/dev/null \
        | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')
    manifest=$(echo "$manifest" | jq --argjson files "$modified_files" \
        '. + {modified_files: $files}')

    # --- Learnings (high-confidence, active only) ---
    if [ -f "$AUTOMATON_DIR/learnings.json" ]; then
        local learnings
        learnings=$(jq '[.entries[]? | select(.active == true and .confidence == "high") | .summary]' \
            "$AUTOMATON_DIR/learnings.json" 2>/dev/null || echo '[]')
        manifest=$(echo "$manifest" | jq --argjson learn "$learnings" \
            '. + {learnings: $learn}')
    fi

    # --- Test status (from test_results.json) ---
    if [ -f "$AUTOMATON_DIR/test_results.json" ]; then
        local test_data
        test_data=$(jq '{
            passed: ([.[]? | select(.status == "passed")] | length),
            failed: ([.[]? | select(.status == "failed")] | length),
            failing_tests: [.[]? | select(.status == "failed") | .test]
        }' "$AUTOMATON_DIR/test_results.json" 2>/dev/null || echo '{}')
        if [ "$test_data" != "{}" ]; then
            manifest=$(echo "$manifest" | jq --argjson tests "$test_data" \
                '. + {test_status: $tests}')
        fi
    fi

    echo "$manifest" | jq .
}

check_dependencies
validate_state
generate_context
BOOTSTRAP_SCRIPT

    chmod +x "$script_path"
    log "ORCHESTRATOR" "Generated bootstrap script: $script_path"
}

# First-run initialization: create .automaton/ structure, write initial state,
# initialize budget tracking, and create an empty session log.
initialize() {
    mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/worktrees" "$AUTOMATON_DIR/inbox" \
             "$AUTOMATON_DIR/run-summaries"

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
    build_sub_phase="implementation"
    scaffold_iterations_done=0
    research_gate_failures=0
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

    # Migrate learnings to per-agent memory when native definitions enabled (spec-27)
    if [ "$AGENTS_USE_NATIVE_DEFINITIONS" = "true" ]; then
        migrate_learnings_to_agent_memory
    fi

    # Initialize garden directory when enabled (spec-38)
    if [ "$GARDEN_ENABLED" = "true" ]; then
        mkdir -p "$AUTOMATON_DIR/garden"
        # Create empty _index.json if it doesn't already exist
        local index_file="$AUTOMATON_DIR/garden/_index.json"
        if [ ! -f "$index_file" ]; then
            local now_ts
            now_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            jq -n --arg updated_at "$now_ts" '{
                total: 0,
                by_stage: { seed: 0, sprout: 0, bloom: 0, harvest: 0, wilt: 0 },
                bloom_candidates: [],
                recent_activity: [],
                next_id: 1,
                updated_at: $updated_at
            }' > "$index_file"
        fi
    fi

    # Initialize votes directory when quorum enabled (spec-39)
    if [ "$QUORUM_ENABLED" = "true" ]; then
        mkdir -p "$AUTOMATON_DIR/votes"
    fi

    # Initialize evolution directory when evolution mode active (spec-41)
    if [ "$ARG_EVOLVE" = "true" ] || [ "$EVOLVE_ENABLED" = "true" ]; then
        mkdir -p "$AUTOMATON_DIR/evolution"
    fi

    # Generate bootstrap script if it doesn't exist (spec-37, gap #1)
    generate_bootstrap_script

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
#       cost task status files_changed_json git_commit auto_compaction
write_agent_history() {
    local model="$1" prompt_file="$2" agent_start="$3" agent_end="$4"
    local duration="$5" exit_code="$6"
    local input_tokens="${7:-0}" output_tokens="${8:-0}"
    local cache_create="${9:-0}" cache_read="${10:-0}"
    local cost="${11:-0}" task_desc="${12:-}" status="${13:-unknown}"
    local files_changed="${14:-[]}" git_commit="${15:-null}"
    local auto_compaction="${16:-false}"

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
        --argjson auto_compaction_detected "$([ "$auto_compaction" = "true" ] && echo true || echo false)" \
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
            git_commit: (if $git_commit == "null" then null else $git_commit end),
            auto_compaction_detected: $auto_compaction_detected
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

        # Calculate initial daily budget for pacing (spec-35)
        local today today_epoch end_epoch days_left initial_daily_budget
        today=$(date +%Y-%m-%d)
        today_epoch=$(date -d "$today" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$today" +%s 2>/dev/null || echo 0)
        end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s 2>/dev/null || echo 0)
        if [ "$today_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
            days_left=$(( (end_epoch - today_epoch) / 86400 + 1 ))
        else
            days_left=1
        fi
        [ "$days_left" -lt 1 ] && days_left=1
        initial_daily_budget=$(awk -v eff="$effective_allowance" -v days="$days_left" \
            'BEGIN { printf "%d", eff / days }')

        jq -n \
            --arg mode "allowance" \
            --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
            --argjson effective_allowance "$effective_allowance" \
            --arg week_start "$week_start" \
            --arg week_end "$week_end" \
            --argjson reserve "$BUDGET_RESERVE_PERCENTAGE" \
            --argjson per_iteration "$BUDGET_PER_ITERATION" \
            --argjson daily_budget "$initial_daily_budget" \
            '{
                mode: $mode,
                limits: {
                    weekly_allowance_tokens: $weekly_allowance,
                    effective_allowance: $effective_allowance,
                    reserve_percentage: $reserve,
                    per_iteration: $per_iteration,
                    daily_budget: $daily_budget,
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

    # Initialize cross-project allowance tracking (spec-35 §5)
    _init_cross_project_allowance
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

# Displays a weekly summary when resuming after a week boundary (spec-35 §7).
# Shows tokens used, runs, tasks completed, estimated API-equivalent savings,
# and the fresh allowance for the new week. Called from _allowance_check_rollover()
# BEFORE resetting counters so old week data is still available.
_display_weekly_summary() {
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ ! -f "$budget_file" ]; then
        return 0
    fi

    local old_week_start old_week_end tokens_used_week
    old_week_start=$(jq -r '.week_start // ""' "$budget_file")
    old_week_end=$(jq -r '.week_end // ""' "$budget_file")
    tokens_used_week=$(jq '.tokens_used_this_week // 0' "$budget_file")
    local weekly_allowance="$BUDGET_WEEKLY_ALLOWANCE"

    if [ -z "$old_week_start" ] || [ -z "$old_week_end" ]; then
        return 0
    fi

    # Format dates for display
    local ws_display we_display
    ws_display=$(date -d "$old_week_start" "+%b %d" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$old_week_start" "+%b %d" 2>/dev/null || echo "$old_week_start")
    we_display=$(date -d "$old_week_end" "+%b %d, %Y" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$old_week_end" "+%b %d, %Y" 2>/dev/null || echo "$old_week_end")

    # Use cross-project data when available for accurate totals
    local total_runs=0 project_count=1
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)
    if [ -f "$allowance_file" ]; then
        local cross_total
        cross_total=$(jq '.current_week.total_used // 0' "$allowance_file" 2>/dev/null || echo 0)
        if [ "$cross_total" -gt "$tokens_used_week" ]; then
            tokens_used_week="$cross_total"
        fi
        project_count=$(jq '.current_week.projects | length' "$allowance_file" 2>/dev/null || echo 1)
        total_runs=$(jq '[.current_week.projects[].runs] | add // 0' "$allowance_file" 2>/dev/null || echo 0)
    fi
    [ "$project_count" -lt 1 ] && project_count=1
    [ "$total_runs" -lt 1 ] && total_runs=1

    # Usage percentage
    local usage_pct
    usage_pct=$(awk -v used="$tokens_used_week" -v total="$weekly_allowance" \
        'BEGIN { if (total > 0) printf "%.0f", used * 100 / total; else printf "0" }')

    # Tasks completed (from plan file)
    local tasks_completed=0
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    if [ -f "$plan_file" ]; then
        tasks_completed=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null || echo 0)
    fi

    # Estimate API-equivalent cost from budget-history.json run entries within the week
    local estimated_savings="0.00"
    local history_file="$AUTOMATON_DIR/budget-history.json"
    if [ -f "$history_file" ]; then
        local run_prefix_start day_after_end run_prefix_end
        run_prefix_start="run-${old_week_start}"
        day_after_end=$(date -d "$old_week_end + 1 day" +%Y-%m-%d 2>/dev/null || \
            date -jf "%Y-%m-%d" -v+1d "$old_week_end" +%Y-%m-%d 2>/dev/null || echo "9999-99-99")
        run_prefix_end="run-${day_after_end}"
        estimated_savings=$(jq --arg start "$run_prefix_start" --arg end "$run_prefix_end" '
            [.runs[] | select(.run_id >= $start and .run_id < $end) | .estimated_cost_usd] |
            add // 0 | . * 100 | round / 100
        ' "$history_file" 2>/dev/null || echo "0.00")
    fi

    # New week boundaries
    local new_week_start new_week_end new_ws_display new_we_display
    new_week_start=$(_allowance_week_start)
    new_week_end=$(_allowance_week_end "$new_week_start")
    new_ws_display=$(date -d "$new_week_start" "+%b %d" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$new_week_start" "+%b %d" 2>/dev/null || echo "$new_week_start")
    new_we_display=$(date -d "$new_week_end" "+%b %d, %Y" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$new_week_end" "+%b %d, %Y" 2>/dev/null || echo "$new_week_end")

    # Fresh allowance for new week
    local effective_allowance
    effective_allowance=$(awk -v total="$weekly_allowance" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
        'BEGIN { printf "%d", total * (1 - reserve/100) }')

    _fmt_num() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Weekly Summary: $ws_display — $we_display"
    printf " Total tokens used:  %s / %s (%s%%)\n" "$(_fmt_num "$tokens_used_week")" "$(_fmt_num "$weekly_allowance")" "$usage_pct"
    printf " Runs:               %s across %s project%s\n" "$total_runs" "$project_count" "$([ "$project_count" -ne 1 ] && echo 's' || echo '')"
    printf " Tasks completed:    %s\n" "$tasks_completed"
    printf " Estimated savings:  \$%s vs API pricing\n" "$estimated_savings"
    echo " New week started:   $new_ws_display — $new_we_display"
    printf " Fresh allowance:    %s tokens\n" "$(_fmt_num "$effective_allowance")"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
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
        # Display weekly summary before resetting counters (spec-35 §7)
        _display_weekly_summary

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

        # Also roll over the cross-project allowance file
        _cross_project_rollover "$stored_week_end"
    fi
}

# ---------------------------------------------------------------------------
# Cross-Project Allowance Tracking (spec-35 §5)
# ---------------------------------------------------------------------------
# Tracks token usage across multiple projects sharing one Max Plan allowance.
# WHY: Max Plan users running automaton on different projects share a single
# weekly allowance; cross-project tracking prevents over-allocation.

# Returns the path to the cross-project allowance file.
_cross_project_allowance_file() {
    echo "${HOME}/.automaton/allowance.json"
}

# Initializes ~/.automaton/allowance.json if missing or if the current week
# has rolled over. Called from initialize_budget() in allowance mode.
_init_cross_project_allowance() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local allowance_file
    allowance_file=$(_cross_project_allowance_file)
    local allowance_dir
    allowance_dir=$(dirname "$allowance_file")

    # Create ~/.automaton/ directory if needed
    mkdir -p "$allowance_dir"

    local week_start week_end
    week_start=$(_allowance_week_start)
    week_end=$(_allowance_week_end "$week_start")

    if [ ! -f "$allowance_file" ] || [ ! -s "$allowance_file" ]; then
        # Create fresh allowance file
        jq -n \
            --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
            --arg reset_day "$BUDGET_ALLOWANCE_RESET_DAY" \
            --arg week_start "$week_start" \
            --arg week_end "$week_end" \
            '{
                weekly_allowance_tokens: $weekly_allowance,
                allowance_reset_day: $reset_day,
                current_week: {
                    week_start: $week_start,
                    week_end: $week_end,
                    projects: {},
                    total_used: 0
                },
                history: []
            }' > "$allowance_file"
        log "ORCHESTRATOR" "Cross-project allowance tracking initialized: $allowance_file"
        return 0
    fi

    # Check if stored week has rolled over
    local stored_week_end
    stored_week_end=$(jq -r '.current_week.week_end // ""' "$allowance_file" 2>/dev/null || echo "")

    if [ -n "$stored_week_end" ] && [[ "$(date +%Y-%m-%d)" > "$stored_week_end" ]]; then
        _cross_project_rollover "$stored_week_end"
    fi

    # Update config values in case they changed
    local tmp="${allowance_file}.tmp"
    jq \
        --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
        --arg reset_day "$BUDGET_ALLOWANCE_RESET_DAY" \
        '.weekly_allowance_tokens = $weekly_allowance | .allowance_reset_day = $reset_day' \
        "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"
}

# Archives the current week in ~/.automaton/allowance.json and resets for a new week.
# Args: old_week_end (ISO date of the week that just ended)
_cross_project_rollover() {
    local old_week_end="$1"
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ ! -f "$allowance_file" ]; then
        return 0
    fi

    local new_week_start new_week_end
    new_week_start=$(_allowance_week_start)
    new_week_end=$(_allowance_week_end "$new_week_start")

    local tmp="${allowance_file}.tmp"
    jq \
        --arg ws "$new_week_start" \
        --arg we "$new_week_end" \
        '
        # Archive current week to history
        .history += [{
            week_start: .current_week.week_start,
            week_end: .current_week.week_end,
            projects: .current_week.projects,
            total_used: .current_week.total_used
        }] |
        # Reset for new week
        .current_week = {
            week_start: $ws,
            week_end: $we,
            projects: {},
            total_used: 0
        }
        ' "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"

    log "ORCHESTRATOR" "Cross-project allowance rolled over to week $new_week_start — $new_week_end"
}

# Updates ~/.automaton/allowance.json with token usage for the current project.
# Called from update_budget() after each iteration in allowance mode.
# Args: tokens_used (input + output tokens for this iteration)
_update_cross_project_allowance() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local tokens_used="${1:-0}"
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ ! -f "$allowance_file" ]; then
        _init_cross_project_allowance
    fi

    local project_dir
    project_dir=$(pwd)
    local now_ts
    now_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp="${allowance_file}.tmp"
    jq \
        --arg project "$project_dir" \
        --argjson tokens "$tokens_used" \
        --arg last_run "$now_ts" \
        '
        # Update or create project entry
        if .current_week.projects[$project] then
            .current_week.projects[$project].tokens_used += $tokens |
            .current_week.projects[$project].last_run = $last_run
        else
            .current_week.projects[$project] = {
                tokens_used: $tokens,
                runs: 0,
                last_run: $last_run
            }
        end |
        # Recalculate total from all projects
        .current_week.total_used = ([.current_week.projects[].tokens_used] | add // 0)
        ' "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"
}

# Increments the run count for the current project in ~/.automaton/allowance.json.
# Called from write_run_summary() at run completion.
_increment_cross_project_run_count() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ ! -f "$allowance_file" ]; then
        return 0
    fi

    local project_dir
    project_dir=$(pwd)

    local tmp="${allowance_file}.tmp"
    jq \
        --arg project "$project_dir" \
        '
        if .current_week.projects[$project] then
            .current_week.projects[$project].runs += 1
        else . end
        ' "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"
}

# Returns total tokens used across all projects this week.
# Reads from ~/.automaton/allowance.json if available, falls back to local budget.json.
# WHY: Pacing calculations must account for all projects sharing the allowance.
_get_cross_project_total_used() {
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ -f "$allowance_file" ]; then
        jq '.current_week.total_used // 0' "$allowance_file" 2>/dev/null || echo 0
    else
        # Fall back to local project usage
        local budget_file="$AUTOMATON_DIR/budget.json"
        if [ -f "$budget_file" ]; then
            jq '.tokens_used_this_week // 0' "$budget_file" 2>/dev/null || echo 0
        else
            echo 0
        fi
    fi
}

# Calculates daily budget for allowance pacing (spec-35).
# Returns the number of tokens available per day based on remaining allowance
# and days until the weekly reset. Minimum 1 day to avoid division by zero.
# Prints the daily budget to stdout.
_calculate_daily_budget() {
    local budget_file="$AUTOMATON_DIR/budget.json"

    # Calculate remaining tokens using cross-project totals when available.
    # WHY: Pacing must account for all projects sharing the weekly allowance.
    local remaining effective_allowance cross_project_used
    effective_allowance=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
        'BEGIN { printf "%d", total * (1 - reserve/100) }')
    cross_project_used=$(_get_cross_project_total_used)
    if [ "$cross_project_used" -gt 0 ]; then
        remaining=$((effective_allowance - cross_project_used))
        [ "$remaining" -lt 0 ] && remaining=0
    elif [ -f "$budget_file" ] && [ "$(jq -r '.mode // ""' "$budget_file")" = "allowance" ]; then
        remaining=$(jq '.tokens_remaining // 0' "$budget_file")
    else
        remaining="$effective_allowance"
    fi

    # Calculate days until reset (minimum 1)
    local week_end today days_left
    if [ -f "$budget_file" ]; then
        week_end=$(jq -r '.week_end // ""' "$budget_file")
    fi
    if [ -z "${week_end:-}" ]; then
        local ws
        ws=$(_allowance_week_start)
        week_end=$(_allowance_week_end "$ws")
    fi
    today=$(date +%Y-%m-%d)

    # Calculate difference in days
    local today_epoch end_epoch
    today_epoch=$(date -d "$today" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$today" +%s 2>/dev/null || echo 0)
    end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s 2>/dev/null || echo 0)

    if [ "$today_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
        days_left=$(( (end_epoch - today_epoch) / 86400 + 1 ))
    else
        days_left=1
    fi
    [ "$days_left" -lt 1 ] && days_left=1

    # daily_budget = remaining / days_left
    awk -v rem="$remaining" -v days="$days_left" \
        'BEGIN { printf "%d", rem / days }'
}

# Checks daily budget at run startup and warns if it's below 500K tokens.
# Called from run_orchestration() after budget initialization.
_check_daily_budget_pacing() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local daily_budget
    daily_budget=$(_calculate_daily_budget)

    # Store daily budget in budget.json for enforcement
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ -f "$budget_file" ]; then
        local tmp="$AUTOMATON_DIR/budget.json.tmp"
        jq --argjson db "$daily_budget" \
            '.limits.daily_budget = $db' "$budget_file" > "$tmp"
        mv "$tmp" "$budget_file"
    fi

    if [ "$daily_budget" -lt 500000 ]; then
        local week_end
        week_end=$(jq -r '.week_end // "unknown"' "$budget_file" 2>/dev/null || echo "unknown")
        local days_left remaining
        remaining=$(jq '.tokens_remaining // 0' "$budget_file" 2>/dev/null || echo 0)
        log "ORCHESTRATOR" "WARNING: Daily budget is ${daily_budget} tokens (allowance resets after ${week_end}). Run may be cut short."
    else
        log "ORCHESTRATOR" "Daily budget pacing: ${daily_budget} tokens/day"
    fi
}

# Displays weekly allowance budget status without starting a run (spec-35).
# Shows: week dates, allowance, used, remaining, reserve, available,
# days left, daily pace, and recommended run budget.
# In API mode, shows API budget info instead.
# Called by --budget-check CLI command.
display_budget_check() {
    local budget_file="$AUTOMATON_DIR/budget.json"

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Calculate week boundaries
        local week_start week_end
        if [ -f "$budget_file" ] && [ "$(jq -r '.mode // ""' "$budget_file")" = "allowance" ]; then
            week_start=$(jq -r '.week_start // ""' "$budget_file")
            week_end=$(jq -r '.week_end // ""' "$budget_file")
        fi
        if [ -z "${week_start:-}" ]; then
            week_start=$(_allowance_week_start)
        fi
        if [ -z "${week_end:-}" ]; then
            week_end=$(_allowance_week_end "$week_start")
        fi

        # Format dates for display (e.g., "Feb 24" / "Mar 02")
        local ws_display we_display
        ws_display=$(date -d "$week_start" "+%b %d" 2>/dev/null || \
            date -jf "%Y-%m-%d" "$week_start" "+%b %d" 2>/dev/null || echo "$week_start")
        we_display=$(date -d "$week_end" "+%b %d, %Y" 2>/dev/null || \
            date -jf "%Y-%m-%d" "$week_end" "+%b %d, %Y" 2>/dev/null || echo "$week_end")

        # Get usage data
        local weekly_allowance used_tokens remaining effective_allowance reserve_pct
        weekly_allowance="$BUDGET_WEEKLY_ALLOWANCE"
        reserve_pct="$BUDGET_RESERVE_PERCENTAGE"

        effective_allowance=$(awk -v total="$weekly_allowance" -v reserve="$reserve_pct" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')

        # Use cross-project total when available for accurate pacing
        local cross_total
        cross_total=$(_get_cross_project_total_used)
        if [ "$cross_total" -gt 0 ]; then
            used_tokens="$cross_total"
        elif [ -f "$budget_file" ] && [ "$(jq -r '.mode // ""' "$budget_file")" = "allowance" ]; then
            used_tokens=$(jq '.tokens_used_this_week // 0' "$budget_file")
        else
            used_tokens=0
        fi
        remaining=$((effective_allowance - used_tokens))
        [ "$remaining" -lt 0 ] && remaining=0

        # Calculate reserve tokens and available (remaining after reserve)
        local reserve_tokens
        reserve_tokens=$(awk -v total="$weekly_allowance" -v reserve="$reserve_pct" \
            'BEGIN { printf "%d", total * reserve / 100 }')

        # Calculate days left
        local today today_epoch end_epoch days_left
        today=$(date +%Y-%m-%d)
        today_epoch=$(date -d "$today" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$today" +%s 2>/dev/null || echo 0)
        end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s 2>/dev/null || echo 0)
        if [ "$today_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
            days_left=$(( (end_epoch - today_epoch) / 86400 + 1 ))
        else
            days_left=1
        fi
        [ "$days_left" -lt 1 ] && days_left=1

        # Calculate daily pace and recommended run budget
        local daily_pace recommended_run
        daily_pace=$(awk -v rem="$remaining" -v days="$days_left" \
            'BEGIN { printf "%d", rem / days }')
        # Recommended = min(daily_pace, remaining * 0.5)
        local half_remaining
        half_remaining=$(awk -v rem="$remaining" 'BEGIN { printf "%d", rem * 0.5 }')
        if [ "$daily_pace" -lt "$half_remaining" ]; then
            recommended_run="$daily_pace"
        else
            recommended_run="$half_remaining"
        fi

        # Calculate usage percentage
        local used_pct
        used_pct=$(awk -v used="$used_tokens" -v total="$weekly_allowance" \
            'BEGIN { if (total > 0) printf "%.1f", used * 100 / total; else printf "0.0" }')

        # Format numbers with commas using printf
        _fmt_num() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " Automaton Weekly Budget Status"
        echo " Week:       $ws_display — $we_display"
        printf " Allowance:  %s tokens\n" "$(_fmt_num "$weekly_allowance")"
        printf " Used:       %s tokens (%s%%)\n" "$(_fmt_num "$used_tokens")" "$used_pct"
        printf " Remaining:  %s tokens\n" "$(_fmt_num "$remaining")"
        printf " Reserve:    %s tokens (%s%%)\n" "$(_fmt_num "$reserve_tokens")" "$reserve_pct"
        printf " Available:  %s tokens\n" "$(_fmt_num "$remaining")"
        echo " Days left:  $days_left"
        printf " Daily pace: %s tokens/day\n" "$(_fmt_num "$daily_pace")"
        printf " Recommended run budget: %s tokens\n" "$(_fmt_num "$recommended_run")"

        # Show cross-project usage if available (spec-35 §5)
        local allowance_file
        allowance_file=$(_cross_project_allowance_file)
        if [ -f "$allowance_file" ]; then
            local project_count cross_total
            project_count=$(jq '.current_week.projects | length' "$allowance_file" 2>/dev/null || echo 0)
            cross_total=$(jq '.current_week.total_used // 0' "$allowance_file" 2>/dev/null || echo 0)
            if [ "$project_count" -gt 1 ] || [ "$cross_total" -gt 0 ]; then
                echo "─────────── Cross-Project Usage ────────"
                printf " Projects:   %s\n" "$project_count"
                printf " Total used: %s tokens (all projects)\n" "$(_fmt_num "$cross_total")"
                # List individual projects
                local projects_list
                projects_list=$(jq -r '.current_week.projects | to_entries[] | "\(.key)\t\(.value.tokens_used)\t\(.value.runs)"' "$allowance_file" 2>/dev/null || true)
                if [ -n "$projects_list" ]; then
                    while IFS=$'\t' read -r proj_path proj_tokens proj_runs; do
                        local proj_name
                        proj_name=$(basename "$proj_path")
                        printf "   %s: %s tokens (%s runs)\n" "$proj_name" "$(_fmt_num "$proj_tokens")" "$proj_runs"
                    done <<< "$projects_list"
                fi
            fi
        fi

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    else
        # API mode: show API budget summary
        local total_used total_cost
        if [ -f "$budget_file" ]; then
            total_used=$(jq '(.used.total_input // 0) + (.used.total_output // 0)' "$budget_file")
            total_cost=$(jq '.used.estimated_cost_usd // 0' "$budget_file")
        else
            total_used=0
            total_cost=0
        fi

        _fmt_num() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " Automaton API Budget Status"
        echo " Mode:       api (pay-per-token)"
        printf " Max tokens: %s\n" "$(_fmt_num "$BUDGET_MAX_TOKENS")"
        printf " Max cost:   \$%s\n" "$BUDGET_MAX_USD"
        printf " Used:       %s tokens\n" "$(_fmt_num "$total_used")"
        printf " Cost:       \$%s\n" "$total_cost"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    exit 0
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

# Detects auto-compaction by finding input_tokens drops between turns in
# stream-json output. Auto-compaction at ~95% context capacity compresses the
# conversation, causing a significant drop in input_tokens on the next turn.
# Sets global: LAST_AUTO_COMPACTION_DETECTED (true/false)
# WHY: Knowing when compaction occurred helps explain unexpected behavior and
# informs task sizing decisions (spec-33).
detect_auto_compaction() {
    local result_output="$1"
    LAST_AUTO_COMPACTION_DETECTED=false

    # Extract all input_tokens values from lines containing usage data
    local token_values
    token_values=$(echo "$result_output" \
        | grep '"input_tokens"' \
        | jq -r '.usage.input_tokens // empty' 2>/dev/null \
        | grep -v '^$' || true)

    [ -z "$token_values" ] && return 0

    # Need at least 2 data points to detect a drop
    local count
    count=$(echo "$token_values" | wc -l)
    [ "$count" -lt 2 ] && return 0

    # Check for any drop where input_tokens decreases by more than 20%
    local prev_tokens=0
    local current_tokens
    while IFS= read -r current_tokens; do
        [ -z "$current_tokens" ] && continue
        if [ "$prev_tokens" -gt 0 ] && [ "$current_tokens" -lt "$prev_tokens" ]; then
            # Calculate drop percentage
            local drop_pct
            drop_pct=$(awk -v prev="$prev_tokens" -v curr="$current_tokens" \
                'BEGIN { printf "%.0f", ((prev - curr) / prev) * 100 }')
            if [ "$drop_pct" -ge 20 ]; then
                LAST_AUTO_COMPACTION_DETECTED=true
                log "ORCHESTRATOR" "WARNING: Auto-compaction detected in ${current_phase} iteration ${phase_iteration} (input_tokens dropped from ${prev_tokens} to ${current_tokens}, -${drop_pct}%). Uncommitted work may have been lost."
                # --- Mitigation: protect uncommitted work and refresh context ---
                mitigate_compaction
                return 0
            fi
        fi
        prev_tokens="$current_tokens"
    done <<< "$token_values"
}

# Mitigates auto-compaction by committing uncommitted work, refreshing
# progress.txt, and flagging the next iteration for reduced dynamic context.
# Without mitigation, auto-compaction can silently lose uncommitted changes
# and leave the agent in a confused state with stale context.
mitigate_compaction() {
    # 1. Force-commit any uncommitted work to prevent data loss
    local uncommitted_files
    uncommitted_files=$(git diff --name-only 2>/dev/null | wc -l)
    local untracked_files
    untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)

    if [ "$uncommitted_files" -gt 0 ] || [ "$untracked_files" -gt 0 ]; then
        log "ORCHESTRATOR" "Compaction mitigation: committing $uncommitted_files modified + $untracked_files untracked files"
        git add -A 2>/dev/null || true
        git commit -m "auto-save: compaction detected in ${current_phase} iteration ${phase_iteration}" \
            --allow-empty 2>/dev/null || true
    fi

    # 2. Regenerate progress.txt so next iteration has fresh state awareness
    generate_progress_txt 2>/dev/null || true

    # 3. Set flag to reduce dynamic context in the next iteration
    # When this flag is set, inject_dynamic_context will omit verbose sections
    # (iteration memory, full git diffs) to keep the prompt lean
    COMPACTION_REDUCE_CONTEXT=true

    # 4. Log the mitigation action
    log "ORCHESTRATOR" "Compaction mitigation complete: committed work, refreshed progress.txt, reducing next iteration context"
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

    # Calculate estimated context utilization (spec-33)
    local context_window=200000
    local estimated_utilization=0
    if [ "$total_iter_tokens" -gt 0 ]; then
        estimated_utilization=$(awk -v total="$total_iter_tokens" -v window="$context_window" \
            'BEGIN { printf "%.1f", (total / window) * 100 }')
    fi

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
            cache_hit_ratio: (if ($cache_read + $input_tokens + $cache_create) > 0
                then (($cache_read / ($cache_read + $input_tokens + $cache_create)) * 100 | round / 100)
                else 0 end),
            estimated_cost: $iter_cost,
            duration_seconds: $duration,
            task: $task,
            status: $status,
            timestamp: $timestamp,
            estimated_utilization: $utilization,
            bootstrap_tokens_saved: $bootstrap_saved,
            bootstrap_time_ms: $bootstrap_ms
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
        --argjson utilization "$estimated_utilization" \
        --argjson bootstrap_saved "${BOOTSTRAP_TOKENS_SAVED:-0}" \
        --argjson bootstrap_ms "${BOOTSTRAP_TIME_MS:-0}" \
        "$jq_filter" "$budget_file" > "$tmp"
    mv "$tmp" "$budget_file"

    # Update cross-project allowance tracking (spec-35 §5)
    if [ "$BUDGET_MODE" = "allowance" ]; then
        local iter_tokens=$((input_tokens + output_tokens))
        _update_cross_project_allowance "$iter_tokens"
    fi
}

# Checks rolling average cache hit ratio for the current phase.
# Emits a warning when the rolling average drops below 50% after 3+ iterations.
# WHY: Low cache ratio indicates the static prompt prefix is changing between
# iterations — likely a bug in prompt assembly that wastes tokens (spec-30).
check_cache_hit_ratio() {
    local budget_file="$AUTOMATON_DIR/budget.json"
    [ -f "$budget_file" ] || return 0

    local phase_count avg
    phase_count=$(jq --arg phase "$current_phase" \
        '[.history[] | select(.phase == $phase)] | length' \
        "$budget_file" 2>/dev/null || echo 0)

    # Only check after 3+ iterations in the current phase
    [ "$phase_count" -ge 3 ] || return 0

    avg=$(jq --arg phase "$current_phase" '
        [.history[] | select(.phase == $phase) | .cache_hit_ratio] |
        if length > 0 then (add / length) else 0 end
    ' "$budget_file" 2>/dev/null || echo 0)

    # Compare: avg < 0.50 means below 50%
    local below
    below=$(awk -v a="$avg" 'BEGIN { print (a < 0.50) ? 1 : 0 }')
    if [ "$below" -eq 1 ]; then
        local pct
        pct=$(awk -v a="$avg" 'BEGIN { printf "%.0f", a * 100 }')
        log "ORCHESTRATOR" "WARNING: Cache hit ratio for phase '${current_phase}' is ${pct}% (rolling avg over ${phase_count} iterations). Expected >=50%. Check that dynamic data is injected after the static prefix marker."
    fi
}

# Checks context utilization for the current iteration against per-phase ceilings.
# Logs a warning when utilization exceeds the ceiling (spec-33).
# WHY: Performance degrades as context fills; warnings alert users to split tasks
# or commit more frequently.
check_context_utilization() {
    local input_tokens="$1" output_tokens="$2" model="$3"

    # Model context window sizes (all current models are 200K)
    local context_window=200000
    case "$model" in
        opus|sonnet|haiku) context_window=200000 ;;
    esac

    # Per-phase context utilization ceilings
    local ceiling
    case "$current_phase" in
        research) ceiling=60 ;;
        plan)     ceiling=70 ;;
        build)    ceiling=80 ;;
        review)   ceiling=70 ;;
        *)        ceiling=80 ;;
    esac

    local total_tokens=$((input_tokens + output_tokens))
    [ "$total_tokens" -eq 0 ] && return 0

    local utilization_pct
    utilization_pct=$(awk -v total="$total_tokens" -v window="$context_window" \
        'BEGIN { printf "%.0f", (total / window) * 100 }')

    local exceeds
    exceeds=$(awk -v u="$utilization_pct" -v c="$ceiling" 'BEGIN { print (u > c) ? 1 : 0 }')

    if [ "$exceeds" -eq 1 ]; then
        log "ORCHESTRATOR" "WARNING: ${current_phase^} iteration ${phase_iteration} context utilization ${utilization_pct}% exceeds ceiling ${ceiling}%. Consider smaller tasks or more frequent commits."
    fi
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

        # Hard stop: weekly allowance exhausted (spec-35 §8)
        # Graceful exhaustion: iteration already completed (check_budget runs in
        # post_iteration), save state and run summary, then exit code 2.
        if [ "$tokens_remaining" -le 0 ]; then
            local reset_day_name
            reset_day_name=$(date -d "$week_end + 1 day" "+%A" 2>/dev/null || \
                date -jf "%Y-%m-%d" -v+1d "$week_end" "+%A" 2>/dev/null || echo "$week_end")
            log "ORCHESTRATOR" "Weekly allowance exhausted. Resets on ${reset_day_name}. Run --resume after reset."
            write_run_summary 2 2>/dev/null || true
            commit_persistent_state "${current_phase:-build}" "${iteration:-0}" 2>/dev/null || true
            write_state
            exit 2
        fi

        # Pre-iteration warning: less than one iteration's worth of tokens left
        if [ "$tokens_remaining" -lt "$BUDGET_PER_ITERATION" ]; then
            log "ORCHESTRATOR" "WARNING: Only ${tokens_remaining} tokens remaining in weekly allowance (need ~${BUDGET_PER_ITERATION} per iteration)"
        fi

        # Daily budget pacing (spec-35): enforce daily_budget as run-level ceiling
        local daily_budget run_tokens
        daily_budget=$(jq '.limits.daily_budget // 0' "$budget_file")
        if [ "$daily_budget" -gt 0 ]; then
            run_tokens=$(jq '(.used.total_input + .used.total_output)' "$budget_file")
            if [ "$run_tokens" -ge "$daily_budget" ]; then
                log "ORCHESTRATOR" "Daily budget pacing limit reached (${run_tokens}/${daily_budget} tokens). Saving state. Run --resume tomorrow or after adjusting budget."
                write_run_summary 2 2>/dev/null || true
                commit_persistent_state "${current_phase:-build}" "${iteration:-0}" 2>/dev/null || true
                write_state
                exit 2
            fi
            # Warning at 80% of daily budget
            local warn_threshold
            warn_threshold=$(awk -v db="$daily_budget" 'BEGIN { printf "%d", db * 0.8 }')
            if [ "$run_tokens" -ge "$warn_threshold" ]; then
                local pct
                pct=$(awk -v used="$run_tokens" -v total="$daily_budget" \
                    'BEGIN { printf "%.0f", (used / total) * 100 }')
                log "ORCHESTRATOR" "WARNING: Run at ${pct}% of daily budget (${run_tokens}/${daily_budget} tokens)"
            fi
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
# Agent Memory Migration (spec-27)
# ---------------------------------------------------------------------------

# Migrates existing AGENTS.md learnings into per-agent memory files under
# .claude/agent-memory/<name>/MEMORY.md. Called once on first run with
# agents.use_native_definitions enabled. The build agent receives the bulk
# of operational learnings since they are most relevant to implementation.
# Also migrates structured learnings from learnings.json if available.
migrate_learnings_to_agent_memory() {
    local memory_base=".claude/agent-memory"
    local builder_memory="$memory_base/automaton-builder/MEMORY.md"
    local marker="$AUTOMATON_DIR/.learnings_migrated"

    # Only migrate once — idempotent via marker file
    if [ -f "$marker" ]; then
        return 0
    fi

    # Ensure directories exist
    local agents=("automaton-research" "automaton-planner" "automaton-builder" "automaton-reviewer" "automaton-self-researcher")
    for agent in "${agents[@]}"; do
        mkdir -p "$memory_base/$agent"
    done

    log "ORCHESTRATOR" "Migrating learnings to per-agent memory (spec-27)"

    # Extract learnings from AGENTS.md (everything under ## Learnings)
    local agents_learnings=""
    if [ -f "AGENTS.md" ]; then
        agents_learnings=$(sed -n '/^## Learnings/,/^## /{ /^## Learnings/d; /^## /d; p; }' "AGENTS.md" | sed '/^$/d' || true)
    fi

    # Extract structured learnings from learnings.json if available
    local structured_learnings=""
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ -f "$learnings_file" ]; then
        structured_learnings=$(jq -r '
            .entries
            | map(select(.active == true))
            | sort_by(if .confidence == "high" then 0
                      elif .confidence == "medium" then 1
                      else 2 end)
            | .[]
            | "- " + .summary + (if .detail != "" then " (" + .detail + ")" else "" end)
        ' "$learnings_file" 2>/dev/null || true)
    fi

    # Build the migrated content for the builder agent
    local migrated=""
    if [ -n "$agents_learnings" ]; then
        migrated="${migrated}${agents_learnings}"$'\n'
    fi
    if [ -n "$structured_learnings" ]; then
        if [ -n "$migrated" ]; then
            migrated="${migrated}"$'\n'
        fi
        migrated="${migrated}${structured_learnings}"$'\n'
    fi

    # Append migrated learnings to builder's MEMORY.md (it gets the bulk)
    if [ -n "$migrated" ] && [ -f "$builder_memory" ]; then
        printf '%s' "$migrated" >> "$builder_memory"
        log "ORCHESTRATOR" "Migrated learnings to $builder_memory"
    fi

    # Seed other agents with relevant subset headers (no content duplication)
    for agent in "${agents[@]}"; do
        local mem_file="$memory_base/$agent/MEMORY.md"
        if [ ! -f "$mem_file" ]; then
            cat > "$mem_file" <<EOF
# ${agent} Memory

## Guidelines
- Keep this file under 200 lines (first 200 lines auto-included in system prompt)
- Remove outdated entries when adding new ones

## Learnings
EOF
        fi
    done

    # Write marker to prevent re-migration
    echo "migrated=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker"
    log "ORCHESTRATOR" "Learnings migration complete — marker written to $marker"
}

# Generates AGENTS.md from learnings.json and project metadata (spec-34).
# Called at phase transitions so AGENTS.md is a generated view rather than
# a manually-appended file. Preserves project metadata (name, language,
# framework, commands) from the existing AGENTS.md and replaces the learnings
# section with structured data from learnings.json.
# Enforces the 60-line AGENTS.md limit by truncating learnings if needed.
generate_agents_md() {
    local agents_file="AGENTS.md"
    local learnings_file="$AUTOMATON_DIR/learnings.json"

    # Extract project metadata from existing AGENTS.md before overwriting
    local project_name="" language="" framework=""
    local cmd_build="" cmd_test="" cmd_lint=""

    if [ -f "$agents_file" ]; then
        project_name=$(grep -m1 '^- Project:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        language=$(grep -m1 '^- Language:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        framework=$(grep -m1 '^- Framework:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        cmd_build=$(grep -m1 '^- Build:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        cmd_test=$(grep -m1 '^- Test:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        cmd_lint=$(grep -m1 '^- Lint:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
    fi

    # Fall back to directory name if project name not set or still placeholder
    if [ -z "$project_name" ] || [ "$project_name" = "your-project" ]; then
        project_name=$(basename "$(pwd)")
    fi

    # Count completed runs from run-summaries/ (may not exist yet)
    local run_count=0
    if [ -d "$AUTOMATON_DIR/run-summaries" ]; then
        run_count=$(find "$AUTOMATON_DIR/run-summaries" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
        run_count=$(echo "$run_count" | tr -d ' ')
    fi

    # Build learnings lines from learnings.json (active, high confidence first)
    local learnings_lines=""
    if [ -f "$learnings_file" ]; then
        learnings_lines=$(jq -r '
            .entries
            | map(select(.active == true))
            | sort_by(if .confidence == "high" then 0
                      elif .confidence == "medium" then 1
                      else 2 end)
            | .[]
            | "- " + .summary
        ' "$learnings_file" 2>/dev/null | head -40 || true)
    fi

    # Build recent activity from run-summaries/ (last 3 runs)
    local activity_lines=""
    if [ -d "$AUTOMATON_DIR/run-summaries" ]; then
        # shellcheck disable=SC2012
        activity_lines=$(ls -t "$AUTOMATON_DIR/run-summaries/"*.json 2>/dev/null \
            | head -3 \
            | while IFS= read -r f; do
                jq -r '"- " + .run_id + ": " +
                    (.phases_completed | join(" → ")) +
                    " (" + (.tasks_completed | tostring) + " tasks)"' "$f" 2>/dev/null || true
            done || true)
    fi

    # Assemble AGENTS.md into a temp file
    {
        echo "# Operational Guide"
        echo ""
        echo "## Project"
        echo ""
        echo "- Project: $project_name"
        [ -n "$language" ] && echo "- Language: $language"
        [ -n "$framework" ] && echo "- Framework: $framework"
        [ -n "${current_phase:-}" ] && echo "- Current Phase: $current_phase"
        [ "$run_count" -gt 0 ] && echo "- Total Runs: $run_count"
        echo ""
        echo "## Commands"
        echo ""
        echo "- Build: ${cmd_build:-(not configured)}"
        echo "- Test: ${cmd_test:-(not configured)}"
        echo "- Lint: ${cmd_lint:-(not configured)}"
        echo ""
        echo "## Learnings"
        echo ""
        if [ -n "$learnings_lines" ]; then
            echo "$learnings_lines"
        else
            echo "(none yet — learnings accumulate in .automaton/learnings.json)"
        fi
        if [ -n "$activity_lines" ]; then
            echo ""
            echo "## Recent Activity"
            echo ""
            echo "$activity_lines"
        fi
    } > "${agents_file}.tmp"

    # Enforce 60-line limit
    local line_count
    line_count=$(wc -l < "${agents_file}.tmp")
    line_count=$(echo "$line_count" | tr -d ' ')

    if [ "$line_count" -gt 60 ]; then
        head -59 "${agents_file}.tmp" > "${agents_file}.tmp2"
        echo "(truncated — full data in .automaton/learnings.json)" >> "${agents_file}.tmp2"
        mv "${agents_file}.tmp2" "$agents_file"
    else
        mv "${agents_file}.tmp" "$agents_file"
    fi

    log "ORCHESTRATOR" "AGENTS.md regenerated from learnings.json (${line_count} lines)"
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
        local remaining effective pct daily_pace
        remaining=$(jq '.tokens_remaining // 0' "$AUTOMATON_DIR/budget.json")
        effective=$(jq '.limits.effective_allowance // 1' "$AUTOMATON_DIR/budget.json")
        pct=$(awk -v r="$remaining" -v e="$effective" 'BEGIN { printf "%d", (r/e)*100 }')
        daily_pace=$(_calculate_daily_budget)
        echo "Remaining weekly allowance: $remaining tokens ($pct%)"
        echo "Daily pace: $daily_pace tokens/day"

        if [ "$daily_pace" -lt 500000 ]; then
            echo "Recommendation: Low daily budget (${daily_pace} tokens). Consider waiting for reset."
        elif [ "$pct" -gt 30 ]; then
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
# Run Summaries (spec-34)
# ---------------------------------------------------------------------------

# Calculates test coverage metrics from IMPLEMENTATION_PLAN.md annotations.
# Parses <!-- test: path --> and <!-- test: none --> markers to count:
# - tasks_with_tests: tasks annotated with a test file that exists on disk
# - tasks_without_tests: tasks annotated with a test file that does NOT exist
# - tasks_exempt: tasks annotated with <!-- test: none -->
# - tasks_unannotated: tasks with no test annotation at all
# Also checks test_results.json for passing/failing counts.
# WHY: coverage tracking ensures test discipline is maintained across runs
# and reveals testing gaps (spec-36 §6).
# Outputs: JSON object to stdout
calculate_test_coverage() {
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    local tasks_with_tests=0
    local tasks_without_tests=0
    local tasks_exempt=0
    local tasks_unannotated=0
    local tests_passing=0
    local tests_failing=0

    if [ -f "$plan_file" ]; then
        # Process each incomplete and completed task line
        while IFS= read -r line; do
            if echo "$line" | grep -q '<!-- test: none -->'; then
                tasks_exempt=$((tasks_exempt + 1))
            elif echo "$line" | grep -q '<!-- test:'; then
                # Extract test file path
                local test_path
                test_path=$(echo "$line" | sed -n 's/.*<!-- test: \([^ ]*\) -->.*/\1/p')
                if [ -n "$test_path" ] && [ -f "$test_path" ]; then
                    tasks_with_tests=$((tasks_with_tests + 1))
                else
                    tasks_without_tests=$((tasks_without_tests + 1))
                fi
            else
                tasks_unannotated=$((tasks_unannotated + 1))
            fi
        done < <(grep -E '^\- \[(x| )\]' "$plan_file" 2>/dev/null || true)
    fi

    # Check test results from test_results.json if it exists
    local results_file="$AUTOMATON_DIR/test_results.json"
    if [ -f "$results_file" ]; then
        tests_passing=$(jq '[.[] | select(.result == "pass")] | length' "$results_file" 2>/dev/null || echo 0)
        tests_failing=$(jq '[.[] | select(.result == "fail")] | length' "$results_file" 2>/dev/null || echo 0)
    fi

    # Calculate coverage ratio: tasks_with_tests / (tasks_with_tests + tasks_without_tests)
    local testable_tasks=$((tasks_with_tests + tasks_without_tests))
    local coverage_ratio="0.00"
    if [ "$testable_tasks" -gt 0 ]; then
        coverage_ratio=$(awk "BEGIN { printf \"%.2f\", $tasks_with_tests / $testable_tasks }")
    fi

    jq -n \
        --argjson tasks_with_tests "$tasks_with_tests" \
        --argjson tasks_without_tests "$tasks_without_tests" \
        --argjson tasks_exempt "$tasks_exempt" \
        --argjson tasks_unannotated "$tasks_unannotated" \
        --argjson coverage_ratio "$coverage_ratio" \
        --argjson tests_passing "$tests_passing" \
        --argjson tests_failing "$tests_failing" \
        '{
            tasks_with_tests: $tasks_with_tests,
            tasks_without_tests: $tasks_without_tests,
            tasks_exempt: $tasks_exempt,
            tasks_unannotated: $tasks_unannotated,
            coverage_ratio: $coverage_ratio,
            tests_passing: $tests_passing,
            tests_failing: $tests_failing
        }'
}

# Writes a per-run summary JSON to .automaton/run-summaries/.
# Captures: phases completed, iterations, tokens, cost, learnings, git commits,
# and test coverage metrics (spec-36 §6).
# Called at the end of run_orchestration() and from _handle_shutdown().
# Args: [exit_code] (default: 0)
write_run_summary() {
    local run_exit_code="${1:-0}"
    local summaries_dir="$AUTOMATON_DIR/run-summaries"
    mkdir -p "$summaries_dir"

    # Build run_id from started_at timestamp (colons → hyphens for filename safety)
    local run_ts="${started_at:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local run_id
    run_id="run-$(echo "$run_ts" | tr ':' '-')"
    local summary_file="$summaries_dir/${run_id}.json"

    local completed_at
    completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Phases completed from phase_history variable
    local phases_json="[]"
    if [ -n "${phase_history:-}" ] && [ "$phase_history" != "[]" ]; then
        phases_json=$(echo "$phase_history" | jq -c '[.[].phase]')
    fi

    # Task counts from IMPLEMENTATION_PLAN.md
    local tasks_completed=0 tasks_remaining=0
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    if [ -f "$plan_file" ]; then
        tasks_completed=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null || echo 0)
        tasks_remaining=$(grep -c '^\- \[ \]' "$plan_file" 2>/dev/null || echo 0)
    fi

    # Token usage from budget.json
    local input_tokens=0 output_tokens=0 cache_create=0 cache_read=0 cost_usd="0.00"
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ -f "$budget_file" ]; then
        input_tokens=$(jq '.used.total_input // 0' "$budget_file")
        output_tokens=$(jq '.used.total_output // 0' "$budget_file")
        cache_create=$(jq '.used.total_cache_create // 0' "$budget_file")
        cache_read=$(jq '.used.total_cache_read // 0' "$budget_file")
        cost_usd=$(jq '.used.estimated_cost_usd // 0' "$budget_file")
    fi

    # Learnings added during this run (created_at >= started_at)
    local learnings_added=0 new_learnings_json="[]"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ -f "$learnings_file" ]; then
        new_learnings_json=$(jq -c --arg since "$run_ts" '
            [.entries[] | select(.created_at >= $since) | .id]
        ' "$learnings_file" 2>/dev/null || echo "[]")
        learnings_added=$(echo "$new_learnings_json" | jq 'length')
    fi

    # Git commits since run started
    local commits_json="[]"
    if [ -n "${run_ts:-}" ]; then
        local raw_commits
        raw_commits=$(git log --oneline --since="$run_ts" --format="%h" 2>/dev/null || true)
        if [ -n "$raw_commits" ]; then
            commits_json=$(echo "$raw_commits" | jq -R -s -c 'split("\n") | map(select(. != ""))')
        fi
    fi

    # Calculate test coverage metrics (spec-36 §6)
    local test_coverage_json
    test_coverage_json=$(calculate_test_coverage 2>/dev/null || echo '{}')

    # Write the summary JSON
    jq -n \
        --arg run_id "$run_id" \
        --arg started_at "$run_ts" \
        --arg completed_at "$completed_at" \
        --argjson exit_code "$run_exit_code" \
        --argjson phases_completed "$phases_json" \
        --argjson iterations_total "${iteration:-0}" \
        --argjson tasks_completed "$tasks_completed" \
        --argjson tasks_remaining "$tasks_remaining" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson cache_create "$cache_create" \
        --argjson cache_read "$cache_read" \
        --argjson cost_usd "$cost_usd" \
        --argjson learnings_added "$learnings_added" \
        --argjson new_learnings "$new_learnings_json" \
        --argjson git_commits "$commits_json" \
        --argjson test_coverage "$test_coverage_json" \
        '{
            run_id: $run_id,
            started_at: $started_at,
            completed_at: $completed_at,
            exit_code: $exit_code,
            phases_completed: $phases_completed,
            iterations_total: $iterations_total,
            tasks_completed: $tasks_completed,
            tasks_remaining: $tasks_remaining,
            tokens_used: {
                input: $input_tokens,
                output: $output_tokens,
                cache_read: $cache_read,
                cache_create: $cache_create
            },
            estimated_cost_usd: $cost_usd,
            learnings_added: $learnings_added,
            new_learnings: $new_learnings,
            git_commits: $git_commits,
            test_coverage: $test_coverage
        }' > "$summary_file"

    log "ORCHESTRATOR" "Run summary written to $summary_file"

    # Accumulate into persistent budget history (spec-34)
    update_budget_history "$run_id" "$input_tokens" "$output_tokens" \
        "$cache_create" "$cache_read" "$cost_usd"

    # Increment run count in cross-project allowance tracking (spec-35 §5)
    _increment_cross_project_run_count
}

# Accumulates per-run token and cost data into .automaton/budget-history.json.
# Appends a run entry and updates/creates the weekly total for the current week.
# WHY: budget.json is ephemeral and reset each run; budget-history.json persists
# across runs for cost analysis and weekly allowance tracking.
# Args: run_id input_tokens output_tokens cache_create cache_read cost_usd
update_budget_history() {
    local run_id="$1" input_tokens="$2" output_tokens="$3"
    local cache_create="$4" cache_read="$5" cost_usd="$6"

    local history_file="$AUTOMATON_DIR/budget-history.json"
    local tmp="$AUTOMATON_DIR/budget-history.json.tmp"

    # Initialize file if missing or empty
    if [ ! -f "$history_file" ] || [ ! -s "$history_file" ]; then
        echo '{"runs":[],"weekly_totals":[]}' > "$history_file"
    fi

    local total_tokens=$((input_tokens + output_tokens))

    # Calculate cache hit ratio: cache_read / (cache_read + input + cache_create)
    local cache_hit_ratio="0.00"
    local cache_denominator=$((cache_read + input_tokens + cache_create))
    if [ "$cache_denominator" -gt 0 ]; then
        cache_hit_ratio=$(awk -v cr="$cache_read" -v denom="$cache_denominator" \
            'BEGIN { printf "%.2f", cr / denom }')
    fi

    # Build per-phase breakdown and utilization stats from budget.json history
    local phases_json="{}"
    local peak_utilization="0" avg_utilization="0"
    local total_bootstrap_saved="0" avg_bootstrap_ms="0"
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ -f "$budget_file" ]; then
        phases_json=$(jq -c '
            .history // [] | group_by(.phase) |
            map({
                key: .[0].phase,
                value: {
                    tokens: ([.[].input_tokens] | add) + ([.[].output_tokens] | add),
                    iterations: length
                }
            }) | from_entries
        ' "$budget_file" 2>/dev/null || echo "{}")

        # Extract peak and average context utilization from per-iteration history (spec-33)
        peak_utilization=$(jq '
            [.history // [] | .[].estimated_utilization // 0] |
            if length > 0 then max else 0 end
        ' "$budget_file" 2>/dev/null || echo "0")
        avg_utilization=$(jq '
            [.history // [] | .[].estimated_utilization // 0] |
            if length > 0 then (add / length * 10 | round / 10) else 0 end
        ' "$budget_file" 2>/dev/null || echo "0")

        # Aggregate bootstrap metrics from per-iteration history (spec-37)
        total_bootstrap_saved=$(jq '
            [.history // [] | .[].bootstrap_tokens_saved // 0] | add // 0
        ' "$budget_file" 2>/dev/null || echo "0")
        avg_bootstrap_ms=$(jq '
            [.history // [] | .[].bootstrap_time_ms // 0] |
            if length > 0 then (add / length | round) else 0 end
        ' "$budget_file" 2>/dev/null || echo "0")
    fi

    # Determine current week boundaries
    local week_start week_end
    if [ "$BUDGET_MODE" = "allowance" ]; then
        week_start=$(_allowance_week_start)
        week_end=$(_allowance_week_end "$week_start")
    else
        # For API mode, use ISO week (Monday-based)
        week_start=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
        week_end=$(date -d "$week_start + 6 days" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
    fi

    # Append run entry and update weekly total atomically
    jq \
        --arg run_id "$run_id" \
        --arg mode "${BUDGET_MODE:-api}" \
        --argjson tokens_used "$total_tokens" \
        --argjson cost "$cost_usd" \
        --arg cache_hit_ratio "$cache_hit_ratio" \
        --argjson phases "$phases_json" \
        --argjson peak_util "$peak_utilization" \
        --argjson avg_util "$avg_utilization" \
        --arg week_start "$week_start" \
        --arg week_end "$week_end" \
        --argjson bootstrap_saved "$total_bootstrap_saved" \
        --argjson bootstrap_avg_ms "$avg_bootstrap_ms" \
        '
        # Append run entry
        .runs += [{
            run_id: $run_id,
            mode: $mode,
            tokens_used: $tokens_used,
            estimated_cost_usd: ($cost | tonumber),
            cache_hit_ratio: ($cache_hit_ratio | tonumber),
            peak_utilization: $peak_util,
            avg_utilization: $avg_util,
            phases: $phases,
            bootstrap_tokens_saved: $bootstrap_saved,
            bootstrap_avg_time_ms: $bootstrap_avg_ms
        }] |

        # Update or create weekly total
        if (.weekly_totals | map(.week_start) | index($week_start)) then
            .weekly_totals |= map(
                if .week_start == $week_start then
                    .tokens_used += $tokens_used |
                    .runs += 1
                else . end
            )
        else
            .weekly_totals += [{
                week_start: $week_start,
                week_end: $week_end,
                tokens_used: $tokens_used,
                runs: 1
            }]
        end
    ' "$history_file" > "$tmp" && mv "$tmp" "$history_file"

    log "ORCHESTRATOR" "Budget history updated: ${total_tokens} tokens, \$${cost_usd} cost"
}

# Commits persistent state files (.automaton/ tracked files) to git.
# Called at phase transitions, run completion, shutdown, and every 5 build
# iterations to ensure persistent state survives interruptions (spec-34).
commit_persistent_state() {
    local phase="${1:-$current_phase}" iter="${2:-$iteration}"

    # Persistent files that should be tracked in git
    local -a persistent_files=(
        "$AUTOMATON_DIR/budget-history.json"
        "$AUTOMATON_DIR/learnings.json"
        "$AUTOMATON_DIR/run-summaries"
        "$AUTOMATON_DIR/test_results.json"
        "$AUTOMATON_DIR/self_modifications.json"
    )

    # Stage only files that exist
    local staged=false
    for f in "${persistent_files[@]}"; do
        if [ -e "$f" ]; then
            git add "$f" 2>/dev/null && staged=true
        fi
    done

    # Also stage AGENTS.md since it is generated from learnings.json
    if [ -f "AGENTS.md" ]; then
        git add "AGENTS.md" 2>/dev/null && staged=true
    fi

    if [ "$staged" != "true" ]; then
        return 0
    fi

    # Only commit if there are staged changes
    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "automaton: state checkpoint — ${phase} iteration ${iter}" 2>/dev/null || true
        log "ORCHESTRATOR" "Persistent state committed (${phase} iter ${iter})"
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

# Focused fix strategy: when the review→build loop has failed twice, instead
# of immediately escalating, extract only the specific failing issues and create
# a minimal, targeted task list for one more build cycle. This gives the system
# one last chance to self-heal before requiring human intervention.
#
# Strategy:
# 1. Extract failing test names and unchecked review tasks from the plan
# 2. Create a focused task list with ONLY those specific fixes
# 3. Clear iteration memory to give the builder fresh context
# 4. Set max iterations for this focused build to 3 (tight scope)
attempt_focused_fix() {
    local plan_file="IMPLEMENTATION_PLAN.md"
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    # Extract only unchecked tasks (these are the review-identified issues)
    local unchecked_tasks
    unchecked_tasks=$(grep '^\- \[ \]' "$plan_file" 2>/dev/null || true)

    # Extract failing test names from test_results.json
    local failing_tests=""
    if [ -f "$AUTOMATON_DIR/test_results.json" ]; then
        failing_tests=$(jq -r '.[]? | select(.status == "failed") | .test // empty' \
            "$AUTOMATON_DIR/test_results.json" 2>/dev/null || true)
    fi

    # Create a focused fix section in the plan
    {
        echo ""
        echo "## Focused Fix (Auto-Generated)"
        echo ""
        echo "The following issues were identified after 2 review cycles."
        echo "This is a targeted fix attempt. Fix ONLY these specific issues:"
        echo ""
        if [ -n "$failing_tests" ]; then
            echo "### Failing Tests"
            echo "$failing_tests" | while IFS= read -r test; do
                [ -z "$test" ] && continue
                echo "- [ ] Fix failing test: $test"
            done
            echo ""
        fi
        if [ -n "$unchecked_tasks" ]; then
            echo "### Remaining Review Issues"
            echo "$unchecked_tasks"
            echo ""
        fi
        echo "**IMPORTANT**: Do NOT refactor or improve unrelated code. Fix ONLY the items listed above."
    } >> "$plan_file"

    # Clear iteration memory to give fresh context
    : > "$AUTOMATON_DIR/iteration_memory.md" 2>/dev/null || true

    # Override max iterations for the focused build to keep it tight
    EXEC_MAX_ITER_BUILD=3

    log "ORCHESTRATOR" "Focused fix: created targeted task list with $(echo "$unchecked_tasks" | grep -c '\[ \]' 2>/dev/null || echo 0) review issues and $(echo "$failing_tests" | grep -c . 2>/dev/null || echo 0) failing tests. Max 3 build iterations."

    # Commit the focused fix plan
    git add "$plan_file" 2>/dev/null || true
    git commit -m "automaton: focused fix attempt after 2 failed reviews" 2>/dev/null || true
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
                local used remaining daily_pace
                used=$(jq '.tokens_used_this_week' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                remaining=$(jq '.tokens_remaining' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                daily_pace=$(jq '.limits.daily_budget // 0' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                echo "Mode: allowance | Used this week: $used | Remaining: $remaining | Daily pace: $daily_pace"
            else
                local cost
                cost=$(jq '.used.estimated_cost_usd' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                echo "Mode: api | Cost so far: \$$cost / \$$BUDGET_MAX_USD"
            fi
        fi
    } > "$summary_file"

    log "ORCHESTRATOR" "Context summary generated: $summary_file"
}

# Generates .automaton/progress.txt at each iteration (spec-33).
# A human-readable status file that any agent in any context window can read
# to understand full project state without loading history.
generate_progress_txt() {
    local progress_file="$AUTOMATON_DIR/progress.txt"
    local plan_file="IMPLEMENTATION_PLAN.md"

    # In self-build mode, use backlog
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    # Task counts
    local tasks_completed=0 tasks_remaining=0 tasks_total=0
    if [ -f "$plan_file" ]; then
        tasks_completed=$(grep -c '\[x\]' "$plan_file" 2>/dev/null || echo 0)
        tasks_remaining=$(grep -c '\[ \]' "$plan_file" 2>/dev/null || echo 0)
        tasks_total=$((tasks_completed + tasks_remaining))
    fi

    # Last completed task (most recent [x] line, stripped of markdown)
    local last_completed="None yet"
    if [ -f "$plan_file" ]; then
        local raw
        raw=$(grep '\[x\]' "$plan_file" | tail -1 | sed 's/^- \[x\] //' | sed 's/ (WHY:.*//' 2>/dev/null || true)
        if [ -n "$raw" ]; then
            last_completed="$raw"
        fi
    fi

    # Next pending task (first [ ] line, stripped of markdown)
    local next_pending="None"
    if [ -f "$plan_file" ]; then
        local raw_next
        raw_next=$(grep '\[ \]' "$plan_file" | head -1 | sed 's/^- \[ \] //' | sed 's/ (WHY:.*//' 2>/dev/null || true)
        if [ -n "$raw_next" ]; then
            next_pending="$raw_next"
        fi
    fi

    # Blocked info from stall/failure state
    local blocked_info="None"
    if [ "${stall_count:-0}" -ge 2 ]; then
        blocked_info="Stall detected ($stall_count consecutive iterations with no changes)"
    elif [ "${consecutive_failures:-0}" -ge 2 ]; then
        blocked_info="Consecutive failures ($consecutive_failures)"
    fi

    # Key decisions from recent git commits
    local key_decisions=""
    key_decisions=$(git log --oneline -5 --format="%s" 2>/dev/null | head -5 || true)

    # Budget info
    local budget_info="unknown"
    if [ -f "$AUTOMATON_DIR/budget.json" ]; then
        if [ "$BUDGET_MODE" = "allowance" ]; then
            local remaining
            remaining=$(jq '.tokens_remaining // "unknown"' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "unknown")
            budget_info="allowance, $remaining tokens remaining"
        else
            local cost_used
            cost_used=$(jq '.used.estimated_cost_usd // 0' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "0")
            budget_info="api, \$$cost_used / \$$BUDGET_MAX_USD spent"
        fi
    fi

    {
        echo "# Automaton Progress"
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Phase: $current_phase (iteration $phase_iteration)"
        if [ "$current_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
            echo "Build sub-phase: ${build_sub_phase:-implementation} (scaffold: $scaffold_iterations_done/$EXEC_TEST_SCAFFOLD_ITERATIONS done)"
        fi
        echo "Total iterations: $iteration"
        echo "Completed: $tasks_completed/$tasks_total tasks"
        echo "Last completed: $last_completed"
        echo "Next pending: $next_pending"
        echo "Currently blocked: $blocked_info"
        echo "Budget: $budget_info"
        echo ""
        echo "## Recent Commits"
        if [ -n "$key_decisions" ]; then
            echo "$key_decisions"
        else
            echo "No commits yet"
        fi
    } > "$progress_file"
}

# ---------------------------------------------------------------------------
# Bootstrap (spec-37)
# ---------------------------------------------------------------------------

# Run bootstrap script and return manifest JSON via stdout.
# Returns exit 0 on success, exit 1 on failure (disabled returns 0).
# On failure, logs error with stderr output and returns empty stdout.
# Falls back gracefully — bootstrap is an optimization, not a requirement.
# Callers should set BOOTSTRAP_FAILED based on exit code.
#
# Sets globals:
#   BOOTSTRAP_TIME_MS — elapsed time in milliseconds
#   BOOTSTRAP_TOKENS_SAVED — estimated input tokens saved vs agent-driven file reads
#
# Args:
#   $1 — phase (optional, defaults to $current_phase)
#   $2 — iteration (optional, defaults to $phase_iteration)
_run_bootstrap() {
    local phase="${1:-$current_phase}"
    local iteration="${2:-$phase_iteration}"

    # Initialize metrics globals
    BOOTSTRAP_TIME_MS=0
    BOOTSTRAP_TOKENS_SAVED=0

    if [ "$EXEC_BOOTSTRAP_ENABLED" != "true" ]; then
        return 0
    fi

    local script_path="$EXEC_BOOTSTRAP_SCRIPT"
    if [ ! -x "$script_path" ]; then
        log "ORCHESTRATOR" "Bootstrap script not found or not executable: $script_path"
        return 1
    fi

    local timeout_seconds=$(( EXEC_BOOTSTRAP_TIMEOUT_MS / 1000 ))
    [ "$timeout_seconds" -lt 1 ] && timeout_seconds=1

    # Millisecond-precision timing (fall back to seconds * 1000)
    local start_ms
    if date +%s%N &>/dev/null && [ "$(date +%s%N)" != "%N" ]; then
        start_ms=$(( $(date +%s%N) / 1000000 ))
    else
        start_ms=$(( $(date +%s) * 1000 ))
    fi

    local manifest="" stderr_file
    stderr_file=$(mktemp)
    if command -v timeout &>/dev/null; then
        manifest=$(timeout "${timeout_seconds}s" "$script_path" "." "$phase" "$iteration" 2>"$stderr_file") || {
            local stderr_output
            stderr_output=$(cat "$stderr_file")
            rm -f "$stderr_file"
            _bootstrap_record_time "$start_ms"
            log "ORCHESTRATOR" "Bootstrap failed. Falling back to agent-driven context loading."
            [ -n "$stderr_output" ] && log "ORCHESTRATOR" "Bootstrap stderr: $stderr_output"
            return 1
        }
    else
        manifest=$("$script_path" "." "$phase" "$iteration" 2>"$stderr_file") || {
            local stderr_output
            stderr_output=$(cat "$stderr_file")
            rm -f "$stderr_file"
            _bootstrap_record_time "$start_ms"
            log "ORCHESTRATOR" "Bootstrap failed. Falling back to agent-driven context loading."
            [ -n "$stderr_output" ] && log "ORCHESTRATOR" "Bootstrap stderr: $stderr_output"
            return 1
        }
    fi
    rm -f "$stderr_file"

    # Validate JSON
    if ! echo "$manifest" | jq empty 2>/dev/null; then
        _bootstrap_record_time "$start_ms"
        log "ORCHESTRATOR" "Bootstrap produced invalid JSON. Falling back to agent-driven context loading."
        return 1
    fi

    # Check for error field in manifest
    if echo "$manifest" | jq -e '.error' &>/dev/null; then
        _bootstrap_record_time "$start_ms"
        log "ORCHESTRATOR" "Bootstrap error: $(echo "$manifest" | jq -r '.error')"
        return 1
    fi

    # Record timing and estimate token savings
    _bootstrap_record_time "$start_ms"
    _bootstrap_estimate_tokens_saved "$manifest"

    # Performance check: warn if bootstrap exceeds 2-second target
    local target_ms="$EXEC_BOOTSTRAP_TIMEOUT_MS"
    if [ "$BOOTSTRAP_TIME_MS" -gt "$target_ms" ]; then
        local elapsed_s
        elapsed_s=$(awk -v ms="$BOOTSTRAP_TIME_MS" 'BEGIN { printf "%.1f", ms / 1000 }')
        local target_s
        target_s=$(awk -v ms="$target_ms" 'BEGIN { printf "%.1f", ms / 1000 }')
        log "ORCHESTRATOR" "WARNING: Bootstrap took ${elapsed_s}s (target: <${target_s}s). Consider optimizing init.sh."
    fi

    # Persist metrics to file so they survive the $() subshell boundary.
    # The caller (run_agent) reads these back into globals after the call.
    echo "{\"time_ms\":${BOOTSTRAP_TIME_MS},\"tokens_saved\":${BOOTSTRAP_TOKENS_SAVED}}" \
        > "${AUTOMATON_DIR}/bootstrap_metrics.json"

    echo "$manifest"
}

# Record elapsed bootstrap time in BOOTSTRAP_TIME_MS and persist metrics to file.
# Called on both success and failure paths so metrics survive the $() subshell.
# Args: $1 — start time in milliseconds
_bootstrap_record_time() {
    local start_ms="$1"
    local end_ms
    if date +%s%N &>/dev/null && [ "$(date +%s%N)" != "%N" ]; then
        end_ms=$(( $(date +%s%N) / 1000000 ))
    else
        end_ms=$(( $(date +%s) * 1000 ))
    fi
    BOOTSTRAP_TIME_MS=$(( end_ms - start_ms ))
    [ "$BOOTSTRAP_TIME_MS" -lt 0 ] && BOOTSTRAP_TIME_MS=0
    # Persist to file (tokens_saved may be updated later on success path)
    echo "{\"time_ms\":${BOOTSTRAP_TIME_MS},\"tokens_saved\":${BOOTSTRAP_TOKENS_SAVED}}" \
        > "${AUTOMATON_DIR}/bootstrap_metrics.json" 2>/dev/null || true
}

# Estimate input tokens saved by bootstrap vs agent-driven file reads.
# Without bootstrap, agents spend 3-5 tool calls reading AGENTS.md,
# IMPLEMENTATION_PLAN.md, state.json, budget.json, and specs (~20-50K tokens).
# Bootstrap provides the same data in a compact manifest (~2K tokens).
# Baseline: 30000 tokens (midpoint of 20-50K range from spec-37).
# Args: $1 — manifest JSON string
_bootstrap_estimate_tokens_saved() {
    local manifest="$1"
    local baseline_tokens=30000
    local manifest_bytes manifest_tokens
    manifest_bytes=$(printf '%s' "$manifest" | wc -c | tr -d ' ')
    manifest_tokens=$(( manifest_bytes / 4 ))
    BOOTSTRAP_TOKENS_SAVED=$(( baseline_tokens - manifest_tokens ))
    [ "$BOOTSTRAP_TOKENS_SAVED" -lt 0 ] && BOOTSTRAP_TOKENS_SAVED=0
}

# Format bootstrap manifest for inclusion in dynamic context.
# Returns formatted markdown block or empty string if manifest is empty.
#
# Args:
#   $1 — manifest JSON string
_format_bootstrap_for_context() {
    local manifest="$1"
    if [ -z "$manifest" ]; then
        # When bootstrap failed, tell the agent to read files manually
        if [ "${BOOTSTRAP_FAILED:-false}" = "true" ]; then
            echo "## Bootstrap Failed"
            echo ""
            echo "Bootstrap context assembly failed. You should read AGENTS.md, IMPLEMENTATION_PLAN.md, state files, and budget files manually to understand the project state."
            echo ""
        fi
        return 0
    fi
    echo "## Bootstrap Manifest"
    echo "<!-- Pre-assembled by init.sh — do NOT re-read these files -->"
    echo '```json'
    echo "$manifest" | jq .
    echo '```'
    echo ""
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

        # Bootstrap manifest (spec-37): pre-assembled context from init.sh
        # When bootstrap fails, _format_bootstrap_for_context emits a fallback
        # notice telling the agent to read files manually.
        if [ -n "${BOOTSTRAP_MANIFEST:-}" ] || [ "${BOOTSTRAP_FAILED:-false}" = "true" ]; then
            _format_bootstrap_for_context "${BOOTSTRAP_MANIFEST:-}"
        fi

        echo "## Current State"
        echo ""
        echo "- Phase: $current_phase"
        echo "- Iteration: $phase_iteration"

        # Build sub-phase context (spec-36)
        if [ "$current_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
            if [ "${build_sub_phase:-implementation}" = "scaffold" ]; then
                echo "- Build sub-phase: TEST SCAFFOLD (3a) — iteration $((scaffold_iterations_done + 1))/$EXEC_TEST_SCAFFOLD_ITERATIONS"
                echo ""
                echo "**TEST SCAFFOLD MODE**: Write test files ONLY for plan tasks with \`<!-- test: path -->\` annotations. Do NOT implement any features. Tests should fail initially (no implementation exists yet). Commit test files when done."
            else
                echo "- Build sub-phase: IMPLEMENTATION (3b)"
            fi
        fi

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

        # Build-specific context for iterations after the first.
        # When COMPACTION_REDUCE_CONTEXT is set (post-compaction mitigation),
        # emit only essential context (current focus) and skip verbose sections
        # (git diffs, iteration memory, codebase overview) to keep the prompt lean.
        if [ "$current_phase" = "build" ] && [ "$phase_iteration" -gt 1 ]; then
            local plan_file="IMPLEMENTATION_PLAN.md"
            if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
                plan_file="$AUTOMATON_DIR/backlog.md"
            fi

            if [ "${COMPACTION_REDUCE_CONTEXT:-false}" = "true" ]; then
                echo "## Post-Compaction Recovery"
                echo "Auto-compaction was detected. Context has been reduced. Read progress.txt for full state."
                echo ""
                echo "## Current Focus"
                if [ -f "$plan_file" ]; then
                    grep '\[ \]' "$plan_file" | head -3 || echo "All tasks complete."
                fi
                echo ""
                # Clear the flag after one reduced-context iteration
                COMPACTION_REDUCE_CONTEXT=false
            else
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

# Checks whether the static prefix of a prompt file meets the minimum token
# threshold required for prompt caching. Logs an informational message when
# the prefix is too small to be cached.
# WHY: Users need to know when caching is inactive so they can decide whether
# to expand the static prefix (spec-30).
#
# Minimum cacheable thresholds per model:
#   Opus/Haiku: 4096 tokens
#   Sonnet: 2048 tokens
#
# Args: prompt_file model
check_cache_prefix_threshold() {
    local prompt_file="$1"
    local model="$2"
    [ -f "$prompt_file" ] || return 0

    # Extract static prefix (everything before <dynamic_context>)
    local static_chars
    if grep -q '<dynamic_context>' "$prompt_file"; then
        static_chars=$(sed -n '1,/<dynamic_context>/p' "$prompt_file" | wc -c)
    else
        # No dynamic_context marker — entire prompt is static
        static_chars=$(wc -c < "$prompt_file")
    fi

    local est_tokens=$((static_chars / 4))

    # Determine threshold for model
    local threshold
    case "$model" in
        sonnet) threshold=2048 ;;
        *)      threshold=4096 ;;
    esac

    if [ "$est_tokens" -lt "$threshold" ]; then
        log "ORCHESTRATOR" "INFO: Static prompt prefix is ~${est_tokens} tokens, below the ${threshold}-token minimum for caching with model '${model}'. Prompt caching will be inactive. Consider expanding the static prefix to enable cache hits."
    fi
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
# Idea Garden (spec-38)
# ---------------------------------------------------------------------------

# Plants a new idea as a seed in .automaton/garden/.
# Creates a JSON file with the complete idea schema, auto-increments the ID
# from _index.json, records a stage_history entry, and rebuilds the index.
#
# Args: title description origin_type origin_source created_by
#       [estimated_complexity] [tags_csv]
# Outputs: the new idea ID (e.g. "idea-001") on stdout
# Returns: 0 on success, 1 on failure
_garden_plant_seed() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local title="${1:?_garden_plant_seed requires title}"
    local description="${2:?_garden_plant_seed requires description}"
    local origin_type="${3:?_garden_plant_seed requires origin_type}"
    local origin_source="${4:?_garden_plant_seed requires origin_source}"
    local created_by="${5:?_garden_plant_seed requires created_by}"
    local estimated_complexity="${6:-medium}"
    local tags_csv="${7:-}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local index_file="$garden_dir/_index.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Ensure garden directory exists
    mkdir -p "$garden_dir"

    # Initialize index if it doesn't exist
    if [ ! -f "$index_file" ]; then
        cat > "$index_file" << 'IDXEOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
IDXEOF
    fi

    # Read and increment next_id
    local next_id
    next_id=$(jq -r '.next_id // 1' "$index_file")
    local idea_id
    idea_id=$(printf "idea-%03d" "$next_id")
    local idea_file="$garden_dir/${idea_id}.json"

    # Build tags JSON array from CSV
    local tags_json="[]"
    if [ -n "$tags_csv" ]; then
        tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Create the idea JSON file with complete schema
    jq -n \
        --arg id "$idea_id" \
        --arg title "$title" \
        --arg description "$description" \
        --arg stage "seed" \
        --arg origin_type "$origin_type" \
        --arg origin_source "$origin_source" \
        --arg created_by "$created_by" \
        --arg created_at "$now" \
        --argjson tags "$tags_json" \
        --arg complexity "$estimated_complexity" \
        --arg updated_at "$now" \
        '{
            id: $id,
            title: $title,
            description: $description,
            stage: $stage,
            origin: {
                type: $origin_type,
                source: $origin_source,
                created_by: $created_by,
                created_at: $created_at
            },
            evidence: [],
            tags: $tags,
            priority: 0,
            estimated_complexity: $complexity,
            related_specs: [],
            related_signals: [],
            related_ideas: [],
            stage_history: [
                {
                    stage: "seed",
                    entered_at: $created_at,
                    reason: "Planted as new seed"
                }
            ],
            vote_id: null,
            implementation: null,
            updated_at: $updated_at
        }' > "$idea_file"

    log "GARDEN" "Planted seed: $idea_id - $title"

    # Rebuild the garden index
    _garden_rebuild_index

    echo "$idea_id"
}

# Adds an evidence item to an existing idea, updates updated_at,
# and calls _garden_advance_stage() if thresholds are met.
#
# Args: idea_id evidence_type observation added_by
# Returns: 0 on success, 1 if idea not found
_garden_water() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_water requires idea_id}"
    local evidence_type="${2:?_garden_water requires evidence_type}"
    local observation="${3:?_garden_water requires observation}"
    local added_by="${4:?_garden_water requires added_by}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "GARDEN" "Idea $idea_id not found"
        return 1
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Add evidence item and update timestamp
    local tmp_file="${idea_file}.tmp"
    jq --arg type "$evidence_type" \
       --arg obs "$observation" \
       --arg by "$added_by" \
       --arg now "$now" \
       '.evidence += [{type: $type, observation: $obs, added_by: $by, added_at: $now}] | .updated_at = $now' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Watered $idea_id with $evidence_type evidence"

    # Check if stage advancement is warranted
    local stage evidence_count
    stage=$(jq -r '.stage' "$idea_file")
    evidence_count=$(jq '.evidence | length' "$idea_file")

    if [ "$stage" = "seed" ] && [ "$evidence_count" -ge "$GARDEN_SPROUT_THRESHOLD" ]; then
        _garden_advance_stage "$idea_id" "sprout" "Evidence count ($evidence_count) reached sprout threshold ($GARDEN_SPROUT_THRESHOLD)"
    elif [ "$stage" = "sprout" ]; then
        local priority
        priority=$(jq -r '.priority // 0' "$idea_file")
        if [ "$evidence_count" -ge "$GARDEN_BLOOM_THRESHOLD" ] && [ "$priority" -ge "$GARDEN_BLOOM_PRIORITY_THRESHOLD" ]; then
            _garden_advance_stage "$idea_id" "bloom" "Evidence count ($evidence_count) and priority ($priority) met bloom thresholds"
        fi
    fi

    _garden_rebuild_index
}

# Transitions an idea to the next lifecycle stage.
# Validates threshold requirements for automatic transitions.
# Supports a force parameter for human promotion (bypasses thresholds).
#
# Args: idea_id target_stage reason [force]
# Returns: 0 on success, 1 on failure
_garden_advance_stage() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_advance_stage requires idea_id}"
    local target_stage="${2:?_garden_advance_stage requires target_stage}"
    local reason="${3:?_garden_advance_stage requires reason}"
    local force="${4:-false}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "GARDEN" "Idea $idea_id not found"
        return 1
    fi

    local current_stage
    current_stage=$(jq -r '.stage' "$idea_file")

    # Validate stage transition order (unless forced)
    if [ "$force" != "true" ]; then
        local transition="${current_stage}_to_${target_stage}"
        case "$transition" in
            seed_to_sprout|sprout_to_bloom|bloom_to_harvest) ;;
            *)
                log "GARDEN" "Invalid transition: $current_stage -> $target_stage for $idea_id"
                return 1
                ;;
        esac

        # Validate thresholds for non-forced transitions
        local evidence_count
        evidence_count=$(jq '.evidence | length' "$idea_file")

        if [ "$target_stage" = "sprout" ] && [ "$evidence_count" -lt "$GARDEN_SPROUT_THRESHOLD" ]; then
            log "GARDEN" "Cannot advance $idea_id to sprout: need $GARDEN_SPROUT_THRESHOLD evidence, have $evidence_count"
            return 1
        fi

        if [ "$target_stage" = "bloom" ]; then
            local priority
            priority=$(jq -r '.priority // 0' "$idea_file")
            if [ "$evidence_count" -lt "$GARDEN_BLOOM_THRESHOLD" ]; then
                log "GARDEN" "Cannot advance $idea_id to bloom: need $GARDEN_BLOOM_THRESHOLD evidence, have $evidence_count"
                return 1
            fi
            if [ "$priority" -lt "$GARDEN_BLOOM_PRIORITY_THRESHOLD" ]; then
                log "GARDEN" "Cannot advance $idea_id to bloom: need priority >= $GARDEN_BLOOM_PRIORITY_THRESHOLD, have $priority"
                return 1
            fi
        fi
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update stage and record history
    local tmp_file="${idea_file}.tmp"
    jq --arg stage "$target_stage" \
       --arg now "$now" \
       --arg reason "$reason" \
       '.stage = $stage | .updated_at = $now | .stage_history += [{stage: $stage, entered_at: $now, reason: $reason}]' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Advanced $idea_id: $current_stage -> $target_stage"
}

# Moves an idea to the wilt stage with a reason.
# Records a stage_history entry and rebuilds the index.
# Wilting preserves the idea record for audit while removing it from active consideration.
#
# Args: idea_id reason
# Returns: 0 on success, 1 on failure
_garden_wilt() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_wilt requires idea_id}"
    local reason="${2:?_garden_wilt requires reason}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "GARDEN" "Idea $idea_id not found"
        return 1
    fi

    local current_stage
    current_stage=$(jq -r '.stage' "$idea_file")

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update stage to wilt, record reason in stage_history, update timestamp
    local tmp_file="${idea_file}.tmp"
    jq --arg now "$now" \
       --arg reason "$reason" \
       '.stage = "wilt" | .updated_at = $now | .stage_history += [{stage: "wilt", entered_at: $now, reason: $reason}]' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Wilted $idea_id ($current_stage -> wilt): $reason"

    _garden_rebuild_index
}

# Recomputes priority scores for all active (non-wilted, non-harvested) ideas
# using the 5-component formula from spec-38 §4:
#   priority = (evidence_weight*30) + (signal_strength*25) + (metric_severity*25) + (age_bonus*10) + (human_boost*10)
#
# Components:
#   evidence_weight: min(evidence_count / bloom_threshold, 1.0)
#   signal_strength: max strength of related signals (0 if none or no signals file)
#   metric_severity: normalized severity of originating metric breach (0-1.0)
#   age_bonus:       min(days_since_creation / 30, 1.0)
#   human_boost:     1.0 if origin.type == "human", else 0
#
# Updates each idea's priority field in-place. Skips wilted and harvested ideas.
_garden_recompute_priorities() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 0; fi
    local garden_dir="$AUTOMATON_DIR/garden"
    local signals_file="$AUTOMATON_DIR/signals.json"

    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

    local now_epoch
    now_epoch=$(date -u +%s)

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")

        # Skip wilted and harvested ideas
        if [ "$stage" = "wilt" ] || [ "$stage" = "harvest" ]; then
            continue
        fi

        # 1. evidence_weight: min(evidence_count / bloom_threshold, 1.0)
        local evidence_count
        evidence_count=$(jq '.evidence | length' "$f")
        local evidence_weight
        evidence_weight=$(awk "BEGIN { v = $evidence_count / $GARDEN_BLOOM_THRESHOLD; print (v > 1.0 ? 1.0 : v) }")

        # 2. signal_strength: max strength of related signals
        local signal_strength=0
        if [ -f "$signals_file" ]; then
            local related_signals
            related_signals=$(jq -r '.related_signals // [] | .[]' "$f" 2>/dev/null)
            if [ -n "$related_signals" ]; then
                local max_str
                max_str=$(echo "$related_signals" | while IFS= read -r sig_id; do
                    jq -r --arg id "$sig_id" '.signals[]? | select(.id == $id) | .strength // 0' "$signals_file" 2>/dev/null
                done | sort -rn | head -1)
                if [ -n "$max_str" ]; then
                    signal_strength="$max_str"
                fi
            fi
        fi

        # 3. metric_severity: based on origin type and source
        local metric_severity=0
        local origin_type
        origin_type=$(jq -r '.origin.type' "$f")
        if [ "$origin_type" = "metric" ]; then
            # Extract numeric value from origin.source if it contains a threshold breach
            local origin_source
            origin_source=$(jq -r '.origin.source // ""' "$f")
            local extracted_val
            extracted_val=$(echo "$origin_source" | grep -oE '[0-9]+\.?[0-9]*' | tail -1 || true)
            if [ -n "$extracted_val" ]; then
                # Normalize: cap at 1.0 (values like 0.25 become 0.25, values > 1 become 1.0)
                metric_severity=$(awk "BEGIN { v = $extracted_val; print (v > 1.0 ? 1.0 : v) }")
            else
                # Metric origin but no extractable value — assign a moderate default
                metric_severity="0.5"
            fi
        fi

        # 4. age_bonus: min(days_since_creation / 30, 1.0)
        local created_at
        created_at=$(jq -r '.origin.created_at' "$f")
        local created_epoch
        created_epoch=$(date -u -d "$created_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || echo "$now_epoch")
        local days_old
        days_old=$(( (now_epoch - created_epoch) / 86400 ))
        local age_bonus
        age_bonus=$(awk "BEGIN { v = $days_old / 30.0; print (v > 1.0 ? 1.0 : v) }")

        # 5. human_boost: 1.0 if origin.type == "human", else 0
        local human_boost=0
        if [ "$origin_type" = "human" ]; then
            human_boost=1
        fi

        # Compute final priority: integer 0-100
        local priority
        priority=$(awk "BEGIN {
            p = ($evidence_weight * 30) + ($signal_strength * 25) + ($metric_severity * 25) + ($age_bonus * 10) + ($human_boost * 10);
            p = int(p + 0.5);
            if (p > 100) p = 100;
            if (p < 0) p = 0;
            print p
        }")

        # Update the idea file
        local tmp_file="${f}.tmp"
        jq --argjson priority "$priority" '.priority = $priority' "$f" > "$tmp_file" && mv "$tmp_file" "$f"
    done

    log "GARDEN" "Recomputed priorities for all active ideas"
}

# Regenerates .automaton/garden/_index.json from all idea files.
# Provides total counts, by_stage breakdown, bloom_candidates sorted by priority,
# recent_activity, next_id, and updated_at.
_garden_rebuild_index() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 0; fi
    local garden_dir="$AUTOMATON_DIR/garden"
    local index_file="$garden_dir/_index.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Collect all idea files
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

    local total=0
    local seed_count=0 sprout_count=0 bloom_count=0 harvest_count=0 wilt_count=0
    local max_id=0
    local bloom_candidates="[]"
    local recent_activity="[]"

    for f in $idea_files; do
        [ -f "$f" ] || continue
        total=$((total + 1))

        local stage id priority title updated_at_idea
        stage=$(jq -r '.stage' "$f")
        id=$(jq -r '.id' "$f")
        priority=$(jq -r '.priority // 0' "$f")
        title=$(jq -r '.title' "$f")
        updated_at_idea=$(jq -r '.updated_at' "$f")

        # Extract numeric ID for next_id calculation
        local num
        num=$(echo "$id" | sed 's/idea-0*//')
        if [ "$num" -gt "$max_id" ] 2>/dev/null; then
            max_id=$num
        fi

        # Count by stage
        case "$stage" in
            seed)    seed_count=$((seed_count + 1)) ;;
            sprout)  sprout_count=$((sprout_count + 1)) ;;
            bloom)   bloom_count=$((bloom_count + 1))
                     bloom_candidates=$(echo "$bloom_candidates" | jq --arg id "$id" --arg title "$title" --argjson priority "$priority" '. + [{"id": $id, "title": $title, "priority": $priority}]')
                     ;;
            harvest) harvest_count=$((harvest_count + 1)) ;;
            wilt)    wilt_count=$((wilt_count + 1)) ;;
        esac

        # Track recent activity (last stage_history entry)
        local last_action last_at
        last_action=$(jq -r '.stage_history[-1].stage // "unknown"' "$f")
        last_at=$(jq -r '.stage_history[-1].entered_at // ""' "$f")
        if [ -n "$last_at" ]; then
            recent_activity=$(echo "$recent_activity" | jq --arg id "$id" --arg action "$last_action" --arg at "$last_at" '. + [{"id": $id, "action": $action, "at": $at}]')
        fi
    done

    # Sort bloom candidates by priority descending
    bloom_candidates=$(echo "$bloom_candidates" | jq 'sort_by(-.priority)')

    # Keep only most recent 10 activity entries, sorted by time descending
    recent_activity=$(echo "$recent_activity" | jq 'sort_by(.at) | reverse | .[0:10]')

    local next_id=$((max_id + 1))

    # Write the index
    jq -n \
        --argjson total "$total" \
        --argjson seed "$seed_count" \
        --argjson sprout "$sprout_count" \
        --argjson bloom "$bloom_count" \
        --argjson harvest "$harvest_count" \
        --argjson wilt "$wilt_count" \
        --argjson bloom_candidates "$bloom_candidates" \
        --argjson recent_activity "$recent_activity" \
        --argjson next_id "$next_id" \
        --arg updated_at "$now" \
        '{
            total: $total,
            by_stage: {
                seed: $seed,
                sprout: $sprout,
                bloom: $bloom,
                harvest: $harvest,
                wilt: $wilt
            },
            bloom_candidates: $bloom_candidates,
            recent_activity: $recent_activity,
            next_id: $next_id,
            updated_at: $updated_at
        }' > "$index_file"
}

# Auto-wilts seeds older than GARDEN_SEED_TTL_DAYS and sprouts older than
# GARDEN_SPROUT_TTL_DAYS that have received no new evidence. TTL for seeds
# is measured from creation date; TTL for sprouts is measured from the most
# recent evidence timestamp (or creation date if no evidence).
_garden_prune_expired() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 0; fi
    local garden_dir="$AUTOMATON_DIR/garden"

    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)
    [ -n "$idea_files" ] || return 0

    local now_epoch
    now_epoch=$(date -u +%s)
    local seed_ttl_secs=$((GARDEN_SEED_TTL_DAYS * 86400))
    local sprout_ttl_secs=$((GARDEN_SPROUT_TTL_DAYS * 86400))
    local pruned=0

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")

        if [ "$stage" = "seed" ]; then
            # Seeds: TTL from creation date
            local created_at
            created_at=$(jq -r '.origin.created_at' "$f")
            local created_epoch
            created_epoch=$(date -u -d "$created_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || echo "$now_epoch")
            local age_secs=$((now_epoch - created_epoch))
            if [ "$age_secs" -ge "$seed_ttl_secs" ]; then
                local idea_id
                idea_id=$(jq -r '.id' "$f")
                _garden_wilt "$idea_id" "TTL expired: seed received no evidence after ${GARDEN_SEED_TTL_DAYS} days"
                pruned=$((pruned + 1))
            fi
        elif [ "$stage" = "sprout" ]; then
            # Sprouts: TTL from most recent evidence timestamp
            local last_evidence_at
            last_evidence_at=$(jq -r '(.evidence | last | .added_at) // .origin.created_at' "$f")
            local last_evidence_epoch
            last_evidence_epoch=$(date -u -d "$last_evidence_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_evidence_at" +%s 2>/dev/null || echo "$now_epoch")
            local stale_secs=$((now_epoch - last_evidence_epoch))
            if [ "$stale_secs" -ge "$sprout_ttl_secs" ]; then
                local idea_id
                idea_id=$(jq -r '.id' "$f")
                _garden_wilt "$idea_id" "TTL expired: sprout received no new evidence after ${GARDEN_SPROUT_TTL_DAYS} days"
                pruned=$((pruned + 1))
            fi
        fi
        # bloom, harvest, wilt stages are immune to TTL pruning
    done

    if [ "$pruned" -gt 0 ]; then
        log "GARDEN" "Pruned $pruned expired ideas"
    fi
}

# Checks for existing non-wilted ideas with matching tags before creating a
# new seed. Returns the existing idea ID (on stdout) if a match is found.
# A match requires at least one overlapping tag between the search tags and
# the candidate idea's tags. Wilted and harvested ideas are excluded.
#
# Args: tags_csv (comma-separated tags to match against)
# Returns: 0 and prints idea ID if duplicate found, 1 if no match
_garden_find_duplicates() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local tags_csv="${1:?_garden_find_duplicates requires tags_csv}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)
    [ -n "$idea_files" ] || return 1

    # Convert search tags CSV to newline-separated list for comparison
    local search_tags
    search_tags=$(echo "$tags_csv" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")

        # Skip wilted and harvested ideas
        [ "$stage" = "wilt" ] && continue
        [ "$stage" = "harvest" ] && continue

        # Get idea's tags as newline-separated list
        local idea_tags
        idea_tags=$(jq -r '.tags[]' "$f" 2>/dev/null)
        [ -n "$idea_tags" ] || continue

        # Check for any overlapping tag
        local tag
        while IFS= read -r tag; do
            [ -n "$tag" ] || continue
            if echo "$idea_tags" | grep -qxF "$tag"; then
                local idea_id
                idea_id=$(jq -r '.id' "$f")
                log "GARDEN" "Duplicate detected: $idea_id matches tags [$tags_csv]"
                echo "$idea_id"
                return 0
            fi
        done <<< "$search_tags"
    done

    return 1
}

# Returns sprout-stage ideas eligible for bloom transition, sorted by priority
# descending. An idea is eligible when its evidence count >= bloom_threshold
# and its priority >= bloom_priority_threshold.
# Outputs one idea ID per line (highest priority first).
#
# Returns: 0 if candidates found, 1 if none
_garden_get_bloom_candidates() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)
    [ -n "$idea_files" ] || return 1

    local candidates=""

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")
        [ "$stage" = "sprout" ] || continue

        local evidence_count priority
        evidence_count=$(jq '.evidence | length' "$f")
        priority=$(jq -r '.priority // 0' "$f")

        if [ "$evidence_count" -ge "$GARDEN_BLOOM_THRESHOLD" ] && [ "$priority" -ge "$GARDEN_BLOOM_PRIORITY_THRESHOLD" ]; then
            local idea_id
            idea_id=$(jq -r '.id' "$f")
            candidates="${candidates}${priority} ${idea_id}"$'\n'
        fi
    done

    [ -n "$candidates" ] || return 1

    # Sort by priority descending, output only idea IDs
    echo "$candidates" | sort -t' ' -k1 -nr | awk '{print $2}'
    return 0
}

# ---------------------------------------------------------------------------
# Stigmergic Signal Coordination (spec-42)
# ---------------------------------------------------------------------------

# Guard: returns 0 if stigmergy is enabled, 1 otherwise.
# All signal functions should call this before operating.
_signal_enabled() {
    [ "${STIGMERGY_ENABLED:-true}" = "true" ]
}

# Returns the default decay_rate for a given signal type.
# See spec-42 §3 for type-specific decay rates.
_signal_default_decay_rate() {
    local type="$1"
    case "$type" in
        attention_needed)    echo "0.10" ;;
        promising_approach)  echo "0.05" ;;
        recurring_pattern)   echo "0.05" ;;
        efficiency_opportunity) echo "0.08" ;;
        quality_concern)     echo "0.07" ;;
        complexity_warning)  echo "0.06" ;;
        *)                   echo "0.05" ;;
    esac
}

# Lazily initializes .automaton/signals.json with an empty structure.
# Called on first signal emission, not during initialize_state().
_signal_init_file() {
    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        cat > "$signals_file" << 'SIGEOF'
{"version":1,"signals":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
SIGEOF
    fi
}

# Emits a new signal or reinforces an existing one if a match is found.
# Creates .automaton/signals.json lazily on first call.
#
# Args: type title description agent cycle detail
# Returns: 0 on success, outputs signal ID (SIG-NNN)
_signal_emit() {
    if ! _signal_enabled; then return 1; fi
    local type="${1:?_signal_emit requires type}"
    local title="${2:?_signal_emit requires title}"
    local description="${3:?_signal_emit requires description}"
    local agent="${4:-unknown}"
    local cycle="${5:-0}"
    local detail="${6:-}"

    local signals_file="$AUTOMATON_DIR/signals.json"

    # Lazy initialization — create signals.json on first emission
    _signal_init_file

    # Check for existing matching signal to reinforce instead of duplicate
    local match_id
    match_id=$(_signal_find_match "$type" "$title" "$description")

    if [ -n "$match_id" ]; then
        # Reinforce the existing signal with a new observation
        _signal_reinforce "$match_id" "$agent" "$cycle" "$detail"
        log "SIGNAL" "Reinforced: $match_id - $title"
        echo "$match_id"
        return 0
    fi

    # No match — create a new signal
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local next_id
    next_id=$(jq -r '.next_id // 1' "$signals_file")
    local signal_id
    signal_id=$(printf "SIG-%03d" "$next_id")

    local decay_rate
    decay_rate=$(_signal_default_decay_rate "$type")

    local initial_strength="${STIGMERGY_INITIAL_STRENGTH:-0.3}"

    # Append the new signal and update next_id
    local tmp_file="${signals_file}.tmp"
    jq --arg id "$signal_id" \
       --arg type "$type" \
       --arg title "$title" \
       --arg desc "$description" \
       --argjson strength "$initial_strength" \
       --argjson decay_rate "$decay_rate" \
       --arg agent "$agent" \
       --argjson cycle "$cycle" \
       --arg now "$now" \
       --arg detail "$detail" \
       '.signals += [{
            id: $id,
            type: $type,
            title: $title,
            description: $desc,
            strength: $strength,
            decay_rate: $decay_rate,
            observations: [{
                agent: $agent,
                cycle: $cycle,
                timestamp: $now,
                detail: $detail
            }],
            related_ideas: [],
            created_at: $now,
            last_reinforced_at: $now,
            last_decayed_at: $now
        }] | .next_id = (.next_id + 1) | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    log "SIGNAL" "Emitted: $signal_id - $title (type=$type, strength=$initial_strength)"
    echo "$signal_id"
}

# Reinforces an existing signal by adding an observation and increasing strength.
# Strength increases by STIGMERGY_REINFORCE_INCREMENT, capped at 1.0.
#
# Args: signal_id agent cycle detail
# Returns: 0 on success
_signal_reinforce() {
    if ! _signal_enabled; then return 1; fi
    local signal_id="${1:?_signal_reinforce requires signal_id}"
    local agent="${2:-unknown}"
    local cycle="${3:-0}"
    local detail="${4:-}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 1

    local reinforce_increment="${STIGMERGY_REINFORCE_INCREMENT:-0.15}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${signals_file}.tmp"
    jq --arg id "$signal_id" \
       --argjson inc "$reinforce_increment" \
       --arg agent "$agent" \
       --argjson cycle "$cycle" \
       --arg now "$now" \
       --arg detail "$detail" \
       '(.signals[] | select(.id == $id)) |=
            (.observations += [{agent: $agent, cycle: $cycle, timestamp: $now, detail: $detail}]
            | .strength = ([.strength + $inc, 1.0] | min)
            | .last_reinforced_at = $now)
        | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"
}

# Finds an existing signal of the same type with sufficient word overlap.
# Uses Jaccard similarity on key terms from title+description.
# Returns the matching signal ID if overlap >= match_threshold, empty otherwise.
#
# Args: type title description
# Outputs: matching signal ID (e.g. SIG-001) or empty string
_signal_find_match() {
    local type="${1:?_signal_find_match requires type}"
    local title="${2:?_signal_find_match requires title}"
    local description="${3:-}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 0

    local threshold="${STIGMERGY_MATCH_THRESHOLD:-0.6}"

    # Extract same-type signal IDs, titles, and descriptions via jq
    local candidates
    candidates=$(jq -r --arg t "$type" \
        '.signals[] | select(.type == $t) | "\(.id)\t\(.title) \(.description)"' \
        "$signals_file" 2>/dev/null) || return 0

    [ -n "$candidates" ] || return 0

    # Build the new signal's word set (lowercase, unique, stop words removed)
    local new_text
    new_text=$(printf '%s %s' "$title" "$description" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | grep -vxE '(a|an|the|in|on|at|of|to|is|it|and|or|for|by|with|from|that|this|was|are|has|been|but|not|its)' || true)

    [ -n "$new_text" ] || return 0

    local best_id=""
    local best_score=0

    while IFS=$'\t' read -r sig_id sig_text; do
        # Build the existing signal's word set
        local existing_text
        existing_text=$(printf '%s' "$sig_text" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | grep -vxE '(a|an|the|in|on|at|of|to|is|it|and|or|for|by|with|from|that|this|was|are|has|been|but|not|its)' || true)

        [ -n "$existing_text" ] || continue

        # Compute Jaccard similarity: |intersection| / |union|
        local intersection union
        intersection=$(comm -12 <(echo "$new_text") <(echo "$existing_text") | wc -l)
        union=$(comm <(echo "$new_text") <(echo "$existing_text") | sed 's/^\t*//' | sort -u | wc -l)

        [ "$union" -gt 0 ] || continue

        # Compare using integer arithmetic (multiply by 100 to avoid floats)
        local score_100=$(( intersection * 100 / union ))
        local threshold_100
        threshold_100=$(printf '%.0f' "$(echo "$threshold * 100" | bc 2>/dev/null || echo "60")")

        if [ "$score_100" -ge "$threshold_100" ] && [ "$score_100" -gt "$best_score" ]; then
            best_score=$score_100
            best_id=$sig_id
        fi
    done <<< "$candidates"

    echo "$best_id"
}

# Decays all signal strengths by their individual decay_rate.
# Removes signals whose strength drops below decay_floor.
# Called at the start of each evolution cycle (spec-42 §4).
#
# Returns: 0 on success, 1 if disabled or no signals file
_signal_decay_all() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 1

    local decay_floor="${STIGMERGY_DECAY_FLOOR:-0.05}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${signals_file}.tmp"
    jq --argjson floor "$decay_floor" \
       --arg now "$now" \
       '.signals = [.signals[] |
            .strength = (.strength - .decay_rate) |
            .last_decayed_at = $now
        ] | .signals = [.signals[] | select(.strength >= $floor)] | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    local remaining
    remaining=$(jq '.signals | length' "$signals_file")
    log "SIGNAL" "Decay applied: $remaining signals remaining (floor=$decay_floor)"
}

_signal_prune() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 0

    local max_signals="${STIGMERGY_MAX_SIGNALS:-100}"
    local current_count
    current_count=$(jq '.signals | length' "$signals_file")

    if [ "$current_count" -le "$max_signals" ]; then
        return 0
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local pruned=$(( current_count - max_signals ))

    local tmp_file="${signals_file}.tmp"
    jq --argjson keep "$max_signals" \
       --arg now "$now" \
       '.signals = (.signals | sort_by(-.strength) | .[0:$keep]) | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    log "SIGNAL" "Pruned $pruned weakest signals (max=$max_signals, kept strongest $max_signals)"
}

# Returns signals with strength >= threshold as a JSON array.
# Args: threshold (float, e.g. 0.6)
# Outputs: JSON array of matching signal objects
_signal_get_strong() {
    if ! _signal_enabled; then return 1; fi
    local threshold="${1:?_signal_get_strong requires threshold}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    jq --argjson thr "$threshold" \
        '[.signals[] | select(.strength >= $thr)]' \
        "$signals_file"
}

# Returns signals matching the given type as a JSON array.
# Args: type (string, e.g. "attention_needed")
# Outputs: JSON array of matching signal objects
_signal_get_by_type() {
    if ! _signal_enabled; then return 1; fi
    local type="${1:?_signal_get_by_type requires type}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    jq --arg t "$type" \
        '[.signals[] | select(.type == $t)]' \
        "$signals_file"
}

# Returns all signals with strength > decay_floor as a JSON array.
# Outputs: JSON array of active signal objects
_signal_get_active() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    local decay_floor="${STIGMERGY_DECAY_FLOOR:-0.05}"

    jq --argjson floor "$decay_floor" \
        '[.signals[] | select(.strength >= $floor)]' \
        "$signals_file"
}

# Returns signals with no related garden ideas as a JSON array.
# Outputs: JSON array of unlinked signal objects
_signal_get_unlinked() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    jq '[.signals[] | select(.related_ideas | length == 0)]' \
        "$signals_file"
}

# Adds a garden idea ID to a signal's related_ideas array (dedup-safe).
# This is one half of the bidirectional link between signals and garden ideas.
#
# Args: signal_id idea_id
# Returns: 0 on success, 1 if signal not found or stigmergy disabled
_signal_link_idea() {
    if ! _signal_enabled; then return 1; fi
    local signal_id="${1:?_signal_link_idea requires signal_id}"
    local idea_id="${2:?_signal_link_idea requires idea_id}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 1

    # Check signal exists
    local exists
    exists=$(jq --arg id "$signal_id" '[.signals[] | select(.id == $id)] | length' "$signals_file")
    [ "$exists" -gt 0 ] || return 1

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Add idea_id to related_ideas if not already present (deduplicate)
    local tmp_file="${signals_file}.tmp"
    jq --arg sid "$signal_id" \
       --arg iid "$idea_id" \
       --arg now "$now" \
       '(.signals[] | select(.id == $sid)) |=
            (if (.related_ideas | index($iid)) then .
             else .related_ideas += [$iid]
             end)
        | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    log "SIGNAL" "Linked signal $signal_id -> idea $idea_id"
}

# Adds a signal ID to a garden idea's related_signals array (dedup-safe).
# This is one half of the bidirectional link between signals and garden ideas.
#
# Args: idea_id signal_id
# Returns: 0 on success, 1 if idea not found or garden disabled
_garden_link_signal() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_link_signal requires idea_id}"
    local signal_id="${2:?_garden_link_signal requires signal_id}"

    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    [ -f "$idea_file" ] || return 1

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Add signal_id to related_signals if not already present (deduplicate)
    local tmp_file="${idea_file}.tmp"
    jq --arg sid "$signal_id" \
       --arg now "$now" \
       'if (.related_signals | index($sid)) then .
        else .related_signals += [$sid] | .updated_at = $now
        end' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Linked idea $idea_id -> signal $signal_id"
}

# Creates a bidirectional link between a signal and a garden idea.
# Updates both the signal's related_ideas and the idea's related_signals.
#
# Args: signal_id idea_id
# Returns: 0 on success
_signal_garden_link() {
    local signal_id="${1:?_signal_garden_link requires signal_id}"
    local idea_id="${2:?_signal_garden_link requires idea_id}"

    _signal_link_idea "$signal_id" "$idea_id"
    _garden_link_signal "$idea_id" "$signal_id"
}

# ---------------------------------------------------------------------------
# Agent Quorum (spec-39)
# ---------------------------------------------------------------------------

# Parse raw voter output into a validated JSON vote object.
# Invalid or unparseable output is treated as an abstain vote with
# "Vote parsing failed" as the reasoning (spec-39 §4).
#
# Args: raw_output voter_name
# Outputs: valid JSON vote object to stdout
_quorum_parse_vote() {
    local raw_output="$1"
    local voter_name="${2:-unknown}"

    # Try to extract JSON from the raw output — the voter may emit
    # explanation text before/after the JSON object.
    local json_candidate
    json_candidate=$(echo "$raw_output" | sed -n '/{/,/}/p' | head -50)

    # Validate it's parseable JSON with required fields
    if [ -n "$json_candidate" ] && echo "$json_candidate" | jq -e '.vote' >/dev/null 2>&1; then
        local vote confidence reasoning risk_assessment conditions
        vote=$(echo "$json_candidate" | jq -r '.vote // "abstain"')
        confidence=$(echo "$json_candidate" | jq -r '.confidence // 0.5')
        reasoning=$(echo "$json_candidate" | jq -r '.reasoning // "No reasoning provided"')
        risk_assessment=$(echo "$json_candidate" | jq -r '.risk_assessment // "medium"')
        conditions=$(echo "$json_candidate" | jq -c '.conditions // []')

        # Validate vote value
        case "$vote" in
            approve|reject|abstain) ;;
            *) vote="abstain"; reasoning="Invalid vote value: $vote" ;;
        esac

        jq -n \
            --arg vote "$vote" \
            --arg confidence "$confidence" \
            --arg reasoning "$reasoning" \
            --arg risk "$risk_assessment" \
            --argjson conditions "$conditions" \
            '{
                vote: $vote,
                confidence: ($confidence | tonumber),
                reasoning: $reasoning,
                conditions: $conditions,
                risk_assessment: $risk
            }'
    else
        # Invalid output — return abstain (spec-39 §4)
        log "QUORUM" "WARN: voter=$voter_name produced invalid output, recording as abstain"
        jq -n \
            --arg voter "$voter_name" \
            '{
                vote: "abstain",
                confidence: 0.0,
                reasoning: "Vote parsing failed",
                conditions: [],
                risk_assessment: "medium"
            }'
    fi
}

# Invoke a single voter agent with a proposal and return the parsed vote.
# Uses the Claude CLI with the voter's agent definition file, Sonnet model,
# --print for text output, and --max-tokens limit. The voter is read-only
# (no tools) and produces a JSON vote.
#
# Args: voter_name proposal_json
# Outputs: parsed JSON vote object to stdout
# Returns: 0 on success (even if vote is abstain due to parse failure)
_quorum_invoke_voter() {
    local voter_name="${1:?_quorum_invoke_voter requires voter_name}"
    local proposal_json="${2:?_quorum_invoke_voter requires proposal_json}"

    local agent_file=".claude/agents/voter-${voter_name}.md"
    local model="${QUORUM_MODEL:-sonnet}"
    local max_tokens="${QUORUM_MAX_TOKENS_PER_VOTER:-500}"

    if [ ! -f "$agent_file" ]; then
        log "QUORUM" "ERROR: voter agent file not found: $agent_file"
        _quorum_parse_vote "" "$voter_name"
        return 0
    fi

    log "QUORUM" "Invoking voter: name=$voter_name model=$model max-tokens=$max_tokens"

    local raw_output=""
    local exit_code=0

    # Invoke claude CLI with:
    #   --agent: voter agent definition (contains perspective + output format)
    #   --model: cost-efficient model (default sonnet)
    #   --max-tokens: limit output length
    #   --print: simple text output (not stream-json)
    #   Proposal is piped via stdin
    local prompt
    printf -v prompt 'Evaluate this proposal:\n\n%s' "$proposal_json"
    raw_output=$(printf '%s' "$prompt" | claude --agent "$agent_file" \
        --model "$model" \
        --max-tokens "$max_tokens" \
        --print 2>&1) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        log "QUORUM" "WARN: voter=$voter_name exited with code $exit_code"
    fi

    log "QUORUM" "Voter $voter_name responded (${#raw_output} bytes)"

    # Parse and validate the vote output — expects JSON with "vote" field.
    # Invalid output is treated as abstain (spec-39 §4).
    local parsed_vote
    parsed_vote=$(_quorum_parse_vote "$raw_output" "$voter_name")
    echo "$parsed_vote"
}

# Tally votes from all voters and determine the quorum result.
# Counts approve/reject/abstain, reduces denominator for abstentions,
# compares approve count against threshold for the decision_type,
# and merges conditions from approving voters into the result.
#
# Args: votes_json decision_type
#   votes_json: JSON object mapping voter names to vote objects
#               e.g. {"conservative":{"vote":"approve","conditions":[...]}, ...}
#   decision_type: one of seed_promotion, bloom_implementation,
#                  constitutional_amendment, emergency_override
# Outputs: JSON tally result to stdout with approve, reject, abstain counts,
#          threshold, result (approved/rejected), and conditions_merged
_quorum_tally() {
    local votes_json="${1:?_quorum_tally requires votes_json}"
    local decision_type="${2:?_quorum_tally requires decision_type}"

    # Count votes by category
    local approve_count reject_count abstain_count total
    approve_count=$(echo "$votes_json" | jq '[.[] | select(.vote == "approve")] | length')
    reject_count=$(echo "$votes_json" | jq '[.[] | select(.vote == "reject")] | length')
    abstain_count=$(echo "$votes_json" | jq '[.[] | select(.vote == "abstain")] | length')
    total=$(echo "$votes_json" | jq 'length')

    # Reduce denominator for abstentions (spec-39 §3)
    local denominator=$(( total - abstain_count ))

    # Look up threshold for the decision type from config
    local threshold
    threshold=$(jq -r ".quorum.thresholds.${decision_type} // 3" "$CONFIG_FILE" 2>/dev/null || echo "3")

    # Determine result: approved if approve_count >= threshold,
    # but also handle edge case where denominator is 0 (all abstain)
    local result
    if [ "$denominator" -le 0 ]; then
        # All voters abstained — cannot reach any threshold
        result="rejected"
        log "QUORUM" "WARN: all voters abstained, decision_type=$decision_type — rejecting"
    elif [ "$approve_count" -ge "$threshold" ]; then
        result="approved"
    else
        result="rejected"
    fi

    # Merge conditions from all approving voters into a flat array
    local conditions_merged
    conditions_merged=$(echo "$votes_json" | jq '[.[] | select(.vote == "approve") | .conditions[]? // empty] | unique')

    log "QUORUM" "Tally: approve=$approve_count reject=$reject_count abstain=$abstain_count denominator=$denominator threshold=$threshold result=$result"

    # Return structured tally result
    jq -n \
        --argjson approve "$approve_count" \
        --argjson reject "$reject_count" \
        --argjson abstain "$abstain_count" \
        --argjson threshold "$threshold" \
        --arg result "$result" \
        --argjson conditions_merged "$conditions_merged" \
        '{
            approve: $approve,
            reject: $reject,
            abstain: $abstain,
            threshold: $threshold,
            result: $result,
            conditions_merged: $conditions_merged
        }'
}

# Check whether the quorum budget for the current cycle has been exceeded.
# Tracks cumulative quorum token usage and compares estimated cost against
# Check whether a bloom candidate idea is on rejection cooldown.
# Scans vote history in .automaton/votes/ for rejected votes matching the idea_id.
# If a rejection is found and fewer than rejection_cooldown_cycles votes have been
# recorded since then, the idea is considered on cooldown and should be skipped.
#
# Args:
#   $1 — idea_id: the garden idea ID to check
# Returns: 0 if idea is not on cooldown (can be evaluated), 1 if on cooldown (skip)
_quorum_check_cooldown() {
    local idea_id="${1:?_quorum_check_cooldown requires idea_id}"
    local cooldown_cycles="${QUORUM_REJECTION_COOLDOWN:-5}"
    local votes_dir="$AUTOMATON_DIR/votes"

    if [ ! -d "$votes_dir" ]; then
        return 0
    fi

    # Find the most recent rejection vote for this idea
    local rejection_vote_id=""
    local vote_files
    vote_files=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | sort -r)

    for vote_file in $vote_files; do
        local matched_idea matched_result
        matched_idea=$(jq -r '.idea_id // empty' "$vote_file" 2>/dev/null) || continue
        matched_result=$(jq -r '.tally.result // empty' "$vote_file" 2>/dev/null) || continue

        if [ "$matched_idea" = "$idea_id" ] && [ "$matched_result" = "rejected" ]; then
            rejection_vote_id=$(jq -r '.vote_id // empty' "$vote_file" 2>/dev/null) || true
            break
        fi
    done

    if [ -z "$rejection_vote_id" ]; then
        return 0
    fi

    # Count how many votes have been recorded after the rejection vote
    # Each vote roughly corresponds to one evaluation cycle
    local votes_since=0
    local past_rejection=false
    local all_vote_files
    all_vote_files=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | sort)

    for vote_file in $all_vote_files; do
        local vid
        vid=$(jq -r '.vote_id // empty' "$vote_file" 2>/dev/null) || continue
        if [ "$past_rejection" = "true" ]; then
            votes_since=$(( votes_since + 1 ))
        elif [ "$vid" = "$rejection_vote_id" ]; then
            past_rejection=true
        fi
    done

    if [ "$votes_since" -lt "$cooldown_cycles" ]; then
        log "QUORUM" "Idea $idea_id on cooldown: $votes_since cycles since rejection ($rejection_vote_id), need $cooldown_cycles"
        return 1
    fi

    return 0
}

# QUORUM_MAX_COST_PER_CYCLE. Uses a simple token-to-cost estimate based on
# Sonnet pricing (~$3/M input + $15/M output tokens, approximated as $0.01/1K tokens).
#
# Args:
#   $1 — tokens_used: cumulative tokens consumed by quorum voters this cycle
# Returns: 0 if budget remains, 1 if budget exceeded
_quorum_check_budget() {
    local tokens_used="${1:?_quorum_check_budget requires tokens_used}"
    local max_cost="${QUORUM_MAX_COST_PER_CYCLE:-1.00}"

    # Estimate cost: ~$0.01 per 1000 tokens (conservative Sonnet estimate)
    local estimated_cost
    estimated_cost=$(echo "$tokens_used $max_cost" | awk '{
        cost = $1 / 1000 * 0.01
        printf "%.4f", cost
    }')

    local exceeded
    exceeded=$(echo "$estimated_cost $max_cost" | awk '{print ($1 >= $2) ? "true" : "false"}')

    if [ "$exceeded" = "true" ]; then
        log "QUORUM" "Budget exceeded: ~\$${estimated_cost} used of \$${max_cost} max — skipping remaining candidates"
        return 1
    fi

    return 0
}

# Evaluate the highest-priority bloom candidate through the quorum.
# Selects the top bloom candidate from the garden, assembles proposal context
# (idea details, metrics, signals), invokes all configured voters sequentially,
# tallies votes, writes a vote record to .automaton/votes/vote-{NNN}.json,
# and advances (harvest) or wilts the idea based on the result.
#
# Args: none (reads bloom candidates from garden, voters from config)
# Returns: 0 on success (even if no candidates), 1 on error
# Outputs: vote record path to stdout if a vote was held
_quorum_evaluate_bloom() {
    if [ "${QUORUM_ENABLED:-true}" != "true" ]; then
        log "EVOLUTION" "Quorum disabled — bloom ideas auto-approved without voting"
        # Auto-approve all bloom candidates without voting (spec-39 §10)
        local disabled_candidates
        disabled_candidates=$(_garden_get_bloom_candidates 2>/dev/null) || true
        if [ -n "$disabled_candidates" ]; then
            while IFS= read -r auto_id; do
                [ -n "$auto_id" ] || continue
                log "QUORUM" "Auto-approving $auto_id (quorum disabled)"
                _garden_advance_stage "$auto_id" "harvest" "Auto-approved (quorum disabled)" "true"
            done <<< "$disabled_candidates"
        fi
        return 0
    fi

    # Get bloom candidates sorted by priority descending
    local candidates
    candidates=$(_garden_get_bloom_candidates 2>/dev/null) || true
    if [ -z "$candidates" ]; then
        log "QUORUM" "No bloom candidates to evaluate"
        return 0
    fi

    # Select highest-priority candidate (first line)
    local idea_id
    idea_id=$(echo "$candidates" | head -1)
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "QUORUM" "ERROR: idea file not found: $idea_file"
        return 1
    fi

    # Check rejection cooldown — skip ideas recently rejected by quorum
    if ! _quorum_check_cooldown "$idea_id"; then
        return 0
    fi

    # Check if quorum budget for this cycle has been exceeded
    if ! _quorum_check_budget "${_QUORUM_CYCLE_TOKENS:-0}"; then
        log "QUORUM" "Skipping bloom candidate $idea_id — quorum budget exceeded"
        return 0
    fi

    log "QUORUM" "Evaluating bloom candidate: $idea_id"

    # Assemble proposal context from idea details
    local proposal_json
    proposal_json=$(jq '{
        title: .title,
        description: .description,
        evidence_count: (.evidence | length),
        priority: (.priority // 0),
        complexity: (.estimated_complexity // "medium"),
        tags: (.tags // []),
        related_specs: (.related_specs // []),
        related_signals: (.related_signals // []),
        evidence: [.evidence[] | {type, observation, added_at}]
    }' "$idea_file")

    # Invoke all voters sequentially (spec-39: not parallel, to control costs)
    local all_votes="{}"
    local voter_list
    IFS=',' read -ra voter_list <<< "$QUORUM_VOTERS"

    local voter_tokens=0
    for voter_name in "${voter_list[@]}"; do
        voter_name=$(echo "$voter_name" | tr -d ' ')
        log "QUORUM" "Invoking voter: $voter_name for $idea_id"
        local vote_result
        vote_result=$(_quorum_invoke_voter "$voter_name" "$proposal_json")
        all_votes=$(echo "$all_votes" | jq --arg name "$voter_name" --argjson vote "$vote_result" '. + {($name): $vote}')
        # Estimate tokens per voter (input prompt + output tokens)
        voter_tokens=$(( voter_tokens + ${QUORUM_MAX_TOKENS_PER_VOTER:-500} ))
    done

    # Accumulate cycle-level quorum token usage
    _QUORUM_CYCLE_TOKENS=$(( ${_QUORUM_CYCLE_TOKENS:-0} + voter_tokens ))

    # Tally the votes using bloom_implementation threshold
    local tally_result
    tally_result=$(_quorum_tally "$all_votes" "bloom_implementation")

    local result
    result=$(echo "$tally_result" | jq -r '.result')

    # Determine next vote ID from existing vote files
    local votes_dir="$AUTOMATON_DIR/votes"
    mkdir -p "$votes_dir"
    local next_vote_id=1
    local latest_vote
    latest_vote=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | sort | tail -1)
    if [ -n "$latest_vote" ]; then
        next_vote_id=$(basename "$latest_vote" .json | sed 's/vote-//' | sed 's/^0*//' )
        next_vote_id=$(( next_vote_id + 1 ))
    fi
    local vote_id
    vote_id=$(printf "vote-%03d" "$next_vote_id")
    local vote_file="$votes_dir/${vote_id}.json"

    # Build the vote record
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg vote_id "$vote_id" \
        --arg idea_id "$idea_id" \
        --arg type "bloom_implementation" \
        --argjson proposal "$proposal_json" \
        --argjson votes "$all_votes" \
        --argjson tally "$tally_result" \
        --arg created_at "$now" \
        '{
            vote_id: $vote_id,
            idea_id: $idea_id,
            type: $type,
            proposal: $proposal,
            votes: $votes,
            tally: $tally,
            created_at: $created_at
        }' > "$vote_file"

    log "QUORUM" "Vote recorded: $vote_id result=$result for $idea_id"

    # Update idea with vote reference
    local tmp_file="${idea_file}.tmp"
    jq --arg vid "$vote_id" '.vote_id = $vid' "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    # Act on the result
    if [ "$result" = "approved" ]; then
        log "QUORUM" "APPROVED: $idea_id — advancing to harvest"
        _garden_advance_stage "$idea_id" "harvest" "Quorum approved ($vote_id)" "true"
    else
        log "QUORUM" "REJECTED: $idea_id — wilting"
        _garden_wilt "$idea_id" "Quorum rejected ($vote_id)"
    fi

    echo "$vote_file"
    return 0
}

# ---------------------------------------------------------------------------
# Growth Metrics (spec-43)
# ---------------------------------------------------------------------------

# Collects all 5 metric categories (capability, efficiency, quality,
# innovation, health) and appends a snapshot to evolution-metrics.json.
# Called at pre-cycle and post-cycle points in the evolution loop.
#
# Usage: _metrics_snapshot <cycle_id>
# Args:  cycle_id — the current evolution cycle number
_metrics_snapshot() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local cycle_id="${1:?_metrics_snapshot requires cycle_id}"
    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Initialize metrics file if it doesn't exist
    if [ ! -f "$metrics_file" ]; then
        echo '{"version":1,"snapshots":[],"baselines":{}}' > "$metrics_file"
    fi

    # --- Capability metrics ---
    local total_lines=0 total_functions=0 total_specs=0 total_tests=0
    local test_assertions=0 cli_flags=0 agent_definitions=0 skills=0 hooks=0

    if [ -f "${SCRIPT_PATH:-automaton.sh}" ]; then
        total_lines=$(wc -l < "${SCRIPT_PATH:-automaton.sh}" 2>/dev/null || true)
        total_functions=$(grep -c '^[a-z_]*()' "${SCRIPT_PATH:-automaton.sh}" 2>/dev/null || true)
        cli_flags=$(grep -c -- '--[a-z]' "${SCRIPT_PATH:-automaton.sh}" 2>/dev/null || true)
    fi
    if [ -d "${PROJECT_ROOT:-.}/specs" ]; then
        total_specs=$(find "${PROJECT_ROOT:-.}/specs" -name 'spec-*.md' 2>/dev/null | wc -l)
    fi
    if [ -d "${PROJECT_ROOT:-.}/tests" ]; then
        total_tests=$(find "${PROJECT_ROOT:-.}/tests" -name 'test_*.sh' -type f 2>/dev/null | wc -l)
        test_assertions=$(grep -r -c 'assert_' "${PROJECT_ROOT:-.}/tests/" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
    fi
    if [ -d "${PROJECT_ROOT:-.}/.claude/agents" ]; then
        agent_definitions=$(find "${PROJECT_ROOT:-.}/.claude/agents" -name '*.md' 2>/dev/null | wc -l)
    fi
    if [ -d "${PROJECT_ROOT:-.}/.claude/skills" ]; then
        skills=$(find "${PROJECT_ROOT:-.}/.claude/skills" -name '*.md' 2>/dev/null | wc -l)
    fi
    if [ -d "${PROJECT_ROOT:-.}/.claude/hooks" ]; then
        hooks=$(find "${PROJECT_ROOT:-.}/.claude/hooks" -name '*.sh' 2>/dev/null | wc -l)
    fi

    # --- Efficiency metrics ---
    local tokens_per_task=0 tokens_per_iteration=0 cache_hit_ratio="0.00"
    local stall_rate="0.00" prompt_overhead_ratio="0.00"
    local bootstrap_time_ms=0 avg_iteration_duration_s=0

    local budget_file="$AUTOMATON_DIR/budget.json"
    local state_file="$AUTOMATON_DIR/state.json"
    if [ -f "$budget_file" ]; then
        local total_input total_output total_tokens cache_read history_count
        total_input=$(jq '.used.total_input // 0' "$budget_file" 2>/dev/null || echo 0)
        total_output=$(jq '.used.total_output // 0' "$budget_file" 2>/dev/null || echo 0)
        total_tokens=$((total_input + total_output))
        cache_read=$(jq '.used.total_cache_read // 0' "$budget_file" 2>/dev/null || echo 0)
        history_count=$(jq '.history | length' "$budget_file" 2>/dev/null || echo 0)

        local tasks_completed
        tasks_completed=$(jq '[.history[] | select(.phase == "build" and .status == "success")] | length' "$budget_file" 2>/dev/null || echo 0)

        if [ "$tasks_completed" -gt 0 ]; then
            tokens_per_task=$((total_tokens / tasks_completed))
        fi
        if [ "$history_count" -gt 0 ]; then
            tokens_per_iteration=$((total_tokens / history_count))
            avg_iteration_duration_s=$(jq '[.history[].duration_seconds // 0] | add / length | floor' "$budget_file" 2>/dev/null || echo 0)
        fi
        if [ "$total_input" -gt 0 ]; then
            cache_hit_ratio=$(awk -v cr="$cache_read" -v ti="$total_input" 'BEGIN { printf "%.2f", cr/ti }')
        fi
    fi

    if [ -f "$state_file" ]; then
        local stall_count total_build_iters
        stall_count=$(jq '.stall_count // 0' "$state_file" 2>/dev/null || echo 0)
        total_build_iters=$(jq '[.history[] | select(.phase == "build")] | length' "$budget_file" 2>/dev/null || echo 0)
        if [ "$total_build_iters" -gt 0 ]; then
            stall_rate=$(awk -v s="$stall_count" -v t="$total_build_iters" 'BEGIN { printf "%.2f", s/t }')
        fi
    fi

    # --- Quality metrics ---
    local test_pass_rate="0.00" first_pass_success_rate="0.00"
    local rollback_count=0 syntax_errors_caught=0
    local review_rework_rate="0.00" constitution_violations=0

    local results_file="$AUTOMATON_DIR/test_results.json"
    if [ -f "$results_file" ]; then
        local passed failed
        passed=$(jq '.passed // 0' "$results_file" 2>/dev/null || echo 0)
        failed=$(jq '.failed // 0' "$results_file" 2>/dev/null || echo 0)
        local total_tests_run=$((passed + failed))
        if [ "$total_tests_run" -gt 0 ]; then
            test_pass_rate=$(awk -v p="$passed" -v t="$total_tests_run" 'BEGIN { printf "%.2f", p/t }')
        fi
    fi

    if [ -f "$state_file" ]; then
        local replan_count tasks_done
        replan_count=$(jq '.replan_count // 0' "$state_file" 2>/dev/null || echo 0)
        tasks_done=$(jq '[.history[] | select(.phase == "build" and .status == "success")] | length' "$budget_file" 2>/dev/null || echo 0)
        if [ "$tasks_done" -gt 0 ]; then
            local successful=$((tasks_done - replan_count))
            [ "$successful" -lt 0 ] && successful=0
            first_pass_success_rate=$(awk -v s="$successful" -v t="$tasks_done" 'BEGIN { printf "%.2f", s/t }')
            review_rework_rate=$(awk -v r="$replan_count" -v t="$tasks_done" 'BEGIN { printf "%.2f", r/t }')
        fi
    fi

    local mods_file="$AUTOMATON_DIR/self_modifications.json"
    if [ -f "$mods_file" ]; then
        rollback_count=$(jq '[.[] | select(.type == "rollback")] | length' "$mods_file" 2>/dev/null || echo 0)
        syntax_errors_caught=$(jq '[.[] | select(.type == "syntax_error")] | length' "$mods_file" 2>/dev/null || echo 0)
    fi

    # --- Innovation metrics ---
    local garden_seeds=0 garden_sprouts=0 garden_blooms=0
    local garden_harvested=0 garden_wilted=0
    local active_signals=0 quorum_votes_cast=0
    local ideas_implemented_total=0 cycles_since_last_harvest=0

    local garden_index="$AUTOMATON_DIR/garden/_index.json"
    if [ -f "$garden_index" ]; then
        garden_seeds=$(jq '.by_stage.seed // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_sprouts=$(jq '.by_stage.sprout // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_blooms=$(jq '.by_stage.bloom // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_harvested=$(jq '.by_stage.harvest // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_wilted=$(jq '.by_stage.wilt // 0' "$garden_index" 2>/dev/null || echo 0)
    fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ -f "$signals_file" ]; then
        active_signals=$(jq '[.signals[] | select(.strength > 0.05)] | length' "$signals_file" 2>/dev/null || echo 0)
    fi

    local votes_dir="$AUTOMATON_DIR/votes"
    if [ -d "$votes_dir" ]; then
        quorum_votes_cast=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | wc -l)
    fi

    ideas_implemented_total=$garden_harvested

    # cycles_since_last_harvest: scan existing snapshots for last harvest
    if [ -f "$metrics_file" ]; then
        local last_harvest_cycle
        last_harvest_cycle=$(jq '[.snapshots[] | select(.innovation.garden_harvested > 0)] | last | .cycle_id // 0' "$metrics_file" 2>/dev/null || echo 0)
        if [ "$last_harvest_cycle" -gt 0 ]; then
            cycles_since_last_harvest=$((cycle_id - last_harvest_cycle))
        else
            cycles_since_last_harvest=$cycle_id
        fi
    fi

    # --- Health indicators ---
    local budget_utilization="0.00" weekly_allowance_remaining="0.00"
    local convergence_risk="low" circuit_breaker_trips=0
    local consecutive_no_improvement=0 error_rate="0.00"
    local self_modification_count=0

    if [ -f "$budget_file" ]; then
        local cost_used cost_limit
        cost_used=$(jq '.used.estimated_cost_usd // 0' "$budget_file" 2>/dev/null || echo 0)
        cost_limit=$(jq '.limits.max_cost_usd // 50' "$budget_file" 2>/dev/null || echo 50)
        if [ "$(echo "$cost_limit" | awk '{print ($1 > 0)}')" = "1" ]; then
            budget_utilization=$(awk -v u="$cost_used" -v l="$cost_limit" 'BEGIN { printf "%.2f", u/l }')
        fi

        if [ "$(jq -r '.mode // "api"' "$budget_file" 2>/dev/null)" = "allowance" ]; then
            local tokens_remaining effective_allowance
            tokens_remaining=$(jq '.tokens_remaining // 0' "$budget_file" 2>/dev/null || echo 0)
            effective_allowance=$(jq '.limits.effective_allowance // 1' "$budget_file" 2>/dev/null || echo 1)
            weekly_allowance_remaining=$(awk -v r="$tokens_remaining" -v e="$effective_allowance" 'BEGIN { printf "%.2f", r/e }')
        fi
    fi

    if [ -f "$mods_file" ]; then
        self_modification_count=$(jq 'length' "$mods_file" 2>/dev/null || echo 0)
    fi

    local breakers_file="$AUTOMATON_DIR/evolution/circuit-breakers.json"
    if [ -f "$breakers_file" ]; then
        circuit_breaker_trips=$(jq '[.[] | select(.tripped == true)] | length' "$breakers_file" 2>/dev/null || echo 0)
    fi

    # consecutive_no_improvement from previous snapshots
    if [ -f "$metrics_file" ]; then
        consecutive_no_improvement=$(jq '.snapshots | last | .health.consecutive_no_improvement // 0' "$metrics_file" 2>/dev/null || echo 0)
    fi

    # convergence_risk based on consecutive_no_improvement
    if [ "$consecutive_no_improvement" -ge 5 ]; then
        convergence_risk="high"
    elif [ "$consecutive_no_improvement" -ge 3 ]; then
        convergence_risk="medium"
    fi

    # --- Build and append the snapshot ---
    local snapshot
    snapshot=$(jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson total_lines "$total_lines" \
        --argjson total_functions "$total_functions" \
        --argjson total_specs "$total_specs" \
        --argjson total_tests "$total_tests" \
        --argjson test_assertions "$test_assertions" \
        --argjson cli_flags "$cli_flags" \
        --argjson agent_definitions "$agent_definitions" \
        --argjson skills "$skills" \
        --argjson hooks "$hooks" \
        --argjson tokens_per_task "$tokens_per_task" \
        --argjson tokens_per_iteration "$tokens_per_iteration" \
        --arg cache_hit_ratio "$cache_hit_ratio" \
        --arg stall_rate "$stall_rate" \
        --arg prompt_overhead_ratio "$prompt_overhead_ratio" \
        --argjson bootstrap_time_ms "$bootstrap_time_ms" \
        --argjson avg_iteration_duration_s "$avg_iteration_duration_s" \
        --arg test_pass_rate "$test_pass_rate" \
        --arg first_pass_success_rate "$first_pass_success_rate" \
        --argjson rollback_count "$rollback_count" \
        --argjson syntax_errors_caught "$syntax_errors_caught" \
        --arg review_rework_rate "$review_rework_rate" \
        --argjson constitution_violations "$constitution_violations" \
        --argjson garden_seeds "$garden_seeds" \
        --argjson garden_sprouts "$garden_sprouts" \
        --argjson garden_blooms "$garden_blooms" \
        --argjson garden_harvested "$garden_harvested" \
        --argjson garden_wilted "$garden_wilted" \
        --argjson active_signals "$active_signals" \
        --argjson quorum_votes_cast "$quorum_votes_cast" \
        --argjson ideas_implemented_total "$ideas_implemented_total" \
        --argjson cycles_since_last_harvest "$cycles_since_last_harvest" \
        --arg budget_utilization "$budget_utilization" \
        --arg weekly_allowance_remaining "$weekly_allowance_remaining" \
        --arg convergence_risk "$convergence_risk" \
        --argjson circuit_breaker_trips "$circuit_breaker_trips" \
        --argjson consecutive_no_improvement "$consecutive_no_improvement" \
        --arg error_rate "$error_rate" \
        --argjson self_modification_count "$self_modification_count" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            capability: {
                total_lines: $total_lines,
                total_functions: $total_functions,
                total_specs: $total_specs,
                total_tests: $total_tests,
                test_assertions: $test_assertions,
                cli_flags: $cli_flags,
                agent_definitions: $agent_definitions,
                skills: $skills,
                hooks: $hooks
            },
            efficiency: {
                tokens_per_task: $tokens_per_task,
                tokens_per_iteration: $tokens_per_iteration,
                cache_hit_ratio: ($cache_hit_ratio | tonumber),
                stall_rate: ($stall_rate | tonumber),
                prompt_overhead_ratio: ($prompt_overhead_ratio | tonumber),
                bootstrap_time_ms: $bootstrap_time_ms,
                avg_iteration_duration_s: $avg_iteration_duration_s
            },
            quality: {
                test_pass_rate: ($test_pass_rate | tonumber),
                first_pass_success_rate: ($first_pass_success_rate | tonumber),
                rollback_count: $rollback_count,
                syntax_errors_caught: $syntax_errors_caught,
                review_rework_rate: ($review_rework_rate | tonumber),
                constitution_violations: $constitution_violations
            },
            innovation: {
                garden_seeds: $garden_seeds,
                garden_sprouts: $garden_sprouts,
                garden_blooms: $garden_blooms,
                garden_harvested: $garden_harvested,
                garden_wilted: $garden_wilted,
                active_signals: $active_signals,
                quorum_votes_cast: $quorum_votes_cast,
                ideas_implemented_total: $ideas_implemented_total,
                cycles_since_last_harvest: $cycles_since_last_harvest
            },
            health: {
                budget_utilization: ($budget_utilization | tonumber),
                weekly_allowance_remaining: ($weekly_allowance_remaining | tonumber),
                convergence_risk: $convergence_risk,
                circuit_breaker_trips: $circuit_breaker_trips,
                consecutive_no_improvement: $consecutive_no_improvement,
                error_rate: ($error_rate | tonumber),
                self_modification_count: $self_modification_count
            }
        }')

    # Append snapshot to metrics file atomically
    local tmp="${metrics_file}.tmp"
    jq --argjson snap "$snapshot" '.snapshots += [$snap]' "$metrics_file" > "$tmp" && mv "$tmp" "$metrics_file"

    # Enforce snapshot retention: prune oldest snapshots when count exceeds limit
    local retention="${METRICS_SNAPSHOT_RETENTION:-100}"
    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -gt "$retention" ]; then
        local excess=$((snap_count - retention))
        jq --argjson n "$excess" '.snapshots = .snapshots[$n:]' "$metrics_file" > "$tmp" && mv "$tmp" "$metrics_file"
        log "METRICS" "Pruned $excess oldest snapshot(s), retaining $retention"
    fi

    log "METRICS" "Snapshot recorded for cycle $cycle_id"
    echo "$metrics_file"
}

# Records the first snapshot's values as baselines in the metrics file.
# Baselines are set once and never updated automatically — they establish the
# reference point for all improvement/regression comparisons. If baselines
# already exist (non-empty object), this function is a no-op.
#
# Usage: _metrics_set_baselines
_metrics_set_baselines() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then return 0; fi

    # Check if baselines already exist (non-empty object)
    local existing
    existing=$(jq '.baselines // {}' "$metrics_file" 2>/dev/null)
    if [ -n "$existing" ] && [ "$existing" != "{}" ] && [ "$existing" != "null" ]; then
        return 0
    fi

    # Check if there are any snapshots to use
    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -eq 0 ]; then return 0; fi

    # Extract baselines from first snapshot
    local tmp="${metrics_file}.tmp"
    jq '.baselines = {
        capability: {
            total_lines: .snapshots[0].capability.total_lines,
            total_functions: .snapshots[0].capability.total_functions,
            total_specs: .snapshots[0].capability.total_specs,
            total_tests: .snapshots[0].capability.total_tests
        },
        efficiency: {
            tokens_per_task: .snapshots[0].efficiency.tokens_per_task,
            stall_rate: .snapshots[0].efficiency.stall_rate
        },
        quality: {
            test_pass_rate: .snapshots[0].quality.test_pass_rate,
            rollback_count: .snapshots[0].quality.rollback_count
        }
    }' "$metrics_file" > "$tmp" && mv "$tmp" "$metrics_file"

    log "METRICS" "Baselines recorded from first snapshot"
}

# Returns the most recent snapshot from evolution-metrics.json as JSON on stdout.
# Returns nothing if no snapshots exist or the metrics file is missing.
#
# Usage: latest=$(_metrics_get_latest)
_metrics_get_latest() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then return 0; fi

    local result
    result=$(jq '.snapshots | last // empty' "$metrics_file" 2>/dev/null)
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
    fi
}

# Analyzes trends across the last N snapshots. For each tracked metric computes
# direction (improving/degrading/stable), rate of change per cycle, and alert
# status when degrading for degradation_alert_threshold consecutive cycles.
# Returns a JSON array of trend observations.
#
# Usage: trends=$(_metrics_analyze_trends [window])
_metrics_analyze_trends() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then echo "[]"; return 0; fi

    local window="${1:-5}"
    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then echo "[]"; return 0; fi

    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -lt 2 ]; then echo "[]"; return 0; fi

    # Use jq to compute all trends in a single pass
    jq --argjson window "$window" '
        # Metrics config: [category, metric_name, higher_is_better]
        def tracked_metrics: [
            ["capability", "total_lines", true],
            ["capability", "total_functions", true],
            ["capability", "total_specs", true],
            ["capability", "total_tests", true],
            ["efficiency", "tokens_per_task", false],
            ["efficiency", "cache_hit_ratio", true],
            ["efficiency", "stall_rate", false],
            ["quality", "test_pass_rate", true],
            ["quality", "first_pass_success_rate", true],
            ["quality", "rollback_count", false],
            ["quality", "review_rework_rate", false],
            ["health", "error_rate", false]
        ];

        .snapshots[-$window:] as $snaps |
        .baselines as $baselines |

        if ($snaps | length) < 2 then []
        else
            [tracked_metrics[] | . as [$cat, $metric, $higher_better] |
                # Extract values for this metric from the window
                [$snaps[] | .[$cat][$metric] // 0] as $values |
                ($values | length) as $n |

                # First and last values in window
                $values[0] as $first |
                $values[$n - 1] as $last |

                # Rate of change: percentage change per cycle
                (if $first == 0 then
                    (if $last == 0 then 0 else 100 end)
                else
                    (($last - $first) / $first * 100 / ($n - 1))
                end) as $rate |

                # Check if stable relative to baseline (within 5%)
                ($baselines[$cat][$metric] // null) as $baseline |
                (if $baseline != null and $baseline != 0 then
                    ((($last - $baseline) / $baseline) | fabs) < 0.05
                else
                    false
                end) as $within_baseline |

                # Count consecutive degrading cycles from the end
                (reduce range($n - 1; 0; -1) as $i (
                    0;
                    if . >= 0 then
                        ($values[$i] - $values[$i - 1]) as $delta |
                        if ($higher_better and $delta < 0) or ($higher_better | not and $delta > 0) then
                            . + 1
                        else
                            -1  # stop counting
                        end
                    else .
                    end
                ) | if . < 0 then 0 else . end) as $consec_degrading |

                # Determine direction
                (if $within_baseline and ($rate | fabs) < 5 then
                    "stable"
                elif ($higher_better and $last > $first) or ($higher_better | not and $last < $first) then
                    "improving"
                elif ($higher_better and $last < $first) or ($higher_better | not and $last > $first) then
                    "degrading"
                else
                    "stable"
                end) as $direction |

                # Alert if degrading for 3+ consecutive cycles
                ($direction == "degrading" and $consec_degrading >= 3) as $alert |

                {
                    category: $cat,
                    metric: $metric,
                    direction: $direction,
                    rate: ($rate * 100 | round / 100),
                    alert: $alert,
                    current: $last,
                    baseline: ($baseline // null),
                    consecutive_degrading: $consec_degrading
                }
            ]
        end
    ' "$metrics_file"
}

# Compares two snapshots (pre-cycle and post-cycle) and computes per-metric
# deltas with direction indicators. Used by the OBSERVE phase to determine
# whether a cycle's implementation improved, degraded, or had no effect.
#
# Usage: result=$(_metrics_compare "$pre_snapshot" "$post_snapshot")
# Both arguments are JSON snapshot objects (not cycle IDs).
# Returns: JSON object with "deltas" array and "summary" counts.
_metrics_compare() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then
        echo '{"deltas":[],"summary":{"improved":0,"degraded":0,"unchanged":0}}'
        return 0
    fi

    local pre_snapshot="${1:?_metrics_compare requires pre_snapshot}"
    local post_snapshot="${2:?_metrics_compare requires post_snapshot}"

    jq -n --argjson pre "$pre_snapshot" --argjson post "$post_snapshot" '
        # Metrics config: [category, metric_name, higher_is_better]
        def tracked_metrics: [
            ["capability", "total_lines", true],
            ["capability", "total_functions", true],
            ["capability", "total_specs", true],
            ["capability", "total_tests", true],
            ["capability", "test_assertions", true],
            ["capability", "cli_flags", true],
            ["efficiency", "tokens_per_task", false],
            ["efficiency", "tokens_per_iteration", false],
            ["efficiency", "cache_hit_ratio", true],
            ["efficiency", "stall_rate", false],
            ["quality", "test_pass_rate", true],
            ["quality", "first_pass_success_rate", true],
            ["quality", "rollback_count", false],
            ["quality", "review_rework_rate", false],
            ["innovation", "garden_seeds", true],
            ["innovation", "garden_sprouts", true],
            ["innovation", "garden_blooms", true],
            ["innovation", "garden_harvested", true],
            ["innovation", "active_signals", true],
            ["health", "budget_utilization", false],
            ["health", "error_rate", false]
        ];

        [tracked_metrics[] | . as [$cat, $metric, $higher_better] |
            ($pre[$cat][$metric] // 0) as $before |
            ($post[$cat][$metric] // 0) as $after |
            ($after - $before) as $delta |

            # Percentage change (avoid division by zero)
            (if $before == 0 then
                (if $after == 0 then 0 else 100 end)
            else
                (($delta / $before) * 100 | round)
            end) as $pct |

            # Direction: did this metric improve, degrade, or stay unchanged?
            (if $delta == 0 then
                "unchanged"
            elif ($higher_better and $delta > 0) or ($higher_better | not and $delta < 0) then
                "improved"
            else
                "degraded"
            end) as $direction |

            {
                category: $cat,
                metric: $metric,
                before: $before,
                after: $after,
                delta: $delta,
                percent_change: $pct,
                direction: $direction
            }
        ] as $deltas |

        {
            deltas: $deltas,
            summary: {
                improved: ([$deltas[] | select(.direction == "improved")] | length),
                degraded: ([$deltas[] | select(.direction == "degraded")] | length),
                unchanged: ([$deltas[] | select(.direction == "unchanged")] | length)
            }
        }
    '
}

# Renders the terminal health dashboard showing all 5 metric categories with
# current/baseline/trend columns, bar charts for utilization metrics, and
# trend indicators. This is the primary human interface for understanding the
# system's quantitative state at a glance.
#
# Usage: _metrics_display_health
_metrics_display_health() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then
        echo "No metrics data available. Run an evolution cycle first."
        return 0
    fi

    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -eq 0 ]; then
        echo "No metrics snapshots found."
        return 0
    fi

    # Extract latest snapshot and baselines in a single jq call
    local data
    data=$(jq '{
        snap: .snapshots[-1],
        baselines: .baselines,
        snap_count: (.snapshots | length),
        prev: (if (.snapshots | length) >= 2 then .snapshots[-2] else null end)
    }' "$metrics_file" 2>/dev/null)

    local W=60  # dashboard width

    # Helper: format a number with commas
    _fmt_num() {
        local n="$1"
        if [ -z "$n" ] || [ "$n" = "null" ] || [ "$n" = "" ]; then echo ""; return; fi
        echo "$n" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta'
    }

    # Helper: compute trend string between prev and current values
    # Args: current baseline prev higher_is_better
    _trend_str() {
        local cur="$1" base="$2" prev="$3" hib="$4"
        if [ -z "$base" ] || [ "$base" = "null" ]; then
            echo "—"
            return
        fi
        # Percentage change from baseline
        local pct
        pct=$(awk -v c="$cur" -v b="$base" 'BEGIN {
            if (b == 0) { if (c == 0) print "0.0"; else print "100.0" }
            else printf "%.1f", ((c - b) / b) * 100
        }')
        local sign="+"
        if echo "$pct" | grep -q '^-'; then
            sign=""
        fi
        # Determine arrow and improvement marker
        local arrow="—" mark=""
        if [ "$prev" != "null" ] && [ -n "$prev" ]; then
            local cmp
            cmp=$(awk -v c="$cur" -v p="$prev" 'BEGIN { if (c > p) print "up"; else if (c < p) print "down"; else print "same" }')
            if [ "$cmp" = "up" ]; then
                arrow="▲"
                [ "$hib" = "true" ] && mark=" ✓"
                [ "$hib" = "false" ] && mark=""
            elif [ "$cmp" = "down" ]; then
                arrow="▼"
                [ "$hib" = "false" ] && mark=" ✓"
                [ "$hib" = "true" ] && mark=""
            fi
        fi
        if [ "$pct" = "0.0" ]; then
            echo "— stable"
        else
            echo "${arrow} ${sign}${pct}%${mark}"
        fi
    }

    # Helper: render a bar chart (width 10 chars)
    _bar() {
        local pct="$1"
        local filled
        filled=$(awk -v p="$pct" 'BEGIN { printf "%d", p / 10 }')
        local empty=$((10 - filled))
        local bar=""
        local i
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = 0; i < empty; i++)); do bar+="░"; done
        echo "$bar"
    }

    # Extract values from data using jq
    _val() { echo "$data" | jq -r "$1" 2>/dev/null; }

    # Print header
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                   AUTOMATON HEALTH                       ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║                                                          ║"

    # --- CAPABILITY ---
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "CAPABILITY" "Current" "Baseline" "Trend"

    local cap_lines cap_funcs cap_specs cap_tests
    cap_lines=$(_val '.snap.capability.total_lines')
    cap_funcs=$(_val '.snap.capability.total_functions')
    cap_specs=$(_val '.snap.capability.total_specs')
    cap_tests=$(_val '.snap.capability.total_tests')

    local bl_lines bl_funcs bl_specs bl_tests
    bl_lines=$(_val '.baselines.capability.total_lines // ""')
    bl_funcs=$(_val '.baselines.capability.total_functions // ""')
    bl_specs=$(_val '.baselines.capability.total_specs // ""')
    bl_tests=$(_val '.baselines.capability.total_tests // ""')

    local prev_lines prev_funcs prev_specs prev_tests
    prev_lines=$(_val '.prev.capability.total_lines // null')
    prev_funcs=$(_val '.prev.capability.total_functions // null')
    prev_specs=$(_val '.prev.capability.total_specs // null')
    prev_tests=$(_val '.prev.capability.total_tests // null')

    local tr
    tr=$(_trend_str "$cap_lines" "$bl_lines" "$prev_lines" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Lines of code" "$(_fmt_num "$cap_lines")" "$(_fmt_num "$bl_lines")" "$tr"
    tr=$(_trend_str "$cap_funcs" "$bl_funcs" "$prev_funcs" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Functions" "$(_fmt_num "$cap_funcs")" "$(_fmt_num "$bl_funcs")" "$tr"
    tr=$(_trend_str "$cap_specs" "$bl_specs" "$prev_specs" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Specs" "$(_fmt_num "$cap_specs")" "$(_fmt_num "$bl_specs")" "$tr"
    tr=$(_trend_str "$cap_tests" "$bl_tests" "$prev_tests" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Tests" "$(_fmt_num "$cap_tests")" "$(_fmt_num "$bl_tests")" "$tr"

    echo "║                                                          ║"

    # --- EFFICIENCY ---
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "EFFICIENCY" "Current" "Baseline" "Trend"

    local eff_tpt eff_stall eff_cache
    eff_tpt=$(_val '.snap.efficiency.tokens_per_task')
    eff_stall=$(_val '.snap.efficiency.stall_rate')
    eff_cache=$(_val '.snap.efficiency.cache_hit_ratio')

    local bl_tpt bl_stall
    bl_tpt=$(_val '.baselines.efficiency.tokens_per_task // ""')
    bl_stall=$(_val '.baselines.efficiency.stall_rate // ""')

    local prev_tpt prev_stall prev_cache
    prev_tpt=$(_val '.prev.efficiency.tokens_per_task // null')
    prev_stall=$(_val '.prev.efficiency.stall_rate // null')
    prev_cache=$(_val '.prev.efficiency.cache_hit_ratio // null')

    tr=$(_trend_str "$eff_tpt" "$bl_tpt" "$prev_tpt" "false")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Tokens/task" "$(_fmt_num "$eff_tpt")" "$(_fmt_num "$bl_tpt")" "$tr"
    tr=$(_trend_str "$eff_stall" "$bl_stall" "$prev_stall" "false")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Stall rate" "$eff_stall" "$bl_stall" "$tr"
    tr=$(_trend_str "$eff_cache" "" "$prev_cache" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Cache hit ratio" "$eff_cache" "" "$tr"

    echo "║                                                          ║"

    # --- QUALITY ---
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "QUALITY" "Current" "Baseline" "Trend"

    local qual_tpr qual_rollback
    qual_tpr=$(_val '.snap.quality.test_pass_rate')
    qual_rollback=$(_val '.snap.quality.rollback_count')

    local bl_tpr bl_rollback
    bl_tpr=$(_val '.baselines.quality.test_pass_rate // ""')
    bl_rollback=$(_val '.baselines.quality.rollback_count // ""')

    local prev_tpr prev_rollback
    prev_tpr=$(_val '.prev.quality.test_pass_rate // null')
    prev_rollback=$(_val '.prev.quality.rollback_count // null')

    tr=$(_trend_str "$qual_tpr" "$bl_tpr" "$prev_tpr" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Test pass rate" "$qual_tpr" "$bl_tpr" "$tr"
    tr=$(_trend_str "$qual_rollback" "$bl_rollback" "$prev_rollback" "false")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Rollbacks" "$qual_rollback" "$bl_rollback" "$tr"

    echo "║                                                          ║"

    # --- INNOVATION ---
    printf "║  %-16s %-39s  ║\n" "INNOVATION" "Current"

    local inn_seeds inn_sprouts inn_blooms inn_harvested inn_signals inn_strong
    inn_seeds=$(_val '.snap.innovation.garden_seeds')
    inn_sprouts=$(_val '.snap.innovation.garden_sprouts')
    inn_blooms=$(_val '.snap.innovation.garden_blooms')
    inn_harvested=$(_val '.snap.innovation.ideas_implemented_total')
    inn_signals=$(_val '.snap.innovation.active_signals')

    printf "║  Garden: %d seeds, %d sprouts, %d blooms%-17s  ║\n" \
        "$inn_seeds" "$inn_sprouts" "$inn_blooms" ""
    printf "║  Signals: %d active%-36s  ║\n" "$inn_signals" ""
    printf "║  Harvested: %d ideas total%-30s  ║\n" "$inn_harvested" ""

    echo "║                                                          ║"

    # --- HEALTH ---
    printf "║  %-16s %-39s  ║\n" "HEALTH" "Status"

    local h_budget h_weekly h_risk h_breakers h_cycles
    h_budget=$(_val '.snap.health.budget_utilization')
    h_weekly=$(_val '.snap.health.weekly_allowance_remaining')
    h_risk=$(_val '.snap.health.convergence_risk')
    h_breakers=$(_val '.snap.health.circuit_breaker_trips')
    h_cycles=$(_val '.snap.cycle_id')

    local budget_pct
    budget_pct=$(awk -v b="$h_budget" 'BEGIN { printf "%d", b * 100 }')
    local weekly_pct
    weekly_pct=$(awk -v w="$h_weekly" 'BEGIN { printf "%d", w * 100 }')

    printf "║  Budget utilization  %3d%% %s%-20s  ║\n" "$budget_pct" "$(_bar "$budget_pct")" ""
    printf "║  Weekly allowance    %3d%% remaining%-21s  ║\n" "$weekly_pct" ""
    printf "║  Convergence risk    %-35s  ║\n" "$(echo "$h_risk" | tr '[:lower:]' '[:upper:]')"
    printf "║  Circuit breakers    %d trips%-29s  ║\n" "$h_breakers" ""
    printf "║  Evolution cycles    %d completed%-25s  ║\n" "$h_cycles" ""

    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"

    local last_ts
    last_ts=$(_val '.snap.timestamp')
    echo "  Last snapshot: ${last_ts} (cycle ${h_cycles})"
}

# ---------------------------------------------------------------------------
# Human Interface — Display Functions (spec-44)
# ---------------------------------------------------------------------------

# Renders a formatted table of all non-wilted, non-harvested garden ideas
# sorted by stage (bloom first) then priority descending. Shows counts,
# bloom candidates, and guidance hints.
#
# Usage: _display_garden
_display_garden() {
    local garden_dir="$AUTOMATON_DIR/garden"

    if [ ! -d "$garden_dir" ]; then
        echo "No garden found. Use --plant \"idea\" to plant the first seed."
        return 0
    fi

    # Collect all idea files and extract relevant fields in a single pass
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

    if [ -z "$idea_files" ]; then
        echo "AUTOMATON GARDEN — 0 ideas"
        echo ""
        echo "The garden is empty. Use --plant \"idea\" to plant the first seed."
        return 0
    fi

    # Build a JSON array of non-wilted, non-harvested ideas with display fields
    local ideas_json="[]"
    local seed_count=0 sprout_count=0 bloom_count=0 total_active=0
    local now_epoch
    now_epoch=$(date +%s)

    for f in $idea_files; do
        [ -f "$f" ] || continue
        local stage
        stage=$(jq -r '.stage' "$f")

        # Skip wilted and harvested ideas
        [ "$stage" = "wilt" ] && continue
        [ "$stage" = "harvest" ] && continue

        total_active=$((total_active + 1))
        case "$stage" in
            seed)   seed_count=$((seed_count + 1)) ;;
            sprout) sprout_count=$((sprout_count + 1)) ;;
            bloom)  bloom_count=$((bloom_count + 1)) ;;
        esac

        # Extract fields for display
        local id title priority created_at
        id=$(jq -r '.id' "$f")
        title=$(jq -r '.title' "$f")
        priority=$(jq -r '.priority // 0' "$f")
        created_at=$(jq -r '.stage_history[0].entered_at // .updated_at' "$f")

        # Calculate age in days
        local age_days="?"
        if [ -n "$created_at" ] && [ "$created_at" != "null" ]; then
            local created_epoch
            created_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo "")
            if [ -n "$created_epoch" ]; then
                age_days=$(( (now_epoch - created_epoch) / 86400 ))
            fi
        fi

        # Stage sort order: bloom=0, sprout=1, seed=2
        local sort_order=2
        case "$stage" in
            bloom)  sort_order=0 ;;
            sprout) sort_order=1 ;;
            seed)   sort_order=2 ;;
        esac

        ideas_json=$(echo "$ideas_json" | jq \
            --arg id "$id" \
            --arg stage "$stage" \
            --argjson priority "$priority" \
            --arg title "$title" \
            --arg age "${age_days}d" \
            --argjson sort_order "$sort_order" \
            '. + [{"id": $id, "stage": $stage, "priority": $priority, "title": $title, "age": $age, "sort_order": $sort_order}]')
    done

    if [ "$total_active" -eq 0 ]; then
        echo "AUTOMATON GARDEN — 0 ideas"
        echo ""
        echo "The garden is empty. Use --plant \"idea\" to plant the first seed."
        return 0
    fi

    # Sort by stage order (bloom first) then priority descending
    ideas_json=$(echo "$ideas_json" | jq 'sort_by(.sort_order, -.priority)')

    # Print header
    local stage_summary=""
    [ "$seed_count" -gt 0 ] && stage_summary="${seed_count} seed"
    [ "$sprout_count" -gt 0 ] && { [ -n "$stage_summary" ] && stage_summary="$stage_summary, "; stage_summary="${stage_summary}${sprout_count} sprout"; }
    [ "$bloom_count" -gt 0 ] && { [ -n "$stage_summary" ] && stage_summary="$stage_summary, "; stage_summary="${stage_summary}${bloom_count} bloom"; }

    echo "AUTOMATON GARDEN — ${total_active} ideas (${stage_summary})"
    echo ""

    # Print table header
    printf " %-10s %-8s %4s  %-40s %s\n" "ID" "STAGE" "PRI" "TITLE" "AGE"

    # Print each idea row
    local row_count
    row_count=$(echo "$ideas_json" | jq 'length')
    local i=0
    while [ "$i" -lt "$row_count" ]; do
        local row_id row_stage row_pri row_title row_age
        row_id=$(echo "$ideas_json" | jq -r ".[$i].id")
        row_stage=$(echo "$ideas_json" | jq -r ".[$i].stage")
        row_pri=$(echo "$ideas_json" | jq -r ".[$i].priority")
        row_title=$(echo "$ideas_json" | jq -r ".[$i].title")
        row_age=$(echo "$ideas_json" | jq -r ".[$i].age")

        # Truncate title to 40 chars
        if [ "${#row_title}" -gt 40 ]; then
            row_title="${row_title:0:37}..."
        fi

        printf " %-10s %-8s %4s  %-40s %s\n" "$row_id" "$row_stage" "$row_pri" "$row_title" "$row_age"
        i=$((i + 1))
    done

    echo ""
    echo "Bloom candidates ready for quorum: ${bloom_count}"
    echo "Use --garden-detail ID for full details. Use --plant \"idea\" to add new seeds."
}

# ---------------------------------------------------------------------------
# Constitutional Principles (spec-40)
# ---------------------------------------------------------------------------

# Creates the default constitution at .automaton/constitution.md with 8 articles
# and initializes .automaton/constitution-history.json with empty amendments.
# Called on first --evolve run when constitution.md does not exist.
# Does not overwrite an existing constitution.
_constitution_create_default() {
    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    # Do not overwrite existing constitution
    if [ -f "$const_file" ]; then
        log "CONSTITUTION" "Constitution already exists at $const_file"
        return 0
    fi

    local ratified_date
    ratified_date=$(date -u +%Y-%m-%d)

    cat > "$const_file" << CONSTEOF
# Automaton Constitution
## Ratified: ${ratified_date}

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.
No evolution cycle may disable, weaken, or bypass:
- Self-build safety protocol (spec-22)
- Syntax validation gates
- Smoke test requirements
- Circuit breakers (spec-45)
- Budget enforcement (spec-23)

A modification that degrades safety must be rejected regardless of other benefits.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority over automaton's evolution.
- All evolution can be paused via \`--pause-evolution\` (spec-44)
- The human can override any quorum decision via \`--override\` (spec-44)
- The human can amend the constitution via \`--amend\` (spec-44)
- No autonomous action may remove or restrict human control mechanisms
- The evolution loop must halt if it cannot reach the human operator

### Article III: Measurable Progress
**Protection: supermajority**

Every implemented change must target a measurable improvement:
- Token efficiency (tokens per completed task)
- Quality (test pass rate, rollback rate)
- Capability (new specs, functions, or test coverage)
- Reliability (stall rate, error rate)

Changes that cannot be measured against at least one metric must not be implemented.
The OBSERVE phase (spec-41) must compare before/after metrics for every implementation.

### Article IV: Transparency
**Protection: supermajority**

All autonomous decisions must be fully auditable:
- Every quorum vote is recorded with reasoning (spec-39)
- Every garden idea has a traceable origin (spec-38)
- Every signal has observation history (spec-42)
- Every implementation records its branch, commits, and metric deltas
- The human can inspect any decision via \`--inspect\` (spec-44)

Hidden or obfuscated decision-making is a constitutional violation.

### Article V: Budget Discipline
**Protection: supermajority**

Evolution must operate within defined resource constraints:
- Each evolution cycle has a budget ceiling (spec-45)
- Quorum voting has per-cycle cost limits (spec-39)
- The evolution loop must halt when budget is exhausted, not proceed on debt
- Budget overruns in one cycle reduce the next cycle's allocation
- Weekly allowance limits (spec-23) apply to evolution cycles

### Article VI: Incremental Growth
**Protection: majority**

Evolution proceeds through small, reversible steps:
- Each cycle implements at most one idea
- Each implementation modifies at most \`self_build.max_files_per_iteration\` files (spec-22)
- Each implementation changes at most \`self_build.max_lines_changed_per_iteration\` lines (spec-22)
- Complex ideas must be decomposed into smaller sub-ideas before implementation
- The system prefers many small improvements over few large changes

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution:
- Test pass rate must remain >= the pre-evolution baseline
- New functionality must include corresponding tests
- Removing a test requires quorum approval as a separate decision
- The OBSERVE phase must run the full test suite after every implementation
- Test count may increase but must never decrease without explicit justification

### Article VIII: Amendment Protocol
**Protection: unanimous**

This constitution may be amended through the following process:
1. An amendment idea is planted in the garden (spec-38) with \`tags: ["constitutional"]\`
2. The idea progresses through normal lifecycle stages (seed -> sprout -> bloom)
3. At bloom, the quorum evaluates with \`constitutional_amendment\` threshold (4/5 supermajority)
4. If approved, the amendment is applied to constitution.md
5. The amendment is recorded in constitution-history.json with before/after text
6. Articles with \`unanimous\` protection cannot have their protection level reduced
7. This article (Article VIII) cannot be removed or modified to reduce amendment requirements
CONSTEOF

    log "CONSTITUTION" "Constitution ratified with 8 articles. Use --constitution to view, --amend to modify."

    # Initialize amendment history if it doesn't exist
    if [ ! -f "$hist_file" ]; then
        jq -n '{
            version: 1,
            amendments: [],
            current_version: 1
        }' > "$hist_file"
    fi
}

# Returns a JSON summary of the constitution for the bootstrap manifest.
# Output: { articles: N, version: N, key_constraints: [...] }
_constitution_get_summary() {
    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    if [ ! -f "$const_file" ]; then
        jq -n '{ articles: 0, version: 0, key_constraints: [] }'
        return 0
    fi

    local article_count
    article_count=$(grep -c '^### Article' "$const_file" || echo "0")

    local version=1
    if [ -f "$hist_file" ]; then
        version=$(jq -r '.current_version // 1' "$hist_file")
    fi

    jq -n \
        --argjson articles "$article_count" \
        --argjson version "$version" \
        '{
            articles: $articles,
            version: $version,
            key_constraints: [
                "Safety mechanisms must be preserved (Art. I)",
                "Human retains override authority (Art. II)",
                "Changes must target measurable metrics (Art. III)",
                "Each cycle implements at most 1 idea (Art. VI)"
            ]
        }'
}

# Validates a proposed diff against the constitution articles.
# Returns: "pass" (no violations), "warn" (non-blocking concerns), "fail" (blocks commit).
#
# Checks:
#   Article I  (Safety) — diff must not remove protected functions
#   Article II (Human Sovereignty) — diff must not remove human control CLI flags
#   Article III (Measurable Progress) — idea must have a metric target
#   Article VI (Incremental Growth) — files/lines within self_build limits
#   Article VII (Test Coverage) — diff must not remove tests
#
# Usage: result=$(_constitution_check "$diff_file" "$idea_id" "$cycle_id")
_constitution_check() {
    local diff_file="$1"
    local idea_id="$2"
    local cycle_id="$3"

    local const_file="$AUTOMATON_DIR/constitution.md"
    local result="pass"

    # If constitution doesn't exist, warn but don't block
    if [ ! -f "$const_file" ]; then
        log "CONSTITUTION" "WARNING: Constitution file not found, skipping compliance check"
        echo "warn"
        return 0
    fi

    local diff_content=""
    if [ -f "$diff_file" ] && [ -s "$diff_file" ]; then
        diff_content=$(cat "$diff_file")
    else
        # Empty diff — nothing to violate
        echo "pass"
        return 0
    fi

    # Extract removed lines (lines starting with -)
    local removed_lines
    removed_lines=$(echo "$diff_content" | grep '^-' | grep -v '^---' || true)

    # --- Check 1: Safety preservation (Article I) ---
    # Diff must not remove or modify protected functions
    IFS=',' read -ra protected_fns <<< "$SELF_BUILD_PROTECTED_FUNCTIONS"
    for fn in "${protected_fns[@]}"; do
        fn=$(echo "$fn" | xargs)  # trim whitespace
        if echo "$removed_lines" | grep -q "${fn}()"; then
            log "CONSTITUTION" "FAIL: Article I violation — protected function '$fn' removed"
            echo "fail"
            return 0
        fi
    done

    # --- Check 2: Human control preservation (Article II) ---
    # Diff must not remove CLI flags: --pause-evolution, --override, --amend
    local human_flags=("--pause-evolution" "--override" "--amend")
    for flag in "${human_flags[@]}"; do
        if echo "$removed_lines" | grep -q -- "$flag"; then
            log "CONSTITUTION" "FAIL: Article II violation — human control flag '$flag' removed"
            echo "fail"
            return 0
        fi
    done

    # --- Check 3: Measurability (Article III) ---
    # Idea must have at least one metric target in its description
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    if [ -f "$idea_file" ]; then
        local description
        description=$(jq -r '.description // ""' "$idea_file")
        # Look for metric-related keywords
        local metric_keywords="metric|token|efficiency|pass rate|coverage|rollback|error rate|stall|reliability|capability|quality|performance|latency|speed|reduce|increase|improve"
        if ! echo "$description" | grep -qiE "$metric_keywords"; then
            log "CONSTITUTION" "WARN: Article III concern — idea '$idea_id' has no measurable metric target"
            result="warn"
        fi
    fi

    # --- Check 4: Scope limits (Article VI) ---
    # Count files changed
    local files_changed
    files_changed=$(echo "$diff_content" | grep -c '^diff --git' || echo "0")
    if [ "$files_changed" -gt "$SELF_BUILD_MAX_FILES" ]; then
        log "CONSTITUTION" "WARN: Article VI concern — $files_changed files changed (limit: $SELF_BUILD_MAX_FILES)"
        result="warn"
    fi

    # Count lines changed (additions + deletions)
    local lines_added lines_removed lines_changed
    lines_added=$(echo "$diff_content" | grep -c '^+' | grep -v '^+++' || echo "0")
    lines_removed=$(echo "$diff_content" | grep -c '^-' | grep -v '^---' || echo "0")
    lines_changed=$((lines_added + lines_removed))
    if [ "$lines_changed" -gt "$SELF_BUILD_MAX_LINES" ]; then
        log "CONSTITUTION" "WARN: Article VI concern — $lines_changed lines changed (limit: $SELF_BUILD_MAX_LINES)"
        result="warn"
    fi

    # --- Check 5: Test coverage (Article VII) ---
    # If tests were removed, flag as warning
    if echo "$removed_lines" | grep -qE 'assert_equals|assert_contains|assert_file_exists|assert_exit_code|test_summary'; then
        log "CONSTITUTION" "WARN: Article VII concern — test assertions appear to be removed"
        result="warn"
    fi

    echo "$result"
}

# Validates that a proposed amendment does not violate immutable constraints.
# These constraints are enforced in code independently of the constitution text:
#   1. unanimous articles cannot have their protection level reduced
#   2. Article VIII cannot be removed or weakened
#
# Usage: _constitution_validate_amendment "VIII" "protection_change" "supermajority" ""
#   article:         Article number (I, II, III, IV, V, VI, VII, VIII)
#   amendment_type:  "modify", "remove", or "protection_change"
#   new_protection:  New protection level (only for protection_change)
#   new_text:        New article text (only for modify)
# Returns: 0 if allowed, 1 if blocked by immutable constraints
_constitution_validate_amendment() {
    local article="$1"
    local amendment_type="$2"
    local new_protection="${3:-}"
    local new_text="${4:-}"

    # Hardcoded immutable articles and their protection levels.
    # These are the articles that have "unanimous" protection and thus
    # cannot have their protection level reduced per spec-40 §2.
    local -A IMMUTABLE_ARTICLES=(
        ["I"]="unanimous"
        ["II"]="unanimous"
        ["VIII"]="unanimous"
    )

    # Protection level hierarchy for comparison (higher = stricter)
    local -A PROTECTION_RANK=(
        ["majority"]=1
        ["supermajority"]=2
        ["unanimous"]=3
    )

    # --- Constraint 1: Article VIII cannot be removed ---
    if [ "$article" = "VIII" ] && [ "$amendment_type" = "remove" ]; then
        log "CONSTITUTION" "BLOCKED: Article VIII cannot be removed (immutable constraint)"
        return 1
    fi

    # --- Constraint 2: Article VIII cannot be weakened ---
    if [ "$article" = "VIII" ] && [ "$amendment_type" = "modify" ] && [ -n "$new_text" ]; then
        # Check for weakening: text that reduces amendment threshold requirements
        # Weakening indicators: removing supermajority/4\/5 requirement, adding "simple majority", etc.
        local lower_text
        lower_text=$(echo "$new_text" | tr '[:upper:]' '[:lower:]')
        # If the new text mentions "simple majority" or "majority vote" without
        # "supermajority" or "4/5", it is weakening the amendment protocol
        if echo "$lower_text" | grep -qE 'simple majority|majority vote'; then
            if ! echo "$lower_text" | grep -qE 'supermajority|4/5|constitutional_amendment'; then
                log "CONSTITUTION" "BLOCKED: Article VIII cannot be weakened (immutable constraint)"
                return 1
            fi
        fi
    fi

    # --- Constraint 3: unanimous articles cannot have protection reduced ---
    if [ "$amendment_type" = "protection_change" ] && [ -n "$new_protection" ]; then
        local current_protection="${IMMUTABLE_ARTICLES[$article]:-}"
        if [ -n "$current_protection" ]; then
            local current_rank="${PROTECTION_RANK[$current_protection]:-0}"
            local new_rank="${PROTECTION_RANK[$new_protection]:-0}"
            if [ "$new_rank" -lt "$current_rank" ]; then
                log "CONSTITUTION" "BLOCKED: Article $article has '$current_protection' protection which cannot be reduced (immutable constraint)"
                return 1
            fi
        fi
    fi

    return 0
}

# Applies an approved amendment to constitution.md and records the change
# in constitution-history.json with a full audit trail.
#
# Usage: _constitution_amend "VI" "modify" "description" "new_text" "vote-001" "human"
#   article:         Article number (I, II, III, IV, V, VI, VII, VIII)
#   amendment_type:  "modify", "remove", or "protection_change"
#   description:     Human-readable description of the amendment
#   new_text:        New article body text (for modify) or new protection level (for protection_change)
#   vote_id:         ID of the quorum vote that approved this amendment
#   proposed_by:     Who proposed: "human" or "agent"
# Returns: 0 on success, 1 if blocked by immutable constraints
_constitution_amend() {
    local article="$1"
    local amendment_type="$2"
    local description="$3"
    local new_text="${4:-}"
    local vote_id="${5:-}"
    local proposed_by="${6:-agent}"

    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    if [ ! -f "$const_file" ]; then
        log "CONSTITUTION" "ERROR: Constitution file not found at $const_file"
        return 1
    fi

    # Validate against immutable constraints before proceeding
    local validate_protection=""
    local validate_text=""
    if [ "$amendment_type" = "protection_change" ]; then
        validate_protection="$new_text"
    elif [ "$amendment_type" = "modify" ]; then
        validate_text="$new_text"
    fi

    if ! _constitution_validate_amendment "$article" "$amendment_type" "$validate_protection" "$validate_text"; then
        return 1
    fi

    # Extract before-text for the article (everything between this article header and the next)
    local before_text
    before_text=$(awk -v art="### Article ${article}:" '
        $0 ~ art { found=1; next }
        found && /^### Article / { exit }
        found { print }
    ' "$const_file")

    # Apply the amendment to constitution.md
    case "$amendment_type" in
        modify)
            # Replace article body text (between this article header+protection line and the next article)
            local tmpfile
            tmpfile=$(mktemp)
            awk -v art="### Article ${article}:" -v newtext="$new_text" '
                $0 ~ art { print; in_article=1; next }
                in_article && /^\*\*Protection:/ { print; in_article=2; next }
                in_article == 2 && /^### Article / { print newtext; print ""; in_article=0; print; next }
                in_article == 2 && /^$/ && !printed_new { next }
                in_article == 2 { next }
                { print }
                END { if (in_article == 2) print newtext }
            ' "$const_file" > "$tmpfile"
            mv "$tmpfile" "$const_file"
            ;;
        protection_change)
            # Update the **Protection: level** line for the article
            local tmpfile
            tmpfile=$(mktemp)
            awk -v art="### Article ${article}:" -v newprot="$new_text" '
                $0 ~ art { print; in_article=1; next }
                in_article && /^\*\*Protection:/ { print "**Protection: " newprot "**"; in_article=0; next }
                { print }
            ' "$const_file" > "$tmpfile"
            mv "$tmpfile" "$const_file"
            ;;
        remove)
            # Remove the entire article section
            local tmpfile
            tmpfile=$(mktemp)
            awk -v art="### Article ${article}:" '
                $0 ~ art { skip=1; next }
                skip && /^### Article / { skip=0; print; next }
                skip { next }
                { print }
            ' "$const_file" > "$tmpfile"
            mv "$tmpfile" "$const_file"
            ;;
    esac

    # Initialize history file if missing
    if [ ! -f "$hist_file" ]; then
        jq -n '{version: 1, amendments: [], current_version: 1}' > "$hist_file"
    fi

    # Compute amendment_id from current amendment count
    local amendment_count
    amendment_count=$(jq '.amendments | length' "$hist_file")
    local amendment_id
    amendment_id=$(printf "amend-%03d" $((amendment_count + 1)))

    local approved_at
    approved_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Record in history
    local after_text="$new_text"
    jq --arg aid "$amendment_id" \
       --arg art "$article" \
       --arg atype "$amendment_type" \
       --arg desc "$description" \
       --arg before "$before_text" \
       --arg after "$after_text" \
       --arg vid "$vote_id" \
       --arg pby "$proposed_by" \
       --arg aat "$approved_at" \
       '.amendments += [{
           amendment_id: $aid,
           article: $art,
           type: $atype,
           description: $desc,
           before_text: $before,
           after_text: $after,
           vote_id: $vid,
           proposed_by: $pby,
           approved_at: $aat
       }] | .current_version += 1' "$hist_file" > "${hist_file}.tmp"
    mv "${hist_file}.tmp" "$hist_file"

    log "CONSTITUTION" "Amendment $amendment_id applied to Article $article ($amendment_type)"
}

# ---------------------------------------------------------------------------
# Safety: Branch Isolation (spec-45 §1)
# ---------------------------------------------------------------------------

# Global variable tracking the working branch before evolution branch creation.
# Set by _safety_branch_create(), used by merge/abandon to return.
WORKING_BRANCH=""

# Build the evolution branch name from cycle_id and idea_id.
# Usage: _safety_branch_get_name "001" "42"
# Output: automaton/evolve-001-42
_safety_branch_get_name() {
    local cycle_id="$1"
    local idea_id="$2"
    echo "automaton/evolve-${cycle_id}-${idea_id}"
}

# Create an evolution branch for the IMPLEMENT phase.
# Saves the current branch as WORKING_BRANCH, then creates and switches to
# a new branch named automaton/evolve-{cycle_id}-{idea_id}.
# Returns 0 on success, 1 on failure.
_safety_branch_create() {
    local cycle_id="$1"
    local idea_id="$2"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    # Save the current branch so merge/abandon can return to it
    WORKING_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

    # Refuse to nest evolution branches
    if _safety_branch_is_evolution; then
        log "SAFETY" "ERROR: Already on an evolution branch ($WORKING_BRANCH). Cannot nest."
        return 1
    fi

    if ! git checkout -b "$branch" 2>/dev/null; then
        log "SAFETY" "ERROR: Failed to create evolution branch $branch"
        return 1
    fi

    log "SAFETY" "Created evolution branch $branch (working branch: $WORKING_BRANCH)"
    return 0
}

# Merge the evolution branch back into the working branch.
# Switches to WORKING_BRANCH, merges the evolution branch, then returns.
# Returns 0 on success, 1 on merge failure.
_safety_branch_merge() {
    local cycle_id="$1"
    local idea_id="$2"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    if [ -z "$WORKING_BRANCH" ]; then
        log "SAFETY" "ERROR: No WORKING_BRANCH recorded — cannot merge"
        return 1
    fi

    # Switch back to the working branch
    if ! git checkout "$WORKING_BRANCH" 2>/dev/null; then
        log "SAFETY" "ERROR: Failed to switch to working branch $WORKING_BRANCH"
        return 1
    fi

    # Merge the evolution branch (fast-forward preferred, three-way if needed)
    if ! git merge "$branch" --no-edit 2>/dev/null; then
        log "SAFETY" "ERROR: Merge of $branch into $WORKING_BRANCH failed — resolve manually"
        return 1
    fi

    log "SAFETY" "Merged evolution branch $branch into $WORKING_BRANCH"
    return 0
}

# Abandon the evolution branch without merging.
# Switches back to WORKING_BRANCH and leaves the evolution branch intact
# for debugging — the branch is never deleted.
# Returns 0 on success, 1 on checkout failure.
_safety_branch_abandon() {
    local cycle_id="$1"
    local idea_id="$2"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    if [ -z "$WORKING_BRANCH" ]; then
        log "SAFETY" "ERROR: No WORKING_BRANCH recorded — cannot abandon"
        return 1
    fi

    # Switch back to working branch
    if ! git checkout "$WORKING_BRANCH" 2>/dev/null; then
        log "SAFETY" "ERROR: Failed to switch back to $WORKING_BRANCH during abandon"
        return 1
    fi

    # Do NOT delete the branch — preserved for debugging
    log "SAFETY" "Abandoned evolution branch $branch (preserved for debugging)"
    return 0
}

# Check whether the current branch is an evolution branch.
# Returns 0 if on an evolution branch, 1 otherwise.
_safety_branch_is_evolution() {
    local current
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [[ "$current" =~ ^automaton/evolve- ]]
}

# ---------------------------------------------------------------------------
# Safety: Sandbox Testing (spec-45 §2)
# ---------------------------------------------------------------------------

# Run the 4-step sandbox validation sequence on an evolution branch before
# merging: (1) syntax check, (2) smoke test, (3) full test suite, (4) test
# pass rate comparison against pre-cycle baseline. Also checks for protected
# function modifications.
#
# Usage: _safety_sandbox_test "automaton/evolve-001-42"
# Returns: 0 if all checks pass, 1 if any check fails
_safety_sandbox_test() {
    local branch="${1:-}"

    # Skip if sandbox testing is disabled
    if [ "${SAFETY_SANDBOX_TESTING_ENABLED:-true}" != "true" ]; then
        log "SAFETY" "Sandbox testing disabled — skipping validation"
        return 0
    fi

    log "SAFETY" "Starting sandbox validation on branch ${branch:-current}"

    # Step 1: Syntax check
    log "SAFETY" "Step 1/4: Syntax check (bash -n automaton.sh)"
    if ! bash -n automaton.sh 2>/dev/null; then
        log "SAFETY" "FAIL: Syntax check failed — automaton.sh has syntax errors"
        return 1
    fi
    log "SAFETY" "Step 1/4: Syntax check passed"

    # Step 2: Smoke test (--dry-run)
    log "SAFETY" "Step 2/4: Smoke test (--dry-run)"
    if ! ./automaton.sh --dry-run >/dev/null 2>&1; then
        log "SAFETY" "FAIL: Smoke test failed — automaton.sh --dry-run returned non-zero"
        return 1
    fi
    log "SAFETY" "Step 2/4: Smoke test passed"

    # Step 3: Full test suite
    log "SAFETY" "Step 3/4: Running full test suite"
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    for test_file in tests/test_*.sh; do
        [ -f "$test_file" ] || continue
        total_tests=$((total_tests + 1))
        if bash "$test_file" >/dev/null 2>&1; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
            log "SAFETY" "Test failed: $test_file"
        fi
    done

    local pass_rate="0.00"
    if [ "$total_tests" -gt 0 ]; then
        pass_rate=$(awk -v p="$passed_tests" -v t="$total_tests" 'BEGIN { printf "%.2f", p/t }')
    fi
    log "SAFETY" "Step 3/4: Test suite complete — $passed_tests/$total_tests passed (rate: $pass_rate)"

    # Step 4: Compare test pass rate against pre-cycle baseline
    log "SAFETY" "Step 4/4: Comparing pass rate against baseline"
    local baseline_snapshot
    baseline_snapshot=$(_metrics_get_latest 2>/dev/null || echo "")

    if [ -n "$baseline_snapshot" ] && [ "$baseline_snapshot" != "null" ]; then
        local baseline_rate
        baseline_rate=$(echo "$baseline_snapshot" | jq -r '.quality.test_pass_rate // 0' 2>/dev/null || echo "0")

        if [ -n "$baseline_rate" ] && [ "$baseline_rate" != "0" ] && [ "$baseline_rate" != "null" ]; then
            local is_regression
            is_regression=$(awk -v current="$pass_rate" -v baseline="$baseline_rate" \
                'BEGIN { print (current < baseline) ? "1" : "0" }')
            if [ "$is_regression" = "1" ]; then
                log "SAFETY" "FAIL: Test regression detected — pass rate $pass_rate < baseline $baseline_rate"
                return 1
            fi
        fi
    fi
    log "SAFETY" "Step 4/4: Pass rate check passed"

    # Step 5: Check for protected function modifications
    if [ -n "$branch" ]; then
        local working="${WORKING_BRANCH:-master}"
        IFS=',' read -ra protected <<< "${SELF_BUILD_PROTECTED_FUNCTIONS:-run_orchestration,_handle_shutdown}"
        for func in "${protected[@]}"; do
            local changes
            changes=$(git diff "${working}...${branch}" -- automaton.sh 2>/dev/null | grep -c "^[-+].*${func}()" || true)
            if [ "${changes:-0}" -gt 0 ]; then
                log "SAFETY" "FAIL: Protected function '${func}' modified without explicit approval"
                return 1
            fi
        done
        log "SAFETY" "Protected function check passed"
    fi

    log "SAFETY" "Sandbox validation passed — all checks successful"
    return 0
}

# ---------------------------------------------------------------------------
# Safety: Circuit Breakers (spec-45 §2)
# ---------------------------------------------------------------------------

# Path to the circuit breakers state file (ephemeral, resets each evolution run).
_BREAKERS_FILE="${AUTOMATON_DIR:-.automaton}/evolution/circuit-breakers.json"

# Initialize the circuit breakers state file with all 5 breakers in un-tripped state.
# Called by _safety_reset_breakers and on first access when the file does not exist.
_safety_init_breakers_file() {
    local dir
    dir="$(dirname "$_BREAKERS_FILE")"
    mkdir -p "$dir"
    cat > "$_BREAKERS_FILE" <<'BREAKERS_EOF'
{
  "budget_ceiling": { "tripped": false, "trip_count": 0, "last_trip": null },
  "error_cascade": { "tripped": false, "consecutive_failures": 0, "last_trip": null },
  "regression_cascade": { "tripped": false, "consecutive_regressions": 0, "last_trip": null },
  "complexity_ceiling": { "tripped": false, "trip_count": 0, "last_trip": null },
  "test_degradation": { "tripped": false, "trip_count": 0, "last_trip": null }
}
BREAKERS_EOF
}

# Ensure the breakers file exists, creating it with defaults if needed.
_safety_ensure_breakers_file() {
    if [ ! -f "$_BREAKERS_FILE" ]; then
        _safety_init_breakers_file
    fi
}

# Check all 5 circuit breakers against current system state and trip any that
# exceed their thresholds. This is called during evolution cycles to detect
# safety violations proactively.
#
# Breakers checked:
#   1. budget_ceiling   — evolution cycle cost exceeds max_cost_per_cycle_usd
#   2. error_cascade    — consecutive_failures >= SAFETY_MAX_CONSECUTIVE_FAILURES
#   3. regression_cascade — consecutive_regressions >= SAFETY_MAX_CONSECUTIVE_REGRESSIONS
#   4. complexity_ceiling — automaton.sh lines > SAFETY_MAX_TOTAL_LINES or
#                           function count > SAFETY_MAX_TOTAL_FUNCTIONS
#   5. test_degradation — test pass rate < SAFETY_MIN_TEST_PASS_RATE
#
# Returns: 0 always (tripped breakers are recorded in state, use
#          _safety_any_breaker_tripped to check)
_safety_check_breakers() {
    _safety_ensure_breakers_file

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # --- 1. Budget ceiling ---
    # Budget ceiling is checked externally by _evolve_check_budget (spec-41).
    # Here we just read the state — it is tripped by _safety_update_breaker.

    # --- 2. Error cascade ---
    local consecutive_failures
    consecutive_failures=$(jq -r '.error_cascade.consecutive_failures // 0' "$_BREAKERS_FILE")
    if [ "$consecutive_failures" -ge "${SAFETY_MAX_CONSECUTIVE_FAILURES:-3}" ]; then
        jq --arg ts "$now" '.error_cascade.tripped = true | .error_cascade.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: error_cascade ($consecutive_failures consecutive failures)"
    fi

    # --- 3. Regression cascade ---
    local consecutive_regressions
    consecutive_regressions=$(jq -r '.regression_cascade.consecutive_regressions // 0' "$_BREAKERS_FILE")
    if [ "$consecutive_regressions" -ge "${SAFETY_MAX_CONSECUTIVE_REGRESSIONS:-2}" ]; then
        jq --arg ts "$now" '.regression_cascade.tripped = true | .regression_cascade.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: regression_cascade ($consecutive_regressions consecutive regressions)"
    fi

    # --- 4. Complexity ceiling ---
    local total_lines=0 total_functions=0
    if [ -f "automaton.sh" ]; then
        total_lines=$(wc -l < automaton.sh)
        total_functions=$(grep -c '^[a-zA-Z_][a-zA-Z0-9_]*()' automaton.sh || true)
    fi
    if [ "$total_lines" -gt "${SAFETY_MAX_TOTAL_LINES:-15000}" ] || \
       [ "$total_functions" -gt "${SAFETY_MAX_TOTAL_FUNCTIONS:-300}" ]; then
        jq --arg ts "$now" \
            '.complexity_ceiling.tripped = true | .complexity_ceiling.trip_count += 1 | .complexity_ceiling.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: complexity_ceiling (lines=$total_lines, functions=$total_functions)"
    fi

    # --- 5. Test degradation ---
    local pass_rate="1.00"
    local latest_snapshot
    latest_snapshot=$(_metrics_get_latest 2>/dev/null || echo "")
    if [ -n "$latest_snapshot" ] && [ "$latest_snapshot" != "null" ]; then
        pass_rate=$(echo "$latest_snapshot" | jq -r '.quality.test_pass_rate // 1.0' 2>/dev/null || echo "1.00")
    fi
    local is_degraded
    is_degraded=$(awk -v rate="$pass_rate" -v min="${SAFETY_MIN_TEST_PASS_RATE:-0.80}" \
        'BEGIN { print (rate < min) ? "1" : "0" }')
    if [ "$is_degraded" = "1" ]; then
        jq --arg ts "$now" \
            '.test_degradation.tripped = true | .test_degradation.trip_count += 1 | .test_degradation.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: test_degradation (pass_rate=$pass_rate < min=${SAFETY_MIN_TEST_PASS_RATE:-0.80})"
    fi

    return 0
}

# Update a specific circuit breaker after an event (phase failure, regression,
# budget exceeded). Increments the appropriate counter and trips the breaker
# if the threshold is reached.
#
# Usage: _safety_update_breaker "error_cascade"
#        _safety_update_breaker "regression_cascade"
#        _safety_update_breaker "budget_ceiling"
#        _safety_update_breaker "complexity_ceiling"
#        _safety_update_breaker "test_degradation"
# Returns: 0 on success, 1 on unknown breaker name
_safety_update_breaker() {
    local breaker_name="$1"
    _safety_ensure_breakers_file

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    case "$breaker_name" in
        budget_ceiling)
            jq --arg ts "$now" \
                '.budget_ceiling.tripped = true | .budget_ceiling.trip_count += 1 | .budget_ceiling.last_trip = $ts' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            log "SAFETY" "BREAKER TRIPPED: budget_ceiling"
            ;;
        error_cascade)
            jq --arg ts "$now" \
                '.error_cascade.consecutive_failures += 1' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            # Check if threshold reached
            local failures
            failures=$(jq -r '.error_cascade.consecutive_failures' "$_BREAKERS_FILE")
            if [ "$failures" -ge "${SAFETY_MAX_CONSECUTIVE_FAILURES:-3}" ]; then
                jq --arg ts "$now" \
                    '.error_cascade.tripped = true | .error_cascade.last_trip = $ts' \
                    "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
                log "SAFETY" "BREAKER TRIPPED: error_cascade ($failures consecutive failures)"
            else
                log "SAFETY" "error_cascade: $failures consecutive failures (threshold: ${SAFETY_MAX_CONSECUTIVE_FAILURES:-3})"
            fi
            ;;
        regression_cascade)
            jq --arg ts "$now" \
                '.regression_cascade.consecutive_regressions += 1' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            # Check if threshold reached
            local regressions
            regressions=$(jq -r '.regression_cascade.consecutive_regressions' "$_BREAKERS_FILE")
            if [ "$regressions" -ge "${SAFETY_MAX_CONSECUTIVE_REGRESSIONS:-2}" ]; then
                jq --arg ts "$now" \
                    '.regression_cascade.tripped = true | .regression_cascade.last_trip = $ts' \
                    "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
                log "SAFETY" "BREAKER TRIPPED: regression_cascade ($regressions consecutive regressions)"
            else
                log "SAFETY" "regression_cascade: $regressions consecutive regressions (threshold: ${SAFETY_MAX_CONSECUTIVE_REGRESSIONS:-2})"
            fi
            ;;
        complexity_ceiling)
            jq --arg ts "$now" \
                '.complexity_ceiling.tripped = true | .complexity_ceiling.trip_count += 1 | .complexity_ceiling.last_trip = $ts' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            log "SAFETY" "BREAKER TRIPPED: complexity_ceiling"
            ;;
        test_degradation)
            jq --arg ts "$now" \
                '.test_degradation.tripped = true | .test_degradation.trip_count += 1 | .test_degradation.last_trip = $ts' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            log "SAFETY" "BREAKER TRIPPED: test_degradation"
            ;;
        *)
            log "SAFETY" "ERROR: Unknown breaker name: $breaker_name"
            return 1
            ;;
    esac
    return 0
}

# Check if any circuit breaker is currently tripped.
# Returns: 0 if at least one breaker is tripped, 1 if none are tripped
_safety_any_breaker_tripped() {
    _safety_ensure_breakers_file

    local tripped_count
    tripped_count=$(jq '[.[] | select(.tripped == true)] | length' "$_BREAKERS_FILE" 2>/dev/null || echo 0)
    [ "$tripped_count" -gt 0 ]
}

# Reset all circuit breakers to un-tripped state with zero counters.
# Called on fresh --evolve start or with --evolve --reset-breakers.
_safety_reset_breakers() {
    _safety_init_breakers_file
    log "SAFETY" "All circuit breakers reset"
}

# ---------------------------------------------------------------------------
# Rollback Protocol (spec-45 §4)
# ---------------------------------------------------------------------------

# Execute the rollback protocol when OBSERVE detects regression or a circuit
# breaker trips during IMPLEMENT. This is the recovery mechanism — it ensures
# every failure is recorded, signaled, and learned from while leaving the
# codebase untouched.
#
# Steps:
#   1. Switch back to the working branch (abandon evolution branch)
#   2. Preserve the failed evolution branch for debugging (never delete)
#   3. Wilt the responsible idea so it is not re-attempted without new evidence
#   4. Emit a quality_concern signal for future cycles to learn from
#   5. Log the rollback event to self_modifications.json (audit trail)
#   6. Increment regression_cascade circuit breaker counter
#
# Args: cycle_id idea_id reason
# Returns: 0 on success, 1 if branch abandon fails
_safety_rollback() {
    local cycle_id="${1:?_safety_rollback requires cycle_id}"
    local idea_id="${2:?_safety_rollback requires idea_id}"
    local reason="${3:?_safety_rollback requires reason}"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    log "SAFETY" "Rollback initiated: cycle=$cycle_id idea=$idea_id reason=$reason"

    # 1. Switch back to working branch (preserves evolution branch for debugging)
    if ! _safety_branch_abandon "$cycle_id" "$idea_id"; then
        log "SAFETY" "Rollback: WARNING — failed to abandon branch $branch"
        return 1
    fi

    # 2. Branch preserved by _safety_branch_abandon (it never deletes)
    log "SAFETY" "Rollback: branch $branch preserved for debugging"

    # 3. Wilt the responsible idea
    _garden_wilt "$idea_id" "Rollback: $reason" 2>/dev/null || true

    # 4. Emit quality_concern signal
    _signal_emit "quality_concern" \
        "Implementation of idea-${idea_id} caused regression" \
        "Rollback triggered: $reason" \
        "safety" "$cycle_id" "" 2>/dev/null || true

    # 5. Record in self_modifications.json (audit trail)
    local audit_file="$AUTOMATON_DIR/self_modifications.json"
    [ -f "$audit_file" ] || echo '[]' > "$audit_file"
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$now" --arg cid "$cycle_id" --arg iid "$idea_id" \
       --arg rsn "$reason" --arg br "$branch" \
       '. + [{timestamp:$ts, action:"rollback", cycle_id:$cid, idea_id:$iid, reason:$rsn, branch:$br}]' \
       "$audit_file" > "${audit_file}.tmp" && mv "${audit_file}.tmp" "$audit_file"

    # 6. Increment circuit breaker counters (regression_cascade)
    _safety_update_breaker "regression_cascade"

    log "SAFETY" "Rollback complete: cycle=$cycle_id idea=$idea_id"
    return 0
}

# ---------------------------------------------------------------------------
# Pre-Evolution Safety Preflight (spec-45 §6)
# ---------------------------------------------------------------------------

# Validates all preconditions before the first evolution cycle begins.
# Checks: clean working tree, test pass rate above minimum, constitution
# exists or can be created, sufficient budget for at least one cycle, and
# no tripped circuit breakers.
#
# Returns: 0 if all checks pass, 1 if any check fails
_safety_preflight() {
    # Skip if preflight is disabled
    if [ "${SAFETY_PREFLIGHT_ENABLED:-true}" != "true" ]; then
        log "SAFETY" "Preflight check disabled — skipping"
        return 0
    fi

    log "SAFETY" "Starting pre-evolution safety preflight"

    # 1. Verify clean working tree (no uncommitted changes)
    if ! git diff --quiet HEAD 2>/dev/null; then
        log "SAFETY" "PREFLIGHT FAIL: Working tree has uncommitted changes. Commit or stash before --evolve."
        return 1
    fi
    log "SAFETY" "Preflight 1/5: Clean working tree — passed"

    # 2. Verify test suite passes on current working branch
    local total_tests=0
    local passed_tests=0

    for test_file in tests/test_*.sh; do
        [ -f "$test_file" ] || continue
        total_tests=$((total_tests + 1))
        if bash "$test_file" >/dev/null 2>&1; then
            passed_tests=$((passed_tests + 1))
        fi
    done

    local pass_rate="0.00"
    if [ "$total_tests" -gt 0 ]; then
        pass_rate=$(awk -v p="$passed_tests" -v t="$total_tests" 'BEGIN { printf "%.2f", p/t }')
    fi

    local min_rate="${SAFETY_MIN_TEST_PASS_RATE:-0.80}"
    local below_min
    below_min=$(awk -v rate="$pass_rate" -v min="$min_rate" 'BEGIN { print (rate < min) ? "1" : "0" }')
    if [ "$below_min" = "1" ]; then
        log "SAFETY" "PREFLIGHT FAIL: Test pass rate $pass_rate below minimum $min_rate. Fix tests before evolving."
        return 1
    fi
    log "SAFETY" "Preflight 2/5: Test pass rate $pass_rate >= $min_rate — passed"

    # 3. Verify constitution exists or can be created
    local constitution_file="$AUTOMATON_DIR/constitution.md"
    if [ ! -f "$constitution_file" ]; then
        log "SAFETY" "Preflight 3/5: Constitution not found — will be created during first cycle"
    else
        log "SAFETY" "Preflight 3/5: Constitution exists — passed"
    fi

    # 4. Verify budget is sufficient for at least one cycle
    local budget_file="$AUTOMATON_DIR/budget.json"
    local budget_remaining="999.00"
    if [ -f "$budget_file" ]; then
        budget_remaining=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
            "$budget_file" 2>/dev/null || echo "999.00")
    fi
    local min_cycle_cost="1.00"
    local budget_insufficient
    budget_insufficient=$(awk -v rem="$budget_remaining" -v min="$min_cycle_cost" \
        'BEGIN { print (rem < min) ? "1" : "0" }')
    if [ "$budget_insufficient" = "1" ]; then
        log "SAFETY" "PREFLIGHT FAIL: Insufficient budget (\$${budget_remaining} USD) for evolution cycle (minimum \$${min_cycle_cost})."
        return 1
    fi
    log "SAFETY" "Preflight 4/5: Budget \$${budget_remaining} sufficient — passed"

    # 5. Check no circuit breakers are tripped
    if _safety_any_breaker_tripped; then
        log "SAFETY" "PREFLIGHT FAIL: Circuit breaker tripped. Reset with --evolve --reset-breakers or investigate."
        return 1
    fi
    log "SAFETY" "Preflight 5/5: No circuit breakers tripped — passed"

    log "SAFETY" "Pre-evolution safety preflight complete — all checks passed"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution Phase: REFLECT (spec-41 §3)
# ---------------------------------------------------------------------------

# Analyzes automaton's current state to identify what needs attention.
# Processes metrics trends to emit signals and auto-seed garden ideas from
# metric threshold breaches and strong unlinked signals. Prunes expired
# garden items and decays all signals. Writes reflect.json to the cycle dir.
#
# Args: cycle_id
# Returns: 0 on success, 1 on failure
_evolve_reflect() {
    local cycle_id="${1:?_evolve_reflect requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "REFLECT phase starting (cycle=$cycle_id)"

    local signals_emitted=0
    local ideas_seeded=0
    local ideas_pruned=0
    local signals_decayed=0
    local metric_alerts="[]"

    # 1. Analyze metric trends
    local trends
    trends=$(_metrics_analyze_trends "${METRICS_TREND_WINDOW:-5}")

    # Extract degrading metrics with alerts
    metric_alerts=$(echo "$trends" | jq '[.[] | select(.alert == true)]' 2>/dev/null || echo "[]")
    local alert_count
    alert_count=$(echo "$metric_alerts" | jq 'length' 2>/dev/null || echo 0)

    if [ "$alert_count" -gt 0 ]; then
        log "EVOLVE" "REFLECT: $alert_count metric alerts detected"
    fi

    # 2. Emit signals for degrading metrics
    local i=0
    while [ "$i" -lt "$alert_count" ]; do
        local metric_name metric_dir consec_deg category
        metric_name=$(echo "$metric_alerts" | jq -r ".[$i].metric")
        metric_dir=$(echo "$metric_alerts" | jq -r ".[$i].direction")
        consec_deg=$(echo "$metric_alerts" | jq -r ".[$i].consecutive_degrading")
        category=$(echo "$metric_alerts" | jq -r ".[$i].category")

        _signal_emit "attention_needed" \
            "Degrading metric: $metric_name" \
            "$metric_name has been $metric_dir for $consec_deg consecutive cycles (category: $category)" \
            "evolve-reflect" "$cycle_id" \
            "metric=$metric_name,direction=$metric_dir,consecutive=$consec_deg" \
            && signals_emitted=$((signals_emitted + 1))

        i=$((i + 1))
    done

    # 3. Auto-seed garden ideas from metric threshold breaches
    if [ "${GARDEN_AUTO_SEED_METRICS:-true}" = "true" ] && [ "$alert_count" -gt 0 ]; then
        i=0
        while [ "$i" -lt "$alert_count" ]; do
            local metric_name category
            metric_name=$(echo "$metric_alerts" | jq -r ".[$i].metric")
            category=$(echo "$metric_alerts" | jq -r ".[$i].category")

            local tags="auto-seed,metrics,$category,$metric_name"
            local dup_id
            dup_id=$(_garden_find_duplicates "$tags" 2>/dev/null) || true

            if [ -z "$dup_id" ]; then
                local seed_id
                seed_id=$(_garden_plant_seed \
                    "Improve $metric_name" \
                    "Metric $metric_name in category $category has been degrading. Investigate root cause and implement improvement." \
                    "metric_alert" "evolve-reflect" "evolve-reflect" \
                    "medium" "$tags") && ideas_seeded=$((ideas_seeded + 1))
                log "EVOLVE" "REFLECT: Auto-seeded idea from metric alert: $metric_name"
            else
                _garden_water "$dup_id" "metric_trend" \
                    "Metric $metric_name still degrading (cycle $cycle_id)" \
                    "evolve-reflect"
                log "EVOLVE" "REFLECT: Watered existing idea $dup_id for metric: $metric_name"
            fi

            i=$((i + 1))
        done
    fi

    # 4. Auto-seed garden ideas from strong unlinked signals
    if [ "${GARDEN_AUTO_SEED_SIGNALS:-true}" = "true" ]; then
        local unlinked_signals
        unlinked_signals=$(_signal_get_unlinked 2>/dev/null || echo "[]")
        local unlinked_count
        unlinked_count=$(echo "$unlinked_signals" | jq 'length' 2>/dev/null || echo 0)

        local seed_threshold="${GARDEN_SIGNAL_SEED_THRESHOLD:-0.7}"
        local j=0
        while [ "$j" -lt "$unlinked_count" ]; do
            local sig_strength sig_title sig_desc sig_id sig_type
            sig_strength=$(echo "$unlinked_signals" | jq -r ".[$j].strength")
            sig_title=$(echo "$unlinked_signals" | jq -r ".[$j].title")
            sig_desc=$(echo "$unlinked_signals" | jq -r ".[$j].description")
            sig_id=$(echo "$unlinked_signals" | jq -r ".[$j].id")
            sig_type=$(echo "$unlinked_signals" | jq -r ".[$j].type")

            local above_threshold
            above_threshold=$(awk -v s="$sig_strength" -v t="$seed_threshold" \
                'BEGIN { print (s >= t) ? "1" : "0" }')

            if [ "$above_threshold" = "1" ]; then
                local tags="auto-seed,signal,$sig_type"
                local dup_id
                dup_id=$(_garden_find_duplicates "$tags" 2>/dev/null) || true

                if [ -z "$dup_id" ]; then
                    local seed_id
                    seed_id=$(_garden_plant_seed \
                        "Address: $sig_title" \
                        "$sig_desc (auto-seeded from strong unlinked signal $sig_id)" \
                        "signal" "evolve-reflect" "evolve-reflect" \
                        "medium" "$tags")
                    if [ -n "$seed_id" ]; then
                        _signal_link_idea "$sig_id" "$seed_id"
                        ideas_seeded=$((ideas_seeded + 1))
                        log "EVOLVE" "REFLECT: Auto-seeded idea $seed_id from signal $sig_id"
                    fi
                else
                    _garden_water "$dup_id" "signal_observation" \
                        "Signal $sig_id ($sig_title) still strong at $sig_strength" \
                        "evolve-reflect"
                    _signal_link_idea "$sig_id" "$dup_id"
                    log "EVOLVE" "REFLECT: Watered existing idea $dup_id from signal $sig_id"
                fi
            fi

            j=$((j + 1))
        done
    fi

    # 5. Prune expired garden items
    local pre_prune_total=0
    if [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local index_file="$AUTOMATON_DIR/garden/_index.json"
        if [ -f "$index_file" ]; then
            pre_prune_total=$(jq '.total // 0' "$index_file" 2>/dev/null || echo 0)
        fi
        _garden_prune_expired
        if [ -f "$index_file" ]; then
            local post_prune_total
            post_prune_total=$(jq '.total // 0' "$index_file" 2>/dev/null || echo 0)
            # Note: wilt increases total, so pruned = ideas that moved to wilt
            # We track via the rebuild count difference
        fi
        _garden_rebuild_index
    fi
    log "EVOLVE" "REFLECT: Garden pruning complete"

    # 6. Decay all signals
    local pre_decay_count=0
    if [ -f "$AUTOMATON_DIR/signals.json" ]; then
        pre_decay_count=$(jq '.signals | length' "$AUTOMATON_DIR/signals.json" 2>/dev/null || echo 0)
    fi
    _signal_decay_all 2>/dev/null || true
    local post_decay_count=0
    if [ -f "$AUTOMATON_DIR/signals.json" ]; then
        post_decay_count=$(jq '.signals | length' "$AUTOMATON_DIR/signals.json" 2>/dev/null || echo 0)
    fi
    signals_decayed=$((pre_decay_count - post_decay_count))
    if [ "$signals_decayed" -lt 0 ]; then signals_decayed=0; fi

    # 7. Build recommendation from metric alerts
    local recommendation="No significant issues detected"
    if [ "$alert_count" -gt 0 ]; then
        local top_metric
        top_metric=$(echo "$metric_alerts" | jq -r '.[0].metric // "unknown"')
        recommendation="Focus on $top_metric — degrading trend detected"
    fi

    # 8. Write reflect.json
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson metric_alerts "$metric_alerts" \
        --argjson signals_emitted "$signals_emitted" \
        --argjson ideas_seeded "$ideas_seeded" \
        --argjson ideas_pruned "$ideas_pruned" \
        --argjson signals_decayed "$signals_decayed" \
        --arg recommendation "$recommendation" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            metric_alerts: $metric_alerts,
            signals_emitted: $signals_emitted,
            ideas_seeded: $ideas_seeded,
            ideas_pruned: $ideas_pruned,
            signals_decayed: $signals_decayed,
            recommendation: $recommendation
        }' > "$cycle_dir/reflect.json"

    log "EVOLVE" "REFLECT phase complete: signals_emitted=$signals_emitted ideas_seeded=$ideas_seeded signals_decayed=$signals_decayed"
    return 0
}

_evolve_ideate() {
    local cycle_id="${1:?_evolve_ideate requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "IDEATE phase starting (cycle=$cycle_id)"

    local ideas_watered=0
    local ideas_promoted_to_bloom=0
    local ideas_created=0
    local ideas_linked=0

    # 1. Read reflection summary from REFLECT phase
    local reflect_file="$cycle_dir/reflect.json"
    local metric_alerts="[]"
    local reflect_recommendation=""
    if [ -f "$reflect_file" ]; then
        metric_alerts=$(jq '.metric_alerts // []' "$reflect_file" 2>/dev/null || echo "[]")
        reflect_recommendation=$(jq -r '.recommendation // ""' "$reflect_file" 2>/dev/null || echo "")
    else
        log "EVOLVE" "IDEATE: No reflect.json found, proceeding without reflection summary"
    fi

    # 2. Gather active signals for cross-referencing
    local active_signals="[]"
    active_signals=$(_signal_get_active 2>/dev/null || echo "[]")
    local active_signal_count
    active_signal_count=$(echo "$active_signals" | jq 'length' 2>/dev/null || echo 0)

    # 3. Water existing sprouts with evidence from metric alerts
    local alert_count
    alert_count=$(echo "$metric_alerts" | jq 'length' 2>/dev/null || echo 0)

    if [ "$alert_count" -gt 0 ] && [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local garden_dir="$AUTOMATON_DIR/garden"
        local sprout_files
        sprout_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

        for idea_file in $sprout_files; do
            [ -f "$idea_file" ] || continue
            local stage idea_id idea_tags
            stage=$(jq -r '.stage' "$idea_file" 2>/dev/null)
            [ "$stage" = "seed" ] || [ "$stage" = "sprout" ] || continue

            idea_id=$(jq -r '.id' "$idea_file" 2>/dev/null)
            idea_tags=$(jq -r '.tags // [] | join(",")' "$idea_file" 2>/dev/null)

            # Check if any metric alert relates to this idea's tags
            local i=0
            while [ "$i" -lt "$alert_count" ]; do
                local metric_name
                metric_name=$(echo "$metric_alerts" | jq -r ".[$i].metric" 2>/dev/null)

                if echo "$idea_tags" | grep -qi "$metric_name" 2>/dev/null; then
                    _garden_water "$idea_id" "ideate_evidence" \
                        "Metric $metric_name still alerting in cycle $cycle_id (IDEATE enrichment)" \
                        "evolve-ideate" 2>/dev/null && ideas_watered=$((ideas_watered + 1))
                    break
                fi
                i=$((i + 1))
            done
        done
    fi

    # 4. Water ideas with evidence from active signals
    if [ "$active_signal_count" -gt 0 ] && [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local garden_dir="$AUTOMATON_DIR/garden"
        local idea_files
        idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

        local s=0
        while [ "$s" -lt "$active_signal_count" ]; do
            local sig_id sig_title sig_related_ideas
            sig_id=$(echo "$active_signals" | jq -r ".[$s].id" 2>/dev/null)
            sig_title=$(echo "$active_signals" | jq -r ".[$s].title" 2>/dev/null)
            sig_related_ideas=$(echo "$active_signals" | jq -r ".[$s].related_ideas // [] | .[]" 2>/dev/null)

            # Water ideas already linked to this signal
            for linked_id in $sig_related_ideas; do
                [ -n "$linked_id" ] || continue
                local linked_file="$garden_dir/${linked_id}.json"
                [ -f "$linked_file" ] || continue
                local linked_stage
                linked_stage=$(jq -r '.stage' "$linked_file" 2>/dev/null)
                if [ "$linked_stage" = "seed" ] || [ "$linked_stage" = "sprout" ]; then
                    _garden_water "$linked_id" "signal_reinforcement" \
                        "Signal $sig_id ($sig_title) still active in cycle $cycle_id" \
                        "evolve-ideate" 2>/dev/null && ideas_watered=$((ideas_watered + 1))
                fi
            done

            # Link unlinked signals to ideas with matching tags
            if [ -z "$sig_related_ideas" ]; then
                local sig_type
                sig_type=$(echo "$active_signals" | jq -r ".[$s].type" 2>/dev/null)
                for idea_file in $idea_files; do
                    [ -f "$idea_file" ] || continue
                    local idea_stage idea_id idea_tags
                    idea_stage=$(jq -r '.stage' "$idea_file" 2>/dev/null)
                    [ "$idea_stage" = "seed" ] || [ "$idea_stage" = "sprout" ] || continue

                    idea_tags=$(jq -r '.tags // [] | join(" ")' "$idea_file" 2>/dev/null)
                    idea_id=$(jq -r '.id' "$idea_file" 2>/dev/null)

                    if echo "$idea_tags" | grep -qi "$sig_type" 2>/dev/null; then
                        _signal_link_idea "$sig_id" "$idea_id" 2>/dev/null && ideas_linked=$((ideas_linked + 1))
                        break
                    fi
                done
            fi

            s=$((s + 1))
        done
    fi

    # 5. Create new ideas from reflection patterns not yet in garden
    if [ -n "$reflect_recommendation" ] && [ "$reflect_recommendation" != "No significant issues detected" ] && [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local tags="auto-seed,ideate,reflection"
        local dup_id
        dup_id=$(_garden_find_duplicates "$tags" 2>/dev/null) || true

        if [ -z "$dup_id" ]; then
            local seed_id
            seed_id=$(_garden_plant_seed \
                "From reflection: $reflect_recommendation" \
                "Auto-seeded from IDEATE phase based on REFLECT recommendation: $reflect_recommendation (cycle $cycle_id)" \
                "ideate" "evolve-ideate" "evolve-ideate" \
                "medium" "$tags") && ideas_created=$((ideas_created + 1))
            if [ -n "$seed_id" ]; then
                log "EVOLVE" "IDEATE: Created idea $seed_id from reflection recommendation"
            fi
        fi
    fi

    # 6. Evaluate sprout-to-bloom transitions and collect bloom candidates
    local bloom_candidates_json="[]"
    if [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        _garden_recompute_priorities 2>/dev/null || true

        local bloom_ids
        bloom_ids=$(_garden_get_bloom_candidates 2>/dev/null) || true

        if [ -n "$bloom_ids" ]; then
            local candidates_arr="["
            local first=true
            for bid in $bloom_ids; do
                local bfile="$AUTOMATON_DIR/garden/${bid}.json"
                [ -f "$bfile" ] || continue
                local btitle bpriority
                btitle=$(jq -r '.title' "$bfile" 2>/dev/null)
                bpriority=$(jq -r '.priority // 0' "$bfile" 2>/dev/null)
                ideas_promoted_to_bloom=$((ideas_promoted_to_bloom + 1))

                if [ "$first" = "true" ]; then
                    first=false
                else
                    candidates_arr="${candidates_arr},"
                fi
                candidates_arr="${candidates_arr}{\"id\":\"$bid\",\"title\":$(echo "$btitle" | jq -Rs .),\"priority\":$bpriority}"
            done
            candidates_arr="${candidates_arr}]"
            bloom_candidates_json="$candidates_arr"
        fi

        _garden_rebuild_index 2>/dev/null || true
    fi

    # 7. Write ideate.json
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson ideas_watered "$ideas_watered" \
        --argjson ideas_promoted_to_bloom "$ideas_promoted_to_bloom" \
        --argjson ideas_created "$ideas_created" \
        --argjson ideas_linked "$ideas_linked" \
        --argjson bloom_candidates "$bloom_candidates_json" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            ideas_watered: $ideas_watered,
            ideas_promoted_to_bloom: $ideas_promoted_to_bloom,
            ideas_created: $ideas_created,
            ideas_linked: $ideas_linked,
            bloom_candidates: $bloom_candidates
        }' > "$cycle_dir/ideate.json"

    log "EVOLVE" "IDEATE phase complete: watered=$ideas_watered promoted=$ideas_promoted_to_bloom created=$ideas_created linked=$ideas_linked"
    return 0
}

# EVALUATE phase (spec-41 §5): runs the agent quorum on bloom-stage ideas.
# Selects the highest-priority bloom candidate, invokes _quorum_evaluate_bloom(),
# and writes evaluate.json to the cycle directory. Skips to OBSERVE if no bloom
# candidates exist. Only the highest-priority candidate is evaluated per cycle
# (Article VI: incremental growth).
#
# Usage: _evolve_evaluate <cycle_id>
# Args:  cycle_id — the current evolution cycle number
_evolve_evaluate() {
    local cycle_id="${1:?_evolve_evaluate requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "EVALUATE phase starting (cycle=$cycle_id)"

    # Read ideate.json for bloom candidates context
    local ideate_file="$cycle_dir/ideate.json"
    local bloom_candidates_count=0
    if [ -f "$ideate_file" ]; then
        bloom_candidates_count=$(jq '.bloom_candidates | length' "$ideate_file" 2>/dev/null || echo 0)
    fi

    # Get bloom candidates from the garden
    local candidates=""
    candidates=$(_garden_get_bloom_candidates 2>/dev/null) || true

    if [ -z "$candidates" ]; then
        log "EVOLVE" "EVALUATE: No bloom candidates — skipping to OBSERVE"

        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq -n \
            --argjson cycle_id "$cycle_id" \
            --arg timestamp "$now" \
            --argjson bloom_candidates_count "$bloom_candidates_count" \
            --arg evaluated "none" \
            --arg vote_id "none" \
            --arg result "skipped" \
            --arg conditions "[]" \
            --argjson tokens_used 0 \
            '{
                cycle_id: $cycle_id,
                timestamp: $timestamp,
                bloom_candidates_count: $bloom_candidates_count,
                evaluated: $evaluated,
                vote_id: $vote_id,
                result: $result,
                conditions: $conditions,
                tokens_used: $tokens_used
            }' > "$cycle_dir/evaluate.json"

        return 0
    fi

    # Select highest-priority candidate (first line from sorted output)
    local idea_id
    idea_id=$(echo "$candidates" | head -1)
    local candidate_count
    candidate_count=$(echo "$candidates" | wc -l | tr -d ' ')
    bloom_candidates_count=$candidate_count

    log "EVOLVE" "EVALUATE: $candidate_count bloom candidate(s), evaluating $idea_id"

    # Reset quorum cycle token counter for this evaluation
    _QUORUM_CYCLE_TOKENS=0

    # Invoke the quorum evaluation (handles voting, vote record, and idea advancement/wilting)
    local vote_file=""
    vote_file=$(_quorum_evaluate_bloom 2>/dev/null) || true

    # Extract vote result from the vote record
    local vote_id="none"
    local eval_result="unknown"
    local conditions="[]"
    local tokens_used="${_QUORUM_CYCLE_TOKENS:-0}"

    if [ -n "$vote_file" ] && [ -f "$vote_file" ]; then
        vote_id=$(jq -r '.vote_id // "none"' "$vote_file" 2>/dev/null || echo "none")
        eval_result=$(jq -r '.tally.result // "unknown"' "$vote_file" 2>/dev/null || echo "unknown")
        conditions=$(jq '.tally.conditions // []' "$vote_file" 2>/dev/null || echo "[]")
    elif [ "${QUORUM_ENABLED:-true}" != "true" ]; then
        eval_result="approved"
        vote_id="auto-approved"
    fi

    # Write evaluate.json
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson bloom_candidates_count "$bloom_candidates_count" \
        --arg evaluated "$idea_id" \
        --arg vote_id "$vote_id" \
        --arg result "$eval_result" \
        --argjson conditions "$conditions" \
        --argjson tokens_used "$tokens_used" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            bloom_candidates_count: $bloom_candidates_count,
            evaluated: $evaluated,
            vote_id: $vote_id,
            result: $result,
            conditions: $conditions,
            tokens_used: $tokens_used
        }' > "$cycle_dir/evaluate.json"

    log "EVOLVE" "EVALUATE phase complete: evaluated=$idea_id result=$eval_result vote=$vote_id tokens=$tokens_used"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution: IMPLEMENT Phase (spec-41 §6)
# ---------------------------------------------------------------------------

# Implements the approved idea on a dedicated evolution branch using the
# standard build pipeline with self-build safety constraints. Runs review
# and constitutional compliance check on the resulting diff. If compliance
# fails, abandons the branch and wilts the idea with a quality_concern signal.
#
# Reads evaluate.json from the cycle directory to determine which idea was
# approved and what conditions were set. Writes implement.json with results.
#
# Usage: _evolve_implement "001"
# Returns: 0 on success (including skipped), 1 on unrecoverable error
_evolve_implement() {
    local cycle_id="${1:?_evolve_implement requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "IMPLEMENT phase starting (cycle=$cycle_id)"

    # Read evaluate.json to determine approved idea and conditions
    local eval_file="$cycle_dir/evaluate.json"
    if [ ! -f "$eval_file" ]; then
        log "EVOLVE" "IMPLEMENT: No evaluate.json found — skipping"
        _write_implement_json "$cycle_dir" "$cycle_id" "" "" 0 0 0 0 "skipped" "skipped" "skipped" "skipped" 0
        return 0
    fi

    local eval_result
    eval_result=$(jq -r '.result // "unknown"' "$eval_file" 2>/dev/null || echo "unknown")
    local idea_id
    idea_id=$(jq -r '.evaluated // "none"' "$eval_file" 2>/dev/null || echo "none")
    local conditions
    conditions=$(jq -r '.conditions // "[]"' "$eval_file" 2>/dev/null || echo "[]")

    # Skip if no idea was approved
    if [ "$eval_result" != "approved" ] || [ "$idea_id" = "none" ]; then
        log "EVOLVE" "IMPLEMENT: No approved idea (result=$eval_result) — skipping"
        _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "" 0 0 0 0 "skipped" "skipped" "skipped" "skipped" 0
        return 0
    fi

    log "EVOLVE" "IMPLEMENT: Building idea=$idea_id on evolution branch"

    # 1. Create a dedicated evolution branch
    if ! _safety_branch_create "$cycle_id" "$idea_id"; then
        log "EVOLVE" "IMPLEMENT: Failed to create evolution branch — aborting"
        _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "" 0 0 0 0 "failed" "skipped" "skipped" "failed" 0
        return 1
    fi

    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    # 2. Generate an implementation plan from the approved idea
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    local idea_title="" idea_description=""
    if [ -f "$idea_file" ]; then
        idea_title=$(jq -r '.title // "Untitled"' "$idea_file" 2>/dev/null || echo "Untitled")
        idea_description=$(jq -r '.description // ""' "$idea_file" 2>/dev/null || echo "")
    fi

    # Write a minimal implementation plan on the evolution branch
    local plan_content="# Evolution Implementation Plan\n\n"
    plan_content+="## Cycle ${cycle_id} — ${idea_title}\n\n"
    plan_content+="${idea_description}\n\n"
    if [ "$conditions" != "[]" ] && [ -n "$conditions" ]; then
        plan_content+="### Conditions from Quorum\n\n"
        plan_content+="$conditions\n\n"
    fi
    plan_content+="## Tasks\n\n- [ ] Implement: ${idea_title}\n"
    printf "%b" "$plan_content" > IMPLEMENTATION_PLAN.md
    git add IMPLEMENTATION_PLAN.md 2>/dev/null || true
    git commit -m "Evolution cycle $cycle_id: plan for $idea_id — $idea_title" --allow-empty 2>/dev/null || true

    # 3. Run the build pipeline with self-build safety
    local build_iterations=0
    local max_build_iterations="${EVOLVE_MAX_BUILD_ITERATIONS:-3}"
    local build_success="false"
    local build_tokens=0

    while [ "$build_iterations" -lt "$max_build_iterations" ]; do
        build_iterations=$((build_iterations + 1))
        log "EVOLVE" "IMPLEMENT: Build iteration $build_iterations/$max_build_iterations"

        run_agent "PROMPT_build.md" "${EVOLUTION_BUILD_MODEL:-sonnet}"

        if [ "$AGENT_EXIT_CODE" -eq 0 ]; then
            build_success="true"
            break
        fi
    done

    # 4. Count changes on the evolution branch
    local files_changed=0 lines_changed=0 tests_added=0
    local diff_stat
    diff_stat=$(git diff --stat "$WORKING_BRANCH"...HEAD 2>/dev/null || echo "")
    if [ -n "$diff_stat" ]; then
        files_changed=$(echo "$diff_stat" | tail -1 | grep -oP '\d+ files?' | grep -oP '\d+' || echo 0)
        lines_changed=$(echo "$diff_stat" | tail -1 | grep -oP '\d+ insertion|deletion' | grep -oP '\d+' | paste -sd+ - | bc 2>/dev/null || echo 0)
        tests_added=$(git diff "$WORKING_BRANCH"...HEAD --name-only 2>/dev/null | grep -c '^tests/' || echo 0)
    fi

    # 5. Run syntax check
    local syntax_result="passed"
    if ! bash -n automaton.sh 2>/dev/null; then
        syntax_result="failed"
    fi

    # 6. Run sandbox testing
    local sandbox_result="passed"
    if ! _safety_sandbox_test "$branch" 2>/dev/null; then
        sandbox_result="failed"
    fi

    # 7. Run review pipeline
    local review_result="passed"
    run_agent "PROMPT_review.md" "${EVOLUTION_REVIEW_MODEL:-opus}" 2>/dev/null || true

    # 8. Run constitutional compliance check on the resulting diff
    local constitution_result="passed"
    local diff_file="$cycle_dir/implement_diff.tmp"
    git diff "$WORKING_BRANCH"...HEAD > "$diff_file" 2>/dev/null || true

    if [ -s "$diff_file" ]; then
        constitution_result=$(_constitution_check "$diff_file" "$idea_id" "$cycle_id" 2>/dev/null || echo "warn")
    fi
    rm -f "$diff_file"

    # 9. Handle failures: abandon branch and wilt idea
    if [ "$syntax_result" = "failed" ] || [ "$constitution_result" = "fail" ] || [ "$sandbox_result" = "failed" ]; then
        local fail_reason="compliance"
        [ "$syntax_result" = "failed" ] && fail_reason="syntax check failed"
        [ "$sandbox_result" = "failed" ] && fail_reason="sandbox testing failed"
        [ "$constitution_result" = "fail" ] && fail_reason="constitutional compliance failed"

        log "EVOLVE" "IMPLEMENT: Compliance failure ($fail_reason) — rolling back"

        # _safety_rollback handles: abandon branch, wilt idea, emit quality_concern signal
        if ! _safety_rollback "$cycle_id" "$idea_id" "$fail_reason" 2>/dev/null; then
            # Fallback: emit quality_concern signal directly if rollback failed
            _signal_emit "quality_concern" \
                "Implementation of $idea_id failed" \
                "Compliance failure: $fail_reason" \
                "evolve" "$cycle_id" "" 2>/dev/null || true
        fi

        _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "$branch" \
            "$build_iterations" "$files_changed" "$lines_changed" "$tests_added" \
            "$syntax_result" "$sandbox_result" "$constitution_result" "failed" "$build_tokens"
        return 0
    fi

    # Success — stay on evolution branch for OBSERVE to decide merge
    _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "$branch" \
        "$build_iterations" "$files_changed" "$lines_changed" "$tests_added" \
        "$syntax_result" "$sandbox_result" "$constitution_result" "completed" "$build_tokens"

    log "EVOLVE" "IMPLEMENT phase complete: idea=$idea_id branch=$branch files=$files_changed lines=$lines_changed syntax=$syntax_result constitution=$constitution_result"
    return 0
}

# Helper: write implement.json with all required fields.
_write_implement_json() {
    local cycle_dir="$1" cycle_id="$2" idea_id="$3" branch="$4"
    local iterations="$5" files_changed="$6" lines_changed="$7" tests_added="$8"
    local syntax_check="$9" smoke_test="${10}" constitution_check="${11}"
    local status="${12}" tokens_used="${13}"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "${cycle_id:-0}" \
        --arg timestamp "$now" \
        --arg idea_id "${idea_id:-none}" \
        --arg branch "${branch:-none}" \
        --argjson iterations "${iterations:-0}" \
        --argjson files_changed "${files_changed:-0}" \
        --argjson lines_changed "${lines_changed:-0}" \
        --argjson tests_added "${tests_added:-0}" \
        --arg syntax_check "${syntax_check:-skipped}" \
        --arg smoke_test "${smoke_test:-skipped}" \
        --arg constitution_check "${constitution_check:-skipped}" \
        --arg status "${status:-unknown}" \
        --argjson tokens_used "${tokens_used:-0}" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            idea_id: $idea_id,
            branch: $branch,
            iterations: $iterations,
            files_changed: $files_changed,
            lines_changed: $lines_changed,
            tests_added: $tests_added,
            syntax_check: $syntax_check,
            smoke_test: $smoke_test,
            constitution_check: $constitution_check,
            status: $status,
            tokens_used: $tokens_used
        }' > "$cycle_dir/implement.json"
}

# ---------------------------------------------------------------------------
# Evolution: OBSERVE Phase (spec-41 §7)
# ---------------------------------------------------------------------------

# Validates the impact of an evolution implementation by comparing pre-cycle
# and post-cycle metrics, running sandbox tests, and deciding the outcome:
# - harvest: merge branch, advance idea to harvest, emit promising_approach
# - wilt: rollback, emit quality_concern signal
# - neutral: merge branch, emit attention_needed signal
#
# Reads implement.json from the cycle directory to determine which idea and
# branch to evaluate. Writes observe.json with the outcome and metrics delta.
#
# Usage: _evolve_observe "001"
# Returns: 0 on success (including skipped), 1 on unrecoverable error
_evolve_observe() {
    local cycle_id="${1:?_evolve_observe requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "OBSERVE phase starting (cycle=$cycle_id)"

    # Read implement.json to determine idea and branch
    local impl_file="$cycle_dir/implement.json"
    if [ ! -f "$impl_file" ]; then
        log "EVOLVE" "OBSERVE: No implement.json found — skipping"
        _write_observe_json "$cycle_dir" "$cycle_id" "" "{}" "{}" "{}" "0.00" "skipped" 0
        return 0
    fi

    local impl_status
    impl_status=$(jq -r '.status // "unknown"' "$impl_file" 2>/dev/null || echo "unknown")
    local idea_id
    idea_id=$(jq -r '.idea_id // "none"' "$impl_file" 2>/dev/null || echo "none")
    local branch
    branch=$(jq -r '.branch // "none"' "$impl_file" 2>/dev/null || echo "none")

    # Skip if implementation was not completed
    if [ "$impl_status" != "completed" ] || [ "$idea_id" = "none" ]; then
        log "EVOLVE" "OBSERVE: Implementation status=$impl_status — skipping observation"
        _write_observe_json "$cycle_dir" "$cycle_id" "$idea_id" "{}" "{}" "{}" "0.00" "skipped" 0
        return 0
    fi

    log "EVOLVE" "OBSERVE: Evaluating idea=$idea_id branch=$branch"

    # 1. Take a post-cycle metrics snapshot
    _metrics_snapshot "$cycle_id" 2>/dev/null || true

    # 2. Get pre-cycle and post-cycle snapshots for comparison
    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    local pre_snapshot="{}" post_snapshot="{}"

    if [ -f "$metrics_file" ]; then
        local snap_count
        snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
        if [ "$snap_count" -ge 2 ]; then
            pre_snapshot=$(jq '.snapshots[-2]' "$metrics_file" 2>/dev/null || echo "{}")
            post_snapshot=$(jq '.snapshots[-1]' "$metrics_file" 2>/dev/null || echo "{}")
        elif [ "$snap_count" -ge 1 ]; then
            post_snapshot=$(jq '.snapshots[-1]' "$metrics_file" 2>/dev/null || echo "{}")
        fi
    fi

    # 3. Compare pre and post metrics
    local comparison="{}"
    comparison=$(_metrics_compare "$pre_snapshot" "$post_snapshot" 2>/dev/null || echo '{"deltas":[],"summary":{"improved":0,"degraded":0,"unchanged":0}}')

    local improved degraded
    improved=$(echo "$comparison" | jq '.summary.improved // 0' 2>/dev/null || echo 0)
    degraded=$(echo "$comparison" | jq '.summary.degraded // 0' 2>/dev/null || echo 0)

    # 4. Run sandbox testing on the evolution branch
    local sandbox_passed="true"
    if ! _safety_sandbox_test "$branch" 2>/dev/null; then
        sandbox_passed="false"
    fi

    # 5. Compute test pass rate from post snapshot
    local test_pass_rate="0.00"
    test_pass_rate=$(echo "$post_snapshot" | jq -r '.quality.test_pass_rate // "0.00"' 2>/dev/null || echo "0.00")

    # 6. Decide outcome based on metrics delta and sandbox results
    local outcome="neutral"
    local signals_emitted=0

    if [ "$sandbox_passed" = "false" ]; then
        # Sandbox failure → regression → rollback
        outcome="wilt"
    elif [ "$degraded" -gt "$improved" ]; then
        # More metrics degraded than improved → regression
        outcome="wilt"
    elif [ "$improved" -gt 0 ] && [ "$degraded" -eq 0 ]; then
        # Improvement detected with no regression → harvest
        outcome="harvest"
    elif [ "$improved" -gt "$degraded" ]; then
        # Net improvement → harvest
        outcome="harvest"
    fi
    # Default: neutral (no measurable change or mixed results with no net direction)

    log "EVOLVE" "OBSERVE: outcome=$outcome improved=$improved degraded=$degraded sandbox=$sandbox_passed"

    # 7. Execute the outcome
    case "$outcome" in
        harvest)
            # Merge the evolution branch into working branch
            if _safety_branch_merge "$cycle_id" "$idea_id" 2>/dev/null; then
                # Advance idea to harvest stage
                _garden_advance_stage "$idea_id" "harvest" "Cycle $cycle_id: metrics improved" "true" 2>/dev/null || true

                # Emit promising_approach signal
                _signal_emit "promising_approach" \
                    "Implementation of $idea_id improved metrics" \
                    "Cycle $cycle_id: $improved metrics improved, $degraded degraded" \
                    "evolve" "$cycle_id" "" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))

                log "EVOLVE" "OBSERVE: Harvested idea=$idea_id — branch merged"
            else
                # Merge failed — treat as regression
                outcome="wilt"
                log "EVOLVE" "OBSERVE: Merge failed — falling back to rollback"
                _safety_rollback "$cycle_id" "$idea_id" "Merge failure during OBSERVE" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))
            fi
            ;;
        wilt)
            # Rollback: abandon branch, wilt idea, emit quality_concern
            _safety_rollback "$cycle_id" "$idea_id" "Regression detected in OBSERVE phase" 2>/dev/null || true
            signals_emitted=$((signals_emitted + 1))
            log "EVOLVE" "OBSERVE: Wilted idea=$idea_id — rolled back"
            ;;
        neutral)
            # Merge with attention signal
            if _safety_branch_merge "$cycle_id" "$idea_id" 2>/dev/null; then
                # Advance idea to harvest (merged but needs monitoring)
                _garden_advance_stage "$idea_id" "harvest" "Cycle $cycle_id: neutral result, merged for monitoring" "true" 2>/dev/null || true

                # Emit attention_needed signal
                _signal_emit "attention_needed" \
                    "Implementation of $idea_id had no measurable impact" \
                    "Cycle $cycle_id: $improved improved, $degraded degraded — monitor in future cycles" \
                    "evolve" "$cycle_id" "" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))

                log "EVOLVE" "OBSERVE: Merged idea=$idea_id with attention_needed signal"
            else
                outcome="wilt"
                log "EVOLVE" "OBSERVE: Merge failed for neutral outcome — falling back to rollback"
                _safety_rollback "$cycle_id" "$idea_id" "Merge failure during OBSERVE (neutral)" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))
            fi
            ;;
    esac

    # 8. Rebuild the garden index to reflect any stage changes
    _garden_rebuild_index 2>/dev/null || true

    # 9. Build delta summary for observe.json
    local delta_json="{}"
    delta_json=$(echo "$comparison" | jq '.deltas | map({(.metric): .delta}) | add // {}' 2>/dev/null || echo "{}")

    # Extract pre/post summaries for the output
    local pre_metrics_json="{}"
    local post_metrics_json="{}"
    pre_metrics_json=$(echo "$comparison" | jq '[.deltas[] | {(.metric): .before}] | add // {}' 2>/dev/null || echo "{}")
    post_metrics_json=$(echo "$comparison" | jq '[.deltas[] | {(.metric): .after}] | add // {}' 2>/dev/null || echo "{}")

    # Write observe.json
    _write_observe_json "$cycle_dir" "$cycle_id" "$idea_id" \
        "$pre_metrics_json" "$post_metrics_json" "$delta_json" \
        "$test_pass_rate" "$outcome" "$signals_emitted"

    log "EVOLVE" "OBSERVE phase complete: idea=$idea_id outcome=$outcome signals=$signals_emitted"
    return 0
}

# Helper: write observe.json with all required fields.
_write_observe_json() {
    local cycle_dir="$1" cycle_id="$2" idea_id="$3"
    local pre_metrics="$4" post_metrics="$5" delta="$6"
    local test_pass_rate="$7" outcome="$8" signals_emitted="$9"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "${cycle_id:-0}" \
        --arg timestamp "$now" \
        --arg idea_id "${idea_id:-none}" \
        --argjson pre_metrics "${pre_metrics:-{}}" \
        --argjson post_metrics "${post_metrics:-{}}" \
        --argjson delta "${delta:-{}}" \
        --arg test_pass_rate "${test_pass_rate:-0.00}" \
        --arg outcome "${outcome:-unknown}" \
        --argjson signals_emitted "${signals_emitted:-0}" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            idea_id: $idea_id,
            pre_metrics: $pre_metrics,
            post_metrics: $post_metrics,
            delta: $delta,
            test_pass_rate: $test_pass_rate,
            outcome: $outcome,
            signals_emitted: $signals_emitted
        }' > "$cycle_dir/observe.json"
}

# ---------------------------------------------------------------------------
# Evolution Cycle Runner (spec-41 §8)
# ---------------------------------------------------------------------------

# Orchestrates one complete evolution cycle: REFLECT → IDEATE → EVALUATE →
# IMPLEMENT → OBSERVE. Manages per-cycle budget, takes pre/post metrics
# snapshots, creates the cycle directory, and handles phase failures.
#
# Usage: _evolve_run_cycle <cycle_id>
# Returns: 0 on success, 1 on phase failure, 2 on budget exhaustion,
#          3 on circuit breaker trip
_evolve_run_cycle() {
    local cycle_id="${1:?_evolve_run_cycle requires cycle_id}"
    local padded_cycle
    padded_cycle=$(printf "%03d" "$cycle_id")
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${padded_cycle}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "=== Cycle $cycle_id starting ==="

    # Check circuit breakers before starting the cycle
    if _safety_any_breaker_tripped 2>/dev/null; then
        log "EVOLVE" "Cycle $cycle_id aborted: circuit breaker tripped"
        jq -n --argjson cycle_id "$cycle_id" --arg status "aborted" \
            --arg reason "circuit_breaker_tripped" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{cycle_id: $cycle_id, status: $status, reason: $reason, timestamp: $timestamp}' \
            > "$cycle_dir/cycle-summary.json"
        return 3
    fi

    # Take pre-cycle metrics snapshot
    _metrics_snapshot "$cycle_id" 2>/dev/null || true

    local cycle_status="completed"
    local cycle_reason=""
    local phases_completed=0

    # --- Phase 1: REFLECT ---
    log "EVOLVE" "Cycle $cycle_id: Phase 1/5 REFLECT"
    if ! _evolve_reflect "$padded_cycle" 2>/dev/null; then
        log "EVOLVE" "Cycle $cycle_id: REFLECT phase failed — aborting cycle"
        cycle_status="failed"
        cycle_reason="reflect_phase_failed"
    fi
    phases_completed=$((phases_completed + 1))

    # Check circuit breakers after REFLECT
    if [ "$cycle_status" = "completed" ] && _safety_any_breaker_tripped 2>/dev/null; then
        log "EVOLVE" "Cycle $cycle_id: circuit breaker tripped after REFLECT"
        cycle_status="aborted"
        cycle_reason="circuit_breaker_tripped_after_reflect"
    fi

    # --- Phase 2: IDEATE ---
    if [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 2/5 IDEATE"
        if ! _evolve_ideate "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: IDEATE phase failed — aborting cycle"
            cycle_status="failed"
            cycle_reason="ideate_phase_failed"
        fi
        phases_completed=$((phases_completed + 1))
    fi

    # --- Phase 3: EVALUATE ---
    local eval_result="skipped"
    if [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 3/5 EVALUATE"
        if ! _evolve_evaluate "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: EVALUATE phase failed — aborting cycle"
            cycle_status="failed"
            cycle_reason="evaluate_phase_failed"
        else
            # Check evaluate.json to determine if we have a candidate
            local eval_file="$cycle_dir/evaluate.json"
            if [ -f "$eval_file" ]; then
                eval_result=$(jq -r '.result // "skipped"' "$eval_file" 2>/dev/null || echo "skipped")
            fi
        fi
        phases_completed=$((phases_completed + 1))
    fi

    # --- Phase 4: IMPLEMENT (skip if no approved candidate) ---
    if [ "$cycle_status" = "completed" ] && [ "$eval_result" = "approved" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 4/5 IMPLEMENT"
        if ! _evolve_implement "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: IMPLEMENT phase failed — skipping to OBSERVE"
            # Implementation failure is not fatal — OBSERVE will handle cleanup
        fi
        phases_completed=$((phases_completed + 1))
    elif [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 4/5 IMPLEMENT skipped (no approved candidate, eval_result=$eval_result)"
        phases_completed=$((phases_completed + 1))
    fi

    # --- Phase 5: OBSERVE ---
    if [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 5/5 OBSERVE"
        if ! _evolve_observe "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: OBSERVE phase failed"
            cycle_status="failed"
            cycle_reason="observe_phase_failed"
        fi
        phases_completed=$((phases_completed + 1))
    fi

    # Persist garden state after cycle
    _garden_rebuild_index 2>/dev/null || true

    # Write cycle summary
    local observe_outcome="none"
    local observe_file="$cycle_dir/observe.json"
    if [ -f "$observe_file" ]; then
        observe_outcome=$(jq -r '.outcome // "none"' "$observe_file" 2>/dev/null || echo "none")
    fi

    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg status "$cycle_status" \
        --arg reason "$cycle_reason" \
        --argjson phases_completed "$phases_completed" \
        --arg eval_result "$eval_result" \
        --arg observe_outcome "$observe_outcome" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            cycle_id: $cycle_id,
            status: $status,
            reason: $reason,
            phases_completed: $phases_completed,
            eval_result: $eval_result,
            observe_outcome: $observe_outcome,
            timestamp: $timestamp
        }' > "$cycle_dir/cycle-summary.json"

    log "EVOLVE" "=== Cycle $cycle_id $cycle_status (phases=$phases_completed, eval=$eval_result, outcome=$observe_outcome) ==="

    if [ "$cycle_status" = "completed" ]; then
        return 0
    elif [ "$cycle_status" = "aborted" ]; then
        return 3
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Evolution Convergence Detection (spec-41 §8)
# ---------------------------------------------------------------------------

# Checks whether the evolution loop has converged and should stop.
# Convergence occurs when:
#   1. consecutive_no_improvement >= EVOLVE_CONVERGENCE_THRESHOLD
#      (no cycle produced a "harvest" outcome in the last N cycles)
#   2. No bloom candidates for EVOLVE_IDLE_GARDEN_THRESHOLD consecutive cycles
#      (eval_result was "skipped" meaning no bloom candidate existed)
#
# Usage: reason=$(_evolve_check_convergence)
# Returns: 0 if converged (reason on stdout), 1 if not converged
_evolve_check_convergence() {
    local evo_dir="$AUTOMATON_DIR/evolution"
    local convergence_threshold="${EVOLVE_CONVERGENCE_THRESHOLD:-5}"
    local idle_threshold="${EVOLVE_IDLE_GARDEN_THRESHOLD:-3}"

    # Collect cycle summaries sorted by cycle number (ascending)
    local cycle_dirs
    cycle_dirs=$(find "$evo_dir" -maxdepth 1 -type d -name 'cycle-*' 2>/dev/null | sort)
    [ -n "$cycle_dirs" ] || return 1

    # Walk cycle summaries in order to compute consecutive streaks
    local consecutive_no_improvement=0
    local consecutive_no_bloom=0

    while IFS= read -r cdir; do
        local summary="$cdir/cycle-summary.json"
        [ -f "$summary" ] || continue

        local observe_outcome eval_result
        observe_outcome=$(jq -r '.observe_outcome // "none"' "$summary" 2>/dev/null || echo "none")
        eval_result=$(jq -r '.eval_result // "skipped"' "$summary" 2>/dev/null || echo "skipped")

        # Track no-improvement streak (harvest resets; anything else increments)
        if [ "$observe_outcome" = "harvest" ]; then
            consecutive_no_improvement=0
        else
            consecutive_no_improvement=$((consecutive_no_improvement + 1))
        fi

        # Track idle garden streak (eval_result=skipped means no bloom candidate)
        if [ "$eval_result" = "skipped" ]; then
            consecutive_no_bloom=$((consecutive_no_bloom + 1))
        else
            consecutive_no_bloom=0
        fi
    done <<< "$cycle_dirs"

    # Check convergence conditions
    if [ "$consecutive_no_improvement" -ge "$convergence_threshold" ]; then
        log "EVOLVE" "Convergence: $consecutive_no_improvement consecutive cycles without improvement (threshold=$convergence_threshold)"
        echo "no_improvement:${consecutive_no_improvement}"
        return 0
    fi

    if [ "$consecutive_no_bloom" -ge "$idle_threshold" ]; then
        log "EVOLVE" "Convergence: $consecutive_no_bloom consecutive cycles with no bloom candidates (threshold=$idle_threshold)"
        echo "idle_garden:${consecutive_no_bloom}"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Evolution Per-Cycle Budget (spec-41 §9)
# ---------------------------------------------------------------------------

# Calculates the per-cycle budget as:
#   min(EVOLVE_MAX_COST_PER_CYCLE, remaining_budget / estimated_remaining_cycles)
# and enforces the budget_ceiling circuit breaker when there is insufficient
# budget to run even one more cycle.
#
# Usage: cycle_budget=$(_evolve_check_budget <current_cycle> <estimated_remaining_cycles>)
# Returns: 0 if budget is available (per-cycle budget on stdout), 1 if exhausted
_evolve_check_budget() {
    local current_cycle="${1:-1}"
    local estimated_remaining="${2:-1}"
    [ "$estimated_remaining" -lt 1 ] && estimated_remaining=1

    local max_per_cycle="${EVOLVE_MAX_COST_PER_CYCLE:-5.00}"
    local budget_file="$AUTOMATON_DIR/budget.json"

    if [ ! -f "$budget_file" ]; then
        log "EVOLVE" "No budget.json found — allowing cycle with max_cost_per_cycle=$max_per_cycle"
        echo "$max_per_cycle"
        return 0
    fi

    local mode remaining_usd
    mode=$(jq -r '.mode // "api"' "$budget_file" 2>/dev/null || echo "api")

    if [ "$mode" = "allowance" ]; then
        # Allowance mode: estimate remaining budget from token headroom
        # Convert token headroom to approximate USD using $3/1M input tokens
        local effective_allowance tokens_used
        effective_allowance=$(jq -r '.limits.effective_allowance // 0' "$budget_file" 2>/dev/null || echo 0)
        tokens_used=$(jq -r '.tokens_used_this_week // 0' "$budget_file" 2>/dev/null || echo 0)
        remaining_usd=$(awk -v eff="$effective_allowance" -v used="$tokens_used" \
            'BEGIN { tokens_left = eff - used; if (tokens_left < 0) tokens_left = 0; printf "%.2f", tokens_left / 1000000 * 3 }')
    else
        # API mode: remaining = max_cost_usd - estimated_cost_usd
        local max_cost_usd used_usd
        max_cost_usd=$(jq -r '.limits.max_cost_usd // 50' "$budget_file" 2>/dev/null || echo 50)
        used_usd=$(jq -r '.used.estimated_cost_usd // 0' "$budget_file" 2>/dev/null || echo 0)
        remaining_usd=$(awk -v max="$max_cost_usd" -v used="$used_usd" \
            'BEGIN { r = max - used; if (r < 0) r = 0; printf "%.2f", r }')
    fi

    # Calculate per-cycle budget: min(max_per_cycle, remaining / estimated_remaining)
    local cycle_budget
    cycle_budget=$(awk -v max="$max_per_cycle" -v rem="$remaining_usd" -v est="$estimated_remaining" \
        'BEGIN { paced = rem / est; budget = (paced < max) ? paced : max; printf "%.2f", budget }')

    # Minimum viable cycle cost threshold ($0.50)
    local min_viable="0.50"
    local is_exhausted
    is_exhausted=$(awk -v cb="$cycle_budget" -v mv="$min_viable" \
        'BEGIN { print (cb + 0 < mv + 0) ? "yes" : "no" }')

    if [ "$is_exhausted" = "yes" ]; then
        log "EVOLVE" "Budget exhausted: cycle_budget=\$$cycle_budget remaining=\$$remaining_usd (min viable=\$$min_viable)"
        _safety_update_breaker "budget_ceiling"
        return 1
    fi

    log "EVOLVE" "Cycle $current_cycle budget: \$$cycle_budget (remaining=\$$remaining_usd, max_per_cycle=\$$max_per_cycle)"
    echo "$cycle_budget"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution Resume State (spec-41 §11)
# ---------------------------------------------------------------------------

# Reads the last cycle directory in .automaton/evolution/ and determines which
# phase was interrupted by checking for phase summary files. Returns the cycle
# number and the phase to resume from via stdout (format: "cycle_id:phase").
#
# Phase files checked in order: reflect.json, ideate.json, evaluate.json,
# implement.json, observe.json. The resume phase is the first missing file.
# If IMPLEMENT was interrupted, checks for an existing evolution branch.
#
# Usage: resume_info=$(_evolve_resume_state)
#        resume_cycle="${resume_info%%:*}"
#        resume_phase="${resume_info##*:}"
# Returns: 0 on success (resume info on stdout), 1 if no previous state
_evolve_resume_state() {
    local evo_dir="$AUTOMATON_DIR/evolution"

    # Find the last cycle directory
    local last_cycle_dir
    last_cycle_dir=$(find "$evo_dir" -maxdepth 1 -type d -name 'cycle-*' 2>/dev/null | sort | tail -1)

    if [ -z "$last_cycle_dir" ]; then
        log "EVOLVE" "No previous evolution cycle found — starting fresh"
        echo "1:reflect"
        return 1
    fi

    # Extract cycle number from directory name (e.g., cycle-003 -> 3)
    local resume_cycle
    resume_cycle=$(basename "$last_cycle_dir" | sed 's/cycle-0*//')
    [ -z "$resume_cycle" ] && resume_cycle=1

    # Check cycle-summary.json — if it exists and status is "completed", start next cycle
    local summary_file="$last_cycle_dir/cycle-summary.json"
    if [ -f "$summary_file" ]; then
        local status
        status=$(jq -r '.status // "unknown"' "$summary_file" 2>/dev/null || echo "unknown")
        if [ "$status" = "completed" ]; then
            local next_cycle=$((resume_cycle + 1))
            log "EVOLVE" "Last cycle $resume_cycle completed — resuming at cycle $next_cycle"
            echo "${next_cycle}:reflect"
            return 0
        fi
    fi

    # Determine which phase was interrupted by checking for phase files
    local resume_phase="reflect"
    if [ -f "$last_cycle_dir/reflect.json" ]; then
        resume_phase="ideate"
    fi
    if [ -f "$last_cycle_dir/ideate.json" ]; then
        resume_phase="evaluate"
    fi
    if [ -f "$last_cycle_dir/evaluate.json" ]; then
        resume_phase="implement"
    fi
    if [ -f "$last_cycle_dir/implement.json" ]; then
        resume_phase="observe"
    fi
    if [ -f "$last_cycle_dir/observe.json" ]; then
        # All phases completed but cycle-summary missing or failed — re-run observe
        resume_phase="observe"
    fi

    # If IMPLEMENT was interrupted, check for an existing evolution branch
    if [ "$resume_phase" = "implement" ] || [ "$resume_phase" = "observe" ]; then
        local branch_prefix="${EVOLVE_BRANCH_PREFIX:-automaton/evolve-}"
        local evolution_branch
        evolution_branch=$(git branch --list "${branch_prefix}*" 2>/dev/null | head -1 | sed 's/^[* ]*//')
        if [ -n "$evolution_branch" ]; then
            log "EVOLVE" "Found interrupted evolution branch: $evolution_branch"
        fi
    fi

    log "EVOLVE" "Resuming cycle $resume_cycle from phase: $resume_phase"
    echo "${resume_cycle}:${resume_phase}"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution Main Loop (spec-41 §8, §11)
# ---------------------------------------------------------------------------

# Orchestrates the evolution cycle loop: runs _evolve_run_cycle repeatedly
# until convergence, budget exhaustion, cycle limit, pause, or circuit breaker.
# Supports resume via start_cycle and start_phase parameters.
#
# Usage: _evolve_run_loop [start_cycle] [start_phase]
#   start_cycle: cycle number to start from (default: 1)
#   start_phase: phase to resume from within start_cycle (default: reflect)
#                When not "reflect", the cycle runner skips completed phases.
# Returns: 0 on convergence/completion, 1 on error, 2 on budget exhaustion
_evolve_run_loop() {
    local start_cycle="${1:-1}"
    local start_phase="${2:-reflect}"
    local max_cycles="${EVOLVE_MAX_CYCLES:-0}"

    # Override max_cycles from CLI if specified
    if [ "${ARG_CYCLES:-0}" -gt 0 ]; then
        max_cycles="$ARG_CYCLES"
    fi

    log "EVOLVE" "Evolution loop starting (start_cycle=$start_cycle, max_cycles=${max_cycles:-unlimited}, start_phase=$start_phase)"

    # Run safety preflight before starting cycles
    if ! _safety_preflight 2>/dev/null; then
        log "EVOLVE" "Safety preflight failed — cannot start evolution"
        return 1
    fi

    # Ensure constitution exists
    if [ ! -f "$AUTOMATON_DIR/constitution.md" ]; then
        _constitution_create_default 2>/dev/null || true
    fi

    local cycle_id="$start_cycle"
    local exit_reason=""

    while true; do
        # Check cycle limit
        if [ "$max_cycles" -gt 0 ] && [ "$cycle_id" -gt "$((start_cycle + max_cycles - 1))" ]; then
            log "EVOLVE" "Cycle limit reached ($max_cycles cycles)"
            exit_reason="cycle_limit"
            break
        fi

        # Check for pause flag
        if [ -f "$AUTOMATON_DIR/evolution/pause" ]; then
            log "EVOLVE" "Pause flag detected — stopping after current cycle"
            exit_reason="paused"
            break
        fi

        # Check per-cycle budget
        local estimated_remaining=1
        if [ "$max_cycles" -gt 0 ]; then
            estimated_remaining=$((start_cycle + max_cycles - cycle_id))
            [ "$estimated_remaining" -lt 1 ] && estimated_remaining=1
        fi
        if ! _evolve_check_budget "$cycle_id" "$estimated_remaining" >/dev/null 2>&1; then
            log "EVOLVE" "Budget exhausted — stopping evolution"
            exit_reason="budget_exhausted"
            break
        fi

        # Run the cycle
        local cycle_rc=0
        _evolve_run_cycle "$cycle_id" || cycle_rc=$?

        case "$cycle_rc" in
            0)  # Cycle completed successfully
                ;;
            1)  # Phase failure — log but continue to next cycle
                log "EVOLVE" "Cycle $cycle_id had a phase failure — continuing"
                ;;
            2)  # Budget exhaustion mid-cycle
                log "EVOLVE" "Cycle $cycle_id hit budget limit"
                exit_reason="budget_exhausted"
                break
                ;;
            3)  # Circuit breaker tripped
                log "EVOLVE" "Circuit breaker tripped during cycle $cycle_id"
                exit_reason="circuit_breaker"
                break
                ;;
        esac

        # Check convergence after each completed cycle
        local convergence_reason
        if convergence_reason=$(_evolve_check_convergence 2>/dev/null); then
            log "EVOLVE" "Convergence detected: $convergence_reason"
            exit_reason="converged:${convergence_reason}"
            break
        fi

        cycle_id=$((cycle_id + 1))
    done

    # Rebuild garden index and persist state
    _garden_rebuild_index 2>/dev/null || true

    log "EVOLVE" "Evolution loop finished (cycles_run=$((cycle_id - start_cycle + 1)), reason=${exit_reason:-completed})"

    case "$exit_reason" in
        budget_exhausted) return 2 ;;
        circuit_breaker)  return 1 ;;
        *)                return 0 ;;
    esac
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

# Maps a PROMPT_*.md filename to the corresponding native agent name (spec-27).
# Returns the agent name on stdout, or empty string if no mapping exists.
_prompt_to_agent_name() {
    local prompt_file="$1"
    local basename
    basename=$(basename "$prompt_file")

    case "$basename" in
        PROMPT_research.md)       echo "automaton-research" ;;
        PROMPT_plan.md)           echo "automaton-planner" ;;
        PROMPT_build.md)          echo "automaton-builder" ;;
        PROMPT_review.md)         echo "automaton-reviewer" ;;
        PROMPT_self_research.md)  echo "automaton-self-researcher" ;;
        *)                        echo "" ;;
    esac
}

# Extracts only the dynamic context portion for native agent invocation.
# Unlike inject_dynamic_context() which augments the full prompt file,
# this returns just the dynamic content that gets piped to `claude --agent`
# since the static prompt is already in the agent definition file.
_build_dynamic_context_stdin() {
    local prompt_file="$1"
    local dynamic_content=""

    # Bootstrap manifest (spec-37): pre-assembled context from init.sh
    # When bootstrap fails, _format_bootstrap_for_context emits a fallback
    # notice telling the agent to read files manually.
    if [ -n "${BOOTSTRAP_MANIFEST:-}" ] || [ "${BOOTSTRAP_FAILED:-false}" = "true" ]; then
        dynamic_content+=$(_format_bootstrap_for_context "${BOOTSTRAP_MANIFEST:-}")$'\n'
    fi

    dynamic_content+="## Current State"$'\n'
    dynamic_content+=""$'\n'
    dynamic_content+="- Phase: $current_phase"$'\n'
    dynamic_content+="- Iteration: $phase_iteration"$'\n'

    # Build sub-phase context (spec-36)
    if [ "$current_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
        if [ "${build_sub_phase:-implementation}" = "scaffold" ]; then
            dynamic_content+="- Build sub-phase: TEST SCAFFOLD (3a) — iteration $((scaffold_iterations_done + 1))/$EXEC_TEST_SCAFFOLD_ITERATIONS"$'\n'
            dynamic_content+=""$'\n'
            dynamic_content+="**TEST SCAFFOLD MODE**: Write test files ONLY for plan tasks with \`<!-- test: path -->\` annotations. Do NOT implement any features. Tests should fail initially (no implementation exists yet). Commit test files when done."$'\n'
            dynamic_content+="- Test framework: $EXEC_TEST_FRAMEWORK"$'\n'
        else
            dynamic_content+="- Build sub-phase: IMPLEMENTATION (3b)"$'\n'
        fi
    fi

    if [ -f "$AUTOMATON_DIR/budget.json" ]; then
        local remaining
        remaining=$(jq '.tokens_remaining // "unknown"' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "unknown")
        dynamic_content+="- Budget remaining: $remaining tokens"$'\n'
    fi
    dynamic_content+=""$'\n'

    if [ -f "$AUTOMATON_DIR/context_summary.md" ]; then
        dynamic_content+=$(cat "$AUTOMATON_DIR/context_summary.md")$'\n'
        dynamic_content+=""$'\n'
    fi

    if [ "$current_phase" = "build" ] && [ "$phase_iteration" -gt 1 ]; then
        local plan_file="IMPLEMENTATION_PLAN.md"
        if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
            plan_file="$AUTOMATON_DIR/backlog.md"
        fi

        dynamic_content+="## Recent Changes"$'\n'
        dynamic_content+='```'$'\n'
        dynamic_content+=$(git diff --stat HEAD~3 2>/dev/null || echo "No recent changes.")$'\n'
        dynamic_content+='```'$'\n'
        dynamic_content+=""$'\n'

        dynamic_content+="## Current Focus"$'\n'
        if [ -f "$plan_file" ]; then
            dynamic_content+=$(grep '\[ \]' "$plan_file" | head -5 || echo "All tasks complete.")$'\n'
        fi
        dynamic_content+=""$'\n'

        if [ -f "$AUTOMATON_DIR/iteration_memory.md" ]; then
            dynamic_content+="## Recent Iteration History"$'\n'
            dynamic_content+=$(tail -5 "$AUTOMATON_DIR/iteration_memory.md")$'\n'
            dynamic_content+=""$'\n'
        fi

        if [ "$SELF_BUILD_ENABLED" = "true" ] && [ -f "automaton.sh" ]; then
            dynamic_content+="## Codebase Overview (automaton.sh)"$'\n'
            dynamic_content+='```'$'\n'
            dynamic_content+=$(grep -n '^[a-z_]*()' automaton.sh | head -40 || true)$'\n'
            dynamic_content+='```'$'\n'
            dynamic_content+=""$'\n'
        fi
    fi

    echo "$dynamic_content"
}

# Centralized agent invocation. Pipes the given prompt file into `claude -p`
# with stream-json output, the specified model, and configured flags.
# When agents.use_native_definitions is true (spec-27), invokes
# `claude --agent <name>` instead, piping only dynamic context via stdin.
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

    # Bootstrap (spec-37): pre-assemble context before agent invocation.
    # _run_bootstrap returns exit 1 on failure; || catches it for set -e safety.
    # Metrics are written to bootstrap_metrics.json inside the $() subshell
    # and read back here since globals don't survive subshell boundaries.
    BOOTSTRAP_MANIFEST=""
    BOOTSTRAP_FAILED="false"
    BOOTSTRAP_TIME_MS=0
    BOOTSTRAP_TOKENS_SAVED=0
    BOOTSTRAP_MANIFEST=$(_run_bootstrap) || BOOTSTRAP_FAILED="true"
    # Read metrics persisted by _run_bootstrap (survives subshell)
    if [ -f "$AUTOMATON_DIR/bootstrap_metrics.json" ]; then
        BOOTSTRAP_TIME_MS=$(jq -r '.time_ms // 0' "$AUTOMATON_DIR/bootstrap_metrics.json" 2>/dev/null || echo 0)
        BOOTSTRAP_TOKENS_SAVED=$(jq -r '.tokens_saved // 0' "$AUTOMATON_DIR/bootstrap_metrics.json" 2>/dev/null || echo 0)
        rm -f "$AUTOMATON_DIR/bootstrap_metrics.json"
    fi
    if [ -n "$BOOTSTRAP_MANIFEST" ]; then
        log "ORCHESTRATOR" "Bootstrap manifest assembled ($(echo "$BOOTSTRAP_MANIFEST" | wc -c | tr -d ' ') bytes, ${BOOTSTRAP_TIME_MS}ms, ~${BOOTSTRAP_TOKENS_SAVED} tokens saved)"
    fi

    # Native agent definitions (spec-27): invoke claude --agent with dynamic
    # context piped via stdin. The static prompt lives in the agent definition
    # file under .claude/agents/.
    if [ "$AGENTS_USE_NATIVE_DEFINITIONS" = "true" ]; then
        local agent_name
        agent_name=$(_prompt_to_agent_name "$prompt_file")

        if [ -z "$agent_name" ]; then
            log "ORCHESTRATOR" "ERROR: No native agent mapping for: $prompt_file"
            AGENT_RESULT=""
            AGENT_EXIT_CODE=1
            return 0
        fi

        local dynamic_context
        dynamic_context=$(_build_dynamic_context_stdin "$prompt_file")

        local cmd_args=("--agent" "$agent_name" "--output-format" "stream-json" "--model" "$model")

        if [ "$FLAG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
            cmd_args+=("--dangerously-skip-permissions")
        fi

        if [ "$FLAG_VERBOSE" = "true" ]; then
            cmd_args+=("--verbose")
        fi

        log "ORCHESTRATOR" "Invoking native agent: name=$agent_name model=$model"

        AGENT_RESULT=""
        AGENT_EXIT_CODE=0

        AGENT_RESULT=$(echo "$dynamic_context" | claude "${cmd_args[@]}" 2>&1) || AGENT_EXIT_CODE=$?

        log "ORCHESTRATOR" "Agent finished: exit_code=$AGENT_EXIT_CODE"
        return 0
    fi

    # Legacy mode: pipe full prompt to claude -p
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

    # Check if static prefix meets minimum cacheable threshold (spec-30)
    check_cache_prefix_threshold "$effective_prompt" "$model"

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
ARG_BUDGET_CHECK=false
ARG_HEALTH=false
ARG_EVOLVE=false
ARG_CYCLES=0
ARG_PLANT=""
ARG_GARDEN=false
ARG_GARDEN_DETAIL=""
ARG_WATER_ID=""
ARG_WATER_EVIDENCE=""
ARG_PRUNE_ID=""
ARG_PRUNE_REASON=""
ARG_PROMOTE=""
ARG_INSPECT=""
ARG_CONSTITUTION=false
ARG_AMEND=false
ARG_OVERRIDE=false
ARG_PAUSE_EVOLUTION=false
ARG_SIGNALS=false

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
        --budget-check)
            ARG_BUDGET_CHECK=true
            shift
            ;;
        --health)
            ARG_HEALTH=true
            shift
            ;;
        --evolve)
            ARG_EVOLVE=true
            ARG_SELF=true
            shift
            ;;
        --cycles)
            if [ -z "${2:-}" ] || ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                echo "Error: --cycles requires a positive integer argument." >&2
                exit 1
            fi
            ARG_CYCLES="$2"
            shift 2
            ;;
        --plant)
            ARG_PLANT="${2:-}"
            if [ -z "$ARG_PLANT" ]; then
                echo "Error: --plant requires an idea description argument." >&2
                exit 1
            fi
            shift 2
            ;;
        --garden)
            ARG_GARDEN=true
            shift
            ;;
        --garden-detail)
            ARG_GARDEN_DETAIL="${2:-}"
            if [ -z "$ARG_GARDEN_DETAIL" ]; then
                echo "Error: --garden-detail requires an idea ID argument." >&2
                exit 1
            fi
            shift 2
            ;;
        --water)
            ARG_WATER_ID="${2:-}"
            ARG_WATER_EVIDENCE="${3:-}"
            if [ -z "$ARG_WATER_ID" ] || [ -z "$ARG_WATER_EVIDENCE" ]; then
                echo "Error: --water requires two arguments: ID and evidence." >&2
                exit 1
            fi
            shift 3
            ;;
        --prune)
            ARG_PRUNE_ID="${2:-}"
            ARG_PRUNE_REASON="${3:-}"
            if [ -z "$ARG_PRUNE_ID" ] || [ -z "$ARG_PRUNE_REASON" ]; then
                echo "Error: --prune requires two arguments: ID and reason." >&2
                exit 1
            fi
            shift 3
            ;;
        --promote)
            ARG_PROMOTE="${2:-}"
            if [ -z "$ARG_PROMOTE" ]; then
                echo "Error: --promote requires an idea ID argument." >&2
                exit 1
            fi
            shift 2
            ;;
        --inspect)
            ARG_INSPECT="${2:-}"
            if [ -z "$ARG_INSPECT" ]; then
                echo "Error: --inspect requires an ID argument." >&2
                exit 1
            fi
            shift 2
            ;;
        --constitution)
            ARG_CONSTITUTION=true
            shift
            ;;
        --amend)
            ARG_AMEND=true
            shift
            ;;
        --override)
            ARG_OVERRIDE=true
            shift
            ;;
        --pause-evolution)
            ARG_PAUSE_EVOLUTION=true
            shift
            ;;
        --signals)
            ARG_SIGNALS=true
            shift
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: automaton.sh [OPTIONS]

Multi-phase orchestrator for autonomous Claude agent workflows.

Standard Mode:
  --resume              Resume from saved state (.automaton/state.json)
  --skip-research       Skip Phase 1 (research), start at Phase 2 (plan)
  --skip-review         Skip Phase 4 (review), mark COMPLETE after build
  --config FILE         Use an alternate config file (default: automaton.config.json)
  --dry-run             Load config, run Gate 1, show settings, then exit
  --self                Self-build mode: improve automaton itself (spec-25)
  --self --continue     Auto-pick highest-priority backlog item and run (spec-26)
  --stats               Display run history and performance trends (spec-26)
  --budget-check        Show weekly allowance status without starting a run (spec-35)
  --help, -h            Show this help message

Evolution Mode:
  --evolve              Start autonomous evolution loop (implies --self)
  --evolve --cycles N   Run exactly N evolution cycles
  --evolve --dry-run    Show REFLECT analysis without acting
  --evolve --resume     Resume interrupted evolution

Garden:
  --plant "idea"        Plant a new seed in the garden
  --garden              Display garden summary
  --garden-detail ID    Show full idea details
  --water ID "evidence" Add evidence to an idea
  --prune ID "reason"   Wilt an idea with a reason
  --promote ID          Force-promote idea to bloom

Observation:
  --health              Display health metrics dashboard
  --signals             Display active stigmergic signals
  --inspect ID          Show vote record details

Governance:
  --constitution        Display the current constitution
  --amend               Propose a constitutional amendment
  --override            Override a quorum decision
  --pause-evolution     Pause running evolution loop

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

# --- Apply Max Plan preset (spec-35) ---
# Must run after load_config and CLI overrides since max_plan_preset sets BUDGET_MODE
# to allowance, which cascades into rate limit and parallel default functions below.
_apply_max_plan_preset

# --- Apply rate limit preset (spec-35) ---
# Must run after load_config and CLI overrides since both can change BUDGET_MODE.
_apply_rate_limit_preset

# --- Apply higher parallel defaults for allowance mode (spec-35) ---
# Must run after load_config and CLI overrides since both can change BUDGET_MODE.
_apply_allowance_parallel_defaults

# --- Check parallel-mode dependencies (tmux, git worktree support) ---
# When parallel.enabled is true and mode is "automaton", tmux and git 2.5+ are required.
# When mode is "agent-teams", only CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is required.
# Check after load_config so PARALLEL_ENABLED and PARALLEL_MODE are resolved.
if [ "$PARALLEL_ENABLED" = "true" ]; then
    if [ "${PARALLEL_MODE:-automaton}" = "automaton" ]; then
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
    elif [ "${PARALLEL_MODE:-automaton}" = "agent-teams" ]; then
        # Agent Teams mode: validate version, set env flag, configure display (spec-28 §10)
        setup_agent_teams_environment
    elif [ "${PARALLEL_MODE:-automaton}" = "hybrid" ]; then
        echo "Error: parallel.mode 'hybrid' is reserved for future use and not yet implemented." >&2
        exit 1
    else
        echo "Error: unknown parallel.mode '${PARALLEL_MODE}'. Valid values: automaton, agent-teams, hybrid" >&2
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
        write_run_summary 130 2>/dev/null || true
        commit_persistent_state "${current_phase:-unknown}" "${iteration:-0}" 2>/dev/null || true
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

# Configures .claude/settings.local.json with dynamic hooks (file ownership)
# that change per wave. Called before spawning builders.
# WHY: file ownership hook must reference the current wave's assignments;
# settings.local.json is gitignored and changes each wave. (spec-31 §7)
configure_wave_hooks() {
    local settings_local=".claude/settings.local.json"
    mkdir -p "$(dirname "$settings_local")"

    cat > "$settings_local" <<'HOOKS_EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/enforce-file-ownership.sh",
            "timeout": 5,
            "statusMessage": "Checking file ownership..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": ".claude/hooks/builder-on-stop.sh",
        "timeout": 30,
        "statusMessage": "Finalizing builder results..."
      }
    ]
  }
}
HOOKS_EOF

    log "CONDUCTOR" "Configured file ownership and builder stop hooks in $settings_local"
}

# Removes dynamic hooks from .claude/settings.local.json after a wave completes.
# WHY: file ownership enforcement should only be active during parallel waves;
# single-builder iterations should not be blocked by ownership checks. (spec-31 §7)
cleanup_wave_hooks() {
    local settings_local=".claude/settings.local.json"
    if [ -f "$settings_local" ]; then
        rm -f "$settings_local"
        log "CONDUCTOR" "Removed dynamic hooks from $settings_local"
    fi
}

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
# It reads its assignment from assignments.json, injects builder-specific
# data (builder number, wave, task, file ownership) into the <dynamic_context>
# section of PROMPT_build.md, runs claude -p, extracts tokens from stream-json
# output, determines status (success/error/rate_limited/partial), captures git
# commit and files_changed, calculates duration, and writes a result JSON to
# .automaton/wave/results/builder-N.json.
# WHY: Builder-specific data goes into <dynamic_context> so all builders share
# an identical static prompt prefix, enabling prompt cache reuse across builders.
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

# ---- Inject builder-specific data into <dynamic_context> (spec-30) ----
# All builders share an identical static prompt prefix (everything before
# <dynamic_context>) so the cache entry created by builder-1 is reused by
# builders 2..N, saving 90% on input tokens for subsequent builders.
PROMPT_FILE=$(mktemp)
BUILD_PROMPT="$PROJECT_ROOT/PROMPT_build.md"

# Static prefix: everything up to and including <dynamic_context>
sed -n '1,/<dynamic_context>/p' "$BUILD_PROMPT" > "$PROMPT_FILE"

# Builder-specific dynamic content
cat >> "$PROMPT_FILE" <<DYNAMIC_INJECT
## Builder Assignment

- Builder: $BUILDER_NUM of wave $WAVE_NUM
- Task: $task
- Task line in plan: $task_line

## File Ownership

You may ONLY create or modify these files (and their test files):
$files_owned

Do NOT modify any other files. If your task requires changes to files outside your ownership, note this in your commit message with the prefix "NEEDS:" and complete what you can.

DYNAMIC_INJECT

# Suffix: </dynamic_context> and everything after
sed -n '/<\/dynamic_context>/,$p' "$BUILD_PROMPT" >> "$PROMPT_FILE"

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
elif ! echo "$AGENT_RESULT" | grep -q '<result status="complete">'; then
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
  "promise_complete": $(echo "$AGENT_RESULT" | grep -q '<result status="complete">' && echo "true" || echo "false")
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

    # Step 4: Remove dynamic hooks (file ownership no longer needed)
    cleanup_wave_hooks

    # Step 5: Kill tmux builder windows (suppress errors for non-tmux runs)
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
    local remaining_usd="?" cost_used="?" cost_limit="?" tokens_used="?" cache_ratio_display="?"
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

        # Cache hit ratio: rolling average across all history entries (spec-30)
        local cache_avg
        cache_avg=$(jq '
            [.history[] | .cache_hit_ratio // 0] |
            if length > 0 then ((add / length) * 100 | round) else -1 end
        ' "$budget_file" 2>/dev/null || echo "-1")
        if [ "$cache_avg" != "-1" ] && [ "$cache_avg" -ge 0 ] 2>/dev/null; then
            cache_ratio_display="${cache_avg}%"
        else
            cache_ratio_display="n/a"
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
  Tokens: ${tokens_used} used  │  Cost: \$${cost_used} / \$${cost_limit}  │  Cache: ${cache_ratio_display}
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

# Validates the Claude Code environment for Agent Teams mode (spec-28 §10).
# Sets the experimental feature flag, checks that the installed Claude Code
# version supports Agent Teams, and configures display mode.
#
# WHY: Agent Teams requires an experimental flag and a compatible Claude Code
# version. Validation at startup prevents cryptic failures mid-build. The
# version check is a warning (not a hard failure) because Agent Teams is
# experimental and version detection may be imprecise.
#
# Returns: 0 always (warnings are non-fatal)
setup_agent_teams_environment() {
    # Set the experimental feature flag required by Agent Teams
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

    # Validate Claude Code version supports Agent Teams
    local _claude_version=""
    _claude_version=$(claude --version 2>/dev/null || echo "unknown")

    if [ "$_claude_version" = "unknown" ]; then
        log "WARNING" "Could not determine Claude Code version. Agent Teams may not be supported."
    else
        # Agent Teams requires Claude Code 1.0.0+. Parse major version.
        local _major_ver=""
        _major_ver=$(echo "$_claude_version" | grep -oE '^[0-9]+' | head -1)
        if [ -n "$_major_ver" ] && [ "$_major_ver" -lt 1 ] 2>/dev/null; then
            log "WARNING" "Claude Code version ${_claude_version} may not support Agent Teams. Version 1.0.0+ recommended."
        fi
    fi

    # Configure display mode
    local display_mode="${PARALLEL_TEAMMATE_DISPLAY:-in-process}"
    if [ "$display_mode" = "tmux" ]; then
        # Verify tmux is available for tmux display mode
        if ! command -v tmux >/dev/null 2>&1; then
            log "WARNING" "tmux display mode requested but tmux not installed. Falling back to in-process."
            PARALLEL_TEAMMATE_DISPLAY="in-process"
        fi
    fi

    log "ORCHESTRATOR" "Agent Teams mode enabled (parallel.mode=agent-teams, display=${PARALLEL_TEAMMATE_DISPLAY:-in-process}, claude=${_claude_version})"
}

# Converts unchecked tasks from IMPLEMENTATION_PLAN.md into the Agent Teams
# shared task list format. Parses task descriptions, file annotations
# (<!-- files: ... -->), and dependency annotations (<!-- depends: task-N -->).
# Each task gets a sequential task_id (task-1, task-2, ...) and is marked
# blocked if it depends on another uncompleted task.
#
# WHY: Agent Teams teammates self-claim tasks from a shared list instead of
# receiving pre-assigned wave work. This function bridges the plan format
# to the Agent Teams task model. (spec-28)
#
# Output: writes .automaton/wave/agent_teams_tasks.json
# Returns: 0 on success, 1 if plan file is missing
populate_agent_teams_task_list() {
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    local output_file="$AUTOMATON_DIR/wave/agent_teams_tasks.json"

    if [ ! -f "$plan_file" ]; then
        log "ORCHESTRATOR" "Cannot populate task list: $plan_file not found"
        return 1
    fi

    mkdir -p "$AUTOMATON_DIR/wave"

    # Parse unchecked tasks with their annotations using awk state machine.
    # Tracks the current task and collects <!-- files: --> and <!-- depends: -->
    # annotations on subsequent lines. Emits the task when a non-annotation
    # line is reached or at EOF.
    # Output: tab-separated fields: line_number, task_text, files, depends
    local parsed
    parsed=$(awk '
    function emit_task() {
        if (task_line > 0) {
            print task_line "\t" task_text "\t" files "\t" depends
        }
        task_line = 0; task_text = ""; files = ""; depends = ""
    }
    /^- \[ \]/ {
        emit_task()
        task_line = NR
        task_text = $0
        sub(/^- \[ \] /, "", task_text)
        next
    }
    task_line > 0 && /<!-- files:/ {
        f = $0
        gsub(/.*<!-- files: /, "", f)
        gsub(/ -->.*/, "", f)
        files = f
        next
    }
    task_line > 0 && /<!-- depends:/ {
        d = $0
        gsub(/.*<!-- depends: /, "", d)
        gsub(/ -->.*/, "", d)
        depends = d
        next
    }
    task_line > 0 { emit_task() }
    END { emit_task() }
    ' "$plan_file")

    # Convert parsed output to JSON with task IDs and blocked status
    echo "$parsed" | jq -R -s '
        split("\n") | map(select(. != "")) | to_entries | map(
            .key as $idx |
            .value | split("\t") | {
                task_id: ("task-" + (($idx + 1) | tostring)),
                line: (.[0] | gsub("^\\s+|\\s+$"; "") | tonumber),
                subject: (.[1] | gsub("^\\s+|\\s+$"; "")),
                files: (.[2] | gsub("^\\s+|\\s+$"; "") | split(", ") | map(select(. != ""))),
                depends_on: (.[3] | gsub("^\\s+|\\s+$"; "") | split(", ") | map(select(. != ""))),
                blocked: ((.[3] | gsub("^\\s+|\\s+$"; "")) != ""),
                status: "pending"
            }
        )
    ' > "$output_file"

    local task_count blocked_count
    task_count=$(jq 'length' "$output_file")
    blocked_count=$(jq '[.[] | select(.blocked == true)] | length' "$output_file")

    log "ORCHESTRATOR" "Agent Teams task list: $task_count tasks ($blocked_count blocked by dependencies)"
}

# Builds the claude CLI command array for an Agent Teams session.
# Configures the lead agent, teammate count, display mode, and permissions
# from automaton config. The lead uses the automaton-builder agent definition
# (spec-27) and teammates inherit the same definition.
#
# WHY: Centralizes command construction so run_agent_teams_build() stays
# focused on orchestration. Teammates use the same agent definition as
# wave-based builders, ensuring identical behavior. (spec-28 §4)
#
# Output: prints space-separated command arguments to stdout
# Usage: cmd_args=$(build_agent_teams_command)
build_agent_teams_command() {
    local agent_name="automaton-builder"
    local display_mode="${PARALLEL_TEAMMATE_DISPLAY:-in-process}"
    local num_teammates="${MAX_BUILDERS:-3}"

    local args=("--agent" "$agent_name")
    args+=("--num-teammates" "$num_teammates")
    args+=("--output-format" "stream-json")

    # Display mode: in-process (default) or tmux
    if [ "$display_mode" = "tmux" ]; then
        args+=("--display-mode" "tmux")
    else
        args+=("--display-mode" "in-process")
    fi

    # Permission mode: inherited from lead. When the orchestrator uses
    # --dangerously-skip-permissions, teammates inherit the same mode.
    if [ "${FLAG_DANGEROUSLY_SKIP_PERMISSIONS:-false}" = "true" ]; then
        args+=("--dangerously-skip-permissions")
    fi

    if [ "${FLAG_VERBOSE:-false}" = "true" ]; then
        args+=("--verbose")
    fi

    echo "${args[@]}"
}

# Agent Teams build phase (spec-28). Uses the Claude Code Agent Teams API
# instead of tmux + worktree wave orchestration. Teammates self-claim tasks
# Aggregates budget from Agent Teams session using subagent_usage.json
# (populated by SubagentStart/SubagentStop hooks from spec-31) and the
# lead session's stream-json token output.
#
# WHY: Agent Teams does not expose per-teammate stream-json token usage.
# This function reads subagent_usage.json for individual teammate data
# when available, and falls back to dividing the lead session's aggregate
# tokens by teammate count for approximate per-teammate attribution.
# (spec-28 §9)
#
# Usage: aggregate_agent_teams_budget
# Reads: .automaton/subagent_usage.json, LAST_INPUT_TOKENS, LAST_OUTPUT_TOKENS
# Writes: budget.json via update_budget()
aggregate_agent_teams_budget() {
    local usage_file="$AUTOMATON_DIR/subagent_usage.json"
    local teammate_count="${MAX_BUILDERS:-3}"

    log "ORCHESTRATOR" "Per-teammate token attribution is approximate in agent-teams mode"

    # If subagent_usage.json does not exist, fall through to lead session fallback
    if [ -f "$usage_file" ]; then
        local completed_entries
        completed_entries=$(jq '[.[] | select(.status == "completed")] | length' "$usage_file" 2>/dev/null || echo 0)

        if [ "$completed_entries" -gt 0 ]; then
            log "ORCHESTRATOR" "Agent Teams budget: found $completed_entries completed subagent entries in subagent_usage.json"

            # Process each completed subagent entry
            local i=0
            while [ "$i" -lt "$completed_entries" ]; do
                local entry
                entry=$(jq --argjson idx "$i" '[.[] | select(.status == "completed")][$idx]' "$usage_file" 2>/dev/null)

                local agent_name input output cache_create cache_read
                agent_name=$(jq -r '.agent_name // "teammate"' <<< "$entry")
                input=$(jq '.tokens.input // 0' <<< "$entry")
                output=$(jq '.tokens.output // 0' <<< "$entry")
                cache_create=$(jq '.tokens.cache_create // 0' <<< "$entry")
                cache_read=$(jq '.tokens.cache_read // 0' <<< "$entry")

                # Skip entries with zero tokens (hook didn't capture usage)
                if [ "$input" -eq 0 ] && [ "$output" -eq 0 ]; then
                    i=$((i + 1))
                    continue
                fi

                local cost duration
                cost=$(estimate_cost "$MODEL_BUILDING" "$input" "$output" "$cache_create" "$cache_read")

                local started_at stopped_at
                started_at=$(jq -r '.started_at // empty' <<< "$entry")
                stopped_at=$(jq -r '.stopped_at // empty' <<< "$entry")
                duration=0
                if [ -n "$started_at" ] && [ -n "$stopped_at" ]; then
                    local start_epoch stop_epoch
                    start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
                    stop_epoch=$(date -d "$stopped_at" +%s 2>/dev/null || echo 0)
                    if [ "$start_epoch" -gt 0 ] && [ "$stop_epoch" -gt 0 ]; then
                        duration=$((stop_epoch - start_epoch))
                    fi
                fi

                update_budget "$MODEL_BUILDING" "$input" "$output" \
                    "$cache_create" "$cache_read" \
                    "$cost" "$duration" "agent-teams ${agent_name}" "success"

                i=$((i + 1))
            done
            return 0
        fi
    fi

    # Fallback: no subagent_usage.json or no completed entries.
    # Use the lead session's aggregate tokens (LAST_INPUT_TOKENS etc.)
    # divided by teammate count as approximate per-teammate attribution.
    local lead_input="${LAST_INPUT_TOKENS:-0}"
    local lead_output="${LAST_OUTPUT_TOKENS:-0}"
    local lead_cache_create="${LAST_CACHE_CREATE:-0}"
    local lead_cache_read="${LAST_CACHE_READ:-0}"

    if [ "$lead_input" -eq 0 ] && [ "$lead_output" -eq 0 ]; then
        log "ORCHESTRATOR" "WARN: No token data available for agent-teams budget tracking"
        return 0
    fi

    log "ORCHESTRATOR" "Agent Teams budget fallback: dividing lead aggregate by $teammate_count teammates"

    # Divide aggregate tokens among teammates for approximate attribution
    local per_teammate_input per_teammate_output per_teammate_cc per_teammate_cr
    per_teammate_input=$((lead_input / teammate_count))
    per_teammate_output=$((lead_output / teammate_count))
    per_teammate_cc=$((lead_cache_create / teammate_count))
    per_teammate_cr=$((lead_cache_read / teammate_count))

    local t=1
    while [ "$t" -le "$teammate_count" ]; do
        local cost
        cost=$(estimate_cost "$MODEL_BUILDING" "$per_teammate_input" "$per_teammate_output" \
            "$per_teammate_cc" "$per_teammate_cr")

        update_budget "$MODEL_BUILDING" "$per_teammate_input" "$per_teammate_output" \
            "$per_teammate_cc" "$per_teammate_cr" \
            "$cost" "0" "agent-teams teammate-${t} (approximate)" "success"

        t=$((t + 1))
    done
}

# Saves Agent Teams task list state for resume after interruption.
#
# WHY: Agent Teams has no session resumption — if interrupted, the team
# cannot be restarted where it left off. Saving task state enables the
# orchestrator to re-create the team with only remaining tasks on --resume.
# (spec-28 §8: no session resumption mitigation)
#
# Output: writes .automaton/agent_teams_state.json (persistent, git-tracked)
save_agent_teams_state() {
    local task_file="$AUTOMATON_DIR/wave/agent_teams_tasks.json"
    local state_file="$AUTOMATON_DIR/agent_teams_state.json"

    if [ ! -f "$task_file" ]; then
        log "ORCHESTRATOR" "No task list to save for Agent Teams state"
        return 0
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg ts "$timestamp" '
        map(. + {saved_at: $ts})
    ' "$task_file" > "$state_file"

    log "ORCHESTRATOR" "Saved Agent Teams task state to $state_file"
}

# Restores saved Agent Teams task state for resume.
#
# WHY: On --resume after interruption, the orchestrator re-creates the
# Agent Teams session with only pending/incomplete tasks from the saved
# state, skipping already-completed work. (spec-28 §8)
#
# Output: prints JSON array of saved tasks to stdout
# Returns: always 0 (empty array if no state)
restore_agent_teams_state() {
    local state_file="$AUTOMATON_DIR/agent_teams_state.json"

    if [ ! -f "$state_file" ]; then
        echo "[]"
        return 0
    fi

    cat "$state_file"
}

# Verifies Agent Teams task completions against actual git changes.
#
# WHY: Agent Teams has a "task status lag" limitation — teammates sometimes
# fail to mark tasks complete even though they did the work. This function
# cross-references completed tasks against git diff to detect mismatches.
# Tasks marked complete but with no corresponding file changes are flagged.
# (spec-28 §8: task status lag mitigation)
#
# Args: $1 — git ref to diff against (e.g. HEAD~5 or a commit sha)
# Output: prints JSON array with verification results to stdout
verify_agent_teams_completions() {
    local diff_base="${1:-HEAD~1}"
    local task_file="$AUTOMATON_DIR/wave/agent_teams_tasks.json"

    if [ ! -f "$task_file" ]; then
        echo "[]"
        return 0
    fi

    local changed_files
    changed_files=$(git diff --name-only "$diff_base" HEAD 2>/dev/null || echo "")

    jq --arg changed "$changed_files" '
        ($changed | split("\n") | map(select(. != ""))) as $diffs |
        map(
            if .status == "completed" then
                if (.files | length) == 0 then
                    . + {verified: "unverifiable", reason: "no file list for task"}
                elif ([.files[] | select(. as $f | $diffs | any(. == $f))] | length) > 0 then
                    . + {verified: true}
                else
                    . + {verified: false, reason: "no matching changes in git diff"}
                end
            else
                . + {verified: "not_completed"}
            end
        )
    ' "$task_file"
}

# Documents Agent Teams limitations and their mitigations.
#
# WHY: Informed users can choose the right parallel mode for their project.
# Limitations are logged at session start so operators understand the
# trade-offs of agent-teams mode vs automaton mode. (spec-28 §8)
#
# Output: prints limitation summary to stdout
document_agent_teams_limitations() {
    cat << 'LIMITATIONS'
Agent Teams Limitations (spec-28 §8):

1. no session resumption — Cannot resume Agent Teams after interrupt.
   Mitigation: orchestrator saves task list state; re-creates team on --resume.

2. task status lag — Teammates may fail to mark tasks complete.
   Mitigation: post-build verification against git diff detects unacknowledged work.

3. no nested teams — Teammates cannot create sub-teams.
   Mitigation: single level of parallelism only.

4. One team per session — Cannot run multiple teams concurrently.
   Mitigation: sequential team sessions for multi-wave scenarios.

5. Lead is fixed — Cannot promote teammate to lead.
   Mitigation: lead must be the orchestrator's build agent.

6. Permissions at spawn — Cannot change teammate permissions after creation.
   Mitigation: set correctly at spawn time.

7. shared working tree — No worktree isolation by default (conflict risk).
   Mitigation: file ownership hooks (spec-31) prevent concurrent writes to same files.
LIMITATIONS
}

# from a shared task list populated from IMPLEMENTATION_PLAN.md.
#
# WHY: Agent Teams provides native parallel execution with self-claiming,
# inter-agent messaging, and lifecycle hooks — replacing bash-orchestrated
# tmux windows and manual worktree management.
#
# Returns: 0 on completion, non-zero on failure
run_agent_teams_build() {
    log "ORCHESTRATOR" "Starting Agent Teams build (mode=agent-teams, builders=${MAX_BUILDERS}, display=${PARALLEL_TEAMMATE_DISPLAY:-in-process})"

    # Log known limitations (spec-28 §8) so operators understand trade-offs
    document_agent_teams_limitations | while IFS= read -r line; do
        log "ORCHESTRATOR" "$line"
    done

    # Ensure the experimental flag is set
    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

    # Check for saved state from a previous interrupted session (resume mitigation)
    local saved_state
    saved_state=$(restore_agent_teams_state)
    local saved_count
    saved_count=$(echo "$saved_state" | jq 'length' 2>/dev/null || echo 0)
    if [ "$saved_count" -gt 0 ]; then
        local completed_in_saved
        completed_in_saved=$(echo "$saved_state" | jq '[.[] | select(.status == "completed")] | length')
        log "ORCHESTRATOR" "Restored Agent Teams state: $saved_count tasks ($completed_in_saved previously completed)"
    fi

    # Record git HEAD before session for post-build verification
    local pre_build_head
    pre_build_head=$(git rev-parse HEAD 2>/dev/null || echo "")

    # Populate the shared task list from the implementation plan
    populate_agent_teams_task_list

    local task_list_file="$AUTOMATON_DIR/wave/agent_teams_tasks.json"
    local task_count
    task_count=$(jq 'length' "$task_list_file" 2>/dev/null || echo 0)

    if [ "$task_count" -eq 0 ]; then
        log "ORCHESTRATOR" "No unchecked tasks remain — skipping Agent Teams session"
        return 0
    fi

    # Build the claude command with teammate configuration
    local cmd_args_str
    cmd_args_str=$(build_agent_teams_command)

    # Convert the space-separated string back into an array
    local -a cmd_args
    read -ra cmd_args <<< "$cmd_args_str"

    log "ORCHESTRATOR" "Spawning Agent Teams session: claude ${cmd_args[*]}"

    # Assemble dynamic context for the lead agent, including the task list.
    # The lead distributes tasks to teammates via the shared task list.
    local dynamic_context=""
    dynamic_context+="## Agent Teams Build Session"$'\n'
    dynamic_context+=""$'\n'
    dynamic_context+="You are the lead of an Agent Teams session with ${MAX_BUILDERS} teammates."$'\n'
    dynamic_context+="Teammates use the automaton-builder agent definition and self-claim tasks."$'\n'
    dynamic_context+=""$'\n'
    dynamic_context+="### Shared Task List"$'\n'
    dynamic_context+=""$'\n'
    dynamic_context+="$(cat "$task_list_file")"$'\n'
    dynamic_context+=""$'\n'
    dynamic_context+="### Instructions"$'\n'
    dynamic_context+=""$'\n'
    dynamic_context+="Distribute these tasks to your teammates. Each teammate should claim"$'\n'
    dynamic_context+="and implement one task at a time. Blocked tasks (blocked=true) must"$'\n'
    dynamic_context+="wait until their dependencies are complete."$'\n'

    # Launch the Agent Teams session
    local agent_result=""
    local agent_exit_code=0

    agent_result=$(echo "$dynamic_context" | claude "${cmd_args[@]}" 2>&1) || agent_exit_code=$?

    log "ORCHESTRATOR" "Agent Teams session finished: exit_code=$agent_exit_code"

    if [ "$agent_exit_code" -ne 0 ]; then
        log "ORCHESTRATOR" "WARN: Agent Teams session exited with code $agent_exit_code"
    fi

    # Extract tokens from the lead session output for fallback attribution
    extract_tokens "$agent_result"

    # Aggregate budget from subagent hooks or lead session (spec-28 §9)
    aggregate_agent_teams_budget

    # Save task list state for resume (spec-28 §8: no session resumption mitigation)
    save_agent_teams_state

    # Post-build verification against git diff (spec-28 §8: task status lag mitigation)
    if [ -n "$pre_build_head" ]; then
        local verification
        verification=$(verify_agent_teams_completions "$pre_build_head")
        local unverified_count
        unverified_count=$(echo "$verification" | jq '[.[] | select(.verified == false)] | length' 2>/dev/null || echo 0)
        if [ "$unverified_count" -gt 0 ]; then
            log "ORCHESTRATOR" "WARN: $unverified_count task(s) marked complete but no matching file changes detected (task status lag)"
            echo "$verification" | jq -r '.[] | select(.verified == false) | "  - \(.task_id): \(.subject)"' | while IFS= read -r line; do
                log "ORCHESTRATOR" "  Unverified: $line"
            done
        fi
    fi

    return 0
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
    # Test scaffold sub-phase (spec-36): run single-builder iterations for
    # test scaffolding before starting parallel implementation waves.
    if [ "$EXEC_TEST_FIRST_ENABLED" = "true" ] && [ "${build_sub_phase:-implementation}" = "scaffold" ]; then
        log "CONDUCTOR" "Running test scaffold sub-phase (3a) as single-builder before parallel waves"
        while [ "${build_sub_phase}" = "scaffold" ] && [ "$scaffold_iterations_done" -lt "$EXEC_TEST_SCAFFOLD_ITERATIONS" ]; do
            if ! run_single_builder_iteration; then
                log "CONDUCTOR" "Test scaffold iteration failed, proceeding to implementation"
                break
            fi
            scaffold_iterations_done=$((scaffold_iterations_done + 1))
            log "ORCHESTRATOR" "Test scaffold iteration $scaffold_iterations_done/$EXEC_TEST_SCAFFOLD_ITERATIONS complete"
        done
        build_sub_phase="implementation"
        log "ORCHESTRATOR" "Test scaffold sub-phase (3a) complete. Transitioning to parallel implementation (3b)."
        write_state
    fi

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

        # --- Step 4a: Configure dynamic hooks for this wave (spec-31) ---
        configure_wave_hooks

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
    # Check for both legacy (<promise>COMPLETE</promise>) and spec-29
    # (<result status="complete">) completion signals for backward compatibility
    echo "$AGENT_RESULT" | grep -qE 'COMPLETE</promise>|<result status="complete">'
}

# Emits a one-line inter-iteration status per spec-01 format.
# Includes cache hit ratio for the current iteration (spec-30).
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

    # Calculate per-iteration cache hit ratio from last token extraction (spec-30)
    local cache_pct="n/a"
    local cr=${LAST_CACHE_READ:-0} inp=${LAST_INPUT_TOKENS:-0} cc=${LAST_CACHE_CREATE:-0}
    local cache_denom=$((cr + inp + cc))
    if [ "$cache_denom" -gt 0 ] 2>/dev/null; then
        cache_pct="$(awk -v cr="$cr" -v d="$cache_denom" 'BEGIN{printf "%d%%", (cr/d)*100}')"
    fi

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Allowance mode: show input/output tokens and remaining allowance (spec-30 §7)
        # Note: cache reduces USD cost but NOT allowance consumption (token-based)
        local tokens_remaining tokens_display
        tokens_remaining=$(jq '.tokens_remaining' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
        if [ "$tokens_remaining" != "?" ] && [ "$tokens_remaining" -ge 1000000 ] 2>/dev/null; then
            tokens_display="$((tokens_remaining / 1000000))M"
        elif [ "$tokens_remaining" != "?" ] && [ "$tokens_remaining" -ge 1000 ] 2>/dev/null; then
            tokens_display="$((tokens_remaining / 1000))K"
        else
            tokens_display="$tokens_remaining"
        fi

        local inp_display out_display
        if [ "${LAST_INPUT_TOKENS:-0}" -ge 1000 ] 2>/dev/null; then
            inp_display="$(awk -v t="${LAST_INPUT_TOKENS:-0}" 'BEGIN{printf "%dK", t/1000}')"
        else
            inp_display="${LAST_INPUT_TOKENS:-0}"
        fi
        if [ "${LAST_OUTPUT_TOKENS:-0}" -ge 1000 ] 2>/dev/null; then
            out_display="$(awk -v t="${LAST_OUTPUT_TOKENS:-0}" 'BEGIN{printf "%dK", t/1000}')"
        else
            out_display="${LAST_OUTPUT_TOKENS:-0}"
        fi

        echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ${inp_display}/${out_display} tokens | cache: ${cache_pct} | allowance: ${tokens_display} remaining (cache saves cost, not tokens)"
    else
        remaining_budget=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
            "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
        echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ~\$${iter_cost} | cache: ${cache_pct} | budget: \$${remaining_budget} remaining"
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

# Set by mitigate_compaction() when auto-compaction is detected. When true,
# inject_dynamic_context() omits verbose sections to keep the prompt lean.
COMPACTION_REDUCE_CONTEXT=false

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

    # 1a. Detect auto-compaction (spec-33: token count drops between turns)
    detect_auto_compaction "$AGENT_RESULT"

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

    # 4a. Check cache hit ratio (spec-30: warn when rolling avg < 50% after 3+ iters)
    check_cache_hit_ratio

    # 4b. Check context utilization against per-phase ceiling (spec-33)
    check_context_utilization "$LAST_INPUT_TOKENS" "$LAST_OUTPUT_TOKENS" "$model"

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

        # Periodic persistent state checkpoint every 5 build iterations (spec-34)
        if [ "$phase_iteration" -gt 0 ] && [ $((phase_iteration % 5)) -eq 0 ]; then
            commit_persistent_state "build" "$iteration"
        fi
    fi

    # 8. Persist state
    write_state

    # 8a. Generate progress.txt for cross-window state awareness (spec-33)
    generate_progress_txt

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
        "$iter_cost" "$task_desc" "$status" "$files_changed" "$git_commit" \
        "$LAST_AUTO_COMPACTION_DETECTED"

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

    # Regenerate AGENTS.md from learnings.json + project metadata (spec-34)
    generate_agents_md

    phase_history=$(echo "$phase_history" | jq -c \
        --arg p "$current_phase" --arg t "$now" \
        '. + [{"phase": $p, "completed_at": $t}]')

    current_phase="$new_phase"
    phase_iteration=0
    PHASE_START_TIME=$(date +%s)

    # Initialize build sub-phase when entering build (spec-36)
    if [ "$new_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
        build_sub_phase="scaffold"
        scaffold_iterations_done=0
        log "ORCHESTRATOR" "Test-first enabled: starting with test scaffold sub-phase (3a), max ${EXEC_TEST_SCAFFOLD_ITERATIONS} iterations, framework=${EXEC_TEST_FRAMEWORK}"
    else
        build_sub_phase="implementation"
        scaffold_iterations_done=0
    fi

    log "ORCHESTRATOR" "Phase transition → $new_phase"
    write_state

    # Commit persistent state at phase transitions (spec-34)
    commit_persistent_state "$current_phase" "$iteration"
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

    # --- Daily budget pacing check (spec-35) ---
    _check_daily_budget_pacing

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

        # === Build phase: parallel vs single-builder (spec-14, spec-15, spec-28) ===
        # When parallel.enabled is true:
        #   - mode "automaton": wave-based conductor loop (tmux + worktrees)
        #   - mode "agent-teams": Agent Teams API (shared task list, self-claiming)
        # When parallel.enabled is false, behavior is identical to v1 single-builder.
        if [ "$current_phase" = "build" ] && [ "$PARALLEL_ENABLED" = "true" ]; then
            if [ "${PARALLEL_MODE:-automaton}" = "agent-teams" ]; then
                run_agent_teams_build
            else
                run_parallel_build
            fi
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

            # Safety ceiling for unlimited build phases (gap #4).
            # When max_iter=0, the build loop is unbounded. This prevents
            # runaway execution by forcing a transition to review after
            # BUILD_SAFETY_CEILING iterations.
            if [ "$max_iter" -eq 0 ] && [ "$current_phase" = "build" ] \
                    && [ "$phase_iteration" -gt "$BUILD_SAFETY_CEILING" ]; then
                log "ORCHESTRATOR" "WARNING: Build safety ceiling reached ($BUILD_SAFETY_CEILING iterations). Forcing transition to review."
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

            # Test scaffold sub-phase transition (spec-36)
            if [ "$current_phase" = "build" ] && [ "${build_sub_phase:-implementation}" = "scaffold" ]; then
                scaffold_iterations_done=$((scaffold_iterations_done + 1))
                if [ "$scaffold_iterations_done" -ge "$EXEC_TEST_SCAFFOLD_ITERATIONS" ]; then
                    build_sub_phase="implementation"
                    log "ORCHESTRATOR" "Test scaffold sub-phase (3a) complete after $scaffold_iterations_done iterations. Transitioning to implementation (3b)."
                    write_state
                else
                    log "ORCHESTRATOR" "Test scaffold iteration $scaffold_iterations_done/$EXEC_TEST_SCAFFOLD_ITERATIONS complete"
                fi
                # During scaffold, agent completion signal means scaffold is done early
                if agent_signaled_complete && [ "${build_sub_phase}" = "scaffold" ]; then
                    build_sub_phase="implementation"
                    log "ORCHESTRATOR" "Agent signaled scaffold COMPLETE early. Transitioning to implementation (3b)."
                    write_state
                fi
                continue
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
                # Gate 2: research completeness (hardened).
                # On fail: retry research if within max iterations, then warn and proceed.
                # Counts remaining TBDs so the log message is actionable.
                if gate_check "research_completeness"; then
                    transition_to_phase "plan"
                else
                    research_gate_failures=$((${research_gate_failures:-0} + 1))
                    local remaining_tbds
                    remaining_tbds=$(grep -ri 'TBD\|TODO' specs/ 2>/dev/null | wc -l)
                    if [ "$research_gate_failures" -lt 2 ] && [ "$phase_iteration" -lt "$max_iter" ]; then
                        log "ORCHESTRATOR" "Research gate failed ($remaining_tbds TBDs remaining). Retrying research (attempt $((research_gate_failures + 1)))."
                        # Don't transition — stay in research for another iteration
                    else
                        log "ORCHESTRATOR" "WARNING: Research gate failed with $remaining_tbds TBDs remaining. Max retries exhausted. Proceeding to plan with unresolved ambiguity."
                        transition_to_phase "plan"
                    fi
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
                # Gate 5: review pass. On fail: back to build.
                # After 2 failures: attempt focused fix. After 3: terminal escalate.
                if gate_check "review_pass"; then
                    transition_to_phase "COMPLETE"
                else
                    review_attempts=$((review_attempts + 1))
                    if [ "$review_attempts" -ge 3 ]; then
                        # Terminal escalation after focused fix also failed
                        escalate "Review failed after $review_attempts attempts (including focused fix). Human intervention required."
                    elif [ "$review_attempts" -eq 2 ]; then
                        # Focused fix strategy: extract only failing issues and create
                        # a minimal targeted task list for one more build cycle
                        log "ORCHESTRATOR" "Review failed twice. Attempting focused fix strategy (attempt 3/3)."
                        attempt_focused_fix
                        stall_count=0
                        transition_to_phase "build"
                    else
                        log "ORCHESTRATOR" "Review failed ($review_attempts/3). Returning to build."
                        stall_count=0
                        transition_to_phase "build"
                    fi
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

    # Write persistent run summary (spec-34)
    write_run_summary 0

    # Commit persistent state at run completion (spec-34)
    commit_persistent_state "$current_phase" "$iteration"

    # Archive run to journal (spec-26)
    archive_run_journal

    log "ORCHESTRATOR" "Run complete."
    exit 0
}

# --- Budget check mode (spec-35) ---
if [ "$ARG_BUDGET_CHECK" = "true" ]; then
    display_budget_check
fi

# --- Health dashboard mode (spec-43) ---
if [ "$ARG_HEALTH" = "true" ]; then
    _metrics_display_health
    exit 0
fi

# --- --garden display mode (spec-44) ---
if [ "$ARG_GARDEN" = "true" ]; then
    _display_garden
    exit 0
fi

# --- Garden detail mode (spec-44) ---
if [ -n "$ARG_GARDEN_DETAIL" ]; then
    _display_garden_detail "$ARG_GARDEN_DETAIL"
    exit 0
fi

# --- Signals display mode (spec-44) ---
if [ "$ARG_SIGNALS" = "true" ]; then
    _display_signals
    exit 0
fi

# --- Vote inspection mode (spec-44) ---
if [ -n "$ARG_INSPECT" ]; then
    _display_vote "$ARG_INSPECT"
    exit 0
fi

# --- Constitution display mode (spec-44) ---
if [ "$ARG_CONSTITUTION" = "true" ]; then
    _display_constitution
    exit 0
fi

# --- Plant seed mode (spec-44) ---
if [ -n "$ARG_PLANT" ]; then
    _cli_plant "$ARG_PLANT"
    exit 0
fi

# --- Water idea mode (spec-44) ---
if [ -n "$ARG_WATER_ID" ]; then
    _cli_water "$ARG_WATER_ID" "$ARG_WATER_EVIDENCE"
    exit 0
fi

# --- Prune idea mode (spec-44) ---
if [ -n "$ARG_PRUNE_ID" ]; then
    _cli_prune "$ARG_PRUNE_ID" "$ARG_PRUNE_REASON"
    exit 0
fi

# --- Promote idea mode (spec-44) ---
if [ -n "$ARG_PROMOTE" ]; then
    _cli_promote "$ARG_PROMOTE"
    exit 0
fi

# --- Amend constitution mode (spec-44) ---
if [ "$ARG_AMEND" = "true" ]; then
    _cli_amend
    exit 0
fi

# --- Override quorum mode (spec-44) ---
if [ "$ARG_OVERRIDE" = "true" ]; then
    _cli_override
    exit 0
fi

# --- Pause evolution mode (spec-44) ---
if [ "$ARG_PAUSE_EVOLUTION" = "true" ]; then
    _cli_pause
    exit 0
fi

# --- Evolution mode (spec-41) ---
if [ "$ARG_EVOLVE" = "true" ]; then
    log "ORCHESTRATOR" "Evolution mode activated (--evolve implies --self)"
    if [ "$ARG_CYCLES" -gt 0 ]; then
        log "ORCHESTRATOR" "Evolution limited to $ARG_CYCLES cycles"
    fi

    # Initialize state (creates .automaton/ directory, garden, signals, etc.)
    initialize

    # Determine start point: resume or fresh
    local evolve_start_cycle=1
    local evolve_start_phase="reflect"
    if [ "$ARG_RESUME" = "true" ]; then
        local resume_info
        if resume_info=$(_evolve_resume_state); then
            evolve_start_cycle="${resume_info%%:*}"
            evolve_start_phase="${resume_info##*:}"
            log "ORCHESTRATOR" "Evolution resume: cycle=$evolve_start_cycle, phase=$evolve_start_phase"
        else
            log "ORCHESTRATOR" "No previous evolution state — starting fresh"
        fi
    fi

    # Run the evolution loop
    local evolve_rc=0
    _evolve_run_loop "$evolve_start_cycle" "$evolve_start_phase" || evolve_rc=$?

    case "$evolve_rc" in
        0) log "ORCHESTRATOR" "Evolution completed successfully"; exit 0 ;;
        2) log "ORCHESTRATOR" "Evolution stopped: budget exhausted (resumable with --evolve --resume)"; exit 2 ;;
        *) log "ORCHESTRATOR" "Evolution stopped with errors"; exit 1 ;;
    esac
fi

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
    echo "    preset:        ${RATE_LIMIT_PRESET}"
    echo "    tokens/min:    ${RATE_TOKENS_PER_MINUTE}"
    echo "    requests/min:  ${RATE_REQUESTS_PER_MINUTE}"
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
