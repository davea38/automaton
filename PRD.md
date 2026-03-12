# Automaton: Product Requirements Document

## 1. Vision

Automaton is a **collaborative software mentor** that can also run as an **autonomous factory**. It guides users through the best way to create software with AI — explaining decisions, teaching patterns, and pausing at key milestones for approval — while retaining the ability to run end-to-end unattended for experienced users.

**Two modes, one system:**

- **Collaborative (default):** Automaton walks alongside you. It researches, explains what it found and why. It plans, shows you the task breakdown and reasoning. It builds, then reviews and teaches you what it learned. At each phase transition, you approve, modify, pause, or abort. The experience should feel like pair-programming with a senior architect who explains their thinking.

- **Autonomous:** The original vision. You talk to an architect, define what you want, and walk away. It researches, plans, builds, and reviews your project end-to-end. You come back to working software. The experience should feel like delegating to a trusted contractor.

It extends the proven RALPH loop methodology (plan/build cycles via `claude -p`) with: automated research, multi-phase orchestration, token tracking, rate limiting, budget enforcement, error recovery, collaborative checkpoints, project-aware suggestions, deep research capability, guided discovery for vague ideas, and a conversation-first UX.

The system also acts as a **project advisor**: suggesting missing features, security improvements, and best practices through a project idea garden — thinking about your software, not just building it.

## 2. Problem Statement

### What exists today

The RALPH loop (`ralph-init`) provides a solid foundation: `loop.sh` drives plan/build cycles, each iteration gets fresh context, one task per iteration, markdown checkboxes track completion, and `<promise>COMPLETE</promise>` signals termination. It works. But it requires manual phase transitions, has no research automation, no token tracking, no budget enforcement, and no quality gate that sends work back for rework.

### What's missing

1. **No research phase** - humans must manually identify libraries, patterns, and technology choices before planning begins.
2. **No conversation phase** - requirements gathering is informal; there's no structured interview process that produces specs.
3. **No review phase** - when the build loop claims COMPLETE, there's no independent verification.
4. **No token/cost tracking** - you don't know what an autonomous run costs until the bill arrives.
5. **No rate limiting** - naive agent spawning can hit 429s or blow through weekly allocations.
6. **No budget enforcement** - a runaway agent can burn $1,000+ before anyone notices.
7. **No multi-agent coordination** - single builder per iteration, no parallel execution option.
8. **No error taxonomy** - all failures get the same retry logic regardless of root cause.
9. **No stall detection** - an agent can spin for 20 iterations claiming progress while changing nothing.
10. **No resume support** - if the process is interrupted, you start over.

### What automaton delivers

A single command (`./automaton.sh`) that orchestrates five phases autonomously: converse, research, plan, build, review. It tracks every token, enforces budgets, handles rate limits, detects stalls, recovers from errors, and resumes from interruption. The RALPH loop's proven patterns are preserved and extended, not replaced.

## 3. Research Findings

### 3.1 Claude Code Agent Teams (Anthropic Official)

**What it is:** Experimental hierarchical multi-agent coordination built into Claude Code. Team lead + multiple teammates working in parallel context windows.

**Architecture:**
- Inbox-based messaging for inter-agent communication
- File ownership isolation to prevent conflicts
- Wave-based execution: tasks execute in waves based on dependency chains
- Persistent filesystem-based task lists with dependency tracking
- TeammateTool with 13 core operations
- Feature flags: Leader, Swarm, Pipeline, Watchdog patterns
- Delegate Mode restricts lead to coordination-only

**Proof point:** 16 Claude agents built a production C compiler from scratch. ~2,000 sessions over ~2 weeks. 100,000-line Rust compiler capable of building Linux 6.9. Cost: ~$20,000 (2B input tokens, 140M output tokens). Used file-based locking.

**What we steal:**
- File ownership model to prevent agent conflicts
- Wave-based execution with dependency ordering
- Cost scaling benchmarks (~$20K for 100K LOC)

### 3.2 Claude-Flow / Ruflo

**What it is:** The most feature-rich community orchestrator. TypeScript + WASM, V3 full rebuild from 250k+ LOC. 54+ specialized agents.

