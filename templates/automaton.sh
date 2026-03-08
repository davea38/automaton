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
# Module loading (dependency order)
# ---------------------------------------------------------------------------

AUTOMATON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"

source "$AUTOMATON_LIB_DIR/config.sh"
source "$AUTOMATON_LIB_DIR/state.sh"
source "$AUTOMATON_LIB_DIR/budget.sh"
source "$AUTOMATON_LIB_DIR/errors.sh"
source "$AUTOMATON_LIB_DIR/lifecycle.sh"
source "$AUTOMATON_LIB_DIR/context.sh"
source "$AUTOMATON_LIB_DIR/garden.sh"
source "$AUTOMATON_LIB_DIR/signals.sh"
source "$AUTOMATON_LIB_DIR/quorum.sh"
source "$AUTOMATON_LIB_DIR/metrics.sh"
source "$AUTOMATON_LIB_DIR/constitution.sh"
source "$AUTOMATON_LIB_DIR/safety.sh"
source "$AUTOMATON_LIB_DIR/utilities.sh"
source "$AUTOMATON_LIB_DIR/evolution.sh"
source "$AUTOMATON_LIB_DIR/qa.sh"
source "$AUTOMATON_LIB_DIR/display.sh"
source "$AUTOMATON_LIB_DIR/parallel.sh"

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
ARG_VALIDATE_CONFIG=false
ARG_DOCTOR=false
ARG_CRITIQUE_SPECS=false
ARG_SKIP_CRITIQUE=false
ARG_STEELMAN=false
ARG_COMPLEXITY=""
ARG_LOG_LEVEL=""
ARG_SETUP=false
ARG_NO_SETUP=false
ARG_WIZARD=false
ARG_NO_WIZARD=false

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
        --validate-config)
            ARG_VALIDATE_CONFIG=true
            shift
            ;;
        --doctor)
            ARG_DOCTOR=true
            shift
            ;;
        --critique-specs)
            ARG_CRITIQUE_SPECS=true
            shift
            ;;
        --skip-critique)
            ARG_SKIP_CRITIQUE=true
            shift
            ;;
        --steelman)
            ARG_STEELMAN=true
            shift
            ;;
        --complexity)
            if [ -z "${2:-}" ] || ! echo "${2:-}" | grep -qE '^(simple|moderate|complex)$'; then
                echo "Error: --complexity requires one of: simple, moderate, complex" >&2
                exit 1
            fi
            ARG_COMPLEXITY="$2"
            shift 2
            ;;
        --log-level)
            if [ -z "${2:-}" ] || ! echo "${2:-}" | grep -qE '^(minimal|normal|verbose)$'; then
                echo "Error: --log-level requires one of: minimal, normal, verbose" >&2
                exit 1
            fi
            ARG_LOG_LEVEL="$2"
            shift 2
            ;;
        --setup)
            ARG_SETUP=true
            shift
            ;;
        --no-setup)
            ARG_NO_SETUP=true
            shift
            ;;
        --wizard)
            ARG_WIZARD=true
            shift
            ;;
        --no-wizard)
            ARG_NO_WIZARD=true
            shift
            ;;
        --help|-h)
            _show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Run './automaton.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

# --- Mutual exclusion: --setup + --no-setup (spec-57) ---
if [ "$ARG_SETUP" = "true" ] && [ "$ARG_NO_SETUP" = "true" ]; then
    echo "Error: --setup and --no-setup are mutually exclusive." >&2
    exit 1
fi

# --- Mutual exclusion: --wizard + --no-wizard (spec-59) ---
if [ "$ARG_WIZARD" = "true" ] && [ "$ARG_NO_WIZARD" = "true" ]; then
    echo "Error: --wizard and --no-wizard are mutually exclusive." >&2
    exit 1
fi

# --- Doctor / health check (spec-48) ---
# Runs before dependency checks and config load — it IS the comprehensive check.
if [ "$ARG_DOCTOR" = "true" ]; then
    doctor_check
    exit $?
