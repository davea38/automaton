# Competitive Analysis: Deer-Flow (bytedance/deer-flow)

## Overview

**DeerFlow** (Deep Exploration and Efficient Research Flow) is an open-source "super agent harness" by ByteDance that orchestrates sub-agents, memory, sandboxed execution, and extensible skills to handle complex, multi-step tasks ranging from deep research to code generation to slide deck creation.

| Metric | Value |
|--------|-------|
| **Primary Language** | Python (backend) + TypeScript/Next.js (frontend) |
| **Stars** | 23,730 |
| **Forks** | 2,815 |
| **License** | MIT |
| **Last Updated** | 2026-03-03 (actively maintained) |
| **Total LOC** | ~40,000 (14,923 Python + 20,450 TS/JS + 4,104 Skill Markdown) |
| **Version** | 2.0 (ground-up rewrite, shares no code with v1) |
| **Trending** | #1 on GitHub Trending (Feb 28, 2026) |

DeerFlow 2.0 is a complete rewrite. The v1 branch (`main-1.x`) was a Deep Research framework; v2 repositions as a general-purpose agent platform with sandboxed execution, sub-agent orchestration, persistent memory, and a skills system.

## Architecture & Structure

### High-Level Architecture

DeerFlow runs as a 4-service stack behind an nginx reverse proxy on port 2026:

1. **LangGraph Server** (port 2024) -- Agent orchestration via LangChain/LangGraph
2. **Gateway API** (port 8001) -- FastAPI service for models, skills, MCP, memory, artifacts, uploads
3. **Frontend** (port 3000) -- Next.js app with workspace UI, chat threads, artifact preview
4. **Nginx** (port 2026) -- Reverse proxy routing `/api/*` to Gateway, `/api/langgraph/*` to LangGraph

### Directory Structure

```
deer-flow/
  backend/
    src/
      agents/lead_agent/     # Main agent: agent.py, prompt.py
      agents/middlewares/     # 8 middlewares (clarification, memory, title, uploads, etc.)
      agents/memory/          # Long-term memory: updater.py, queue.py
      subagents/              # Sub-agent execution engine + builtins (general-purpose, bash)
      sandbox/                # Local + Docker sandbox providers with tool wrappers
      community/              # Integrations: Tavily, Jina AI, image search, Firecrawl, AIO sandbox
      gateway/                # FastAPI app with routers: models, mcp, memory, skills, artifacts, uploads
      mcp/                    # MCP client with OAuth support
      skills/                 # Skill loader + parser (SKILL.md files)
      tools/                  # Built-in tools: task, clarification, present_file, view_image
      models/                 # Model factory + patched DeepSeek wrapper
      config/                 # YAML-based config: app, models, sandbox, skills, summarization, etc.
      client.py               # Embedded Python client (no HTTP needed)
    tests/                    # 15+ test files
  frontend/
    src/
      app/                    # Next.js pages: workspace/chats, mock APIs
      components/
        ai-elements/          # 20+ components: canvas, chain-of-thought, message, plan, reasoning
        workspace/             # Chat UI: messages, artifacts, settings, code-editor, input-box
        landing/               # Marketing landing page
        ui/                    # ~40 UI primitives (shadcn-style)
      core/                   # API clients, i18n, MCP, memory, skills, threads, streaming
  skills/
    public/                   # 15 built-in skills (see Features)
    custom/                   # User-defined skills (SKILL.md format)
  docker/                     # docker-compose, nginx configs, provisioner Dockerfile
  scripts/                    # Setup and Docker helper scripts
```

### Key Technical Decisions

- **LangGraph + LangChain** as the agent framework (not a custom agent loop)
- **Middleware chain** pattern for the lead agent (`backend/src/agents/lead_agent/agent.py`): ThreadData -> Uploads -> Sandbox -> DanglingToolCall -> Summarization -> TodoList -> Title -> Memory -> ViewImage -> SubagentLimit -> Clarification
- **YAML-based configuration** (`config.yaml`) for models, tools, sandbox, skills, summarization, memory
- **Skills as Markdown** (`SKILL.md` files) with progressive loading -- only loaded when needed to preserve context window
- **Model-agnostic** -- works with OpenAI, Anthropic, Google, DeepSeek, Doubao, Moonshot via LangChain adapters
- **pnpm** for frontend, **uv** for Python backend dependency management

