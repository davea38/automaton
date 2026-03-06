#\!/usr/bin/env bash
# lib/config.sh — Configuration loading, validation, setup wizard, and presets.
# Spec references: spec-12 (config defaults), spec-35 (allowance presets),
#                  spec-48 (doctor check), spec-50 (config validation),
#                  spec-57 (setup wizard), spec-59 (requirements wizard)
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

        # -- output truncation (spec-49) --
        OUTPUT_MAX_LINES=$(jq -r '.execution.output_max_lines // 200' "$config_file")
        OUTPUT_HEAD_LINES=$(jq -r '.execution.output_head_lines // 50' "$config_file")
        OUTPUT_TAIL_LINES=$(jq -r '.execution.output_tail_lines // 150' "$config_file")

        # -- QA validation loop (spec-46) --
        QA_ENABLED=$(jq -r '.execution.qa_enabled // true' "$config_file")
        QA_MAX_ITERATIONS=$(jq -r '.execution.qa_max_iterations // 5' "$config_file")
        QA_BLIND_VALIDATION=$(jq -r '.execution.qa_blind_validation // false' "$config_file")
        QA_MODEL=$(jq -r '.execution.qa_model // "sonnet"' "$config_file")

        # -- blind validation (spec-54) --
        FLAG_BLIND_VALIDATION=$(jq -r '.flags.blind_validation // false' "$config_file")
        BLIND_VALIDATION_MAX_DIFF_LINES=$(jq -r '.blind_validation.max_diff_lines // 500' "$config_file")

        # -- steelman critique (spec-53) --
        FLAG_STEELMAN_CRITIQUE=$(jq -r '.flags.steelman_critique // false' "$config_file")

        # -- critique (spec-47) --
        CRITIQUE_AUTO_PREFLIGHT=$(jq -r '.critique.auto_preflight // false' "$config_file")
        CRITIQUE_BLOCK_ON_ERROR=$(jq -r '.critique.block_on_error // true' "$config_file")
        CRITIQUE_MAX_TOKEN_ESTIMATE=$(jq -r '.critique.max_token_estimate // 80000' "$config_file")

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

        # -- notifications (spec-52) --
        NOTIFY_WEBHOOK_URL=$(jq -r '.notifications.webhook_url // ""' "$config_file")
        NOTIFY_COMMAND=$(jq -r '.notifications.command // ""' "$config_file")
        NOTIFY_EVENTS=$(jq -r '.notifications.events // [] | join(",")' "$config_file")
        NOTIFY_TIMEOUT=$(jq -r '.notifications.timeout_seconds // 5' "$config_file")

        # -- work_log (spec-55) --
        WORK_LOG_ENABLED=$(jq -r '.work_log.enabled // true' "$config_file")
        WORK_LOG_LEVEL=$(jq -r '.work_log.log_level // "normal"' "$config_file")

        # -- debt_tracking (spec-56) --
        DEBT_TRACKING_ENABLED=$(jq -r '.debt_tracking.enabled // true' "$config_file")
        DEBT_TRACKING_THRESHOLD=$(jq -r '.debt_tracking.threshold // 20' "$config_file")
        DEBT_TRACKING_MARKERS=$(jq -r '.debt_tracking.markers // ["TODO","FIXME","HACK","DEBT","WORKAROUND","TEMPORARY"] | join(" ")' "$config_file")

        # -- guardrails (spec-58) --
        GUARDRAILS_MODE=$(jq -r '.guardrails_mode // "warn"' "$config_file")
        GUARDRAILS_SIZE_CEILING=18000
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

        # -- QA validation loop (spec-46) --
        QA_ENABLED="true"
        QA_MAX_ITERATIONS=5
        QA_BLIND_VALIDATION="false"
        QA_MODEL="sonnet"

        # -- critique (spec-47) --
        CRITIQUE_AUTO_PREFLIGHT="false"
        CRITIQUE_BLOCK_ON_ERROR="true"
        CRITIQUE_MAX_TOKEN_ESTIMATE=80000

        # -- output truncation (spec-49) --
        OUTPUT_MAX_LINES=200
        OUTPUT_HEAD_LINES=50
        OUTPUT_TAIL_LINES=150

        # -- git --
        GIT_AUTO_PUSH="true"
        GIT_AUTO_COMMIT="true"
        GIT_BRANCH_PREFIX="automaton/"

        # -- flags --
        FLAG_DANGEROUSLY_SKIP_PERMISSIONS="true"
        FLAG_VERBOSE="true"
        FLAG_SKIP_RESEARCH="false"
        FLAG_SKIP_REVIEW="false"
        FLAG_BLIND_VALIDATION="false"
        BLIND_VALIDATION_MAX_DIFF_LINES=500
        FLAG_STEELMAN_CRITIQUE="false"

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

        # -- notifications (spec-52) --
        NOTIFY_WEBHOOK_URL=""
        NOTIFY_COMMAND=""
        NOTIFY_EVENTS=""
        NOTIFY_TIMEOUT=5

        # -- work_log (spec-55) --
        WORK_LOG_ENABLED="true"
        WORK_LOG_LEVEL="normal"

        # -- debt_tracking (spec-56) --
        DEBT_TRACKING_ENABLED="true"
        DEBT_TRACKING_THRESHOLD=20
        DEBT_TRACKING_MARKERS="TODO FIXME HACK DEBT WORKAROUND TEMPORARY"

        # -- guardrails (spec-58) --
        GUARDRAILS_MODE="warn"
        GUARDRAILS_SIZE_CEILING=18000
    fi
}

