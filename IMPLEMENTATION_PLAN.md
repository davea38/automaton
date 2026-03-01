# Implementation Plan

Specs 1-37 are fully implemented in `automaton.sh` (5249 lines, 99 functions). All templates are synced, `.gitignore` is committed, and `PROMPT_self_research.md` is registered in the scaffolder.

Eight new specs (38-45) introduce autonomous evolution capabilities: an idea garden for managing improvement proposals, stigmergic signal coordination, multi-agent quorum voting, growth metrics tracking, constitutional governance, safety and reversibility mechanisms, a 5-phase evolution loop, and a human interface for observation and control. The specs are organized into five implementation tiers based on their dependency graph.

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

## Tier 1: Foundation (No Dependencies Among New Specs) — COMPLETE

### Spec 29 — Prompt Engineering for Claude 4.6 — COMPLETE

- [x] Remove "Ultrathink", "think deeply", and explicit `budget_tokens` directives from all `PROMPT_*.md` files (WHY: Claude 4.6 uses adaptive thinking)
- [x] Replace fixed subagent cardinality instructions with outcome-oriented scaling directives (WHY: Claude 4.6 decides subagent count adaptively)
- [x] Restructure `PROMPT_research.md` with XML-tagged sections and add "do NOT over-explore" guardrail (WHY: XML tags provide semantic boundaries)
- [x] Restructure `PROMPT_plan.md` with XML-tagged sections and replace "be exhaustive" with "cover all tasks needed, no more" (WHY: static-first ordering for caching)
- [x] Restructure `PROMPT_build.md` with XML-tagged sections, replace `<promise>COMPLETE</promise>` with `<result status="complete">`, and add anti-overengineering guardrails (WHY: structured result signaling)
- [x] Restructure `PROMPT_review.md` with XML-tagged sections, remove "be thorough", add "focus on correctness, not style" (WHY: prevent review over-flagging)
- [x] Add `<!-- DYNAMIC CONTEXT BELOW -->` separator and parallel tool calling directive to all `PROMPT_*.md` files (WHY: defines cache boundary for spec-30)
- [x] Update `run_agent()` to inject dynamic context after the static separator (WHY: prevents cache invalidation)

### Spec 34 — Structured State via Git — COMPLETE

- [x] Restructure `.gitignore` to split ephemeral and persistent `.automaton/` state (WHY: persistent state survives directory loss)
- [x] Create `.automaton/learnings.json` with structured schema and CRUD functions (WHY: structured JSON enables querying)
- [x] Implement AGENTS.md generation from `learnings.json` at phase transitions (WHY: prevents content drift)
- [x] Create `.automaton/run-summaries/` with per-run summary JSON (WHY: audit trail and resume context)
- [x] Create `.automaton/budget-history.json` for cross-run cost data (WHY: budget trends require persistent history)
- [x] Implement resume recovery from persistent state (WHY: enables resume from git-tracked state)
- [x] Add persistent state commit protocol at phase transitions (WHY: periodic checkpoints prevent data loss)

## Tier 2: Core Features — COMPLETE

### Spec 30 — Prompt Caching Optimization — COMPLETE

- [x] Add `<!-- STATIC CONTENT -->` markers to all `PROMPT_*.md` files (WHY: defines cache boundary)
- [x] Calculate cache hit ratio after every agent invocation (WHY: validates prompt assembly)
- [x] Emit warning when cache hit ratio drops below 50% (WHY: detects static prefix changes)
- [x] Ensure parallel builders share identical static prompt prefix (WHY: cache reuse across builders)
- [x] Move context summaries to after static prefix (WHY: prevents cache invalidation)
- [x] Add cache hit ratio to dashboard (WHY: visibility into cache performance)
- [x] Log message when static prefix below minimum cacheable threshold (WHY: user awareness of caching status)

### Spec 33 — Context Window Lifecycle — COMPLETE

- [x] Define context utilization ceilings per phase (WHY: prevents performance degradation)
- [x] Add frequent-commit rule to `PROMPT_build.md` (WHY: prevents lost work from compaction)
- [x] Add compaction guidance to build and research prompts (WHY: proactive context management)
- [x] Implement auto-compaction detection (WHY: explains unexpected behavior)
- [x] Generate `.automaton/progress.txt` at each iteration (WHY: cross-context-window state sharing)
- [x] Track context utilization per iteration (WHY: informs future task sizing)

### Spec 35 — Max Plan Optimization — COMPLETE

- [x] Add rate_limits_presets with api_default and max_plan profiles (WHY: Max Plan has higher rate limits)
- [x] Implement daily budget pacing (WHY: prevents weekly allowance exhaustion)
- [x] Add `--budget-check` CLI flag (WHY: pre-run budget visibility)
- [x] Apply higher parallel defaults in allowance mode (WHY: free parallelism)
- [x] Create `~/.automaton/allowance.json` for cross-project tracking (WHY: shared allowance management)
- [x] Add `max_plan_preset` config shortcut (WHY: one-line Max Plan config)
- [x] Display weekly summary on resume and implement graceful exhaustion (WHY: visibility and data safety)

### Spec 27 — Native Subagent Definitions — COMPLETE

- [x] Create `.claude/agents/` with five agent definition files (WHY: structured agent management)
- [x] Write YAML frontmatter for each agent (WHY: tool scoping and model selection)
- [x] Migrate static prompt content into agent definitions (WHY: native system prompt)
- [x] Add `isolation: worktree` to build agent (WHY: parallel build isolation)
- [x] Configure `memory: project` for all agents (WHY: persistent per-agent memory)
- [x] Add `agents.use_native_definitions` flag (WHY: gradual migration)

### Spec 36 — Test-First Build Strategy — COMPLETE

