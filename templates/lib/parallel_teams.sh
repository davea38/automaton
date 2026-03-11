#!/usr/bin/env bash
# lib/parallel_teams.sh — Agent Teams build mode: team configuration, role assignment, team-specific prompts.
# Spec references: spec-28 (agent teams)

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

    local _tmp_output
    _tmp_output=$(mktemp) || { log "CONDUCTOR" "Failed to create temp file"; return 1; }
    echo "$dynamic_context" | claude "${cmd_args[@]}" > "$_tmp_output" 2>&1 || agent_exit_code=$?
    agent_result=$(truncate_output "$_tmp_output" "agent_teams" "${CURRENT_ITERATION:-0}")
    rm -f "$_tmp_output"

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
