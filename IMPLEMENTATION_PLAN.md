# Implementation Plan

Specs 1-26 are fully implemented in `automaton.sh` (5249 lines, 99 functions). All templates are synced, `.gitignore` is committed, and `PROMPT_self_research.md` is registered in the scaffolder.

Eleven new specs (27-37) extend the orchestrator with Claude 4.6 prompt engineering, native subagent definitions, hooks, skills, structured state, prompt caching, context lifecycle management, test-first builds, Max Plan optimization, session bootstrap, and Agent Teams integration. The specs are organized into four implementation tiers based on their dependency graph.

## Previously Completed

- [x] Sync `templates/automaton.sh` with root (WHY: template was 1103 lines behind, missing specs 22-26 functionality)
- [x] Sync `templates/automaton.config.json` with root (WHY: template was missing self_build, journal, and budget fields)
- [x] Sync `templates/PROMPT_build.md` with root (WHY: template was missing self-build safety rules from spec-22)
- [x] Sync `templates/PROMPT_review.md` with root (WHY: template was missing self-build review section from spec-25)
- [x] Sync `templates/PROMPT_research.md` with root (WHY: template was missing context_summary read from spec-24)
- [x] Sync `templates/PROMPT_plan.md` with root (WHY: template was missing context_summary read and proportional subagent scaling)
- [x] Copy root `PROMPT_self_research.md` to `templates/PROMPT_self_research.md` (WHY: without the template, scaffolded projects cannot use `--self` mode's research phase)
- [x] Add `'PROMPT_self_research.md'` to the `TEMPLATE_FILES` array in `bin/cli.js` (WHY: the scaffolder must know about the file to copy it during `npx automaton`)
- [x] Stage and commit `.gitignore` (WHY: it is untracked and should be in version control to ensure `.automaton/` runtime state is excluded; committed in af3cdd5)

## Tier 1: Foundation (No Dependencies Among New Specs)

### Spec 29 — Prompt Engineering for Claude 4.6

This is the foundation spec. Five other specs (30, 27, 33, 36, 37) depend on the XML-tagged prompt structure and static-first ordering it introduces.

- [x] Remove "Ultrathink", "think deeply", and explicit `budget_tokens` directives from all `PROMPT_*.md` files (WHY: Claude 4.6 uses adaptive thinking; manual thinking directives interfere with its calibration)
- [x] Replace fixed subagent cardinality instructions ("500 parallel Sonnet subagents") with outcome-oriented scaling directives in all `PROMPT_*.md` files (WHY: Claude 4.6 decides subagent count adaptively; prescriptive counts prevent optimal tool calling)
- [x] Restructure `PROMPT_research.md` with XML-tagged sections (`<context>`, `<identity>`, `<rules>`, `<instructions>`, `<output_format>`, `<dynamic_context>`) and add "do NOT over-explore" guardrail (WHY: XML tags provide semantic boundaries that Claude 4.6 is highly responsive to; research phase tends to over-explore without guardrails)
- [x] Restructure `PROMPT_plan.md` with XML-tagged sections and replace "be exhaustive" with "cover all tasks needed, no more" (WHY: static-first ordering is required for prompt caching in spec-30; tone calibration prevents plan bloat)
- [x] Restructure `PROMPT_build.md` with XML-tagged sections, replace `<promise>COMPLETE</promise>` with `<result status="complete">`, and add anti-overengineering guardrails (WHY: structured result signaling integrates with file-state verification; guardrails prevent known Claude 4.6 anti-patterns)
- [x] Restructure `PROMPT_review.md` with XML-tagged sections, remove "be thorough"/"be exhaustive", and add "focus on correctness, not style" (WHY: Opus 4.6 is already thorough; redundant thoroughness directives cause review over-flagging)
- [x] Add `<!-- DYNAMIC CONTEXT BELOW — injected by orchestrator -->` separator and parallel tool calling directive to all `PROMPT_*.md` files (WHY: the separator defines the cache boundary for spec-30; the parallel directive ensures maximum tool call parallelism)
- [x] Update `run_agent()` in `automaton.sh` to inject dynamic context (iteration number, budget, diffs) after the static separator instead of prepending (WHY: injecting dynamic data into the static prefix would invalidate the prompt cache every iteration)

### Spec 34 — Structured State via Git

Persistent state split is required by spec-37 (session bootstrap reads `learnings.json`) and improves resume recovery for all future runs.

- [x] Restructure `.gitignore` to split `.automaton/` into ephemeral (gitignored: `state.json`, `rate.json`, `wave/`, `worktrees/`, `dashboard.txt`, `session.log`, `self_checksums.json`, `progress.txt`) and persistent (tracked: `budget-history.json`, `learnings.json`, `run-summaries/`, `test_results.json`, `self_modifications.json`) (WHY: currently all `.automaton/` is gitignored; losing the directory loses all orchestration history)
- [x] Create `.automaton/learnings.json` with structured schema (id, category, summary, detail, confidence, source_phase, tags, active) and add functions in `automaton.sh` to read/write/query learnings (WHY: AGENTS.md learnings are unstructured free text with a 60-line limit; structured JSON enables querying, categorization, and confidence filtering)
- [x] Implement AGENTS.md generation from `learnings.json` + project metadata at phase transitions in `automaton.sh` (WHY: AGENTS.md becomes a generated view rather than a manually-appended file, preventing content drift and enforcing the 60-line limit automatically)
- [x] Create `.automaton/run-summaries/` directory and write per-run summary JSON (phases completed, iterations, tokens, cost, learnings added, git commits) at run completion in `automaton.sh` (WHY: run summaries provide audit trail and resume context; they replace the improvement loop journal from spec-26)
- [x] Create `.automaton/budget-history.json` separate from ephemeral `budget.json`, accumulating cross-run token and cost data with weekly totals (WHY: budget trends and cost analysis require persistent history that survives directory loss)
- [x] Implement resume recovery from persistent state in `automaton.sh`: reconstruct `state.json` from latest run summary, `IMPLEMENTATION_PLAN.md` checkboxes, `budget-history.json`, and `git log` when ephemeral state is missing (WHY: users who lose `.automaton/state.json` can resume from git-tracked persistent state instead of starting over)
- [x] Add persistent state commit protocol to `automaton.sh`: commit persistent files at phase transitions, run completion, and every 5 build iterations (WHY: periodic checkpoints ensure persistent state is not lost if the orchestrator is interrupted mid-run)

## Tier 2: Core Features (Depends on Tier 1)

### Spec 30 — Prompt Caching Optimization (depends on spec-29)

Prompt cache reads cost 90% less than uncached input tokens. Spec-29's static-first ordering makes caching possible; this spec activates and tracks it.

- [x] Add `<!-- STATIC CONTENT — do not inject per-iteration data above this line -->` markers to all `PROMPT_*.md` files to define the cache boundary (WHY: the static prefix must be byte-for-byte identical across iterations to achieve cache hits; explicit markers prevent accidental injection of dynamic data)
- [x] Calculate cache hit ratio (`cache_read / (cache_read + input + cache_create)`) after every agent invocation in `post_iteration()` and store in `budget.json` history (WHY: cache hit ratio is the primary metric for validating that prompt assembly preserves the static prefix)
- [x] Emit warning when rolling average cache hit ratio drops below 50% after 3+ iterations in any phase (WHY: low cache ratio indicates the static prefix is changing between iterations — likely a bug in prompt assembly)
- [x] Ensure all parallel builders share an identical static prompt prefix by moving builder number, wave number, task assignment, and file ownership list to `<dynamic_context>` (WHY: cache entry created by builder-1 is reused by builders 2..N, saving 90% on input tokens for all subsequent builders in a wave)
- [x] Move context summaries (`context_summary.md`) and iteration memory (`iteration_memory.md`) to after the static prefix in prompt assembly (WHY: these change every iteration and would invalidate the cache if placed before the static content)
- [x] Add cache hit ratio to the dashboard (spec-21) and status line output, including allowance-mode token accounting note (WHY: visibility into cache performance helps users diagnose cost issues; allowance users need to know cache reduces cost but not token consumption)
- [x] Log informational message when static prefix is below minimum cacheable token threshold per model (4096 for Opus/Haiku, 2048 for Sonnet) (WHY: users need to know when caching is inactive so they can decide whether to expand the static prefix)

### Spec 33 — Context Window Lifecycle (depends on spec-29)

Context window management is the critical constraint for multi-iteration workflows. This spec prevents performance degradation and data loss from auto-compaction.

- [x] Define context utilization ceilings per phase (research 60%, plan 70%, build 80%, review 70%) and log warnings when exceeded using `(input_tokens + output_tokens) / model_context_window_size` (WHY: performance degrades as context fills; warnings alert users to split tasks or commit more frequently)
- [x] Add frequent-commit rule to `PROMPT_build.md` `<rules>` section: "Commit after each logical change. Do not accumulate uncommitted work — auto-compaction at 95% context may lose uncommitted state." (WHY: auto-compaction is the #1 cause of lost work in multi-iteration builds; frequent commits ensure all work survives compaction)
- [x] Add compaction guidance to build and research prompts: use `/compact` for long investigations, prefer targeted file reads over full-file reads, scope investigations narrowly (WHY: proactive compaction preserves important context; narrow scoping prevents context waste)
- [x] Implement auto-compaction detection in `automaton.sh` by detecting token count drops in `stream-json` output between turns within an iteration (WHY: knowing when compaction occurred helps explain unexpected behavior and informs task sizing decisions)
- [x] Generate `.automaton/progress.txt` at each iteration with human-readable status (phase, iteration, completed/total tasks, last completed, currently blocked, key decisions) (WHY: any agent in any context window can read this one file to understand full project state without loading history)
- [x] Track context utilization per iteration in budget history as `estimated_utilization` field (WHY: historical utilization data informs future task sizing and helps identify phases that consistently hit context limits)

### Spec 35 — Max Plan Optimization (extends specs 23, 08, 12)

Max Plan subscribers have zero token cost within allowance but need pacing and multi-project tracking to avoid exhausting the weekly allowance.

- [x] Add `rate_limits_presets` to `automaton.sh` with `api_default` and `max_plan` profiles, and auto-apply `max_plan` preset when `budget.mode` is `"allowance"` (WHY: Max Plan has higher rate limits; using API-tier limits leaves performance on the table)
- [x] Implement daily budget pacing: calculate `daily_budget = remaining_allowance / days_until_reset` and use as run-level token ceiling; warn if daily budget < 500K tokens (WHY: without pacing, a single Monday run can exhaust the entire week's allowance)
- [x] Add `--budget-check` CLI flag that displays weekly allowance status (used, remaining, reserve, daily pace, recommended run budget) without starting a run (WHY: users need to check budget before committing to a run, especially when sharing allowance across projects)
- [x] Apply higher parallel defaults when in allowance mode (5 builders, 5s stagger, 5 research iterations) unless user has explicitly overridden (WHY: no per-token cost means more parallelism is free; faster completion with no cost penalty)
- [x] Create `~/.automaton/allowance.json` for cross-project allowance tracking with per-project usage, weekly totals, and week rollover archiving (WHY: Max Plan users running automaton on multiple projects share one allowance; cross-project tracking prevents over-allocation)
- [x] Add `max_plan_preset: true` config shortcut that applies all Max Plan defaults (allowance mode, Opus everywhere, 5 builders, 5s stagger, max_plan rate limits) (WHY: one-line config for Max Plan users instead of setting 6+ individual fields)
- [x] Display weekly summary on resume after week boundary and implement graceful allowance exhaustion (complete current iteration, save state, exit code 2) (WHY: users need visibility into week-over-week usage trends; graceful exhaustion prevents data loss)

### Spec 27 — Native Subagent Definitions (depends on spec-29)

Migrates agent spawning from bare `claude -p` with piped prompts to structured `.claude/agents/` definitions with model selection, tool restrictions, memory, and hooks.

- [x] Create `.claude/agents/` directory with five agent definition files: `research.md`, `plan.md`, `build.md`, `review.md`, `self-research.md` (WHY: native agent definitions replace manual prompt piping with structured files that Claude Code manages natively)
- [x] Write YAML frontmatter for each agent with correct model, tools, permissionMode, maxTurns, and memory fields per spec-27 field table (WHY: tool scoping prevents agents from writing when they should only read; model selection matches phase requirements)
- [x] Migrate static prompt content from `PROMPT_*.md` into agent definition bodies using spec-29 XML structure (WHY: the agent definition body serves as the system prompt; content must use the XML-tagged format from spec-29)
- [x] Add `isolation: worktree` to build agent definition for parallel mode and document the nesting constraint (`Agent` tool unavailable inside subagents) in each agent's `<rules>` section (WHY: worktree isolation replaces manual git worktree management from spec-17; documenting nesting prevents agents from attempting impossible subagent spawning)
- [x] Configure `memory: project` for all agents to use `.claude/agent-memory/<name>/MEMORY.md` and implement AGENTS.md learnings migration on first run (WHY: per-agent persistent memory replaces monolithic AGENTS.md learnings; first 200 lines auto-included in system prompt)
- [x] Add `agents.use_native_definitions` flag to `automaton.config.json` (default false) and update `run_agent()` in `automaton.sh` to invoke `claude --agent` when flag is true, piping only dynamic context via stdin (WHY: migration flag allows gradual rollout; keeping `claude -p` as default preserves backward compatibility)

### Spec 36 — Test-First Build Strategy (depends on spec-29)

For a self-building orchestrator, tests are the only reliable way to verify behavior without human review. This spec adds test scaffolding before implementation.

- [x] Add test scaffold sub-phase (3a) to the build loop in `automaton.sh`: run 1-3 iterations of test-only writing before implementation iterations (3b), controlled by `execution.test_scaffold_iterations` config (WHY: writing tests before implementation ensures tests verify intended behavior, not just current behavior)
- [x] Add test annotation rules to `PROMPT_plan.md`: each task gets `<!-- test: tests/test_[feature].sh -->` or `<!-- test: none -->` (WHY: test annotations connect plan tasks to test files, enabling the scaffold sub-phase to know which tests to write)
- [x] Add test-first discipline rules to `PROMPT_build.md` `<rules>` section: check for existing test, write test if missing, implement, verify test passes, commit (WHY: test-first discipline catches regressions and ensures build agents verify their own work)
- [x] Create `tests/test_helpers.sh` with minimal bash assertion functions: `assert_equals`, `assert_exit_code`, `assert_file_exists`, `assert_contains` (WHY: automaton.sh is bash; a lightweight assertion library enables testing without external dependencies like bats)
- [x] Add test-driven verification priority to `PROMPT_review.md`: run all tests first, check test coverage, review test quality, then review code; fail review gate if tests fail (WHY: test results are objective quality signals; code review without passing tests is theater)
- [x] Track test coverage metric (tasks with tests, tasks without, coverage ratio, passing/failing) in `automaton.sh` and append to run summaries (WHY: coverage tracking ensures test discipline is maintained across runs and reveals testing gaps)
- [x] Add `execution.test_first_enabled` (default true) and `execution.test_framework` ("bats" or "assertions") to `automaton.config.json` (WHY: users who do not want test-first can disable it; framework choice supports both bats users and minimal-dependency setups)

## Tier 3: Integration Features (Depends on Tier 2)

### Spec 31 — Hooks Integration (depends on spec-27)

Hooks guarantee enforcement of rules that prompts can only request. File ownership, self-build safety, and test capture move from advisory to mandatory.

- [x] Create `.claude/hooks/enforce-file-ownership.sh`: read builder assignment from `.automaton/wave/assignments.json`, extract target file path from stdin JSON, exit 0 if owned, exit 2 if not (WHY: prompt-based file ownership is advisory; hooks block writes to unowned files with a guaranteed enforcement mechanism)
- [x] Create `.claude/hooks/self-build-guard.sh`: block writes to orchestrator files (`automaton.sh`, `PROMPT_*.md`, `automaton.config.json`, `bin/cli.js`) unless the current task explicitly targets them; check `self_build.enabled` flag (WHY: self-modification safety is currently prompt-enforced; a hook prevents accidental orchestrator corruption regardless of agent behavior)
- [x] Create `.claude/hooks/capture-test-results.sh`: detect test/lint commands in Bash tool input, parse exit code, append structured result to `.automaton/test_results.json` (WHY: structured test results enable automated quality gates in review and provide test history for regression tracking)
- [x] Create `.claude/hooks/builder-on-stop.sh`: extract token usage, write builder result JSON, stage and commit changes, signal completion to conductor (WHY: `Stop` hook replaces builder wrapper cleanup logic; runs guaranteed even if agent crashes or times out)
- [x] Create `.claude/hooks/track-subagent-start.sh` and `.claude/hooks/track-subagent-stop.sh`: record agent name/timestamp at start, extract token usage at stop, append to `.automaton/subagent_usage.json` (WHY: per-subagent token tracking enables accurate budget attribution across parallel builders)
- [x] Create `.claude/hooks/task-quality-gate.sh` for `TaskCompleted` hook: run task-specific validation, exit 0 to accept or exit 2 to reject with feedback (WHY: prevents tasks from being marked complete when tests fail or syntax errors exist)
- [ ] Configure hook locations: file ownership in `.claude/settings.local.json` (changes per wave), self-build guard and test capture in `.claude/settings.json` (stable rules), agent-scoped hooks in agent frontmatter (WHY: dynamic hooks that change per wave must be in local settings; stable hooks belong in committed settings)
- [ ] Ensure all `PreToolUse` hooks complete in under 2 seconds and all hooks are idempotent (WHY: PreToolUse hooks block agent progress; slow hooks degrade iteration speed; non-idempotent hooks produce inconsistent results on retry)

### Spec 32 — Skills Library (depends on spec-27)

Skills extract reusable workflow patterns from prompts, reducing prompt size by an estimated 160 lines and improving consistency across agents.

- [ ] Create `.claude/skills/spec-reader.md` with YAML frontmatter (name, description, tools: Read/Glob/Grep) and instructions to read all specs and output structured JSON summary (WHY: "read all specs" is duplicated across research, plan, and review prompts; a skill makes it consistent and testable)
- [ ] Create `.claude/skills/validation-suite.md` with project-type detection (package.json, Makefile, automaton.sh) and structured pass/fail output (WHY: inline validation instructions differ between build and review prompts; a unified skill ensures the same checks run everywhere)
- [ ] Create `.claude/skills/context-loader.md` to load and assemble context from AGENTS.md, IMPLEMENTATION_PLAN.md, and recent git history (WHY: "Phase 0: Load Context" is duplicated across all four phase prompts at ~25 lines each; one skill replaces ~100 lines of prose)
- [ ] Create `.claude/skills/plan-updater.md` for updating IMPLEMENTATION_PLAN.md task checkboxes and adding new tasks (WHY: plan update instructions are embedded in the build prompt; extracting to a skill makes the pattern reusable by the review agent for adding fix tasks)
- [ ] Create `.claude/skills/self-analysis.md` for analyzing automaton.sh in self-build mode (function index, modification targets, dependencies) (WHY: self-build codebase analysis from spec-24 is a recurring pattern that benefits from skill encapsulation and versioning)
- [ ] Add `skills` field references to agent definitions (spec-27) and replace Phase 0 instructions in all `PROMPT_*.md` with skill references (WHY: prompt size reduction of ~160 lines frees context window capacity for actual work)

### Spec 37 — Session Bootstrap (depends on specs 33, 29, 34)

Bootstrap eliminates the first N tool calls of every iteration that were spent reading AGENTS.md, IMPLEMENTATION_PLAN.md, specs, and state files.

- [ ] Create `.automaton/init.sh` bootstrap script that assembles JSON manifest (project state, next task, recent commits, budget, modified files, high-confidence learnings) from file reads and git commands (WHY: context assembly by shell script is 100x faster than agent tool calls; saves 18-48K input tokens per iteration)
- [ ] Integrate bootstrap into `run_agent()` in `automaton.sh`: call `init.sh` before each agent invocation, inject manifest into `<dynamic_context>` section (WHY: pre-assembled context arrives in the prompt, so the agent starts working immediately instead of spending turns reading files)
- [ ] Replace "Phase 0: Load Context" instructions in all `PROMPT_*.md` files with bootstrap manifest placeholder (`{{BOOTSTRAP_MANIFEST}}`) and note that agents do NOT need to read state files themselves (WHY: Phase 0 instructions become dead weight when bootstrap provides the data; removing them reclaims prompt space)
- [ ] Implement bootstrap failure handling: log error, fall back to empty `<dynamic_context>` and legacy agent-driven file reading, do NOT abort the iteration (WHY: bootstrap is an optimization, not a requirement; graceful degradation ensures iterations always proceed)
- [ ] Track cold start token savings (`bootstrap_tokens_saved`, `bootstrap_time_ms`) in budget history and enforce 2-second performance target with warning on overrun (WHY: quantifying savings validates the bootstrap approach; the 2-second target ensures bootstrap does not become a bottleneck)
- [ ] Add `execution.bootstrap_enabled` (default true), `execution.bootstrap_script`, and `execution.bootstrap_timeout_ms` to `automaton.config.json` (WHY: users who prefer agent-driven context loading can disable bootstrap; configurable script path supports custom bootstrap implementations)

## Tier 4: Capstone (Depends on Tier 3)

### Spec 28 — Agent Teams Integration (depends on specs 27, 31)

Agent Teams provides a native parallel execution backend as an alternative to automaton's bash-orchestrated tmux + worktree model, with self-claiming task lists and inter-agent messaging.

- [ ] Add `parallel.mode` config field with values `"automaton"` (default, current behavior), `"agent-teams"`, and `"hybrid"` (future) (WHY: multiple parallel backends let users choose between the proven bash model and the native Agent Teams API)
- [ ] Implement task list population: convert unchecked `IMPLEMENTATION_PLAN.md` tasks to Agent Teams shared task list format with dependency annotations (`<!-- depends: task-N -->`) mapped to blocked tasks (WHY: the shared task list replaces wave-based assignment; teammates self-claim tasks instead of receiving pre-assigned work)
- [ ] Configure teammate spawning from `automaton-builder` agent definition (spec-27) with count from `parallel.max_builders`, permission mode from lead, and display mode from `parallel.teammate_display` (WHY: teammates use the same agent definitions as the wave-based builders, ensuring identical behavior regardless of parallel backend)
- [ ] Create `.claude/hooks/teammate-idle.sh` for `TeammateIdle` hook: check for unclaimed tasks, exit 2 to keep teammate working or exit 0 to allow idle (WHY: TeammateIdle replaces stall detection from spec-16's wave polling; prevents teammates from going idle while work remains)
- [ ] Implement Agent Teams environment setup: set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, validate Claude Code version supports Agent Teams, configure display mode (in-process or tmux) (WHY: Agent Teams requires an experimental flag; validation at startup prevents cryptic failures mid-build)
- [ ] Implement approximate budget tracking in agent-teams mode using `SubagentStart`/`SubagentStop` hooks from spec-31, with per-teammate attribution as aggregate divided by teammate count (WHY: Agent Teams does not expose per-teammate `stream-json` token usage; approximate tracking ensures budget limits are still enforced)
- [ ] Document Agent Teams limitations (no session resumption, task status lag, no nested teams, shared working tree conflict risk) and implement mitigations (save task list state for resume, post-build verification against git diff, file ownership hooks) (WHY: informed users can choose the right parallel mode for their project; mitigations reduce the impact of known limitations)