- [x] Add test scaffold sub-phase to build loop (WHY: tests verify intended behavior)
- [x] Add test annotation rules to `PROMPT_plan.md` (WHY: connects tasks to tests)
- [x] Add test-first discipline rules to `PROMPT_build.md` (WHY: catches regressions)
- [x] Create `tests/test_helpers.sh` with assertion functions (WHY: lightweight bash testing)
- [x] Add test-driven verification priority to `PROMPT_review.md` (WHY: objective quality signals)
- [x] Track test coverage metric in run summaries (WHY: reveals testing gaps)
- [x] Add `execution.test_first_enabled` and `execution.test_framework` config (WHY: user configurability)

## Tier 3: Integration Features — COMPLETE

### Spec 31 — Hooks Integration — COMPLETE

- [x] Create `.claude/hooks/enforce-file-ownership.sh` (WHY: mandatory file ownership enforcement)
- [x] Create `.claude/hooks/self-build-guard.sh` (WHY: prevents orchestrator corruption)
- [x] Create `.claude/hooks/capture-test-results.sh` (WHY: structured test history)
- [x] Create `.claude/hooks/builder-on-stop.sh` (WHY: guaranteed cleanup)
- [x] Create `.claude/hooks/track-subagent-start.sh` and `track-subagent-stop.sh` (WHY: per-subagent token tracking)
- [x] Create `.claude/hooks/task-quality-gate.sh` (WHY: prevents incomplete task completion)
- [x] Configure hook locations in settings (WHY: dynamic vs stable hooks)
- [x] Ensure all hooks complete in under 2 seconds and are idempotent (WHY: performance and reliability)

### Spec 32 — Skills Library — COMPLETE

- [x] Create `.claude/skills/spec-reader.md` (WHY: reusable spec reading)
- [x] Create `.claude/skills/validation-suite.md` (WHY: unified validation)
- [x] Create `.claude/skills/context-loader.md` (WHY: replace 100 lines of Phase 0 prose)
- [x] Create `.claude/skills/plan-updater.md` (WHY: reusable plan update pattern)
- [x] Create `.claude/skills/self-analysis.md` (WHY: encapsulated self-build analysis)
- [x] Add `skills` references to agent definitions and replace Phase 0 instructions (WHY: prompt size reduction)

### Spec 37 — Session Bootstrap — COMPLETE

- [x] Create `.automaton/init.sh` bootstrap script (WHY: 100x faster context assembly)
- [x] Integrate bootstrap into `run_agent()` (WHY: agents start working immediately)
- [x] Replace Phase 0 instructions with bootstrap manifest placeholder (WHY: reclaim prompt space)
- [x] Implement bootstrap failure handling (WHY: graceful degradation)
- [x] Track cold start token savings (WHY: quantify optimization value)
- [x] Add bootstrap config options (WHY: user configurability)

## Tier 4: Capstone — COMPLETE

### Spec 28 — Agent Teams Integration — COMPLETE

- [x] Add `parallel.mode` config field (WHY: multiple parallel backend options)
- [x] Implement task list population from IMPLEMENTATION_PLAN.md (WHY: self-claiming task lists)
- [x] Configure teammate spawning from agent definitions (WHY: consistent behavior)
- [x] Create `.claude/hooks/teammate-idle.sh` (WHY: prevent premature idling)
- [x] Implement Agent Teams environment setup (WHY: prevent cryptic failures)
- [x] Implement approximate budget tracking for agent-teams mode (WHY: budget enforcement)
- [x] Document limitations and implement mitigations (WHY: informed mode selection)

---

## Tier 5: Evolution Foundation (Specs 38, 42) — COMPLETE

These two specs have no dependencies on other new specs. They provide the data structures (garden ideas and stigmergic signals) that all higher-tier specs build upon.

### Spec 38 — Idea Garden

#### 38.1 Garden Data Layer

- [x] Add `garden` configuration section to `automaton.config.json` with all fields (enabled, seed_ttl_days, sprout_ttl_days, sprout_threshold, bloom_threshold, bloom_priority_threshold, signal_seed_threshold, max_active_ideas, auto_seed_from_metrics, auto_seed_from_signals) (WHY: configuration must exist before any garden functions can read thresholds and feature flags) <!-- test: tests/test_garden_config.sh -->

- [x] Update `.gitignore` to add `.automaton/garden/` as persistent git-tracked state and `.automaton/garden/_index.json` comment (WHY: garden ideas are persistent state that must survive directory loss; the index is regenerated but tracked for bootstrap) <!-- test: none -->

- [x] Implement `_garden_plant_seed()` in `automaton.sh` that creates a new idea JSON file in `.automaton/garden/` with the full schema (id, title, description, stage=seed, origin, evidence=[], tags, priority=0, estimated_complexity, related_specs, related_signals, related_ideas, stage_history, vote_id=null, implementation=null, updated_at) and auto-increments the ID from `_index.json` (WHY: this is the primary write operation — every idea enters the garden as a seed, and the schema must be complete from the start to avoid migration later) <!-- test: tests/test_garden_plant.sh -->

- [x] Implement `_garden_water()` in `automaton.sh` that adds an evidence item to an existing idea, updates `updated_at`, and calls `_garden_advance_stage()` if thresholds are met (WHY: evidence accumulation is the mechanism that moves ideas from seed to sprout to bloom — without watering, ideas stay inert) <!-- test: tests/test_garden_water.sh -->

- [x] Implement `_garden_advance_stage()` in `automaton.sh` that transitions an idea to the next lifecycle stage (seed->sprout->bloom->harvest), validates threshold requirements (sprout_threshold evidence items for seed->sprout, bloom_threshold + bloom_priority_threshold for sprout->bloom), records stage_history entry, and supports a `force` parameter for human promotion (WHY: stage transitions enforce the maturation model — ideas must accumulate evidence before being evaluated) <!-- test: tests/test_garden_advance.sh -->