fi

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

# --- First-time setup wizard (spec-57) ---
# Runs after dependency checks, before config load. Detects missing config.
if [ "$ARG_SETUP" = "true" ]; then
    # Force re-run even if config exists
    setup_wizard
    _wizard_rc=$?
    if [ "$_wizard_rc" -ne 0 ]; then
        exit 1
    fi
elif [ "$ARG_NO_SETUP" != "true" ] && [ -z "$ARG_CONFIG_FILE" ] && [ ! -f "automaton.config.json" ]; then
    # First-run detection: no config file and --no-setup not passed
    if [ -t 0 ]; then
        printf 'No automaton.config.json found. Starting setup wizard...\n'
        setup_wizard || true
    fi
    # Non-TTY: silently continue with defaults (equivalent to --no-setup)
fi

# --- Apply --config before loading configuration ---
if [ -n "$ARG_CONFIG_FILE" ]; then
    CONFIG_FILE="$ARG_CONFIG_FILE"
fi

# --- Load configuration (uses CONFIG_FILE if set, else automaton.config.json) ---
load_config

# --- Config pre-flight validation (spec-50) ---
# Runs after load_config, before any phase dispatch. Catches bad config early.
if [ "$ARG_VALIDATE_CONFIG" = "true" ]; then
    validate_config
    echo "Config validation passed."
    exit 0
fi
validate_config

# --- Standalone spec critique (spec-47) ---
# Runs after config load so CRITIQUE_* vars are available. Standalone mode exits.
if [ "$ARG_CRITIQUE_SPECS" = "true" ]; then
    phase_critique "${PROJECT_ROOT:-.}/specs"
    exit $?
fi

# --- Standalone steelman critique (spec-53) ---
# Runs after config load. Standalone mode exits with 0 on success, 1 if no plan.
if [ "$ARG_STEELMAN" = "true" ]; then
    run_steelman_critique
    exit $?
fi

# --- Override config flags with CLI arguments ---
if [ "$ARG_SKIP_RESEARCH" = "true" ]; then
    FLAG_SKIP_RESEARCH="true"
fi
if [ "$ARG_SKIP_REVIEW" = "true" ]; then
    FLAG_SKIP_REVIEW="true"
fi
if [ -n "$ARG_LOG_LEVEL" ]; then
    WORK_LOG_LEVEL="$ARG_LOG_LEVEL"
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

