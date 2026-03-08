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

- [ ] Add `AUTOMATON_INSTALL_DIR` variable to `automaton.sh` (set to `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`) and make `AUTOMATON_DIR` absolute (`$(pwd)/.automaton`) (WHY: scope flag requires decoupling where agents work (`PROJECT_ROOT`) from where state lives (`AUTOMATON_DIR`) and where prompts live (`AUTOMATON_INSTALL_DIR`) — currently these are conflated) <!-- test: tests/test_scope.sh -->

- [ ] Add `ARG_SCOPE=""` default and `--scope` case branch to CLI argument parsing in `automaton.sh` (WHY: the entry point for the feature — parses the path argument and stores it for resolution) <!-- test: tests/test_cli_args.sh -->

- [ ] Implement path resolution block after argument parsing: resolve relative→absolute via `cd "$path" && pwd`, validate directory exists, set `PROJECT_ROOT` (WHY: invalid paths must fail early with clear error messages before any phase dispatch) <!-- test: tests/test_scope.sh -->

- [ ] Add mutual exclusion check: `--scope` + `--self` exits with error (WHY: self-build targets automaton's own directory, so scoping to a subdirectory is contradictory) <!-- test: tests/test_scope.sh -->

### 60.2 Agent Invocation Changes

- [ ] Update `get_phase_prompt()` in `lib/utilities.sh` to prefix paths with `$AUTOMATON_INSTALL_DIR/` instead of relative paths (WHY: when agent cwd changes to the scoped directory, relative prompt paths break — prompts live alongside automaton.sh, not in the scoped dir) <!-- test: tests/test_scope.sh -->

- [ ] Wrap `claude` invocation in `run_agent()` (`lib/utilities.sh`) with `(cd "$PROJECT_ROOT" && ...)` subshell (WHY: agents must operate within the scoped directory, but the orchestrator must stay at its own cwd to manage state) <!-- test: tests/test_scope.sh -->

- [ ] Export `AUTOMATON_PROJECT_ROOT="$PROJECT_ROOT"` before agent invocation (WHY: hooks read this environment variable to determine the project root — without it, hooks in scoped mode operate on the wrong directory) <!-- test: tests/test_scope.sh -->

### 60.3 Parallel Mode & Bootstrap

- [ ] Update `spawn_builders()` in `lib/parallel.sh` to use `${PROJECT_ROOT:-$(pwd)}` instead of `$(pwd)` (WHY: parallel builders must inherit the scoped directory, not the orchestrator's cwd) <!-- test: tests/test_scope.sh -->

- [ ] Update `generate_builder_wrapper()` in `lib/parallel.sh` to bake in `AUTOMATON_INSTALL_DIR` and absolute `AUTOMATON_DIR` as template placeholders (WHY: standalone wrapper scripts can't inherit shell state — they need hard-coded paths to find prompts and state files) <!-- test: tests/test_scope.sh -->

- [ ] Update `generate_bootstrap_script()` template in `lib/state.sh` to read `AUTOMATON_DIR` from environment with fallback: `AUTOMATON_DIR="${AUTOMATON_DIR:-$PROJECT_ROOT/.automaton}"` (WHY: backward-compatible — when AUTOMATON_DIR isn't exported, the old derivation still works; when scoped, it uses the correct absolute path) <!-- test: tests/test_scope.sh -->

### 60.4 Display & Help

- [ ] Add `Scope:` line to startup banner in `automaton.sh` (only when scope differs from cwd) (WHY: users need visual confirmation of which directory agents will operate in — omitting it when scope=cwd avoids noise) <!-- test: tests/test_scope.sh -->

- [ ] Add `--scope PATH` to `_show_help()` in `lib/display.sh` (WHY: discoverability — users must know the flag exists to use it) <!-- test: tests/test_cli_help.sh -->

### 60.5 Tests

- [ ] Create `tests/test_scope.sh` with integration tests: relative path resolution, absolute path passthrough, non-existent path error, file-not-dir error, `--scope .` no-op, `AUTOMATON_DIR` stays cwd-anchored, `--scope` + `--self` mutual exclusion (WHY: 7 distinct code paths need test coverage to prevent regressions) <!-- test: tests/test_scope.sh -->

- [ ] Add `ARG_SCOPE` test cases to `tests/test_cli_args.sh`: default is empty, `--scope /tmp` sets value, `--scope` with no argument errors, combined flags work (WHY: existing CLI arg tests must cover the new flag to maintain comprehensive CLI test coverage) <!-- test: tests/test_cli_args.sh -->

---

## Tier 19: Audit Wave 1 — Test Infrastructure Foundation

From audit finding 04-A (bash at scale) and 04-B (shellcheck). No code changes to the orchestrator itself.

- [x] Create `run_tests.sh` that discovers and runs all `tests/test_*.sh`, counts pass/fail, exits non-zero on failure (WHY: 158 test files exist but no way to run them all at once — this is prerequisite for CI, review gate integration, and self-build validation) <!-- test: none -->

- [ ] Add `shellcheck automaton.sh lib/*.sh` as a mandatory check in `PROMPT_review.md` (WHY: bash has no type system — shellcheck catches undefined variables, word splitting, and quoting bugs that cause silent failures at 17K lines) <!-- test: none -->

- [ ] Add `## Edge Cases` section to `templates/PROMPT_converse.md` spec template and update conversation prompt to push for edge case enumeration (WHY: specs currently lack explicit edge case sections — boundary conditions get discovered/missed during build instead of being planned for) <!-- test: none -->

---

## Tier 20: Audit Wave 2 — Spec Traceability

From audit finding 01 (spec-to-code traceability gap). The #1 gap for hit rate — requirements can be silently dropped without detection.

- [ ] Update `PROMPT_plan.md` (template version) to require acceptance criteria extraction from specs as `AC-XX-Y` items grouped under each spec section in the plan (WHY: without structured acceptance criteria in the plan, the review agent checks "does code work" instead of "does code cover all spec requirements") <!-- test: none -->

- [ ] Add traceability verification pass to `PROMPT_review.md` (template version): "For each AC-XX-Y, verify implementation evidence" before existing code review steps (WHY: creates the feedback loop — review catches requirements that were silently dropped during build) <!-- test: none -->

- [ ] Add instruction to `PROMPT_review.md` to generate `.automaton/traceability.json` mapping each AC to pass/fail with evidence (WHY: makes traceability auditable and machine-readable — enables future automated regression detection) <!-- test: none -->

---

## Tier 21: Audit Wave 3 — Test-Driven Spec Compliance

From audit findings 06 (acceptance test generation) and 07-#2 (red-before-green gate). Depends on Wave 2 (needs AC extraction format).

- [ ] Update `PROMPT_plan.md` (template version) to generate test skeleton files from acceptance criteria: each AC becomes a test function with `assert_fail "Not yet implemented"` (WHY: separates test authorship from implementation authorship — prevents confirmation bias where the same agent writes both test and code) <!-- test: none -->

- [ ] Add red-before-green gate in `lib/lifecycle.sh` or `lib/qa.sh`: after plan phase, run test suite and record failure count; after build, verify failure count decreased (WHY: proves implementation actually made progress — if tests pass before AND after, the tests may not be testing the right thing) <!-- test: tests/test_red_green_gate.sh -->

- [ ] Update `PROMPT_build.md` (template version) to instruct: "Find pre-existing test skeletons. Implement code to make them pass. Do NOT modify skeleton test assertions." (WHY: true TDD — tests exist before code, builder has concrete targets instead of writing tests to match what they built) <!-- test: none -->

---

## Tier 22: Audit Wave 4 — Incremental Verification

From audit finding 02 (missing incremental verification). Adds per-task validation to catch bugs early instead of reviewing everything at the end.

- [ ] Create micro-validation prompt (~30 lines) for lightweight post-task Sonnet check on specific acceptance criterion (WHY: catches bugs in task N before task N+1 compounds them — prevents 500K+ token cost of failed review → rebuild cycles; estimated net savings 60-80%) <!-- test: none -->

- [ ] Implement post-task micro-validation in build loop (`lib/lifecycle.sh`): after each build iteration, run lightweight 2K-token Sonnet check (WHY: batch-and-check is the current anti-pattern — this adds the "verify small" discipline from VSDD) <!-- test: tests/test_micro_validation.sh -->

- [ ] Track `git diff --stat` per iteration in `.automaton/agents/` and provide per-task diffs to review agent (WHY: review currently gets one giant diff — per-task breakdown reduces review context size and improves accuracy) <!-- test: none -->

- [ ] Add early escalation: if micro-validation fails 2 consecutive tasks, force transition to review phase (WHY: extends existing stall detection — continuing to build on top of broken tasks wastes tokens) <!-- test: tests/test_micro_validation.sh -->

---

## Tier 23: Audit Wave 5 — Token Optimization

From audit finding 05 (token waste). Depends on Waves 2+4 for traceability data.

- [ ] Split review into tiered passes: (1) Sonnet mechanical pass (tests/lint/typecheck → binary pass/fail), (2) Opus judgment pass only if mechanical passes (WHY: saves Opus tokens on mechanically-failing runs — estimated 40-60% review cost reduction) <!-- test: none -->

- [ ] Implement delta-only review context: include only changed files and related specs via traceability map, not entire codebase (WHY: estimated 30-50% input token reduction — review currently reads everything) <!-- test: none -->

- [ ] Add QA oscillation detection in `lib/qa.sh`: track failing test sets across iterations, detect if same test fails→fixed→re-fails pattern, escalate instead of retrying (WHY: prevents 2-3 wasted QA cycles when fixes are fighting each other) <!-- test: tests/test_qa_oscillation.sh -->

---

## Tier 24: Audit Wave 6 — Advanced Process (Optional)

From audit finding 07 (VSDD process extraction). Lower priority — implement after Waves 1-5 are proven on real projects.

- [ ] Add review confidence scoring: review agent rates confidence (1-5) across spec coverage, test quality, code quality, regression risk; all ≥4 = complete, any <3 = create tasks (WHY: completion is currently binary — gradient scoring catches "barely passing" reviews that need more work) <!-- test: none -->

- [ ] Add feedback level routing: review classifies issues as spec-level, test-level, or implementation-level; spec-level issues create spec amendment proposals instead of build tasks (WHY: prevents building against flawed specs — if review finds an ambiguous requirement, fixing the spec is better than working around it) <!-- test: none -->

- [ ] Implement living spec amendments: build agent proposes spec amendments to `.automaton/spec-amendments.json`, review evaluates, approved amendments update specs (WHY: specs currently freeze after Phase 0 — when builder discovers a requirement is impossible/wrong, the spec should evolve) <!-- test: none -->

---

## Spec Conflicts Noted

- **Root vs template PROMPT files**: Root `PROMPT_build.md` (58 lines) and `PROMPT_plan.md` (41 lines) diverge significantly from their template counterparts (157 and 101 lines). The templates appear authoritative (they have spec-29 XML structure, spec-36 annotations, etc.) but the root versions are what the orchestrator actually uses. Tier 17 addresses this.

- **Audit 03 vs evolution specs (38-45)**: The audit recommends freezing evolution features until the core pipeline is proven on 5+ projects. Evolution specs are fully implemented but the audit considers them premature. This plan follows the audit's recommendation by prioritizing core pipeline improvements (Tiers 19-23) over new evolution work.
