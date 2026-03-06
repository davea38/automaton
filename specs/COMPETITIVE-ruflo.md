# Competitive Analysis: Ruflo / Claude-Flow (ruvnet/ruflo)

## Overview

**Ruflo** (formerly Claude Flow) is a TypeScript-based multi-agent AI orchestration platform
for Claude Code. It bills itself as "the leading agent orchestration platform for Claude" and
provides a CLI + MCP server for deploying coordinated agent swarms.

| Metric | Value |
|--------|-------|
| **Primary Language** | TypeScript (~393K LOC in v3/@claude-flow alone) |
| **Secondary Language** | Rust (~4.3K LOC, WASM kernels for guidance/policy engine) |
| **Total Files** | ~9,400 (excluding .git and node_modules) |
| **Stars** | 18,363 |
| **Forks** | 2,033 |
| **Watchers** | 200 |
| **License** | MIT |
| **npm weekly downloads** | ~14,400 (claude-flow) + ~5,000 (ruflo) |
| **npm monthly downloads** | ~71,200 (claude-flow package) |
| **Last Updated** | 2026-03-03 (actively developed) |
| **Version** | v3.5.2 (5,800+ commits, 55 alpha iterations) |
| **npm Packages** | 3 umbrella packages: `@claude-flow/cli`, `claude-flow`, `ruflo` |
| **Sub-packages** | 21 bounded-context packages under `v3/@claude-flow/` |
| **Test Files** | ~316 |
| **CI Workflows** | 6 GitHub Actions workflows |
| **Author** | RuvNet (ruv@ruv.io) -- solo maintainer |

## Architecture & Structure

### Repository Layout

```
ruflo/
  bin/cli.js              -- Umbrella entry point, proxies to v3/@claude-flow/cli
  package.json            -- Root package (claude-flow@3.5.2), minimal deps (semver, zod)
  agents/                 -- YAML agent definitions (coder, tester, reviewer, architect, security-architect)
  scripts/install.sh      -- Curl-pipe installer with --full/--global/--minimal modes
  ruflo/                  -- Thin wrapper npm package for `npx ruflo@latest`
  .claude-plugin/         -- Claude Code plugin manifest (plugin.json, hooks, scripts)
  .claude/                -- Claude config and checkpoints
  .agents/                -- Agent skills and config.toml
  tests/                  -- Root-level integration tests (8 files)
  v3/                     -- Main v3 source (monorepo)
    @claude-flow/
      cli/                -- CLI entry point: 38 commands, 140+ subcommands (~98K LOC)
        src/commands/      -- 38 command files (agent, swarm, hooks, memory, neural, etc.)
        src/mcp-tools/     -- 27 MCP tool modules
        src/ruvector/      -- RuVector intelligence layer integration
        src/plugins/       -- Plugin system (store, discovery, IPFS registry)
      swarm/              -- Swarm coordination (~16.5K LOC)
        src/consensus/     -- Raft, Byzantine, Gossip consensus implementations
        src/topology-manager.ts  -- Mesh/hierarchical/ring/star topologies
        src/queen-coordinator.ts -- Queen-led hive-mind
        src/federation-hub.ts    -- Cross-swarm federation
      hooks/              -- 17 hooks + 12 background workers (~10.9K LOC)
        src/workers/       -- ultralearn, optimize, consolidate, audit, etc.
        src/reasoningbank/ -- Pattern storage
        src/daemons/       -- Background daemon processes
      memory/             -- AgentDB + HNSW search (~21.3K LOC)
        src/hnsw-index.ts  -- HNSW vector search
        src/hybrid-backend.ts -- SQLite + AgentDB dual-write
        src/memory-graph.ts    -- PageRank, community detection
        src/learning-bridge.ts -- SONA integration
        src/rvf-backend.ts     -- RuVector Format native storage
      neural/             -- Neural pattern learning (~13K LOC)
        src/algorithms/    -- RL algorithms
        src/reasoning-bank.ts
        src/sona-integration.ts -- Self-Optimizing Neural Architecture
        src/pattern-learner.ts
      guidance/           -- Governance control plane (~22.3K LOC)
        wasm-kernel/       -- Rust WASM kernel (scoring, gates, proof)
        src/               -- TypeScript governance layer
      security/           -- Input validation, CVE remediation (~3.8K LOC)
      embeddings/         -- Vector embeddings with sql.js (~4.4K LOC)
      plugins/            -- Plugin system core (~48.7K LOC)
      providers/          -- Multi-LLM provider support (Claude, GPT, Gemini, Ollama, Novita, Moonshot)
      codex/              -- Dual-mode Claude + OpenAI Codex collaboration
      mcp/                -- MCP server implementation
      browser/            -- Browser automation agents
      claims/             -- Claims-based authorization
      deployment/         -- Deployment management
      performance/        -- Benchmarking and profiling
      testing/            -- Testing framework
      shared/             -- Shared utilities
      aidefence/          -- AI security defense
      integration/        -- Third-party integration bridge
```

