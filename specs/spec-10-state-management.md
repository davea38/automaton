# Spec 10: State Management

## Purpose

All automaton state is file-based. No database, no daemon, no server. Every state file is inspectable with `cat`, diffable with `git diff`, recoverable with `git checkout`. This spec defines all state files, their formats, and the resume protocol.

## Design Principles

1. **Files are the universal interface.** Every piece of state is a text file on disk.
2. **Write after every iteration.** State is never more than one iteration stale.
3. **Crash-safe.** If the process dies between writes, the state from the previous iteration is still valid.
4. **Human-readable.** No binary formats. JSON for structured data, plaintext for logs.

## `.automaton/` Directory Structure

```
.automaton/
  state.json              # Current phase, iteration, counters
  budget.json             # Token usage and limits (see spec-07)
  session.log             # Append-only execution log
  plan_checkpoint.md      # Plan backup for corruption guard
  agents/                 # Per-agent iteration history
    research-001.json
    plan-001.json
    build-001.json
    build-002.json
    ...
    review-001.json
  worktrees/              # Git worktrees for parallel builders (if used)
    builder-1/
    builder-2/
  inbox/                  # Inter-agent messages (future, for parallel builders)
```

The entire `.automaton/` directory should be gitignored. It's runtime state, not project state.

## State File: `state.json`

