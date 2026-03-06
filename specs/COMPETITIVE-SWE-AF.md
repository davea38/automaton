# Competitive Analysis: SWE-AF (Agent-Field/SWE-AF)

## Overview

**SWE-AF** ("swee-AF") is an autonomous software engineering team runtime built on the [AgentField](https://github.com/Agent-Field/agentfield) control plane. It transforms a natural-language goal into verified, merged code with a draft GitHub PR via a single API call. The project orchestrates fleets of 400-500+ specialized AI agent invocations across planning, coding, review, QA, and verification phases.

| Metric | Value |
|---|---|
| **Primary Language** | Python (3.12+) |
| **Core Package LOC** | ~13,625 lines (`swe_af/` package only) |
| **Total Repo LOC** | ~84,872 lines (including examples, tests, docs, configs) |
| **Stars** | 272 |
| **Forks** | 41 |
| **License** | Apache 2.0 |
| **Last Activity** | 2026-03-03 (actively maintained) |
| **Initial Release** | 2026-02-16 (v0.1.0) |
| **Status** | Public Beta |
| **Homepage** | https://agentfield.ai/ |

The project is very young (about 2 weeks old as of analysis date) but has accumulated meaningful traction quickly.

## Architecture & Structure

### Tech Stack

- **Language**: Python 3.12+
- **Framework**: Built on `agentfield` (their own agent orchestration platform) for node registration, async execution, DID/VC governance
- **AI Providers**: Claude (via `claude-agent-sdk`), OpenCode (OpenRouter/OpenAI/Google), Codex (OpenAI)
- **Data Validation**: Pydantic v2 for all schemas
- **Async**: `asyncio` throughout for parallel execution
- **Deployment**: Docker Compose, Railway one-click deploy
- **Git**: Heavy use of git worktrees for agent isolation
- **CI**: GitHub Actions (`ci.yml`, `cla.yml`)
- **Testing**: pytest + pytest-asyncio with mocked AI providers

### Key Directory Structure

```
swe_af/
  app.py                          (1,092 LOC) - Main entry: build(), plan(), execute(), resume_build()
  __main__.py                     (5 LOC) - CLI entry point

  execution/
    dag_executor.py               (1,792 LOC) - Core DAG execution loop with self-healing replanning
    coding_loop.py                (886 LOC) - Inner loop: coder -> reviewer/QA -> synthesizer
    schemas.py                    (878 LOC) - All Pydantic models (DAGState, BuildConfig, IssueResult, etc.)
    dag_utils.py                  (173 LOC) - DAG mutation helpers (apply_replan, find_downstream)
    envelope.py                   (62 LOC) - Result unwrapping

  reasoners/
    pipeline.py                   (404 LOC) - Planning chain: PM -> Architect -> Tech Lead -> Sprint Planner
    execution_agents.py           (1,490 LOC) - All 22 agent reasoners (coder, qa, reviewer, merger, etc.)
    schemas.py                    (103 LOC) - PRD, Architecture, PlannedIssue schemas

  agent_ai/
    client.py                     (86 LOC) - Provider-agnostic AgentAI facade
    factory.py                    (77 LOC) - Provider factory (Claude, Codex, OpenCode)
    providers/claude/client.py    (586 LOC) - Claude provider implementation
    providers/opencode/client.py  (432 LOC) - OpenCode provider
    providers/codex/client.py     (364 LOC) - Codex provider

  prompts/                        (~2,600 LOC total) - 15 prompt modules for each agent role
    product_manager.py, architect.py, coder.py, code_reviewer.py,
    qa.py, qa_synthesizer.py, sprint_planner.py, tech_lead.py,
    merger.py, verifier.py, replanner.py, issue_advisor.py,
    issue_writer.py, integration_tester.py, fix_generator.py, etc.

  fast/
    app.py                        (308 LOC) - swe-fast: lightweight speed-optimized build agent
    planner.py                    (139 LOC) - Single-pass flat task decomposition
    executor.py                   (115 LOC) - Sequential task executor
    verifier.py                   (79 LOC) - Single-pass verification
    schemas.py                    (169 LOC) - FastBuild config/result schemas

tests/                            (~45 test files) - Comprehensive mocked-AI functional tests
docs/
  ARCHITECTURE.md                 - Deep architectural documentation (8 design patterns)
  SKILL.md                        - AgentField skill definition for tool-use agents
  CONTRIBUTING.md                 - Contribution guide
examples/
  agent-comparison/               - Benchmark artifacts: SWE-AF vs Claude Code vs Codex
  llm-rust-python-compiler-sonnet/ - Showcase: autonomously-built Rust Python compiler
  diagrams/                       - Showcase: autonomously-built diagram tool
  pyrust/                         - Showcase: another autonomous Rust build
```

### Architectural Patterns (8 Documented)

1. **Hierarchical Escalation Control** -- Three nested loops: inner (coder retry), middle (issue advisor), outer (replanner)
2. **Structured Concurrency with Barrier Synchronization** -- Parallel execution within levels, 10-step gate between levels
3. **Agent Isolation with Semantic Reconciliation** -- Git worktrees per issue, AI-powered merge
4. **Graceful Degradation with Explicit Incompleteness** -- Typed/severity-rated debt tracking, never silent failures
5. **Runtime Plan Mutation** -- DAG restructuring mid-execution via replanner
6. **Durable Execution & Checkpoint Recovery** -- Full DAGState serialization at every boundary, `resume_build()`
7. **Risk-Proportional Resource Allocation** -- 2-call default path vs 4-call flagged path based on sprint planner risk assessment
8. **Cross-Agent Knowledge Propagation** -- Shared memory for conventions, failure patterns, bug patterns, interfaces

### Agent Catalog (22 Agents)

**Planning (5)**: Product Manager, Architect, Tech Lead, Sprint Planner, Issue Writer
**Execution (7)**: Coder, QA, Code Reviewer, QA Synthesizer, Retry Advisor, Issue Advisor, Replanner
**Git & Merge (5)**: Git Init, Workspace Setup, Merger, Integration Tester, Workspace Cleanup
**Verification (4)**: Verifier, Fix Generator, Repo Finalizer, GitHub PR Creator

## Features

### Core Pipeline

- **One-call DX**: Single `curl` POST triggers an entire plan-build-verify-PR cycle
- **Goal-to-PR pipeline**: Natural language goal -> PRD -> Architecture -> Issue DAG -> Code -> Tests -> Review -> Merge -> Verify -> Draft PR
- **Async execution API**: Returns `execution_id` immediately; poll for status
- **Resume after crash**: `resume_build()` loads checkpoint, continues from exact failure point

### Multi-Model / Multi-Provider

- **Two runtimes**: `claude_code` (Anthropic SDK) and `open_code` (OpenCode CLI supporting OpenRouter, OpenAI, Google)
- **Per-role model assignment**: 16 role keys (`pm`, `architect`, `coder`, `qa`, `code_reviewer`, `verifier`, etc.) each independently configurable
- **Model resolution chain**: `runtime defaults` < `models.default` < `models.<role>`
- **Codex provider**: Also has a Codex/OpenAI provider implementation

### Multi-Repository Support

- **Multi-repo builds**: Orchestrate coordinated changes across multiple repos in a single build
- **Repo roles**: `primary` (main app, failures block) and `dependency` (libraries, failures captured but non-blocking)
- **Sparse checkout**: Optional `sparse_paths` per repo for partial cloning
- **Per-repo PRs**: Creates separate draft PRs for each repo

### Self-Healing & Adaptation

- **Three nested control loops**: Inner (max 5 coding iterations), Middle (max 2 advisor invocations), Outer (max 2 replans)
- **Issue Advisor with 5 actions**: `RETRY_MODIFIED`, `RETRY_APPROACH`, `SPLIT`, `ACCEPT_WITH_DEBT`, `ESCALATE_TO_REPLAN`
- **Replanner with 4 actions**: `CONTINUE`, `MODIFY_DAG`, `REDUCE_SCOPE`, `ABORT`
- **Stuck loop detection**: Both synthesizer-based (flagged path) and history-based (default path) stuck detection
- **Graceful crash fallback**: If replanner itself fails, defaults to `CONTINUE`, not `ABORT`

### Parallel Execution

- **DAG-based parallelism**: Kahn's algorithm topological sort into parallel execution levels
- **Git worktree isolation**: Each parallel issue gets its own worktree/branch -- no interference
- **Configurable concurrency**: `max_concurrent_issues` (default 3) per level
- **File conflict detection**: Pre-detected at planning time, passed to merger for informed resolution

### Quality & Governance

- **Risk-proportional QA**: Sprint planner routes each issue to 2-call (default) or 4-call (flagged) path
- **Typed technical debt**: Dropped ACs, missing functionality, unmet criteria -- all tracked with severity
- **Debt propagation**: Downstream issues receive `debt_notes` and `failure_notes` from upstream
- **DID/VC governance** (via AgentField): Every agent invocation gets a cryptographically signed Verifiable Credential
- **Workflow VC chain**: Full provenance record for every build output

### Continual Learning

- **Shared memory** (`enable_learning=true`): Key-value store across all issues in a build
- **Memory categories**: `codebase_conventions`, `failure_patterns`, `bug_patterns`, `interfaces/{issue}`, `build_health`
- **Convention discovery**: First successful coder writes conventions; all downstream coders read them

### Fast Mode (swe-fast)

- **Speed-optimized agent**: Single-pass planning, sequential execution, no DAG/replanning overhead
- **Sub-10-minute target**: For simple goals where full factory overhead is unnecessary
- **Same interface**: Accepts same `build()` API as the full pipeline
- **Separate node**: Runs as `swe-fast` on port 8004, coexists with `swe-planner`

### Deployment & Operations

- **Docker Compose**: Control plane + agent(s) + volumes; `docker compose up --scale swe-agent=3`
- **Railway one-click**: Template deploy with PostgreSQL
- **Artifact persistence**: `.artifacts/plan/`, `.artifacts/execution/`, `.artifacts/verification/`
- **Health checks**: `/health` endpoint with 30s interval
- **Configurable timeouts**: Per-agent (`agent_timeout_seconds`, default 2700s/45min), per-build for fast mode

### Benchmarking

- **95/100 on custom benchmark** with both Claude haiku ($20) and MiniMax M2.5 ($6)
- **Outperformed**: Claude Code Sonnet (73), Codex o3 (62), Claude Code Haiku (59) on same prompt
- **Benchmark included in repo**: `examples/agent-comparison/` with logs, evaluator, generated projects

## What Users Like

### Evidence from Stars and Activity

- 272 stars and 41 forks in ~2 weeks indicates strong early interest
- Community contribution already happening: Issue #8 from external user requesting GLM-5 support (closed with working solution from maintainer)

### Evidence from PRs and Issues

- **One-call simplicity**: The entire value proposition is "one curl command = shipped code." PR #19 restructured the README to lead with this, suggesting it resonates
- **Multi-model flexibility**: PR #7 and PR #18 added multi-repo support, suggesting demand for orchestrating across codebases
- **Open-source model support**: The OpenCode runtime enabling MiniMax/DeepSeek/Qwen at 70% cost savings was a key selling point (benchmarked at $6 vs $20 for Claude)
- **Draft PR output**: End-to-end from goal to GitHub draft PR with zero human code (PR #179 on AgentField repo cited as showcase: 10/10 issues, 217 tests, $19.23 cost)
- **Fast mode demand**: PR #3 and PR #4 show iteration on a speed-optimized path, suggesting users wanted faster turnarounds for simpler tasks

### Evidence from Showcase Projects

- `examples/llm-rust-python-compiler-sonnet/` demonstrates a complex autonomous Rust build with 175 tracked agents -- this is the kind of showcase that builds credibility
- `examples/agent-comparison/` with objective metrics (coverage, LOC, test counts) across agents provides trust through transparency

## What Users Dislike / Struggle With

### From Issues

- **Issue #8**: User struggled with GLM-5 (ZhipuAI) integration -- "Product manager failed to produce a valid PRD" because the system expects structured output that not all models handle well. This reveals a core fragility: the pipeline depends on structured JSON output from LLMs, and models that don't support this cleanly will fail
- **No other user-filed issues visible**: Only 1 external issue in the tracker. The low issue count (1 user issue, rest are internal PRs) suggests either (a) very few active users beyond the team, or (b) issues are reported elsewhere

### From Closed/Failed PRs

- **PR #15, #16, #17 (all CLOSED)**: Three separate attempts to optimize pipeline time through parameter tuning and prompt compression -- all closed. This suggests the team struggled to reduce build times without breaking quality. The 30-40 minute build time is a real pain point they haven't solved
- **PR #4 (CLOSED)**: First attempt at `fast_build` inside the main app was closed; PR #3 (MERGED) created it as a separate agent instead. Architecture iteration on how to offer a lightweight path

### From Architecture Analysis

- **Heavyweight setup**: Requires AgentField control plane (separate Go binary), Docker, PostgreSQL (for Railway). This is a lot of infra for "just make code from a goal"
- **No CLI mode**: Everything goes through HTTP APIs. There is no `swe-af build "Add JWT auth" --repo .` command. Users must run `curl` commands
- **No streaming output**: The API is async poll-based. Users have no real-time visibility into what agents are doing (only after-the-fact artifacts)
- **Pinned SDK version**: `claude-agent-sdk==0.1.20` pinned due to "Unknown message type: rate_limit_event" -- indicates fragility in the provider layer
- **No web UI**: No dashboard, no visual DAG viewer, no real-time build monitor. Monitoring is `curl` on the execution ID

### Implicit Pain Points

- **Cost opacity**: While they show total cost ($19 for the showcase), there is no per-build cost estimation or budget limits visible in the API
- **No incremental builds**: Every build starts from scratch. No concept of "only rebuild what changed"
- **Single-tenant**: One control plane, one or more agent nodes. No multi-user, no auth beyond API key
- **Test coverage unknown for core**: While examples show 99% coverage for generated code, the test suite for swe_af itself is all mocked-AI -- no integration tests against real LLMs in CI

## Good Ideas to Poach

### 1. Three-Nested-Loop Self-Healing (Critical)

The inner/middle/outer loop architecture is the most valuable pattern. Automaton should adopt a similar escalation strategy:
- **Inner**: Retry with feedback (current approach)
- **Middle**: Change approach, relax scope, split task, accept with debt
- **Outer**: Restructure remaining plan

Key files: `swe_af/execution/coding_loop.py` (inner loop), `swe_af/execution/dag_executor.py` (middle+outer loops), `swe_af/execution/schemas.py` (AdvisorAction, ReplanAction enums)

### 2. Typed Technical Debt Tracking

When scope is relaxed or work is incomplete, SWE-AF doesn't silently drop it -- it creates typed, severity-rated debt items that propagate to downstream tasks and surface in the final PR. Automaton should track:
- What acceptance criteria were dropped and why
- What functionality is missing
- Severity rating (high/medium/low)
- Propagation to dependent steps

Key file: `swe_af/execution/schemas.py` (IssueAdaptation, IssueOutcome.COMPLETED_WITH_DEBT)

### 3. Risk-Proportional QA Routing

The sprint planner deciding "this issue needs deeper QA" vs "this is straightforward" at planning time is efficient. Instead of running full QA on everything, Automaton could:
- Rate task complexity at planning time
- Route simple tasks through a lightweight review
- Route complex tasks through full test + review + synthesis

Key file: `swe_af/reasoners/schemas.py` (IssueGuidance.needs_deeper_qa)

### 4. Cross-Agent Shared Memory

The `enable_learning` feature where codebase conventions, failure patterns, and interfaces discovered by early agents are injected into later agents is powerful for multi-step builds. Automaton could maintain a simple key-value context that accumulates across pipeline steps.

Key file: `swe_af/execution/coding_loop.py` (_read_memory_context, _write_memory_on_approve, _write_memory_on_failure)

### 5. Checkpoint/Resume for Long Builds

Serializing full execution state at every boundary so builds can resume after crashes. For a bash pipeline, this could be as simple as writing state to a JSON file after each major step.

Key file: `swe_af/execution/dag_executor.py` (checkpoint save/load logic)

### 6. Git Worktree Isolation for Parallel Work

Using git worktrees to give each parallel task its own working directory eliminates merge conflicts during coding. Bash can do this natively with `git worktree add`.

Key file: `swe_af/execution/dag_executor.py` (_setup_worktrees)

### 7. File Conflict Pre-Detection

At planning time, detecting which parallel tasks touch the same files and flagging these for the merger. Simple set intersection -- easy to implement in bash.

Key file: `swe_af/reasoners/pipeline.py` (_validate_file_conflicts)

### 8. Stuck Loop Detection

Detecting when the coder is cycling without progress (same feedback repeated) and breaking out early rather than burning budget. Simple window-based history check.

Key file: `swe_af/execution/coding_loop.py` (_detect_stuck_loop)

## Ideas to Improve On

### 1. Eliminate the Infrastructure Tax

SWE-AF requires: AgentField control plane (Go binary) + PostgreSQL (Railway) + Docker + HTTP API calls. Automaton's single-bash-file approach is a massive advantage. A user should be able to run `./automaton "Add JWT auth"` with zero infrastructure setup. No Docker, no control plane, no database.

### 2. Provide a Real CLI Experience

SWE-AF has no CLI -- everything is `curl` to HTTP endpoints. Automaton should be invocable as a simple command with streaming terminal output, progress bars, and color-coded status. The developer experience of watching agents work in real-time is far superior to polling an execution ID.

### 3. Streaming Output / Live Visibility

SWE-AF provides no real-time visibility -- you submit a build and poll. Automaton should stream agent output to the terminal as it happens: what the planner decided, what the coder is writing, what the reviewer found. This builds trust and lets users intervene early if something goes wrong.

### 4. Faster Builds for Common Cases

SWE-AF's 30-40 minute builds are their biggest pain point (three failed PRs trying to optimize). Their `swe-fast` mode targets sub-10 minutes but is a separate agent. Automaton should be fast by default -- under 5 minutes for simple goals -- with optional depth for complex projects. Start lean, add depth only when needed.

### 5. Cost Estimation and Budget Controls

SWE-AF shows cost after the fact ($19 for a showcase build) but has no pre-build cost estimation or hard budget limits in the API. `max_budget_usd` exists on the AgentAI config but is not exposed at the build level. Automaton should estimate cost before starting and enforce hard limits.

### 6. Incremental Builds

SWE-AF rebuilds everything from scratch every time. Automaton could detect what changed in the spec and only regenerate affected components, reusing artifacts from previous runs. This would dramatically reduce both time and cost for iterative development.

### 7. Simpler Model Configuration

SWE-AF's model config is powerful but complex: runtime + default + 16 role-specific overrides, with legacy key rejection and resolution chains. They even had to add error messages for legacy config formats (V1 to V2 migration in `_reject_legacy_config_keys`). Automaton should keep it simple: one model flag, maybe a fast/quality toggle.

### 8. Better Error Messages and Debugging

When SWE-AF fails, the error is buried in artifacts JSON files. No centralized error log, no "here's what went wrong" summary. Automaton should surface errors prominently with clear root cause analysis and suggested fixes.

### 9. Local-First, No Network Required for Core

SWE-AF requires network access to a control plane even for local builds. Automaton should work fully offline with local models if desired, with no mandatory network dependencies for the core pipeline.

### 10. Avoid Pydantic Schema Fragility

SWE-AF depends on LLMs producing valid structured JSON that matches Pydantic schemas (PRD, Architecture, PlannedIssue, etc.). Issue #8 showed this breaks with models that don't support structured output well. Automaton should use more forgiving parsing -- extract what you can from LLM output rather than requiring exact schema compliance.
