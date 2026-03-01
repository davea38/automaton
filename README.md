# Automaton

Describe your project. Walk away. Come back to working software.

## What Is Automaton?

Automaton is a single bash script that orchestrates Claude CLI agents through five phases to autonomously deliver software from a conversation.

- **Zero infrastructure.** No server, no database, no daemon. Just `bash` + `jq` + `git` + `claude`.
- **Everything is a text file.** State is JSON you can `cat`. Plans are markdown you can `grep`. Logs are append-only lines you can `tail`. Every decision is in `git log`.
- **Conversation-first.** You talk to an architect, describe what you want, then walk away. Research, planning, building, and review happen autonomously.
- **Budget-aware.** Every token is tracked, every phase has a limit, every iteration shows estimated cost. Runaway agents are impossible.
- **Resumable.** Interrupted? `./automaton.sh --resume` picks up exactly where it stopped.
- **Parallel when you need it.** One builder by default. Enable parallel mode and multiple Claude agents build simultaneously in isolated git worktrees, coordinated by a conductor in tmux windows.

## Explain Like I'm 5

Imagine you want to build a house.

1. **You talk to an architect** (Phase 0: Converse). You describe your dream house. The architect asks questions, pushes back on vague ideas, and draws up blueprints (spec files).

2. **The architect researches materials** (Phase 1: Research). Picks specific brands of lumber, exact tile types, checks building codes. Updates the blueprints with real choices.

3. **A project manager writes the schedule** (Phase 2: Plan). Looks at the blueprints, figures out what gets built in what order. Foundation before walls. Walls before roof. Writes it all down as a checklist.

4. **Workers build it** (Phase 3: Build). One worker at a time by default. Or flip a switch and multiple workers build in different rooms simultaneously, each with their own set of tools, never stepping on each other's toes.

5. **An inspector checks everything** (Phase 4: Review). Walks through the whole house with the blueprints. Runs the faucets, flips the switches. If something's wrong, sends the workers back to fix it. If everything checks out, hands you the keys.

The workers, architect, and inspector are all Claude. The bash script is the general contractor managing everyone.

## Quick Start

**1. Scaffold**

```bash
npx automaton
```

This creates `automaton.sh`, prompt files, config, and a `specs/` directory in your current project.

**2. Converse**

```bash
claude
```

Claude interviews you, challenges vague requirements, and writes numbered spec files into `specs/`. When done, it tells you to run automaton.

**3. Build**

```bash
./automaton.sh
```

Automaton takes over. Research, planning, building, and review run autonomously. Come back to working software.

**To resume after interruption:**

```bash
./automaton.sh --resume
```

## How It Works: The Five Phases

```
Phase 0: CONVERSE ──> Phase 1: RESEARCH ──> Phase 2: PLAN ──> Phase 3: BUILD ──> Phase 4: REVIEW
  (interactive)        (autonomous)          (autonomous)       (autonomous)        (autonomous)
   You + Claude         Sonnet, max 3         Opus, max 2        Sonnet, unlimited    Opus, max 2
                                                                                         │
                                                                                         ▼
                                                                               PASS ──> COMPLETE
                                                                               FAIL ──> back to BUILD
```

### Phase 0: Converse (Interactive)

You run `claude` and have a conversation. Claude interviews you about core functionality, users, constraints, and non-functional requirements. It writes:
- Numbered spec files in `specs/` (e.g., `spec-01-auth.md`, `spec-02-api.md`)
- `PRD.md` with vision and problem statement
- `AGENTS.md` with project name, language, framework

This is the only interactive phase. Everything after runs autonomously.

### Phase 1: Research (Autonomous)

A Sonnet agent reads your specs, identifies unknowns (anything marked TBD, unresolved technology choices, security gaps), searches the web, and enriches specs with concrete decisions. Updates `AGENTS.md` with specific library and framework selections.

**Max iterations:** 3 | **Token budget:** 500K | **Gate:** No TBD/TODO remaining in specs

### Phase 2: Plan (Autonomous)

An Opus agent performs gap analysis across specs and existing code, then produces `IMPLEMENTATION_PLAN.md`: a dependency-ordered checklist of tasks with `[ ]` checkboxes. Each task is small, specific, and references the spec it fulfills.

**Max iterations:** 2 | **Token budget:** 1M | **Gate:** At least 5 tasks, tasks reference specs

### Phase 3: Build (Autonomous)

A Sonnet agent picks one unchecked `[ ]` task per iteration, investigates, implements, validates, commits, and marks it `[x]`. Fresh context every iteration. Continues until all tasks are complete.

