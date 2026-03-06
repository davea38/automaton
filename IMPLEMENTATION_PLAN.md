# Implementation Plan

Specs 1-58 are fully implemented across `automaton.sh` (1,390 lines) and 17 library modules in `lib/` (15,797 lines), totaling 17,187 lines. The codebase was refactored from a monolithic `automaton.sh` into a modular architecture with dependency-ordered `source` loading. There are 110 test files covering all implemented specs.

Spec 59 (Requirements Wizard) is partially implemented: the `requirements_wizard()` function, CLI flags, Gate 1 integration, and `PROMPT_wizard.md` all exist, but test coverage and scaffolder registration are missing.

The `templates/` directory is out of sync with the modular refactor — the template `automaton.sh` is still the old 5,249-line monolith. The `lib/` directory is untracked in git.

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

- [x] Remove "Ultrathink", "think deeply", and explicit `budget_tokens` directives from all `PROMPT_*.md` files (WHY: Claude 4.6 uses adaptive thinking) <!-- test: none -->
- [x] Replace fixed subagent cardinality instructions with outcome-oriented scaling directives (WHY: Claude 4.6 decides subagent count adaptively) <!-- test: none -->
- [x] Restructure `PROMPT_research.md` with XML-tagged sections and add "do NOT over-explore" guardrail (WHY: XML tags provide semantic boundaries) <!-- test: none -->
- [x] Restructure `PROMPT_plan.md` with XML-tagged sections and replace "be exhaustive" with "cover all tasks needed, no more" (WHY: static-first ordering for caching) <!-- test: none -->
- [x] Restructure `PROMPT_build.md` with XML-tagged sections, replace `<promise>COMPLETE</promise>` with `<result status="complete">`, and add anti-overengineering guardrails (WHY: structured result signaling) <!-- test: none -->
- [x] Restructure `PROMPT_review.md` with XML-tagged sections, remove "be thorough", add "focus on correctness, not style" (WHY: prevent review over-flagging) <!-- test: none -->
- [x] Add `<!-- DYNAMIC CONTEXT BELOW -->` separator and parallel tool calling directive to all `PROMPT_*.md` files (WHY: defines cache boundary for spec-30) <!-- test: none -->
- [x] Update `run_agent()` to inject dynamic context after the static separator (WHY: prevents cache invalidation) <!-- test: none -->

### Spec 34 — Structured State via Git — COMPLETE

- [x] Restructure `.gitignore` to split ephemeral and persistent `.automaton/` state <!-- test: none -->
- [x] Create `.automaton/learnings.json` with structured schema and CRUD functions <!-- test: none -->
- [x] Implement AGENTS.md generation from `learnings.json` at phase transitions <!-- test: none -->
- [x] Create `.automaton/run-summaries/` with per-run summary JSON <!-- test: none -->
- [x] Create `.automaton/budget-history.json` for cross-run cost data <!-- test: none -->
- [x] Implement resume recovery from persistent state <!-- test: none -->
- [x] Add persistent state commit protocol at phase transitions <!-- test: none -->

## Tier 2: Core Features — COMPLETE

### Spec 30 — Prompt Caching Optimization — COMPLETE

- [x] Add `<!-- STATIC CONTENT -->` markers to all `PROMPT_*.md` files <!-- test: none -->
- [x] Calculate cache hit ratio after every agent invocation <!-- test: none -->
- [x] Emit warning when cache hit ratio drops below 50% <!-- test: none -->
- [x] Ensure parallel builders share identical static prompt prefix <!-- test: none -->
- [x] Move context summaries to after static prefix <!-- test: none -->
- [x] Add cache hit ratio to dashboard <!-- test: none -->
- [x] Log message when static prefix below minimum cacheable threshold <!-- test: none -->

### Spec 33 — Context Window Lifecycle — COMPLETE

- [x] Define context utilization ceilings per phase <!-- test: none -->
- [x] Add frequent-commit rule to `PROMPT_build.md` <!-- test: none -->
- [x] Add compaction guidance to build and research prompts <!-- test: none -->
- [x] Implement auto-compaction detection <!-- test: none -->
- [x] Generate `.automaton/progress.txt` at each iteration <!-- test: none -->
- [x] Track context utilization per iteration <!-- test: none -->

