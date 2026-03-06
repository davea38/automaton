# Competitive Analysis: Agent Orchestrator (ComposioHQ/agent-orchestrator)

## Overview

**Agent Orchestrator** (AO) is an open-source system for orchestrating parallel AI coding agents across repositories, issue trackers, and runtimes. Built by ComposioHQ, it manages fleets of AI agents that work simultaneously on different issues, each in its own git worktree with its own branch and PR.

| Metric | Value |
|--------|-------|
| **Primary Language** | TypeScript (ESM, strict mode) |
| **Stars** | 2,942 |
| **Forks** | 307 |
| **License** | MIT |
| **Last Updated** | 2026-03-03 (actively developed, multiple PRs merged same day) |
| **Total Issues** | 55 (38 open, 17 closed) |
| **Total PRs** | 79 (61 merged) |
| **Source LOC (non-test)** | ~17,843 TypeScript + ~6,261 TSX = ~24,104 |
| **Test LOC** | ~29,899 (3,288 test cases claimed) |
| **Total LOC** | ~53,473 (all code files) |
| **Package Manager** | pnpm workspaces (monorepo) |
| **Node Version** | 20+ |
| **Key Dependencies** | Next.js 15, Commander.js, Zod, YAML parser, xterm.js |

The project is very active -- PRs #272 through #276 were all merged/opened on 2026-03-03 alone. The self-hosting "dogfood" config (`agent-orchestrator.yaml`) shows ComposioHQ uses AO to build AO itself.

## Architecture & Structure

### Monorepo Layout (pnpm workspaces)

```
packages/
  core/           -- @composio/ao-core: types, config, session-manager, lifecycle-manager, metadata, paths, prompt-builder
  cli/            -- @composio/ao-cli: the `ao` command (Commander.js)
  web/            -- @composio/ao-web: Next.js 15 dashboard (App Router + Tailwind)
  mobile/         -- React Native (Expo) mobile app for session monitoring
  integration-tests/  -- Cross-package integration test suite
  agent-orchestrator/ -- Wrapper package (bin/ao.js entry point)
  plugins/
    runtime-tmux/          runtime-process/
    agent-claude-code/     agent-codex/         agent-aider/    agent-opencode/
    workspace-worktree/    workspace-clone/
    tracker-github/        tracker-linear/
    scm-github/
    notifier-desktop/      notifier-slack/      notifier-composio/   notifier-webhook/
    terminal-iterm2/       terminal-web/
```

### Core Architecture: 8 Plugin Slots

The central design pattern is a **slot-based plugin architecture** with 8 swappable slots:

| Slot | Interface | Default | Alternatives |
|------|-----------|---------|-------------|
| **Runtime** | `Runtime` | tmux | process, (docker/k8s planned) |
| **Agent** | `Agent` | claude-code | codex, aider, opencode |
| **Workspace** | `Workspace` | worktree | clone |
| **Tracker** | `Tracker` | github | linear, (jira planned) |
| **SCM** | `SCM` | github | (gitlab planned) |
| **Notifier** | `Notifier` | desktop | slack, composio, webhook |
| **Terminal** | `Terminal` | iterm2 | web |
| **Lifecycle** | (core) | built-in | -- |

All interfaces are defined in `packages/core/src/types.ts` (1,098 lines). A plugin exports a `PluginModule` with a `manifest` and `create()` function, using TypeScript `satisfies` for compile-time checking.

### Key Files