**Max iterations:** unlimited | **Token budget:** 7M | **Gate:** All `[ ]` are `[x]`, code changes exist

### Phase 4: Review (Autonomous)

An Opus agent runs the full validation suite (tests, linting, type checking, build), checks spec coverage, and reviews code quality. If everything passes, it signals COMPLETE. If not, it creates new `[ ]` tasks and the orchestrator loops back to Phase 3.

**Max iterations:** 2 | **Token budget:** 1.5M | **Gate:** Tests pass, lint passes, types pass, specs covered

### Quality Gates

Five automated gates enforce transitions between phases:

| Gate | After Phase | Key Checks |
|------|-------------|------------|
| Gate 1 | Converse | Specs exist, PRD is non-empty, AGENTS.md has project name |
| Gate 2 | Research | Agent signaled COMPLETE, no TBD/TODO in specs |
| Gate 3 | Plan | At least 5 tasks, tasks reference spec files |
| Gate 4 | Build | All checkboxes complete, git diff shows changes |
| Gate 5 | Review | Tests pass, lint passes, type checks pass, specs have coverage |

## Parallel Builds

By default, automaton runs a single builder. For larger projects, enable parallel mode to run multiple Claude agents simultaneously in tmux windows.

### Enabling Parallel Mode

In `automaton.config.json`:

```json
{
  "parallel": {
    "enabled": true,
    "max_builders": 3
  }
}
```

### How It Works

Parallelism only happens during Phase 3 (Build). All other phases remain sequential.

**Architecture:**

```
tmux session: "automaton"
  ├── window 0: "conductor"   ── automaton.sh (orchestator, no Claude agent)
  ├── window 1: "builder-1"   ── Claude agent in isolated git worktree
  ├── window 2: "builder-2"   ── Claude agent in isolated git worktree
  ├── window 3: "builder-3"   ── Claude agent in isolated git worktree
  └── window 4: "dashboard"   ── live progress view (watch .automaton/dashboard.txt)
```

**Wave-based execution:** Tasks are grouped into waves. Each wave is a batch of non-conflicting tasks (no two builders touch the same file). The conductor dispatches a wave, waits for all builders to finish, merges their work, verifies, then dispatches the next wave.

**File ownership prevents conflicts:** During planning, each task is annotated with the files it will touch. The conductor uses these annotations to batch tasks into waves where no file is claimed by more than one builder.

**Builders are ephemeral:** Each builder runs in its own git worktree, branched from the current main state. It knows nothing about other builders. After merge, the worktree is destroyed.

**Three-tier merge protocol:**
1. Clean merge (no conflicts) - fast-forward or automatic
2. Coordination file conflicts (AGENTS.md, IMPLEMENTATION_PLAN.md) - auto-resolved by the conductor
3. Source code conflicts - escalated for human review

**Rate limit safety:** Each builder gets `tokens_per_minute / N` allocation. Builders are spawned with a stagger delay (default 15s) to avoid burst spikes.

### Parallel Configuration

| Field | Default | Description |
|-------|---------|-------------|
| `parallel.enabled` | `false` | Master switch for multi-window mode |
| `parallel.max_builders` | `3` | Maximum concurrent builders per wave |
| `parallel.tmux_session_name` | `"automaton"` | tmux session name |
| `parallel.stagger_seconds` | `15` | Delay between spawning builders |
| `parallel.wave_timeout_seconds` | `600` | Max wallclock time per wave |
| `parallel.dashboard` | `true` | Show live dashboard window |

### Additional Requirements

Parallel mode requires:
- `tmux` (checked at startup)
- `git` 2.5+ (for `git worktree` support)

## Configuration

All configuration lives in `automaton.config.json`. Every field is optional with sensible defaults. CLI flags override config values.

### Models

```json
{
  "models": {
    "research": "sonnet",
    "planning": "opus",
    "building": "sonnet",
    "review": "opus",
    "subagent_default": "sonnet"
  }
}
```

Valid values: `"opus"`, `"sonnet"`, `"haiku"`.

### Budget

```json
{
  "budget": {
    "mode": "api",
    "max_total_tokens": 10000000,
    "max_cost_usd": 50.00,
    "per_phase": {
      "research": 500000,
      "plan": 1000000,
      "build": 7000000,
      "review": 1500000
    },
    "per_iteration": 500000
  }
}
```

Two budget modes:
- **`"api"`** (default): Tracks USD costs based on token pricing. Hard stop when `max_cost_usd` is reached.
- **`"allowance"`**: For Max subscription users with weekly token allowances. Tracks raw token counts against `weekly_allowance_tokens` with a configurable `reserve_percentage` (default 20%) held back. Resets weekly on `allowance_reset_day`.

