# Implementation Plan

<!-- Dependency-ordered task list for building the automaton orchestration system. -->
<!-- Tasks within each group are ordered by internal dependencies. -->
<!-- Groups are ordered so that foundational infrastructure comes before features that depend on it. -->
<!-- PROMPT_plan.md and PROMPT_build.md already exist and are used as-is (per spec-04, spec-05). -->
<!-- Parallel builder mode (spec-05, parallel_builders > 1) is deferred: infrastructure is created but execution logic is future work. -->
<!-- Spec contradiction noted: spec-07 says per-iteration budget exceeded is a warning; PRD says "kill agent". Plan follows spec-07 (warning only). -->

## 1. Project Scaffolding & Package Setup

- [x] Create `package.json` with name, version, description, bin entry pointing to `bin/cli.js`, files array including `bin/` and `templates/`, keywords, and MIT license (WHY: npm distribution requires a valid package.json before anything else; spec-13 defines the exact schema)
- [x] Create `bin/cli.js` scaffolding CLI that copies templates to the user's project directory, creates `specs/` and `.automaton/` directories, makes `automaton.sh` executable, appends `.automaton/` to `.gitignore`, includes overwrite protection for user-content files (specs/, PRD.md, AGENTS.md), checks system dependencies (claude, jq, git), and prints the getting-started banner (WHY: this is the entry point users interact with first; it must exist before templates are finalized so we can test the full scaffold flow; spec-13)

## 2. Configuration System

- [x] Create `automaton.config.json` template with the full default schema covering models, budget, rate_limits, execution, git, and flags sections (WHY: every module reads config values; the template must exist before any bash function can reference it; spec-12 defines the complete schema)
- [ ] Write the `load_config()` bash function that reads `automaton.config.json` with jq, falls back to hardcoded defaults for every missing key, and stores values in shell variables (WHY: this is the first function called by automaton.sh on startup; all other modules depend on config variables being populated; spec-12)

## 3. State Management

- [ ] Write the `initialize()` function that creates `.automaton/`, `.automaton/agents/`, `.automaton/worktrees/`, `.automaton/inbox/` directories, initializes `state.json` with zeroed counters, and creates an empty `session.log` (WHY: every iteration reads/writes state files; initialization must happen before the first agent runs; spec-10)
- [ ] Write the `log()` function that appends timestamped `[ISO-8601] [COMPONENT] MESSAGE` lines to `.automaton/session.log` and echoes to stdout (WHY: every module calls log(); it must exist before anything that produces output; spec-10)
- [ ] Write `write_state()` using atomic temp-file-then-mv pattern to update `state.json` after each iteration (WHY: crash-safe state persistence is critical for resume support; spec-10)
- [ ] Write `read_state()` for the `--resume` path that parses `state.json` with jq and restores phase, iteration, phase_iteration, stall_count, and other counters into shell variables, resetting consecutive_failures to 0 (WHY: resume must restore exact position in the phase sequence; spec-10)
- [ ] Write agent history file creation: after each agent invocation, write a `{phase}-{NNN}.json` file to `.automaton/agents/` recording phase, iteration, model, tokens, cost, duration, task, status, files_changed, and git_commit (WHY: per-agent history enables debugging and post-run analysis; spec-10)

## 4. Token Tracking & Budget

- [ ] Write `initialize_budget()` that creates `.automaton/budget.json` from config limits with zeroed usage counters and an empty history array (WHY: budget tracking starts on first iteration; the file must exist before any agent runs; spec-07)
- [ ] Write `extract_tokens()` that parses the stream-json result string to find the `"type":"result"` line and extracts input_tokens, output_tokens, cache_creation_input_tokens, and cache_read_input_tokens using jq (WHY: this is the raw data source for all cost tracking; called after every agent invocation; spec-07)
- [ ] Write `estimate_cost()` that takes a model name and four token counts, applies the pricing table (opus/sonnet/haiku rates from spec-07), and returns the estimated USD cost (WHY: cost estimation feeds into budget enforcement and display; spec-07)
- [ ] Write `update_budget()` that adds iteration tokens to cumulative totals in budget.json, appends a history entry, and recalculates estimated_cost_usd using atomic write (WHY: budget.json is the single source of truth for cost tracking across the entire run; spec-07)
- [ ] Write `check_budget()` that enforces four rules: per-iteration warning, per-phase force-transition, total-token hard stop (exit 2), and cost-USD hard stop (exit 2), logging the appropriate message for each (WHY: budget enforcement prevents runaway costs; the four tiers ensure graceful degradation rather than abrupt failure; spec-07)

