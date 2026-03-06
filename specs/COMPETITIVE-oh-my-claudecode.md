# Competitive Analysis: Oh My Claude Code (Yeachan-Heo/oh-my-claudecode)

## Overview

**Oh My Claude Code (OMC)** is a multi-agent orchestration system for Claude Code. It is written in **TypeScript** (primary language), with supporting JavaScript (CJS bridge bundles), Python (bridge/benchmark), and Bash scripts. The npm package is published as `oh-my-claude-sisyphus`.

| Metric | Value |
|--------|-------|
| Language | TypeScript (primary), JS, Python, Bash |
| Stars | 8,065 |
| Forks | 558 |
| License | MIT |
| Version | 4.6.0 |
| Created | 2026-01-09 |
| Last Updated | 2026-03-03 (same day as analysis) |
| Production TS LOC | ~93,000 |
| Test TS LOC | ~69,000 |
| Agent prompts (MD) | ~2,200 lines across 21 agent files |
| Skill definitions (MD) | ~10,800 lines across 36 skills |
| Hook/script LOC | ~7,200 |
| Total codebase | ~377,000 lines (including tests, docs, generated bundles, JSON) |
| Test count | 5,750 tests (per PR #1248) |
| i18n | README in 7 languages (EN, KO, ZH, JA, ES, VI, PT) |

This is a **very large, very active** project. It went from creation to 8k+ stars in under 2 months, with 1,260+ issues filed. It has an active Korean-speaking author (Yeachan Heo) and a broad international community.

---

## Architecture & Structure

### High-level design

OMC installs as a **Claude Code plugin** via the `/plugin marketplace` system. It integrates through Claude Code's hook system and MCP servers, injecting orchestration behavior into standard Claude Code sessions.

```
User Input --> Magic Keyword Detection --> Skill Composition --> Agent Delegation
                                                                    |
                                           +------------------------+
                                           |          |             |
                                        Team Mode   Autopilot   Single-agent
                                        (tmux panes) (5-phase)  (ralph, ulw)
```

### Key directories

| Path | Purpose |
|------|---------|
| `src/agents/` (18 files) | Agent definitions, prompt metadata, model routing config |
| `agents/` (21 .md files) | Agent system prompts (analyst, architect, executor, critic, etc.) |
| `src/hooks/` (38 subdirs) | Claude Code lifecycle hooks (UserPromptSubmit, Stop, PreToolUse, PostToolUse) |
| `src/team/` (37 files) | Team mode runtime: tmux session management, worker health, task routing |
| `src/hud/` (14 files) | Real-time HUD statusline (context %, rate limits, agent status) |
| `src/features/` (18 subdirs) | Core features: magic keywords, delegation, model routing, background tasks |
| `src/tools/` (16 files) | LSP tools, AST tools (via ast-grep), Python REPL, shared memory, state tools |
| `src/notifications/` (14 files) | Telegram, Discord, Slack (including Socket Mode) notification dispatch |
| `src/mcp/` (16 files) | MCP server definitions, team MCP bridge, omc-tools server |
| `skills/` (36 dirs) | Skill definitions as SKILL.md files (autopilot, team, ralph, deep-interview, etc.) |
| `bridge/` (6 files) | CJS bundles for MCP servers, team bridge, runtime CLI |
| `scripts/` (35 files) | Build scripts, hook scripts, maintenance utilities |
| `benchmark/` | SWE-bench style benchmark harness comparing OMC vs vanilla Claude Code |
| `.claude-plugin/` | Plugin manifest (`plugin.json`, `marketplace.json`) |

### Tech stack

- **Runtime**: Node.js >= 20, TypeScript 5.7
- **Build**: `tsc` + esbuild (for CJS bundles)
- **Testing**: Vitest 4.x (5,750 tests)
- **Key dependencies**: `@anthropic-ai/claude-agent-sdk`, `@modelcontextprotocol/sdk`, `@ast-grep/napi`, `better-sqlite3`, `zod`, `commander`, `chalk`
- **Multi-model**: tmux-based worker panes for `claude`, `codex`, and `gemini` CLI processes
- **State**: JSON files in `.omc/state/`, with optional centralized `OMC_STATE_DIR`

### Integration model

OMC integrates with Claude Code via two mechanisms:
1. **Hooks** (`src/hooks/`): 38+ hooks for lifecycle events (prompt submit, tool use, stop, session end, compaction)
2. **MCP Servers** (`.mcp.json`): Two MCP servers -- `t` (omc-tools providing LSP/AST/state/memory tools) and `team` (team runtime management)

---

## Features

### Orchestration Modes

| Mode | Description |
|------|-------------|
| **Team** (canonical) | Staged pipeline: plan -> PRD -> exec -> verify -> fix loop. Runs in tmux with Claude Code's experimental agent teams. |
| **omc-teams** | Spawns real CLI processes (claude/codex/gemini) as tmux split-pane workers. On-demand, die when done. |
| **ccg** | Tri-model: Codex (analytical) + Gemini (design) in parallel, Claude synthesizes results. |
| **Autopilot** | 5-phase autonomous execution: expansion -> planning -> execution -> QA -> validation. |
| **Ultrawork (ulw)** | Maximum parallelism mode for burst parallel fixes/refactors. |
| **Ralph** | Persistent execution with verify/fix loops. Auto-generates PRD. Cannot stop until verified done. |
| **Pipeline** | Sequential staged processing with strict ordering. |
| **Swarm / Ultrapilot** | Legacy compatibility facades that route to Team. |

### Agent System

21 specialized agent prompt files with metadata-driven routing:

- **Tiered model routing**: Haiku (LOW/quick), Sonnet (MEDIUM/standard), Opus (HIGH/complex)
- **32 agents** total (per README): architect, analyst, explorer, executor, designer, writer, critic, planner, debugger, security-reviewer, qa-tester, build-fixer, code-reviewer, code-simplifier, deep-executor, document-specialist, git-master, scientist, test-engineer, verifier, quality-reviewer
- **Delegation categories**: `visual-engineering`, `ultrabrain`, `artistry`, `quick`, `writing` -- each with preset temperature and thinking budget
- **Model aliases config**: Override agent defaults for non-Claude backends (e.g., DashScope, OpenRouter)

### Skills System

36 skills defined as `SKILL.md` files:

`analyze`, `autopilot`, `build-fix`, `cancel`, `ccg`, `code-review`, `configure-notifications`, `configure-openclaw`, `deep-interview`, `deepinit`, `external-context`, `hud`, `learn-about-omc`, `learner`, `mcp-setup`, `note`, `omc-doctor`, `omc-help`, `omc-setup`, `omc-teams`, `plan`, `project-session-manager`, `ralph-init`, `ralph`, `ralplan`, `release`, `sciomc`, `security-review`, `skill`, `tdd`, `team`, `trace`, `ultraqa`, `ultrawork`, `writer-memory`

### Magic Keywords

Natural language triggers: `team`, `omc-teams`, `ccg`, `autopilot`, `ralph`, `ulw`, `plan`, `ralplan`, `deep-interview`, `swarm` (deprecated), `ultrapilot` (deprecated)

### HUD (Heads-Up Display)

Real-time tmux statusline showing:
- OMC version
- Context window usage percentage
- Rate limit status (with error indicators like `[API err]`, `[API auth]`)
- Active profile name (multi-profile support)
- API key source indicator (project vs global)
- Custom rate provider support
- Configurable max width

### Notification System

- **Telegram**: Bot token integration with @mention tagging
- **Discord**: Webhook with @here/@everyone/user ID/role support
- **Slack**: Incoming webhooks AND Socket Mode (bidirectional WebSocket for replay injection)
- **File**: Local file output
- Stop callback notifications with session summaries
- Token redaction in logs

### Developer Tools (via MCP)

- **LSP Tools**: Language Server Protocol integration for IDE-like diagnostics
- **AST Tools**: ast-grep based code analysis
- **Python REPL**: Embedded Python execution
- **Shared Memory**: Cross-agent memory with file locking
- **State Tools**: Mode/session state management
- **Trace Tools**: Execution tracing
- **Notepad/Wisdom**: Plan-scoped knowledge capture (learnings, decisions, issues, problems)
- **Directory Diagnostics**: `tsc --noEmit` and LSP-based quality checks

### Other Notable Features

- **Deep Interview**: Socratic questioning for requirements elicitation (inspired by Ouroboros)
- **Factcheck Sentinel**: Readiness gate for team pipeline verification
- **Rate Limit Wait**: Auto-resume daemon when rate limits reset (`omc wait --start`)
- **Auto-update**: Background update checking from GitHub releases
- **Context Injection**: Automatic AGENTS.md/CLAUDE.md loading
- **Continuation Enforcement**: Prevents premature task completion
- **Learner Hook**: Extracts reusable patterns from sessions
- **Cross-session Memory Sync**: Shared memory subsystem for multi-agent handoffs
- **Benchmark Suite**: SWE-bench comparison harness (OMC vs vanilla)
- **OpenClaw Integration**: Gateway hooks for OpenClaw compatibility
- **Centralized State**: `OMC_STATE_DIR` for preserving state across worktree deletions
- **Project Session Manager**: tmux-based session management

---

## What Users Like

### Popularity signal

8,065 stars and 558 forks in under 2 months is exceptional growth. The project has README translations in 7 languages, indicating strong international adoption (particularly Korean, Chinese, Japanese communities).

### Positive feedback from issues

- **Issue #1217** (9 comments): Users asking for an OpenClaw version -- "The oh-my-claudecode experience is excellent" -- shows genuine enthusiasm.
- **Issue #1214** (3 comments): Feature request for writing/document mode -- user opens with "I want to express my sincere gratitude to everyone who built and maintains oh-my-claudecode."
- **Issue #1149** (3 comments): A physician (non-dev) proposing factcheck features -- shows OMC has reached non-developer users doing real clinical work.
- **Issue #1240** (6 comments): Community member (zivtech) contributing A/B-tested research on review agent design, then publishing a standalone skill. Deep community engagement.

### What users clearly value

1. **Zero learning curve** -- natural language interface with no commands to memorize
2. **Multi-model orchestration** -- ability to use Claude + Codex + Gemini together
3. **Persistence** -- ralph mode's "won't give up until verified" behavior
4. **Real-time visibility** -- HUD statusline showing what is happening
5. **Team mode** -- coordinated multi-agent execution with tmux
6. **Plugin-based install** -- simple `/plugin marketplace add` workflow

---

## What Users Dislike / Struggle With

### Installation and compatibility issues

- **Issue #1218**: Plugin not recognized in Claude Code 2.1.63 -- requires explicit `settings.json` enablement. Users expect plug-and-play.
- **Issue #1129**: CLI detection fails for version-manager-installed CLIs (mise, asdf, nvm, fnm, volta). MCP server processes do not inherit interactive-shell PATH.
- **Issue #1245**: Confusion about whether omc-teams requires Claude Code itself to run inside tmux.

### Stability and reliability

- **Issue #1258** (6 comments): Claude ignores new requests and summarizes previous context instead -- a significant UX problem that occurs after ~20 minutes of runtime.
- **Issue #1158**: Leader pane breaks during fast worker spawn/kill cycles (layout thrashing), corrupting the TUI display.
- **Issue #1144**: Race condition where `send-keys` fires before zsh is ready in promptMode agent panes.
- **Issue #1241**: `omc_run_team_wait` could miss completion and appear to hang indefinitely.
- **Issues #1159, #1160, #1167, #1168**: Multiple shared memory bugs -- non-atomic writes, silent data loss on concurrent writes, TOCTOU cache bugs, full-overwrite sync without merge strategy.

### Complexity and mode confusion

- **Issue #1130**: "Currently 8 execution modes" acknowledged as a problem -- the author proposed unifying autopilot/ultrawork/ultrapilot into a single configurable pipeline.
- **Issue #1221**: Ralplan execution mode options outdated and inconsistent with README recommendations.
- **Issue #1131**: Multiple legacy modes needing deprecation.

### Model routing inflexibility

- **Issue #1135**: Users want a single-model option -- "model routing system always overrides my preference."
- **Issue #1201**: Hardcoded Claude model names prevent CC Switch users from using other models (glm-5, MiniMax, Kimi).
- **Issue #1211**: Agent model mapping overridden by hardcoded model in agent definition files.

### State management

- **Issue #1126**: `OMC_STATE_DIR` not respected by HUD and hooks -- `.omc/` still created inside project directories.
- **Issue #1118**: HUD creates `.omc/state/` in subdirectories instead of worktree root.
- **Issue #1191**: Stop hook error when transcript path is missing during worktree operations.

### Security concerns

- Issues #1161-#1170: A cluster of 10 security/reliability issues filed in rapid succession, covering path traversal in worker inbox, Slack token exposure, WebSocket message validation, shell RC trust boundaries, and shared memory corruption.

---

## Good Ideas to Poach

### 1. Magic keyword detection via natural language

OMC's keyword detection system (`src/features/magic-keywords.ts`) lets users type `autopilot: build a REST API` and the system automatically routes to the right execution mode. This is zero-friction UX that Automaton could adopt for mode selection (e.g., `parallel:`, `sequential:`, `verify:`).

### 2. HUD statusline

The real-time HUD showing context window usage, rate limit status, active mode, and profile is genuinely useful feedback. Automaton could implement a lightweight progress bar or status output in the terminal showing pipeline phase, agent activity, and resource usage.

### 3. Deep Interview / Socratic requirements elicitation

The `/deep-interview` skill (inspired by Ouroboros) that uses Socratic questioning to clarify vague requirements before any code is written. This directly addresses the "garbage in, garbage out" problem of spec-driven pipelines. Automaton could adopt a pre-execution interview phase for ambiguous specs.

### 4. Plan-scoped notepad/wisdom system

OMC stores learnings, decisions, issues, and problems in `.omc/notepads/{plan-name}/` as timestamped markdown. This is a practical knowledge management approach that Automaton could use to persist context across pipeline stages.

### 5. Verification protocol with evidence freshness

OMC's verification module requires fresh evidence (within 5 minutes) and actual command output for BUILD/TEST/LINT/FUNCTIONALITY checks. This is more rigorous than "did it pass y/n" and prevents stale verification claims.

### 6. Ralph persistence mode ("cannot stop until verified done")

The continuation enforcement system (`src/features/continuation-enforcement.ts`) that prevents premature task completion is a pattern Automaton should adopt. Too many AI pipelines declare victory prematurely.

### 7. Delegation categories with auto-detected parameters

The semantic task classification system (`visual-engineering`, `ultrabrain`, `quick`, etc.) that auto-selects model tier, temperature, and thinking budget from prompt analysis. Automaton could use similar heuristics to choose between fast/cheap and slow/expensive model calls.

### 8. Rate limit auto-resume

`omc wait --start` runs a daemon that detects rate limits and auto-resumes the session when limits reset. For long-running Automaton pipelines, this would prevent stalls.

### 9. Notification callbacks (Telegram/Discord/Slack)

Session completion notifications with summaries sent to chat platforms. For headless/background Automaton runs, this is essential UX.

### 10. Benchmark harness

OMC includes a `benchmark/` directory with SWE-bench style evaluation comparing OMC-enhanced vs vanilla Claude Code. Automaton should build a similar comparison framework to prove its value quantitatively.

---

## Ideas to Improve On

### 1. Overwhelming complexity

OMC has 93k lines of production TypeScript, 8 execution modes (acknowledged as too many in issue #1130), 36 skills, 21 agents, 38 hook directories, and a deeply nested architecture. **Automaton's single-bash-file approach is a massive advantage** for debuggability, portability, and onboarding. OMC's complexity creates real user confusion (see issues #1221, #1130, #1131).

**Opportunity**: Automaton's simplicity is a feature. Emphasize it. A single file with clear pipeline stages is easier to understand, modify, and debug than 654 TypeScript source files.

### 2. tmux dependency is fragile

OMC's Team mode and omc-teams both require tmux for multi-agent coordination. This creates installation friction (issue #1245), race conditions (issue #1144), layout thrashing (issue #1158), and platform incompatibility (Windows users need WSL). tmux session management is 37 files of code.

**Opportunity**: Automaton can use simpler process management (background subshells, `&`, `wait`) without requiring tmux. This works everywhere bash runs.

### 3. State management is scattered and buggy

OMC stores state in `.omc/state/`, `.omc/notepads/`, `.omc/plans/`, `.omc/autopilot/`, plus global `~/.omc/state/`. Issues #1126 and #1118 show state ending up in wrong directories. The shared memory system had multiple critical bugs (issues #1159, #1160, #1167, #1168).

**Opportunity**: Automaton can use a single, flat state directory with atomic file operations from the start. A simpler state model is more reliable.

### 4. Installation requires plugin system knowledge

OMC requires `/plugin marketplace add`, then `/plugin install`, then `/omc-setup`. Users hit issues with unrecognized plugins (issue #1218) and CLI detection failures (issue #1129). The npm package name (`oh-my-claude-sisyphus`) differs from the repo name, adding confusion.

**Opportunity**: A single bash file that is sourced or executed directly has zero installation friction. No plugin system, no npm, no build step.

### 5. Multi-model orchestration adds complexity without clear ROI

The Codex/Gemini integration (ccg mode, omc-teams with codex/gemini workers) requires three separate AI subscriptions ($60/month), three CLI installations, and introduces cross-model coordination bugs (issue #1204, #1148, #1151). The gemini worker has had gitignore bypass issues and done.json completion detection failures.

**Opportunity**: Automaton can focus on doing one model exceptionally well rather than juggling three. If multi-model is needed, it can be a simple optional flag rather than a complex tmux worker system.

### 6. Security issues from architecture complexity

The 10-issue security cluster (#1159-#1170) reveals that architectural complexity creates security surface area: path traversal in worker inbox, token exposure in logs, unvalidated WebSocket messages, shell RC trust boundaries. A simpler architecture has fewer attack vectors.

**Opportunity**: Automaton's single-file approach has a much smaller attack surface. State files in a single directory, no IPC channels, no WebSocket listeners, no tmux pane injection.

### 7. Context window exhaustion

Issue #1258 describes Claude ignoring new requests after ~20 minutes and summarizing previous context instead. This is a fundamental problem with large orchestration systems that inject massive system prompts (OMC's generated CLAUDE.md, 32 agent definitions, skill compositions). OMC's approach of injecting everything into context can exhaust the window.

**Opportunity**: Automaton should keep orchestration prompts minimal and pipeline-stage-specific rather than loading everything at once. Each stage gets only what it needs.

### 8. No clear spec-to-code pipeline

Despite its complexity, OMC does not have a structured spec-to-code pipeline as its primary abstraction. Its autopilot mode comes closest (5 phases: expansion -> planning -> execution -> QA -> validation), but it is one of 8 modes, not the core concept. The user must choose between team, autopilot, ralph, ultrawork, etc.

**Opportunity**: Automaton's spec-first pipeline is a clearer mental model. One way to do things. Spec in, code out, verified.

### 9. Test-to-production ratio suggests over-engineering

69,000 lines of tests for 93,000 lines of production code is healthy coverage, but the sheer volume (5,750 tests) suggests a system that has grown beyond what a single developer or small team can maintain coherently. Many tests are fixing regressions from other fixes (issue #1248: "stub TMUX env for tmux-in-tmux test environments").

**Opportunity**: Automaton's simplicity means fewer tests needed. Integration tests of the pipeline stages matter more than unit tests of internal abstractions.

### 10. Documentation sprawl

OMC has `README.md`, `AGENTS.md`, `ANALYSIS.md`, `CATEGORY_IMPLEMENTATION.md`, `CHANGELOG.md`, `CLAUDE.md`, `IMPLEMENTATION_SUMMARY.md`, `ISSUE-319-FIX.md`, `REVIEW-FIXES.md`, `SECURITY-FIXES.md`, plus 7 README translations, plus `docs/` with 13 files, plus `AGENTS.md` in 3 locations. This is hard for users to navigate.

**Opportunity**: Automaton can maintain a single README and inline comments in the bash file. The code IS the documentation.