### Rate Limits

```json
{
  "rate_limits": {
    "tokens_per_minute": 80000,
    "requests_per_minute": 50,
    "cooldown_seconds": 60,
    "backoff_multiplier": 2,
    "max_backoff_seconds": 300
  }
}
```

Proactive pacing: if token velocity exceeds 80% of configured TPM over the last 3 iterations, automaton inserts a cooling delay. Reactive backoff: exponential backoff on 429 responses, up to 5 retries.

### Execution

```json
{
  "execution": {
    "max_iterations": {
      "research": 3,
      "plan": 2,
      "build": 0,
      "review": 2
    },
    "stall_threshold": 3,
    "max_consecutive_failures": 3,
    "retry_delay_seconds": 10,
    "phase_timeout_seconds": {
      "research": 0, "plan": 0, "build": 0, "review": 0
    }
  }
}
```

`build: 0` means unlimited iterations. Phase timeouts of `0` mean no timeout.

### Git

```json
{
  "git": {
    "auto_push": true,
    "auto_commit": true,
    "branch_prefix": "automaton/"
  }
}
```

### Flags

```json
{
  "flags": {
    "dangerously_skip_permissions": true,
    "verbose": true,
    "skip_research": false,
    "skip_review": false
  }
}
```

### Self-Build

```json
{
  "self_build": {
    "enabled": false,
    "max_files_per_iteration": 3,
    "max_lines_changed_per_iteration": 200,
    "protected_functions": ["run_orchestration", "_handle_shutdown"],
    "require_smoke_test": true
  }
}
```

## CLI Reference

### Commands

| Command | Description |
|---------|-------------|
| `npx automaton` | Scaffold automaton files into current directory |
| `./automaton.sh` | Start full pipeline from Phase 1 (requires specs from Phase 0) |
| `./automaton.sh --resume` | Resume from saved state after interruption |
| `./automaton.sh --skip-research` | Skip Phase 1, go straight to planning |
| `./automaton.sh --skip-review` | Skip Phase 4, finish after build completes |
| `./automaton.sh --config FILE` | Use alternate config file |
| `./automaton.sh --dry-run` | Show what would happen without executing |
| `./automaton.sh --self` | Self-improvement mode (automaton improves itself) |
| `./automaton.sh --self --continue` | Pick highest-priority backlog item and run one self-build cycle |
| `./automaton.sh --stats` | Display run history table and performance trends |

### Exit Codes

| Code | Meaning | Resumable? |
|------|---------|------------|
| `0` | All phases complete, review passed | N/A |
| `1` | General error | No |
| `2` | Budget exhausted | Yes (`--resume`) |
| `3` | Escalation required (human intervention needed) | Yes (`--resume` after fixing) |
| `130` | Interrupted by user (Ctrl+C) | Yes (`--resume`) |

## Project Files

After running `npx automaton`, your project contains:

```
project/
  automaton.sh               # Master orchestrator bash script (executable)
  automaton.config.json      # All configuration with defaults
  PROMPT_converse.md         # Phase 0 prompt: conversation and spec writing
  PROMPT_research.md         # Phase 1 prompt: autonomous research
  PROMPT_plan.md             # Phase 2 prompt: task breakdown and ordering
  PROMPT_build.md            # Phase 3 prompt: implementation
  PROMPT_review.md           # Phase 4 prompt: quality review
  PROMPT_self_research.md    # Self-build research prompt (used with --self)
  AGENTS.md                  # Operational guide: project name, language, learnings
  IMPLEMENTATION_PLAN.md     # Task checklist: [ ] pending, [x] complete
  PRD.md                     # Product requirements document (written in Phase 0)
  CLAUDE.md                  # Points agents to AGENTS.md
  specs/                     # Requirement specs (written in Phase 0, enriched in Phase 1)
  .automaton/                # Runtime state directory (gitignored)
    state.json               # Phase, iteration, counters, timestamps
    budget.json              # Token usage, limits, cost estimates, history
    session.log              # Append-only human-readable execution log
    agents/                  # Per-agent iteration history
    plan_checkpoint.md       # Plan backup for corruption detection
    wave/                    # Current wave state (parallel mode only)
      assignments.json       # Task-to-builder mapping
      results/               # Builder result files
    dashboard.txt            # Live progress display (parallel mode only)
    backlog.md               # Improvement tasks (self-build mode only)
    journal/                 # Run archives (self-build mode only)
      run-001/               # Archived budget, state, logs per run
```

Everything except `.automaton/` is committed to git. Runtime state is ephemeral and reconstructable from git history.