## 5. Rate Limiting

- [ ] Write `handle_rate_limit()` implementing exponential backoff: starting at cooldown_seconds, retrying up to 5 times with backoff_multiplier, capping at max_backoff_seconds, and triggering a 10-minute pause after 5 consecutive failures (WHY: rate limits are the most common transient failure; proper backoff prevents wasted iterations; spec-08)
- [ ] Write `check_pacing()` that calculates token velocity over the last 3 iterations from budget.json history and inserts a sleep if velocity exceeds 80% of tokens_per_minute (WHY: proactive pacing avoids rate limits rather than reacting to them; spec-08)

## 6. Error Handling & Recovery

- [ ] Write `is_rate_limit()` and `is_network_error()` classification helpers that grep agent output for known error signatures (WHY: error classification determines which recovery path to take; must exist before the main iteration loop; spec-09)
- [ ] Write the CLI crash handler: increment consecutive_failures on non-zero exit that is not a rate limit or network error, retry with delay up to max_consecutive_failures, then save state and exit 1 (WHY: transient CLI crashes should not abort the entire run; spec-09)
- [ ] Write stall detection: after each build iteration, check `git diff --stat HEAD~1` for emptiness, increment stall_count if empty, reset on changes, force re-plan after stall_threshold consecutive stalls, escalate after 2 re-plans (WHY: stall detection catches agents that claim progress without producing code; spec-09)
- [ ] Write plan corruption guard: checkpoint IMPLEMENTATION_PLAN.md before each iteration, verify [x] count did not decrease after, restore from checkpoint if corrupted, escalate after 2 corruptions (WHY: agents occasionally rewrite the plan and destroy completed work; this is the safety net; spec-09)
- [ ] Write `escalate()` function that logs the escalation, appends an ESCALATION section to IMPLEMENTATION_PLAN.md, saves state, commits, and exits with code 3 (WHY: when automated recovery fails, the system must stop cleanly and hand off to a human; spec-09)
- [ ] Write optional phase timeout check: compare elapsed wallclock time against phase_timeout_seconds from config, force phase transition if exceeded (WHY: safety net for unattended runs where a phase might loop indefinitely; spec-09)

## 7. Quality Gates

- [ ] Write `gate_check()` wrapper that calls the named gate function, logs PASS/FAIL, and returns the gate's exit code (WHY: uniform gate invocation with logging; called at every phase transition; spec-11)
- [ ] Write `gate_spec_completeness()` checking for at least one spec file, non-empty PRD.md, and AGENTS.md without placeholder values (WHY: Gate 1 prevents starting autonomous work on incomplete inputs; spec-11)
- [ ] Write `gate_research_completeness()` checking AGENTS.md growth and absence of TBD/TODO in specs (WHY: Gate 2 ensures research actually resolved unknowns before planning begins; spec-11)
- [ ] Write `gate_plan_validity()` checking for at least 5 unchecked tasks, plan length over 10 lines, and heuristic spec references (WHY: Gate 3 ensures the plan is substantive enough to drive a build phase; spec-11)
- [ ] Write `gate_build_completion()` checking for zero unchecked tasks, git commit existence, and test file presence (WHY: Gate 4 confirms the build phase actually produced complete work; spec-11)
- [ ] Write `gate_review_pass()` checking for zero unchecked tasks and no ESCALATION markers (WHY: Gate 5 is the final quality check that determines COMPLETE vs return-to-build; spec-11)

## 8. Prompt Files

