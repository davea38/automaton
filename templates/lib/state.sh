#!/usr/bin/env bash
# lib/state.sh — Logging, state persistence, initialization, notifications, and events.
# Spec references: spec-01 (state management), spec-34 (persistent state),
#                  spec-52 (notifications), spec-55 (structured events)

log() {
    local component="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local line="[$timestamp] [$component] $message"
    echo "$line" >> "$AUTOMATON_DIR/session.log"
    echo "$line"
}

# Ensures core .automaton/ subdirectories exist.
_ensure_automaton_dirs() {
    mkdir -p "$AUTOMATON_DIR/agents" "$AUTOMATON_DIR/worktrees" "$AUTOMATON_DIR/inbox" \
             "$AUTOMATON_DIR/run-summaries"
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
        local _wn="${wave_number:-0}"
        local _wh="${wave_history:-[]}"
        local _cwf="${consecutive_wave_failures:-0}"
        # Validate wave_history is valid JSON before interpolation
        if ! echo "$_wh" | jq empty 2>/dev/null; then
            _wh="[]"
        fi
        wave_fields="  \"wave_number\": ${_wn},
  \"wave_history\": ${_wh},
  \"consecutive_wave_failures\": ${_cwf},"
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
    # Single jq invocation extracts all state values as newline-separated fields.
    # This replaces 13+ individual jq calls with one process spawn.
    local _st
    _st=$(jq -r '[
        .phase,
        (.iteration | tostring),
        (.phase_iteration | tostring),
        (.stall_count | tostring),
        (.corruption_count | tostring),
        (.replan_count | tostring),
        ((.test_failure_count // 0) | tostring),
        (.build_sub_phase // "implementation"),
        ((.scaffold_iterations_done // 0) | tostring),
        .started_at,
        (.resumed_from // "null" | tostring),
        (.phase_history | tojson),
        ((.wave_number // 0) | tostring),
        ((.wave_history // []) | tojson),
        ((.consecutive_wave_failures // 0) | tostring)
    ] | .[]' "$state_file")

    local IFS=$'\n'
    local _fields
    mapfile -t _fields <<< "$_st"
    unset IFS

    current_phase="${_fields[0]}"
    iteration="${_fields[1]}"
    phase_iteration="${_fields[2]}"
    stall_count="${_fields[3]}"
    consecutive_failures=0
    corruption_count="${_fields[4]}"
    replan_count="${_fields[5]}"
    test_failure_count="${_fields[6]}"
    build_sub_phase="${_fields[7]}"
    scaffold_iterations_done="${_fields[8]}"
    started_at="${_fields[9]}"
    resumed_from="${_fields[10]}"
    phase_history="${_fields[11]}"

    # Restore wave state for parallel mode resume
    if [ "${PARALLEL_ENABLED:-false}" = "true" ]; then
        wave_number="${_fields[12]}"
        wave_history="${_fields[13]}"
        consecutive_wave_failures="${_fields[14]}"
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
            remaining=$(grep -c '^\- \[ \]' "$plan_file" 2>/dev/null) || remaining=0
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
    _ensure_automaton_dirs

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
        done=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null) || done=0
        remaining=$(grep -c '^\- \[ \]' "$plan_file" 2>/dev/null) || remaining=0
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
AUTOMATON_DIR="${AUTOMATON_DIR:-$PROJECT_ROOT/.automaton}"

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
        total_tasks=$(grep -c '^\- \[' "$plan_file" 2>/dev/null) || total_tasks=0
        done_tasks=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null) || done_tasks=0
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
    _ensure_automaton_dirs

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

    # Initialize structured work log (spec-55)
    RUN_START_EPOCH=$(date +%s)
    if [ "${WORK_LOG_ENABLED:-false}" = "true" ]; then
        local run_ts
        run_ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)
        WORK_LOG="$AUTOMATON_DIR/work-log-${run_ts}.jsonl"
        : > "$WORK_LOG"
        ln -sf "work-log-${run_ts}.jsonl" "$AUTOMATON_DIR/work-log.jsonl"
    fi

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
    local auto_compaction="${16:-false}" diff_stat="${17:-}"

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
        --arg diff_stat "$diff_stat" \
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
            auto_compaction_detected: $auto_compaction_detected,
            diff_stat: $diff_stat
        }' > "$filename"
}

# ---------------------------------------------------------------------------
# Notifications (spec-52)
# ---------------------------------------------------------------------------

send_notification() {
    local event="$1" phase="$2" status="$3" message="$4"

    # Early return if both notification channels are disabled
    if [ -z "${NOTIFY_WEBHOOK_URL:-}" ] && [ -z "${NOTIFY_COMMAND:-}" ]; then
        return 0
    fi

    # Event filtering: skip if event is not in the configured events list
    if [ -n "${NOTIFY_EVENTS:-}" ]; then
        if ! echo ",$NOTIFY_EVENTS," | grep -qF ",$event,"; then
            return 0
        fi
    fi

    local project
    project=$(basename "${PROJECT_ROOT:-.}")
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Webhook delivery (fire-and-forget background subshell)
    if [ -n "${NOTIFY_WEBHOOK_URL:-}" ]; then
        local payload
        payload=$(jq -n \
            --arg event "$event" \
            --arg project "$project" \
            --arg phase "$phase" \
            --arg status "$status" \
            --arg message "$message" \
            --arg timestamp "$timestamp" \
            '{event: $event, project: $project, phase: $phase, status: $status, message: $message, timestamp: $timestamp}')
        local webhook_host
        webhook_host=$(echo "$NOTIFY_WEBHOOK_URL" | sed 's|https\?://||' | cut -d/ -f1 | cut -d@ -f2)
        log "ORCHESTRATOR" "[NOTIFY] POST $event to $webhook_host"
        (curl -s -m "${NOTIFY_TIMEOUT:-5}" -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$NOTIFY_WEBHOOK_URL" >/dev/null 2>&1 &)
    fi

    # Command execution (fire-and-forget background subshell)
    if [ -n "${NOTIFY_COMMAND:-}" ]; then
        log "ORCHESTRATOR" "[NOTIFY] CMD $event"
        (AUTOMATON_EVENT="$event" \
         AUTOMATON_PROJECT="$project" \
         AUTOMATON_PHASE="$phase" \
         AUTOMATON_STATUS="$status" \
         AUTOMATON_MESSAGE="$message" \
         bash -c "$NOTIFY_COMMAND" >/dev/null 2>&1 &)
    fi
}

# === Structured Work Log (spec-55) ===
# Appends one JSON line per event to the JSONL work log file.
# Usage: emit_event "event_type" '{"details":"..."}'
# Reads from global shell variables: current_phase, iteration, RUN_START_EPOCH,
# WORK_LOG, WORK_LOG_ENABLED, WORK_LOG_LEVEL.
emit_event() {
    [ "${WORK_LOG_ENABLED:-false}" = "true" ] || return 0
    local event="$1"
    local details="${2-"{}"}"
    local now_epoch elapsed_s ts

    # Log level filtering
    case "$WORK_LOG_LEVEL" in
        minimal)
            case "$event" in
                phase_start|phase_end|completion|error) ;;
                *) return 0 ;;
            esac
            ;;
        normal)
            case "$event" in
                gate_check|budget_update) return 0 ;;
            esac
            ;;
        verbose) ;;  # all events pass
    esac

    now_epoch=$(date +%s)
    elapsed_s=$((now_epoch - ${RUN_START_EPOCH:-now_epoch}))
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    printf '{"ts":"%s","event":"%s","phase":"%s","iteration":%s,"elapsed_s":%s,"details":%s}\n' \
        "$ts" "$event" "${current_phase:-orchestrator}" \
        "${iteration:-0}" "$elapsed_s" "$details" >> "${WORK_LOG:-/dev/null}"
}