# Validates config file: JSON syntax, types, ranges, enums, cross-field conflicts (spec-50).
# Collects all errors and reports them at once. Returns 0 if valid, 1 if errors found.
validate_config() {
    local config_file="${1:-${CONFIG_FILE:-automaton.config.json}}"
    local -a CONFIG_ERRORS=()

    # --- Missing config file ---
    if [ ! -f "$config_file" ]; then
        echo "CONFIG ERROR: config file not found: $config_file" >&2
        return 1
    fi

    # --- JSON syntax check ---
    local jq_err
    if ! jq_err=$(jq empty "$config_file" 2>&1); then
        echo "CONFIG ERROR: JSON parse error in $config_file:" >&2
        echo "  $jq_err" >&2
        return 1
    fi

    # --- Type checks ---
    local field jtype expected
    while IFS='|' read -r field expected; do
        jtype=$(jq -r "$field | type" "$config_file" 2>/dev/null)
        if [ "$jtype" != "$expected" ]; then
            CONFIG_ERRORS+=("CONFIG ERROR: ${field#.} must be $expected (got $jtype)")
        fi
    done <<'TYPECHECKS'
.models.primary|string
.models.research|string
.models.planning|string
.models.building|string
.models.review|string
.models.subagent_default|string
.budget.max_total_tokens|number
.budget.max_cost_usd|number
.budget.per_iteration|number
.budget.per_phase.research|number
.budget.per_phase.plan|number
.budget.per_phase.build|number
.budget.per_phase.review|number
.rate_limits.tokens_per_minute|number
.rate_limits.cooldown_seconds|number
.rate_limits.backoff_multiplier|number
.execution.max_iterations.research|number
.execution.max_iterations.plan|number
.execution.max_iterations.build|number
.execution.max_iterations.review|number
.execution.stall_threshold|number
.execution.max_consecutive_failures|number
.execution.qa_enabled|boolean
.execution.qa_max_iterations|number
.execution.qa_blind_validation|boolean
.execution.qa_model|string
.git.auto_push|boolean
.git.auto_commit|boolean
.git.branch_prefix|string
.flags.dangerously_skip_permissions|boolean
.flags.verbose|boolean
.flags.blind_validation|boolean
.blind_validation.max_diff_lines|number
TYPECHECKS

    # --- Range validation ---
    local val
    while IFS='|' read -r field op threshold label; do
        val=$(jq -r "$field // empty" "$config_file" 2>/dev/null)
        [ -z "$val" ] && continue
        if ! echo "$val $op $threshold" | awk '{exit !($1 '"$op"' $3)}'; then
            CONFIG_ERRORS+=("CONFIG ERROR: ${field#.} must be $op $threshold (got: $val)")
        fi
    done <<'RANGECHECKS'
.budget.max_total_tokens|>|0|
.budget.max_cost_usd|>|0|
.budget.per_iteration|>|0|
.rate_limits.tokens_per_minute|>|0|
.rate_limits.backoff_multiplier|>|1.0|
.execution.stall_threshold|>=|1|
.execution.max_consecutive_failures|>=|1|
.execution.qa_max_iterations|>=|1|
.blind_validation.max_diff_lines|>|0|
RANGECHECKS

    # --- Enum validation: model names ---
    local model_val
    for model_field in .models.primary .models.research .models.planning .models.building .models.review .models.subagent_default .execution.qa_model; do
        model_val=$(jq -r "$model_field // empty" "$config_file" 2>/dev/null)
        [ -z "$model_val" ] && continue
        case "$model_val" in
            opus|sonnet|haiku) ;;
            *) CONFIG_ERRORS+=("CONFIG ERROR: ${model_field#.} must be one of opus|sonnet|haiku (got: \"$model_val\")") ;;
        esac
    done

    # --- Cross-field conflict detection ---
    local max_tokens per_phase_val smallest_phase per_iter
    max_tokens=$(jq -r '.budget.max_total_tokens // 0' "$config_file")
    per_iter=$(jq -r '.budget.per_iteration // 0' "$config_file")
    smallest_phase="$max_tokens"
    for phase in research plan build review; do
        per_phase_val=$(jq -r ".budget.per_phase.$phase // 0" "$config_file")
        if echo "$per_phase_val $max_tokens" | awk '{exit !($1 > $2)}'; then
            CONFIG_ERRORS+=("CONFIG ERROR: budget.per_phase.$phase ($per_phase_val) exceeds budget.max_total_tokens ($max_tokens)")
        fi
        if echo "$per_phase_val $smallest_phase" | awk '{exit !($1 < $2)}'; then
            smallest_phase="$per_phase_val"
        fi
    done
    if echo "$per_iter $smallest_phase" | awk '{exit !($1 > $2)}'; then
        CONFIG_ERRORS+=("CONFIG ERROR: budget.per_iteration ($per_iter) exceeds smallest budget.per_phase value ($smallest_phase)")
    fi

    # --- Output truncation: head + tail must equal max (spec-49) ---
    local out_max out_head out_tail
    out_max=$(jq -r '.execution.output_max_lines // empty' "$config_file" 2>/dev/null)
    out_head=$(jq -r '.execution.output_head_lines // empty' "$config_file" 2>/dev/null)
    out_tail=$(jq -r '.execution.output_tail_lines // empty' "$config_file" 2>/dev/null)
    if [ -n "$out_max" ] && [ -n "$out_head" ] && [ -n "$out_tail" ]; then
        local sum=$((out_head + out_tail))
        if [ "$sum" -ne "$out_max" ]; then
            CONFIG_ERRORS+=("CONFIG ERROR: execution.output_head_lines ($out_head) + execution.output_tail_lines ($out_tail) = $sum, must equal execution.output_max_lines ($out_max)")
        fi
    fi

    # --- Warnings (stderr, non-blocking) ---
    local build_iters cost_usd backoff stall_t fail_t
    build_iters=$(jq -r '.execution.max_iterations.build // 0' "$config_file")
    cost_usd=$(jq -r '.budget.max_cost_usd // 0' "$config_file")
    backoff=$(jq -r '.rate_limits.backoff_multiplier // 0' "$config_file")
    stall_t=$(jq -r '.execution.stall_threshold // 0' "$config_file")
    fail_t=$(jq -r '.execution.max_consecutive_failures // 0' "$config_file")

    if echo "$build_iters" | awk '{exit !($1 > 50)}'; then
        echo "CONFIG WARNING: execution.max_iterations.build is $build_iters — unusually high, possible infinite loop risk" >&2
    fi
    if echo "$cost_usd" | awk '{exit !($1 > 200)}'; then
        echo "CONFIG WARNING: budget.max_cost_usd is \$$cost_usd — unusually high" >&2
    fi
    if echo "$backoff" | awk '{exit !($1 > 10)}'; then
        echo "CONFIG WARNING: rate_limits.backoff_multiplier is $backoff — unusually high, likely a typo" >&2
    fi
    if [ "$stall_t" = "$fail_t" ] && [ "$stall_t" != "0" ]; then
        echo "CONFIG WARNING: execution.stall_threshold ($stall_t) equals execution.max_consecutive_failures ($fail_t) — stall detection and failure abort will trigger simultaneously" >&2
    fi

    # --- Report errors ---
    if [ "${#CONFIG_ERRORS[@]}" -gt 0 ]; then
        for err in "${CONFIG_ERRORS[@]}"; do
            echo "$err" >&2
        done
        echo "Found ${#CONFIG_ERRORS[@]} config errors. Fix automaton.config.json and re-run." >&2
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Doctor / Health Check (spec-48)
# ---------------------------------------------------------------------------