## Features

### Full Feature Catalog

#### Agent System
- **Lead agent** with configurable model, thinking mode, reasoning effort (`backend/src/agents/lead_agent/agent.py`)
- **Sub-agent orchestration** via `task` tool -- spawns parallel sub-agents with isolated contexts (`backend/src/subagents/executor.py`)
  - Two built-in sub-agent types: `general-purpose` and `bash`
  - Hard concurrency limit (default 3) with multi-batch execution across turns
  - Timeout support with configurable per-agent timeouts (`backend/src/subagents/config.py`)
- **Clarification system** -- agent asks for user clarification before proceeding on ambiguous requests (`backend/src/tools/builtins/clarification_tool.py`)
- **Plan mode** with TodoList middleware -- visual task tracking for complex multi-step work

#### Sandbox Execution
- **Three sandbox modes** (`config.yaml`):
  - Local execution (direct on host)
  - Docker container isolation (AIO Sandbox with auto-start)
  - Kubernetes-managed pods via provisioner service
- **Apple Container** support on macOS (auto-detected)
- **Virtual filesystem** mapping: `/mnt/user-data/{uploads,workspace,outputs}` (`backend/src/sandbox/tools.py`)
- **5 sandbox tools**: `bash`, `ls`, `read_file`, `write_file`, `str_replace`

#### Skills System
- **15 built-in skills** as Markdown workflow definitions (`skills/public/`):
  - `deep-research` -- systematic multi-angle web research methodology
  - `report-generation` -- not found in tree but referenced in README
  - `chart-visualization` -- 27 chart types via JS generation scripts
  - `data-analysis` -- Python-based data analysis with scripts
  - `ppt-generation` -- PowerPoint slide creation
  - `image-generation` -- AI image generation with templates
  - `video-generation` -- AI video generation
  - `podcast-generation` -- TTS-based podcast creation
  - `web-design-guidelines` -- frontend design patterns
  - `frontend-design` -- UI/UX design skill
  - `consulting-analysis` -- business consulting frameworks
  - `github-deep-research` -- GitHub repo analysis with API scripts
  - `skill-creator` -- meta-skill for creating new skills
  - `find-skills` -- discover and install community skills
  - `surprise-me` -- creative/random generation
  - `vercel-deploy-claimable` -- deploy web apps to Vercel