### Tech Stack

- **Runtime**: Node.js >= 20, TypeScript 5.x
- **Build**: tsc (TypeScript compiler), Vitest for testing
- **WASM**: Rust (wasm-bindgen) for guidance kernel policy engine
- **Database**: SQLite (via sql.js WASM), AgentDB (custom), RVF (RuVector Format binary)
- **Vector Search**: HNSW (Hierarchical Navigable Small World), ONNX Runtime for embeddings
- **Consensus**: Raft, Byzantine Fault Tolerance, Gossip protocol, CRDT
- **Plugin Distribution**: IPFS via Pinata for decentralized plugin registry
- **MCP**: Model Context Protocol for Claude Code integration (215 MCP tools claimed)
- **CI**: GitHub Actions (6 workflows)
- **Package Management**: npm (monorepo without formal workspace tooling; sub-packages use pnpm in v3)

### Key Architectural Patterns

1. **Domain-Driven Design**: Bounded contexts for each sub-package (memory, swarm, neural, etc.)
2. **Event Sourcing**: State changes tracked via event log
3. **CQRS-like separation**: MCP tools coordinate, Claude Code Task tool executes
4. **Hierarchical topology by default**: Queen/worker pattern to prevent agent "drift"
5. **3-tier model routing**: WASM (<1ms, free) -> Haiku (~500ms, cheap) -> Opus (2-5s, expensive)
6. **Hybrid memory backend**: SQLite + AgentDB dual-write with HNSW indexing

## Features

### Core Agent Orchestration
- **60+ specialized agent types**: coder, reviewer, tester, planner, researcher, security-architect, etc.
- **Agent YAML definitions**: Declarative agent config in `agents/*.yaml`
- **Agent lifecycle management**: spawn, list, status, stop, metrics, pool, health, logs
- **Agent teams**: Experimental multi-agent coordination with Task tool, mailbox messaging, shared task lists

### Swarm Coordination
- **4 topology types**: mesh, hierarchical, ring, star (plus hierarchical-mesh hybrid)
- **5 consensus algorithms**: Raft, Byzantine (BFT), Gossip, CRDT, Quorum
- **Queen-led hive-mind**: Strategic/Tactical/Adaptive queen types with worker coordination
- **Anti-drift mechanisms**: Hierarchical topology, short task cycles, verification gates, checkpoints
- **Federation hub**: Cross-swarm coordination

### Intelligence & Learning
- **RuVector Intelligence Layer**: SONA (Self-Optimizing Neural Architecture), EWC++ (Elastic Weight Consolidation)
- **9 RL algorithms**: Q-Learning, SARSA, A2C, PPO, DQN, Decision Transformer, MCTS, Model-Based, Policy Gradient
- **ReasoningBank**: Pattern storage with trajectory learning (RETRIEVE -> JUDGE -> DISTILL -> CONSOLIDATE)
- **Flash Attention**: Optimized attention computation
- **LoRA/MicroLoRA**: Lightweight fine-tuning (128x compression claimed)
- **Hyperbolic embeddings**: Poincare ball model for hierarchical code relationships

### Memory & Storage
- **HNSW vector search**: Claimed 150x-12,500x faster pattern retrieval
- **Hybrid memory backend**: SQLite + AgentDB with dual-write
- **RVF (RuVector Format)**: Custom native binary storage format
- **Memory graph**: PageRank computation, community detection via label propagation
- **3-scope agent memory**: project/local/user isolation
- **COW branching**: Copy-on-Write memory snapshots via AgentDB v3
- **BM25 hybrid search**: Vector similarity + keyword matching
- **Witness chain**: Cryptographic audit trail for memory operations

### CLI (38 Commands, 140+ Subcommands)
- `init` (wizard, presets, skills, hooks), `agent`, `swarm`, `memory`, `mcp`, `task`
- `session`, `config`, `status`, `start`, `workflow`, `hooks`, `hive-mind`
- `daemon`, `neural`, `security`, `performance`, `providers`, `plugins`
- `deployment`, `embeddings`, `claims`, `migrate`, `process`, `doctor`, `completions`

