# Competitive Analysis: Gas Town (steveyegge/gastown)

## Overview

**Gas Town** is a multi-agent orchestration system for AI coding agents (primarily Claude Code), written in Go.
It manages persistent workspaces, coordinates 20-30+ concurrent agents across multiple repositories, and tracks
all work via a git-backed issue/work ledger called "Beads."

| Metric | Value |
|--------|-------|
| **Primary Language** | Go (100% of core) |
| **Go Source LOC** | ~194,000 (non-test) + ~152,000 (tests) = ~347,000 total |
| **Markdown Docs LOC** | ~23,700 |
| **Go Files** | 940 |
| **Internal Packages** | 71 (`internal/` subdirectories) |
| **Stars** | 10,788 |
| **Forks** | 855 |
| **License** | MIT |
| **Last Updated** | 2026-03-03 (actively maintained, multiple commits per day) |
| **Description** | "Gas Town - multi-agent workspace manager" |
| **CLI Binary** | `gt` (installed via Homebrew, npm, or `go install`) |
| **Go Version** | 1.25.6 |

The project is authored by Steve Yegge and is extremely active, with issues and PRs being filed and merged
multiple times per day. The codebase is large and mature -- 347K lines of Go is a substantial engineering
investment.

## Architecture & Structure

### Directory Layout

