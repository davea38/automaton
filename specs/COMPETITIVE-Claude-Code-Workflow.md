# Competitive Analysis: Claude-Code-Workflow (catlog22/Claude-Code-Workflow)

## Overview

**Claude-Code-Workflow (CCW)** is a JSON-driven multi-agent development framework that wraps around Claude Code (and other AI CLIs) to provide structured workflow orchestration. It installs itself as a set of skills, commands, and agents into Claude Code's `.claude/` directory, then uses Claude Code's native skill/command system as the execution surface.

| Attribute | Value |
|-----------|-------|
| **Primary language** | TypeScript (~210k LOC backend + ~169k LOC React frontend) |
| **Secondary language** | Python (~92k LOC for CodexLens semantic search engine) |
| **Prompt/config markdown** | ~236k LOC across 742 `.md` files (skills, agents, commands, workflows) |
| **Total estimated LOC** | ~309k source (excl. node_modules, dist, lock files), plus ~236k markdown prompts |
| **Stars** | 1,389 |
| **Forks** | 114 |
| **License** | MIT |
| **Last updated** | 2026-03-03 (actively maintained, daily commits) |
| **Version** | v7.2.1 (npm: `claude-code-workflow`) |
| **Install** | `npm install -g claude-code-workflow && ccw install -m Global` |

The project originates from a Chinese-speaking developer community. Most issues, documentation, and in-code comments are bilingual (Chinese + English). It targets power users of Claude Code who want structured multi-phase development workflows.

---

## Architecture & Structure

### Top-Level Organization