# Helper: consistent output for each doctor check line.
# Usage: report_check "name" "PASS|WARN|FAIL|INFO" "detail"
report_check() {
    local name="$1" status="$2" detail="${3:-}"
    local color="" reset=""
    if [ "$_DOCTOR_COLOR" = "true" ]; then
        case "$status" in
            PASS) color="\033[32m" ;; # green
            WARN) color="\033[33m" ;; # yellow
            FAIL) color="\033[31m" ;; # red
            INFO) color="\033[34m" ;; # blue
        esac
        reset="\033[0m"
    fi
    local pad
    pad=$(printf '%.0s.' $(seq 1 $((22 - ${#name}))))
    local msg="  ${name} ${pad} ${color}${status}${reset}"
    [ -n "$detail" ] && msg="${msg}  (${detail})"
    echo -e "$msg"
    case "$status" in
        PASS) _DOCTOR_PASS=$((_DOCTOR_PASS + 1)) ;;
        WARN) _DOCTOR_WARN=$((_DOCTOR_WARN + 1)) ;;
        FAIL) _DOCTOR_FAIL=$((_DOCTOR_FAIL + 1)) ;;
        INFO) _DOCTOR_INFO=$((_DOCTOR_INFO + 1)) ;;
    esac
}

# Runs all environment checks and prints a human-readable report.
# Exit 0 if pass/warn only, exit 1 if any FAIL.
doctor_check() {
    _DOCTOR_PASS=0; _DOCTOR_WARN=0; _DOCTOR_FAIL=0; _DOCTOR_INFO=0
    _DOCTOR_COLOR=true
    [ -n "${NO_COLOR:-}" ] && _DOCTOR_COLOR=false
    [ ! -t 1 ] && _DOCTOR_COLOR=false

    echo "automaton --doctor"
    echo ""

    # --- Tool checks ---
    # bash version
    if [ "${BASH_VERSINFO[0]}" -ge 4 ] 2>/dev/null; then
        report_check "bash" "PASS" "${BASH_VERSION}, requires >=4.0"
    else
        report_check "bash" "FAIL" "${BASH_VERSION:-unknown}, requires >=4.0; upgrade: brew install bash (macOS) or apt install bash"
    fi

    # git
    if command -v git >/dev/null 2>&1; then
        local git_ver
        git_ver=$(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        local git_major git_minor
        git_major="${git_ver%%.*}"
        git_minor="${git_ver#*.}"
        if [ "${git_major:-0}" -gt 2 ] || { [ "${git_major:-0}" -eq 2 ] && [ "${git_minor:-0}" -ge 20 ]; }; then
            report_check "git" "PASS" "${git_ver}, requires >=2.20"
        else
            report_check "git" "FAIL" "${git_ver}, requires >=2.20; upgrade git"
        fi
    else
        report_check "git" "FAIL" "not found; install: apt install git or brew install git"
    fi

    # claude
    if command -v claude >/dev/null 2>&1; then
        report_check "claude" "PASS"
    else
        report_check "claude" "FAIL" "not found; install: https://docs.anthropic.com/en/docs/claude-code"
    fi

    # jq
    if command -v jq >/dev/null 2>&1; then
        local jq_ver
        jq_ver=$(jq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        local jq_major jq_minor
        jq_major="${jq_ver%%.*}"
        jq_minor="${jq_ver#*.}"
        if [ "${jq_major:-0}" -gt 1 ] || { [ "${jq_major:-0}" -eq 1 ] && [ "${jq_minor:-0}" -ge 5 ]; }; then
            report_check "jq" "PASS" "${jq_ver}, requires >=1.5"
        else
            report_check "jq" "FAIL" "${jq_ver}, requires >=1.5; install: https://jqlang.github.io/jq/download/"
        fi
    else
        report_check "jq" "FAIL" "not found; install: https://jqlang.github.io/jq/download/"
    fi

    # --- Claude auth check ---
    if command -v claude >/dev/null 2>&1; then
        if claude --version >/dev/null 2>&1; then
            report_check "claude auth" "PASS"
        else
            report_check "claude auth" "WARN" "could not verify; run 'claude login' or check ANTHROPIC_API_KEY"
        fi
    else
        report_check "claude auth" "WARN" "claude not installed; skipping auth check"
    fi

    # --- Disk space check ---
    local free_kb
    free_kb=$(df -k . 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$free_kb" ]; then
        local free_mb=$((free_kb / 1024))
        if [ "$free_mb" -lt 10 ]; then
            report_check "disk space" "FAIL" "${free_mb} MB free; need at least 10 MB"
        elif [ "$free_mb" -lt 100 ]; then
            report_check "disk space" "WARN" "${free_mb} MB free; recommend at least 100 MB"
        else
            local free_display="${free_mb} MB"
            if [ "$free_mb" -ge 1024 ]; then
                local free_gb=$((free_mb / 1024))
                local free_gb_frac=$(( (free_mb % 1024) * 10 / 1024 ))
                free_display="${free_gb}.${free_gb_frac} GB"
            fi
            report_check "disk space" "PASS" "${free_display} free"
        fi
    else
        report_check "disk space" "WARN" "could not determine free space"
    fi

    # --- Git repo checks ---
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        report_check "git repo" "PASS"

        if git log -1 >/dev/null 2>&1; then
            local remote_info
            remote_info=$(git remote -v 2>/dev/null | head -1)
            if [ -n "$remote_info" ]; then
                local remote_name remote_url
                remote_name=$(echo "$remote_info" | awk '{print $1}')
                remote_url=$(echo "$remote_info" | awk '{print $2}')
                report_check "git remote" "PASS" "${remote_name} -> ${remote_url}"
            else
                report_check "git remote" "WARN" "no remote configured; add: git remote add origin <url>"
            fi
        else
            report_check "git commits" "WARN" "no commits yet"
        fi

        local dirty_count
        dirty_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        if [ "$dirty_count" -gt 0 ]; then
            report_check "working tree" "INFO" "${dirty_count} uncommitted changes"
        else
            report_check "working tree" "INFO" "clean"
        fi
    else
        report_check "git repo" "WARN" "not inside a git repository"
    fi

    # --- Project file checks ---
    if [ -f "automaton.config.json" ]; then
        if jq empty < automaton.config.json >/dev/null 2>&1; then
            report_check "automaton.config.json" "PASS" "valid JSON"
        else
            report_check "automaton.config.json" "FAIL" "invalid JSON; fix syntax in automaton.config.json"
        fi
    else
        report_check "automaton.config.json" "WARN" "not found; automaton runs with defaults"
    fi

    if [ -f "AGENTS.md" ]; then
        report_check "AGENTS.md" "PASS"
    else
        report_check "AGENTS.md" "WARN" "not found; create to define agent roles"
    fi

    if [ -d "specs/" ]; then
        report_check "specs/" "PASS"
    else
        report_check "specs/" "WARN" "not found; create for spec-driven workflow"
    fi

    if [ -f "PRD.md" ]; then
        report_check "PRD.md" "PASS"
    else
        report_check "PRD.md" "WARN" "not found; create for product context"
    fi

    # --- .automaton/ state directory ---
    if [ -d ".automaton" ]; then
        if [ -w ".automaton" ]; then
            report_check ".automaton/" "PASS"
        else
            report_check ".automaton/" "FAIL" "directory not writable"
        fi
    elif [ -e ".automaton" ]; then
        report_check ".automaton/" "FAIL" "exists but is not a directory"
    else
        report_check ".automaton/" "PASS" "will be created on first run"
    fi

    # --- Summary ---
    echo ""
    echo "  Result: $_DOCTOR_PASS passed, $_DOCTOR_WARN warnings, $_DOCTOR_FAIL failures"

    if [ "$_DOCTOR_FAIL" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# First-Time Setup Wizard (spec-57)
# ---------------------------------------------------------------------------
# Interactive wizard that generates automaton.config.json on first run.
# Uses only read, printf, jq, and bash builtins — no Claude API calls.
setup_wizard() {
    # Non-TTY check: if stdin is not a terminal, cannot run interactively
    if [ ! -t 0 ]; then
        echo "Error: --setup requires an interactive terminal (stdin is not a TTY)." >&2
        return 1
    fi

    local _decline_count=0

    while true; do
        # --- Prompt 1: Model Tier ---
        local model_tier="sonnet"
        printf '\nSelect model tier [sonnet]:\n'
        printf '  1) opus   -- highest quality, ~$15/M input tokens\n'
        printf '  2) sonnet -- balanced quality/cost, ~$3/M input tokens\n'
        printf 'Choice (1 or 2): '
        read -r _choice
        case "$_choice" in
            1) model_tier="opus" ;;
            2|"") model_tier="sonnet" ;;
            *) model_tier="sonnet" ;;
        esac

        # --- Prompt 2: Budget Limit ---
        local budget_usd="50"
        printf '\nMaximum spend limit in USD [50]: '
        read -r _budget_input
        if [ -z "$_budget_input" ]; then
            budget_usd="50"
        elif [[ "$_budget_input" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(echo "$_budget_input > 0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
            budget_usd="$_budget_input"
        else
            printf 'Invalid input. Enter a positive number [50]: '
            read -r _budget_input
            if [[ "$_budget_input" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ "$(echo "$_budget_input > 0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                budget_usd="$_budget_input"
            else
                budget_usd="50"
            fi
        fi

        # --- Prompt 3: Auto-Push ---
        local auto_push="true"
        printf '\nAuto-push commits to git remote? (yes/no) [yes]: '
        read -r _push_input
        case "$(echo "$_push_input" | tr '[:upper:]' '[:lower:]')" in
            y|yes|"") auto_push="true" ;;
            n|no) auto_push="false" ;;
            *)
                printf 'Invalid input. (yes/no) [yes]: '
                read -r _push_input
                case "$(echo "$_push_input" | tr '[:upper:]' '[:lower:]')" in
                    n|no) auto_push="false" ;;
                    *) auto_push="true" ;;
                esac
                ;;
        esac

        # --- Prompt 4: Skip Research ---
        local skip_research="false"
        printf '\nSkip research phase? (yes/no) [no]:\n'
        printf "  (Choose 'yes' for existing codebases where research is unnecessary)\n"
        printf 'Choice: '
        read -r _skip_input
        case "$(echo "$_skip_input" | tr '[:upper:]' '[:lower:]')" in
            y|yes) skip_research="true" ;;
            n|no|"") skip_research="false" ;;
            *) skip_research="false" ;;
        esac

        # --- Confirmation Summary ---
        local _push_display="yes"
        [ "$auto_push" = "false" ] && _push_display="no"
        local _skip_display="no"
        [ "$skip_research" = "true" ] && _skip_display="yes"

        printf '\n--- Setup Summary ---\n'
        printf '  Model tier:      %s\n' "$model_tier"
        printf '  Budget limit:    $%s\n' "$budget_usd"
        printf '  Auto-push:       %s\n' "$_push_display"
        printf '  Skip research:   %s\n' "$_skip_display"
        printf '  Config file:     automaton.config.json\n'
        printf '\nWrite this configuration? (yes/no) [yes]: '
        read -r _confirm
        case "$(echo "$_confirm" | tr '[:upper:]' '[:lower:]')" in
            n|no)
                ((_decline_count++))
                if [ "$_decline_count" -ge 2 ]; then
                    printf '\nSetup cancelled. Edit automaton.config.json manually or run --setup again.\n'
                    return 1
                fi
                printf '\nRestarting setup...\n'
                continue
                ;;
        esac

        # --- Generate Config ---
        jq -n \
            --arg model "$model_tier" \
            --arg budget "$budget_usd" \
            --argjson auto_push "$auto_push" \
            --argjson skip_research "$skip_research" \
            '{
                models: { primary: $model, research: "sonnet", planning: "opus", building: $model, review: "opus", subagent_default: "sonnet" },
                budget: { mode: "api", max_total_tokens: 10000000, max_cost_usd: ($budget | tonumber), per_phase: { research: 500000, plan: 1000000, build: 7000000, review: 1500000 }, per_iteration: 500000 },
                rate_limits: { preset: "auto", tokens_per_minute: 80000, requests_per_minute: 50, cooldown_seconds: 60, backoff_multiplier: 2, max_backoff_seconds: 300 },
                execution: { max_iterations: { research: 3, plan: 2, build: 0, review: 2 }, parallel_builders: 1, stall_threshold: 3, max_consecutive_failures: 3, retry_delay_seconds: 10, phase_timeout_seconds: { research: 0, plan: 0, build: 0, review: 0 }, test_first_enabled: true, test_scaffold_iterations: 2, test_framework: "assertions", bootstrap_enabled: true, bootstrap_script: ".automaton/init.sh", bootstrap_timeout_ms: 2000, output_max_lines: 200, output_head_lines: 50, output_tail_lines: 150, qa_enabled: true, qa_max_iterations: 5, qa_blind_validation: false, qa_model: "sonnet" },
                git: { auto_push: $auto_push, auto_commit: true, branch_prefix: "automaton/" },
                flags: { dangerously_skip_permissions: true, verbose: true, skip_research: $skip_research, skip_review: false, blind_validation: false, steelman_critique: false },
                blind_validation: { max_diff_lines: 500 },
                parallel: { enabled: false, mode: "automaton", max_builders: 3 },
                self_build: { enabled: false, max_files_per_iteration: 3, max_lines_changed_per_iteration: 200, protected_functions: ["run_orchestration", "_handle_shutdown"], require_smoke_test: true },
                journal: { max_runs: 50 },
                agents: { use_native_definitions: false },
                garden: { enabled: true, seed_ttl_days: 14, sprout_ttl_days: 30, sprout_threshold: 2, bloom_threshold: 3, bloom_priority_threshold: 40, signal_seed_threshold: 0.7, max_active_ideas: 50, auto_seed_from_metrics: true, auto_seed_from_signals: true },
                stigmergy: { enabled: true, initial_strength: 0.3, reinforce_increment: 0.15, decay_floor: 0.05, match_threshold: 0.6, max_signals: 100 },
                quorum: { enabled: true, voters: ["conservative", "ambitious", "efficiency", "quality", "advocate"], thresholds: { seed_promotion: 3, bloom_implementation: 3, constitutional_amendment: 4, emergency_override: 5 }, max_tokens_per_voter: 500, max_cost_per_cycle_usd: 1, rejection_cooldown_cycles: 5, model: "sonnet" },
                metrics: { enabled: true, trend_window: 5, degradation_alert_threshold: 3, snapshot_retention: 100 },
                evolution: { enabled: false, max_cycles: 0, max_cost_per_cycle_usd: 5.00, convergence_threshold: 5, idle_garden_threshold: 3, branch_prefix: "automaton/evolve-", auto_merge: true, reflect_model: "sonnet", ideate_model: "sonnet", observe_model: "sonnet" },
                critique: { auto_preflight: false, block_on_error: true, max_token_estimate: 80000 },
                notifications: { webhook_url: "", events: ["run_started", "phase_completed", "run_completed", "run_failed", "escalation"], command: "", timeout_seconds: 5 },
                safety: { max_total_lines: 15000, max_total_functions: 300, min_test_pass_rate: 0.80, max_consecutive_failures: 3, max_consecutive_regressions: 2, preserve_failed_branches: true, preflight_enabled: true, sandbox_testing_enabled: true },
                work_log: { enabled: true, log_level: "normal" },
                debt_tracking: { enabled: true, threshold: 20, markers: ["TODO", "FIXME", "HACK", "DEBT", "WORKAROUND", "TEMPORARY"] },
                guardrails_mode: "warn"
            }' > automaton.config.json

        printf '\nConfiguration written to automaton.config.json\n'

        # --- Create .automaton/ if absent ---
        if [ ! -d ".automaton" ]; then
            mkdir -p ".automaton"
            printf 'Created .automaton/ state directory.\n'
        fi

        # --- Post-setup doctor check (spec-48) ---
        printf '\nRunning environment check...\n\n'
        doctor_check || true

        return 0
    done
}

