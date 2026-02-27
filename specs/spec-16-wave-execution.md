# Spec 16: Wave Execution

## Purpose

Define the complete lifecycle of a wave — from task selection through builder completion, result collection, merge, and cleanup. A wave is one round of parallel work: the conductor assigns a batch of non-conflicting tasks to N builder windows, waits for them to finish, and merges the results. This spec defines the data formats, happy path, and all failure modes.

## Wave Lifecycle

```
1. Task Selection       — Pick non-conflicting tasks from IMPLEMENTATION_PLAN.md (spec-18)
2. Assignment File      — Write .automaton/wave/assignments.json
3. Budget Checkpoint    — Verify budget can support N builders (spec-20)
4. Builder Spawning     — Create worktrees, spawn tmux windows (staggered)
5. Completion Polling   — Wait for all builder result files
6. Result Collection    — Read and validate all result files
7. Merge Sequence       — Merge worktree branches back to main (spec-19)
8. Plan Update          — Update IMPLEMENTATION_PLAN.md with completed tasks
9. Post-Wave Verify     — Run verification checks
10. Cleanup             — Remove worktrees, clear wave directory
```

## Step 1: Task Selection

Delegates to the task partitioning algorithm (spec-18). Returns up to `max_builders` non-conflicting tasks. If fewer tasks than builders are available, the wave runs with fewer builders. If only one task is available, the conductor runs a single-builder iteration instead of a wave.

## Step 2: Assignment File

The conductor writes `.automaton/wave/assignments.json` before spawning builders:

```json
{
  "wave": 3,
  "created_at": "2026-02-26T10:30:00Z",
  "assignments": [
    {
      "builder": 1,
      "task": "Implement user authentication middleware",
      "task_line": 14,
      "files_owned": ["src/middleware/auth.ts", "src/middleware/auth.test.ts"],
      "worktree": ".automaton/worktrees/builder-1",
      "branch": "automaton/wave-3-builder-1"
    },
    {
      "builder": 2,
      "task": "Add database migration for users table",
      "task_line": 18,
      "files_owned": ["src/db/migrations/001-users.ts", "src/db/schema.ts"],
      "worktree": ".automaton/worktrees/builder-2",
      "branch": "automaton/wave-3-builder-2"
    },
    {
      "builder": 3,
      "task": "Create API error handling utilities",
      "task_line": 22,
      "files_owned": ["src/utils/errors.ts", "src/utils/errors.test.ts"],
      "worktree": ".automaton/worktrees/builder-3",
      "branch": "automaton/wave-3-builder-3"
    }
  ]
}
```

### Assignment Fields

| Field | Type | Description |
|-------|------|-------------|
| wave | number | Wave number (1-indexed) |
| created_at | ISO 8601 | When assignments were created |
| assignments[].builder | number | Builder number (1-indexed) |
| assignments[].task | string | Full task description from IMPLEMENTATION_PLAN.md |
| assignments[].task_line | number | Line number in IMPLEMENTATION_PLAN.md |
| assignments[].files_owned | string[] | Files this builder is allowed to create/modify |
| assignments[].worktree | string | Path to the builder's git worktree |
| assignments[].branch | string | Git branch name for this builder |

## Step 3: Budget Checkpoint

Before spawning builders, the conductor estimates whether the budget can support the wave:

```bash
check_wave_budget() {
    local wave=$1
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")

    # Estimate: each builder uses ~per_iteration tokens
    local estimated_tokens=$((builder_count * BUDGET_PER_ITERATION))
    local remaining=$(get_remaining_budget_tokens)

    if [ "$estimated_tokens" -gt "$remaining" ]; then
        log "CONDUCTOR" "Wave $wave: estimated ${estimated_tokens} tokens, only ${remaining} remaining"
        # Reduce builder count if possible
        local affordable=$((remaining / BUDGET_PER_ITERATION))
        if [ "$affordable" -ge 2 ]; then
            log "CONDUCTOR" "Wave $wave: reducing to $affordable builders"
            trim_assignments "$affordable"
            return 0
        fi
        return 1  # can't afford even 2 builders
    fi
    return 0
}
```