## Budget and Cost Tracking

### How It Works

Claude CLI's `--output-format=stream-json` emits token usage data with every response. The orchestrator parses this after each iteration, accumulates totals in `.automaton/budget.json`, and logs a one-line summary.

### Pricing

| Model | Input (per M) | Output (per M) | Cache Write (per M) | Cache Read (per M) |
|-------|--------------|----------------|---------------------|-------------------|
| Opus | $15.00 | $75.00 | $18.75 | $1.50 |
| Sonnet | $3.00 | $15.00 | $3.75 | $0.30 |
| Haiku | $0.80 | $4.00 | $1.00 | $0.08 |

### Enforcement

| Limit Hit | What Happens |
|-----------|--------------|
| Per-iteration exceeded | Log warning, continue (iteration already done) |
| Per-phase exceeded | Force phase transition (move forward) |
| Total tokens exceeded | Graceful shutdown, save state, exit 2 |
| Cost limit exceeded | Graceful shutdown, save state, exit 2 |

Phase budget exhaustion is not fatal -- it forces the project forward. Global budget exhaustion is fatal but resumable with `--resume`.

### Expected Costs

| Project Size | Estimated Cost | Estimated Tokens |
|-------------|---------------|-----------------|
| Small (< 5 specs) | $5 - $15 | 1M - 3M |
| Medium (5-15 specs) | $15 - $50 | 3M - 8M |
| Large (15+ specs) | $50 - $200 | 8M - 30M |

### Log Output

Each iteration logs a summary line:

```
[BUILD 7/~20] Task: Add auth middleware | ~$2.04 | budget: $18.60 remaining
```

## Error Handling and Recovery

### Error Taxonomy

| Error | Detection | Response | Max Retries |
|-------|-----------|----------|-------------|
| CLI crash | Exit code != 0 | Retry with delay | 3 |
| Rate limit (429) | Output contains `rate_limit`/`429`/`overloaded` | Exponential backoff | 5 |
| Budget exhausted | budget.json limits exceeded | Graceful stop, save state, exit 2 | Not retryable |
| Stall (no changes) | `git diff --stat` empty | After 3 stalls, return to Plan phase | 3, then escalate |
| Plan corruption | `[x]` count decreased | Restore from checkpoint | 1, then escalate |
| Network error | Output contains connection/timeout errors | Backoff like rate limit | 5 |
| Test failure (repeated) | Same test fails 3+ iterations | Escalate to Review phase | 3 |
| Phase timeout | Wallclock timer exceeded | Force phase transition | Not retryable |

### Stall Detection

After each build iteration, the orchestrator checks `git diff --stat`. If no code changed, the stall counter increments. After 3 consecutive stalls, automaton returns to the Plan phase to re-plan. If re-planning also stalls, the orchestrator escalates.

### Plan Corruption Guard

Before each iteration, the orchestrator snapshots `IMPLEMENTATION_PLAN.md`. After the iteration, it verifies the `[x]` count only increased. If an agent unchecked completed tasks, the orchestrator restores from the snapshot.

### Escalation

When automaton cannot resolve a problem, it:
1. Writes `ESCALATION: [description]` to `IMPLEMENTATION_PLAN.md`
2. Saves all state
3. Commits to git
4. Exits with code 3

You review, fix the issue, and `./automaton.sh --resume`.

### Resume

`--resume` reads `.automaton/state.json` and continues from the exact phase and iteration where execution stopped. Budget tracking continues from accumulated totals. Works after: Ctrl+C (exit 130), budget exhaustion (exit 2), and escalation (exit 3).

## Self-Improvement Mode

Automaton can improve itself. The `--self` flag activates a modified pipeline where automaton is both the orchestrator and the target project.

### How It Works

```bash
./automaton.sh --self              # Run one full self-improvement cycle
./automaton.sh --self --continue   # Pick highest-priority backlog item, estimate cost, run
./automaton.sh --stats             # View performance history and trends
```

`--self` mode changes the pipeline:
- **Skips Gate 1** (specs already exist)
- **Research** uses `PROMPT_self_research.md` focused on Claude CLI best practices and analyzing own performance data
- **Plan** reads from `.automaton/backlog.md` (improvement backlog) instead of `IMPLEMENTATION_PLAN.md`, prioritizes by estimated token savings
- **Build** enforces scope limits: max 3 files and 200 lines changed per iteration, protected functions cannot be modified
- **Review** additionally runs `bash -n automaton.sh` (syntax check) and `./automaton.sh --dry-run` (smoke test)

### Safety Guardrails