| File | Role | Lines |
|------|------|-------|
| `packages/core/src/types.ts` | All interfaces -- Runtime, Agent, Workspace, Tracker, SCM, Notifier, Terminal, Session, Events, Reactions, Config | 1,098 |
| `packages/core/src/session-manager.ts` | CRUD for sessions: spawn, list, get, kill, restore, send, cleanup | 1,152 |
| `packages/core/src/lifecycle-manager.ts` | Polling loop + state machine + reaction engine | 611 |
| `packages/core/src/config.ts` | YAML config loader with Zod validation | 422 |
| `packages/core/src/prompt-builder.ts` | 3-layer prompt composition (base + config + user rules) | 179 |
| `packages/core/src/orchestrator-prompt.ts` | Generates system prompt for the orchestrator agent | 212 |
| `packages/core/src/metadata.ts` | Flat key=value file I/O for session metadata | ~200 |
| `packages/core/src/paths.ts` | Hash-based directory structure, session naming | ~200 |
| `packages/plugins/agent-claude-code/src/index.ts` | Claude Code agent plugin (JSONL activity detection, cost tracking) | 832 |
| `packages/plugins/agent-codex/src/index.ts` | OpenAI Codex agent plugin | 819 |
| `packages/plugins/scm-github/src/index.ts` | GitHub SCM: PR lifecycle, CI checks, reviews, merge readiness | 581 |
| `packages/cli/src/commands/start.ts` | `ao start` command: dashboard + orchestrator launch, URL onboarding | 497 |
| `packages/web/src/components/Dashboard.tsx` | Main dashboard UI with Kanban-style attention zones | 274 |
| `packages/web/src/components/SessionDetail.tsx` | Session detail page with embedded terminal | 682 |

### Stateless Design

AO is explicitly **stateless** -- no database. Session state is stored as flat key=value metadata files under `~/.agent-orchestrator/{hash}-{projectId}/sessions/`. Events are logged to JSONL. The hash is derived from the config file path, enabling multiple AO instances to coexist without collision.

### Session Lifecycle State Machine

Sessions transition through 14 states:
`spawning -> working -> pr_open -> review_pending -> changes_requested -> approved -> mergeable -> merged`
Plus: `ci_failed`, `needs_input`, `stuck`, `errored`, `killed`, `done`, `terminated`, `cleanup`

Activity detection has 6 states: `active`, `ready`, `idle`, `waiting_input`, `blocked`, `exited`.

## Features

### Core Features

1. **Parallel agent management** -- Spawn N agents simultaneously, each in isolated git worktrees with unique branches and PRs
2. **Agent-agnostic** -- First-class support for Claude Code, OpenAI Codex, Aider, and OpenCode via plugin interfaces
3. **One-command onboarding** -- `ao start https://github.com/org/repo` clones, auto-detects language/package manager, generates config, starts dashboard + orchestrator
4. **Automated reaction engine** -- CI failures auto-forwarded to agents with retry/escalation; review comments auto-routed; merge readiness notifications
5. **Web dashboard** (Next.js 15) -- Kanban-style attention zones (merge ready, needs response, review, pending, working, done), PR table with CI/review status, embedded xterm.js terminal, real-time SSE updates
6. **CLI** (`ao` command) -- `ao spawn`, `ao status`, `ao send`, `ao session ls/kill/restore`, `ao dashboard`, `ao open`
7. **Orchestrator agent** -- A meta-agent that runs via `ao start`, receives a system prompt about available commands, and can spawn/manage worker agents autonomously
8. **Session restore** -- Crashed agents can be revived: workspace recreation, new runtime, agent resume command support
9. **Multi-project support** -- Single config file manages multiple repos with per-project plugin overrides and reaction configs
10. **Mobile app** (React Native/Expo) -- Session monitoring, spawn, terminal access from mobile devices (7 screens, ~2,088 LOC)

### Configuration Features

11. **YAML config with Zod validation** -- `agent-orchestrator.yaml` with auto-derived defaults (session prefix, SCM, tracker)
12. **Reactions system** -- Configurable auto-responses: `ci-failed` (send fix instructions, 2 retries), `changes-requested` (forward comments, escalate after 30m), `approved-and-green` (notify or auto-merge), `agent-stuck` (10m threshold, urgent notify), `merge-conflicts` (auto-send rebase instructions)
13. **Notification routing by priority** -- Events classified as urgent/action/warning/info, each routed to configured channels
14. **Per-project agent rules** -- Inline `agentRules` or `agentRulesFile` injected into every agent prompt
15. **Symlinks and postCreate hooks** -- Symlink `.env`, `.claude` etc. into worktrees; run `pnpm install` after workspace creation

### Agent Integration Features

16. **Prompt delivery modes** -- "inline" (flag-based) or "post-launch" (send after agent starts, for agents that exit on inline prompts)
17. **JSONL-based activity detection** -- Reads agent's native session files (Claude Code JSONL, Codex logs) for accurate state without terminal parsing
18. **Cost tracking** -- Extracts input/output tokens and estimated USD cost from agent session data
19. **Agent session resume** -- `getRestoreCommand()` attempts to resume previous agent conversation
20. **Workspace hooks** -- `setupWorkspaceHooks()` configures agent-specific post-tool hooks for automatic metadata updates (e.g., writes `pr=<url>` when `gh pr create` runs)