- [x] Implement `_garden_wilt()` in `automaton.sh` that moves an idea to the wilt stage with a reason, records the stage_history entry, and updates the index (WHY: wilting is how the garden prunes rejected, expired, or rolled-back ideas while preserving their record for audit) <!-- test: tests/test_garden_wilt.sh -->

#### 38.2 Garden Computation and Maintenance

- [x] Implement `_garden_recompute_priorities()` in `automaton.sh` using the 5-component formula: `(evidence_weight*30) + (signal_strength*25) + (metric_severity*25) + (age_bonus*10) + (human_boost*10)` for all active (non-wilted, non-harvested) ideas (WHY: priority scores drive which ideas bloom first — the formula balances evidence, signals, metrics, age, and human input to surface the most actionable ideas) <!-- test: tests/test_garden_priority.sh -->

- [x] Implement `_garden_rebuild_index()` in `automaton.sh` that regenerates `_index.json` from all idea files with total counts, by_stage breakdown, bloom_candidates list sorted by priority, recent_activity, next_id, and updated_at (WHY: the index provides a lightweight summary for bootstrap and CLI display without reading every idea file) <!-- test: tests/test_garden_index.sh -->

- [x] Implement `_garden_prune_expired()` in `automaton.sh` that auto-wilts seeds older than `seed_ttl_days` and sprouts older than `sprout_ttl_days` that have received no new evidence (WHY: TTL-based pruning prevents the garden from filling up with stale ideas that will never mature) <!-- test: tests/test_garden_prune.sh -->

- [x] Implement `_garden_find_duplicates()` in `automaton.sh` that checks for existing non-wilted ideas with matching tags before creating a new seed, returning the existing idea ID if found (WHY: duplicate detection prevents the same metric breach or signal from spawning multiple identical ideas — the existing idea gets watered instead) <!-- test: tests/test_garden_duplicates.sh -->

- [x] Implement `_garden_get_bloom_candidates()` in `automaton.sh` that returns ideas eligible for bloom transition (meeting evidence and priority thresholds) sorted by priority descending (WHY: the EVALUATE phase needs a ranked list of ideas ready for quorum voting — this function is the gateway from garden to quorum) <!-- test: tests/test_garden_bloom.sh -->

#### 38.3 Garden Integration

- [x] Add garden directory initialization to `initialize_state()` in `automaton.sh` that creates `.automaton/garden/` and an empty `_index.json` when `garden.enabled` is true (WHY: the garden directory must exist before any garden operations can write idea files) <!-- test: tests/test_garden_init.sh -->

- [x] Add `garden_summary` field to the bootstrap manifest in `.automaton/init.sh` sourced from `_index.json` (total, seeds, sprouts, blooms, top_bloom) (WHY: evolution agents need garden state in their prompt context without reading individual idea files) <!-- test: tests/test_garden_bootstrap.sh -->

- [x] Implement backward compatibility: when `garden.enabled` is false, skip all garden operations and fall back to `.automaton/backlog.md` behavior from spec-25 (WHY: existing users who do not want the garden can continue using the flat backlog without any breakage) <!-- test: tests/test_garden_config.sh -->

### Spec 42 — Stigmergic Coordination

#### 42.1 Signal Data Layer

- [x] Add `stigmergy` configuration section to `automaton.config.json` with all fields (enabled, initial_strength, reinforce_increment, decay_floor, match_threshold, max_signals) (WHY: signal behavior is tunable — initial strength, decay rates, and matching sensitivity need configuration before any signals can be emitted) <!-- test: tests/test_signal_config.sh -->

- [x] Update `.gitignore` to add `.automaton/signals.json` as persistent git-tracked state (WHY: signals accumulate evidence across runs and must survive directory loss to maintain coordination history) <!-- test: none -->

- [x] Implement `_signal_emit()` in `automaton.sh` that creates a new signal in `.automaton/signals.json` with full schema (id, type, title, description, strength=initial_strength, decay_rate from type defaults, observations[], related_ideas, created_at, last_reinforced_at, last_decayed_at), or reinforces an existing signal if `_signal_find_match()` returns a match (WHY: emission is the core write operation — agents leave persistent markers in the environment that guide future agents) <!-- test: tests/test_signal_emit.sh -->

- [x] Implement `_signal_reinforce()` in `automaton.sh` that adds an observation to an existing signal and increases strength by `reinforce_increment` capped at 1.0 (WHY: reinforcement is the mechanism that makes repeated observations louder — it converts multiple weak observations into a strong signal) <!-- test: tests/test_signal_reinforce.sh -->

- [x] Implement `_signal_find_match()` in `automaton.sh` using word-overlap similarity (extract key terms from title+description, compare against same-type signals, return match if overlap >= `match_threshold`) (WHY: tag-based matching prevents duplicate signals for the same observation while allowing distinct signals for different issues) <!-- test: tests/test_signal_match.sh -->

#### 42.2 Signal Lifecycle and Queries

- [x] Implement `_signal_decay_all()` in `automaton.sh` that reduces all signal strengths by their `decay_rate` and removes signals below `decay_floor` (WHY: decay ensures one-off observations fade naturally while persistent issues remain visible — this is the self-regulating cleanup mechanism) <!-- test: tests/test_signal_decay.sh -->

- [x] Implement `_signal_prune()` in `automaton.sh` that enforces `max_signals` by removing the weakest signals when the limit is exceeded (WHY: unbounded signal growth would degrade performance and dilute attention — pruning keeps the signal space focused on the strongest observations) <!-- test: tests/test_signal_prune.sh -->

