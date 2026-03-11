#!/usr/bin/env bash
# lib/parallel_core.sh — Parallel build: tmux sessions, wave orchestration, worktrees, IPC, result collection.
# Spec references: spec-14 (parallel build), spec-15 (tmux management),
#                  spec-18 (file ownership)

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
            "cd \"$worktree\" && bash \"${project_root}/.automaton/wave/builder-wrapper.sh\" $i $wave \"$project_root\"; exit"

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

    PARALLEL_PLAN_PROMPT=$(mktemp "${TMPDIR:-/tmp}/automaton-plan-XXXXXX.md") || { log "CONDUCTOR" "Failed to create temp file"; return 1; }
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
    ' > "${tasks_file}.tmp" && mv "${tasks_file}.tmp" "$tasks_file"

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

    # Check for any shared file (use arrays to handle filenames with spaces)
    local -a arr1 arr2
    IFS=',' read -ra arr1 <<< "$task1_files"
    IFS=',' read -ra arr2 <<< "$task2_files"
    local f1 f2
    for f1 in "${arr1[@]}"; do
        for f2 in "${arr2[@]}"; do
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

    total=$(grep -c '^\- \[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null) || total=0
    if [ "$total" -eq 0 ]; then
        log "CONDUCTOR" "Task annotations: 0/0 (no incomplete tasks)"
        return 0
    fi

    # Count annotation lines that follow a [ ] task line
    # We count <!-- files: lines in the plan as proxy for annotated tasks
    annotated=$(grep -c '<!-- files:' IMPLEMENTATION_PLAN.md 2>/dev/null) || annotated=0
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
AUTOMATON_INSTALL_DIR="__AUTOMATON_INSTALL_DIR__"
AUTOMATON_DIR="__AUTOMATON_DIR__"

# ---- Derived paths ----
ASSIGNMENTS_FILE="$AUTOMATON_DIR/wave/assignments.json"
RESULT_FILE="$AUTOMATON_DIR/wave/results/builder-${BUILDER_NUM}.json"

# ---- Read assignment from assignments.json ----
assignment=$(jq ".assignments[$((BUILDER_NUM - 1))]" "$ASSIGNMENTS_FILE")
task=$(echo "$assignment" | jq -r '.task')
task_line=$(echo "$assignment" | jq -r '.task_line')
files_owned=$(echo "$assignment" | jq -r '.files_owned | join(", ")')

# ---- Inject builder-specific data into <dynamic_context> (spec-30) ----
# All builders share an identical static prompt prefix (everything before
# <dynamic_context>) so the cache entry created by builder-1 is reused by
# builders 2..N, saving 90% on input tokens for subsequent builders.
PROMPT_FILE=$(mktemp) || { echo "Failed to create temp file" >&2; exit 1; }
BUILD_PROMPT="$AUTOMATON_INSTALL_DIR/PROMPT_build.md"

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
_tmp_output=$(mktemp) || { echo "Failed to create temp file" >&2; exit 1; }
claude "${claude_args[@]}" < "$PROMPT_FILE" > "$_tmp_output" 2>&1
exit_code=$?
set -e

# ---- Truncate output (spec-49, inlined since wrapper is standalone) ----
_total_lines=$(wc -l < "$_tmp_output" 2>/dev/null || echo 0)
_total_lines=$((_total_lines + 0))
_OUT_MAX=200; _OUT_HEAD=50; _OUT_TAIL=150
if [ "$_total_lines" -le "$_OUT_MAX" ]; then
    AGENT_RESULT=$(cat "$_tmp_output")
else
    _logs_dir="$AUTOMATON_DIR/logs"
    mkdir -p "$_logs_dir"
    cp "$_tmp_output" "$_logs_dir/output_build_${BUILDER_NUM}_$(date +%s).log"
    _trunc=$((_total_lines - _OUT_HEAD - _OUT_TAIL))
    AGENT_RESULT=$(head -n "$_OUT_HEAD" "$_tmp_output"; echo "... [$_trunc lines truncated] ..."; tail -n "$_OUT_TAIL" "$_tmp_output")
fi
rm -f "$_tmp_output"

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
    sed -i "s|__AUTOMATON_INSTALL_DIR__|${AUTOMATON_INSTALL_DIR}|g" "$wrapper"
    sed -i "s|__AUTOMATON_DIR__|${AUTOMATON_DIR}|g" "$wrapper"

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
       "$rate_file" > "$tmp" && mv "$tmp" "$rate_file" \
       || log "CONDUCTOR" "WARNING: Failed to update rate state for backoff"

    # Wait for the backoff period
    log "CONDUCTOR" "Rate limit backoff: waiting ${backoff}s"
    sleep "$backoff"

    # Clear backoff
    jq '.backoff_until = null' "$rate_file" > "$tmp" && mv "$tmp" "$rate_file" \
       || log "CONDUCTOR" "WARNING: Failed to clear backoff state"

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
       "$rate_file" > "$tmp" && mv "$tmp" "$rate_file" \
       || log "CONDUCTOR" "WARNING: Failed to update rate history"

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
        if ! bash -c "$BUILD_COMMAND" >/dev/null 2>&1; then
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
    completed_after=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null) || completed_after=0
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
    remaining_tasks=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null) || remaining_tasks=0

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
    total_tasks=$(grep -c '\[ \]\|\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null) || total_tasks=0
    completed_tasks=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null) || completed_tasks=0

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
            remaining=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null) || remaining=0
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
        COMPLETED_BEFORE_WAVE=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null) || COMPLETED_BEFORE_WAVE=0

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

