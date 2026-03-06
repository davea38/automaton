# Competitive Analysis: Agents (wshobson/agents)

## Overview

**What it is:** A massive collection of Claude Code plugins providing pre-built AI agent configurations, slash commands, and "skills" (knowledge packages) for software development workflows. Not executable code -- it is almost entirely Markdown files (504 of 601 non-git files) that serve as system prompts, workflow scripts, and knowledge documents loaded into Claude Code's plugin system.

| Metric | Value |
|---|---|
| **Primary Language** | Markdown (99%+ by file count; Python used only for one utility script) |
| **Stars** | 30,034 |
| **Forks** | 3,293 |
| **Last Updated** | 2026-03-03 (active daily) |
| **License** | MIT |
| **Total Files** | ~601 (excluding .git) |
| **Total LOC** | ~188,000 lines across all files |
| **Marketplace Version** | 1.5.5 |
| **Author** | Seth Hobson (@wshobson) |

The project is a Claude Code plugin marketplace -- not a standalone tool. It requires Claude Code's `/plugin` infrastructure to function and provides no independent execution capability.

## Architecture & Structure

### Repository Layout

```
wshobson-agents/
├── .claude-plugin/
│   └── marketplace.json          # Central registry of 72 plugins (950 lines)
├── plugins/                      # 72 plugin directories
│   └── <plugin-name>/
│       ├── agents/               # Agent .md files (system prompts)
│       ├── commands/             # Slash command .md files (workflow scripts)
│       └── skills/               # Knowledge package directories
│           └── <skill-name>/
│               └── SKILL.md
├── docs/                         # 5 documentation files
│   ├── architecture.md
│   ├── agents.md
│   ├── agent-skills.md
│   ├── plugins.md
│   └── usage.md
├── tools/
│   └── yt-design-extractor.py    # Only actual code (~500 lines Python)
├── Makefile                      # For yt-design-extractor only
└── README.md
```

### Key Files