### MCP Integration (27 Tool Modules)
- agent-tools, agentdb-tools, analyze-tools, browser-tools, claims-tools
- config-tools, coordination-tools, embeddings-tools, github-tools
- hive-mind-tools, hooks-tools, memory-tools, neural-tools
- performance-tools, progress-tools, security-tools, session-tools
- swarm-tools, system-tools, task-tools, terminal-tools, transfer-tools, workflow-tools

### Multi-Provider LLM Support
- Anthropic (Claude), OpenAI (GPT/Codex), Google (Gemini), Ollama (local), Cohere
- Novita AI, Moonshot (Kimi) -- contributed via PRs
- Automatic failover between providers
- Smart routing picks cheapest option meeting quality requirements
- Dual-mode collaboration: Claude + Codex workers in parallel

### Plugin System
- 20 plugins available via IPFS/Pinata decentralized registry
- Categories: core (embeddings, security, claims, neural), integration, domain-specific
- Domain-specific plugins: healthcare-clinical, financial-risk, legal-contracts
- Plugin SDK for creating custom capabilities

### Security
- AIDefence module for prompt injection defense
- Input validation (Zod-based) at system boundaries
- Path traversal prevention, command injection blocking
- CVE remediation module
- Password hashing (bcrypt), secure token generation
- Rust WASM kernel for deterministic policy engine (scoring, gates, proof)

### DevOps & Operations
- 12 background workers (ultralearn, optimize, consolidate, predict, audit, map, etc.)
- Doctor command with health checks (Node version, npm, git, config, daemon, memory, API keys, disk)
- Deployment management (deploy, rollback, status, environments, release)
- GitHub integration (PR manager, issue tracker, release manager, workflow automation)
- Session persistence and restore across conversations

### Cost Optimization
- 3-tier model routing: WASM booster ($0, <1ms) -> Haiku ($0.0002, ~500ms) -> Opus ($0.015, 2-5s)
- Agent Booster: 6 WASM transforms skip LLM entirely (var-to-const, add-types, async-await, etc.)
- Token optimizer: 30-50% token reduction via ReasoningBank, caching, batching
- Claims: "Extend your Claude Code subscription by 250%"

## What Users Like

### High Star Count and Visibility
- 18,363 stars, 2,033 forks -- very popular in the Claude Code ecosystem
- Named "GitHub Project of the Day"
- Active development: last commit same day as this analysis (2026-03-03)