**Architecture:**
- RuVector + WASM integrations with Agentic Flow core
- Memory, attention, routing, and execution as first-class foundations
- MCP native support, RAG integration built-in
- Orchestration patterns: parallel, sequential, map-reduce, fork-join
- Self-learning neural capabilities
- Intelligent routing to specialized experts
- 87 specialized MCP tools

**What we steal:**
- The concept of neural routing for task-to-agent assignment (simplified to rule-based for MVP)
- Memory/attention management patterns
- The lesson that 250k+ LOC is what "impressive but opaque" looks like - we go the other direction

### 3.3 Oh My Claude Code (OMC)

**What it is:** "Teams-first" multi-agent orchestration with zero learning curve. 32 specialized agents, 40 skills.

**Architecture:**
- Execution modes: Autopilot (sequential), Ultrapilot (5 concurrent), Swarm (full team), Pipeline (stage-based), Ecomode (cost-optimized)
- Smart model routing: Haiku -> Sonnet -> Opus based on task complexity
- 3-5x speedup via automatic parallelization
- Context window sharing reduces token consumption

**What we steal:**
- Model routing by task complexity (Haiku for research subagents, Sonnet for building, Opus for planning/review)
- Multiple execution modes as a configuration option, not a code change
- The principle that cost optimization is a feature, not an afterthought

### 3.4 Gas Town

**What it is:** Steve Yegge's "coding agent factory." Mayor (central Claude Code instance) + Rigs (git repository wrappers managing agents).

**Architecture:**
- Hierarchical: Mayor has full workspace context, delegates to Rigs
- Persistent work tracking across sessions
- Repository-aware agent management

**What we steal:**
- Hierarchical orchestration pattern (our orchestrator is the "mayor")
- Persistent state tracking patterns across sessions

### 3.5 Multiclaude

**What it is:** Dan Lorenc's "brownian ratchet" - always push forward.

**Architecture:**
- Singleplayer mode: all PRs auto-merge, no human review
- Multiplayer mode: teammates review before merge
- CI-driven coordination
- Handles duplicate changes intelligently

**What we steal:**
- CI-driven validation as coordination mechanism
- Duplicate-safe merge strategies for parallel builders

### 3.6 CCSwarm

**What it is:** Rust-based multi-agent orchestration. Key innovation: git worktree isolation.

**Architecture:**
- Master Claude for orchestration + proactive task generation
- Session-Persistent Manager: 93% token reduction through context reuse
- Git Worktree Manager: each agent gets isolated filesystem + shared git history
- Multi-provider Agent Pool: Claude Code, Aider, OpenAI Codex
- Autonomous orchestration with predictive task generation based on completion patterns
- Real-time progress analysis with velocity tracking
- Dependency resolution engine

**What we steal:**
- Git worktrees as the parallelization primitive (each parallel builder gets its own worktree)
- Session persistence for token reduction
- Velocity-based task prediction (if builder averages 3 min/task, estimate remaining time)
- Stall detection via velocity tracking

### 3.7 Overstory

**What it is:** "Project-agnostic swarm system" via git worktrees + tmux. TypeScript, Bun-native.

**Architecture:**
- Git worktrees for isolated working directories
- Tmux manages concurrent session UI
- SQLite mail system for inter-agent messaging
- Tiered conflict resolution on merge
- Agent roles: builder, scout, reviewer, lead, merger, coordinator, supervisor, monitor

**What we steal:**
- Tiered merge conflict resolution (auto-resolve trivial, flag complex for human review)
- The lesson that 8 agent roles is too many - we use 5
- SQLite messaging is clever but violates our "files only" principle - we use filesystem inbox instead

### 3.8 Claude-Swarm (Hackathon Winner, Feb 2026)

**What it is:** Winner of Cerebral Valley x Anthropic hackathon. Built with Claude Agent SDK.

**Architecture:**
- Task Decomposition: Opus analyzes codebase, generates dependency graph of subtasks
- Parallel Execution: agents spawned via Claude Agent SDK
- File-level conflict detection
- Budget enforcement: token/cost limits per agent
- Quality Gate: Opus reviews combined output for correctness/consistency/completeness
- Terminal UI

**What we steal:**
- Budget enforcement per-agent (not just global)
- Quality gate pattern: Opus reviews everything before declaring complete
- File-level conflict detection for parallel builders
- Dependency graph decomposition

### 3.9 SPARC Framework

