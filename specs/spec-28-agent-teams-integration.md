# Spec 28: Agent Teams Integration

## Purpose

Specs 14-21 reimplement in bash what Claude Code Agent Teams provides natively: shared task lists, teammate self-claiming, inter-agent messaging, tmux/in-process display, and lifecycle hooks. This spec defines an opt-in Agent Teams mode as an alternative parallel execution backend, mapping automaton's wave-based task model to Agent Teams' shared task list and teammate architecture.

## Requirements

### 1. Parallel Mode Selector

Add `parallel.mode` to configuration with three values:

```json
{
  "parallel": {
    "enabled": true,
    "mode": "automaton"
  }
}
```

| Mode | Description | Default |
|------|-------------|---------|
| `"automaton"` | Current bash-orchestrated tmux + worktree model (specs 14-21). Stable, fully specified. | Yes |
| `"agent-teams"` | Claude Code Agent Teams API. Experimental, opt-in. | No |
| `"hybrid"` | Automaton orchestration with Agent Teams for teammate display and messaging. Future. | No |

When `parallel.enabled` is `false`, `parallel.mode` is ignored (single-builder mode).

### 2. Agent Teams Mode Architecture

In `agent-teams` mode, the build phase uses the Claude Code Agent Teams API instead of tmux windows and manual worktree management:

```
Orchestrator (automaton.sh)
  │
  ├─ Phase 1: Research (single agent — unchanged)
  ├─ Phase 2: Plan (single agent — unchanged)
  ├─ Phase 3: Build
  │    ├─ Start Agent Teams session
  │    ├─ Lead = automaton-build-lead agent
  │    ├─ Teammates = N automaton-builder agents (from spec-27 definitions)
  │    ├─ Shared task list populated from IMPLEMENTATION_PLAN.md
  │    ├─ Teammates self-claim and implement tasks
  │    ├─ TaskCompleted hook runs quality gates (spec-31)
  │    ├─ TeammateIdle hook detects stalls
  │    └─ Session ends when all tasks complete or budget exhausted
  └─ Phase 4: Review (single agent — unchanged)
```

### 3. Task List Population

Before starting the Agent Teams session, the orchestrator converts unchecked tasks from `IMPLEMENTATION_PLAN.md` into the Agent Teams shared task list format:

For each unchecked task `[ ] Task description`:
- Create a task with `subject` = task description
- Set `description` with file ownership annotations from spec-18 partition data
- Set dependencies between tasks based on `<!-- depends: task-N -->` annotations in the plan
- Tasks with unmet dependencies are blocked until dependency tasks complete

The task list replaces wave-based assignment (spec-16). Teammates self-claim tasks from the shared list rather than receiving pre-assigned work.

### 4. Teammate Configuration

Teammates are spawned from the `automaton-builder` agent definition (spec-27):

| Setting | Value | Rationale |
|---------|-------|-----------|
| Count | `parallel.max_builders` (default 3) | Maps to existing config |
| Permission mode | Inherited from lead (bypassPermissions) | Permissions set at spawn time |
| Display mode | `"in-process"` (default) or `"tmux"` via config | In-process requires no tmux dependency |
| File ownership | Communicated via task description | Each task includes its file list |

```json
{
  "parallel": {
    "mode": "agent-teams",
    "max_builders": 3,
    "teammate_display": "in-process"
  }
}
```

### 5. TeammateIdle Hook for Stall Detection

Use the `TeammateIdle` hook to detect stalled teammates. When a teammate is about to go idle:

The hook receives `teammate_name` and `team_name` in its input JSON. The hook script:
- Checks if unclaimed tasks remain in the task list
- If tasks remain: exit 2 with stderr "Unclaimed tasks remain — pick up the next available task" (keeps teammate working)
- If no tasks remain: exit 0 (allow idle — teammate has finished its work)

This replaces the stall detection logic in spec-16's wave polling.

`TeammateIdle` only supports command hooks.

### 6. TaskCompleted Hook for Quality Gates

Use the `TaskCompleted` hook (defined in spec-31) to run per-task quality checks before a task is marked complete:

- Receives `task_id`, `task_subject`, `task_description`, `teammate_name`
- Runs task-relevant tests (if test file exists for the modified files)
- Runs syntax validation on modified files
- Exit 0: task accepted as complete
- Exit 2: task rejected, stderr feedback tells teammate what to fix

### 7. Wave-to-Task-List Mapping

The wave model (spec-16) and Agent Teams task list are fundamentally different:

| Aspect | Automaton Waves | Agent Teams |
|--------|----------------|-------------|
| Assignment | Pre-assigned by conductor | Self-claimed by teammates |
| Ordering | Waves with barriers | Dependencies + priority |
| Isolation | Git worktrees per builder | Shared working tree (conflict risk) |
| Communication | None (file-based) | Direct messaging between teammates |
| Merge | Post-wave merge protocol | No merge needed (shared tree) |

In `agent-teams` mode:
- Wave barriers become task dependencies
- File ownership becomes task description annotations (advisory, plus hooks for enforcement)
- Merge protocol (spec-19) is not needed (shared working tree)
- Conflict risk is higher — file ownership enforcement via hooks (spec-31) is critical

### 8. Agent Teams Limitations

Document these limitations that affect automaton's design:

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| No session resumption | Cannot resume Agent Teams after interrupt | Orchestrator saves task list state; re-creates team on `--resume` |
| Task status lag | Teammates sometimes fail to mark tasks complete | Post-build verification against git diff |
| No nested teams | Teammates cannot create sub-teams | Single level of parallelism only |
| One team per session | Cannot run multiple teams concurrently | Sequential team sessions for multi-wave scenarios |
| Lead is fixed | Cannot promote teammate to lead | Lead must be the orchestrator's build agent |
| Permissions at spawn | Cannot change teammate permissions after creation | Set correctly at spawn time |
| Shared working tree | No worktree isolation by default | Rely on file ownership hooks (spec-31) for conflict prevention |

### 9. Budget Tracking Challenge

Agent Teams does not expose per-teammate `stream-json` token usage. Budget tracking in `agent-teams` mode:

- Use `SubagentStart`/`SubagentStop` hooks (spec-31) to track teammate sessions
- Parse the lead session's `stream-json` output for aggregate token usage
- Per-teammate attribution is approximate (divide aggregate by teammate count as fallback)
- Log warning: "Per-teammate token attribution is approximate in agent-teams mode"

### 10. Environment Configuration

Agent Teams requires the experimental feature flag:

```json
// .claude/settings.json or settings.local.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

The orchestrator must set this environment variable before starting the build phase in `agent-teams` mode. It should validate that the Claude Code version supports Agent Teams at startup.

### 11. Display Mode Configuration

```json
{
  "parallel": {
    "teammate_display": "in-process"
  }
}
```

| Display Mode | Requirements | Behavior |
|-------------|-------------|----------|
| `"in-process"` | None | All teammates in main terminal. Shift+Down cycles. Ctrl+T toggles task list. |
| `"tmux"` | tmux installed | Each teammate in own tmux pane. Same dependency as automaton mode. |

Default to `"in-process"` — it requires no external dependencies and works in all terminal environments except VS Code terminal, Windows Terminal, and Ghostty (where split panes are not supported).

## Acceptance Criteria

- [ ] `parallel.mode` config field with values `"automaton"`, `"agent-teams"`, `"hybrid"`
- [ ] `"automaton"` mode is default and unchanged
- [ ] `"agent-teams"` mode populates shared task list from IMPLEMENTATION_PLAN.md
- [ ] Task dependencies mapped from plan annotations to Agent Teams blocked tasks
- [ ] `TeammateIdle` hook keeps teammates working while tasks remain
- [ ] `TaskCompleted` hook enforces quality gates per task
- [ ] Agent Teams limitations documented and mitigated
- [ ] Budget tracking works in agent-teams mode (approximate per-teammate)
- [ ] `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set automatically when agent-teams mode active
- [ ] Display mode configurable between in-process and tmux

## Dependencies

- Depends on: spec-27 (agent definitions for teammates), spec-31 (hooks for TeammateIdle, TaskCompleted, file ownership)
- Extends: spec-14 (becomes one of three parallel modes)
- Extends: spec-12 (new `parallel.mode` and `parallel.teammate_display` config)
- Uses: spec-18 (task partitioning for file ownership annotations in task descriptions)
- Uses: spec-07 (budget tracking — aggregate mode)

## Files to Modify

- `automaton.sh` — add `agent-teams` mode branch in build phase, task list population, environment setup
- `automaton.config.json` — add `parallel.mode`, `parallel.teammate_display` fields
- `.claude/settings.json` — add Agent Teams environment variable and hook definitions
- `.claude/hooks/teammate-idle.sh` — new file: TeammateIdle handler
- `.claude/hooks/task-quality-gate.sh` — shared with spec-31 TaskCompleted hook