- **Custom skills** via `skills/custom/` directory with same SKILL.md format
- **Progressive loading** -- skills loaded only when task matches, preserving context window
- **Recursive nested skill loading** (PR #950)
- **Skill enable/disable** via `extensions_config.json` and frontend settings UI

#### MCP (Model Context Protocol) Integration
- **MCP server support** via `extensions_config.json` (`backend/src/mcp/client.py`)
- **Three transports**: stdio, SSE, HTTP
- **OAuth token flows**: `client_credentials` and `refresh_token` grant types
- **Frontend MCP configuration UI** (`frontend/src/components/workspace/settings/tool-settings-page.tsx`)

#### Memory System
- **Long-term persistent memory** across sessions (`backend/src/agents/memory/`)
- **Fact-based storage** with confidence thresholds (configurable `max_facts: 100`, `fact_confidence_threshold: 0.7`)
- **Memory injection** into system prompts (configurable max injection tokens)
- **Debounced updates** via queue (`debounce_seconds: 30`)
- **Per-agent memory** support (PR #957, in progress)
- **Frontend memory settings** page

#### Context Engineering
- **Summarization middleware** -- auto-summarizes when token/message thresholds are hit
  - Configurable triggers: token count, message count, fraction of max tokens
  - Configurable retention: keep N recent messages after summarization
- **Isolated sub-agent contexts** -- each sub-agent has its own context scope
- **Title generation** -- auto-generates conversation titles after first exchange

#### Frontend
- **Next.js workspace UI** with chat threads, artifact preview, settings
- **Artifact system** -- preview HTML, images, code, videos, markdown
- **Chain-of-thought visualization** (`frontend/src/components/ai-elements/chain-of-thought.tsx`)
- **Code editor** component (`frontend/src/components/workspace/code-editor.tsx`)
- **i18n** -- English and Chinese locales
- **BetterAuth** integration for authentication
- **Demo mode** with pre-built thread examples (14 demo threads with diverse outputs)
- **Landing page** with case studies, skill animations, community section

#### Embedded Client
- **DeerFlowClient** (`backend/src/client.py`) -- in-process Python client, no HTTP needed
- Streaming support via LangGraph SSE protocol
- Configuration and management APIs (list models, list skills, upload files)
- Gateway-aligned response schemas with CI conformance tests

#### DevOps
- **Docker Compose** setup with 4 services + optional provisioner
- **Makefile** with `make dev`, `make docker-start`, `make check`, `make install`
- **GitHub Actions** for backend unit tests
- **LangSmith** tracing support via metadata injection

## What Users Like

### Evidence from Stars and Trending
- 23,730 stars and 2,815 forks indicate very strong community interest
- Hit #1 on GitHub Trending (Feb 28, 2026) after v2 launch
- Active maintainer engagement in issues (WillemJiang, MagicCube responding quickly)

### Positive Signals from Issues/Comments
- **Skills extensibility** praised -- users excited about extending capabilities without code changes (Issue #819 comments: WillemJiang confirms skills can generate ECharts, reports, charts)
- **Ground-up v2 rewrite** generated excitement (Issue #824 comments: "DeerFlow 2.0 is really a great milestone!")
- **Multi-model support** appreciated -- users can use OpenAI, DeepSeek, Doubao, Gemini, Claude
- **Sandbox isolation** is a differentiator -- actual code execution environment, not just tool calling
- **Open source MIT license** from ByteDance (a major company backing) gives confidence
- **Docker deployment** simplifies setup (one-command `make docker-start`)

### Wish List Items (Issue #819) Show What Users Value
- Tool recall via RAG to dynamically load relevant tools (user haifeng9414)
- Section-by-section report generation for more detailed output (user jiaoqiyuan)
- History record viewing (user ponyioy -- implemented in v2)
- Inline citation links with hover preview (user jialudev)
- Background execution for long research tasks (user jiaoqiyuan)
- File upload support (user LiuAlex1109 -- implemented in v2)
- Long-form reports with ECharts and mixed media (user mythic-p)

## What Users Dislike / Struggle With

### Setup and Configuration Pain (Most Common Issue Category)
- **Issue #955**: `make dev` fails without first running `make install` -- docs gap
- **Issue #956**: Frontend model list configuration unclear for v2
- **Issue #882**: Missing `frontend/.env` creation in Quick Start
- **Issue #880**: Missing `git clone` step in Quick Start docs
- **Issue #921**: Windows line endings cause `bash\r` errors (`/usr/bin/env: 'bash\r': No such file or directory`)
- **Issue #817**: Custom port configuration causes frontend/backend connection failures
- **Issue #925**: `make docker-init` fails pulling sandbox image from Chinese registry
- **Issue #918**: Docker startup produces hydration errors

### Sandbox Issues
- **Issue #940**: File attachment button doesn't work -- files not found in `/mnt/user-data/uploads`
- **Issue #946**: Uploaded attachments not recognized by LLM
- **Issue #935**: Shell environment errors on macOS Docker (`/bin/zsh` not found -- fixed in PR #939)
- **Issue #928**: Bash tool configuration issues + uploaded file recognition failures
- **Issue #915**: No way to persistently install custom dependencies in sandbox containers

### Model and Agent Issues
- **Issue #891**: Switching models in config.yaml causes "Model not found" errors
- **Issue #951**: Google Gemini module import failures
- **Issue #907**: Question/answer mismatch (conversation session management bug)
- **Issue #899**: First message in new conversation doesn't appear
- **Issue #856**: Confusion about `enable_thinking` requirement (must be false for non-streaming?)
- **Issue #916**: No way to assign different models to different sub-agents

### Skills Issues
- **Issue #945**: Custom skills found but reported as "not found" and can't be used
- **Issue #949**: No support for hierarchical/nested skill structures (fixed in PR #950)
- **Issue #953**: No support for programmatic skills (only Markdown-described skills)

### Performance and UX
- **Issue #909**: Web UI frequently freezes/hangs
- **Issue #887**: Title generation blocks subsequent conversation (synchronous blocking after main response)
- **Issue #902**: 502 Bad Gateway errors (5 comments, persistent issue)

### Multi-User and Enterprise Gaps
- **Issue #890**: No multi-user support (user requests multi-user version)
- **Issue #933**: No RAG/knowledge base integration (user asks about RAGFlow integration)
- **Issue #879**: No IM integration (user wants Feishu/Lark integration)
- **Issue #959**: No PyPI package (can't install via pip)

## Good Ideas to Poach

### 1. Skills-as-Markdown Pattern
DeerFlow's skill system (`skills/public/*/SKILL.md`) is remarkably elegant. Each skill is a Markdown file with YAML frontmatter defining name and description, followed by a structured workflow document. Skills can reference scripts and templates in subdirectories. The agent loads them progressively -- only when the task matches.

**For Automaton**: Define pipeline stages or spec templates as Markdown files with frontmatter metadata. This makes the system extensible without code changes, and the progressive loading pattern keeps context windows lean.

### 2. Clarification-Before-Action Workflow
The `ClarificationMiddleware` (`backend/src/agents/middlewares/clarification_middleware.py`) and `ask_clarification` tool enforce a strict workflow: CLARIFY -> PLAN -> ACT. The agent is prompted to never start working until all ambiguities are resolved, with typed clarification categories (missing_info, ambiguous_requirement, approach_choice, risk_confirmation, suggestion).

**For Automaton**: Before executing a spec-to-code pipeline, implement a structured clarification pass that identifies missing information, ambiguous requirements, and risky operations. This prevents wasted compute on bad assumptions.

### 3. Sub-Agent Decomposition with Batched Parallelism
The `task` tool (`backend/src/tools/builtins/task_tool.py`) implements a sophisticated pattern: the lead agent decomposes tasks into parallel sub-tasks, launches up to N sub-agents per turn (hard limit enforced by `SubagentLimitMiddleware`), and synthesizes results across batches. Sub-agents inherit sandbox state but get isolated contexts.

**For Automaton**: For multi-file or multi-module code generation, decompose specs into parallel generation units. Process them in batches with a configurable concurrency limit to avoid overwhelming the LLM context.

### 4. Virtual Filesystem Abstraction
The sandbox tools (`backend/src/sandbox/tools.py`) use a virtual path system (`/mnt/user-data/{uploads,workspace,outputs}`) that maps to actual paths depending on sandbox mode (local vs Docker). The `replace_virtual_path` function transparently handles the translation.

**For Automaton**: Abstract file paths in specs so the pipeline can run identically in local mode, Docker, or CI environments. Define virtual paths like `/workspace/src`, `/workspace/output` that get resolved at runtime.

### 5. Context Summarization with Configurable Triggers
The `SummarizationMiddleware` automatically compresses conversation history when token/message thresholds are hit, retaining only the most recent N messages. Triggers can be token count, message count, or fraction-based.

**For Automaton**: For long-running pipelines that accumulate context, implement automatic summarization of completed stages. Keep only the most recent stage's full context plus summaries of prior stages.

### 6. Embedded Python Client
The `DeerFlowClient` (`backend/src/client.py`) provides in-process access to the full agent system without requiring HTTP services. This enables programmatic use, testing, and integration into other tools.

**For Automaton**: Consider providing both a CLI interface and an embeddable Python/bash function library so the pipeline can be invoked programmatically from other scripts.

### 7. Middleware Chain Architecture
The agent uses a composable middleware chain (11 middlewares) where each middleware handles one concern: thread data, uploads, sandbox initialization, summarization, memory injection, title generation, etc. Middleware ordering matters and is documented in comments.

**For Automaton**: Structure pipeline stages as composable middleware/hooks that can be reordered, enabled/disabled, or replaced. Document the ordering constraints.

### 8. YAML-Driven Configuration
Everything is configurable via `config.yaml` -- models, tools, tool groups, sandbox mode, summarization triggers, memory settings, skill paths. Environment variables can be referenced with `$VAR_NAME` syntax.

**For Automaton**: Use a single configuration file (YAML or similar) with environment variable interpolation for all pipeline settings rather than hardcoded values.

## Ideas to Improve On

### 1. Setup Complexity is a Major Pain Point
DeerFlow requires Node.js 22+, pnpm, uv, nginx, Docker, and a YAML config file just to start. Issues #955, #882, #880, #921, #925, #918 all stem from setup failures. The `make check` command lists prerequisites but doesn't install them.

**Automaton advantage**: As a single bash file, Automaton has zero setup beyond bash itself. No Docker, no Node.js, no package managers. This is a massive differentiator -- emphasize the single-file, zero-dependency nature.

### 2. 4-Service Architecture is Overkill for Many Use Cases
Running nginx + LangGraph + Gateway + Frontend for a code generation task is heavy. The `DeerFlowClient` was added (PR #931) precisely because users wanted in-process access without the full stack. Even then, `uv`, `langchain`, and `langgraph` are required.

**Automaton advantage**: A single-file pipeline that shells out to LLM APIs directly is fundamentally simpler. No service orchestration, no reverse proxy, no WebSocket connections.

### 3. Skills Are Markdown-Only (No Programmatic Skills)
Issue #953 explicitly asks for programmatic skills (Python scripts as skills, not just Markdown descriptions). While skills can *reference* scripts in subdirectories, the skill definition itself must be a Markdown file, and the agent must interpret it. This is an inherent limitation of the "skills as prompts" pattern.

**Automaton advantage**: Specs can contain actual executable steps, not just descriptions for an LLM to interpret. Direct bash execution means skills/stages are deterministic code, not probabilistic prompt interpretation.

### 4. No Multi-User or Team Support
Issue #890 requests multi-user support. DeerFlow is currently single-user only -- one memory file, one config, no authentication beyond basic BetterAuth. There's no concept of team projects, shared memories, or role-based access.

**Automaton advantage**: If Automaton targets developer workflows, it can operate in a git-centric model where specs are versioned, shared, and collaborated on via standard git workflows rather than requiring a dedicated multi-user system.

### 5. Heavy Dependency on LangChain/LangGraph
DeerFlow is deeply coupled to LangChain and LangGraph. The agent, tools, middleware, and streaming all use LangChain primitives. This means:
- Breaking changes in LangChain/LangGraph directly affect DeerFlow
- Users must understand LangChain concepts to extend or debug
- Model support depends on LangChain adapter availability

**Automaton advantage**: Direct API calls to LLM providers (via curl/httpie in bash) have zero framework dependency. New models can be supported by adding an API endpoint, not waiting for a LangChain adapter.

### 6. Chinese-Centric Documentation and Community
Many issues are in Chinese (#956, #955, #949, #946, #945, #933, #928, #916, #915, #909, #907, #899, #891, #890, #887, #879, #856, #847, #845, #825, #822, #819, #817, #815, #808, #805, #803, #800). While understandable given ByteDance's origin, this creates a barrier for non-Chinese-speaking developers.

**Automaton advantage**: English-first documentation with clear, concise single-file design makes the project more globally accessible.

### 7. Synchronous Title Generation Blocks UX
Issue #887 reports that title generation after the first exchange blocks subsequent conversation, causing noticeable lag. This is a symptom of the middleware chain running synchronously.

**Automaton advantage**: A pipeline orchestrator doesn't need a real-time chat UI, so blocking concerns are irrelevant. But the lesson is: keep non-critical operations (logging, metadata) asynchronous and never block the critical path.

### 8. No Deterministic Execution
DeerFlow relies on LLM judgment for every step -- which tools to call, which skills to load, how to decompose tasks. The `task` tool's polling loop (5-second intervals, `backend/src/tools/builtins/task_tool.py` line 178) and the sub-agent's unbounded execution make it impossible to predict runtime or resource consumption.

**Automaton advantage**: A spec-driven pipeline can define deterministic stages with predictable execution. The LLM is consulted for code generation, not for pipeline orchestration. This makes the system auditable and reproducible.

### 9. No Cost Control or Token Budgeting
There's no mechanism to set a token budget or cost limit for a task. A deep research task can spawn multiple sub-agents, each making multiple LLM calls with full context windows. The only controls are `max_turns` per sub-agent and a timeout.

**Automaton advantage**: A pipeline orchestrator can track token usage per stage and abort or switch to cheaper models when approaching a budget. Define cost limits in the spec itself.

### 10. Frontend/Backend Coupling
The frontend is tightly coupled to the backend's API and streaming protocol. You can't easily use DeerFlow's agent system with a different UI, and you can't easily use the frontend with a different agent backend. The embedded client (PR #931) partially addresses this but is Python-only.

**Automaton advantage**: A CLI-first tool with plain text output (Markdown, JSON) is inherently UI-agnostic. Output can be piped to any consumer.