**What it is:** Specification, Pseudocode, Architecture, Refinement, Completion. Adds discipline and guardrails to autonomous code generation.

**Architecture:**
- Five sequential phases (like ours)
- Claude-Flow spawns dedicated agents per SPARC phase
- CLI-first orchestration
- Test-driven development integration

**What we steal:**
- The validation that sequential phases work (SPARC proves it)
- TDD as part of the build phase, not a separate concern
- The framing: "agile methodology for AI agents"

### 3.10 GPT-Engineer

**What it is:** 50K+ stars. Generate entire codebases from natural language specs.

**Architecture:**
- Q&A clarification process before generation
- Technical planning phase
- Iterative refinement

**What we steal:**
- Requirements clarification workflow (our Phase 0 conversation)
- The proof that "interview then build" is a pattern users want

### 3.11 Devika

**What it is:** Open-source alternative to Cognition's Devin.

**Architecture:**
- Context-aware code generation
- Aligns with existing code style/architecture

**What we steal:**
- Context-aware generation: builders should match existing project conventions
- The lesson that "delegate" models (Devin-style) feel different from "you operate" models (Claude Code-style) - we stay in the "you operate" camp

## 4. Cross-Cutting Patterns Synthesized

From analyzing all 11 projects, seven patterns emerge repeatedly:

| Pattern | Source Projects | Automaton Approach |
|---------|----------------|-------------------|
| **Token Efficiency** | CCSwarm (93% reduction), OMC (model routing) | Fresh context per iteration + model routing by phase |
| **Conflict-Free Coordination** | Agent Teams (file ownership), CCSwarm/Overstory (worktrees) | Git worktrees for parallel builders, single builder by default |
| **Cost-Aware Orchestration** | Claude-Swarm (budget enforcement), OMC (model routing) | Per-phase budgets, per-iteration limits, estimated cost in logs |
| **Dependency Management** | Agent Teams (waves), Claude-Swarm (graphs) | Dependency-ordered checkboxes in IMPLEMENTATION_PLAN.md |
| **Scalable Messaging** | Agent Teams (filesystem), Overstory (SQLite) | Filesystem-based inbox at `.automaton/inbox/` |
| **Quality Gates** | Claude-Swarm (Opus review), Multiclaude (CI) | Phase 4 review agent + test/lint/typecheck gates |
| **Monitoring** | CCSwarm (velocity), Claude-Swarm (terminal UI) | Session log with per-iteration token/cost tracking |

## 5. Proposed Architecture

### 5.1 Five-Phase System

```
Phase 0: CONVERSE (interactive)
    Human talks to Claude. Claude interviews, challenges, writes specs.
    Output: specs/*.md, PRD.md
    Gate: At least one spec exists, PRD.md is non-empty

Phase 1: RESEARCH (autonomous, max 3 iterations)
    Research agent reads specs, identifies gaps, web searches, enriches specs.
    Output: Enriched specs/*.md, updated AGENTS.md
    Gate: No TBD/TODO in specs, AGENTS.md has tech choices

Phase 2: PLAN (autonomous, max 2 iterations)
    Planning agent does gap analysis, produces dependency-ordered task list.
    Output: IMPLEMENTATION_PLAN.md with [ ] checkboxes
    Gate: At least 5 tasks, tasks reference specs, no circular deps

Phase 3: BUILD (autonomous, configurable iterations)
    Builder agent(s) execute one task per iteration, validate, commit.
    Output: Working code, [x] checkboxes
    Gate: All [ ] are [x], git diff shows code changes, tests exist

Phase 4: REVIEW (autonomous, max 2 iterations)
    Review agent runs full validation, compares against specs.
    Pass -> COMPLETE
    Fail -> New tasks in plan, return to Phase 3
    Gate: Tests pass, lint passes, types pass, specs covered
```

### 5.2 Agent Roles (Exactly Five)