### Spec 35 — Max Plan Optimization — COMPLETE

- [x] Add rate_limits_presets with api_default and max_plan profiles <!-- test: none -->
- [x] Implement daily budget pacing <!-- test: none -->
- [x] Add `--budget-check` CLI flag <!-- test: none -->
- [x] Apply higher parallel defaults in allowance mode <!-- test: none -->
- [x] Create `~/.automaton/allowance.json` for cross-project tracking <!-- test: none -->
- [x] Add `max_plan_preset` config shortcut <!-- test: none -->
- [x] Display weekly summary on resume and implement graceful exhaustion <!-- test: none -->

### Spec 27 — Native Subagent Definitions — COMPLETE

- [x] Create `.claude/agents/` with five agent definition files <!-- test: none -->
- [x] Write YAML frontmatter for each agent <!-- test: none -->
- [x] Migrate static prompt content into agent definitions <!-- test: none -->
- [x] Add `isolation: worktree` to build agent <!-- test: none -->
- [x] Configure `memory: project` for all agents <!-- test: none -->
- [x] Add `agents.use_native_definitions` flag <!-- test: none -->

### Spec 36 — Test-First Build Strategy — COMPLETE

- [x] Add test scaffold sub-phase to build loop <!-- test: tests/test_helpers.sh -->
- [x] Add test annotation rules to `PROMPT_plan.md` <!-- test: none -->
- [x] Add test-first discipline rules to `PROMPT_build.md` <!-- test: none -->
- [x] Create `tests/test_helpers.sh` with assertion functions <!-- test: tests/test_helpers.sh -->
- [x] Add test-driven verification priority to `PROMPT_review.md` <!-- test: none -->
- [x] Track test coverage metric in run summaries <!-- test: none -->
- [x] Add `execution.test_first_enabled` and `execution.test_framework` config <!-- test: none -->

## Tier 3: Integration Features — COMPLETE

### Spec 31 — Hooks Integration — COMPLETE

- [x] Create `.claude/hooks/enforce-file-ownership.sh` <!-- test: none -->
- [x] Create `.claude/hooks/self-build-guard.sh` <!-- test: none -->
- [x] Create `.claude/hooks/capture-test-results.sh` <!-- test: none -->
- [x] Create `.claude/hooks/builder-on-stop.sh` <!-- test: none -->
- [x] Create `.claude/hooks/track-subagent-start.sh` and `track-subagent-stop.sh` <!-- test: none -->
- [x] Create `.claude/hooks/task-quality-gate.sh` <!-- test: none -->
- [x] Configure hook locations in settings <!-- test: none -->
- [x] Ensure all hooks complete in under 2 seconds and are idempotent <!-- test: none -->

### Spec 32 — Skills Library — COMPLETE

- [x] Create `.claude/skills/spec-reader.md` <!-- test: none -->
- [x] Create `.claude/skills/validation-suite.md` <!-- test: none -->
- [x] Create `.claude/skills/context-loader.md` <!-- test: none -->
- [x] Create `.claude/skills/plan-updater.md` <!-- test: none -->
- [x] Create `.claude/skills/self-analysis.md` <!-- test: none -->
- [x] Add `skills` references to agent definitions and replace Phase 0 instructions <!-- test: none -->

### Spec 37 — Session Bootstrap — COMPLETE

- [x] Create `.automaton/init.sh` bootstrap script <!-- test: tests/test_bootstrap_integration.sh -->
- [x] Integrate bootstrap into `run_agent()` <!-- test: tests/test_bootstrap_integration.sh -->
- [x] Replace Phase 0 instructions with bootstrap manifest placeholder <!-- test: none -->
- [x] Implement bootstrap failure handling <!-- test: tests/test_bootstrap_failure.sh -->
- [x] Track cold start token savings <!-- test: tests/test_bootstrap_metrics.sh -->
- [x] Add bootstrap config options <!-- test: tests/test_bootstrap_config.sh -->

## Tier 4: Capstone — COMPLETE

### Spec 28 — Agent Teams Integration — COMPLETE

