# Implementation Plan

Specs 1-59 are fully implemented across `automaton.sh` (1,390 lines) and 17 library modules in `lib/` (15,797 lines), totaling 17,187 lines. There are 158 test files (24,129 lines) covering all implemented specs.

Spec 60 (--scope flag) has no implementation started.

An architectural audit (specs/audit/01-07) identified 7 findings with a 6-wave improvement roadmap focused on spec traceability, incremental verification, token optimization, and test infrastructure hardening.

## Previously Completed

- [x] All specs 1-59 implemented (WHY: core orchestrator, 5-phase pipeline, evolution subsystem, CLI distribution, quality gates, and all supporting infrastructure)
- [x] Template sync: `templates/automaton.sh`, `templates/lib/`, `templates/automaton.config.json` all match root (WHY: scaffolded projects get correct modular architecture)
- [x] Fix: `((_i++))` returning exit code 1 under `set -e` — fixed with `((_i++ , 1))` pattern across lib/config.sh (WHY: dry-run smoke test was failing)

---

## Tier 17: Housekeeping & Prompt Sync

### Root PROMPT File Sync

- [x] Sync root `PROMPT_build.md` with `templates/PROMPT_build.md` (the authoritative XML-tagged version with bootstrap support, self-build safety rules, and `<result>` output format) (WHY: root version is a 58-line abbreviated copy missing spec-29 XML structure, spec-22 self-build rules, spec-36 test-first discipline, spec-41 evolution safety, and the `<result>` output format — the orchestrator uses the root version, so agents get incomplete instructions) <!-- test: none -->

- [x] Sync root `PROMPT_plan.md` with `templates/PROMPT_plan.md` (the authoritative XML-tagged version with bootstrap support, test annotation rules, and `<result>` output format) (WHY: root version is a 41-line abbreviated copy missing spec-29 XML structure, spec-36 test annotation format, anti-over-engineering rules, and the `<result>` output format — the orchestrator uses the root version, so the planning agent gets incomplete instructions) <!-- test: none -->