| Role | Implementation | Model | Purpose |
|------|---------------|-------|---------|
| **Orchestrator** | `automaton.sh` (bash) | N/A (not an LLM) | Phase transitions, budgets, rate limits, error recovery, agent lifecycle |
| **Research Agent** | `PROMPT_research.md` via `claude -p` | Sonnet | Read specs, identify unknowns, web search, enrich specs |
| **Planning Agent** | `PROMPT_plan.md` via `claude -p` | Opus | Gap analysis, dependency ordering, task list generation |
| **Builder Agent** | `PROMPT_build.md` via `claude -p` | Sonnet (Opus for debugging) | Pick task, investigate, implement, validate, commit |
| **Review Agent** | `PROMPT_review.md` via `claude -p` | Opus | Full test suite, lint, typecheck, spec coverage verification |

The orchestrator is the only process that persists across phases. All LLM agents get fresh context each iteration. This is a deliberate design choice inherited from RALPH: fresh context prevents context pollution and keeps each iteration independent.

### 5.3 Phase Transitions

```
CONVERSE -> RESEARCH:  Human signals "specs are complete"
RESEARCH -> PLAN:      Research agent outputs COMPLETE, gates pass
PLAN     -> BUILD:     Planning agent outputs COMPLETE, gates pass
BUILD    -> REVIEW:    All [ ] are [x] in IMPLEMENTATION_PLAN.md
REVIEW   -> COMPLETE:  All gates pass
REVIEW   -> BUILD:     Gates fail, review agent creates new [ ] tasks
```

The orchestrator drives all transitions. No agent can transition itself to a different phase.

### 5.4 File Layout

```
project/
  automaton.sh                     # Master orchestrator
  automaton.config.json            # Configuration
  PROMPT_converse.md               # Phase 0: Interactive requirements
  PROMPT_research.md               # Phase 1: Automated research
  PROMPT_plan.md                   # Phase 2: Planning (from RALPH)
  PROMPT_build.md                  # Phase 3: Building (from RALPH)
  PROMPT_review.md                 # Phase 4: Review
  AGENTS.md                        # Operational guide (from RALPH)
  IMPLEMENTATION_PLAN.md           # Task list (from RALPH)
  PRD.md                           # Product requirements document
  CLAUDE.md                        # Reference file
  specs/                           # Requirement specifications
  .automaton/                      # Runtime state (gitignored)
    state.json                     # Phase, iteration, counters
    budget.json                    # Token usage and limits
    session.log                    # Append-only execution log
    agents/                        # Per-agent iteration history
    inbox/                         # Inter-agent messages (future)
```

## 6. Token Tracking & Budget System

### 6.1 Data Source

Claude CLI's `--output-format stream-json` emits usage data with every response:

```json
{
  "type": "result",
  "usage": {
    "input_tokens": 15234,
    "output_tokens": 3421,
    "cache_creation_input_tokens": 8000,
    "cache_read_input_tokens": 12000
  }
}
```

The orchestrator parses this after every agent iteration and accumulates totals.

### 6.2 Budget File (`.automaton/budget.json`)

```json
{
  "limits": {
    "max_total_tokens": 10000000,
    "max_cost_usd": 50.00,
    "per_phase": {
      "research": 500000,
      "plan": 1000000,
      "build": 7000000,
      "review": 1500000
    },
    "per_iteration": 500000
  },
  "used": {
    "total_input": 0,
    "total_output": 0,
    "total_cache_create": 0,
    "total_cache_read": 0,
    "by_phase": {
      "research": { "input": 0, "output": 0 },
      "plan": { "input": 0, "output": 0 },
      "build": { "input": 0, "output": 0 },
      "review": { "input": 0, "output": 0 }
    },
    "estimated_cost_usd": 0.00
  },
  "history": []
}
```

### 6.3 Cost Estimation

Based on published pricing:

| Model | Input (per M) | Output (per M) | Cache Write (per M) | Cache Read (per M) |
|-------|--------------|----------------|---------------------|-------------------|
| Opus | $15.00 | $75.00 | $18.75 | $1.50 |
| Sonnet | $3.00 | $15.00 | $3.75 | $0.30 |
| Haiku | $0.80 | $4.00 | $1.00 | $0.08 |

The orchestrator computes estimated cost after each iteration and logs it to `session.log`.

### 6.4 Enforcement Rules

