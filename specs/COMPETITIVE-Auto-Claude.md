# Competitive Analysis: Auto-Claude (AndyMik90/Auto-Claude)

## Overview

**What it is:** Auto-Claude is an autonomous multi-agent coding framework that plans, builds, and validates software through a desktop application (Electron) and CLI. Users describe a goal; AI agents autonomously handle planning, implementation, and QA validation. All work happens in isolated git worktrees so the main branch stays safe.

| Metric | Value |
|--------|-------|
| **Primary Language** | TypeScript (frontend) + Python (backend) |
| **Stars** | 12,931 |
| **Forks** | 1,774 |
| **License** | AGPL-3.0 |
| **Created** | 2024-12-04 |
| **Last Updated** | 2026-03-03 |
| **Current Version** | 2.7.6 (stable), 2.7.6-beta.6 (beta) |
| **Total Source Files** | ~1,518 (.py, .ts, .tsx, .js, .jsx) |
| **Total LOC** | ~451,000 (Python: ~201k, TypeScript/TSX: ~250k) |
| **Test Files** | 106 Python test files (~57,600 LOC) |
| **Watchers** | 104 |

**Requires:** Claude Pro/Max subscription, Claude Code CLI (`@anthropic-ai/claude-code`), git repo.

**Distribution:** Native desktop apps for Windows (.exe), macOS (.dmg, Intel + Apple Silicon), Linux (.AppImage, .deb, .flatpak). Auto-updates included. CLI mode also available for headless/CI usage.

---

## Architecture & Structure

### High-Level Organization

Monorepo with two main apps:

```
Auto-Claude/
  apps/
    backend/          # Python — ALL agent logic, CLI, specs, QA, merge
      agents/         # planner.py, coder.py, session.py, memory_manager.py
      qa/             # reviewer.py, fixer.py, loop.py, criteria.py, report.py
      spec/           # Spec creation pipeline (gatherer, researcher, writer, critic)
        pipeline/     # orchestrator.py, agent_runner.py, models.py
        validate_pkg/ # Spec validation (prereqs, document, strategy)
      merge/          # Intent-aware semantic merge system
        ai_resolver/  # Claude-powered conflict resolution
        auto_merger/  # Deterministic merge strategies
      security/       # Command allowlisting, validators, hooks
      context/        # Task context building, semantic search
      runners/        # Standalone runners (spec, roadmap, insights, github, gitlab)
      integrations/   # graphiti/ (memory), linear/ (PM integration)
      memory/         # Codebase mapping, session memory, patterns
      prompts/        # 25+ .md agent system prompts
      cli/            # CLI commands (spec, build, workspace, QA, batch)
      core/           # client.py, auth.py, worktree.py, platform/
    frontend/         # Electron desktop application
      src/
        main/         # Electron main process
          agent/      # Agent queue, process, state, events
          terminal/   # PTY daemon, lifecycle, Claude integration
          claude-profile/  # Multi-profile credential management
          ipc-handlers/    # 40+ handler modules by domain
          platform/        # Cross-platform abstraction
        renderer/     # React UI
          components/ # Onboarding, settings, task, terminal, github, etc.
          stores/     # 24+ Zustand state stores
        shared/       # Types, i18n (en/fr), constants, utils
  tests/              # Backend test suite (106 files, ~57k LOC)
  scripts/            # Build utilities
  guides/             # Documentation (CLI usage, Linux builds, Windows dev)
```

### Tech Stack

- **Backend:** Python 3.10+, Claude Agent SDK (`claude-agent-sdk`), asyncio, pytest
- **Frontend:** Electron 39, React 19, TypeScript (strict), Zustand 5, Tailwind CSS v4, Radix UI, xterm.js 6, Vite 7, Vitest 4, Biome 2, Motion (Framer Motion)
- **State Management:** 24+ Zustand stores (project, task, terminal, settings, github, insights, roadmap, kanban-settings, etc.)
- **IPC:** 40+ Electron IPC handler modules organized by domain
- **CI/CD:** GitHub Actions (13 workflows: CI, lint, release, beta-release, quality-security, virustotal-scan, stale, etc.)
- **Packaging:** Electron Forge for cross-platform builds
- **Memory:** Graphiti-based knowledge graph for cross-session agent memory
- **Dependencies:** `uv` for Python venv, `npm` for Node, uses `package-lock.json`

