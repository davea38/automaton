# Competitive Analysis: Zeroshot (covibes/zeroshot)

## Overview

**Zeroshot** is an open-source, multi-agent AI coding orchestration CLI that runs planner, implementer, and validator agents in isolated environments, looping until changes are verified or rejected with actionable failures. It positions itself as a tool for teams where **correctness matters more than speed**.

| Attribute         | Value                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------- |
| **Language**      | JavaScript (primary), Rust (TUI), TypeScript (TUI backend)                             |
| **LOC (source)**  | ~57,000 (non-test: JS + TS + Rust); ~90,000 total including tests                     |
| **Files**         | 436 files (253 JS, 60 RS, 21 TS, 47 JSON, 22 MD)                                      |
| **Test files**    | 118 test files                                                                         |
| **Stars**         | 1,257                                                                                  |
| **Forks**         | 103                                                                                    |
| **License**       | MIT                                                                                    |
| **Last activity** | 2026-03-02 (actively maintained, near-daily commits)                                   |
| **Version**       | v5.4.0 (published on npm as `@covibes/zeroshot`)                                       |
| **Platforms**     | Linux, macOS (Windows deferred)                                                        |
| **Node**          | 18+                                                                                    |
| **Install**       | `npm install -g @covibes/zeroshot`                                                     |
| **Total issues**  | 32 (many closed; active development)                                                   |
| **Total PRs**     | 16 (most merged; rapid iteration)                                                      |

## Architecture & Structure

### High-Level Design

Zeroshot is a **message-driven coordination layer** with a pub/sub architecture backed by SQLite. It shells out to provider CLIs (Claude Code, OpenAI Codex, Gemini CLI, OpenCode) rather than calling APIs directly. The core loop is:

```
Task -> Conductor (classifies complexity x task type) -> Workflow Template -> Agents (pub/sub via message bus) -> SQLite Ledger -> Completion/Rejection
```

### Key Files & Directories

| File/Directory                          | Purpose                                                         |
| --------------------------------------- | --------------------------------------------------------------- |
| `cli/index.js`                          | CLI entry point (Commander.js), all user-facing commands        |
| `src/orchestrator.js`                   | Core cluster lifecycle: init, agent management, crash recovery  |
| `src/message-bus.js`                    | Pub/sub layer over the ledger with WebSocket broadcasting       |
| `src/ledger.js`                         | SQLite-backed immutable event log (better-sqlite3)              |
| `src/agent-wrapper.js`                  | Agent state machine: idle -> evaluating -> executing -> idle    |
| `src/logic-engine.js`                   | Trigger evaluation engine (JS predicates for conditions)        |
| `src/config-validator.js`               | Static analysis of cluster configs (deadlock, unreachable, etc) |
| `src/preflight.js`                      | Pre-run dependency validation (CLIs, auth, Docker)              |
| `src/isolation-manager.js`              | Docker container and git worktree lifecycle                     |
| `src/template-resolver.js`             | Resolves parameterized workflow templates                       |
| `src/state-snapshotter.js`              | Crash-safe state persistence and context snapshots              |
| `src/providers/`                        | Provider adapters: `anthropic/`, `openai/`, `google/`, `opencode/` |
| `src/issue-providers/`                  | Issue source adapters: GitHub, GitLab, Jira, Azure DevOps      |
| `src/agent/`                            | Agent internals: context builder, hook executor, stuck detector |
| `src/attach/`                           | Attach/detach to running daemon clusters (Unix sockets)         |
| `cluster-templates/`                    | JSON workflow definitions (single-worker, full-workflow, etc.)  |
| `cluster-templates/conductor-bootstrap.json` | Conductor agent config for task classification              |
| `cluster-hooks/`                        | Python safety hooks: `block-dangerous-git.py`, `block-ask-user-question.py` |
| `task-lib/`                             | Background task runner: scheduler, watcher, resume, store       |
| `tui-rs/`                               | Rust TUI (Ratatui) with spatial "canvas" visualization          |
| `src/tui-backend/`                      | TypeScript backend for TUI (JSON-RPC over stdio)                |
| `lib/`                                  | Shared utilities: settings, docker-config, git-remote-utils     |
| `.zeroshot/settings.json`               | Repo-local default settings                                    |
| `CLAUDE.md`                             | Comprehensive architecture/rules doc for Claude Code agents     |

