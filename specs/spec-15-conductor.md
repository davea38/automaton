# Spec 15: Conductor

## Purpose

Define how the orchestrator evolves into a conductor for multi-window coordination. During the build phase with `parallel.enabled: true`, the conductor replaces the inner build loop with wave dispatch: it selects tasks, spawns builder windows in tmux, monitors their progress, performs merges, and writes dashboard state. Outside the build phase, the conductor behaves identically to the v1 orchestrator.

## Conductor Lifecycle

```
startup
  ├─ load config (spec-12)
  ├─ check dependencies (claude, jq, git, tmux)
  ├─ create tmux session if parallel.enabled
  ├─ create dashboard window if parallel.dashboard
  ├─ run Phase 1 (research) — unchanged from v1
  ├─ run Phase 2 (plan) — extended to annotate file ownership (spec-18)
  ├─ run Phase 3 (build) — wave dispatch (this spec)
  ├─ run Phase 4 (review) — unchanged from v1
  └─ cleanup tmux session
```

## tmux Session Management

### Session Creation

```bash
start_tmux_session() {
    local session="$TMUX_SESSION_NAME"

    # Don't create if already inside a tmux session
    if [ -n "$TMUX" ]; then
        log "CONDUCTOR" "Already in tmux session. Using current session."
        return 0
    fi

    if tmux has-session -t "$session" 2>/dev/null; then
        log "CONDUCTOR" "Attaching to existing tmux session: $session"
    else
        tmux new-session -d -s "$session" -n "conductor"
        log "CONDUCTOR" "Created tmux session: $session"
    fi

    # Create dashboard window if configured
    if [ "$PARALLEL_DASHBOARD" = "true" ]; then
        tmux new-window -t "$session" -n "dashboard" \
            "watch -n2 cat .automaton/dashboard.txt"
    fi
}
```

### Session Cleanup

```bash
cleanup_tmux_session() {
    local session="$TMUX_SESSION_NAME"

    # Kill any remaining builder windows
    for i in $(seq 1 "$MAX_BUILDERS"); do
        tmux kill-window -t "$session:builder-$i" 2>/dev/null
    done

    # Kill dashboard
    tmux kill-window -t "$session:dashboard" 2>/dev/null

    log "CONDUCTOR" "Cleaned up tmux session: $session"
    # Don't kill the session itself — conductor is running in window 0
}
```

## Wave Dispatch (Build Phase)

When `parallel.enabled` is `true`, the conductor replaces the v1 build loop with:

```bash
run_parallel_build() {
    local wave_number=0

    while true; do
        wave_number=$((wave_number + 1))

        # 1. Select non-conflicting tasks for this wave (spec-18)
        local tasks=$(select_wave_tasks "$MAX_BUILDERS")
        if [ -z "$tasks" ]; then
            # No more incomplete tasks — check if all done
            local remaining=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
            if [ "$remaining" -eq 0 ]; then
                log "CONDUCTOR" "All tasks complete."
                break
            fi
            # Tasks exist but can't be parallelized — fall back to single-builder
            log "CONDUCTOR" "Wave $wave_number: falling back to single-builder for remaining tasks"
            run_single_builder_iteration
            continue
        fi

        # 2. Write assignments file (spec-16)
        write_assignments "$wave_number" "$tasks"

        # 3. Budget checkpoint (spec-20)
        if ! check_wave_budget "$wave_number"; then
            log "CONDUCTOR" "Budget insufficient for wave $wave_number. Stopping."
            break
        fi

        # 4. Spawn builder windows (staggered)
        spawn_builders "$wave_number"

        # 5. Poll for completion (spec-16)
        poll_builders "$wave_number"

        # 6. Collect results
        collect_results "$wave_number"

        # 7. Merge worktrees (spec-19)
        merge_wave "$wave_number"

        # 8. Post-wave verification
        verify_wave "$wave_number"

        # 9. Update state and dashboard
        update_wave_state "$wave_number"
        write_dashboard

        # 10. Check global limits
        if ! check_budget; then break; fi
        if ! check_phase_budget "build"; then break; fi
    done
}
```

## Builder Window Spawning

```bash
spawn_builders() {
    local wave=$1
    local session="$TMUX_SESSION_NAME"
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")
    local stagger="$PARALLEL_STAGGER_SECONDS"

    for i in $(seq 1 "$builder_count"); do
        local worktree=".automaton/worktrees/builder-$i"
        local branch="automaton/wave-${wave}-builder-${i}"

        # Create worktree (spec-19)
        git worktree add "$worktree" -b "$branch" HEAD

        # Spawn builder in tmux window
        tmux new-window -t "$session" -n "builder-$i" \
            "cd $worktree && bash $(pwd)/.automaton/wave/builder-wrapper.sh $i $wave; exit"

        log "CONDUCTOR" "Wave $wave: spawned builder-$i (branch: $branch)"

        # Stagger starts (spec-20)
        if [ "$i" -lt "$builder_count" ]; then
            sleep "$stagger"
        fi
    done
}
```