### Core Pipeline (The Heart of the System)

The autonomous workflow is a multi-agent pipeline:

1. **Spec Creation** (`spec/pipeline/orchestrator.py`) -- User describes a goal. A pipeline of agents (gatherer, researcher, writer, critic) creates a specification with requirements, complexity assessment, and QA criteria. Stored in `.auto-claude/specs/XXX-name/`.
2. **Planning** (`agents/planner.py`, `prompts/planner.md`) -- Planner agent reads the spec and creates a subtask-based implementation plan (`implementation_plan.json`) with phase dependencies.
3. **Coding** (`agents/coder.py`, `prompts/coder.md`) -- Coder agent works through subtasks one at a time in isolated git worktrees. Can spawn parallel subagents. Supports recovery from interruptions.
4. **QA Validation** (`qa/loop.py`, `qa/reviewer.py`, `qa/fixer.py`) -- Self-validating QA loop: reviewer checks, fixer addresses issues, loop continues up to 50 iterations until approved or escalated to human.
5. **Merge** (`merge/orchestrator.py`) -- Intent-aware semantic merge system with deterministic auto-merger and AI-powered conflict resolution for ambiguous cases.
6. **Human Review** -- Final user review before merging to main branch.

### Key Architectural Decisions

- **Claude Agent SDK only** -- All AI interactions use `claude-agent-sdk` (handles security hooks, tool permissions, MCP). Direct `anthropic.Anthropic()` usage is forbidden.
- **Git worktree isolation** -- Every build happens in a separate git worktree under `.auto-claude/worktrees/tasks/{spec-name}/`. Main branch is never touched during builds.
- **Three-layer security model** -- OS sandbox for bash commands, filesystem restrictions to project dir, dynamic command allowlist based on detected project stack.
- **Orchestrator-first pattern** -- The CLAUDE.md instructs Claude to act as an orchestrator: investigate, plan, delegate to agent teams, verify and integrate.
- **Phase-based execution** -- Phases with events (`phase_event.py`) track execution lifecycle (PLANNING, CODING, QA, MERGE).

---

## Features

### Core Autonomous Pipeline
- **Spec creation pipeline** with 4 specialized agents (gatherer, researcher, writer, critic) and AI-based complexity assessment
- **Subtask-based implementation plans** with phase dependencies and priority ordering
- **Parallel execution** with up to 12 agent terminals running simultaneously
- **Git worktree isolation** for every build -- main branch stays safe
- **Self-validating QA loop** (reviewer + fixer, up to 50 iterations) with acceptance criteria
- **AI-powered semantic merge** with deterministic auto-merger for simple cases and Claude-powered resolution for ambiguous conflicts
- **Recovery management** (`recovery.py`) for interrupted builds -- sessions resume from last known state
- **Batch operations** -- create, check status, cleanup multiple specs

### Desktop Application (Electron)
- **Kanban board** -- Visual task management from planning through completion with real-time progress
- **Agent terminals** -- Up to 12 AI-powered PTY terminals with one-click task context injection (xterm.js + WebGL)
- **Insights** -- AI chat interface for exploring and understanding your codebase
- **Roadmap** -- AI-assisted feature planning with competitor analysis and audience targeting
- **Ideation** -- Discover improvements, performance issues, security vulnerabilities, documentation gaps, and UI/UX improvements (6 specialized prompts in `prompts/ideation_*.md`)
- **Changelog generator** -- Generate release notes from completed tasks
- **7 color themes** (Default, Dusk, Lime, Ocean, Retro, Neo, more) with light/dark mode
- **i18n** -- English and French localization with react-i18next
- **Auto-updates** -- Built-in auto-updater for stable and beta channels

### Integrations
- **GitHub integration** -- Import issues, AI-powered investigation, PR creation with template generation, PR review system with trigger-driven exploration
- **GitLab integration** -- Import issues, create merge requests
- **Linear integration** -- Sync tasks with Linear for team progress tracking
- **Graphiti memory system** -- Graph-based semantic memory that retains insights across sessions (via MCP server)
- **MCP server integration** -- Support for external MCP servers (Figma, Chrome, etc.)
- **Ollama support** -- Local model detection for alternative endpoints