### Tech Stack

- **Runtime**: Node.js 18+
- **Database**: SQLite via `better-sqlite3` (WAL mode, crash-safe)
- **CLI framework**: Commander.js
- **TUI**: Ratatui (Rust) communicating with a Node TypeScript backend over stdio JSON-RPC
- **Process management**: `node-pty` for pseudoterminal agent execution
- **Locking**: `proper-lockfile` for concurrent access
- **CI/CD**: GitHub Actions, semantic-release, merge queue enforcement
- **Testing**: Mocha + Chai + Sinon, c8 for coverage
- **Linting**: ESLint 9 (flat config) + Prettier + Husky pre-commit/pre-push

### Workflow Templates (Built-in)

| Template                  | File                                              | Agents                                      |
| ------------------------- | ------------------------------------------------- | ------------------------------------------- |
| Single Worker             | `cluster-templates/base-templates/single-worker.json`   | 1 agent (trivial tasks)                     |
| Worker + Validator        | `cluster-templates/base-templates/worker-validator.json` | Worker + 1 generic validator                |
| Full Workflow             | `cluster-templates/base-templates/full-workflow.json`    | Planner + worker + 3-5 validators           |
| Debug Workflow            | `cluster-templates/base-templates/debug-workflow.json`   | Debug-specific agent composition            |
| Quick Validation          | `cluster-templates/base-templates/quick-validation.json` | Fast validation pass                        |
| Heavy Validation          | `cluster-templates/base-templates/heavy-validation.json` | Thorough validation with multiple checkers  |

## Features

### Core Orchestration
- **2D task classification**: Conductor classifies tasks by Complexity (TRIVIAL/SIMPLE/STANDARD/CRITICAL) x TaskType (INQUIRY/TASK/DEBUG), routing to appropriate workflow templates
- **Multi-agent coordination**: Planner, implementer, and independent validators with message-bus pub/sub
- **Blind validation**: Validators never see the worker's context or code history -- they validate independently
- **Accept/reject iteration loop**: Rejections include actionable findings; worker fixes and resubmits until all validators approve
- **Dynamic agent spawning**: Conductor can add/remove agents mid-execution via CLUSTER_OPERATIONS messages
- **Model selection by complexity**: TRIVIAL uses cheapest models, CRITICAL uses most capable (level1/level2/level3 mapping to provider-specific models)
- **Adversarial testing** (STANDARD+ only): A tester agent actually uses the implementation rather than just reading tests