```
Claude-Code-Workflow/
├── .claude/                 # Claude Code integration layer
│   ├── agents/              # 22 specialized agent definitions (.md)
│   ├── commands/            # Slash commands (ccw.md, ccw-coordinator.md, cli/, issue/, memory/, workflow/)
│   ├── skills/              # 36 modular skills (brainstorm, workflow-*, team-*, etc.)
│   ├── scripts/             # Helper scripts
│   └── CLAUDE.md            # Claude Code system instructions
├── .codex/                  # OpenAI Codex CLI integration
│   ├── agents/              # 20 Codex agent definitions (mirrors .claude/agents)
│   ├── skills/              # 20 Codex skill definitions
│   └── prompts/             # Codex-specific prompts
├── .gemini/                 # Google Gemini CLI integration (GEMINI.md)
├── .qwen/                   # Alibaba Qwen CLI integration (QWEN.md)
├── .ccw/                    # CCW-specific configs
│   ├── workflows/           # Workflow architecture definitions, coding philosophy, CLI templates
│   ├── specs/               # Architecture constraints, coding conventions
│   └── personal/            # Personal preferences
├── ccw/                     # Main TypeScript CLI application
│   ├── src/
│   │   ├── cli.ts           # CLI entry point (Commander.js)
│   │   ├── commands/        # 19 command implementations (install, view, serve, session, issue, team, etc.)
│   │   ├── core/            # Core services (~40+ modules: auth, a2ui, hooks, routes, memory, server)
│   │   ├── tools/           # 60+ tool implementations (CLI executor, session manager, smart search, etc.)
│   │   ├── mcp-server/      # MCP server implementation
│   │   └── templates/       # Code generation templates
│   └── frontend/            # React dashboard (~598 TSX files, ~169k LOC)
│       ├── src/stores/      # 20+ Zustand stores
│       ├── src/hooks/       # React hooks for CLI, sessions, teams, memory
│       └── src/orchestrator/# Visual workflow orchestration
├── codex-lens/              # Python semantic code search engine
│   └── src/codexlens/       # Search (hybrid, association tree, chain), LSP, MCP, parsers, storage
├── ccw-litellm/             # LiteLLM integration for multi-model support
├── docs/                    # VitePress documentation site (bilingual EN/ZH)
└── docs-site/               # Alternative docs site
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| CLI framework | Commander.js (TypeScript, ESM) |
| Frontend | React + Zustand + React Flow (visual workflow editor) + Tailwind CSS |
| Backend server | Custom Express-like Node.js server with JWT auth, CSRF, WebSocket |
| Semantic search | Python (fastembed, SQLite FTS5, tree-sitter, ast-grep, ONNX reranker) |
| Database | better-sqlite3 (session/memory storage) |
| Terminal | node-pty (multi-terminal dashboard) |
| MCP | @modelcontextprotocol/sdk (MCP server for tool exposure) |
| Build | TypeScript 5.9, Vite (frontend), pyproject.toml (Python) |
| Testing | Node.js built-in test runner, Playwright (E2E), pytest (Python) |

### Key Architectural Patterns

1. **Skill-as-Markdown**: Each skill is a markdown file (`SKILL.md`) with YAML frontmatter (`name`, `description`, `allowed-tools`) and structured phases. Claude Code loads these natively.
2. **Agent-as-Markdown**: 22 agent definitions in `.claude/agents/` define specialized roles (code-developer, tdd-developer, cli-discuss-agent, team-worker, etc.)
3. **JSON-only data model**: Task state stored exclusively in JSON files (`.task/IMPL-*.json`). Markdown docs are read-only generated views.
4. **Multi-CLI orchestration**: Dispatches work to Gemini, Codex, Qwen, or OpenCode CLIs based on semantic intent detection.
5. **Session lifecycle**: Directory-based session management (`.workflow/active/`, `.workflow/archives/`) with start/resume/complete/sync operations.
6. **Beat/Cadence model**: Event-driven coordinator that wakes only on callbacks, spawns parallel workers, supports dynamic pipeline generation.

---

## Features

### Workflow Skills (36 skills)

| Category | Skills | Description |
|----------|--------|-------------|
| **Lightweight planning** | `workflow-lite-planex` | 5-phase interactive workflow: analyze, clarify, plan, confirm, execute |
| **Standard planning** | `workflow-plan`, `workflow-plan-verify`, `workflow:replan` | Full planning with session persistence and verification |
| **TDD** | `workflow-tdd-plan`, `workflow-tdd-verify` | 6-phase TDD (Red-Green-Refactor) with progressive test layers L0-L3 |
| **Test-fix** | `workflow-test-fix` | Test generation and iterative fix cycles |
| **Brainstorm** | `brainstorm` | Dual-mode: auto pipeline (multi-role parallel analysis + synthesis) or single-role |
| **Multi-CLI** | `workflow-multi-cli-plan` | Multi-CLI collaborative analysis with ACE semantic search |
| **Execution** | `workflow-execute` | Execute plans generated by planning skills |
| **Team** | `team-coordinate-v2`, `team-executor-v2`, `team-lifecycle-v5`, `team-planex`, `team-brainstorm`, `team-frontend`, `team-issue`, `team-iterdev`, `team-quality-assurance`, `team-review`, `team-roadmap-dev`, `team-tech-debt`, `team-testing`, `team-uidesign`, `team-ultra-analyze`, `team-perf-opt`, `team-arch-opt` | Role-based multi-agent team coordination |
| **Meta** | `skill-generator`, `spec-generator`, `command-generator`, `skill-tuning`, `workflow-skill-designer` | Generate new skills/commands/specs |
| **Memory** | `memory-capture`, `memory-manage` | Memory extraction, consolidation, embedding |
| **Review** | `review-code`, `review-cycle` | Code review workflows |
| **Help** | `ccw-help` | Auto-analyze available commands and skills |

### CLI Commands

| Command | Description |
|---------|-------------|
| `ccw install -m Global` | Install skills, agents, commands, workflows to `~/.claude/` |
| `ccw view` | Launch React-based terminal dashboard |
| `ccw serve` | Start backend API server (JWT auth, WebSocket) |
| `ccw cli -p "..." --tool gemini` | Execute prompts via external CLIs |
| `ccw session start/resume/complete/list/sync` | Session lifecycle management |
| `ccw issue new/plan/queue/execute/done` | Issue tracking and execution pipeline |
| `ccw team start/status/stop` | Team orchestration commands |
| `ccw memory embed/compact` | Memory management with embeddings |
| `ccw upgrade -a` | Upgrade all installations |
| `ccw install --codex-only` | Install only Codex-compatible files |
| `ccw hook` | Manage Claude Code hooks |
| `ccw loop` | Loop execution management |
| `ccw spec` | Specification management |

### Terminal Dashboard (React Frontend)

- Multi-terminal grid with resizable panes via node-pty
- Real-time execution monitor with agent status
- File browser with project navigation
- Session grouping by project tags
- CLI history viewer and configuration editor
- Issue manager with status filtering
- Team coordination view
- Queue scheduler status display
- Orchestrator Editor (React Flow-based visual workflow editing)
- Bilingual i18n (English/Chinese)
- Dark/light theme toggle

### CodexLens (Python Semantic Search)

- Full-text search via SQLite FTS5
- Semantic search with local embedding models (fastembed, jina-embeddings-v2)
- Hybrid search combining FTS + semantic + reranking
- Tree-sitter and ast-grep based code parsing
- LSP server integration
- MCP server endpoint for tool exposure
- File watcher for incremental indexing
- Association tree and graph-based code navigation
- Chain search with staged cascade strategies

### Multi-Agent Architecture

- **22 agent definitions** with role-specific instructions
- **Team Architecture v2**: Coordinator + Worker model with beat/cadence orchestration
- **Inner loop execution**: Workers execute sequential phases autonomously
- **Message bus protocol** for inter-agent communication
- **Wisdom accumulation**: Learnings, decisions, and conventions persisted across sessions
- **A2UI (Agent-to-User Interface)**: Interactive communication channel

### Memory System

- Memory extraction pipeline from conversation history
- Memory consolidation with embedding-based deduplication
- Core memory store (persistent key facts)
- Memory embedder bridge to CodexLens
- Memory job scheduler for background processing

### Multi-CLI Orchestration

- Semantic intent detection to auto-select CLI tools
- Supported CLIs: Gemini, Codex, OpenCode, Qwen, Claude
- Orchestration patterns: collaborative, parallel, iterative, pipeline
- Per-tool configuration (model, environment, API keys) via dashboard

---

## What Users Like

### Strong Engagement (1,389 stars, 114 forks)

The project has significant traction in the Chinese AI developer community, with rapid star growth.

### Structured Workflow System

Issue #102 (the only detailed English-language issue) praised the project extensively. The user appreciated the structured approach to development with planning, execution, and review phases. Quote from the issue: the user called it a "structured workflow system" they had been looking for.

Issue #86 expressed enthusiasm about using CCW for structured development, specifically praising the workflow system for taking Claude Code to "the next level."

### Active Maintenance

The repo receives near-daily updates. Version 7.2.1 at time of analysis, with rapid feature iteration (team architecture v2, queue scheduler, dashboard improvements).

### Multi-CLI Integration

Several issues (#87, #95, #91) show active use of the multi-CLI features. Users actively orchestrate between Gemini, Codex, and Claude.

### Dashboard UI

Users actively use the web dashboard (`ccw view`) for monitoring sessions, managing issues, and configuring CLI tools (issues #80, #96, #97, #98, #99, #101).

### Community

The project has a WeChat group for community support. The maintainer (catlog22) responds quickly to issues, often resolving them within hours (e.g., issue #124 fixed in one comment exchange).

---

## What Users Dislike / Struggle With

### High Token Consumption

**Issue #117**: Users report that CCW causes excessive token usage with Claude Opus, frequently hitting rate limits. After uninstalling CCW, the token overconsumption largely disappeared. This is a fundamental architectural concern -- the markdown-heavy skill/agent/command system injects massive context into every Claude Code interaction.

### Installation Complexity

- **Issue #115**: User requested pre-packaged builds because self-installation causes various errors due to missing system dependencies.
- **Issue #104**: CodexLens installation fails for NPM global install users (path detection bug, fixed in PR #105).
- **Issue #94**: CodexLens installation failure due to Python dependency resolution errors.
- **Issue #120**: ccw-litellm installation fails on WSL2.
- **Issue #124**: `ccw view` breaks after upgrade (missing React frontend directory).

### Incomplete Uninstall

**Issue #126**: `ccw uninstall` does not fully clean up skills and commands installed by Claude Code and Codex integrations, leaving orphaned files.

**Issue #103**: User asked how to completely uninstall without affecting other functionality.

### Documentation Gaps

- **Issue #125**: README lacks a "getting started" best practices section. Users don't know how to go from install to actual use.
- **Issue #110**: User simply asked "how to uninstall" -- even basic operations are not obvious.

### Dashboard Bugs (Frequent)

A large cluster of issues relates to the web dashboard:
- **Issue #80**: Project overview shows "Unknown" with no description
- **Issue #79**: Data structure mismatch between `project-tech.json` and `data-aggregator.ts`
- **Issue #85**: Summary tab empty for lite-fix-plan sessions
- **Issue #76**: Completed status filter doesn't work in Issue Manager
- **Issue #75**: Frontend cache not updated after config save
- **Issue #97**: Hidden files toggle doesn't work in file browser
- **Issue #96**: Gemini envFile setting lost on page refresh
- **Issue #34/35**: Page refresh crashes due to `const` reassignment bug

### Cross-Platform Issues

- **Issue #82**: Stop hook syntax errors with shell quoting on different platforms
- **Issue #73**: jq command escaping errors in hook configs
- **Issue #42**: Path separator issues on Linux/WSL (backslash vs forward slash)
- **Issue #71**: Temp files (`tmpclaude-xxxx-cwd`) generated in project root

### CLI Execution Failures

- **Issue #84**: `ccw cli --mode review` fails with "unexpected argument" for Codex
- **Issue #89**: Template discovery fails with nested directory structures
- **Issue #91**: Multi-CLI plan outputs wrong command format, breaking execution chain
- **Issue #95**: Disabled CLIs (e.g., Qwen) still get invoked during task execution

### Workflow Fragility

- **Issue #100**: `lite-execute` doesn't pass project guidelines to execution stage
- **Issue #111**: CLI/Hybrid mode receives condensed, incomplete context compared to Agent mode in TDD workflow

---

## Good Ideas to Poach

### 1. Phased Workflow Execution with Plan-Execute Separation

CCW's `workflow-lite-planex` skill separates planning (Phase 1: analyze, clarify, plan, confirm) from execution (Phase 2), with explicit handoff between phases. This is a well-structured pattern. Automaton could adopt a similar plan-then-execute cadence with checkpoint confirmation.

**Relevant files**: `.claude/skills/workflow-lite-planex/SKILL.md`, `.claude/skills/workflow-lite-planex/phases/01-lite-plan.md`, `phases/02-lite-execute.md`

### 2. Coding Philosophy as System-Level Constraint

The file `.ccw/workflows/coding-philosophy.md` encodes development principles (simplicity, no suppression, incremental progress, "fix don't hide") as system-level instructions injected into every session. This is effective for maintaining code quality consistency. Key rules:
- "Stop after 3 failed attempts and reassess"
- "Find 3 similar features before implementing"
- "Never generate reports/documentation without explicit request"
- "Edit fallback: When Edit tool fails 2+ times, try Bash sed/awk"

### 3. Context-First Tool Strategy

`.ccw/workflows/context-tools.md` and `.ccw/workflows/tool-strategy.md` define when to use which tools (Read vs Grep vs Glob), file modification rules, and context gathering requirements before writing code. Automaton could embed similar tool-usage heuristics.

### 4. Multi-CLI Dispatch with Semantic Intent Detection

The ability to say "use Gemini to analyze" and have the system automatically invoke the right CLI tool is powerful. For Automaton, this could translate to dispatching different phases to different models (e.g., use a fast model for exploration, a strong model for implementation).

### 5. Session Persistence with Directory-Based State

CCW's `.workflow/active/` and `.workflow/archives/` directory model is simple and effective. Session state is just directories with JSON files inside. No database needed for session tracking.

**Relevant file**: `.ccw/workflows/workflow-architecture.md`

### 6. Issue-to-Execution Pipeline

The `issue/new` -> `issue/plan` -> `issue/queue` -> `issue/execute` pipeline is a concrete workflow for going from bug report to fix. Automaton could adopt a similar spec-to-plan-to-execute pipeline.

### 7. Compact Recovery / Phase Persistence

CCW addresses Claude Code's context window compression by marking active phases in TodoWrite so the compressor knows which phase context to preserve. This is a pragmatic solution to a real problem.

**Relevant file**: `.claude/skills/workflow-lite-planex/SKILL.md` (Compact Recovery section)

### 8. Progressive Test Layers (L0-L3)

The test-fix workflow defines progressive test layers: L0 (static analysis/types), L1 (unit tests), L2 (integration), L3 (E2E). This structured approach to testing could be embedded in Automaton's test phase.

### 9. Brainstorm as Multi-Role Analysis

The `brainstorm` skill spawns multiple "roles" (conceptual-planning-agent, context-search-agent) in parallel, each analyzing from a different perspective, then synthesizes results. This is an effective pattern for thorough analysis.

### 10. Skill/Command Self-Generation

CCW includes meta-skills (`skill-generator`, `command-generator`, `spec-generator`) that can create new skills and commands from descriptions. This enables user-extensibility.

---

## Ideas to Improve On

### 1. Massive Complexity and Token Waste

CCW is approximately 309k LOC of code plus 236k lines of markdown prompts. This is an extraordinarily large surface area. Issue #117 confirms that users experience excessive token consumption. The 22 agents, 36 skills, and 60+ tools create a combinatorial explosion of context that gets loaded into Claude Code sessions.

**Automaton advantage**: A single bash file is inherently leaner. By keeping the orchestration minimal and focused, Automaton avoids the token bloat problem entirely. Embed only the prompts needed for the current phase, not the entire skill library.

### 2. Installation Hell

CCW requires `npm install -g`, then `ccw install -m Global`, which copies files into `~/.claude/`, `~/.codex/`, `~/.gemini/`, `~/.qwen/`, and `~/.ccw/`. It requires Node.js 18+, rebuilds native modules (better-sqlite3, node-pty), and optionally needs Python for CodexLens. Issues #94, #104, #115, #120, #124, #126 document installation failures.

**Automaton advantage**: A single bash file with zero dependencies is infinitely easier to install. `curl | bash` or just copy the file. No npm, no native modules, no Python environment.

### 3. Tight Coupling to Claude Code Internals

CCW is deeply coupled to Claude Code's skill/command/agent system, MCP protocol, and hook mechanisms. It also tries to integrate Codex, Gemini, Qwen, and OpenCode, each with their own configuration surface. When any of these tools change their APIs or conventions, CCW breaks (e.g., issues #82, #84, #89).

**Automaton advantage**: By orchestrating at the shell level (invoking `claude` CLI directly with prompts), Automaton has a much thinner integration surface. It doesn't depend on internal Claude Code plugin systems.

### 4. Dashboard as Unnecessary Overhead

CCW ships a 169k-LOC React frontend with node-pty terminal emulation, WebSocket communication, JWT authentication, and CSRF protection. This is a full web application that introduces its own bug surface (issues #34, #75, #76, #79, #80, #85, #96, #97). For a development workflow tool, this is massive overengineering.

**Automaton advantage**: A bash pipeline that writes specs and code files, then lets the user's existing editor/terminal handle the UI, is simpler and more robust. Output to files, not web dashboards.

### 5. Fragile Multi-Agent Coordination

The team architecture with coordinator/worker beat model, message bus, and callback chains is conceptually interesting but introduces significant coordination overhead and failure modes. Issue #111 documents context parity gaps between execution modes. Issue #100 shows guidelines not propagating between phases.

**Automaton advantage**: A linear pipeline (spec -> plan -> implement -> test -> review) with explicit file-based handoffs between phases is easier to debug and less likely to lose context.

### 6. Bilingual Documentation Without Clear Primary

The codebase mixes Chinese and English extensively. Skill definitions contain Chinese comments inline with English headers. Issues are predominantly in Chinese. This makes the project harder to adopt for non-Chinese speakers despite the English README.

**Automaton advantage**: Pick one language for all internal documentation and comments. Provide translations separately if needed.

### 7. No Offline-First or Local-Only Mode

CCW's multi-CLI orchestration assumes network access to multiple AI services (Gemini, Codex, Qwen). There is no clear offline or degraded mode.

**Automaton advantage**: Design for single-model operation by default. Multi-model is optional enhancement, not a requirement.

### 8. Skill Definition Verbosity

Individual skill files are extremely verbose. `workflow-lite-planex/SKILL.md` alone is 441 lines. The brainstorm skill references multiple phase files. This verbosity means each skill invocation consumes significant context window.

**Automaton advantage**: Express workflow phases as compact, structured data (e.g., a JSON spec or a concise bash function) rather than verbose markdown narratives.

### 9. Uninstall/Cleanup is Incomplete

Issue #126 documents that uninstall leaves orphaned files. Issue #103 shows users unsure how to cleanly remove CCW. A tool that modifies `~/.claude/` should have pristine cleanup.

**Automaton advantage**: A single file that doesn't install anything globally. When you're done, delete the file. No cleanup needed.

### 10. Session State Scattered Across Filesystem

Session data lives in `.workflow/active/`, memory in SQLite databases, CLI config in `~/.claude/cli-tools.json`, project settings in various `.ccw/` directories. This distributed state is hard to reason about and prone to inconsistency.

**Automaton advantage**: Keep all pipeline state in a single directory (e.g., `.automaton/`) with a clear, flat structure. One place to look, one place to clean up.