### Authentication & Profiles
- **Multi-account swapping** -- Register multiple Claude accounts; automatic switch when rate-limited
- **OAuth + API profiles** -- Use Claude Code subscription (OAuth) or API profiles with any Anthropic-compatible endpoint (Anthropic API, z.ai for GLM models)
- **Token lifecycle management** -- Automatic OAuth token refresh, credential storage via OS keychain
- **Profile scoring** -- Scores profiles by usage and availability for intelligent rotation

### Security
- **Three-layer security** -- OS sandbox, filesystem restrictions, dynamic command allowlist
- **Command allowlisting** -- Base commands (always allowed), stack-detected commands (from project analysis), custom user commands
- **Secret scanning** -- Built-in secret detection (`scan_secrets.py`)
- **VirusTotal scanning** -- All releases scanned before publishing
- **SHA256 checksums** -- For release verification

### CLI Mode
- `python run.py --spec 001` -- Run autonomous build
- `python run.py --spec 001 --review` -- Review what was built
- `python run.py --spec 001 --merge` -- Merge to main
- `python run.py --spec 001 --qa` -- Run QA validation
- `python spec_runner.py --interactive` -- Create spec interactively
- Batch commands for multi-spec operations
- Headless operation for CI/CD integration

### Developer Experience
- **E2E testing via Electron MCP** -- QA agents can interact with the running Electron app via Chrome DevTools Protocol (take_screenshot, click_by_text, fill_input, etc.)
- **Pre-commit hooks** -- Husky + lint-staged for frontend, Ruff for backend
- **Sentry error tracking** -- Instrumented for production error monitoring
- **Debug mode** -- `npm run dev:debug` for verbose output and AI self-validation

---

## What Users Like