### Multi-Provider Support
- **Claude Code** (Anthropic): Primary supported provider
- **Codex** (OpenAI): Full support with streaming output parsing
- **Gemini CLI** (Google): Full support
- **OpenCode**: Full support
- Provider-agnostic runtime (provider aliases decoupled from orchestration logic per issue #392)
- Per-run provider override: `zeroshot run 123 --provider gemini`
- Default provider management: `zeroshot providers set-default codex`

### Multi-Platform Issue Sources
- **GitHub**: `gh` CLI, auto-detected from git remote
- **GitLab**: `glab` CLI, cloud and self-hosted instances
- **Jira**: `jira` CLI, cloud and self-hosted (Server/Data Center)
- **Azure DevOps**: `az` CLI
- Auto-detection from git remote URL (no configuration needed)
- Force flags for overriding: `--github`, `--gitlab`, `--jira`, `--devops`

### Isolation Modes
- **No isolation** (default): Agents modify files in-place
- **Git worktree** (`--worktree`): Lightweight branch isolation, <1s setup
- **Docker container** (`--docker`): Full container isolation with credential mounting
- Configurable Docker mounts: presets for `gh`, `git`, `ssh`, `aws`, `azure`, `kube`, `terraform`, `gcloud`, `claude`, `codex`, `gemini`
- Custom mount support with JSON config and env var passthrough

### Automation Pipeline
- `--pr`: Worktree + automatic PR creation
- `--ship`: Worktree + PR + auto-merge on approval
- `--pr-base <branch>`: Target specific base branch for PRs
- Background/daemon mode (`-d`): Detach and run in background
- Attach to running daemon: `zeroshot attach <id>`

### Crash Recovery & Persistence
- All state persisted to SQLite ledger (`~/.zeroshot/<id>.db`)
- Resume any cluster: `zeroshot resume <id>`
- Cluster metadata in `~/.zeroshot/clusters.json`
- State snapshots for context management across agent restarts

### TUI (Terminal UI)
- **Ratatui (Rust)**: Spatial canvas-based "Disruptive" UI with:
  - Fleet Radar: clusters rendered as spatial orbs
  - Cluster Canvas: topology nodes + edges with focus navigation
  - Agent Microscope: deep-focus single-stream view
  - Scrub bar with time controls (rewind/fast-forward through execution history)
  - Spine (command bar) with completions, hints, and intent-driven input
  - Guidance verbs: `/guide`, `/nudge`, `/interrupt`, `/pin`
  - Phase markers in margins derived from timeline
- Node.js TUI backend communicates over stdio JSON-RPC

### Developer Experience
- Preflight validation with actionable error messages and recovery steps
- Config validator catches: missing triggers, deadlocks, circular dependencies, impossible consensus
- Template preflight simulation (random schema-output topology simulation per PR #423)
- Update checker for new versions
- Shell completion support
- Export cluster conversation: `zeroshot export <id>`
- Direct SQLite access for debugging: `sqlite3 ~/.zeroshot/*.db`

### Safety & Guardrails
- Python hooks block dangerous git operations in validators
- Python hooks block `AskUserQuestion` in autonomous agents
- Pre-push hook blocks direct pushes to main/dev
- Pre-commit hook validates test files exist for new code
- CI enforces PRs to main must come from dev branch only
- Cost control via model ceilings (maxModel setting)
- Context metrics tracking to prevent runaway token usage

### Custom Workflow Support (Framework Mode)
- Define arbitrary agent topologies via JSON cluster configs
- Expert panels, staged gates, hierarchical supervisors, dynamic spawning
- Coordination primitives: message bus, triggers, ledger, dynamic spawning
- Logic script API: `ledger.query()`, `ledger.findLast()`, `cluster.getAgents()`, `helpers.allResponded()`, `helpers.hasConsensus()`

### Task Library
- Background task scheduling with cron-like scheduling
- Task commands: `run`, `list`, `status`, `logs`, `resume`, `kill`, `clean`, `schedule`, `unschedule`
- Episode tracking for multi-run analysis

## What Users Like

### Evidence from Stars & Activity
- 1,257 stars with 103 forks indicates significant community interest for a relatively new project
- Active development with near-daily commits (last updated 2026-03-02)
- Clean PR workflow with merge queue enforcement and semantic versioning

### Positive Signals from Issues
- Users are submitting **feature requests** rather than just bug reports, indicating engagement:
  - #369: Enhanced Beads/Beads-BV integration (structured task graphs, memory management)
  - #366: SSH remote execution support (users want to scale beyond local machines)
  - #390: Users want more model flexibility through OpenCode (shows provider diversity is valued)
- The TUI received massive investment (issues #267-#361, approximately 30 issues for the Disruptive TUI), suggesting users care about observability
- Multi-platform issue support (GitHub, GitLab, Jira, Azure DevOps) was implemented, reflecting enterprise demand

### Implied Strengths
- **Correctness focus**: The blind validation pattern (validators cannot see worker context) is a genuinely novel approach to AI code verification
- **Crash recovery**: SQLite-backed persistence with resume capability addresses a real pain point for long-running AI tasks
- **Provider agnosticism**: Supporting 4 AI providers (Claude, Codex, Gemini, OpenCode) reduces lock-in
- **Isolation modes**: Three levels of isolation (none, worktree, Docker) cover different risk profiles

## What Users Dislike / Struggle With

### Bug Patterns (Recurring Themes)

1. **Git-pusher reliability** (Issues #176, #340, #418): The git-pusher agent repeatedly fails to trigger or hallucinates PR creation. Issue #340 describes the agent claiming it created and merged a PR when no git operations were executed. This is a recurring, high-severity problem.

2. **Detached daemon control** (Issues #289, #290): `zeroshot stop` reports success but the daemon continues running, sometimes creating unwanted PRs. A stopped cluster was observed finishing work and opening a PR afterward.

3. **Provider-specific quirks** (Issues #370, #284, #390):
   - Codex streaming output not rendered in logs (#370)
   - Wrong provider displayed in status for detached clusters (#284)
   - Model names hardcoded to Claude aliases (opus/sonnet/haiku), blocking OpenCode models like `kimi/kimi-k2-5` (#390, still open)

4. **Detached mode flag propagation** (Issue #257): `--pr-base` flag silently dropped in daemon mode, causing PRs to target wrong branches

5. **Template simulation gaps** (Issue #418): Preflight simulation only tests base templates with synthetic messages, not the resolved cluster topology -- so preflights pass but runtime fails

### Complexity & Learning Curve
- The system is ~57,000 LOC of non-test source across 3 languages (JS, TS, Rust)
- The CLAUDE.md alone is 650 lines of rules, anti-patterns, and behavioral standards
- Custom workflow creation requires understanding message bus topics, triggers, logic scripts, hooks, and JSON config schemas
- The 2D classification model (Complexity x TaskType) is powerful but opaque to new users

### Open Pain Points (Unresolved Issues)
- **#390**: Cannot use arbitrary models through OpenCode (hard validation against opus/sonnet/haiku)
- **#368**: No static semantic linting for cluster configs -- semantically broken configs only fail at runtime after spending tokens
- **#366**: No SSH remote execution -- all agents run locally, limiting scalability
- **#369**: No structured task graph or persistent memory across runs

## Good Ideas to Poach

### 1. Blind Validation Pattern
Validators never see the worker's context, code history, or reasoning. They validate the output independently. This prevents "rubber stamp" validation where a model just agrees with itself. **Concrete implementation**: Validators are separate agent instances with their own context windows, triggered by message bus events, not shared state.

### 2. 2D Task Classification (Complexity x TaskType)
The conductor automatically classifies tasks before routing to workflow templates. A typo fix gets 1 agent with no validators; a payment flow gets 7 agents with 5 validators including security and adversarial testing. This adaptive resource allocation prevents both over-engineering simple tasks and under-validating critical ones.

### 3. Crash-Safe SQLite Ledger
All coordination state is an immutable append-only log in SQLite (WAL mode). Any cluster can be resumed from any point. The ledger also serves as the message bus backing store, so there is no distinction between "state" and "history" -- they are the same thing. File: `src/ledger.js`.

### 4. Config Validator (Static Analysis Before Execution)
Before spending any tokens, `src/config-validator.js` checks cluster configs for: missing bootstrap triggers, no path to completion, circular dependencies, impossible consensus, and orchestrator-as-executor anti-patterns. This catches structural bugs at config-load time. PR #422 extended this to validate resolved conductor topologies.

### 5. Preflight Simulation with Random Schema Outputs
PR #423 added bounded random topology simulation: after resolving templates, it samples agent outputs from declared JSON schemas and executes trigger logic, hooks, and transforms to verify the cluster can reach completion -- all without spending any API tokens.

### 6. Provider-Agnostic Shell-Out Architecture
Rather than calling AI APIs directly, Zeroshot spawns provider CLIs (`claude`, `codex`, `gemini`, `opencode`) as subprocesses. This means: zero API key management, automatic provider auth, and support for any future CLI without code changes. Each provider has a `cli-builder.js` and `output-parser.js` adapter.

### 7. Isolation Mode Cascade (`--ship` implies `--pr` implies `--worktree`)
The flag cascade is elegant: `--ship` automatically enables `--pr` which automatically enables `--worktree`. Users get the right isolation level without thinking about it. The implementation is in `cli/index.js` and `lib/start-cluster.js`.

### 8. Adversarial Tester Agent
For STANDARD+ complexity, an adversarial tester agent actually invokes the implementation (runs CLI commands, calls APIs, tries edge cases) rather than just reading test files. The principle is explicitly stated: "Tests passing does not equal implementation works. The ONLY verification is: USE IT YOURSELF."

### 9. State Snapshots for Context Management
`src/state-snapshotter.js` and `src/state-snapshot.js` maintain a running summary of cluster state (issue opened -> plan ready -> implementation ready -> validation results). This is used to build context for agents that need to understand where the cluster is in its lifecycle without reading the entire ledger.

### 10. Repo-Local Settings (`.zeroshot/settings.json`)
Per-repo configuration for default cluster topology, provider preferences, and isolation settings. No need to pass flags every run. Implemented in `lib/repo-settings.js`.

## Ideas to Improve On

### 1. Excessive Complexity for Common Cases
Zeroshot is ~57,000 LOC across 3 languages for what is fundamentally an agent orchestration loop. The Rust TUI alone (~14,900 LOC of Rust + ~3,500 LOC of TypeScript backend) nearly matches the core orchestration engine. **Automaton's opportunity**: A single bash file that does 80% of the job at 1% of the complexity. Most users want plan-implement-validate, not a spatial canvas TUI with scrub bars.

### 2. Fragile Git Integration
The recurring git-pusher failures (issues #176, #340, #418) and daemon control bugs (#289, #290) suggest that shelling out to git from multi-agent contexts is fundamentally fragile. The CLAUDE.md explicitly bans git commands in validator prompts because "git state is unreliable" and "multiple agents modify git state concurrently." **Automaton's opportunity**: Simpler, sequential git operations rather than concurrent multi-agent git access. Do one thing at a time.

### 3. Opaque Failure Modes
When a cluster fails, users must dig through SQLite ledger databases, parse message bus events, and trace trigger logic to understand what went wrong. The system has a postmortem analyzer (per troubleshooting docs), but it requires Claude Code to run. **Automaton's opportunity**: Simple, linear log output. When something fails, print the error and what to do about it. No ledger archaeology.

### 4. Provider Model Lock-In Despite "Agnostic" Claims
Issue #390 (still open) shows that model names are hardcoded to Claude aliases (opus/sonnet/haiku) even in provider-agnostic paths. Users cannot use OpenCode models like `kimi/kimi-k2-5`. The model validation rejects anything not in the hardcoded list. **Automaton's opportunity**: Accept any model string the user provides. Let the provider reject invalid models, not the orchestrator.

### 5. Heavy Dependency Chain
The `package.json` lists 17 runtime dependencies including `better-sqlite3` (native C++ addon requiring compilation), `node-pty` (native addon), `blessed` + `blessed-contrib` (legacy TUI), `ink` + `react` (React-based TUI being removed), and `md-to-pdf`. The postinstall script runs `fix-node-pty-permissions.js` and `install-tui-binary.js`. **Automaton's opportunity**: Zero dependencies. Bash + the AI CLI + git. Nothing to compile, nothing to break.

### 6. No Windows Support
Explicitly deferred: "Windows (native/WSL) is deferred while we harden reliability and multi-provider correctness." **Automaton's opportunity**: Bash runs on WSL, Git Bash, and any Unix-like environment. Simpler tools have broader platform reach.

### 7. Expensive for Simple Tasks
Even a TRIVIAL task goes through: CLI parsing -> preflight validation -> conductor classification -> template resolution -> config validation -> agent spawning via node-pty -> message bus setup -> SQLite ledger creation -> provider CLI invocation. The overhead for "fix a typo" is significant. **Automaton's opportunity**: For simple tasks, just call the AI directly with the spec. No ceremony.

### 8. TUI Over-Investment
Approximately 30 GitHub issues (#267-#361) and thousands of lines of Rust code were dedicated to the "Disruptive TUI" -- a spatial canvas with orbs, scrub bars, phase markers, and microscope views. This is impressive engineering but questionable prioritization given that core orchestration still has recurring reliability bugs (git-pusher, daemon control). **Automaton's opportunity**: Focus on reliability of the pipeline, not visualization. A simple `tail -f` of a log file covers 90% of monitoring needs.

### 9. Custom Workflow Configs Are JSON Programs
Creating custom agent topologies requires writing JSON "programs" with topics, triggers, logic scripts, hooks, and transforms. This is powerful but hard to debug and has no IDE support. Issue #368 requests static semantic linting because these configs are "effectively event-driven programs" that only fail at runtime. **Automaton's opportunity**: Opinionated defaults with override knobs rather than a full workflow DSL.

### 10. Daemon Mode Reliability
Multiple bugs relate to the daemon/detached mode: flags not propagating (#257), stop not actually stopping (#289, #290), status showing wrong provider (#284). Background process management is a hard problem in Node.js. **Automaton's opportunity**: Run in the foreground or use `nohup`/`tmux`/`screen` for backgrounding. Don't reinvent process management.