1. **Per-iteration limit exceeded:** Kill agent, log warning, continue to next iteration.
2. **Per-phase limit exceeded:** Force phase transition (don't hard-stop the entire run).
3. **Total token limit exceeded:** Graceful shutdown, save state for resume, exit code 2.
4. **Cost limit exceeded:** Same as total token limit.

Budget exhaustion for a phase is not fatal - it forces the project forward. Budget exhaustion globally is fatal but resumable.

## 7. Rate Limiting Strategy

### 7.1 Token Bucket Algorithm

```
Config defaults:
  tokens_per_minute: 80000
  requests_per_minute: 50
  cooldown_seconds: 60
  backoff_multiplier: 2
  max_backoff_seconds: 300
```

### 7.2 Detection

Rate limits are detected by:
- Claude CLI exit code != 0
- Output containing `rate_limit`, `429`, or `overloaded`
- HTTP headers (when available): `anthropic-ratelimit-tokens-remaining`

### 7.3 Backoff Strategy

```
On rate limit detection:
  delay = cooldown_seconds
  for attempt in 1..max_retries:
    sleep(delay)
    retry
    if success: break
    delay = min(delay * backoff_multiplier, max_backoff_seconds)
```

### 7.4 Inter-Iteration Pacing

After each iteration, the orchestrator checks the token velocity over the last 3 iterations. If consumption rate exceeds 80% of the configured TPM, it inserts a cooling delay before starting the next iteration. This is proactive rate limiting - avoid the 429 rather than react to it.

### 7.5 Parallel Agent Rate Sharing

When running N parallel builders, each gets `tokens_per_minute / N` as its allocation. Two builders get 40K TPM each. Three get ~27K each. The orchestrator staggers their start times to avoid burst spikes.

## 8. Error Handling & Recovery

### 8.1 Error Taxonomy

| Error | Detection | Response | Max Retries |
|-------|-----------|----------|-------------|
| CLI exit != 0 | `$?` check | Retry with backoff | 3 |
| Rate limit (429) | grep output | Exponential backoff | 5 |
| Budget exhausted | budget.json | Graceful stop, save state | 0 (not retryable) |
| Stall (no changes) | `git diff --stat` | After 3 stalls, re-plan | 3 then escalate |
| Plan corruption | Checkbox count decreased | Restore from git | 1 then escalate |
| Network error | Exit code + error text | Same as rate limit | 5 |
| Test failure (single) | Stream-json parse | Agent handles normally | N/A |
| Test failure (repeated) | 3+ iterations same test | Escalate to review phase | 3 |
| Phase timeout | Wallclock timer | Force phase transition | 0 |

### 8.2 Stall Detection

After each iteration, the orchestrator runs `git diff --stat HEAD~1`. If diff is empty (no code changes), the stall counter increments. After 3 consecutive stalls (iterations with no meaningful changes), the orchestrator:

1. Logs warning with last 3 iteration summaries
2. Forces a re-plan (return to Phase 2) if in build phase
3. If re-plan also stalls, writes `ESCALATION: Agent stalled` to IMPLEMENTATION_PLAN.md

### 8.3 Plan Corruption Guard

Before each agent iteration, the orchestrator saves a checkpoint:
```bash
cp IMPLEMENTATION_PLAN.md .automaton/plan_checkpoint.md
```

After the iteration, it verifies:
- Count of `[x]` checkboxes only increased or stayed same
- Count of `[ ]` checkboxes only decreased or stayed same (new tasks are acceptable)
- If `[x]` count decreased, the agent destroyed completed work - restore from checkpoint

### 8.4 Escalation Protocol

When an agent cannot resolve a problem:
1. Agent writes `ESCALATION: [description]` in IMPLEMENTATION_PLAN.md
2. Orchestrator detects the ESCALATION marker on next read
3. Execution pauses, state is saved
4. Session log records: `[timestamp] [ORCHESTRATOR] ESCALATION: [description] - human intervention required`
5. Human reviews, resolves, runs `./automaton.sh --resume`

## 9. State Management

### 9.1 Design Principle

All state is file-based. No database, no daemon, no server. Every state file is inspectable with `cat`, diffable with `git diff`, recoverable with `git checkout`. This is a deliberate choice: files are the universal interface.

### 9.2 State Files

| File | Purpose | Updated |
|------|---------|---------|
| `.automaton/state.json` | Phase, iteration, counters, timestamps | Every iteration |
| `.automaton/budget.json` | Token usage, limits, cost estimates | Every iteration |
| `.automaton/session.log` | Human-readable execution log | Every event |
| `.automaton/agents/*.json` | Per-agent iteration history | Per agent run |
| `.automaton/plan_checkpoint.md` | Plan backup for corruption guard | Before each iteration |
| `IMPLEMENTATION_PLAN.md` | Task list (shared coordination artifact) | By planning/build/review agents |
| `AGENTS.md` | Operational learnings | By any agent |
| `specs/*.md` | Requirements | By converse/research agents |

### 9.3 State File Format (`state.json`)

```json
{
  "phase": "build",
  "iteration": 7,
  "phase_iteration": 4,
  "stall_count": 0,
  "consecutive_failures": 0,
  "started_at": "2026-02-26T10:00:00Z",
  "last_iteration_at": "2026-02-26T10:45:00Z",
  "parallel_builders": 1,
  "resumed_from": null
}
```

### 9.4 Resume Protocol

If `automaton.sh` is interrupted (Ctrl+C, crash, terminal close):
1. State is already saved (written after every iteration)
2. `./automaton.sh --resume` reads `.automaton/state.json`
3. Resumes from exact phase and iteration
4. Budget tracking continues from accumulated totals
5. Session log gets a `[ORCHESTRATOR] RESUMED` entry

### 9.5 Session Log Format

Greppable, append-only, human-readable:

```
[2026-02-26T10:00:00Z] [ORCHESTRATOR] Starting automaton v0.1.0
[2026-02-26T10:00:01Z] [ORCHESTRATOR] Phase: research (1/3)
[2026-02-26T10:02:30Z] [RESEARCH] Iteration 1 complete: 45,231 input / 8,102 output tokens (~$0.82)
[2026-02-26T10:02:31Z] [ORCHESTRATOR] Gate check: research completeness... PASS
[2026-02-26T10:02:32Z] [ORCHESTRATOR] Phase transition: research -> plan
```

## 10. Quality Gates

Five gates, one per phase transition:

### Gate 1: Spec Completeness (after Phase 0)

| Check | Method | On Fail |
|-------|--------|---------|
| At least one `specs/*.md` file exists | `ls specs/*.md` | Refuse to start |
| `PRD.md` exists and is non-empty | `wc -l PRD.md` | Refuse to start |
| `AGENTS.md` has project name set | `grep "Project:" AGENTS.md` | Refuse to start |

### Gate 2: Research Completeness (after Phase 1)

| Check | Method | On Fail |
|-------|--------|---------|
| Research agent signaled COMPLETE | grep output | Retry research (max 3) |
| `AGENTS.md` grew in size | `wc -l` comparison | Warning, continue |
| No `TBD` or `TODO` in specs | `grep -r "TBD\|TODO" specs/` | Retry research |

### Gate 3: Plan Validity (after Phase 2)

| Check | Method | On Fail |
|-------|--------|---------|
| At least 5 unchecked `[ ]` tasks | `grep -c '\[ \]'` | Retry plan |
| Tasks reference spec files | `grep -c 'spec'` (heuristic) | Warning, continue |
| No circular dependencies | (deferred to spec phase) | N/A |

### Gate 4: Build Completion (after Phase 3)

| Check | Method | On Fail |
|-------|--------|---------|
| All `[ ]` are now `[x]` | `grep -c '\[ \]' == 0` | Continue building |
| Git diff shows code changes | `git diff --stat` | Warning |
| Tests exist | `find . -name "*test*"` (heuristic) | Warning, continue |

### Gate 5: Review Pass (after Phase 4)

| Check | Method | On Fail |
|-------|--------|---------|
| Full test suite passes | Run test command from AGENTS.md | Create tasks, return to Phase 3 |
| Linting passes | Run lint command from AGENTS.md | Create tasks, return to Phase 3 |
| Type checking passes | Run typecheck from AGENTS.md | Create tasks, return to Phase 3 |
| Each spec has implementation | Spec-to-code traceability check | Create tasks, return to Phase 3 |

## 11. Configuration Schema

`automaton.config.json`:

```json
{
  "models": {
    "primary": "opus",
    "research": "sonnet",
    "planning": "opus",
    "building": "sonnet",
    "review": "opus",
    "subagent_default": "sonnet"
  },
  "budget": {
    "max_total_tokens": 10000000,
    "max_cost_usd": 50.00,
    "per_phase": {
      "research": 500000,
      "plan": 1000000,
      "build": 7000000,
      "review": 1500000
    },
    "per_iteration": 500000
  },
  "rate_limits": {
    "tokens_per_minute": 80000,
    "requests_per_minute": 50,
    "cooldown_seconds": 60,
    "backoff_multiplier": 2,
    "max_backoff_seconds": 300
  },
  "execution": {
    "max_iterations": {
      "research": 3,
      "plan": 2,
      "build": 0,
      "review": 2
    },
    "parallel_builders": 1,
    "stall_threshold": 3,
    "max_consecutive_failures": 3,
    "retry_delay_seconds": 10
  },
  "git": {
    "auto_push": true,
    "auto_commit": true,
    "branch_prefix": "automaton/"
  },
  "flags": {
    "dangerously_skip_permissions": true,
    "verbose": true,
    "skip_research": false,
    "skip_review": false
  }
}
```

All values have sensible defaults. The config file is optional - automaton runs with defaults if absent.

## 12. What Differentiates Automaton

### vs. Claude-Flow/Ruflo (250k+ LOC, 54 agents, neural routing)
Automaton is deliberately simple. Five roles, five phases, bash orchestrator. Everything is a text file. You can read the entire system in 30 minutes. Claude-Flow is impressive but opaque; automaton is transparent and debuggable.

### vs. Oh My Claude Code (32 agents, 5 execution modes)
OMC optimizes for breadth of capability. Automaton optimizes for depth of a single workflow: conversation -> research -> plan -> build -> review. One thing, done well.

### vs. CCSwarm (Rust, multi-provider, session persistence)
CCSwarm's 93% token reduction through session persistence is compelling but trades simplicity for statefulness. Automaton uses fresh context per iteration (RALPH's proven pattern) and accepts the token cost for independence between iterations.