### Dashboard Features

21. **Attention zones** -- Sessions grouped by urgency: merge-ready, needs-response, in-review, pending, working, done
22. **PR table** -- Shows CI status, review decision, unresolved comments, additions/deletions, merge readiness score
23. **Embedded terminal** -- xterm.js with WebSocket connection to tmux sessions, direct terminal access
24. **Dynamic favicon** -- Favicon changes based on session states (shows counts of attention-needed sessions)
25. **SSE real-time updates** -- Dashboard subscribes to Server-Sent Events for live session/PR state changes
26. **Session actions** -- Send message, kill, restore, merge PR directly from dashboard
27. **Rate limit handling** -- Graceful degradation with cached data when GitHub API is rate-limited

### Infrastructure Features

28. **Hash-based namespacing** -- Config path hashed (SHA-256, 12 chars) to prevent tmux/directory collisions across AO instances
29. **Atomic session ID reservation** -- Prevents concurrent spawn collisions via filesystem locks
30. **Pre-flight checks** -- Validates Node.js version, git, tmux, gh CLI, port availability before operations
31. **Config auto-generation** -- `ao start <url>` auto-detects language, package manager, default branch; generates config
32. **Auth-aware cloning** -- Tries `gh repo clone` (GitHub auth), falls back to SSH, then HTTPS for private repos

## What Users Like

**Evidence from stars (2,942) and fork count (307):** Strong community interest in the parallel agent orchestration space.

**Active development velocity:** 61 merged PRs, multiple PRs merged daily. The self-hosting dogfood approach (using AO to build AO) demonstrates real-world usage.

**Agent-agnostic design (from README and architecture):** Supporting Claude Code, Codex, Aider, and OpenCode via clean plugin interfaces is a significant differentiator. Users are not locked into one AI provider.