## Step 4: Builder Spawning

Builders are spawned in staggered fashion (spec-15, spec-20). Each builder:

1. Gets a git worktree created at `.automaton/worktrees/builder-N/`.
2. Gets a tmux window created with the builder wrapper script.
3. Starts `stagger_seconds` after the previous builder.

## Step 5: Completion Polling

The conductor polls for builder completion by checking for result files:

```
.automaton/wave/results/builder-1.json  — written by builder-1 on completion
.automaton/wave/results/builder-2.json  — written by builder-2 on completion
.automaton/wave/results/builder-3.json  — written by builder-3 on completion
```

Poll interval: 5 seconds. Timeout: `wave_timeout_seconds` (default 600s).

During polling, the conductor:
- Updates the dashboard with per-builder status.
- Checks for early failures (result file with `"status": "error"`).
- Does NOT interrupt other builders when one fails — let them continue.

## Step 6: Result Collection

Each builder writes a result file on completion. The conductor reads and validates all results.

### Result File Format (`results/builder-N.json`)

```json
{
  "builder": 1,
  "wave": 3,
  "status": "success",
  "task": "Implement user authentication middleware",
  "task_line": 14,
  "started_at": "2026-02-26T10:30:15Z",
  "completed_at": "2026-02-26T10:33:40Z",
  "duration_seconds": 205,
  "exit_code": 0,
  "tokens": {
    "input": 112000,
    "output": 24000,
    "cache_create": 5000,
    "cache_read": 80000
  },
  "estimated_cost": 2.04,
  "git_commit": "abc1234",
  "files_changed": ["src/middleware/auth.ts", "src/middleware/auth.test.ts"],
  "promise_complete": true
}
```

### Result Status Values

| Status | Meaning | Conductor Action |
|--------|---------|-----------------|
| `success` | Task completed, committed | Include in merge |
| `error` | CLI crash or agent failure | Re-queue task for next wave |
| `rate_limited` | Hit rate limit | Trigger global pause (spec-20) |
| `timeout` | Written by conductor on timeout | Re-queue task |
| `partial` | Agent ran but didn't complete task | Include partial work in merge, re-queue task |

## Step 7: Merge Sequence

Delegates to the merge protocol (spec-19). Merges are performed in builder order (builder-1 first, then builder-2, etc.). Only builders with `"status": "success"` or `"status": "partial"` are merged.

## Step 8: Plan Update

After merge, the conductor updates `IMPLEMENTATION_PLAN.md`:

1. For each successful builder, find the task by `task_line` and mark it `[x]`.
2. If a builder added new tasks (discovered during implementation), incorporate them.
3. Commit the updated plan: `git commit -m "automaton: wave N complete (M/N tasks)"`.

The conductor reads the updated `IMPLEMENTATION_PLAN.md` from the merged main branch, not from individual worktrees.

## Step 9: Post-Wave Verification

After merging and updating the plan:

```bash
verify_wave() {
    local wave=$1
    local pass=true

    # Check: merged code compiles/builds (if build command configured)
    # This is a lightweight check, not a full test suite
    if [ -n "$BUILD_COMMAND" ]; then
        if ! eval "$BUILD_COMMAND" >/dev/null 2>&1; then
            log "CONDUCTOR" "Wave $wave: post-merge build failed"
            pass=false
        fi
    fi

    # Check: no unresolved merge conflict markers
    if grep -r '<<<<<<< ' --include='*.ts' --include='*.js' --include='*.py' . 2>/dev/null | grep -v node_modules | grep -v .automaton; then
        log "CONDUCTOR" "Wave $wave: unresolved merge conflict markers found"
        pass=false
    fi

    # Check: plan integrity (completed count didn't decrease)
    local completed_after=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$completed_after" -lt "$COMPLETED_BEFORE_WAVE" ]; then
        log "CONDUCTOR" "Wave $wave: plan corruption detected post-merge"
        pass=false
    fi

    if ! $pass; then
        log "CONDUCTOR" "Wave $wave: verification failed. Will re-run failed tasks."
    fi

    $pass
}
```