### vs. Claude Code Agent Teams (official, hierarchical)
Agent Teams is the official multi-agent system from Anthropic. When it matures, automaton may adopt it for Phase 3 (build). Until then, automaton provides the orchestration layer that Agent Teams doesn't: research, conversation, review, budget enforcement, and end-to-end phase management.

### vs. RALPH loop (the foundation)
Automaton is a superset. The RALPH loop becomes Phase 2+3 of automaton. Everything RALPH does, automaton does - plus research, conversation, review, token tracking, rate limiting, budget enforcement, stall detection, plan corruption guards, and resume support.

### Core differentiators

1. **Bash orchestrator, not a server.** Zero dependencies, instant start. `automaton.sh` is a shell script, not a TypeScript/Rust application.
2. **File-based state, not SQLite or Redis.** Inspectable with `cat`, diffable with `git diff`, recoverable with `git checkout`.
3. **Sequential phases, not free-form collaboration.** Five roles in a fixed sequence vs. swarms with neural routing. Easier to reason about, debug, and explain.
4. **Single builder by default, parallel as opt-in.** Most projects are better served by one focused builder. Parallel is available for large projects but isn't the default.
5. **Conversation-first UX.** Phase 0 is a real conversation with an architect, not a config file or CLI flags.
6. **Budget as a first-class concept.** Every token is tracked, every phase has a limit, every iteration shows estimated cost.
7. **No MCP server, no daemon, no port.** CLI tool that scaffolds files and a script. Everything is text, everything is inspectable.