**One-command onboarding (PR #267):** `ao start https://github.com/org/repo` eliminates configuration friction -- auto-cloning, language detection, config generation. This is a strong UX win evidenced by rapid iteration (PRs #272-#275 all fixing edge cases in this flow).

**Reaction engine (from config and issues):** The automated CI-failure-retry and review-comment-forwarding loop is the core value proposition. Users configure it once and agents self-heal through multiple failure cycles.

**Comprehensive test suite:** 3,288 test cases with ~30K lines of test code shows engineering maturity.

**Self-building narrative:** The project's marketing angle -- "AI agents building their own orchestrator" -- generated social proof (demo video tweet linked from README).

## What Users Dislike / Struggle With

### Bugs and Reliability Issues

- **Issue #117**: Dashboard shows "CI failing" when a PR has zero CI checks. The `getCIChecks` fallback misinterprets an empty check list as failure. Unresolved.
- **Issue #146**: `ao session cleanup` removes sessions with open, unmerged PRs if they never transitioned past "starting" status. Orphans active work. Unresolved.
- **Issue #239**: Lifecycle manager never actually started in the CLI, causing a silent 5s spawn freeze and wrong agent plugin reported in status. Unresolved.
- **Issue #92**: `ao stop` logs "Dashboard stopped" even when no dashboard was running. Minor but indicates rough edges.
- **Issue #116**: TOCTOU race in terminal server port auto-detection. Unresolved.

### Complexity and Setup Friction

- **17K+ lines of TypeScript source** across 22 packages is substantial overhead for what is fundamentally a session coordinator. Compare to Automaton's single-bash-file approach.
- **Requires Node.js 20+, pnpm, tmux, git 2.25+, gh CLI** -- heavy prerequisite stack. Issue #264 requests Windows support (currently Unix-only due to tmux dependency).
- **SETUP.md is 17,798 bytes** -- the length of the setup guide itself signals complexity.

### Missing Features (Open Issues)

- **Issue #251**: No GitLab support (SCM or tracker). GitHub-only.
- **Issue #137**: No Jira tracker. GitHub Issues and Linear only.
- **Issue #171**: No Cline agent support.
- **Issue #175**: Dashboard not mobile-responsive (separate React Native app was built as workaround -- PR #266).
- **Issue #81**: No "Mission Control" live visualization -- the viral demo feature is still a wishlist item.
- **Issue #255**: No semantic merge -- when parallel agents edit different functions in the same file, git produces spurious conflicts. Major pain point for the core use case.

### Agent-Specific Gaps

- **Issues #159-163, #167, #176-184**: Massive backlog of Codex-specific issues (11 open) -- activity detection, session resume, metadata auto-update, binary resolution, approval modes. The Codex plugin is clearly the weakest integration.
- **Issue #257**: Fixed 5-second sleep before sending initial prompt to agents. Should poll for ready state instead.

### Architectural Concerns

- **Polling-based lifecycle** -- 30-second poll interval means state transitions can take up to 30s to detect. Not event-driven.
- **Flat file metadata** -- No database means no querying, no transactions, no concurrent write safety beyond filesystem semantics. The `reserveSessionId` function retries 10 times to handle races.
- **GitHub API rate limiting** -- The dashboard's PR enrichment hits GitHub API heavily. PR #276 added aggressive caching (60s default, 15s for pending CI) to mitigate, but this is a fundamental design tension.

## Good Ideas to Poach

### 1. Reaction Engine with Escalation
The reaction config pattern is excellent and directly applicable to Automaton:
```yaml
reactions:
  ci-failed:
    auto: true
    action: send-to-agent
    retries: 2
    escalateAfter: 2  # escalate to human after 2 failures
  changes-requested:
    auto: true
    action: send-to-agent
    escalateAfter: 30m  # escalate after 30 minutes
```
**Poach this:** Configurable auto-retry with escalation thresholds for CI failures and review comments. Automaton could implement this as a simple retry loop with timeout in bash.

### 2. Session Status State Machine
The 14-state lifecycle with typed transitions (`spawning -> working -> pr_open -> ci_failed -> ...`) provides clear observability. The `determineStatus()` function in `lifecycle-manager.ts` (lines 182-293) checks runtime liveness, agent activity, PR state, CI status, and review decision in a well-defined priority order.
**Poach this:** A simpler version -- even 5-6 states -- would make Automaton's pipeline status much clearer.

### 3. Attention Zones (Dashboard UX Pattern)
Grouping sessions into urgency-based zones (merge-ready, needs-response, in-review, working, done) is a superior UX to a flat list. The `getAttentionLevel()` function classifies sessions into actionable buckets.
**Poach this:** Even a CLI-based "attention zones" output would be valuable for Automaton's status command.

### 4. Layered Prompt Composition
The 3-layer prompt builder (`packages/core/src/prompt-builder.ts`) composes: (1) base agent instructions, (2) config-derived project context, (3) user rules. Each layer is independently testable and overridable.
**Poach this:** Automaton's spec-to-prompt pipeline could adopt this layered approach for composing agent instructions.

### 5. One-Command URL Onboarding
`ao start https://github.com/org/repo` handles: parse URL -> clone (with auth fallback) -> detect language/package manager -> generate config -> find free port -> start dashboard + orchestrator. Extremely low friction.
**Poach this:** A `automaton start <repo-url>` that auto-scaffolds the spec from repo analysis would be a strong onboarding feature.

### 6. Agent-Agnostic Plugin Interface
The `Agent` interface (`types.ts` lines 262-325) defines a clean contract: `getLaunchCommand()`, `getEnvironment()`, `detectActivity()`, `getActivityState()`, `getSessionInfo()`, `getRestoreCommand()`, `setupWorkspaceHooks()`. This allows swapping Claude Code for Codex with zero orchestration changes.
**Poach this:** Even without a formal plugin system, Automaton could define agent adapter functions with a consistent interface.

### 7. Orchestrator-as-Agent Pattern
The `spawnOrchestrator()` function creates a meta-agent that receives a comprehensive system prompt about available `ao` CLI commands and can autonomously spawn/manage workers. This is a powerful recursive pattern.
**Poach this:** Automaton could have a "coordinator mode" where the pipeline itself is an LLM conversation that decides what to build next.

### 8. Config-Driven Notification Routing
```yaml
notificationRouting:
  urgent: [desktop, slack]   # agent stuck, needs input
  action: [desktop, slack]   # PR ready to merge
  warning: [slack]           # auto-fix failed
  info: [slack]              # summary
```
**Poach this:** Priority-based notification routing so users only get pulled in for decisions that need human judgment.

## Ideas to Improve On

### 1. Complexity is the Enemy
AO is 24K+ lines of TypeScript across 22 packages with a build step, pnpm workspaces, and heavy Node.js dependency chain. Automaton's single-bash-file approach is fundamentally simpler and more portable. AO's complexity creates real costs:
- Setup guide is 17K+ bytes
- Requires Node 20+, pnpm, tmux, git 2.25+, gh CLI
- Build step required before dev server works
- 22 packages means 22 `package.json` files, 22 `tsconfig.json` files
**Improve:** Keep Automaton's zero-dependency, single-file simplicity. Implement the best AO features (reactions, state machine, status) as bash functions rather than TypeScript classes.

### 2. Polling is Slow
AO's 30-second polling interval for lifecycle checks means state transitions take up to 30 seconds to detect. This is especially bad for CI failures where quick retry matters.
**Improve:** Automaton could use filesystem watches (inotifywait), git hooks, or webhook receivers for instant state change detection instead of polling.

### 3. Flat File Metadata is Fragile
AO stores session state as `key=value` flat files with no locking, no schema evolution, and an atomic write workaround (`reserveSessionId` retries 10 times). Issue #238 was about metadata corruption bugs.
**Improve:** Automaton can use simpler state tracking (a single JSON file per pipeline run with flock-based locking, or even sqlite3 which is available on most systems).

### 4. Agent Integrations Are Shallow
Despite advertising 4 agent backends, the Codex plugin has 11 open issues (#159-184) for basic functionality like activity detection, session resume, and binary resolution. Aider and OpenCode plugins appear even less mature.
**Improve:** Automaton should deeply integrate with one agent first (Claude Code) and make that integration bulletproof before expanding to others. AO's breadth-over-depth approach left most integrations half-baked.

### 5. No Semantic Merge Strategy
Issue #255 identifies the core unsolved problem: parallel agents editing the same file create merge conflicts even when they touch different functions. AO has no solution -- it just flags the PR as "not mergeable."
**Improve:** Automaton could implement smart task decomposition that prevents file-level conflicts by assigning non-overlapping file scopes to parallel agents, or use tree-sitter-based merge strategies.

### 6. Dashboard is Over-Engineered for the Use Case
A full Next.js 15 app with React components, Tailwind CSS, WebSocket terminal emulation, SSE streaming, and a separate React Native mobile app is massive overhead for what could be a TUI or simple HTML page.
**Improve:** A lightweight ncurses/blessed TUI or even a static HTML dashboard with periodic refresh would serve 90% of use cases at 1% of the complexity.

### 7. No Spec-Driven Pipeline
AO orchestrates agents around *issues* (GitHub Issues, Linear tickets). There is no concept of a spec-to-code pipeline, architecture planning, or multi-stage build process. You point it at issue #123 and hope the agent figures out what to do.
**Improve:** This is Automaton's key differentiator. A structured spec -> plan -> implement -> test -> review pipeline with explicit stage gates is more reliable than "spawn agent on issue and pray."

### 8. GitHub API Dependency is a Bottleneck
The dashboard hammers the GitHub API for PR status, CI checks, review decisions, and merge readiness. PR #276 is entirely about cache staleness vs. API rate limits. This is a fundamental design tension.
**Improve:** Automaton could use `gh` CLI (which handles auth/caching) and local git state rather than API calls for status tracking. Git reflog + branch state + local CI results are all available without API calls.

### 9. No Cost Controls
AO tracks token costs per session but has no budget limits, cost caps, or alerts. A runaway agent can burn through API credits with no safeguard.
**Improve:** Automaton could implement per-task cost caps with automatic session termination when exceeded.

### 10. Security Model is Permissive by Default
The `agentConfig.permissions: skip` setting (which maps to `--dangerously-skip-permissions` for Claude Code) is the *default* in AO's Zod schema (line 56 of `config.ts`). The orchestrator agent always runs with skip permissions.
**Improve:** Default to restrictive permissions and require explicit opt-in for dangerous modes. Log all permission escalations.