- [x] Implement query functions in `automaton.sh`: `_signal_get_strong()` (strength >= threshold), `_signal_get_by_type()` (filter by type), `_signal_get_active()` (strength > decay_floor), `_signal_get_unlinked()` (no related garden ideas) (WHY: the REFLECT phase queries these functions to identify patterns that need attention — unlinked strong signals are candidates for auto-seeding garden ideas) <!-- test: tests/test_signal_query.sh -->

#### 42.3 Signal Integration

- [x] Initialize `.automaton/signals.json` with empty structure on first signal emission (not during initialization) (WHY: the spec requires lazy initialization — the file is created when first needed, not preemptively, to avoid empty state files cluttering the repo) <!-- test: tests/test_signal_emit.sh -->

- [x] Add `active_signals` field to the bootstrap manifest in `.automaton/init.sh` (total, strong count, strongest signal, unlinked_count) (WHY: evolution agents need signal awareness in their prompt context to inform reflection and ideation phases) <!-- test: tests/test_signal_bootstrap.sh -->

- [x] Add bidirectional linking between signals and garden ideas: update signal `related_ideas` when an idea is seeded from a signal, update idea `related_signals` when a signal triggers seeding (WHY: traceability between signals and ideas enables the evolution loop to understand why an idea exists and which observations support it) <!-- test: tests/test_signal_garden_link.sh -->

---

## Tier 6: Evolution Core (Specs 39, 43) — Depends on Tier 5

These specs build on the garden and signals to add collective decision-making and quantitative self-awareness.

### Spec 39 — Agent Quorum

#### 39.1 Voter Definitions

- [x] Create 5 voter agent definition files in `.claude/agents/`: `voter-conservative.md`, `voter-ambitious.md`, `voter-efficiency.md`, `voter-quality.md`, `voter-advocate.md` with their respective perspectives, read-only constraints, and JSON output format (WHY: each voter brings a distinct evaluation lens — conservative for risk, ambitious for growth, efficiency for cost, quality for reliability, advocate for user experience — creating balanced collective judgment) <!-- test: tests/test_quorum_voters.sh -->

#### 39.2 Quorum Mechanics

- [x] Add `quorum` configuration section to `automaton.config.json` with all fields (enabled, voters, thresholds for seed_promotion/bloom_implementation/constitutional_amendment/emergency_override, max_tokens_per_voter, max_cost_per_cycle_usd, rejection_cooldown_cycles, model) (WHY: quorum thresholds are the governance dial — too low and bad ideas pass, too high and nothing advances; configuration enables tuning) <!-- test: tests/test_quorum_config.sh -->

- [x] Update `.gitignore` to add `.automaton/votes/` as persistent git-tracked state (WHY: vote records form the audit trail of every autonomous decision — they must persist for transparency and debugging) <!-- test: none -->