## 13. Communication Protocol

### Primary Channels

| Channel | Purpose | Written By | Read By |
|---------|---------|-----------|---------|
| `IMPLEMENTATION_PLAN.md` | Task coordination | Planning, Build, Review agents | All agents |
| `AGENTS.md` | Operational learnings | Any agent | All agents |
| `specs/*.md` | Requirements | Converse, Research agents | Planning, Build, Review agents |
| `PRD.md` | High-level vision | Converse agent | Research, Planning agents |
| Git history | Implementation details | Build agent | Review agent |

### Inter-Agent Inbox (Future, for Parallel Builders)

File-based inbox at `.automaton/inbox/`:

```json
{
  "from": "builder-1",
  "to": "orchestrator",
  "type": "claim",
  "task_id": "task-17",
  "files": ["src/auth/login.ts", "src/auth/session.ts"],
  "timestamp": "2026-02-26T10:30:00Z"
}
```

The orchestrator reads all inbox messages before assigning tasks, preventing file ownership conflicts between parallel builders.

## 14. CLI & Distribution

### Entry Point

```bash
npx automaton          # Scaffold into current directory
./automaton.sh         # Run (starts at Phase 1 if specs exist, Phase 0 otherwise)
./automaton.sh --resume  # Resume from saved state
```

### Scaffolded Files