- Pre-iteration checkpointing of all modified files
- Syntax validation gate before any changes are accepted
- Smoke test (`--dry-run`) must pass after changes
- Self-modification audit log tracks every change
- Scope limits prevent large, risky modifications
- Protected functions list prevents changes to critical orchestration code

### Performance Tracking

After each run, automaton archives data to `.automaton/journal/run-{NNN}/` and tracks:
- Tokens per completed task
- Stall rate
- First-pass success rate
- Average iteration duration
- Prompt overhead ratio

### Convergence Detection

If the last 3 self-improvement runs show zero measurable improvement, automaton warns that self-improvement may have converged and suggests manual review of backlog priorities.

### Auto-Generated Backlog

After each `--self` run, automaton analyzes its journal and generates new backlog items:
- Token efficiency regression leads to investigation tasks
- Stall rate above 20% leads to prompt improvement tasks
- Prompt overhead above 50% leads to prompt size reduction tasks
- Modified-then-reverted functions lead to review tasks

## Prerequisites

**Required:**
- `claude` - Claude CLI ([install](https://docs.anthropic.com/en/docs/claude-code))
- `jq` - JSON processor
- `git` - version control
- Node.js - for `npx automaton` scaffolding

**Required for parallel mode:**
- `tmux` - terminal multiplexer
- `git` 2.5+ - for `git worktree` support

All dependencies are checked at startup with clear error messages if missing.

## How It Compares

### vs. Claude-Flow / Ruflo
Claude-Flow is the most feature-rich community orchestrator: 250K+ lines of TypeScript, 54+ specialized agents, neural routing, WASM integrations. Impressive but opaque. Automaton goes the other direction: five roles, five phases, one bash script. You can read the entire system in 30 minutes.

### vs. Oh My Claude Code (OMC)
OMC optimizes for breadth: 32 agents, 5 execution modes, smart model routing. Automaton optimizes for depth of a single workflow: converse, research, plan, build, review. One thing, done well.

### vs. Gas Town
Steve Yegge's "coding agent factory" with a Mayor orchestrating Rigs. Automaton shares the hierarchical pattern but keeps everything in plain files instead of requiring a persistent mayor process.

### vs. Claude Code Agent Teams
Anthropic's official multi-agent system uses file ownership, wave-based execution, and hierarchical coordination. When it matures, automaton may adopt it for Phase 3. Until then, automaton provides the end-to-end orchestration layer that Agent Teams does not: research, conversation, review, budget enforcement, and phase management.

### Core thesis

Transparency over sophistication. Every state file is `cat`-able, every decision is in `git log`, every dollar is tracked. The orchestrator is a bash script, not a TypeScript application. The right amount of complexity is the minimum needed for the current task.

## Architecture Evaluation

An assessment of whether the 26 specs achieve the stated goal: **using Claude CLI to manage multiple CLI windows and multiple concurrent agent streams.**

### Verdict: Yes, comprehensively.

The specs define a complete system covering three dimensions:

**Multi-window, multi-agent concurrency** (Specs 14-21):
- Spec 14 defines tmux session topology with conductor, N builders, and dashboard windows
- Spec 15 makes the orchestrator a conductor that spawns, monitors, and coordinates builder windows
- Spec 16 organizes parallel work into waves of non-conflicting tasks
- Spec 17 defines each builder as an ephemeral Claude CLI agent in its own git worktree
- Spec 18 prevents conflicts through file ownership annotations on tasks
- Spec 19 provides a three-tier merge strategy for combining concurrent work
- Spec 20 enforces rate limiting and budgets across concurrent agents
- Spec 21 provides a dashboard window for real-time visibility into all streams

**End-to-end autonomous pipeline** (Specs 01-13):
- Five distinct phases from conversation through review, with automated transitions
- Budget tracking, rate limiting, error recovery, stall detection, and resume support
- Single `./automaton.sh` command runs everything after conversation phase completes
- All state in plain text files, inspectable and recoverable

**Self-improvement** (Specs 22-26):
- Automaton can improve its own prompts, configuration, and orchestration logic
- Safety rails prevent destructive self-modification
- Performance journaling tracks improvement over time
- Convergence detection prevents infinite self-improvement loops

**No significant architectural gaps.** The 26 specs form a coherent, complete system. Two observations for users:
1. Parallel mode is opt-in (`parallel.enabled: false` by default). This is the right default for safety, but you need to know to enable it for multi-agent builds.
2. The conversation phase (Phase 0) runs separately via `claude` before `./automaton.sh`. This is the correct design (interactive vs. autonomous are fundamentally different modes) and is documented in Quick Start.

## License

MIT