- [x] Add `parallel.mode` config field <!-- test: tests/test_agent_teams_config.sh -->
- [x] Implement task list population from IMPLEMENTATION_PLAN.md <!-- test: tests/test_agent_teams_task_list.sh -->
- [x] Configure teammate spawning from agent definitions <!-- test: tests/test_agent_teams_teammate_spawn.sh -->
- [x] Create `.claude/hooks/teammate-idle.sh` <!-- test: none -->
- [x] Implement Agent Teams environment setup <!-- test: tests/test_agent_teams_env_setup.sh -->
- [x] Implement approximate budget tracking for agent-teams mode <!-- test: tests/test_agent_teams_budget.sh -->
- [x] Document limitations and implement mitigations <!-- test: tests/test_agent_teams_limitations.sh -->

---

## Tier 5: Evolution Foundation (Specs 38, 42) — COMPLETE

### Spec 38 — Idea Garden — COMPLETE

- [x] Add `garden` configuration section to `automaton.config.json` <!-- test: tests/test_garden_config.sh -->
- [x] Update `.gitignore` for `.automaton/garden/` <!-- test: none -->
- [x] Implement `_garden_plant_seed()` <!-- test: tests/test_garden_plant.sh -->
- [x] Implement `_garden_water()` <!-- test: tests/test_garden_water.sh -->
- [x] Implement `_garden_advance_stage()` <!-- test: tests/test_garden_advance.sh -->
- [x] Implement `_garden_wilt()` <!-- test: tests/test_garden_wilt.sh -->
- [x] Implement `_garden_recompute_priorities()` <!-- test: tests/test_garden_priority.sh -->
- [x] Implement `_garden_rebuild_index()` <!-- test: tests/test_garden_init.sh -->
- [x] Implement `_garden_prune_expired()` <!-- test: tests/test_garden_prune.sh -->
- [x] Implement `_garden_find_duplicates()` <!-- test: tests/test_garden_duplicates.sh -->
- [x] Implement `_garden_get_bloom_candidates()` <!-- test: tests/test_garden_bloom.sh -->
- [x] Add garden directory initialization to `initialize_state()` <!-- test: tests/test_garden_init.sh -->
- [x] Add `garden_summary` field to bootstrap manifest <!-- test: none -->
- [x] Implement backward compatibility when `garden.enabled` is false <!-- test: tests/test_garden_config.sh -->

### Spec 42 — Stigmergic Coordination — COMPLETE

- [x] Add `stigmergy` configuration section to `automaton.config.json` <!-- test: tests/test_signal_config.sh -->
- [x] Update `.gitignore` for `.automaton/signals.json` <!-- test: none -->
- [x] Implement `_signal_emit()` <!-- test: tests/test_signal_emit.sh -->
- [x] Implement `_signal_reinforce()` <!-- test: tests/test_signal_reinforce.sh -->
- [x] Implement `_signal_find_match()` <!-- test: tests/test_signal_match.sh -->
- [x] Implement `_signal_decay_all()` <!-- test: tests/test_signal_decay.sh -->
- [x] Implement `_signal_prune()` <!-- test: tests/test_signal_prune.sh -->
- [x] Implement signal query functions <!-- test: tests/test_signal_query.sh -->
- [x] Initialize `.automaton/signals.json` lazily <!-- test: tests/test_signal_emit.sh -->
- [x] Add `active_signals` field to bootstrap manifest <!-- test: none -->
- [x] Add bidirectional linking between signals and garden ideas <!-- test: tests/test_signal_garden_link.sh -->

---

## Tier 6: Evolution Core (Specs 39, 43) — COMPLETE

### Spec 39 — Agent Quorum — COMPLETE

- [x] Create 5 voter agent definitions <!-- test: none -->
- [x] Add `quorum` configuration section to `automaton.config.json` <!-- test: tests/test_quorum_config.sh -->
- [x] Update `.gitignore` for `.automaton/votes/` <!-- test: none -->
- [x] Implement `_quorum_invoke_voter()` <!-- test: tests/test_quorum_invoke.sh -->
- [x] Implement `_quorum_tally()` <!-- test: tests/test_quorum_tally.sh -->
- [x] Implement `_quorum_evaluate_bloom()` <!-- test: tests/test_quorum_evaluate.sh -->
- [x] Implement `_quorum_check_budget()` <!-- test: tests/test_quorum_budget.sh -->
- [x] Implement rejection cooldown <!-- test: tests/test_quorum_cooldown.sh -->
- [x] Implement quorum-disabled fallback <!-- test: tests/test_quorum_config.sh -->