- [ ] Write `PROMPT_converse.md` for Phase 0: instruct Claude to interview the user, challenge vague requirements, write numbered spec files with Purpose/Requirements/Acceptance Criteria/Dependencies sections, write PRD.md, update AGENTS.md with project name and tech fields, and signal handoff when specs are complete (WHY: the conversation phase prompt defines the entire requirements-gathering UX; spec-02)
- [ ] Write `PROMPT_research.md` for Phase 1: instruct Claude to read all specs and PRD.md, identify TBD/TODO/unknown markers, web search to resolve them, enrich specs with concrete technology decisions and rationale, update AGENTS.md with language/framework/commands, and output COMPLETE when done (WHY: the research prompt drives autonomous technology decision-making; spec-03)
- [ ] Write `PROMPT_review.md` for Phase 4: instruct Claude to read all specs, run the full validation suite (test/lint/typecheck/build from AGENTS.md), perform spec coverage analysis, check code quality, and either output COMPLETE or create new [ ] tasks in IMPLEMENTATION_PLAN.md (WHY: the review prompt is the independent verification that closes the loop; spec-06)

## 9. Orchestrator Main Script (automaton.sh)

- [ ] Write CLI argument parsing for `--resume`, `--skip-research`, `--skip-review`, `--config FILE`, and `--dry-run`, storing flags in variables (WHY: argument parsing is the entry point; it determines which code paths execute; spec-01)
- [ ] Write system dependency checks for claude, jq, and git with clear install instructions on failure (WHY: automaton.sh depends on all three; failing fast with a helpful message prevents confusing errors later; spec-13)
- [ ] Write signal handlers for SIGINT (save state, log interruption, exit 130), SIGTERM (same as SIGINT), and SIGHUP (ignored for background execution) (WHY: graceful shutdown preserves state for resume; spec-01)
- [ ] Write the startup banner displaying version, current phase, budget limits, config file path, and git branch (WHY: the banner orients the user at launch; spec-01)
- [ ] Write the `run_agent()` function that invokes `claude -p` with the appropriate prompt file, model, --dangerously-skip-permissions, --output-format=stream-json, and --verbose flags, captures the result, and returns the exit code (WHY: centralizes agent invocation so token extraction, error handling, and logging happen consistently; spec-01)
- [ ] Write the phase sequence controller: a loop that progresses through research, plan, build, review with gate checks at each transition, handles --skip-research and --skip-review, transitions back to build on review failure, and declares COMPLETE when Gate 5 passes (WHY: this is the core orchestration logic that ties all modules together; spec-01)
- [ ] Write the per-iteration post-processing pipeline: extract tokens, update budget, check budget limits, check pacing, detect stalls (build phase only), check plan integrity (build phase only), write state, write agent history, log iteration summary, emit one-line stdout status, and push to git if configured (WHY: this pipeline runs after every agent invocation and integrates all subsystems; spec-01, spec-05, spec-07, spec-08, spec-09, spec-10)
- [ ] Wire the `--resume` path: read state, restore counters, skip to the saved phase, log RESUMED, and enter the phase sequence loop at the correct point (WHY: resume support is essential for long-running autonomous sessions that may be interrupted; spec-10)
- [ ] Implement `--dry-run` mode: load config, run Gate 1, display the startup banner with all resolved settings, show which phases would run, and exit 0 without invoking any agents (WHY: dry-run lets users verify configuration before committing to a potentially expensive autonomous run; spec-01)

## 10. Templates Directory Finalization

- [ ] Copy all scaffoldable files into `templates/`: automaton.sh, automaton.config.json, PROMPT_converse.md, PROMPT_research.md, PROMPT_plan.md, PROMPT_build.md, PROMPT_review.md, AGENTS.md, IMPLEMENTATION_PLAN.md, CLAUDE.md, PRD.md (WHY: bin/cli.js copies from templates/; every file the user gets must have a template source; spec-13)
- [ ] Update `templates/AGENTS.md` to replace "thesis-map" with a generic placeholder like "your-project" and set language/framework to "(to be filled by conversation phase)" (WHY: the template should not reference a specific project; it is a blank starting point for any new user; spec-02)
