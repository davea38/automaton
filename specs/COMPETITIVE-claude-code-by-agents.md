# Competitive Analysis: Claude Code by Agents (baryhuang/claude-code-by-agents)

## Overview

**What it is:** A desktop app (Electron) and web UI for multi-agent Claude Code orchestration. Users coordinate local and remote Claude Code agents through @mentions in a chat interface. Forked originally from [sugyan/claude-code-webui](https://github.com/sugyan/claude-code-webui), it has diverged significantly to add multi-agent workflows, an orchestration layer, and a native macOS SwiftUI companion app.

- **Primary Language:** TypeScript (17,580 LOC), with Swift (3,982 LOC for macOS native app), JavaScript (1,808 LOC for Electron shell), CSS (918 LOC)
- **Total LOC (excluding lock files, binary assets):** ~24,500
- **Stars:** 788
- **Forks:** 68
- **License:** MIT
- **Created:** 2025-07-18
- **Last Updated:** 2026-03-03 (actively maintained)
- **Latest Release:** v0.1.46

## Architecture & Structure

### High-Level Architecture

```
Electron Shell (electron/main.js)
  |
  +-- Frontend (React/Vite/Tailwind) -- localhost:3000
  |     src/components/native/  -- AgentHubPage, AgentDetailView, Sidebar
  |     src/hooks/              -- useChatState, useClaudeStreaming, useAgentConfig
  |     src/utils/              -- message conversion, streaming debug
  |
  +-- Backend (Hono + Node/Deno) -- localhost:8080
  |     handlers/               -- chat.ts, multiAgentChat.ts, abort.ts, histories.ts
  |     providers/              -- registry.ts, claude-code.ts, openai.ts, anthropic.ts
  |     history/                -- conversationLoader.ts, parser.ts, pathUtils.ts
  |     auth/                   -- claude-auth-utils.ts
  |     swagger/                -- config.ts (API docs)
  |
  +-- ClaudeAgentHub/ (native macOS SwiftUI app, separate target)
        Models/                 -- Agent.swift, Project.swift, ChatMessage.swift
        ViewModels/             -- ChatViewModel.swift, AgentHubViewModel.swift
        Views/                  -- ChatView.swift, AgentHubView.swift, AgentCardView.swift
        Services/               -- APIService.swift, ClaudeStreamingService.swift
```

### Key Files

| File | Purpose | LOC |
|------|---------|-----|
| `backend/handlers/chat.ts` | Core chat handler: routes to local Claude SDK, remote agent HTTP, or orchestrator | 785 |
| `backend/handlers/multiAgentChat.ts` | Multi-agent chat with provider abstraction, screen capture, orchestration | 378 |
| `backend/providers/registry.ts` | Provider registry pattern: OpenAI, Claude Code, Anthropic providers | 140 |
| `backend/app.ts` | Hono app with all REST routes, Swagger docs, CORS, static serving | 622 |
| `electron/main.js` | Electron shell: window management, OAuth PKCE flow, IPC storage handlers | 689 |
| `frontend/src/components/native/AgentHubPage.tsx` | Main entry page: agent grid, sidebar, chat routing | 805 |
| `frontend/src/components/native/AgentDetailView.tsx` | Per-agent detail view with chat and history tabs | 1,174 |
| `frontend/src/hooks/chat/useChatState.ts` | React state management for multi-agent sessions | 249 |
| `frontend/src/hooks/streaming/useStreamParser.ts` | NDJSON stream parser for Claude SDK messages | 320 |
| `shared/types.ts` | Shared TypeScript types between frontend and backend | 85 |
| `auth/claude-oauth-service.ts` | OAuth service for Claude authentication | 970 |

### Tech Stack

- **Frontend:** React 18, Vite, Tailwind CSS, React Router (HashRouter)
- **Backend:** Hono (lightweight web framework), runs on both Node.js and Deno
- **Desktop:** Electron 37, electron-builder for packaging
- **Native macOS:** SwiftUI (separate companion app, `ClaudeAgentHub/`)
- **AI SDKs:** `@anthropic-ai/claude-code` v1.0.51 (primary), `@anthropic-ai/sdk` (orchestrator), `openai` (UX designer agent)
- **Auth:** OAuth 2.0 with PKCE (Claude AI OAuth)
- **API Docs:** Swagger/OpenAPI via swagger-jsdoc
- **Testing:** Vitest (backend), Playwright (frontend E2E)
- **CI/CD:** GitHub Actions with tagpr for automatic releases, Lefthook for pre-commit hooks
- **Build targets:** macOS DMG (universal), Windows portable exe + zip, Linux AppImage (x64 + arm64)

## Features

### Core Features

1. **@agent-name Mentions** -- Direct message routing to specific agents via `@agent-name` syntax in chat input. Single mentions go directly via HTTP; no orchestration overhead.

2. **Multi-Agent Orchestration** -- When multiple agents are @mentioned, an orchestrator (Claude Sonnet via Anthropic API) creates a structured execution plan using the `orchestrate_execution` tool. Plans include step IDs, agent assignments, messages with file paths, output files, and dependency chains.

3. **Local + Remote Agents** -- Agents can be local (localhost:808x) or remote (any HTTP endpoint). Each agent runs its own Claude Code instance with its own working directory and file system access. Configuration via Settings UI.

4. **Multi-Provider Support** -- Provider registry pattern supports three backends:
   - `ClaudeCodeProvider` -- wraps `@anthropic-ai/claude-code` SDK, uses `bypassPermissions` mode
   - `OpenAIProvider` -- GPT-4o with vision, hardcoded as "UX Designer" role
   - `AnthropicProvider` -- direct Anthropic API for orchestrator coordination

5. **No API Key Required (OAuth)** -- Uses Claude CLI OAuth authentication (PKCE flow) via the user's existing Claude subscription. The Electron app opens the browser for OAuth, user pastes back the authorization code.

6. **Streaming Responses** -- NDJSON streaming from backend to frontend. Includes anti-buffering headers (`X-Accel-Buffering: no`, `X-Proxy-Buffering: no`), periodic flush markers, and connection acknowledgments to prevent 504 timeouts.

7. **Conversation History** -- Loads conversation history from Claude Code's local JSONL files. Supports both local project history and remote agent history via a 3-endpoint API pattern (`/api/agent-projects`, `/api/agent-histories/:project`, `/api/agent-conversations/:project/:session`).

8. **Session Continuity** -- Uses Claude Code SDK's `resume` option with session IDs to maintain conversation context across messages.

9. **Request Abort** -- Tracks `AbortController` instances per request ID. POST `/api/abort/:requestId` cancels in-flight requests.

10. **Screenshot Capture** -- Multi-agent chat supports `capture_screen` commands via `@agent-name capture_screen`. Uses `globalImageHandler` for capturing and passing image data between agents.

11. **Dynamic Agent Configuration** -- Add/remove/configure agents via the web UI Settings modal. Stored in Electron userData or localStorage.

12. **Swagger API Documentation** -- Full OpenAPI 3.0 spec auto-generated from JSDoc annotations, served at `/api-docs` with Swagger UI.

13. **Cross-Platform Desktop App** -- Electron app with macOS-native styling (hidden title bar, traffic lights), plus a separate native SwiftUI macOS app (`ClaudeAgentHub/`) with MVVM architecture.

14. **File-Based Inter-Agent Communication** -- Orchestrator tells agents to write results to `/tmp/stepN_results.txt` and instructs subsequent agents to read from those files.

### Secondary Features

15. **Dark Theme** -- Default dark theme matching Claude Desktop (`#1a1d1a` background)
16. **Agent Hub Grid** -- Card-based grid layout showing all configured agents with status indicators
17. **Configurable Enter Behavior** -- Toggle between Enter-to-send and Shift+Enter-to-send
18. **Project Selector** -- Browse and select working directory projects
19. **Health Check Endpoint** -- `GET /api/health` returns status, timestamp, version
20. **AWS Lambda Support** -- `backend/lambda.ts` and `backend/template.yml` (SAM) for serverless deployment
21. **Demo Video Recording** -- CI pipeline records Playwright demo videos and attaches them to releases

## What Users Like

### Evidence from Stars and Engagement

- **788 stars** in ~8 months indicates strong interest in the multi-agent Claude Code orchestration space
- **68 forks** suggest active community experimentation
- The project has attracted external contributors (e.g., `@axisSN01` filed issue #8 on parallel task coordination, `@Xinxin-Ma` contributed a backend bug fix PR #39)

### Positive Signals from Issues

- **Issue #37** (Dev workflow documentation): A user (`@rinormaloku`) called out that the project is "already in the direction that I was planning" for defining agents, tools, and proper protocols -- indicating the vision resonates.
- **Issue #33** (Adopt Claude Code sub-agents): Active design discussion between maintainer and Claude bot, showing thoughtful product evolution. The maintainer pushes back on over-engineering: "you overcomplicated it... We should only talk about User experience and use cases."
- **Issue #20** (Multi-agent UX + Figma + Claude Code): Ambitious vision for heterogeneous agent coordination (ChatGPT for UX, Figma for design, Claude for implementation).
- **Issue #10**: Users want a canvas showing git change diffs -- "That's pretty much replace my need for cursor (only to see diff)."

### Technical Strengths Users Appreciate

- **No API key required** -- leveraging Claude subscription via OAuth is a significant friction reducer
- **Cross-platform binaries** -- pre-built downloads for Linux, macOS, Windows
- **Forked from a working base** -- `sugyan/claude-code-webui` provided a proven starting point

## What Users Dislike / Struggle With

### Setup and Distribution Issues

- **Issue #57** (OPEN): "Cant open the agent room in mac" -- screenshot shows a blank/broken UI. No resolution.
- **Issue #38** (OPEN): "can not download binary linux distr" -- Linux and Windows binaries were missing from releases. Comment from `@jason-curtis`: "the windows distribution also doesn't appear in the releases."
- **Issue #37** (OPEN): Developer found that messages go to `https://api.claudecode.run` and fail with CORS. The dev workflow documentation is insufficient -- "how do I define such an agent and start it up?"

### Feature Gaps

- **Issue #8** (OPEN): "No support for parallel tasks coordination" -- "The entire orchestration is always built sequentially, and this is a significant bottleneck." User `@axisSN01` requests parallel branch execution with dependency graphs.
- **Issue #36** (OPEN): "How to use tools?" -- User confused about how to define agents, tools, and protocols. Suggests the UX for agent/tool configuration is not self-explanatory.
- **Issue #5** (OPEN): "Validate endpoint on adding new agent" -- No validation that an agent endpoint is reachable before allowing configuration.
- **Issue #12** (OPEN): "How to install the backend service easiest?" -- Backend requires separate setup, which is a pain point. Discussion of creating installers, npm packages, or macOS services.
- **Issue #13** (OPEN): "Implement pro/subscription mode" -- No billing/subscription management.
- **Issue #11** (OPEN): "Should there be a web version that only supports remote agents?" -- Desktop-only is a limitation.

### Architecture Concerns

- **Issue #31** (OPEN): Suggestion to spin off the backend as a separate "Remote Claude Code" service with OpenAI-compatible API interface.
- **Issue #33**: Design tension between Claude Code sub-agents (SDK-native) vs. the current HTTP-based agent routing. Resource isolation (different agents accessing different local resources like browsers, files) adds complexity.

### Quality Issues

- The `package.json` version is stuck at `0.0.7` while the backend is at `0.1.46` -- version confusion.
- Debug logging is verbose with `console.debug` everywhere, including in production code paths.
- The orchestrator has hardcoded fallback agent names (`readymojo-admin`, `readymojo-api`, `readymojo-web`, `peakmojo-kit`) that leak internal project names.
- OAuth flow requires manual code pasting (no redirect URI callback server), which is a clunky UX.
- The `.env` file is committed to the repository (contains API configuration).

## Good Ideas to Poach

### 1. @Mention-Based Agent Routing
The `@agent-name` pattern for directing messages to specific agents is intuitive and low-friction. Automaton could adopt a similar pattern in spec files to target specific pipeline stages or tools: `@lint`, `@test`, `@deploy`.

**Relevant code:** `backend/handlers/chat.ts` lines 14-45 (`shouldUseOrchestrator` function) and lines 686-744 (routing logic).

### 2. Provider Registry Pattern
The `ProviderRegistry` class (`backend/providers/registry.ts`) cleanly abstracts multiple AI backends (Claude Code, OpenAI, Anthropic) behind a common `AgentProvider` interface. Each provider implements `executeChat()` as an `AsyncGenerator<ProviderResponse>`. Automaton could adopt this pattern to support pluggable LLM backends.

**Relevant code:** `backend/providers/types.ts`, `backend/providers/registry.ts`.

### 3. File-Based Inter-Agent Communication
The orchestrator's approach of telling agents to write results to `/tmp/stepN_results.txt` and having subsequent agents read from those files is dead simple and suits Automaton's bash-file philosophy perfectly. No databases, no message queues -- just files.

**Relevant code:** `backend/handlers/chat.ts` lines 260-321 (orchestrator tool definition with `output_file` and `dependencies` fields).

### 4. Structured Execution Plans
The `orchestrate_execution` tool schema forces the LLM to produce structured plans with step IDs, agent assignments, messages, output files, and dependency arrays. This is a clean pattern for decomposing complex tasks.

**Relevant code:** `backend/handlers/chat.ts` lines 260-305 (tool schema definition).

### 5. Request Abort Infrastructure
The `requestAbortControllers` Map pattern for tracking and cancelling in-flight requests is simple and effective. Each request gets an `AbortController` keyed by `requestId`, and a dedicated endpoint (`POST /api/abort/:requestId`) triggers cancellation.

**Relevant code:** `backend/handlers/chat.ts` lines 67-71, `backend/handlers/abort.ts`.

### 6. NDJSON Streaming with Anti-Buffering
The combination of NDJSON streaming, connection acknowledgment messages, periodic flush markers, and comprehensive anti-proxy-buffering headers is well-engineered for real-world deployment behind proxies.

**Relevant code:** `backend/handlers/chat.ts` lines 663-784, `STREAMING_DEPLOYMENT.md`.

### 7. Conversation History from Claude Code JSONL Files
Reading conversation history directly from Claude Code's internal JSONL storage files is clever -- it means the UI can show past conversations without maintaining its own database.

**Relevant code:** `backend/history/conversationLoader.ts`, `backend/history/parser.ts`.

### 8. Swagger/OpenAPI Auto-Documentation
JSDoc-annotated route handlers that auto-generate Swagger UI at `/api-docs` is good developer experience. Automaton could adopt this for any HTTP interfaces it exposes.

**Relevant code:** `backend/app.ts` lines 96-567, `backend/swagger/config.ts`.

## Ideas to Improve On

### 1. Sequential-Only Orchestration
The orchestrator creates purely sequential execution plans -- step 1 finishes before step 2 starts. Issue #8 correctly identifies this as a major bottleneck. Automaton could implement a proper DAG-based execution engine where independent steps run in parallel, with `wait` semantics for dependency edges. Bash's `&` and `wait` make this trivial.

### 2. Overcomplicated Setup
The project requires: (a) clone repo, (b) install frontend deps, (c) install backend deps, (d) start backend on one port, (e) start frontend on another port, (f) optionally run Electron. Automaton's single-bash-file approach is inherently simpler. One file, one command, zero setup.

### 3. No Spec-Driven Workflow
The orchestrator generates ad-hoc plans at runtime with no way to save, version, review, or replay them. Automaton's spec-file approach is superior: plans are human-readable, version-controlled, and repeatable. The execution plan should be a first-class artifact, not an ephemeral LLM output.

### 4. Weak Error Recovery
When a step fails in the orchestrator, there is no retry logic, no fallback, and no partial-result handling. The entire workflow fails. Automaton could implement step-level retry with exponential backoff, checkpoint/resume from last successful step, and graceful degradation.

### 5. No Cost Tracking or Budget Controls
Despite using multiple LLM providers (Claude, OpenAI, Anthropic API), there is no token counting, cost estimation, or budget limits. Issue #13 requests subscription management. Automaton could track token usage per step and enforce configurable budgets.

### 6. Hardcoded Agent Roles
The `OpenAIProvider` is hardcoded as a "UX designer and design critic" (see `backend/providers/openai.ts` lines 43-53). Agent roles should be configurable, not baked into provider code. Automaton's spec-based approach naturally separates role definitions from execution logic.

### 7. Security: bypassPermissions Mode
The Claude Code provider runs with `permissionMode: "bypassPermissions"` (see `backend/providers/claude-code.ts` line 103 and `backend/handlers/chat.ts` line 563). This means the agent can execute any tool without user approval -- a security concern for remote agents. Automaton should implement explicit permission scoping per pipeline stage.

### 8. Fragmented State Management
Chat state is split across React `useState` hooks (`useChatState.ts`), Electron IPC storage (`electron/storage.js`), localStorage fallback, and Claude Code's internal JSONL files. There is no single source of truth. Automaton benefits from bash's natural approach: state is files on disk, easily inspected and debugged.

### 9. No Validation or Testing of Agent Endpoints
Issue #5 requests endpoint validation before configuration, and it is still open. The system happily accepts invalid endpoints and only fails at runtime. Automaton should validate all external dependencies (endpoints, tools, file paths) before execution begins -- a "preflight check" phase.

### 10. Branding Confusion
Multiple PRs (#58-#61) attempted to rebrand from "Agentrooms" to "Claude Ops-Deck by Axiom-Labs" but were all closed without merging. The codebase still has references to "ReadyMojo" agents, "sugyan" as author, and inconsistent naming. This signals organizational instability. Automaton should maintain clear, consistent branding from day one.

### 11. No Deterministic Replay
Since the orchestrator generates plans via LLM at runtime, the same input can produce different plans on different runs. Automaton's spec files provide deterministic, reproducible execution -- the same spec always produces the same pipeline.

### 12. Missing Observability
No structured logging, no execution traces, no timing metrics for individual steps. The only debugging tool is setting `debugMode: true` which dumps verbose `console.debug` output. Automaton should produce structured execution logs with timestamps, durations, token counts, and success/failure status for each step.