### Spec 43 — Growth Metrics — COMPLETE

- [x] Add `metrics` configuration section to `automaton.config.json` <!-- test: tests/test_metrics_config.sh -->
- [x] Update `.gitignore` for `.automaton/evolution-metrics.json` <!-- test: none -->
- [x] Implement `_metrics_snapshot()` <!-- test: tests/test_metrics_snapshot.sh -->
- [x] Implement `_metrics_set_baselines()` and `_metrics_get_latest()` <!-- test: tests/test_metrics_baselines.sh -->
- [x] Implement `_metrics_analyze_trends()` <!-- test: tests/test_metrics_trends.sh -->
- [x] Implement `_metrics_compare()` <!-- test: tests/test_metrics_compare.sh -->
- [x] Implement `_metrics_display_health()` <!-- test: tests/test_metrics_display.sh -->
- [x] Add `--health` CLI flag <!-- test: tests/test_metrics_display.sh -->
- [x] Add `metrics_trend` field to bootstrap manifest <!-- test: none -->
- [x] Enforce snapshot retention <!-- test: tests/test_metrics_snapshot.sh -->

---

## Tier 7: Evolution Governance (Specs 40, 45) — COMPLETE

### Spec 40 — Constitutional Principles — COMPLETE

- [x] Implement `_constitution_create_default()` <!-- test: tests/test_constitution_create.sh -->
- [x] Update `.gitignore` for constitution files <!-- test: none -->
- [x] Implement `_constitution_check()` <!-- test: tests/test_constitution_check.sh -->
- [x] Implement immutable constraint enforcement <!-- test: tests/test_constitution_immutable.sh -->
- [x] Implement `_constitution_amend()` <!-- test: tests/test_constitution_amend.sh -->
- [x] Create `evolve-constitution-checker.md` agent definition <!-- test: none -->
- [x] Implement `_constitution_get_summary()` <!-- test: tests/test_constitution_create.sh -->
- [x] Add `constitution_summary` field to bootstrap manifest <!-- test: none -->

### Spec 45 — Safety and Reversibility — COMPLETE

- [x] Implement branch-based isolation for IMPLEMENT phase <!-- test: tests/test_safety_branch.sh -->
- [x] Implement `_safety_sandbox_test()` <!-- test: tests/test_safety_sandbox.sh -->
- [x] Add `safety` configuration section to `automaton.config.json` <!-- test: tests/test_safety_config.sh -->
- [x] Implement circuit breakers <!-- test: tests/test_safety_breakers.sh -->
- [x] Implement `_safety_rollback()` <!-- test: tests/test_safety_rollback.sh -->
- [x] Implement `_safety_preflight()` <!-- test: tests/test_safety_preflight.sh -->
- [x] Create `evolution-safety-guard.sh` hook <!-- test: none -->
- [x] Register hook in `.claude/settings.json` <!-- test: none -->
- [x] Create `rollback-executor.md` skill <!-- test: none -->
- [x] Add `.automaton/evolution/` to `.gitignore` <!-- test: none -->

---

## Tier 8: Evolution Engine (Spec 41) — COMPLETE

### Spec 41 — Autonomous Evolution Loop — COMPLETE

- [x] Add `--evolve` and `--cycles N` CLI flag parsing <!-- test: tests/test_evolve_cli.sh -->
- [x] Add `evolution` configuration section to `automaton.config.json` <!-- test: tests/test_evolve_config.sh -->
- [x] Add `.automaton/evolution/` ephemeral directory creation <!-- test: none -->
- [x] Implement `_evolve_reflect()` <!-- test: tests/test_evolve_reflect.sh -->
- [x] Implement `_evolve_ideate()` <!-- test: tests/test_evolve_ideate.sh -->
- [x] Implement `_evolve_evaluate()` <!-- test: tests/test_evolve_evaluate.sh -->
- [x] Implement `_evolve_implement()` <!-- test: tests/test_evolve_implement.sh -->
- [x] Implement `_evolve_observe()` <!-- test: tests/test_evolve_observe.sh -->
- [x] Implement `_evolve_run_cycle()` <!-- test: tests/test_evolve_cycle.sh -->
- [x] Implement `_evolve_check_convergence()` <!-- test: tests/test_evolve_convergence.sh -->
- [x] Implement `_evolve_check_budget()` <!-- test: tests/test_evolve_budget.sh -->
- [x] Implement resume support <!-- test: tests/test_evolve_resume.sh -->
- [x] Create 3 evolution agent definitions <!-- test: none -->
- [x] Create 3 evolution prompt files <!-- test: none -->
- [x] Add evolution safety rules to `PROMPT_build.md` and `PROMPT_review.md` <!-- test: none -->

