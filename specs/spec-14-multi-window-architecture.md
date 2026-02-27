# Spec 14: Multi-Window Architecture

## Purpose

Define the architecture for running multiple Claude agents in parallel within tmux windows. This is the master spec for v2 parallelism. It introduces three window types (conductor, builder, reviewer), a wave-based execution model, and a tmux session topology. When `parallel.enabled` is `false` (the default), automaton v2 behaves identically to v1 — all parallelism is opt-in.

## Design Principles

1. **Phases stay sequential.** Research depends on specs, plan depends on research, review depends on builds. Parallelism only happens within the build phase.
2. **Opt-in only.** The `parallel.enabled` config flag is the master switch. When false, the orchestrator runs in single-builder mode exactly as v1 does.
3. **Wave-based execution.** Parallel work is organized into waves. Each wave is a batch of non-conflicting tasks assigned to N builder windows. The wave completes when all builders finish, their work is merged, and verification passes.
4. **File ownership prevents conflicts.** Each task is annotated with the files it will touch. No two builders in the same wave may own the same file.
5. **Builders are ephemeral.** A builder window is created for a wave and destroyed after merge. No state carries between waves.
6. **Conductor is the single source of truth.** Only the conductor reads/writes shared state files (`state.json`, `budget.json`, `IMPLEMENTATION_PLAN.md`). Builders communicate results through their worktree commits and a `results.json` file.

## Window Types

### Conductor (Window 0)

The conductor is the orchestrator (`automaton.sh`) running in tmux window 0. It drives the entire lifecycle:

- Runs phases 1 (research), 2 (plan), and 4 (review) as single-agent sequential invocations — unchanged from v1.
- During phase 3 (build), replaces the single-builder loop with wave dispatch.
- Spawns and monitors builder windows.
- Performs merges after each wave.
- Writes the dashboard file (`.automaton/dashboard.txt`).
- Handles all budget, rate limit, and error decisions.

The conductor never runs a Claude agent directly during the wave — it is purely a coordinator during parallel builds.

### Builder (Windows 1..N)

Each builder runs in its own tmux window within a dedicated git worktree. Builders:

- Receive a task assignment via `.automaton/wave/assignments.json`.
- Run `claude -p` with a task-specific prompt header prepended to `PROMPT_build.md`.
- Work in an isolated worktree branched from the current main state.
- Commit their changes to the worktree branch.
- Write results to `.automaton/wave/results/builder-{N}.json`.
- Exit. The window is destroyed by the conductor after merge.

Builders have no knowledge of other builders. They do not read shared state files.

### Dashboard (Window N+1, optional)

A passive window running `watch -n2 cat .automaton/dashboard.txt`. Provides a human-readable view of current wave progress, builder status, and budget. No Claude agent runs here.

## tmux Session Topology

```
automaton-session
  ├── window 0: "conductor"   — automaton.sh (orchestrator)
  ├── window 1: "builder-1"   — Claude agent in worktree (ephemeral)
  ├── window 2: "builder-2"   — Claude agent in worktree (ephemeral)
  ├── window 3: "builder-3"   — Claude agent in worktree (ephemeral)
  └── window 4: "dashboard"   — watch .automaton/dashboard.txt (optional)
```

The conductor creates the tmux session on startup if `parallel.enabled` is `true`. Builder windows are created per-wave and destroyed after merge. The dashboard window persists for the session.

## Wave-Based Execution Model

```
Conductor
  │
  ├─ Phase 1: Research (single agent, sequential — unchanged)
  ├─ Gate 2
  ├─ Phase 2: Plan (single agent, extended to annotate file ownership — see spec-18)
  ├─ Gate 3
  ├─ Phase 3: Build (wave-based parallel)
  │    ├─ Wave 1: select tasks → assign to builders → spawn → poll → merge → verify
  │    ├─ Wave 2: select tasks → assign to builders → spawn → poll → merge → verify
  │    ├─ Wave N: ...
  │    └─ (loop until all tasks [x] or limits hit)
  ├─ Gate 4
  └─ Phase 4: Review (single agent, sequential — unchanged)
```

Each wave follows the lifecycle defined in spec-16-wave-execution.

## Configuration

New config keys under a `parallel` section in `automaton.config.json`:

```json
{
  "parallel": {
    "enabled": false,
    "max_builders": 3,
    "tmux_session_name": "automaton",
    "stagger_seconds": 15,
    "wave_timeout_seconds": 600,
    "dashboard": true
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| enabled | boolean | false | Master switch for multi-window parallel mode |
| max_builders | number | 3 | Maximum builder windows per wave |
| tmux_session_name | string | "automaton" | Name of the tmux session |
| stagger_seconds | number | 15 | Delay between spawning builder windows |
| wave_timeout_seconds | number | 600 | Max wallclock time per wave (0 = none) |
| dashboard | boolean | true | Create a dashboard window |

When `parallel.enabled` is `false`, the `parallel.*` keys are ignored and the build phase runs the v1 single-builder loop from spec-05. The existing `execution.parallel_builders` config key is superseded by `parallel.max_builders` when `parallel.enabled` is `true`.

## Backward Compatibility

v2 preserves all v1 behavior:

- The `parallel.enabled: false` default means existing users see no change.
- All existing specs (01–13) remain accurate for single-builder mode.
- Existing config keys (`execution.parallel_builders`, `rate_limits.*`, `budget.*`) continue to work.
- The `.automaton/` directory gains new subdirectories (`wave/`, `dashboard.txt`) but existing files are unchanged.
- Exit codes, gate functions, and error taxonomy are unchanged. New error types for wave failures are additions, not modifications.

## New Dependencies

- **tmux**: Required when `parallel.enabled` is `true`. The orchestrator checks for tmux availability at startup (same pattern as the jq check in spec-13). If tmux is missing and `parallel.enabled` is `true`, exit with a clear error message.
- **git worktrees**: Required for builder isolation. Git version must support `git worktree` (2.5+). Checked at startup alongside tmux.

## New `.automaton/` Subdirectories

```
.automaton/
  wave/                         # Current wave state (cleared between waves)
    assignments.json            # Task-to-builder mapping (see spec-16)
    results/                    # Builder result files
      builder-1.json
      builder-2.json
      builder-3.json
  dashboard.txt                 # Human-readable status (see spec-21)
```

## Dependencies on Other Specs

- Extends: spec-01-orchestrator (conductor role), spec-05-phase-build (parallel build mode)
- Extends: spec-12-configuration (new `parallel.*` config section)
- Extends: spec-10-state-management (new `.automaton/wave/` directory)
- Depends on: spec-15-conductor, spec-16-wave-execution, spec-17-builder-agent
- Depends on: spec-18-task-partitioning, spec-19-merge-protocol
- Depends on: spec-20-parallel-budgets, spec-21-observability