## Builder Monitoring

The conductor polls builder status by checking for result files:

```bash
poll_builders() {
    local wave=$1
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")
    local timeout="$WAVE_TIMEOUT_SECONDS"
    local start_time=$(date +%s)
    local completed=0

    while [ "$completed" -lt "$builder_count" ]; do
        completed=0
        for i in $(seq 1 "$builder_count"); do
            if [ -f ".automaton/wave/results/builder-${i}.json" ]; then
                completed=$((completed + 1))
            fi
        done

        # Update dashboard with progress
        write_dashboard

        # Check timeout
        if [ "$timeout" -gt 0 ]; then
            local elapsed=$(( $(date +%s) - start_time ))
            if [ "$elapsed" -ge "$timeout" ]; then
                log "CONDUCTOR" "Wave $wave: timeout after ${elapsed}s ($completed/$builder_count complete)"
                handle_wave_timeout "$wave"
                return 1
            fi
        fi

        sleep 5
    done

    log "CONDUCTOR" "Wave $wave: all $builder_count builders complete"
    return 0
}
```

## Wave Timeout Handling

When a wave exceeds `wave_timeout_seconds`:

1. Log which builders are still running.
2. Send SIGTERM to the timed-out builder tmux windows.
3. Wait 10 seconds for graceful shutdown.
4. Kill remaining builder windows.
5. Collect results from builders that did complete.
6. Merge completed work only.
7. Re-queue timed-out tasks for the next wave.

```bash
handle_wave_timeout() {
    local wave=$1
    local session="$TMUX_SESSION_NAME"
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")

    for i in $(seq 1 "$builder_count"); do
        if [ ! -f ".automaton/wave/results/builder-${i}.json" ]; then
            log "CONDUCTOR" "Wave $wave: builder-$i timed out. Terminating."
            tmux send-keys -t "$session:builder-$i" C-c
            sleep 10
            tmux kill-window -t "$session:builder-$i" 2>/dev/null

            # Write a timeout result
            cat > ".automaton/wave/results/builder-${i}.json" <<EOF
{
  "builder": $i,
  "wave": $wave,
  "status": "timeout",
  "task": $(jq ".assignments[$((i-1))].task" ".automaton/wave/assignments.json"),
  "exit_code": -1
}
EOF
        fi
    done
}
```

## Wave-Level Error Handling

Extends the error taxonomy from spec-09 with wave-specific errors:

| Error | Detection | Response |
|-------|-----------|----------|
| Builder timeout | Result file missing after `wave_timeout_seconds` | Kill builder, re-queue task |
| Builder crash | Result file has `"status": "error"` | Re-queue task for next wave |
| All builders crash | All result files have `"status": "error"` | Fall back to single-builder mode for 1 iteration, then retry wave |
| Merge conflict (real) | `git merge` fails on source files | Re-queue conflicting task for single-builder wave (spec-19) |
| Rate limit (any builder) | Result file has `"status": "rate_limited"` | Pause all builders, backoff, resume (spec-20) |

After 3 consecutive wave failures (all builders crash), escalate per spec-09.

## State Updates

After each wave, the conductor updates:

- `state.json`: increment `iteration` by the number of builders that succeeded, update `phase_iteration`, `last_iteration_at`. Add `wave_number` and `wave_history` fields.
- `budget.json`: aggregate token usage from all builder result files.
- `session.log`: one entry per builder plus a wave summary.
- `IMPLEMENTATION_PLAN.md`: merge the updated plan from the winning worktree (tasks marked `[x]`).

### Extended `state.json` Fields

```json
{
  "wave_number": 3,
  "wave_history": [
    { "wave": 1, "builders": 3, "succeeded": 3, "tasks_completed": 3, "duration_seconds": 180 },
    { "wave": 2, "builders": 2, "succeeded": 2, "tasks_completed": 2, "duration_seconds": 150 }
  ]
}
```

## Single-Builder Fallback

When wave dispatch cannot proceed (no parallelizable tasks, or repeated wave failures), the conductor falls back to the v1 single-builder loop from spec-05. This ensures forward progress even when parallelism is not possible.

```bash
run_single_builder_iteration() {
    # Identical to v1 build iteration
    result=$(cat PROMPT_build.md | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model "$MODEL_BUILDING" \
        --verbose)
    # ... standard v1 post-iteration checks
}
```

## Dependencies on Other Specs

- Extends: spec-01-orchestrator (replaces build loop with wave dispatch)
- Extends: spec-05-phase-build (parallel mode becomes wave-based)
- Extends: spec-09-error-handling (wave-level errors)
- Extends: spec-10-state-management (wave state fields)
- Uses: spec-16-wave-execution (wave lifecycle)
- Uses: spec-17-builder-agent (builder spawning)
- Uses: spec-18-task-partitioning (task selection)
- Uses: spec-19-merge-protocol (post-wave merge)
- Uses: spec-20-parallel-budgets (budget checkpoints)
- Uses: spec-21-observability (dashboard)