---

## Tier 9: Evolution Interface (Spec 44) — COMPLETE

### Spec 44 — Human Interface — COMPLETE

- [x] Add argument parsing for all 15 new CLI flags <!-- test: tests/test_cli_args.sh -->
- [x] Implement `_display_garden()` <!-- test: tests/test_display_garden.sh -->
- [x] Implement `_display_garden_detail()` <!-- test: tests/test_display_garden_detail.sh -->
- [x] Implement `_display_signals()` <!-- test: tests/test_display_signals.sh -->
- [x] Implement `_display_vote()` <!-- test: tests/test_display_vote.sh -->
- [x] Implement `_display_constitution()` <!-- test: tests/test_display_constitution.sh -->
- [x] Implement `_cli_plant()` <!-- test: tests/test_cli_plant.sh -->
- [x] Implement `_cli_water()` <!-- test: tests/test_cli_water.sh -->
- [x] Implement `_cli_prune()` <!-- test: tests/test_cli_prune.sh -->
- [x] Implement `_cli_promote()` <!-- test: tests/test_cli_promote.sh -->
- [x] Implement `_cli_amend()` <!-- test: tests/test_cli_amend.sh -->
- [x] Implement `_cli_override()` <!-- test: tests/test_cli_override.sh -->
- [x] Implement `_cli_pause()` <!-- test: tests/test_cli_pause.sh -->
- [x] Create 4 skill files <!-- test: none -->
- [x] Update `_show_help()` with all new commands <!-- test: tests/test_cli_help.sh -->

---

## Tier 10: Core Quality Infrastructure — COMPLETE

### Spec 50 — Config Pre-Flight Validation — COMPLETE

- [x] Implement `validate_config()` with JSON syntax and type checks <!-- test: tests/test_config_validation.sh -->
- [x] Add range validation <!-- test: tests/test_config_validation.sh -->
- [x] Add enum validation <!-- test: tests/test_config_validation.sh -->
- [x] Add cross-field conflict detection <!-- test: tests/test_config_validation.sh -->
- [x] Add warnings for unusual values <!-- test: tests/test_config_validation.sh -->
- [x] Wire `validate_config()` into `main()` after `load_config()` <!-- test: tests/test_config_validation.sh -->
- [x] Add `--validate-config` CLI flag <!-- test: tests/test_config_validation.sh -->

### Spec 48 — Doctor / Health Check — COMPLETE

- [x] Implement `doctor_check()` with dependency checks <!-- test: tests/test_doctor.sh -->
- [x] Add auth, disk space, and git state checks <!-- test: tests/test_doctor.sh -->
- [x] Add project file checks <!-- test: tests/test_doctor.sh -->
- [x] Add ANSI-colored output with `NO_COLOR` support <!-- test: tests/test_doctor.sh -->
- [x] Add `--doctor` CLI flag <!-- test: tests/test_doctor.sh -->

### Spec 49 — Output Truncation — COMPLETE

- [x] Implement `truncate_output()` with head+tail strategy <!-- test: tests/test_output_truncation.sh -->
- [x] Add full output archival <!-- test: tests/test_output_truncation.sh -->
- [x] Add `execution.output_max_lines` config fields <!-- test: tests/test_output_truncation.sh -->
- [x] Call `truncate_output()` at all output capture points <!-- test: tests/test_output_truncation.sh -->

### Spec 46 — Self-Validating QA Loop — COMPLETE