- [x] Add execute permission to root `automaton.sh` (`chmod +x automaton.sh`) (WHY: template version has execute bit but root doesn't — users expect `./automaton.sh` to work without `bash automaton.sh`) <!-- test: none -->

---

## Tier 18: Spec 60 — `--scope PATH` Flag

This feature enables directory-scoped agent operations, critical for monorepo support. All tasks are derived from the detailed specification in `specs/spec-60-scope-flag.md`.

### 60.1 Variable Separation & CLI Parsing

- [x] Add `AUTOMATON_INSTALL_DIR` variable to `automaton.sh` (set to `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`) and make `AUTOMATON_DIR` absolute (`$(pwd)/.automaton`) (WHY: scope flag requires decoupling where agents work (`PROJECT_ROOT`) from where state lives (`AUTOMATON_DIR`) and where prompts live (`AUTOMATON_INSTALL_DIR`) — currently these are conflated) <!-- test: tests/test_scope.sh -->

- [x] Add `ARG_SCOPE=""` default and `--scope` case branch to CLI argument parsing in `automaton.sh` (WHY: the entry point for the feature — parses the path argument and stores it for resolution) <!-- test: tests/test_cli_args.sh -->

- [x] Implement path resolution block after argument parsing: resolve relative→absolute via `cd "$path" && pwd`, validate directory exists, set `PROJECT_ROOT` (WHY: invalid paths must fail early with clear error messages before any phase dispatch) <!-- test: tests/test_scope.sh -->

- [x] Add mutual exclusion check: `--scope` + `--self` exits with error (WHY: self-build targets automaton's own directory, so scoping to a subdirectory is contradictory) <!-- test: tests/test_scope.sh -->

### 60.2 Agent Invocation Changes

- [x] Update `get_phase_prompt()` in `lib/utilities.sh` to prefix paths with `$AUTOMATON_INSTALL_DIR/` instead of relative paths (WHY: when agent cwd changes to the scoped directory, relative prompt paths break — prompts live alongside automaton.sh, not in the scoped dir) <!-- test: tests/test_scope.sh -->

- [x] Wrap `claude` invocation in `run_agent()` (`lib/utilities.sh`) with `(cd "$PROJECT_ROOT" && ...)` subshell (WHY: agents must operate within the scoped directory, but the orchestrator must stay at its own cwd to manage state) <!-- test: tests/test_scope.sh -->

- [x] Export `AUTOMATON_PROJECT_ROOT="$PROJECT_ROOT"` before agent invocation (WHY: hooks read this environment variable to determine the project root — without it, hooks in scoped mode operate on the wrong directory) <!-- test: tests/test_scope.sh -->

### 60.3 Parallel Mode & Bootstrap

- [x] Update `spawn_builders()` in `lib/parallel.sh` to use `${PROJECT_ROOT:-$(pwd)}` instead of `$(pwd)` (WHY: parallel builders must inherit the scoped directory, not the orchestrator's cwd) <!-- test: tests/test_scope.sh -->

- [x] Update `generate_builder_wrapper()` in `lib/parallel.sh` to bake in `AUTOMATON_INSTALL_DIR` and absolute `AUTOMATON_DIR` as template placeholders (WHY: standalone wrapper scripts can't inherit shell state — they need hard-coded paths to find prompts and state files) <!-- test: tests/test_scope.sh -->

- [x] Update `generate_bootstrap_script()` template in `lib/state.sh` to read `AUTOMATON_DIR` from environment with fallback: `AUTOMATON_DIR="${AUTOMATON_DIR:-$PROJECT_ROOT/.automaton}"` (WHY: backward-compatible — when AUTOMATON_DIR isn't exported, the old derivation still works; when scoped, it uses the correct absolute path) <!-- test: tests/test_scope.sh -->

### 60.4 Display & Help

- [x] Add `Scope:` line to startup banner in `automaton.sh` (only when scope differs from cwd) (WHY: users need visual confirmation of which directory agents will operate in — omitting it when scope=cwd avoids noise) <!-- test: tests/test_scope.sh -->

- [x] Add `--scope PATH` to `_show_help()` in `lib/display.sh` (WHY: discoverability — users must know the flag exists to use it) <!-- test: tests/test_cli_help.sh -->

### 60.5 Tests

- [x] Create `tests/test_scope.sh` with integration tests: relative path resolution, absolute path passthrough, non-existent path error, file-not-dir error, `--scope .` no-op, `AUTOMATON_DIR` stays cwd-anchored, `--scope` + `--self` mutual exclusion (WHY: 7 distinct code paths need test coverage to prevent regressions) <!-- test: tests/test_scope.sh -->

- [x] Add `ARG_SCOPE` test cases to `tests/test_cli_args.sh`: default is empty, `--scope /tmp` sets value, `--scope` with no argument errors, combined flags work (WHY: existing CLI arg tests must cover the new flag to maintain comprehensive CLI test coverage) <!-- test: tests/test_cli_args.sh -->

---

## Tier 19: Audit Wave 1 — Test Infrastructure Foundation

From audit finding 04-A (bash at scale) and 04-B (shellcheck). No code changes to the orchestrator itself.

- [x] Create `run_tests.sh` that discovers and runs all `tests/test_*.sh`, counts pass/fail, exits non-zero on failure (WHY: 158 test files exist but no way to run them all at once — this is prerequisite for CI, review gate integration, and self-build validation) <!-- test: none -->

- [x] Add `shellcheck automaton.sh lib/*.sh` as a mandatory check in `PROMPT_review.md` (WHY: bash has no type system — shellcheck catches undefined variables, word splitting, and quoting bugs that cause silent failures at 17K lines) <!-- test: none -->

- [x] Add `## Edge Cases` section to `templates/PROMPT_converse.md` spec template and update conversation prompt to push for edge case enumeration (WHY: specs currently lack explicit edge case sections — boundary conditions get discovered/missed during build instead of being planned for) <!-- test: none -->

---

## Tier 20: Audit Wave 2 — Spec Traceability

From audit finding 01 (spec-to-code traceability gap). The #1 gap for hit rate — requirements can be silently dropped without detection.

- [x] Update `PROMPT_plan.md` (template version) to require acceptance criteria extraction from specs as `AC-XX-Y` items grouped under each spec section in the plan (WHY: without structured acceptance criteria in the plan, the review agent checks "does code work" instead of "does code cover all spec requirements") <!-- test: none -->

- [x] Add traceability verification pass to `PROMPT_review.md` (template version): "For each AC-XX-Y, verify implementation evidence" before existing code review steps (WHY: creates the feedback loop — review catches requirements that were silently dropped during build) <!-- test: none -->

- [x] Add instruction to `PROMPT_review.md` to generate `.automaton/traceability.json` mapping each AC to pass/fail with evidence (WHY: makes traceability auditable and machine-readable — enables future automated regression detection) <!-- test: none -->

---

## Tier 21: Audit Wave 3 — Test-Driven Spec Compliance

From audit findings 06 (acceptance test generation) and 07-#2 (red-before-green gate). Depends on Wave 2 (needs AC extraction format).

- [x] Update `PROMPT_plan.md` (template version) to generate test skeleton files from acceptance criteria: each AC becomes a test function with `assert_fail "Not yet implemented"` (WHY: separates test authorship from implementation authorship — prevents confirmation bias where the same agent writes both test and code) <!-- test: none -->

- [x] Add red-before-green gate in `lib/lifecycle.sh` or `lib/qa.sh`: after plan phase, run test suite and record failure count; after build, verify failure count decreased (WHY: proves implementation actually made progress — if tests pass before AND after, the tests may not be testing the right thing) <!-- test: tests/test_red_green_gate.sh -->

- [x] Update `PROMPT_build.md` (template version) to instruct: "Find pre-existing test skeletons. Implement code to make them pass. Do NOT modify skeleton test assertions." (WHY: true TDD — tests exist before code, builder has concrete targets instead of writing tests to match what they built) <!-- test: none -->

---

## Tier 22: Audit Wave 4 — Incremental Verification

From audit finding 02 (missing incremental verification). Adds per-task validation to catch bugs early instead of reviewing everything at the end.

- [x] Create micro-validation prompt (~30 lines) for lightweight post-task Sonnet check on specific acceptance criterion (WHY: catches bugs in task N before task N+1 compounds them — prevents 500K+ token cost of failed review → rebuild cycles; estimated net savings 60-80%) <!-- test: none -->

- [x] Implement post-task micro-validation in build loop (`lib/lifecycle.sh`): after each build iteration, run lightweight 2K-token Sonnet check (WHY: batch-and-check is the current anti-pattern — this adds the "verify small" discipline from VSDD) <!-- test: tests/test_micro_validation.sh -->

- [x] Track `git diff --stat` per iteration in `.automaton/agents/` and provide per-task diffs to review agent (WHY: review currently gets one giant diff — per-task breakdown reduces review context size and improves accuracy) <!-- test: none -->

- [x] Add early escalation: if micro-validation fails 2 consecutive tasks, force transition to review phase (WHY: extends existing stall detection — continuing to build on top of broken tasks wastes tokens) <!-- test: tests/test_micro_validation.sh -->

---

## Tier 23: Audit Wave 5 — Token Optimization

From audit finding 05 (token waste). Depends on Waves 2+4 for traceability data.

- [x] Split review into tiered passes: (1) Sonnet mechanical pass (tests/lint/typecheck → binary pass/fail), (2) Opus judgment pass only if mechanical passes (WHY: saves Opus tokens on mechanically-failing runs — estimated 40-60% review cost reduction) <!-- test: none -->

- [x] Implement delta-only review context: include only changed files and related specs via traceability map, not entire codebase (WHY: estimated 30-50% input token reduction — review currently reads everything) <!-- test: none -->

- [x] Add QA oscillation detection in `lib/qa.sh`: track failing test sets across iterations, detect if same test fails→fixed→re-fails pattern, escalate instead of retrying (WHY: prevents 2-3 wasted QA cycles when fixes are fighting each other) <!-- test: tests/test_qa_oscillation.sh -->

---

## Tier 24: Audit Wave 6 — Advanced Process (Optional)

From audit finding 07 (VSDD process extraction). Lower priority — implement after Waves 1-5 are proven on real projects.

- [x] Add review confidence scoring: review agent rates confidence (1-5) across spec coverage, test quality, code quality, regression risk; all ≥4 = complete, any <3 = create tasks (WHY: completion is currently binary — gradient scoring catches "barely passing" reviews that need more work) <!-- test: tests/test_review_confidence.sh -->

- [x] Add feedback level routing: review classifies issues as spec-level, test-level, or implementation-level; spec-level issues create spec amendment proposals instead of build tasks (WHY: prevents building against flawed specs — if review finds an ambiguous requirement, fixing the spec is better than working around it) <!-- test: none -->

- [x] Implement living spec amendments: build agent proposes spec amendments to `.automaton/spec-amendments.json`, review evaluates, approved amendments update specs (WHY: specs currently freeze after Phase 0 — when builder discovers a requirement is impossible/wrong, the spec should evolve) <!-- test: none -->

---

## Tier 25: Quick Wins — Context & Correctness

Small, low-risk, independent changes that each save tokens or fix a bug.

### 25.1 Remove self-build codebase overview from dynamic context

- [x] Delete the `if [ "$SELF_BUILD_ENABLED" = "true" ] && [ -f "automaton.sh" ]` block in `lib/utilities.sh:111-117` that greps automaton.sh function signatures and injects ~40 lines into build context (WHY: builder already has Grep/Read tools — this is redundant context costing ~1K tokens per build iteration in self-build mode) <!-- test: tests/test_utilities_functional.sh -->

- [x] Apply the same deletion in `templates/lib/utilities.sh:111-117` to keep template in sync (WHY: templates are the authoritative copy for scaffolded projects) <!-- test: tests/test_scaffolder_files.sh -->

### 25.2 Fix complexity assessment defaulting to MODERATE on invalid tier

- [x] In `assess_complexity()` (`lib/qa.sh:1299`), changed `--output-format json` to `--output-format text` — the json format wraps the response in an API envelope, so `jq '.tier'` found nothing at the top level and fell to the invalid-tier default; text format returns the model's raw output directly (WHY: complexity.json showed "Assessment returned invalid tier" because `.tier` was not at the top level of the JSON envelope) <!-- test: tests/test_utilities_functional.sh -->

- [x] Apply the same fix in `templates/lib/qa.sh` to keep template in sync <!-- test: tests/test_scaffolder_files.sh -->

### 25.3 Investigate token-efficient tool use header

- [x] Check whether the `claude` CLI supports a `--token-efficient-tool-use` flag or equivalent environment variable (run `claude --help` and search docs); if available, add the flag to `run_agent()` in `lib/utilities.sh`; if not available, mark this task as not-applicable and remove from backlog (WHY: potential 30-50% reduction in tool result tokens, but only if the CLI exposes this API feature) <!-- test: manual verification -->

---

## Tier 26: .claudeignore Generation

### 26.1 Add .claudeignore to setup wizard

- [x] Add a `.claudeignore` generation step to `setup_wizard()` in `lib/config.sh:952+`: after writing `automaton.config.json`, write a `.claudeignore` file containing `templates/`, `.automaton/logs/`, `.automaton/work-log*.jsonl`, `tests/output/`, and `*.jsonl` (WHY: prevents agents from reading large template files, logs, and test output that waste 5-15% of input tokens per invocation) <!-- test: tests/test_setup_wizard.sh -->

- [x] Apply the same addition to `templates/lib/config.sh` to keep template in sync <!-- test: tests/test_scaffolder_files.sh -->

---

## Tier 27: Token Tracking Infrastructure

Depends on existing `extract_tokens()` in `lib/budget.sh:753` and `emit_event()` in `lib/state.sh:671`. These two tasks are related but independent — either can be built first.

### 27.1 Wire token data into work-log events

- [x] Added `input_tokens`, `output_tokens`, `cache_create`, `cache_read` fields to the `iteration_end` `emit_event` call in `automaton.sh:1031` using `LAST_*` globals set by `extract_tokens()` (WHY: work-log.jsonl `iteration_end` events had no token data; adding to existing event avoids a separate `iteration_tokens` event type) <!-- test: verify work-log.jsonl iteration_end events contain token fields after a run -->

- [x] Apply the same change in `templates/automaton.sh` to keep template in sync <!-- test: tests/test_scaffolder_files.sh -->

### 27.2 Populate budget.json history array

- [x] `budget.json` history array is already populated by `update_budget()` in `lib/budget.sh:920` — verified 10 history entries with full token/cost/phase/iteration data. Task description was stale (the implementation was already complete). <!-- test: cat .automaton/budget.json | jq '.history | length' -->

- [x] `append_budget_history()` not needed — `update_budget()` already handles atomic writes via tmp file and is called from all agent invocation paths (serial and parallel). <!-- resolved -->

---

## Tier 28: Hot Path jq Optimization

Medium complexity, medium risk. Batch multiple `jq` field extractions from the same JSON file into single calls.

### 28.1 Batch jq reads in budget.sh

- [x] Identify sequences in `lib/budget.sh` where multiple `jq -r '.field'` calls read the same file (budget.json) in succession; consolidate into single `jq -r '[.field1, .field2, .field3] | @tsv'` calls with `read` to split the output (WHY: budget.sh has ~60 jq invocations; batching saves subprocess overhead during every iteration's budget check) <!-- test: tests/test_utilities_functional.sh -->

### 28.2 Batch jq reads in qa.sh

- [x] Apply the same batching pattern to `lib/qa.sh` (~78 jq calls), focusing on functions that run per-iteration: `check_qa_gate()`, `detect_oscillation()`, `assess_complexity()` (WHY: these run in the hot path — every subprocess saved is ~5ms) <!-- test: tests/test_utilities_functional.sh -->

### 28.3 Batch jq reads in evolution.sh

- [x] Apply the same batching pattern to `lib/evolution.sh` (~78 jq calls), focusing on `evolve_reflect()`, `evolve_observe()` which read multiple fields from garden.json and metrics files (WHY: completes the hot-path optimization across the three heaviest modules) <!-- test: tests/test_utilities_functional.sh -->

### 28.4 Template sync for Tier 28

- [x] Sync all jq optimizations to `templates/lib/budget.sh`, `templates/lib/qa.sh`, `templates/lib/evolution.sh` <!-- test: tests/test_scaffolder_files.sh -->

---

## Tier 29: Module Size Management

### 29.1 Split parallel.sh

- [x] Split `lib/parallel.sh` (2,832 lines) into `lib/parallel_core.sh` (spawn, dispatch, IPC, result collection) and `lib/parallel_teams.sh` (team configuration, role assignment, team-specific prompts) (WHY: codebase is at 18,476 lines approaching the 18,000-line guardrail; splitting the largest module improves maintainability and reduces agent confusion when reading code) <!-- test: tests/test_utilities_functional.sh, run_tests.sh -->

- [x] Update all `source` statements in `automaton.sh` and other `lib/*.sh` files that reference `parallel.sh` to source both new files; `lib/parallel.sh` kept as 4-line compat shim <!-- test: run_tests.sh -->

- [x] Apply split to `templates/lib/parallel.sh` → `templates/lib/parallel_core.sh` + `templates/lib/parallel_teams.sh` <!-- test: tests/test_scaffolder_files.sh -->

---

## Tier 30: Garden Subsystem Assessment

### 30.1 Evaluate garden.sh utility

- [x] The garden subsystem (`lib/garden.sh`, 607 lines) has 0 ideas and is unused during self-build; determined: option (b) — added comment to `source` line in `automaton.sh` and `templates/automaton.sh` explaining garden is active when `evolution.enabled=true` and 0 ideas is expected during build-only runs. Garden IS already wired into evolution.sh (evolve_reflect, evolve_observe, etc.); it just doesn't fire during build iterations. (WHY: garden IS already wired to evolution cycle — it's not dead code, just inactive without evolution cycles) <!-- test: none — decision task -->

---

## Tier 31: Observability & Correctness Bug Fixes (Priority: HIGH)

Small, low-risk, independent fixes for data collection bugs that degrade stall detection and post-run diagnostics. All 4 tasks are independent — build in any order.

### 31.1 Fix files_changed always 0 in iteration_end events

- [x] The `files_changed` variable is computed at `automaton.sh:690` via `git diff --name-only HEAD~1` and written to agent history JSON at line 698. But the `emit_event "iteration_end"` call at line 1032 hardcodes `\"files_changed\":0` instead of using this variable. The fix: right before the `emit_event "iteration_end"` at line 1032, compute `local files_changed_count; files_changed_count=$(git diff --name-only HEAD~1 2>/dev/null | wc -l)` and replace `\"files_changed\":0` with `\"files_changed\":${files_changed_count:-0}`. Note: the existing `files_changed` at line 690 is a JSON array (for agent history); the event needs an integer count. Apply to `templates/automaton.sh`. (WHY: stall detection in `lib/qa.sh` relies on `files_changed` from work-log events; hardcoded 0 makes every iteration look stalled) <!-- test: grep iteration_end .automaton/work-log.jsonl and verify files_changed > 0 after a build run -->

### 31.2 Fix complexity assessment prompt template

- [x] In `assess_complexity()` in `lib/qa.sh`, find the prompt template string containing `"SIMPLE|MODERATE|COMPLEX"` (around line 1290). Change the JSON example from `{"tier": "SIMPLE|MODERATE|COMPLEX", "rationale": "one-line reason"}` to `{"tier": "MODERATE", "rationale": "one-line reason"}`. Add a comment above: `# Valid tier values: SIMPLE, MODERATE, COMPLEX`. The pipe-delimited string causes Haiku to return the literal `"SIMPLE|MODERATE|COMPLEX"` which fails the bash `case` match. Apply to `templates/lib/qa.sh`. (WHY: complexity assessment defaults to MODERATE for ALL tasks because the model returns the template literal instead of a single value) <!-- test: tests/test_utilities_functional.sh -->

### 31.3 Add stderr capture to agent failure events

- [x] At `automaton.sh:966`, the error event is: `emit_event "error" "{\"message\":\"agent exit code ${AGENT_EXIT_CODE}\",\"fatal\":false}"`. Expand to capture diagnostic detail from `$AGENT_RESULT`. Before the emit_event, compute: `local error_detail; error_detail=$(printf '%s' "$AGENT_RESULT" | tail -10 | jq -Rs '.' 2>/dev/null || echo '"(no output)"')`. Then change the emit to: `emit_event "error" "{\"message\":\"agent exit code ${AGENT_EXIT_CODE}\",\"fatal\":false,\"detail\":${error_detail}}"`. Apply to `templates/automaton.sh`. (WHY: run-2026-03-12T14:00 had 3 consecutive exit-code-1 failures with no way to diagnose cause — only the numeric exit code was logged) <!-- test: verify error events in work-log.jsonl contain detail field after a forced failure -->

### 31.4 Fix research max_iterations not enforced

- [x] Root cause: `automaton.sh:927-931` — when `phase_iteration > max_iter`, the inner loop breaks but first decrements `phase_iteration` back to `max_iter - 1` (line 929). The outer loop then re-enters the `research` case, and the gate check at line 1056 (`phase_iteration < max_iter`) evaluates true because of the decrement — allowing another full cycle of inner-loop iterations. Fix: add `local max_iter_reached=false` before the outer while loop (around line 870). In the max_iter break block (lines 927-931), add `max_iter_reached=true` before `break`. In the research gate check (line 1056), change `[ "$phase_iteration" -lt "$max_iter" ]` to `[ "$phase_iteration" -lt "$max_iter" ] && [ "$max_iter_reached" != "true" ]`. Reset `max_iter_reached=false` in `transition_to_phase()`. Apply to `templates/automaton.sh`. (WHY: config says max 3 research iterations but runs show 5 — the decrement-before-break causes the outer loop to re-enter research) <!-- test: run with max_iterations.research=2 and verify exactly 2 research iterations in work-log -->


---

## Tier 32: Phase Skip & Guard Rail Fixes (Priority: HIGH)

Prevent wasted iterations when phases have nothing to do. Tasks 32.1 and 32.2 are independent; 32.3 is independent of both.

### 32.1 Auto-skip research when all specs are implemented

- [x] In `automaton.sh`, after the starting state block (lines 815-827) and before the outer while loop, add a research skip check. The logic: if `current_phase = "research"` AND `IMPLEMENTATION_PLAN.md` exists AND has 0 unchecked tasks, then transition to plan phase. Implemented in the phase loop pre-checks (before `--skip-review` check). Apply to `templates/automaton.sh`. (WHY: research phase ran 5 iterations with 0 file changes because all specs were already implemented -- wastes ~7 minutes and ~2M tokens per self-build run) <!-- test: run self-build with all tasks [x] and verify research is skipped -->

### 32.2 Plan phase: detect all-tasks-complete before planning

- [x] In the plan gate block (`automaton.sh:1066-1080`), add a pre-check BEFORE calling `gate_check "plan_validity"`. The check: if `IMPLEMENTATION_PLAN.md` exists AND has 0 unchecked tasks, then log "All plan tasks already complete -- skipping to build" and call `transition_to_phase "build"` followed by `continue`. Implemented in the phase loop pre-checks (before `--skip-review` check). Apply to `templates/automaton.sh`. (WHY: run-2026-03-11T21:09 escalated because the planner couldn't produce a valid plan when nothing remained -- the gate requires >=5 unchecked tasks, which is impossible when everything is done) <!-- test: create IMPLEMENTATION_PLAN.md with all [x] tasks, verify plan phase auto-skips -->

### 32.3 Auto-refresh AGENTS.md at run start

- [x] In `automaton.sh`, right after the starting-state block (after line 827, before the pre-flight spec critique at line 829), add: `generate_agents_md 2>/dev/null || true`. The function already exists in `lib/lifecycle.sh:748` and is already called at line 742 during initialization. Adding it here ensures AGENTS.md is also refreshed on `--resume` runs (the line 742 call only fires for fresh runs). Apply to `templates/automaton.sh`. (WHY: AGENTS.md shows stale phase "research", run count "2", and missing 4+ recent runs -- misleads both humans and agents reading it for context) <!-- test: verify AGENTS.md reflects accurate state after a run start -->

---

## Tier 33: Spec 61 -- Collaboration Mode (Priority: MEDIUM)

Foundation for specs 62-64. All new functionality; no existing code modified beyond wiring. Depends on Tiers 31-32 being stable.

### 33.1 Create lib/collaborate.sh core module

- [ ] Create `lib/collaborate.sh` (~250 lines) with: `checkpoint()` function (the core -- checks mode, TTY, generates summary, writes audit file, presents choices, dispatches); `generate_checkpoint_summary()` (phase-specific summary generation reading state.json, IMPLEMENTATION_PLAN.md, traceability.json); `handle_modify()` (launches interactive `claude` session with context files); `handle_pause()` (writes `checkpoint_paused_at` to state.json, exits 0); `handle_abort()` (writes state, exits 1). Create matching `templates/lib/collaborate.sh`. (WHY: AC-61-1 through AC-61-9 -- this is the entire checkpoint system) <!-- test: tests/test_collaborate.sh -->

### 33.2 Add --mode CLI flag and config

- [ ] Add `--mode` CLI flag parsing to `automaton.sh` (alongside existing --skip-research etc.): `--mode) ARG_MODE="$2"; shift 2`. Add `collaboration` config section to `automaton.config.json` and `templates/automaton.config.json`: `{"collaboration": {"mode": "collaborative", "checkpoint_dir": ".automaton/checkpoints"}}`. Load in `lib/config.sh` with CLI override. Add to help text in `lib/display.sh`. (WHY: AC-61-10 -- CLI flag must override config) <!-- test: tests/test_cli_args.sh -->

### 33.3 Wire checkpoints into phase transitions

- [ ] In `automaton.sh`, source `lib/collaborate.sh` and call `checkpoint "after_research"` after line 1051 (research-to-plan transition), `checkpoint "after_plan"` after line 1074 (plan-to-build transition), `checkpoint "after_review"` before the COMPLETE transition in review gate. Handle `--resume` detection of `checkpoint_paused_at` in state.json at startup. Apply to `templates/automaton.sh`. (WHY: AC-61-1 -- checkpoints at all 3 phase transitions) <!-- test: tests/test_collaborate.sh -->

### 33.4 Add educational annotation injection

- [ ] In `lib/context.sh`, when `COLLABORATION_MODE != "autonomous"`, append educational context blocks to phase prompts: "Why This Matters" for research, "Rationale" instructions for plan, "Learning Opportunity" for review. Gate on `COLLABORATION_MODE` variable. Apply to `templates/lib/context.sh`. (WHY: AC-61-11 -- educational annotations in collaborative mode) <!-- test: tests/test_collaborate.sh -->

### 33.5 Update setup wizard

- [ ] In `lib/config.sh` `run_setup_wizard()`, add collaboration mode question after existing questions: "How would you like automaton to work? 1. Collaborative (recommended) 2. Autonomous". Default: 1. Write choice to config. Apply to `templates/lib/config.sh`. (WHY: spec-61 section 11 -- discoverability for new users) <!-- test: tests/test_setup_wizard.sh -->

---

## Tier 34: Spec 64 -- Wizard Discovery & Spec 63 -- Deep Research (Priority: MEDIUM)

These are largely prompt-only changes (spec 64) and a new standalone mode (spec 63). Can be built in parallel. Spec 63 standalone mode works without spec 61; collaborative integration (34.5) depends on Tier 33.

### 34.1 Add Discovery Stage to wizard and converse prompts

- [ ] Edit `PROMPT_wizard.md`: add Stage 0 (Discovery) before existing Stage 1. Include vagueness detection heuristics, 2-3 open-ended questions, 3-direction suggestion format, rejection/combination handling, transition signal. Edit `PROMPT_converse.md` with same discovery capability. Gate educational framing on `COLLABORATION_MODE` context variable (injected by spec-61's system). Apply edits to `templates/PROMPT_wizard.md` and `templates/PROMPT_converse.md`. (WHY: AC-64-1 through AC-64-9 -- entirely prompt-driven, no bash changes) <!-- test: tests/test_wizard_discovery.sh -->

### 34.2 Create PROMPT_deep_research.md

- [ ] Create `PROMPT_deep_research.md` (~100 lines) instructing Claude to: understand domain from topic + PRD/specs, research 3-5 approaches via web search, produce comparative matrix, make recommendation. Output format per spec-63 section 4. Create matching `templates/PROMPT_deep_research.md`. (WHY: AC-63-1 through AC-63-4 -- the research prompt drives the quality of output) <!-- test: tests/test_deep_research.sh -->

### 34.3 Add --research CLI flag and dispatch

- [ ] Add `--research` CLI flag to `automaton.sh`: `--research) ARG_RESEARCH_TOPIC="$2"; shift 2`. Add dispatch: if `ARG_RESEARCH_TOPIC` is set, run `run_deep_research "$ARG_RESEARCH_TOPIC"` and exit (standalone mode, no phase loop). Implement `run_deep_research()` in `lib/collaborate.sh` or a new `lib/research.sh`: sanitize topic for filename, create `.automaton/research/` dir, invoke claude with PROMPT_deep_research.md + topic context, enforce `research.deep_research_budget` token limit, write output to `RESEARCH-{topic}-{timestamp}.md`. Add config keys `research.deep_research_budget` (200000) and `research.deep_research_model` ("sonnet") to config files. Add to help text. Apply to templates. (WHY: AC-63-1, AC-63-5, AC-63-6, AC-63-8 -- standalone deep research mode) <!-- test: tests/test_deep_research.sh -->

### 34.4 Include research documents in plan phase context

- [ ] In `lib/context.sh`, when building plan phase context, check for `.automaton/research/RESEARCH-*.md` files and include their content (or summaries if too large) in the dynamic context. (WHY: AC-63-7 -- research findings should inform planning decisions) <!-- test: tests/test_deep_research.sh -->

### 34.5 Add [r]esearch option to after_research checkpoint (depends on 33.1)

- [ ] In `lib/collaborate.sh`, when displaying the `after_research` checkpoint choices, add `[r]esearch` option. When selected, prompt for topic, call `run_deep_research()`, then re-display checkpoint. (WHY: AC-63-9 -- collaborative mode integration) <!-- test: tests/test_collaborate.sh -->

---

## Build Order Summary

**Recommended next task**: 31.1 (files_changed fix) -- lowest risk, highest observability impact, 1 line change + template sync.

**Tier 31** (4 tasks, all independent, all LOW effort): Fix data collection bugs that degrade stall detection and diagnostics. Build in any order. Each task is a 1-5 line change in automaton.sh or lib/qa.sh plus template sync.

**Tier 32** (3 tasks, all independent, all LOW effort): Prevent wasted iterations. 32.1 saves ~2M tokens per self-build run. 32.2 prevents false escalations. 32.3 is cosmetic but improves agent context.

**Tier 33** (5 tasks, sequential 33.1->33.2->33.3, then 33.4/33.5 independent): New collaboration mode. MEDIUM effort. 33.1 is the core module (~250 lines new code).

**Tier 34** (5 tasks, 34.1/34.2 independent, 34.3 depends on 34.2, 34.5 depends on 33.1): Prompt changes + standalone research mode. 34.1 and 34.2 are LOW effort prompt-only tasks.

**Total remaining**: 17 unchecked tasks across 4 tiers.

---

## Spec Conflicts Noted

- **Root vs template PROMPT files**: Root `PROMPT_build.md` (58 lines) and `PROMPT_plan.md` (41 lines) diverge significantly from their template counterparts (157 and 101 lines). The templates appear authoritative (they have spec-29 XML structure, spec-36 annotations, etc.) but the root versions are what the orchestrator actually uses. Tier 17 addresses this.

- **Audit 03 vs evolution specs (38-45)**: The audit recommends freezing evolution features until the core pipeline is proven on 5+ projects. Evolution specs are fully implemented but the audit considers them premature. This plan follows the audit's recommendation by prioritizing core pipeline improvements (Tiers 19-23) over new evolution work.