# ---------------------------------------------------------------------------
# Orchestration Functions
# ---------------------------------------------------------------------------

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
    # Show Scope line only when --scope targets a different directory (spec-60 §6)
    if [ "${PROJECT_ROOT:-$(pwd)}" != "$(pwd)" ]; then
        echo " Scope:   ${PROJECT_ROOT}"
    fi
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
    local stall_rc=0 test_fail_rc=0 micro_rc=0
    if [ "$current_phase" = "build" ]; then
        check_stall || stall_rc=$?
        check_test_failures "$AGENT_RESULT" || test_fail_rc=$?
        check_plan_integrity
        # Self-build safety: validate orchestrator file modifications (spec-22)
        self_build_validate
        self_build_check_scope
        # Append iteration memory for incremental context (spec-24)
        append_iteration_memory

        # Post-task micro-validation: lightweight Sonnet check (audit wave 4)
        run_micro_validation "$task_desc" "" || micro_rc=$?

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

    # Notify: phase completed (spec-52)
    send_notification "phase_completed" "$current_phase" "success" "${current_phase} phase completed"

    # Structured work log: phase_end and phase_start (spec-55)
    emit_event "phase_end" "{\"exit_code\":0,\"iterations\":${phase_iteration:-0}}"

    phase_history=$(echo "$phase_history" | jq -c \
        --arg p "$current_phase" --arg t "$now" \
        '. + [{"phase": $p, "completed_at": $t}]')

    current_phase="$new_phase"
    phase_iteration=0
    PHASE_START_TIME=$(date +%s)

    emit_event "phase_start" "{\"phase_config\":{}}"

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
        # --- Requirements wizard integration (spec-59) ---
        # If --wizard flag, force-run wizard before Gate 1 check
        if [ "$ARG_WIZARD" = "true" ]; then
            requirements_wizard || exit 1
        fi

        if ! gate_check "spec_completeness"; then
            if [ "$ARG_NO_WIZARD" = "true" ]; then
                echo "Gate 1 (spec completeness) failed. Run the conversation phase first."
                exit 1
            elif [ -t 0 ]; then
                # TTY available: auto-launch requirements wizard
                log "ORCHESTRATOR" "Gate 1 failed — launching requirements wizard"
                printf 'No specs found. Starting requirements wizard...\n'
                requirements_wizard || exit 1
            else
                # Non-TTY: actionable error message
                echo "Gate 1 (spec completeness) failed." >&2
                echo "No spec files found. To fix this, either:" >&2
                echo "  1. Run './automaton.sh' from an interactive terminal (wizard auto-launches)" >&2
                echo "  2. Run 'claude' manually to write specs, then re-run './automaton.sh'" >&2
                echo "  3. Create spec files in specs/ and PRD.md manually" >&2
                exit 1
            fi
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

    # --- Pre-flight spec critique (spec-47) ---
    # When auto_preflight is enabled and not skipped, critique specs before planning.
    # Only runs on fresh starts (not resumes) and when not in self-build mode.
    if [ "$CRITIQUE_AUTO_PREFLIGHT" = "true" ] && [ "$ARG_SKIP_CRITIQUE" != "true" ] \
        && [ "$ARG_RESUME" != "true" ] && [ "${ARG_SELF:-false}" != "true" ]; then
        log "ORCHESTRATOR" "Running pre-flight spec critique (spec-47)"
        local critique_rc=0
        phase_critique "${PROJECT_ROOT:-.}/specs" || critique_rc=$?
        if [ "$critique_rc" -ne 0 ] && [ "$CRITIQUE_BLOCK_ON_ERROR" = "true" ]; then
            local err_count
            err_count=$(grep -c '^\### \[ERROR\]' "${AUTOMATON_DIR:-.automaton}/SPEC_CRITIQUE.md" 2>/dev/null || echo "?")
            echo "Spec critique found ${err_count} error(s). Review .automaton/SPEC_CRITIQUE.md and re-run." >&2
            echo "Use --skip-critique to bypass." >&2
            exit 1
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

    # Notify: run started (spec-52)
    send_notification "run_started" "$current_phase" "info" "Run started (phase=$current_phase)"

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
            emit_event "iteration_start" "{\"task\":\"${current_phase} iteration ${phase_iteration}\"}"
            local iter_start_epoch
            iter_start_epoch=$(date +%s)
            run_agent "$prompt_file" "$model"

            # --- Error classification and recovery ---
            if [ "$AGENT_EXIT_CODE" -ne 0 ]; then
                emit_event "error" "{\"message\":\"agent exit code ${AGENT_EXIT_CODE}\",\"fatal\":false}"
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

            emit_event "iteration_end" "{\"exit_code\":${AGENT_EXIT_CODE:-0},\"files_changed\":0}"

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
                    # Steelman critique (spec-53): non-blocking adversarial analysis after planning
                    if [ "${FLAG_STEELMAN_CRITIQUE:-false}" = "true" ]; then
                        log "ORCHESTRATOR" "Running steelman critique (spec-53)"
                        run_steelman_critique || true
                    fi
                    transition_to_phase "build"
                    # Red-before-green gate (audit wave 3): record pre-build test failures
                    local rg_test_runner="${PROJECT_ROOT:-.}/run_tests.sh"
                    red_green_record_baseline "$rg_test_runner"
                else
                    escalate "Plan phase failed to produce a valid implementation plan."
                fi
                ;;

            build)
                # Gate 4: build completion. On fail: continue building (spec-05)
                if gate_check "build_completion"; then
                    # Red-before-green gate (audit wave 3): verify failures decreased
                    local rg_test_runner="${PROJECT_ROOT:-.}/run_tests.sh"
                    if ! red_green_check_progress "$rg_test_runner"; then
                        log "ORCHESTRATOR" "WARNING: Red-before-green gate detected regression — proceeding to review for diagnosis"
                    fi
                    # QA loop (spec-46): validate → fix → rebuild before review
                    if [ "${QA_ENABLED:-true}" = "true" ]; then
                        log "ORCHESTRATOR" "Running QA validation loop before review"
                        local test_cmd
                        test_cmd=$(grep -E '^- Test:' AGENTS.md 2>/dev/null | head -1 | sed 's/^- Test: *//' || echo "bash -n automaton.sh")
                        [ -z "$test_cmd" ] && test_cmd="bash -n automaton.sh"
                        local qa_result
                        qa_result=$(_qa_run_loop "$test_cmd" "${PROJECT_ROOT:-.}/specs")
                        local qa_verdict
                        qa_verdict=$(echo "$qa_result" | jq -r '.verdict')
                        local qa_iters
                        qa_iters=$(echo "$qa_result" | jq -r '.iterations_run')
                        local qa_fixes
                        qa_fixes=$(echo "$qa_result" | jq -r '.fix_tasks_created')
                        if [ "$qa_verdict" = "PASS" ]; then
                            log "ORCHESTRATOR" "QA passed after ${qa_iters} iteration(s)"
                        else
                            log "ORCHESTRATOR" "QA exhausted ${qa_iters} iterations with unresolved failures (${qa_fixes} fix tasks created)"
                        fi
                    fi
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
                    # Blind validation (spec-54): additional independent review pass
                    if [ "${FLAG_BLIND_VALIDATION:-false}" = "true" ]; then
                        local blind_spec
                        blind_spec=$(ls -t specs/spec-*.md 2>/dev/null | head -1)
                        if [ -n "$blind_spec" ] && ! run_blind_validation "$blind_spec"; then
                            log "ORCHESTRATOR" "Blind validation FAILED — overriding review pass"
                            review_attempts=$((review_attempts + 1))
                            if [ "$review_attempts" -ge 3 ]; then
                                escalate "Review passed but blind validation failed after $review_attempts attempts."
                            else
                                log "ORCHESTRATOR" "Returning to build to address blind validation findings."
                                stall_count=0
                                transition_to_phase "build"
                                continue 2
                            fi
                        fi
                    fi
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

    # Structured work log: completion (spec-55)
    emit_event "completion" "{\"status\":\"success\",\"total_iterations\":${iteration:-0},\"total_tokens\":0}"

    # Notify: run completed (spec-52)
    send_notification "run_completed" "all" "success" "Run completed successfully"

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

# --- Complexity assessment and routing (spec-51) ---
# Classify task complexity before pipeline runs. The assessment uses a cheap
# haiku call; --complexity=TIER bypasses it. Routing adjusts pipeline variables
# (model, review iterations, blind validation, etc.) based on the tier.
# Only runs on fresh starts (not resumes) and when not in evolution mode.
if [ "$ARG_RESUME" != "true" ] && [ "${ARG_EVOLVE:-false}" != "true" ]; then
    # Build a task description from available context
    _task_desc=""
    if [ -f "${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md" ]; then
        _task_desc=$(grep -m1 '^\- \[ \]' "${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md" 2>/dev/null | sed 's/^- \[ \] //' || echo "")
    fi
    [ -z "$_task_desc" ] && _task_desc="General project task"
    assess_complexity "$_task_desc"
    apply_complexity_routing
    unset _task_desc
fi

run_orchestration