- [x] Add QA config fields to `automaton.config.json` <!-- test: tests/test_qa_config.sh -->
- [x] Create `PROMPT_qa.md` <!-- test: none -->
- [x] Implement QA validation pass <!-- test: tests/test_qa_validate.sh -->
- [x] Implement failure classification <!-- test: tests/test_qa_classify.sh -->
- [x] Implement targeted fix task creation <!-- test: tests/test_qa_fix_tasks.sh -->
- [x] Implement QA retry loop <!-- test: tests/test_qa_loop.sh -->
- [x] Implement QA exhaustion handling <!-- test: tests/test_qa_report.sh -->
- [x] Implement blind validation option <!-- test: tests/test_qa_blind.sh -->

---

## Tier 11: Pre-Planning Quality — COMPLETE

### Spec 47 — Pre-Flight Spec Critique — COMPLETE

- [x] Implement `phase_critique()` with spec concatenation and token estimation <!-- test: tests/test_critique.sh -->
- [x] Make single `claude -p` call with critique prompt <!-- test: tests/test_critique.sh -->
- [x] Generate `.automaton/SPEC_CRITIQUE.md` from structured JSON <!-- test: tests/test_critique.sh -->
- [x] Add `--critique-specs`, `--skip-critique` flags, and `critique` config section <!-- test: tests/test_critique.sh -->

---

## Tier 12: Pipeline Enhancements — COMPLETE

### Spec 54 — Blind Validation Pattern — COMPLETE

- [x] Implement `run_blind_validation()` <!-- test: tests/test_blind_validation.sh -->
- [x] Parse structured verdict and integrate into review phase <!-- test: tests/test_blind_validation.sh -->
- [x] Add `flags.blind_validation` and `blind_validation.max_diff_lines` config <!-- test: none -->

### Spec 53 — Steelman Self-Critique — COMPLETE

- [x] Implement `run_steelman_critique()` <!-- test: tests/test_steelman.sh -->
- [x] Add `--steelman` CLI flag and `flags.steelman_critique` config <!-- test: tests/test_steelman.sh -->

### Spec 52 — Notification Callbacks — COMPLETE

- [x] Implement `send_notification()` with webhook and command execution <!-- test: tests/test_notifications.sh -->
- [x] Add 5 call sites <!-- test: tests/test_notifications.sh -->
- [x] Add `notifications` config section <!-- test: none -->

---

## Tier 13: Advanced Routing — COMPLETE

### Spec 51 — Complexity-Based Execution Routing — COMPLETE

- [x] Implement `assess_complexity()` <!-- test: tests/test_complexity.sh -->
- [x] Implement routing logic <!-- test: tests/test_complexity.sh -->
- [x] Add `--complexity` CLI flag <!-- test: tests/test_complexity.sh -->

---

## Tier 14: Observability & Hardening — COMPLETE

### Spec 55 — Structured Work Logs — COMPLETE

- [x] Implement `emit_event()` <!-- test: tests/test_work_log.sh -->
- [x] Add 9 call sites <!-- test: tests/test_work_log.sh -->
- [x] Add `--log-level` CLI flag and `work_log` config section <!-- test: tests/test_work_log.sh -->

### Spec 56 — Typed Technical Debt Tracking — COMPLETE

- [x] Implement `_scan_technical_debt()` <!-- test: tests/test_debt_tracking.sh -->
- [x] Implement `_generate_debt_summary()` <!-- test: tests/test_debt_tracking.sh -->
- [x] Add `debt_tracking` config section <!-- test: none -->

### Spec 58 — Design Principles & Anti-Pattern Guard Rails — COMPLETE

- [x] Create `.automaton/DESIGN_PRINCIPLES.md` <!-- test: tests/test_guardrails.sh -->
- [x] Implement 6 `guardrail_check_*` functions <!-- test: tests/test_guardrails.sh -->
- [x] Implement `run_guardrails()` dispatcher <!-- test: tests/test_guardrails.sh -->

---

## Tier 15: Onboarding — COMPLETE

### Spec 57 — First-Time Setup Wizard — COMPLETE

- [x] Implement `setup_wizard()` with 4 interactive prompts <!-- test: tests/test_setup_wizard.sh -->
- [x] Add first-run detection, `--setup`/`--no-setup` flags, config generation <!-- test: tests/test_setup_wizard.sh -->
- [x] Call `doctor_check()` after writing config <!-- test: tests/test_setup_wizard.sh -->

---