- **`.claude-plugin/marketplace.json`** (950 lines): Central plugin registry. Each entry defines a plugin name, source path, description, version, and category. This is the entry point Claude Code uses to discover and install plugins.
- **`plugins/*/agents/*.md`**: 177 agent files. Each contains YAML frontmatter (`name`, `description`, `model`) followed by a system prompt defining the agent's persona, capabilities, and behavioral rules.
- **`plugins/*/commands/*.md`**: 90 command files. Each defines a slash command with argument hints and detailed step-by-step workflow instructions.
- **`plugins/*/skills/*/SKILL.md`**: 146 skill files. Progressive-disclosure knowledge documents with YAML frontmatter and structured content.
- **`plugins/conductor/`**: Most architecturally significant plugin -- a Context-Driven Development workflow (adapted from Google's Gemini CLI Conductor).

### Tech Stack

- **Runtime dependency**: Claude Code's plugin system (`/plugin marketplace add`, `/plugin install`)
- **Content format**: Markdown with YAML frontmatter
- **Model tiers**: Opus 4.6 (42 agents), Sonnet (51 agents), Haiku (18 agents), Inherit/user-choice (42 agents)
- **No build system, no tests, no CI**: Pure content repository
- **Single Python utility** (`tools/yt-design-extractor.py`): YouTube video-to-markdown extractor, unrelated to core functionality

### Architectural Pattern

The architecture follows a "marketplace of prompt templates" pattern:
1. User installs the marketplace via Claude Code CLI
2. User cherry-picks plugins to install
3. Each installed plugin loads its agents, commands, and skills into Claude Code's context
4. Agents are invoked via natural language or slash commands
5. Multi-agent workflows are orchestrated by command files that reference agent names

There is no actual orchestration runtime -- Claude Code itself is the execution engine. The "agents" are just system prompts that Claude adopts as personas.

## Features

### Core Feature Catalog

**Plugin System (72 plugins across 24 categories):**
- Development: backend, frontend, multi-platform, debugging
- Languages: Python (16 skills), JS/TS (4 skills), systems programming, JVM, functional, Julia, shell scripting, .NET
- Infrastructure: Kubernetes, cloud (AWS/Azure/GCP), CI/CD, deployment strategies/validation
- Security: SAST scanning, compliance, backend/API security, frontend/mobile security
- Data: engineering, validation suites, database design/migrations/optimization
- AI/ML: LLM application dev (8 skills), agent orchestration, MLOps, context management
- Operations: incident response, error diagnostics, distributed debugging, observability
- Business: analytics, HR/legal, customer/sales, startup analysis
- Marketing: SEO (3 plugins), content marketing
- Specialized: blockchain/Web3, quantitative trading, payment processing, game development, ARM Cortex microcontrollers

**Agent Configurations (177 agent files):**
- Each agent has a model tier assignment (Opus/Sonnet/Haiku/inherit)
- Detailed system prompts with capabilities, behavioral rules, tool access
- Examples: `python-pro.md`, `backend-architect.md`, `security-auditor.md`, `kubernetes-architect.md`
- Some agents are duplicated across plugins (e.g., `code-reviewer.md` appears 7 times, `backend-architect.md` 6 times)

**Slash Commands (90 command files):**
- Workflow orchestrators: `/full-stack-orchestration:full-stack-feature`, `/conductor:setup`
- Development tools: `/python-development:python-scaffold`, `/unit-testing:test-generate`
- Security: `/security-scanning:security-hardening`, `/security-scanning:security-sast`
- DevOps: `/cicd-automation:workflow-automate`, `/kubernetes-operations:k8s-deploy`
- TDD: `/tdd-workflows:tdd-cycle`, `/tdd-workflows:tdd-red`, `/tdd-workflows:tdd-green`

**Agent Skills (146 skills):**
- Progressive disclosure: metadata (always loaded) -> instructions (on activation) -> resources (on demand)
- Follows Anthropic's Agent Skills Specification
- Examples: `async-python-patterns`, `k8s-manifest-generator`, `helm-chart-scaffolding`, `sast-configuration`

**Conductor Plugin (spec-to-implementation pipeline):**
- `/conductor:setup`: Interactive project initialization (product vision, tech stack, workflow rules, style guides)
- `/conductor:new-track`: Spec and plan generation for features/bugs/chores
- `/conductor:implement`: TDD-driven task execution from plans
- `/conductor:status`: Progress monitoring
- `/conductor:revert`: Git-aware semantic undo by track/phase/task
- `/conductor:manage`: Track lifecycle management (archive, restore, delete, rename)
- Generates `conductor/` directory with structured artifacts (spec.md, plan.md, metadata.json per track)

**Agent Teams Plugin (multi-agent parallelism):**
- 7 team presets: review, debug, feature, fullstack, research, security, migration
- Parallel code review across dimensions (security, performance, architecture)
- Hypothesis-driven debugging with competing investigator agents
- Requires Claude Code's experimental Agent Teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- 4 agent types: team-lead, team-reviewer, team-debugger, team-implementer

**Three-Tier Model Strategy:**
- Opus 4.6 for critical architecture/security/review (42 agents)
- Sonnet 4.6 for complex tasks (51 agents)
- Haiku 4.5 for fast operational tasks (18 agents)
- "Inherit" tier lets user control model selection (42 agents)

## What Users Like

**Massive popularity (30K+ stars):** The star count alone signals strong community interest. The repo gained significant traction quickly, evidenced by the star history chart in the README.

**Breadth of coverage:** The 72 plugins cover a remarkable range of domains from Python development to quantitative trading to ARM Cortex microcontrollers. Users don't need to write their own agent prompts from scratch.

**Community contributions:** Active PR activity shows community engagement:
- PR #435 (merged): Stripe employee contributing modern Stripe best practices
- PR #427 (merged): Community member updating Tailwind CSS v4 skill
- PR #419 (merged): Comprehensive Python development skill expansion (5 -> 16 skills)
- PR #432 (merged): YouTube design concept extractor tool
- PR #437 (closed): External company offering to improve skill eval scores

**Conductor plugin resonates:** The spec-to-implementation workflow (adapted from Google's Gemini CLI) addresses a real need for structured AI-driven development. Its interactive setup, track-based development, and semantic revert features show thoughtful workflow design.

**Progressive disclosure architecture:** The three-tier skill loading (metadata -> instructions -> resources) is praised as token-efficient. Issue #93 shows users care deeply about context window usage.

**Plugin granularity:** Users appreciate installing only what they need. The average 3.4 components per plugin aligns with Anthropic's recommended 2-8 pattern.

**Feature request activity (8 labeled enhancement issues in sample):** Signals engaged user base requesting improvements like model upgrades (#136), expanded Python skills (#418), and better documentation (#102).

## What Users Dislike / Struggle With

**Duplicate agents cause token waste and errors (Issues #413, #112, #111, #80):**
- `code-reviewer.md` is duplicated 7 times across plugins
- `backend-architect.md` is duplicated 6 times
- `test-automator.md` duplicated 6 times
- Issue #111: "Error: 400 Tool names must be unique" -- Claude Code rejects duplicate agent names when multiple plugins installed
- Issue #80: "Installing 5 plugins makes 95% of agents being added double"
- Issue #413: Token waste quantified at ~4,200 tokens for code-reviewer alone
- PR #414 proposes symlinks but remains open/unmerged

**Missing referenced files and broken references (Issues #416, #406, #116, #424, #428):**
- Issue #416: Skill files reference non-existent directories
- Issue #406: `marketplace.json` references `./skills/monorepo-dependency-management` which does not exist
- Issue #424: SKILLS.md references non-existent npm packages
- Issue #428: `python-development` references 11 non-existent skills
- Issue #116: "architecture-patterns" skill missing referenced `references/` and `assets/` directories
- Pattern: Content was AI-generated without verification that referenced files actually exist

**Context window bloat (Issue #93):**
- Users report "Large cumulative agent descriptions will impact performance" error
- Installing multiple plugins loads too many agent descriptions, overwhelming the context window
- 4 comments on this issue indicate widespread frustration

**Plugin installation confusion (Issues #133, #85, #105, #75, #81):**
- Issue #133: "Plugin not installed error" -- users confused about plugin vs agent naming
- Issue #85: "Failed to clone marketplace repository"
- Issue #105: "Not all agents seem to be available"
- Issue #75: "Workflows and tools not seen by Claude Code"
- Issue #81: "404 error on run"

**Agent interruption and reliability (Issue #101):**
- "Agents keep getting 'Interrupted'" -- agents fail mid-execution
- 2 comments, indicating recurring problem

**Stale/incorrect content (Issues #438, #436, #88, #87, #55):**
- Issue #438: Deprecated iOS TabView version used in agent prompt
- Issue #436: react-modernization agent fails trust hub rating
- Issue #88: "Agent Count Mismatch: Documented vs Actual Agents"
- Issue #87: doc-generate tool poorly documented
- Issue #55: hr-pro.md contained "inappropriate and harmful content"

**Plugins claim independence but aren't (Issue #433):**
- User reports that `/backend-development:feature-development` command references agents from other plugins
- Contradicts the "independent, self-contained units" philosophy

**Version/cache issues (Issue #143):**
- Version numbers not bumped when adding skills, breaking cache invalidation
- Users must manually clear cache to pick up changes

## Good Ideas to Poach

**1. Conductor's Spec-to-Implementation Pipeline:**
The `conductor/` plugin implements a structured `Context -> Spec & Plan -> Implement` workflow with persistent artifacts. Key patterns worth adopting:
- Interactive Q&A to gather requirements (one question per turn, max 5 per section)
- Generated `spec.md` and `plan.md` per work unit ("track")
- TDD-driven implementation with verification checkpoints
- Semantic revert by logical work unit (not just git commits)
- State persistence via `setup_state.json` for resumable sessions
- See: `plugins/conductor/commands/setup.md`, `plugins/conductor/commands/new-track.md`, `plugins/conductor/commands/implement.md`

**2. Three-Tier Model Strategy:**
Assigning different model tiers (Opus/Sonnet/Haiku) based on task complexity is smart cost optimization. Automaton could adopt a similar principle for deciding when to use expensive vs. cheap models during different pipeline phases.

**3. Progressive Disclosure for Knowledge:**
The skill architecture's three-tier loading (metadata always -> instructions on activation -> resources on demand) is an elegant way to manage context window budget. Automaton could apply this to spec files or reference documentation.

**4. Full-Stack Feature Orchestrator Pattern:**
The `full-stack-feature.md` command (see `plugins/full-stack-orchestration/commands/full-stack-feature.md`) defines:
- Pre-flight checks with state persistence
- Phase checkpoints requiring user approval
- Halt-on-failure with error presentation
- Output files per step (not relying on context window memory)
- These behavioral rules are directly applicable to Automaton's pipeline stages.

**5. Agent Teams for Parallel Work:**
The hypothesis-driven debugging pattern (spawn multiple agents with competing hypotheses, evidence-based selection) and parallel code review across dimensions (security, performance, architecture) are novel coordination patterns. See `plugins/agent-teams/`.

**6. Track/Task State Management:**
The `metadata.json` per track with status tracking, the `tracks.md` registry, and the `/conductor:status` progress display show mature project state management. Automaton could adopt similar state files for pipeline progress.

**7. YAML Frontmatter Convention:**
Every agent/command/skill uses YAML frontmatter for metadata (name, description, model, argument-hint). This is a clean, standardized way to make content machine-parseable. Automaton specs could adopt similar frontmatter.

## Ideas to Improve On

**1. No Actual Code -- All Prompts:**
The entire 188K-line repository is Markdown system prompts with zero executable logic, zero tests, and zero validation. Automaton's advantage as a single-bash-file pipeline is that it actually executes, with real control flow, error handling, and state management. The "agents" here are just personas Claude adopts -- there is no orchestration runtime. Automaton should emphasize its deterministic execution model vs. this "hope the LLM follows the prompt" approach.

**2. Rampant Content Duplication:**
The same agent file (`code-reviewer.md`, `backend-architect.md`, etc.) is copy-pasted across 5-7 plugins. This causes real user-facing bugs (duplicate tool names, token waste). Automaton should enforce DRY principles -- define agents/capabilities once, reference them everywhere.

**3. AI-Generated Content Not Verified:**
Multiple issues (#416, #406, #424, #428, #116) report references to files that do not exist. This is a hallmark of AI-generated content committed without verification. Automaton should include validation steps that verify all referenced paths/files actually exist.

**4. No Testing or CI:**
Zero automated tests. No GitHub Actions workflow. No linting. No validation that `marketplace.json` entries point to real directories, that agent names are unique across plugins, or that skill references resolve. Automaton could include self-validation as a pipeline step (e.g., `automaton validate` checks all spec references).

**5. Context Window Management is User's Problem:**
Despite 146 skills and 177 agents, there is no mechanism to prevent context overflow beyond telling users to "install only what you need." Issue #93 shows this fails in practice. Automaton should have built-in context budget management -- automatically pruning, summarizing, or paginating content to stay within limits.

**6. No Execution Feedback Loop:**
The Conductor plugin generates specs and plans but has no mechanism to verify that implementation actually matches the spec. The `/conductor:implement` command follows plans step-by-step but cannot validate outcomes beyond "did tests pass." Automaton should close the loop with spec-vs-implementation verification.

**7. Plugin Independence is a Lie:**
Issue #433 exposes that commands reference agents from other plugins, breaking the "independent, self-contained" claim. Automaton should have true modularity with explicit dependency declarations and validation.

**8. Version Management is Manual:**
Issue #143 shows that version numbers are not bumped when content changes, breaking cache invalidation. With 72 plugins and 950 lines of `marketplace.json`, manual version management is unsustainable. Automaton could auto-version based on content hashes.

**9. No Observability Into Pipeline Execution:**
When an agent is "Interrupted" (Issue #101), users have no diagnostics. When a multi-step workflow fails mid-way, there is no structured log. Automaton should provide detailed execution logs, timing, token usage, and failure diagnostics for every pipeline run.

**10. Conductor is Adapted, Not Original:**
The most interesting plugin (Conductor) is explicitly credited as "based on Conductor by Google, originally developed for Gemini CLI" (see `plugins/conductor/README.md` line 119). The core innovation came from elsewhere. Automaton has the opportunity to build a native, purpose-built pipeline that goes deeper than a port.