`npx automaton` creates:
- `automaton.sh` (master orchestrator)
- `automaton.config.json` (with defaults)
- `PROMPT_converse.md`, `PROMPT_research.md`, `PROMPT_plan.md`, `PROMPT_build.md`, `PROMPT_review.md`
- `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `CLAUDE.md`
- `PRD.md` (empty template)
- `specs/` directory
- `.automaton/` directory (gitignored)

### What Gets Committed to Git

Everything except `.automaton/` (runtime state). The prompts, config, specs, plan, and agents file are all version-controlled. This means the project's automation setup is reproducible and reviewable.

## 15. Cost Model & Benchmarks

### Expected Cost Ranges

| Project Size | Phases Used | Estimated Cost | Estimated Tokens |
|-------------|-------------|---------------|-----------------|
| Small (< 5 specs) | All 5 | $5 - $15 | 1M - 3M |
| Medium (5-15 specs) | All 5 | $15 - $50 | 3M - 8M |
| Large (15+ specs) | All 5 | $50 - $200 | 8M - 30M |

### Cost Scaling Facts (from research)

- Single-agent usage = 4x more tokens than chat
- Multi-agent usage = 15x more tokens than chat
- Agent teams use ~7x more tokens than standard sessions
- Average $6/dev/day for single agent
- Prompt caching: 60-80% of input should be cache reads when well-optimized
- One documented case: 887K tokens/minute cost explosion with naive subagent spawning (automaton prevents this via rate limiting)
- Anthropic C compiler proof: ~$20,000 for 100K-line codebase with 16 agents over 2 weeks

## 16. Open Questions & Decisions Deferred to Specs

These are intentionally unresolved. Each becomes a spec file during implementation:

1. **Parallel builder merge strategy.** When two builders modify adjacent lines, how does the orchestrator resolve? Options: last-writer-wins, three-way merge, flag for human review. Needs experimentation.

2. **Conversation handoff signal.** What exact signal does Phase 0 emit to trigger Phase 1? Options: `<promise>SPECS_COMPLETE</promise>`, a file marker, or human runs `./automaton.sh` manually. The manual option is simplest.

3. **Research agent web search scope.** How aggressively should the research agent search? Options: only search when specs mention "TBD", search proactively for alternatives, search for security advisories. Scope affects cost significantly.

4. **Review agent spec traceability.** How does the review agent map specs to implementation? Options: naming conventions (`spec-01-auth.md` -> `src/auth/`), explicit mapping file, heuristic grep. Naming conventions are simplest.

5. **Config override precedence.** If `automaton.config.json` exists but also CLI flags are passed, which wins? Standard convention: CLI > config file > defaults.

6. **Subagent strategy within agents.** RALPH prompts already specify "500 Sonnet subagents for research, 1 for building." Should automaton modify these numbers based on budget remaining? Probably yes, but the mechanism needs design.

7. **Progress reporting.** Should automaton emit a progress summary to stdout between iterations? A one-line status like `[BUILD 7/~20] Task: Add auth middleware | $12.34 spent | 3.2M tokens` would be useful.

8. **Multi-project orchestration.** Can automaton manage multiple projects simultaneously? Gas Town's "mayor + rigs" model suggests yes, but this is out of scope for v1.

9. **Agent Teams integration.** When Anthropic's official Agent Teams feature stabilizes, should automaton adopt it for Phase 3? Likely yes, but the integration surface needs study.

10. **Prompt caching optimization.** RALPH's fresh-context-per-iteration pattern means low cache hit rates. Should automaton structure prompts to maximize `cache_read_input_tokens`? This is a performance optimization that could reduce costs 60-80% but requires careful prompt engineering.

---

*This PRD synthesizes research from 11 multi-agent orchestration projects into a single architecture designed for simplicity, debuggability, and cost awareness. It is ready to be decomposed into individual spec files in `specs/` for implementation.*