```json
{
  "version": "0.1.0",
  "phase": "build",
  "iteration": 7,
  "phase_iteration": 4,
  "stall_count": 0,
  "consecutive_failures": 0,
  "corruption_count": 0,
  "replan_count": 0,
  "started_at": "2026-02-26T10:00:00Z",
  "last_iteration_at": "2026-02-26T10:45:00Z",
  "parallel_builders": 1,
  "resumed_from": null,
  "phase_history": [
    { "phase": "research", "iterations": 2, "duration_seconds": 180 },
    { "phase": "plan", "iterations": 1, "duration_seconds": 120 }
  ]
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| version | string | Automaton version for migration compatibility |
| phase | string | Current phase: research, plan, build, review |
| iteration | number | Global iteration counter (across all phases) |
| phase_iteration | number | Iteration counter within current phase |
| stall_count | number | Consecutive stalls in current phase |
| consecutive_failures | number | Consecutive CLI failures |
| corruption_count | number | Times plan corruption was detected |
| replan_count | number | Times build phase was sent back to plan |
| started_at | ISO 8601 | When this automaton run started |
| last_iteration_at | ISO 8601 | When the last iteration completed |
| parallel_builders | number | Number of concurrent builders (from config) |
| resumed_from | string/null | Timestamp of state that was resumed, or null |
| phase_history | array | Completed phases with iteration counts and durations |

## State Write Protocol

After every iteration:

```bash
write_state() {
    local tmp=".automaton/state.json.tmp"
    # Write to temp file first (atomic on most filesystems)
    cat > "$tmp" <<EOF
{
  "version": "$VERSION",
  "phase": "$current_phase",
  "iteration": $iteration,
  "phase_iteration": $phase_iteration,
  ...
}
EOF
    mv "$tmp" ".automaton/state.json"
}
```

Write to a temp file then `mv` for atomicity. If the process dies during write, the old state.json is still intact.

## Session Log: `session.log`

Append-only, human-readable, greppable:

```
[2026-02-26T10:00:00Z] [ORCHESTRATOR] Starting automaton v0.1.0
[2026-02-26T10:00:00Z] [ORCHESTRATOR] Config: automaton.config.json
[2026-02-26T10:00:00Z] [ORCHESTRATOR] Budget: $50.00 max, 10M tokens max
[2026-02-26T10:00:01Z] [ORCHESTRATOR] Phase: research (iteration 1/3)
[2026-02-26T10:02:30Z] [RESEARCH] Iteration 1 complete: 45,231 in / 8,102 out (~$0.82)
[2026-02-26T10:02:31Z] [ORCHESTRATOR] Gate: research completeness... PASS
[2026-02-26T10:02:32Z] [ORCHESTRATOR] Phase transition: research -> plan
[2026-02-26T10:05:00Z] [PLAN] Iteration 1 complete: 89,000 in / 15,400 out (~$2.49)
[2026-02-26T10:05:01Z] [ORCHESTRATOR] Gate: plan validity... PASS (12 tasks)
[2026-02-26T10:05:02Z] [ORCHESTRATOR] Phase transition: plan -> build
[2026-02-26T10:08:00Z] [BUILD] Iteration 1 complete: 112,000 in / 24,000 out (~$2.04) | Task: Add auth middleware
[2026-02-26T10:08:01Z] [ORCHESTRATOR] Stall check: PASS (14 files changed)
[2026-02-26T10:08:01Z] [ORCHESTRATOR] Plan integrity: PASS (1 new [x])
```

### Log Format

```
[ISO-8601-TIMESTAMP] [COMPONENT] MESSAGE
```

Components: `ORCHESTRATOR`, `RESEARCH`, `PLAN`, `BUILD`, `REVIEW`

### Log Function

```bash
log() {
    local component="$1"
    local message="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$timestamp] [$component] $message" >> .automaton/session.log
    # Also echo to stdout for live monitoring
    echo "[$timestamp] [$component] $message"
}
```

## Agent History Files

Each agent invocation gets a JSON file in `.automaton/agents/`:

```json
{
  "phase": "build",
  "iteration": 7,
  "model": "sonnet",
  "prompt_file": "PROMPT_build.md",
  "started_at": "2026-02-26T10:30:00Z",
  "completed_at": "2026-02-26T10:32:25Z",
  "duration_seconds": 145,
  "exit_code": 0,
  "tokens": {
    "input": 112000,
    "output": 24000,
    "cache_create": 5000,
    "cache_read": 80000
  },
  "estimated_cost": 2.04,
  "task": "Add auth middleware",
  "status": "success",
  "files_changed": ["src/middleware/auth.ts", "src/middleware/auth.test.ts"],
  "git_commit": "abc1234"
}
```

Filename pattern: `{phase}-{NNN}.json` (e.g., `build-007.json`)

## Resume Protocol

### Saving for Resume

State is always ready for resume because `state.json` and `budget.json` are written after every iteration.

### Resuming

```bash
if [ "$1" = "--resume" ]; then
    if [ ! -f ".automaton/state.json" ]; then
        echo "Error: No state to resume from. Run without --resume."
        exit 1
    fi

    # Read saved state
    state=$(cat .automaton/state.json)
    current_phase=$(echo "$state" | jq -r '.phase')
    iteration=$(echo "$state" | jq -r '.iteration')
    phase_iteration=$(echo "$state" | jq -r '.phase_iteration')
    stall_count=$(echo "$state" | jq -r '.stall_count')
    consecutive_failures=0  # reset on resume
    resumed_from=$(echo "$state" | jq -r '.last_iteration_at')

    log "ORCHESTRATOR" "RESUMED from $resumed_from (phase: $current_phase, iteration: $iteration)"

    # Budget continues from where it left off (budget.json is persistent)
    # Jump to the appropriate phase in the main loop
fi
```

### What Resets on Resume

| Field | Resets? | Why |
|-------|---------|-----|
| phase | No | Continue where we left off |
| iteration | No | Don't re-count |
| phase_iteration | No | Don't re-count |
| stall_count | No | Stalls may persist |
| consecutive_failures | Yes (to 0) | Human presumably fixed the issue |
| corruption_count | No | Track across sessions |
| budget | No | Continue accumulating |

## Initialization

On first run (no `.automaton/` directory):

```bash
initialize() {
    mkdir -p .automaton/agents .automaton/worktrees .automaton/inbox
    write_state  # initial state.json
    initialize_budget  # initial budget.json from config
    echo "" > .automaton/session.log
    log "ORCHESTRATOR" "Initialized .automaton/ directory"
}
```

## Gitignore

The scaffolder adds to `.gitignore`:
```
.automaton/
```