## Tier 16: Requirements Wizard & Template Sync (Spec 59 + Housekeeping)

Spec 59 is the last unfinished spec. The `lib/` refactor also created template and scaffolder drift that needs resolution.

### Spec 59 — Requirements Wizard

#### 59.1 Core Function — COMPLETE

- [x] Implement `requirements_wizard()` in `lib/config.sh` with non-TTY guard, overwrite confirmation, banner, Claude invocation via `--system-prompt`, and Gate 1 re-check (WHY: this is the core wizard flow — launches an interactive Claude session with the wizard prompt and validates output before continuing) <!-- test: tests/test_requirements_wizard.sh -->

- [x] Create `PROMPT_wizard.md` with 6-stage interview structure (Project Overview, Users & Workflows, Core Features, Constraints & Preferences, Boundaries, Review & Generate) (WHY: the structured prompt ensures Claude follows a consistent interview flow and generates spec files in the standard template) <!-- test: none -->

- [x] Add `--wizard` and `--no-wizard` CLI flags with mutual exclusion check (WHY: `--wizard` forces the wizard even when specs exist; `--no-wizard` preserves the old Gate 1 failure behavior for CI) <!-- test: tests/test_cli_args.sh -->

- [x] Wire wizard into Gate 1 failure path in `run_orchestration()`: auto-launch when TTY available and `--no-wizard` not set, print actionable error when non-TTY (WHY: seamless onboarding — running `./automaton.sh` with no specs "just works" in a terminal) <!-- test: tests/test_cli_args.sh -->

- [x] Add `--wizard` and `--no-wizard` to `_show_help()` (WHY: discoverability — users need to know the flags exist) <!-- test: tests/test_cli_help.sh -->

#### 59.2 Remaining Work

- [x] Create `tests/test_requirements_wizard.sh` with unit tests for `requirements_wizard()`: non-TTY guard returns 1, overwrite confirmation flow, prompt file missing returns 1, Gate 1 re-check after completion (WHY: the function has 4 distinct code paths that need test coverage — TTY check, confirmation, missing file, and post-wizard validation) <!-- test: tests/test_requirements_wizard.sh -->

- [x] Add `'PROMPT_wizard.md'` to the `TEMPLATE_FILES` array in `bin/cli.js` (WHY: scaffolded projects need the wizard prompt to support the `--wizard` flow; without it, `requirements_wizard()` fails with "PROMPT_wizard.md not found") <!-- test: none -->

- [ ] Update `bin/cli.js` scaffolder output to remove any "run `claude` first" language and explain that `./automaton.sh` handles everything including requirements gathering (WHY: spec-59 eliminates the manual `claude` step — the scaffolder banner must reflect this) <!-- test: none -->

### Template & Scaffolder Sync (Housekeeping)

The codebase was refactored from a monolithic `automaton.sh` (14,767 lines) into a modular architecture: `automaton.sh` (1,390 lines) + `lib/` (17 modules, 15,797 lines). Templates and the scaffolder do not reflect this structure.

- [x] Track `lib/` directory in git (WHY: the 17 library modules contain all function implementations — without them in git, the project is non-functional; committed in e367daf) <!-- test: none -->

- [ ] Sync `templates/automaton.sh` with the current modular entry point (WHY: the template is the old 5,249-line monolith; scaffolded projects would get the wrong architecture) <!-- test: none -->

- [ ] Copy `lib/` directory to `templates/lib/` (WHY: scaffolded projects need all library modules to function; without them, the modular `automaton.sh` fails on `source` lines 23-39) <!-- test: none -->

- [ ] Add `lib/` directory copying to the scaffolder in `bin/cli.js` (WHY: `npx automaton` must copy the `lib/` directory alongside `automaton.sh` for the modular architecture to work in scaffolded projects) <!-- test: none -->

- [ ] Sync `templates/automaton.config.json` with root config including all spec 38-59 config sections (WHY: the template config is missing garden, stigmergy, quorum, metrics, evolution, safety, qa, critique, notifications, work_log, debt_tracking, guardrails, and wizard-related fields) <!-- test: none -->

- [ ] Sync all `templates/PROMPT_*.md` files with root versions (WHY: prompt templates may be stale after specs 46-59 added QA, evolution, and wizard prompt content) <!-- test: none -->