### High Star Count & Rapid Growth
- 12,931 stars and 1,774 forks indicate strong interest in autonomous coding tools
- Featured in "Awesome Claude Code" list (issue #1811)
- Active Discord community
- YouTube channel with tutorials

### The Full Pipeline Concept
- Users value the end-to-end autonomy: describe a goal and get working code with QA validation
- The spec-to-code pipeline (spec creation -> planning -> coding -> QA -> merge) is the core value proposition
- Git worktree isolation gives users confidence to let agents run unsupervised

### Cross-Platform Desktop App
- Native apps for all three platforms (Windows, macOS, Linux) with auto-updates
- The visual Kanban board and terminal UI make it accessible to non-CLI users
- Multiple distribution formats (AppImage, deb, flatpak, dmg, exe)

### Parallel Execution
- Up to 12 simultaneous agent terminals is a differentiator
- Queue system with smart task prioritization and auto-promotion

### Active Development
- Rapid release cadence (v2.7.6 with extensive changelog)
- Responsive to community issues (many bugs get "auto-claude:findings-ready" label with AI-generated investigation)
- PRs from external contributors accepted (accessibility fixes, test coverage, etc.)

---

## What Users Dislike / Struggle With

### AI Merge is Broken (Issue #1854)
- The "Merge with AI" button only analyzes conflicts but does not actually resolve them. Users report it "just analyzing the problem without solving it." This is a core feature that does not work as advertised. Severity: high.

### Rate Limiting and Auth Issues Are Pervasive
- **Issue #1864:** Tasks fail with `rate_limit_event` error even on Claude Max plan, before any meaningful work starts
- **Issue #1903:** Incorrect rate limit error for inactive "Primary" profile while using Z.AI API -- the system conflates OAuth and API profile rate limits
- **Issue #1876:** Auth loop: repeated re-authentication due to token/env precedence and credential parsing drift
- **Issue #1798:** OAuth-to-API profile swap infrastructure was built but never wired into execution paths
- **Issue #1768:** Prepaid Anthropic billing accounts not recognized as authenticated

### Windows is a Second-Class Citizen
- **Issue #1800:** PR review logs show "No logs yet" because `\r\n` line endings break all log parsing regexes
- **Issue #1911:** Cannot paste in agent terminals on Windows
- **Issue #1856:** Logs UI bug with errors on Windows
- **Issue #1801:** Failed building wheel for `real_ladybug` on Windows (Graphiti dependency)
- Multiple Windows-specific path resolution bugs documented in CHANGELOG

### Worktree System Causes Disk Bloat (Issue #1901)
- Each worktree gets its own full `node_modules` copy (~1GB+) instead of symlinking. In monorepos, the root project's dependencies are never analyzed, causing massive duplication.

### Spec Writing Fails with Non-Anthropic Models (Issue #1883)
- Planning phase completes but spec writing fails with "Agent did not create spec.md" when using custom endpoints (LM Studio, OpenRouter). The system is tightly coupled to Anthropic's API behavior.

### State Management Bugs
- **Issue #1910:** Reopening a project does not reload the UI -- Kanban cards, roadmap all empty
- **Issue #1885:** Kanban card shows planning stage when actually in coding stage
- **Issue #1879:** Expanding memories throws error
- **Issue #1878:** Terminal does not resume after crash
- **Issue #1882:** Setup wizard fails at the beginning

### Complexity is Overwhelming
- 451,000 LOC across 1,518 source files
- 24+ Zustand stores, 40+ IPC handlers
- The CLAUDE.md alone is 333 lines of instructions for AI agents working on the codebase
- Multiple backward-compatibility shim files suggest rapid iteration without cleanup

### MCP Integration Issues
- **Issue #1792:** Figma MCP does not work
- **Issue #1870:** Planning agent cannot use Jira MCP tools despite server showing "connected successfully"
- **Issue #1775:** Graphiti MCP server fails to start silently, wizard stuck in loop

---

## Good Ideas to Poach

### 1. Spec Creation Pipeline with Complexity Assessment
Auto-Claude's 4-agent spec pipeline (gatherer -> researcher -> writer -> critic) with AI-based complexity assessment (`complexity_assessor.md`) is sophisticated. The complexity score determines the number of phases and depth of planning. **Automaton could adopt:** A lightweight version where the spec undergoes a critique pass before execution, and complexity determines whether to use single-pass or multi-phase execution.

### 2. Self-Validating QA Loop
The QA reviewer + fixer loop (up to 50 iterations) with explicit acceptance criteria from the spec is powerful. The reviewer agent checks against spec requirements, and the fixer agent addresses issues. **Automaton could adopt:** A validation pass after code generation that checks against spec requirements and loops if failures are found, with a configurable max iteration count.

### 3. Git Worktree Isolation
All builds happen in isolated git worktrees under `.auto-claude/worktrees/tasks/`. Main branch is never touched. **Automaton could adopt:** Create a worktree before execution and merge back after validation passes. This is simple to implement in bash (`git worktree add`, `git worktree remove`).

### 4. Dynamic Command Allowlisting from Project Analysis
The security system detects the project's stack (Python, Node, Go, etc.) and dynamically allows relevant commands. Base commands are always allowed; stack-specific commands are auto-detected. **Automaton could adopt:** A project analysis step that determines the tech stack and tailors the execution environment accordingly.

### 5. Recovery from Interruptions
`recovery.py` allows builds to resume from the last known state after crashes or interruptions. Progress is tracked in `implementation_plan.json` with subtask statuses (pending, in_progress, completed). **Automaton could adopt:** Checkpoint files that track which spec steps have been completed, allowing re-runs to skip already-done work.

### 6. Phase Events and Progress Tracking
The `phase_event.py` system emits structured events for each execution phase (PLANNING, CODING, QA, MERGE). Combined with `progress.py` which tracks subtask completion counts. **Automaton could adopt:** Simple progress output at each pipeline stage showing what step we are on and what is remaining.

### 7. Subtask-Based Implementation Plans
The planner creates structured `implementation_plan.json` with phases containing ordered subtasks, each scoped to one service/component. Dependencies between phases are respected. **Automaton could adopt:** For complex specs, break the work into ordered subtasks and execute them sequentially, verifying each before moving on.

### 8. Agent Prompt Architecture
25+ specialized `.md` prompt files in `prompts/` with clear role definitions, mandatory phases (PHASE 0: LOAD CONTEXT, PHASE 1: VERIFY, etc.), and explicit constraints. Each prompt is task-specific rather than generic. **Automaton could adopt:** Separate, focused system prompts for each pipeline stage rather than one monolithic prompt.

### 9. Multi-Account Rate Limit Rotation
When one Claude account hits a rate limit, the system automatically switches to another registered account. Profile scoring ranks accounts by usage and availability. **Automaton could adopt (if relevant):** Simple API key rotation with health checking.

### 10. Ideation Feature
Six specialized ideation prompts (`ideation_code_improvements.md`, `ideation_security.md`, `ideation_performance.md`, etc.) that scan the codebase for improvements. **Automaton could adopt:** A pre-build analysis pass that identifies potential issues in the target area before making changes.

---

## Ideas to Improve On

### 1. Eliminate the Electron Desktop App Overhead
Auto-Claude's ~250k LOC TypeScript frontend is its biggest liability. It introduces massive complexity (40+ IPC handlers, 24+ Zustand stores, cross-platform Electron bugs, PTY management, GPU crashes). **Automaton's advantage:** A single bash file is infinitely simpler to distribute, debug, and maintain. No Electron, no React, no build step, no platform-specific packaging. Users just `curl` and run.

### 2. Actually Make Merge Work
Auto-Claude's AI merge system is reported broken (issue #1854) -- it analyzes conflicts but does not resolve them. The merge subsystem alone has 25+ files with AI resolver, auto merger, semantic analyzer, file evolution tracker, conflict detector, etc. **Automaton can do better:** Use simple `git merge` with conflict detection, and if conflicts exist, feed them to Claude with a focused prompt asking for resolution. No need for a 25-file merge framework.

### 3. Support Non-Anthropic Models Properly
Auto-Claude's tight coupling to `claude-agent-sdk` and Anthropic's API means custom endpoints frequently break (issue #1883, #1718). The spec writing pipeline fails entirely with local models. **Automaton can do better:** By being model-agnostic from day one -- if you can call it from a CLI or API, it works.

### 4. Avoid Disk Bloat from Worktrees
Auto-Claude duplicates `node_modules` (~1GB+) per worktree because the root project is not analyzed (issue #1901). **Automaton can do better:** Symlink shared dependencies into worktrees, or use `--no-install` patterns that reuse the parent's dependency tree.

### 5. Simplify the Security Model
Auto-Claude's three-layer security (OS sandbox, filesystem restrictions, dynamic command allowlist) with 15+ files in `security/` is complex and fragile. **Automaton can do better:** Since it is a bash script that the user runs intentionally, leverage the OS's existing permission model. A simple allowlist file is sufficient.

### 6. Reduce State Management Complexity
24+ Zustand stores with complex synchronization between main and renderer processes leads to state bugs (issue #1885: Kanban shows wrong stage; issue #1910: reopening project shows empty UI). **Automaton can do better:** State is the spec file plus git status. No stores, no sync, no UI state bugs.

### 7. Make QA Actually Lightweight
Auto-Claude's QA loop can run up to 50 iterations with separate reviewer and fixer agents, each spawning new Claude sessions. This burns tokens rapidly. **Automaton can do better:** A single validation pass that runs the project's test suite and linting, then feeds failures back for one fix attempt. If it does not pass after 2-3 rounds, escalate to human.

### 8. Avoid the i18n Tax Early On
Auto-Claude requires all UI strings in both English and French via react-i18next. This adds friction to every UI change. **Automaton's advantage:** No UI means no i18n burden.

### 9. Ship Smaller, Iterate Faster
Auto-Claude is 451,000 LOC with 13 CI workflows, pre-commit hooks, Sentry instrumentation, VirusTotal scanning, and code signing. The release process requires a dedicated `RELEASE.md` document. **Automaton's advantage:** Single file. `git push` to release. The entire competitive surface is simplicity and speed of iteration.

### 10. Better Error Visibility
Multiple issues report that errors are invisible or swallowed: issue #1762 says "Task Failed: Encountered an error but won't show what the error is", issue #1856 reports log UI bugs, issue #1862 describes "strange behavior in logs." **Automaton can do better:** Since output goes to stdout/stderr in a terminal, errors are immediately visible. No Electron log routing to break.

### 11. Do Not Require Claude Pro/Max Subscription
Auto-Claude requires a Claude Pro/Max subscription and the Claude Code CLI. This gates the entire tool behind a specific subscription tier. **Automaton can do better:** Work with any API key or any model that exposes a compatible interface, lowering the barrier to entry.