On verification failure: revert the merge (`git reset --hard` to pre-wave state), re-queue all wave tasks, fall back to single-builder for 1 iteration, then retry wave.

## Step 10: Cleanup

```bash
cleanup_wave() {
    local wave=$1
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")

    # Remove worktrees
    for i in $(seq 1 "$builder_count"); do
        git worktree remove ".automaton/worktrees/builder-$i" --force 2>/dev/null
    done

    # Archive wave data (keep for debugging)
    mkdir -p ".automaton/wave-history"
    cp ".automaton/wave/assignments.json" ".automaton/wave-history/wave-${wave}-assignments.json"
    cp -r ".automaton/wave/results" ".automaton/wave-history/wave-${wave}-results" 2>/dev/null

    # Clear current wave directory
    rm -rf ".automaton/wave/results"
    mkdir -p ".automaton/wave/results"
    rm -f ".automaton/wave/assignments.json"

    # Kill tmux builder windows
    local session="$TMUX_SESSION_NAME"
    for i in $(seq 1 "$builder_count"); do
        tmux kill-window -t "$session:builder-$i" 2>/dev/null
    done

    log "CONDUCTOR" "Wave $wave: cleanup complete"
}
```

## Failure Modes

### Single Builder Failure

One builder fails, others succeed. The conductor:
1. Merges successful builders' work.
2. Re-queues the failed task for the next wave.
3. Logs the failure. No escalation unless failures are consecutive.

### All Builders Fail

All builders in a wave fail. The conductor:
1. Increments a `consecutive_wave_failures` counter.
2. Falls back to single-builder mode for 1 iteration to verify the codebase is sane.
3. If single-builder succeeds, retry wave dispatch.
4. If 3 consecutive wave failures, escalate per spec-09.

### Merge Conflict

A real merge conflict (not in coordination files). The conductor:
1. Aborts the merge for the conflicting builder.
2. Merges other builders' work.
3. Re-queues the conflicting task as a single-builder task in the next wave (spec-19).

### Budget Exhaustion Mid-Wave

Budget runs out while builders are running. The conductor:
1. Lets running builders finish (they've already consumed tokens).
2. Collects and merges completed work.
3. Saves state and exits with code 2 (same as v1).

## Logging

Wave events use the `CONDUCTOR` component tag:

```
[2026-02-26T10:30:00Z] [CONDUCTOR] Wave 3: starting with 3 builders
[2026-02-26T10:30:00Z] [CONDUCTOR] Wave 3: builder-1 assigned "Implement user auth middleware"
[2026-02-26T10:30:15Z] [CONDUCTOR] Wave 3: builder-2 assigned "Add database migration"
[2026-02-26T10:30:30Z] [CONDUCTOR] Wave 3: builder-3 assigned "Create API error utils"
[2026-02-26T10:33:40Z] [CONDUCTOR] Wave 3: builder-1 complete (success, 205s, ~$2.04)
[2026-02-26T10:34:10Z] [CONDUCTOR] Wave 3: builder-2 complete (success, 235s, ~$1.82)
[2026-02-26T10:34:50Z] [CONDUCTOR] Wave 3: builder-3 complete (success, 260s, ~$1.91)
[2026-02-26T10:34:51Z] [CONDUCTOR] Wave 3: merging 3 builders
[2026-02-26T10:34:55Z] [CONDUCTOR] Wave 3: merge complete, 3/3 tasks done
[2026-02-26T10:34:56Z] [CONDUCTOR] Wave 3: verification PASS
[2026-02-26T10:34:56Z] [CONDUCTOR] Wave 3: cleanup complete
```

## Dependencies on Other Specs

- Used by: spec-15-conductor (wave dispatch loop)
- Uses: spec-17-builder-agent (builder execution)
- Uses: spec-18-task-partitioning (task selection)
- Uses: spec-19-merge-protocol (merge sequence)
- Uses: spec-20-parallel-budgets (budget checkpoints)
- Extends: spec-09-error-handling (wave failure modes)
- Extends: spec-10-state-management (wave directory structure)
