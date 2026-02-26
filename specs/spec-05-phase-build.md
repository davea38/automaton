# Spec 05: Phase 3 - Build

## Purpose

The build phase executes tasks from `IMPLEMENTATION_PLAN.md` one at a time, each in a fresh Claude context. This is the existing RALPH build loop, extended with parallel builder support (opt-in) and orchestrator-level monitoring.

## How It Runs (Single Builder - Default)

```bash
result=$(cat PROMPT_build.md | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model sonnet \
    --verbose)
```

Uses the existing `PROMPT_build.md` from RALPH templates. The orchestrator loops until all tasks are `[x]` or limits are hit.

## Prompt Behavior (Inherited from RALPH)

The build prompt (already defined in `PROMPT_build.md`) instructs Claude to:

1. **Load Context:** Study AGENTS.md, IMPLEMENTATION_PLAN.md, relevant specs.
2. **Pick One Task:** Select the most important incomplete task. Ultrathink about dependencies.
3. **Investigate:** Study existing codebase related to the task (up to 500 Sonnet subagents for research, 1 for building).
4. **Implement:** Complete implementation. No placeholders, no TODOs, no stubs.
5. **Validate:** Run tests, type checking, linting, build (1 Sonnet subagent for backpressure).
6. **Update and Commit:** Mark task `[x]`, add discovered tasks, note bugs, git commit.

### Rules (from RALPH)
- One task per iteration, then stop
- No migrations or adapters - single sources of truth
- Implement completely, no placeholders
- Keep 5 recent `[x]` checkboxes visible (loop script counts them)
- Update AGENTS.md with operational learnings (keep under 60 lines)
- Output `<promise>COMPLETE</promise>` when all `[ ]` are `[x]`

## Single Builder Mode (Default)

Identical to the RALPH build loop. One `claude -p` invocation per iteration, fresh context each time, sequential task execution. This is the proven pattern.

Configuration: `execution.parallel_builders: 1`

## Parallel Builder Mode (Opt-In)

When `execution.parallel_builders` > 1, the orchestrator:

1. Reads `IMPLEMENTATION_PLAN.md` to find incomplete tasks
2. Identifies N non-conflicting tasks (tasks that don't touch the same files)
3. Creates N git worktrees: `.automaton/worktrees/builder-1/`, `.automaton/worktrees/builder-2/`, etc.
4. Spawns N `claude -p` processes concurrently, each in its own worktree
5. Waits for all to complete
6. Merges worktrees back to main branch
7. Handles merge conflicts (auto-resolve trivial, escalate complex)

### File Conflict Prevention

Before assigning tasks to parallel builders:
- Parse each task for likely file paths (heuristic: look for paths in task description)
- Ensure no two builders are assigned tasks that reference the same files
- If conflict detected, serialize those tasks (assign to same builder sequentially)

### Merge Strategy

After parallel builders complete:
1. Merge builder-1's worktree to main (fast-forward if possible)
2. For each subsequent builder, attempt three-way merge
3. If auto-merge succeeds, continue
4. If conflict, log the conflict details and escalate to next single-builder iteration to resolve

### Rate Sharing

Each parallel builder gets `tokens_per_minute / N` allocation. The orchestrator staggers start times by 5 seconds to avoid burst spikes.

## Iteration Limits

| Setting | Default | Config Key |
|---------|---------|-----------|
| Max iterations | 0 (unlimited) | execution.max_iterations.build |
| Per-iteration token limit | 500K | budget.per_iteration |
| Phase token budget | 7M | budget.per_phase.build |
| Parallel builders | 1 | execution.parallel_builders |

## Quality Gate (Gate 4) Checks

After build loop completes (all `[x]` or limits hit):

| Check | Method | On Fail |
|-------|--------|---------|
| All tasks complete | `grep -c '\[ \]' IMPLEMENTATION_PLAN.md` == 0 | Continue building |
| Code was actually written | `git diff --stat` shows changes | Warning |
| Tests exist | `find . -name "*test*" -o -name "*spec*"` | Warning, continue |

## Orchestrator Monitoring Per Iteration

After each build iteration, the orchestrator:
1. Parses token usage from stream-json output
2. Updates budget tracking
3. Checks for stalls (`git diff --stat HEAD~1`)
4. Checks for plan corruption (checkbox counts)
5. Logs iteration summary to session.log
6. Emits one-line status to stdout