# --- Requirements Wizard (spec-59) ---
# Launches an interactive Claude session that guides the user through a
# structured 6-stage interview to produce spec files, PRD.md, and AGENTS.md.
# Called automatically when Gate 1 fails and stdin is a TTY, or explicitly
# via --wizard. After the wizard completes, Gate 1 is re-checked so
# autonomous execution can continue without interruption.
requirements_wizard() {
    # Non-TTY guard: cannot run an interactive wizard without a terminal
    if [ ! -t 0 ]; then
        echo "Error: Requirements wizard requires an interactive terminal (stdin is not a TTY)." >&2
        echo "Write spec files manually or run from an interactive shell." >&2
        return 1
    fi

    # If specs already exist (--wizard force mode), confirm overwrite
    if ls specs/*.md >/dev/null 2>&1; then
        printf '\nSpec files already exist in specs/. The wizard will generate new specs\n'
        printf 'which may overwrite existing ones.\n'
        printf 'Continue? (yes/no) [no]: '
        read -r _overwrite_confirm
        case "$(echo "$_overwrite_confirm" | tr '[:upper:]' '[:lower:]')" in
            y|yes) ;;
            *)
                printf 'Wizard cancelled.\n'
                return 1
                ;;
        esac
    fi

    # Banner
    printf '\n'
    printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
    printf ' automaton — Requirements Wizard\n'
    printf '\n'
    printf ' This wizard will interview you about your\n'
    printf ' project and generate structured specs.\n'
    printf ' Takes about 5-15 minutes.\n'
    printf '\n'
    printf ' Say "next" at any time to advance stages.\n'
    printf ' Press Ctrl+C to cancel (re-runnable).\n'
    printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
    printf '\n'

    # Ensure specs/ directory exists
    mkdir -p specs

    # Launch Claude with the wizard prompt
    # Use --system-prompt to inject PROMPT_wizard.md as the system prompt
    local _wizard_prompt_file
    _wizard_prompt_file="$(cd "$(dirname "$0")" && pwd)/PROMPT_wizard.md"

    if [ ! -f "$_wizard_prompt_file" ]; then
        echo "Error: PROMPT_wizard.md not found at $_wizard_prompt_file" >&2
        return 1
    fi

    local _wizard_prompt
    _wizard_prompt="$(cat "$_wizard_prompt_file")"

    # Run interactive Claude session with wizard system prompt
    claude --system-prompt "$_wizard_prompt" 2>&1
    local _claude_rc=$?

    if [ "$_claude_rc" -ne 0 ] && [ "$_claude_rc" -ne 130 ]; then
        echo "Warning: Claude session exited with code $_claude_rc" >&2
    fi

    # Re-check Gate 1 after wizard completes
    printf '\nChecking spec completeness...\n'
    if gate_spec_completeness; then
        log "ORCHESTRATOR" "Requirements wizard: Gate 1 now passes"
        printf 'Specs validated. Continuing with autonomous execution...\n\n'
        return 0
    else
        printf '\nGate 1 still failing after wizard. Check the output above for details.\n'
        printf 'You can re-run the wizard with: ./automaton.sh --wizard\n'
        return 1
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