```
cmd/
  gt/main.go                   # Main CLI entry point (cobra-based)
  gt-proxy-server/             # Remote polecat proxy server
  gt-proxy-client/             # Remote polecat proxy client
internal/                      # 71 packages (the bulk of the code)
  cmd/                         # All CLI subcommands (~131K LOC, largest package)
  daemon/                      # Background daemon (convoy manager, dogs, health, lifecycle)
  beads/                       # Issue tracking integration (Dolt SQL-backed ledger)
  polecat/                     # Worker agent management (spawn, heartbeat, session, namepool)
  witness/                     # Polecat health monitoring and lifecycle oversight
  refinery/                    # Merge queue (batch-then-bisect, Bors-style)
  convoy/                      # Work batch tracking (convoy create/check/close)
  mail/                        # Inter-agent messaging with prefix-based routing
  tmux/                        # Tmux session management for agent sessions
  formula/                     # TOML-defined workflow templates (42 built-in formulas)
  web/                         # Web dashboard (htmx-based, command palette)
  feed/                        # Real-time TUI activity dashboard (charmbracelet/bubbletea)
  telemetry/                   # OpenTelemetry integration
  config/                      # Multi-layer config (town, rig, runtime, agent presets)
  templates/                   # Role templates (mayor, polecat, witness, refinery, etc.)
  runtime/                     # Multi-agent runtime abstraction (claude, gemini, codex, copilot, etc.)
  doctor/                      # Health diagnostics and auto-repair
  plugin/                      # Plugin system (town-level and rig-level)
  hooks/                       # Git worktree-based persistent state
  ...
plugins/                       # 6 plugins (compactor-dog, rebuild-gt, session-hygiene, etc.)
templates/                     # Agent-specific templates (witness-CLAUDE.md, polecat-CLAUDE.md)
docs/                          # Extensive design docs, concepts, examples
gt-model-eval/                 # LLM evaluation suite (promptfoo-based)
npm-package/                   # npm wrapper for cross-platform binary distribution
scripts/                       # Migration, testing, and deployment scripts
.github/workflows/             # 9 CI/CD workflows (CI, e2e, release, nightly, Windows CI)
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| **CLI Framework** | `spf13/cobra` |
| **TUI** | `charmbracelet/bubbletea` + `charmbracelet/lipgloss` + `charmbracelet/glamour` |
| **Storage** | Dolt SQL Server (MySQL protocol, per-town, managed by daemon) |
| **Issue Tracking** | Beads (`steveyegge/beads`) -- git-backed structured issue data |
| **Agent Sessions** | tmux (multiplexed terminal sessions) |
| **Git Operations** | Git worktrees for polecats/refinery; full clones for crew |
| **Config** | `spf13/viper` + TOML (formulas) + JSON (settings) + YAML (beads config) |
| **Telemetry** | OpenTelemetry (OTLP HTTP exporters for logs, metrics) |
| **Testing** | testcontainers-go (Dolt integration tests), go-rod (browser e2e) |
| **Release** | GoReleaser + Homebrew + npm OIDC trusted publishing |
| **Web Dashboard** | htmx + server-rendered HTML templates |

### Key Architectural Patterns

1. **Two-level beads architecture**: Town-level (`hq-*` prefix) for cross-rig coordination;
   rig-level (project prefix) for implementation work. All stored in Dolt SQL Server.

2. **Worktree-based isolation**: Polecats and refinery are git worktrees (fast spawn, shared
   object store). Crew workspaces are full clones for human developers.

3. **Beads redirects**: Worktrees use `.beads/redirect` files pointing to the canonical beads
   location in `mayor/rig/.beads/`, ensuring all agents share a single Dolt-backed database.

4. **Role-based agent taxonomy**: 8 distinct roles (Mayor, Deacon, Boot, Dog, Witness,
   Refinery, Polecat, Crew) with templated context injection via `gt prime`.

5. **Event-driven + poll hybrid**: Daemon uses event polling (5s) for completion detection
   plus stranded scan (30s) as a safety net for crash recovery.

6. **Propulsion Principle**: Agents find work on their "hook" and execute immediately -- no
   confirmation, no waiting. This is the core throughput philosophy.

## Features

### Agent Orchestration
- **Multi-agent coordination**: Scale to 20-30+ concurrent AI agents across repositories
- **Role-based agent system**: 8 specialized roles (Mayor, Deacon, Boot, Dog, Witness, Refinery, Polecat, Crew)
- **Multi-runtime support**: Built-in presets for Claude, Gemini, Codex, Cursor, Auggie, Amp, Copilot, OpenCode, OMP, Pi
- **Agent identity and persistence**: Persistent identity with ephemeral sessions; work survives crashes
- **Hook-based work assignment**: Git worktree hooks as persistent, version-controlled work state
- **Context recovery**: `gt prime` re-injects full role context after compaction/restart
- **Handoff protocol**: Structured session cycling with context preservation (`gt handoff`)
- **Heartbeat monitoring**: Daemon watches agent health via heartbeats

### Work Tracking (Convoys & Beads)
- **Convoy system**: Batch work tracking units across multiple rigs and agents
- **Beads integration**: Git-backed issue tracking with structured data (types, priorities, dependencies)
- **Graph-aware triage**: `bv` tool provides PageRank, betweenness centrality, cycle detection for issues
- **Merge queue**: Bors-style batch-then-bisect merge queue via Refinery role
- **Cross-rig routing**: Prefix-based routing (`gt-*`, `bd-*`, `hq-*`) for transparent multi-repo operations
- **Dependency tracking**: Issue dependencies with blocking/unblocking detection

### Automation & Workflows
- **42 built-in formulas**: TOML-defined workflow templates (`internal/formula/formulas/`)
  - Patrol formulas: deacon-patrol, witness-patrol, refinery-patrol
  - Work formulas: polecat-work, polecat-code-review, polecat-conflict-resolve
  - Lifecycle: convoy-cleanup, convoy-feed, session-gc, shutdown-dance
  - Demos: towers-of-hanoi (complexity benchmarks)
- **Plugin system**: Town-level and rig-level plugins with gate types (cooldown, cron, condition, event, manual)
- **6 shipping plugins**: compactor-dog, dolt-archive, github-sheriff, quality-review, rebuild-gt, session-hygiene
- **Formula variables**: Parameterized workflows with `--var key=value` syntax

### Monitoring & Observability
- **TUI activity feed** (`gt feed`): Three-panel dashboard (agent tree, convoy panel, event stream)
- **Problems view**: Health state classification (GUPP Violation, Stalled, Zombie, Working, Idle)
- **Web dashboard** (`gt dashboard`): htmx-based browser dashboard with command palette
- **OpenTelemetry**: Structured telemetry with OTLP HTTP exporters
- **Capability ledger**: Every agent completion permanently recorded for accountability
- **Cost tracking**: `gt costs` for monitoring agent spend

### Communication
- **Inter-agent mail**: Prefix-routed mailboxes (`gt mail send <rig>/<role>`)
- **Nudge system**: Lightweight ephemeral notifications (no Dolt overhead)
- **Escalation protocol**: Severity-routed (CRITICAL/HIGH/MEDIUM) with tiered resolution (Agent -> Deacon -> Mayor -> Human)
- **Broadcast**: `gt broadcast` for town-wide announcements

### Infrastructure
- **Daemon**: Background process managing Dolt server, convoy manager, agent health, scheduled maintenance
- **Dolt SQL storage**: Single Dolt SQL Server per town (MySQL protocol, port 3307)
- **Data lifecycle**: CREATE -> LIVE -> CLOSE -> DECAY -> COMPACT -> FLATTEN (6-stage pipeline)
- **Doctor system**: `gt doctor --fix` with health diagnostics and auto-repair
- **Proxy server**: Remote polecat execution via `gt-proxy-server` / `gt-proxy-client`
- **Cross-platform**: macOS, Linux, Windows support (dedicated Windows CI)

### Developer Experience
- **Shell completions**: Bash, Zsh, Fish
- **npm distribution**: `npx @gastown/gt` with auto-binary download
- **Homebrew tap**: `brew install gastown`
- **Nix flake**: `flake.nix` for reproducible builds
- **LLM evaluation suite**: promptfoo-based model eval (`gt-model-eval/`) for testing agent decision quality

## What Users Like

### High Star Count and Active Development
With 10,788 stars and 855 forks, Gas Town has significant community interest. The project
sees multiple commits per day (issues #2281-#2284 were all filed/merged on 2026-03-03).

### Comprehensive Multi-Agent Orchestration
The role taxonomy (Mayor, Witness, Refinery, Polecat, etc.) provides a well-thought-out
division of labor. Users get persistent agent identity, crash recovery, and structured
handoff -- solving the core problem of agents losing context on restart.

### Multi-Runtime Flexibility
Support for 7+ AI coding runtimes (Claude, Gemini, Codex, Cursor, Copilot, Amp, OpenCode)
means users are not locked into a single provider. The runtime abstraction
(`internal/runtime/runtime.go`) uses a registration pattern for hook installers.

### Built-in Merge Queue
The Bors-style batch-then-bisect merge queue (Refinery role) is a sophisticated feature
that automates code integration -- not commonly found in agent orchestration tools.

### Thorough Monitoring
The `gt feed` TUI and `gt dashboard` web interface give real-time visibility. The
problems view with health states (GUPP Violation, Stalled, Zombie) proactively surfaces
stuck agents (issue #2041, #2203 demonstrate this monitoring catching real problems).

### Structured Work Tracking
Convoys + Beads provide structured, queryable work state. Cross-rig routing with
prefix-based addressing (`gt-*`, `bd-*`, `hq-*`) enables transparent multi-repo operations.

### Formula System
42 built-in TOML formulas provide repeatable workflows. The formula system handles
everything from patrol cycles to release processes to demo benchmarks (towers-of-hanoi).

## What Users Dislike / Struggle With

### Installation Complexity (Issue #2230)
Release v0.9.0 does not install via `go install` due to development-time `replace`
directives in `go.mod`. Users report that v0.7.0 works but the latest does not. This
is a significant onboarding barrier.

### Heavy Prerequisite Chain
The README lists 8 prerequisites: Go 1.23+, Git 2.25+, Dolt 1.82.4+, beads (bd) 0.55.4+,
sqlite3, tmux 3.0+, Claude Code CLI, and optionally Codex CLI. This is a steep
setup curve compared to simpler tools.

### Daemon/Dolt Stability Issues
Multiple issues relate to the Dolt SQL Server and daemon:
- **#2180**: Thundering herd -- concurrent `SHOW DATABASES` queries overwhelm Dolt
- **#2259**: `gt dashboard --port <X>` sets wrong Dolt port, causing connection failures
- **#2107**: `gt daemon start` fails with stale PID files
- **#2061**: `bd init` fails with server connection errors instead of graceful fallback

### Agent Session Crashes (Issue #2041)
The Deacon session consistently crashes after ~2 minutes regardless of formula complexity.
This triggers a respawn cycle where Witnesses flood the Mayor with alerts. The issue
suggests fundamental stability problems with long-running agent sessions.

### Silent Failures and Data Loss
Several issues describe scenarios where errors are silently swallowed:
- **#2281**: `setupSharedBeads` failure is non-fatal, causing MR beads to be invisible to Refinery
- **#2142**: `gt convoy stranded --json` writes warnings to stdout, breaking JSON parsing
- **#2095**: `gt mail send --wisp` generates empty IDs causing UNIQUE constraint failures
- **#2038**: Invalid mail recipient addresses silently lose mail

### Race Conditions in Multi-Agent Scenarios
- **#2215**: Race condition in polecat name allocation allows duplicate names
- **#2279**: Orphaned sling contexts permanently block convoy dispatch
- **#2072**: PreCompact handoff cycle destroys conversation context

### tmux Dependency Pain (Issue #2066)
Detached tmux sessions receive no TTY input for Ink rendering, requiring manual
workarounds. The tmux dependency adds operational complexity.

### Windows Support Gaps (Issue #1991)
Cannot build from source on Windows -- a P3 issue that limits the user base.

### Complexity Overhead
With 71 internal packages, 940 Go files, and 347K LOC, this is a large system to
understand, debug, or contribute to. The learning curve includes domain-specific
terminology (polecats, rigs, hooks, beads, wisps, convoys, molecules, formulas,
dogs, witnesses, refineries, mayors, deacons) that creates cognitive overhead.

## Good Ideas to Poach

### 1. Persistent Agent Identity with Ephemeral Sessions
Gas Town's separation of persistent identity (name, work history, capability ledger)
from ephemeral sessions (tmux processes that can crash and restart) is a key pattern.
Automaton could track agent identity and accumulated context across pipeline runs.
**Key file**: `internal/polecat/manager.go` (2,301 LOC)

### 2. Hook-Based Work State
Using git worktrees as durable, version-controlled work state that survives crashes
is elegant. Automaton could persist pipeline state in a git-tracked structure so that
interrupted runs can resume.
**Key files**: `internal/hooks/`, `internal/beads/beads_redirect.go`

### 3. The Propulsion Principle
The philosophy that agents should execute immediately when they find work -- no
confirmation, no waiting -- maximizes throughput. Automaton should adopt this
principle: specs go in, code comes out, no human gates unless explicitly configured.
**Key file**: `internal/templates/roles/polecat.md.tmpl` (lines 78-98)

### 4. Formula/Recipe System for Repeatable Workflows
TOML-defined workflow templates with dependency graphs, variables, and step checklists
(`internal/formula/formulas/*.formula.toml`, 42 formulas) provide repeatability.
Automaton could define spec-to-code pipeline stages as composable formulas.

### 5. Structured Escalation Protocol
The tiered escalation (Agent -> Deacon -> Mayor -> Human) with severity routing
and stale detection (`docs/design/escalation.md`) prevents stuck agents from
blocking forever. Automaton could implement a simpler version: retry -> fallback
strategy -> human alert.

### 6. Health State Classification
The problems view categorizes agents as GUPP Violation / Stalled / Zombie / Working / Idle.
Automaton could classify pipeline stages similarly for stuck detection.
**Key file**: `internal/feed/` (TUI), README lines 405-416

### 7. Context Recovery via `gt prime`
After crashes, compaction, or new sessions, `gt prime` re-injects full role context.
Automaton could implement a similar "re-prime" mechanism for interrupted spec-to-code
pipelines, replaying the spec context into a fresh agent session.
**Key file**: `internal/templates/townroot.go`

### 8. Multi-Runtime Abstraction
Supporting multiple AI backends (Claude, Gemini, Codex, Copilot, etc.) via a
registration pattern is smart future-proofing. Automaton could support swapping
the underlying LLM backend without changing pipeline logic.
**Key file**: `internal/runtime/runtime.go` (hook installer registration)

### 9. Capability Ledger / Work History
Recording every completion as a permanent, auditable record (mentioned in every
role template) creates accountability. Automaton could log every spec-to-code
transformation with provenance data (which spec, which model, what was generated).

### 10. Merge Queue with Batch-then-Bisect
The Refinery's Bors-style merge queue (`docs/design/architecture.md`, lines 199-228)
tests batches of changes and binary-bisects on failure. Automaton could apply
this when integrating multiple generated code modules.

## Ideas to Improve On

### 1. Complexity and Setup Burden
Gas Town requires 8 prerequisites (Go, Git, Dolt, beads, sqlite3, tmux, Claude Code,
and optionally Codex). The installation involves `go install`, workspace creation,
rig setup, crew creation, and Mayor attachment. **Automaton's advantage**: a single
bash file with minimal dependencies. No daemon, no Dolt server, no tmux requirement.
The spec-to-code pipeline should be `curl | bash` simple.

### 2. Dolt as a Single Point of Failure
Gas Town's Dolt SQL Server dependency creates operational fragility (issues #2180,
#2259, #2107, #2061). Thundering herd problems, port conflicts, and stale PIDs
are recurring themes. **Automaton's advantage**: use flat files (JSON, YAML, or
plain text) for state. A single bash file should not require a running database
server.

### 3. Silent Failure Patterns
Multiple issues (#2281, #2142, #2095, #2038) describe errors being silently
swallowed -- non-fatal beads setup failures, stdout pollution breaking JSON,
empty IDs, and lost mail. **Automaton's advantage**: fail loudly by default.
Every error should halt the pipeline with a clear message. `set -euo pipefail`
in bash gives this for free.

### 4. Domain Terminology Overload
Gas Town introduces 15+ domain-specific terms (polecats, rigs, hooks, beads, wisps,
convoys, molecules, formulas, dogs, witnesses, refineries, mayors, deacons, crews,
slings). This creates a steep learning curve. **Automaton's advantage**: use plain
English terms (spec, pipeline, stage, agent, output). Every concept should be
self-explanatory without a glossary.

### 5. Agent Session Stability
The Deacon crashing after ~2 minutes (issue #2041) and the respawn flood it causes
reveal fragility in long-running agent sessions. **Automaton's advantage**: design
for short-lived, stateless pipeline stages rather than long-running sessions.
Each stage does one thing, writes its output, and exits.

### 6. Race Conditions in Coordination
Duplicate polecat names (#2215), orphaned sling contexts (#2279), and destroyed
handoff context (#2072) indicate concurrency bugs in multi-agent coordination.
**Automaton's advantage**: a single-bash-file pipeline runs stages sequentially
by default. Concurrency is opt-in and controlled, not the default mode.

### 7. Over-Engineering for the Common Case
Gas Town's 347K LOC Go codebase with 71 packages solves the "20-30 agent" problem
but is massive overkill for the common case of 1-5 agents working on a single
project. **Automaton's advantage**: start simple. A single spec file and a bash
pipeline can handle the 80% case. Complexity is earned, not assumed.

### 8. Tmux Dependency and TTY Issues
The tmux dependency for agent sessions creates platform-specific issues (issue #2066
on TTY input, general complexity of tmux session management). **Automaton's advantage**:
run agents as simple subprocesses or use background jobs. No terminal multiplexer
required.

### 9. Lack of Graceful Degradation
When Dolt is down, `bd` fails fast with no embedded fallback (explicitly stated in
`docs/design/architecture.md`). When the daemon is down, convoys stall.
**Automaton's advantage**: a bash pipeline should work without any background
services. State can be flat files that degrade gracefully (worst case: lose some
caching, but pipeline still runs).

### 10. Web Dashboard as Afterthought
The web dashboard (`internal/web/`, htmx-based) is functional but secondary to the
CLI and TUI. **Automaton's advantage**: since Automaton is simpler, its output can
be a self-contained report (markdown, HTML) that serves as both dashboard and
documentation -- no running server required.