- [x] Implement `_quorum_invoke_voter()` in `automaton.sh` that invokes a single voter agent with the proposal JSON using `claude --agent` with Sonnet model, `--no-tools`, and `--max-tokens` limit, and parses the JSON vote response (handling invalid output as abstain) (WHY: lightweight read-only Sonnet invocations keep quorum costs predictable while each voter's perspective ensures balanced evaluation) <!-- test: tests/test_quorum_invoke.sh -->

- [x] Implement `_quorum_tally()` in `automaton.sh` that counts approve/reject/abstain votes, reduces denominator for abstentions, compares against the threshold for the decision type, merges conditions from approving voters, and returns the result (WHY: the tally algorithm is the core governance mechanism — abstention handling and threshold comparison determine whether ideas advance) <!-- test: tests/test_quorum_tally.sh -->

- [x] Implement `_quorum_evaluate_bloom()` in `automaton.sh` that selects the highest-priority bloom candidate, assembles proposal context (idea details, metrics, signals, bootstrap manifest), invokes all 5 voters sequentially, tallies votes, writes a vote record to `.automaton/votes/vote-{NNN}.json`, and advances/wilts the idea based on the result (WHY: this is the end-to-end evaluation flow — it connects garden bloom candidates to quorum decisions and records the full audit trail) <!-- test: tests/test_quorum_evaluate.sh -->

- [x] Implement `_quorum_check_budget()` in `automaton.sh` that tracks cumulative quorum tokens per cycle and skips remaining candidates when `max_cost_per_cycle_usd` is exceeded (WHY: quorum invocations cost real tokens — budget enforcement prevents runaway voting costs from consuming the evolution cycle's budget) <!-- test: tests/test_quorum_budget.sh -->

#### 39.3 Quorum Integration

- [x] Implement rejection cooldown: check vote history before evaluating a bloom candidate and skip ideas wilted by quorum within the last `rejection_cooldown_cycles` cycles (WHY: cooldown prevents the same idea from being re-evaluated every cycle when nothing has changed — it must accumulate new evidence before another attempt) <!-- test: tests/test_quorum_cooldown.sh -->

- [x] Implement quorum-disabled fallback: when `quorum.enabled` is false, auto-approve bloom candidates with a warning log (WHY: users who want faster iteration can bypass voting, but the warning ensures they know decisions are unreviewed) <!-- test: tests/test_quorum_config.sh -->

### Spec 43 — Growth Metrics

#### 43.1 Metrics Data Layer

- [x] Add `metrics` configuration section to `automaton.config.json` with all fields (enabled, trend_window, degradation_alert_threshold, snapshot_retention) (WHY: trend analysis window and alert thresholds need configuration before snapshots can be analyzed) <!-- test: tests/test_metrics_config.sh -->

- [x] Update `.gitignore` to add `.automaton/evolution-metrics.json` as persistent git-tracked state (WHY: metrics snapshots accumulate across cycles and must persist for trend analysis and historical comparison) <!-- test: none -->

- [x] Implement `_metrics_snapshot()` in `automaton.sh` that collects all 5 metric categories — capability (line/function/spec/test counts from source files), efficiency (tokens/task, cache ratio, stall rate from run metadata), quality (test pass rate, rollbacks, syntax errors from results files), innovation (garden/signal/vote counts from their state files), health (budget utilization, convergence risk, circuit breakers, error rate) — and appends the snapshot to `.automaton/evolution-metrics.json` (WHY: snapshots are the raw data for all trend analysis — each data point captures the system's complete quantitative state at a moment in time) <!-- test: tests/test_metrics_snapshot.sh -->

- [x] Implement `_metrics_set_baselines()` in `automaton.sh` that records the first snapshot's values as baselines in the metrics file, and `_metrics_get_latest()` that returns the most recent snapshot (WHY: baselines establish the reference point for all improvement/regression comparisons — without them, there is no way to know if the system is getting better or worse) <!-- test: tests/test_metrics_baselines.sh -->

#### 43.2 Metrics Analysis

- [x] Implement `_metrics_analyze_trends()` in `automaton.sh` that examines the last N snapshots (configurable trend_window) and for each metric computes direction (improving/degrading/stable), rate of change, and alert status when degrading for `degradation_alert_threshold` consecutive cycles (WHY: trend analysis drives the REFLECT phase — degrading trends trigger signal emission and idea auto-seeding, which is how the system identifies what to fix next) <!-- test: tests/test_metrics_trends.sh -->

- [x] Implement `_metrics_compare()` in `automaton.sh` that takes two snapshots (pre-cycle and post-cycle) and computes per-metric deltas with direction indicators (WHY: before/after comparison is how the OBSERVE phase determines whether an implementation helped, hurt, or had no effect — this is the feedback loop that validates evolution decisions) <!-- test: tests/test_metrics_compare.sh -->

#### 43.3 Metrics Display and Integration

- [x] Implement `_metrics_display_health()` in `automaton.sh` that renders the terminal health dashboard with all 5 categories, current/baseline/trend columns, bar charts for utilization, and trend indicators (WHY: the `--health` dashboard is the primary human interface for understanding the system's quantitative state at a glance) <!-- test: tests/test_metrics_display.sh -->

- [x] Add `--health` CLI flag to argument parsing in `automaton.sh` that calls `_metrics_display_health()` and exits (WHY: `--health` is a standalone observation command that works without starting an evolution cycle) <!-- test: tests/test_metrics_display.sh -->

- [x] Add `metrics_trend` field to the bootstrap manifest in `.automaton/init.sh` (improving metrics list, degrading list, alerts, cycles_completed, last_harvest_cycle) (WHY: evolution agents need metrics trend awareness to inform REFLECT and OBSERVE decisions without re-analyzing raw data) <!-- test: tests/test_metrics_bootstrap.sh -->

- [x] Enforce snapshot retention by pruning oldest snapshots when count exceeds `snapshot_retention` (WHY: unbounded snapshot accumulation would grow the metrics file indefinitely — retention limits keep it manageable while preserving sufficient history for trend analysis) <!-- test: tests/test_metrics_snapshot.sh -->

---

## Tier 7: Evolution Governance (Specs 40, 45) — Depends on Tier 6

These specs add the safety constraints and governance framework that the evolution loop requires before it can autonomously modify code.

### Spec 40 — Constitutional Principles

#### 40.1 Constitution Creation

- [x] Implement `_constitution_create_default()` in `automaton.sh` that writes `.automaton/constitution.md` with the 8 default articles (Safety First, Human Sovereignty, Measurable Progress, Transparency, Budget Discipline, Incremental Growth, Test Coverage, Amendment Protocol) and their protection levels, and initializes `.automaton/constitution-history.json` with empty amendments array (WHY: the constitution is the governance foundation — it must exist with all 8 articles before any evolution cycle can run its compliance check) <!-- test: tests/test_constitution_create.sh -->

- [x] Update `.gitignore` to add `.automaton/constitution.md` and `.automaton/constitution-history.json` as persistent git-tracked state (WHY: the constitution and its amendment history are the most important persistent state — losing them would remove all governance constraints from the evolution loop) <!-- test: none -->

#### 40.2 Constitutional Compliance

- [x] Implement `_constitution_check()` in `automaton.sh` that validates a proposed diff against the constitution articles: safety preservation (Article I — no removal of protected functions or safety mechanisms), human control preservation (Article II — no removal of override/pause CLI flags), measurability (Article III — idea has metric target), scope limits (Article VI — files/lines within self_build limits), test coverage (Article VII — no test removal, new functions have tests), returning pass/warn/fail (WHY: the compliance check is the enforcement mechanism — without it, the constitution is advisory text; with it, articles I and II become inviolable constraints) <!-- test: tests/test_constitution_check.sh -->

- [x] Implement immutable constraint enforcement in code: `unanimous` articles cannot have their protection level reduced, Article VIII cannot be removed or weakened, enforced in `_constitution_validate_amendment()` independently of the constitution text (WHY: code-enforced immutability prevents the constitution from being amended to remove its own safety guarantees — this is the meta-safety that protects the safety system) <!-- test: tests/test_constitution_immutable.sh -->

#### 40.3 Constitutional Amendment and Agent

- [x] Implement `_constitution_amend()` in `automaton.sh` that applies an approved amendment to `constitution.md`, records before/after text in `constitution-history.json` with amendment_id, article, type, description, vote_id, proposed_by, and approved_at fields (WHY: amendments must be tracked with full audit trail so any governance change can be traced back to its vote and proposer) <!-- test: tests/test_constitution_amend.sh -->

- [x] Create `.claude/agents/evolve-constitution-checker.md` agent definition for deep compliance analysis when automated checks return `warn` (receives diff + constitution text, produces per-article compliance report) (WHY: some violations are subtle — a change might technically pass automated checks but violate the spirit of an article; the checker agent provides nuanced analysis for edge cases) <!-- test: tests/test_constitution_checker_agent.sh -->

- [x] Implement `_constitution_get_summary()` in `automaton.sh` that generates the summary object (articles count, version, key_constraints list) for the bootstrap manifest (WHY: evolution agents need constitution awareness in their prompt context to self-regulate their proposals) <!-- test: tests/test_constitution_create.sh -->

- [x] Add `constitution_summary` field to the bootstrap manifest in `.automaton/init.sh` (WHY: injecting the summary into agent prompts is cheaper than having each agent read the full constitution file) <!-- test: tests/test_constitution_bootstrap.sh -->

### Spec 45 — Safety and Reversibility

#### 45.1 Branch Isolation and Sandbox

- [x] Implement branch-based isolation for IMPLEMENT phase in `automaton.sh`: create `automaton/evolve-{cycle_id}-{idea_id}` branch at IMPLEMENT start, run all build iterations on the branch, and never directly modify the working branch (WHY: branch isolation guarantees that a failed evolution cycle has zero impact on the codebase — the worst case is an unmerged branch, never a corrupted working tree) <!-- test: tests/test_safety_branch.sh -->

- [x] Implement `_safety_sandbox_test()` in `automaton.sh` that runs the 4-step validation sequence on the evolution branch: syntax check (`bash -n`), smoke test (`--dry-run`), full test suite, and test pass rate comparison against pre-cycle baseline (WHY: sandbox testing catches regressions before they reach the working branch — each step is progressively more expensive, so early failures save time) <!-- test: tests/test_safety_sandbox.sh -->

#### 45.2 Circuit Breakers

- [x] Add `safety` configuration section to `automaton.config.json` with all fields (max_total_lines, max_total_functions, min_test_pass_rate, max_consecutive_failures, max_consecutive_regressions, preserve_failed_branches, preflight_enabled, sandbox_testing_enabled) (WHY: safety thresholds need configuration — different projects have different acceptable limits for complexity, test coverage, and failure tolerance) <!-- test: tests/test_safety_config.sh -->

- [x] Implement `_safety_check_breakers()`, `_safety_update_breaker()`, `_safety_any_breaker_tripped()`, and `_safety_reset_breakers()` in `automaton.sh` for the 5 circuit breakers (budget ceiling, error cascade at 3 failures, regression cascade at 2 regressions, complexity ceiling at line/function limits, test degradation below min pass rate), tracking state in `.automaton/evolution/circuit-breakers.json` (WHY: circuit breakers are the automatic safety net — they halt evolution before damage cascades, ensuring the system fails safe rather than fails dangerous) <!-- test: tests/test_safety_breakers.sh -->

#### 45.3 Rollback and Safety Guard

- [x] Implement `_safety_rollback()` in `automaton.sh` that switches back to the working branch, preserves the failed evolution branch for debugging, wilts the responsible idea, emits a `quality_concern` signal, logs to `self_modifications.json`, and increments circuit breaker counters (WHY: the rollback protocol is the recovery mechanism — it ensures every failure is recorded, signaled, and learned from while leaving the codebase untouched) <!-- test: tests/test_safety_rollback.sh -->

- [x] Implement `_safety_preflight()` in `automaton.sh` that validates clean working tree, test pass rate above minimum, constitution exists or can be created, sufficient budget for at least one cycle, and no tripped circuit breakers (WHY: preflight catches problems before the first cycle starts — running evolution with a dirty tree or failing tests would produce unreliable results) <!-- test: tests/test_safety_preflight.sh -->

- [x] Create `.claude/hooks/evolution-safety-guard.sh` that enforces branch isolation (commits only on evolution branches), constitutional compliance, and scope limits during evolution mode (WHY: the hook is a guaranteed enforcement mechanism that runs before every commit — even if the build agent ignores prompt instructions, the hook blocks invalid commits) <!-- test: tests/test_safety_guard_hook.sh -->

- [x] Register `evolution-safety-guard.sh` in `.claude/settings.json` hooks configuration (WHY: the hook must be registered in settings to be invoked by Claude Code before commits during evolution) <!-- test: none -->

- [x] Create `.claude/skills/rollback-executor.md` skill for guided manual rollback of a specific evolution cycle (WHY: when automatic rollback is insufficient — e.g., a merged change that was later found to be problematic — the human needs a guided process to cleanly undo a specific cycle's changes) <!-- test: tests/test_safety_rollback_skill.sh -->

- [x] Add `.automaton/evolution/` and `.automaton/evolution/circuit-breakers.json` to `.gitignore` as ephemeral state (WHY: per-cycle artifacts and circuit breaker state are ephemeral — they reset each evolution run; only the results persisted via garden, votes, and metrics matter across runs) <!-- test: none -->

---

## Tier 8: Evolution Engine (Spec 41) — Depends on Tier 7

This spec connects all the foundation (garden, signals), core (quorum, metrics), and governance (constitution, safety) components into the autonomous evolution loop.

### Spec 41 — Autonomous Evolution Loop

#### 41.1 CLI and Configuration

- [x] Add `--evolve` and `--cycles N` CLI flag parsing to `automaton.sh` argument parser, setting `ARG_EVOLVE=true` and `ARG_CYCLES=N`, with `--evolve` implying `--self` mode (WHY: `--evolve` is the entry point to autonomous evolution — it activates all evolution subsystems and sets self-build mode which is required for code modification) <!-- test: tests/test_evolve_cli.sh -->

- [x] Add `evolution` configuration section to `automaton.config.json` with all fields (enabled, max_cycles, max_cost_per_cycle_usd, convergence_threshold, idle_garden_threshold, branch_prefix, auto_merge, reflect_model, ideate_model, observe_model) (WHY: cycle budget, convergence detection, and model selection need configuration before the loop starts) <!-- test: tests/test_evolve_config.sh -->

- [x] Add `.automaton/evolution/` ephemeral directory creation to initialization and update `.gitignore` to exclude it (WHY: per-cycle artifacts like reflect.json and ideate.json are ephemeral working state — they do not need to persist across evolution runs) <!-- test: none -->

#### 41.2 Evolution Phases

- [x] Implement `_evolve_reflect()` in `automaton.sh` that invokes the REFLECT agent with metrics trends, active signals, garden state, and constitution summary as context; processes the agent's structured JSON output to emit signals, auto-seed garden ideas from metric thresholds, auto-seed from strong unlinked signals, prune expired garden items, and decay all signals; writes `reflect.json` to the cycle directory (WHY: REFLECT is the sensory phase — it turns raw data into actionable observations by identifying degrading metrics, recurring patterns, and unaddressed signals) <!-- test: tests/test_evolve_reflect.sh -->

- [x] Implement `_evolve_ideate()` in `automaton.sh` that invokes the IDEATE agent with the reflection summary and garden state; processes output to water existing sprouts, evaluate sprout-to-bloom transitions, create new ideas, link ideas to signals, and recompute priorities; writes `ideate.json` to the cycle directory (WHY: IDEATE is the creative phase — it enriches ideas with evidence and promotes the most supported ones toward evaluation) <!-- test: tests/test_evolve_ideate.sh -->

- [x] Implement `_evolve_evaluate()` in `automaton.sh` that selects the highest-priority bloom candidate, invokes `_quorum_evaluate_bloom()`, and writes `evaluate.json` to the cycle directory; skips to OBSERVE if no bloom candidates exist (WHY: EVALUATE is the governance phase — it prevents bad ideas from reaching implementation through collective judgment) <!-- test: tests/test_evolve_evaluate.sh -->

- [ ] Implement `_evolve_implement()` in `automaton.sh` that creates an evolution branch, generates an implementation plan from the approved idea, runs the standard build pipeline with self-build safety, runs review and constitutional compliance check, and writes `implement.json`; abandons the branch and wilts the idea if compliance fails (WHY: IMPLEMENT is the action phase — it converts an approved idea into actual code changes while enforcing all safety constraints from specs 22, 40, and 45) <!-- test: tests/test_evolve_implement.sh -->

- [ ] Implement `_evolve_observe()` in `automaton.sh` that takes a post-cycle metrics snapshot, compares against the pre-cycle snapshot, runs sandbox testing, and decides the outcome: harvest (merge branch, mark idea as harvested, emit promising_approach signal), wilt (rollback, emit quality_concern signal), or neutral (merge with attention_needed signal); writes `observe.json` (WHY: OBSERVE is the feedback phase — it validates whether the implementation actually improved the target metrics, closing the loop between intention and result) <!-- test: tests/test_evolve_observe.sh -->

#### 41.3 Evolution Loop Control

- [ ] Implement `_evolve_run_cycle()` in `automaton.sh` that orchestrates the 5-phase sequence (REFLECT, IDEATE, EVALUATE, IMPLEMENT, OBSERVE), manages per-cycle budget allocation, takes pre-cycle and post-cycle metrics snapshots, creates the cycle directory, and handles phase failures (WHY: the cycle runner is the main event loop — it sequences the phases, manages resources, and ensures each cycle is atomic) <!-- test: tests/test_evolve_cycle.sh -->

- [ ] Implement `_evolve_check_convergence()` in `automaton.sh` that detects convergence when `consecutive_no_improvement >= convergence_threshold` or no bloom candidates for `idle_garden_threshold` consecutive cycles (WHY: convergence detection prevents the loop from spinning indefinitely when there is nothing left to improve — it signals completion rather than wasting budget) <!-- test: tests/test_evolve_convergence.sh -->

- [ ] Implement `_evolve_check_budget()` in `automaton.sh` that calculates per-cycle budget as `min(max_cost_per_cycle_usd, remaining_allowance / estimated_remaining_cycles)` and enforces the budget ceiling breaker when exceeded (WHY: per-cycle budget prevents a single expensive cycle from consuming the entire evolution budget — it ensures the system can run multiple improvement cycles rather than exhausting resources on one) <!-- test: tests/test_evolve_budget.sh -->

- [ ] Implement resume support: `--evolve --resume` reads the last cycle directory, determines which phase was interrupted, and resumes from that phase (WHY: evolution runs can take hours and may be interrupted by network issues, budget exhaustion, or human intervention — resume prevents losing progress) <!-- test: tests/test_evolve_resume.sh -->

#### 41.4 Evolution Agents and Prompts

- [ ] Create 3 evolution agent definitions in `.claude/agents/`: `evolve-reflect.md` (Sonnet, read-only), `evolve-ideate.md` (Sonnet, read-only), `evolve-observe.md` (Sonnet, read-only) with structured JSON output format (WHY: dedicated agent definitions ensure consistent behavior — read-only access prevents agents from accidentally modifying state, and Sonnet model keeps costs low for non-build phases) <!-- test: tests/test_evolve_agents.sh -->

- [ ] Create 3 evolution prompt files: `PROMPT_evolve_reflect.md` (metrics analysis, signal emission format, auto-seed criteria), `PROMPT_evolve_ideate.md` (evidence evaluation, promotion criteria, priority scoring), `PROMPT_evolve_observe.md` (before/after comparison, harvest/wilt criteria, signal emission) following the spec-29 XML structure (WHY: structured prompts with XML sections ensure evolution agents produce parseable output that the orchestrator can act on deterministically) <!-- test: tests/test_evolve_prompts.sh -->

- [ ] Add evolution safety rules to `PROMPT_build.md` (build on evolution branch only) and evolution review guidelines to `PROMPT_review.md` (constitutional compliance verification) (WHY: existing build and review agents need awareness of the evolution context to enforce branch isolation and constitutional compliance during their standard workflows) <!-- test: none -->

---

## Tier 9: Evolution Interface (Spec 44) — Depends on Tier 8

This spec adds the human-facing commands that wrap all evolution subsystems in a usable CLI.

### Spec 44 — Human Interface

#### 44.1 Argument Parsing

- [ ] Add argument parsing for all 15 new CLI flags to `automaton.sh`: `--plant`, `--garden`, `--garden-detail`, `--water`, `--prune`, `--promote`, `--health` (already in spec-43 but connect here), `--inspect`, `--constitution`, `--amend`, `--override`, `--pause-evolution`, `--signals`, and connect `--evolve`/`--cycles` from spec-41 (WHY: argument parsing is the entry point for all human interaction — each flag must be correctly parsed with its arguments before any display or action function can be invoked) <!-- test: tests/test_cli_args.sh -->

#### 44.2 Display Functions

- [ ] Implement `_display_garden()` in `automaton.sh` that renders a formatted table of all non-wilted ideas sorted by stage (bloom first) then priority, with ID, stage, priority, title, and age columns (WHY: the garden table is the primary view into the evolution pipeline — the human needs to see at a glance what ideas exist and which are closest to implementation) <!-- test: tests/test_display_garden.sh -->

- [ ] Implement `_display_garden_detail()` in `automaton.sh` that renders full details for a single idea including description, evidence list with timestamps, related specs/signals, stage history, and vote status (WHY: detail view lets the human evaluate whether an idea has sufficient evidence and understand its full history before deciding to water, promote, or prune it) <!-- test: tests/test_display_garden_detail.sh -->

- [ ] Implement `_display_signals()` in `automaton.sh` that renders a formatted table of active signals with ID, type, strength, title, observation count, and linked idea status, plus summary counts of unlinked and strong signals (WHY: the signals view shows what the system is "noticing" — unlinked signals are opportunities for the human to plant related ideas) <!-- test: tests/test_display_signals.sh -->

- [ ] Implement `_display_vote()` in `automaton.sh` that renders a vote record with per-voter breakdown (vote, confidence, risk, reasoning), tally result, merged conditions, and cost — accepting either a vote ID or idea ID (WHY: vote inspection lets the human understand why an idea was approved or rejected and what conditions were set) <!-- test: tests/test_display_vote.sh -->

- [ ] Implement `_display_constitution()` in `automaton.sh` that renders the constitution article summary with version, amendment count, and per-article protection levels (WHY: the constitution view provides a quick overview of governance without reading the full markdown file) <!-- test: tests/test_display_constitution.sh -->

#### 44.3 Action Functions

- [ ] Implement `_cli_plant()` in `automaton.sh` that calls `_garden_plant_seed()` with `origin.type="human"` and displays the result including the assigned ID, priority (with human boost), and guidance to water the idea (WHY: human-planted seeds get a priority boost and need clear feedback so the human knows what to do next) <!-- test: tests/test_cli_plant.sh -->

- [ ] Implement `_cli_water()` in `automaton.sh` that calls `_garden_water()` with the provided evidence, displays updated evidence count and priority, and reports any stage advancement that occurred (WHY: watering feedback must show the impact — did the evidence push the idea to the next stage? how did priority change?) <!-- test: tests/test_cli_water.sh -->

- [ ] Implement `_cli_prune()` in `automaton.sh` that calls `_garden_wilt()` with the provided reason and displays confirmation (WHY: pruning is a destructive action — clear confirmation with the idea title and reason prevents accidental deletions) <!-- test: tests/test_cli_prune.sh -->

- [ ] Implement `_cli_promote()` in `automaton.sh` that calls `_garden_advance_stage()` with `force=true` to bypass thresholds and displays the new stage (WHY: human promotion is the mechanism for Article II sovereignty — the human can override the normal maturation process when they know an idea is ready) <!-- test: tests/test_cli_promote.sh -->

- [ ] Implement `_cli_amend()` in `automaton.sh` that guides the human through the amendment process: select article, show current text, accept proposed change, create a garden idea tagged `constitutional`, and display next steps (WHY: constitutional amendments need a guided workflow because they affect governance — the human must see the current text and understand the quorum requirement before proceeding) <!-- test: tests/test_cli_amend.sh -->

- [ ] Implement `_cli_override()` in `automaton.sh` that lists recently rejected ideas, accepts an override selection with confirmation, re-promotes the idea to bloom, and logs the override in the vote record and constitution history (WHY: overrides implement Article II sovereignty — they must be auditable with full trail so the system can learn from human corrections) <!-- test: tests/test_cli_override.sh -->

- [ ] Implement `_cli_pause()` in `automaton.sh` that writes `.automaton/evolution/pause` flag file and displays confirmation message (WHY: pause is the non-destructive way to halt evolution — it lets the current phase complete and saves state for resume, unlike Ctrl+C which may interrupt mid-phase) <!-- test: tests/test_cli_pause.sh -->

#### 44.4 Skills and Help

- [ ] Create 4 skill files in `.claude/skills/`: `garden-tender.md` (guided garden review), `constitutional-review.md` (guided constitution review and amendments), `signal-reader.md` (guided signal interpretation), `metrics-analyzer.md` (guided metrics analysis and trend interpretation) (WHY: skills provide higher-level guided workflows beyond what individual CLI commands offer — they help the human make informed decisions about garden tending, governance, and system health) <!-- test: tests/test_cli_skills.sh -->

- [ ] Update `_show_help()` in `automaton.sh` to include all new commands organized by category (Standard Mode, Evolution Mode, Garden, Observation, Governance) (WHY: discoverable help text is essential — users who do not know about `--garden` or `--health` cannot use the evolution interface effectively) <!-- test: tests/test_cli_help.sh -->