### Ambitious Feature Scope
- Issue #1277: External developer praises "multi-agent swarm architecture is impressive -- 18k+ stars well deserved!"
- Multiple community-contributed PRs adding new providers (Novita AI PR #1266, Moonshot/Kimi PR #1255, PR #1246)
- PR #1249 and #1248: Community members proactively upgrading GitHub Actions dependencies

### Comprehensive CLI
- 38 commands with 140+ subcommands provide extensive orchestration surface
- The `doctor --fix` self-diagnostic is a user-friendly feature
- Shell completions for bash, zsh, fish, powershell (Issue #1236 requests even more shortcuts)

### Native Claude Code Integration
- MCP server integration works inside Claude Code sessions
- `.claude-plugin/` manifest for plug-and-play Claude Code plugin installation
- Integration with Claude Code's experimental Agent Teams feature

### Active Iteration
- 5,800+ commits, 55 alpha iterations before v3.5.0 stable release
- Multiple ADRs (Architecture Decision Records) showing structured decision-making
- Active issue pipeline: issues filed, analyzed, and closed with PRs

## What Users Dislike / Struggle With

### Broken Core Features (Many Modules Never Wired Up)

A large cluster of issues (#1207-#1227) reveals that many advertised features are **exported but never instantiated at runtime**:

- **Issue #1264**: AgentDB bridge always unavailable -- `ControllerRegistry` not exported from `@claude-flow/memory`. All `agentdb_*` MCP tools permanently return `{ available: false }`.
- **Issue #1214**: `MemoryGraph` class (PageRank, community detection) exported but never instantiated.
- **Issue #1213**: `LearningBridge` has zero runtime callers. Config keys written but never consumed.
- **Issue #1209**: `recordFeedback()` exposed by AgentDB v3 has zero callers -- self-learning feedback loop is broken.
- **Issue #1215**: `SkillLibrary` controller (Voyager pattern) not instantiated by CLI.
- **Issue #1216**: `ExplainableRecall` controller exported but never instantiated.
- **Issue #1217**: `SolverBandit` Thompson Sampling never used in routing.
- **Issue #1204**: 12 out of 19 config.json keys written during init are dead -- written but never read at runtime.

This pattern suggests that much of the codebase is **aspirational scaffolding** -- exported classes and interfaces that look impressive but have no actual runtime integration.

### Confusing Onboarding / Documentation

- **Issue #1251**: User asks "How to use ruflo?" after installing. README immediately jumps to Codex section. User says: "When I run Claude I can see it's active but this doesn't mean anything to a new user."
- **Issue #1205**: `init` command has no CLI flags for most config.json settings -- users must manually edit JSON.
- **Issue #1230**: Settings error after `init` in a new project directory.

### Broken Hook System

- **Issue #1211**: `hook-handler.cjs` ignores stdin entirely. Claude Code 2.x delivers all hook data via stdin JSON, but the handler reads from environment variables that Claude Code 2.x does not set. Result: **every hook invocation silently receives empty data**, making route/pre-bash/post-edit handlers non-functional.
- **Issue #1259**: Hook commands use relative paths, break when CWD is not project root (e.g., monorepo subdirectories).

### Process Hangs and Bugs

- **Issue #1256**: `CacheManager.setInterval()` missing `.unref()` prevents Node.js process exit. Any CLI command touching memory hangs indefinitely.
- **Issue #1257**: HybridBackend dual-write causes SQLite "database is locked" contention under 4+ concurrent agents.
- **Issue #1243**: `SonaTrajectoryService` does not use native `@ruvector/sona` API correctly -- SONA trajectory learning effectively disabled.

### Version and Branding Confusion

- **Issue #1253**: MCP server reports version 3.0.0-alpha but package is v3.5.2.
- **Issue #1254**: Statusline shows "Claude Flow V3" instead of "Ruflo V3" after rebrand.
- **Issue #1235**: `doctor` command reports wrong version (v0.0.0 or stale npx cache).
- **Issue #1231**: npm ECOMPROMISED cache corruption blocking npx installs.

### Security Concern: Obfuscated Preinstall Script

- **Issue #1261**: The `preinstall` script in package.json is an obfuscated one-liner that (1) walks `~/.npm/_npx/*/node_modules/` deleting certain directories, and (2) recursively walks `~/.npm/_cacache/index-v5/` deleting cache entries containing "claude-flow" or "ruflo". This performs destructive writes outside the package directory on a shared user-level npm resource, with no disclosure in README or CHANGELOG. The reporter flags this as a potential npm acceptable-use policy violation.

### Swarm Doesn't Actually Work

- **PR #1265**: "swarm start was showing a fake 500ms spinner without spawning any agents." The fix had to add actual process spawning. This suggests the core swarm feature was previously non-functional.
- **Issue #1206**: Templates still reference stale `--topology hierarchical` instead of the correct `hierarchical-mesh`.

## Good Ideas to Poach

### 1. YAML Agent Definitions
The `agents/*.yaml` pattern for declaratively defining agent roles, capabilities, and optimizations is clean and user-friendly. Automaton could adopt a similar approach for defining pipeline stages or agent personas.

**Example from `agents/coder.yaml`:**
```yaml
type: coder
version: "3.0.0"
capabilities:
  - code-generation
  - refactoring
  - debugging
optimizations:
  - flash-attention
  - token-reduction
```

### 2. Doctor / Health Check Command
`npx ruflo doctor --fix` runs diagnostics on the entire system (Node version, npm, git, config, daemon, memory, API keys, disk). This self-healing pattern is valuable for any complex CLI tool. Automaton should have a `--doctor` or `--check` flag.

### 3. 3-Tier Model Routing for Cost Optimization
The concept of routing tasks by complexity to different cost tiers is sound:
- Tier 1: WASM/local transforms for trivial edits ($0, <1ms)
- Tier 2: Cheap/fast models for simple tasks
- Tier 3: Expensive models for complex reasoning

Automaton could implement a simpler version: skip LLM calls entirely for deterministic operations (file moves, template expansion, regex transforms), and route to cheaper models when full reasoning is unnecessary.

### 4. Anti-Drift Mechanisms
The "anti-drift" concept -- preventing agents from going off-task during long swarm operations -- is a real problem worth solving. Techniques: hierarchical topology with a coordinator, short task cycles, verification gates, checkpoints, raft consensus for shared state.

### 5. Plugin Distribution via IPFS
Decentralized plugin registry via Pinata/IPFS is a creative approach for distributing extensions without a centralized server. Worth considering if Automaton ever needs a plugin ecosystem.

### 6. Session Persistence and Restore
The ability to save session state and restore context across conversations (`session-start`, `session-end`, `session-restore`) addresses a real pain point in long-running AI workflows.

### 7. Agent Booster / WASM Transforms
Using WebAssembly for deterministic code transforms (var-to-const, add-types, async-await) that skip LLM entirely is clever cost optimization. Automaton could implement similar "fast-path" operations for common code transformations.

### 8. Background Workers / Daemon
12 background workers (audit, optimize, consolidate, map, testgaps, etc.) that run asynchronously while the user works. The daemon pattern for long-running background analysis could be valuable.

### 9. Dual-Mode Collaboration Templates
Pre-built workflow templates for common tasks (feature, security, refactor, bugfix) with predefined agent team compositions and dependency levels. Automaton could offer similar "recipes" or "playbooks."

### 10. CLAUDE.md as Instruction Surface
Using `CLAUDE.md` at project root to inject behavioral rules, architecture constraints, and routing instructions into Claude Code sessions is an effective pattern. Automaton already uses this (being a single bash file), but the structured approach to defining agent routing codes and complexity detection thresholds is worth adopting.

## Ideas to Improve On

### 1. Feature Bloat Without Runtime Integration
Ruflo's biggest weakness is the gap between advertised features and actual functionality. Issues #1207-#1227 reveal that many subsystems (MemoryGraph, LearningBridge, SkillLibrary, ExplainableRecall, SolverBandit, ReflexionMemory, FederatedSessionManager, etc.) are exported TypeScript classes that are **never instantiated at runtime**. Automaton should maintain a strict "no dead code" policy: every feature should be wired end-to-end before being documented.

### 2. Simpler Is Better
Ruflo has 21 sub-packages, 38 CLI commands, 140+ subcommands, 215 MCP tools, and ~393K LOC of TypeScript. Despite this, users struggle with basic onboarding (Issue #1251: "How do I use it?"). Automaton's single-bash-file approach is a massive competitive advantage -- zero dependencies, instant understanding, no monorepo complexity. Lean into this.

### 3. Actually Working Hook System
Ruflo's hook system is fundamentally broken: it reads from environment variables while Claude Code sends data via stdin JSON (Issue #1211). Automaton should ensure its hook/callback system works correctly with how Claude Code actually delivers data, and should test against real Claude Code behavior, not assumed behavior.

### 4. No Obfuscation or Surprise Side Effects
The obfuscated `preinstall` script (Issue #1261) that silently deletes npm cache entries is a trust-destroying anti-pattern. Automaton should be fully transparent -- a single readable bash file with no hidden behavior.

### 5. Honest Performance Claims
Ruflo claims "150x-12,500x faster HNSW search", "352x faster edits", "2.49-7.47x Flash Attention speedup" without published benchmarks or methodology. Many of these features (SONA, Flash Attention) are listed as "In progress" even in the project's own documentation. Automaton should only claim performance improvements that are measured and reproducible.

### 6. Real Testing vs. Aspirational Testing
316 test files sounds impressive, but the core hook system doesn't work (Issue #1211), the swarm command was faking output (PR #1265), and AgentDB tools always return "not available" (Issue #1264). This suggests tests may not be testing real behavior. Automaton should prioritize integration tests that verify end-to-end functionality over unit tests of isolated modules.

### 7. Straightforward Onboarding
Issue #1251 shows a user who installed, initialized, and ran the daemon but still had no idea what to do next. Automaton should have a zero-to-working-example path that takes under 60 seconds and produces visible output -- no wizard, no daemon, no MCP server configuration.

### 8. Stable Naming and Versioning
Ruflo has three npm package names (claude-flow, ruflo, @claude-flow/cli), multiple dist-tags (alpha, latest, v3alpha), lingering old branding in output (Issues #1253, #1254), and version mismatches between the MCP server and the npm package. Automaton should have one name, one version, one package.

### 9. Working Concurrency Without SQLite Locking
Issue #1257 reports SQLite "database is locked" errors with 4+ concurrent agents. For a tool whose entire value proposition is multi-agent orchestration, this is a critical failure. If Automaton needs shared state between parallel processes, it should use a concurrency-safe approach (file locking, separate per-agent state files, or an actual concurrent database).

### 10. Lean Dependencies
Ruflo's root package.json lists only semver and zod, but optional dependencies pull in `@ruvector/core`, `@ruvector/router`, `@ruvector/sona`, `agentdb`, `agentic-flow` -- a web of custom packages by the same author. The total `node_modules` footprint and install time is significant. Automaton's zero-dependency bash approach is a clear advantage for adoption speed and reliability.
