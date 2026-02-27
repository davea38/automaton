# Implementation Plan

<!-- Dependency-ordered task list for building the automaton orchestration system. -->
<!-- Tasks within each group are ordered by internal dependencies. -->
<!-- Groups are ordered so that foundational infrastructure comes before features that depend on it. -->
<!-- PROMPT_plan.md and PROMPT_build.md already exist and are used as-is (per spec-04, spec-05). -->
<!-- Spec contradiction noted: spec-07 says per-iteration budget exceeded is a warning; PRD says "kill agent". Plan follows spec-07 (warning only). -->
<!-- Spec contradiction noted: spec-14 says execution.parallel_builders is "superseded" by parallel.max_builders, but spec-05 still references execution.parallel_builders for parallel mode. Plan treats parallel.max_builders as the authoritative key when parallel.enabled=true. -->
<!-- Spec contradiction noted: spec-17 builder-wrapper.sh takes 3 args ($1=builder, $2=wave, $3=project_root) but spec-15 spawn_builders() invokes it with only 2 args ($i $wave). Plan follows spec-17 (3 args) and fixes the spawn call. -->
<!-- Spec contradiction noted: spec-19 handle_coordination_conflict() references $builder_branch as a free variable but it should be passed as a parameter or derived from wave/builder args. Plan passes it explicitly. -->
<!-- Spec contradiction noted: spec-20 check_wave_budget() takes $1=wave in spec-16 code but $1=builder_count in spec-20 code. Plan uses wave as $1 and reads builder_count from assignments.json (spec-16 version). -->

## 1. Project Scaffolding & Package Setup

- [x] Create `package.json` with name, version, description, bin entry pointing to `bin/cli.js`, files array including `bin/` and `templates/`, keywords, and MIT license (WHY: npm distribution requires a valid package.json before anything else; spec-13 defines the exact schema)
- [x] Create `bin/cli.js` scaffolding CLI that copies templates to the user's project directory, creates `specs/` and `.automaton/` directories, makes `automaton.sh` executable, appends `.automaton/` to `.gitignore`, includes overwrite protection for user-content files (specs/, PRD.md, AGENTS.md), checks system dependencies (claude, jq, git), and prints the getting-started banner (WHY: this is the entry point users interact with first; it must exist before templates are finalized so we can test the full scaffold flow; spec-13)

## 2. Configuration System

- [x] Create `automaton.config.json` template with the full default schema covering models, budget, rate_limits, execution, git, and flags sections (WHY: every module reads config values; the template must exist before any bash function can reference it; spec-12 defines the complete schema)
- [x] Write the `load_config()` bash function that reads `automaton.config.json` with jq, falls back to hardcoded defaults for every missing key, and stores values in shell variables (WHY: this is the first function called by automaton.sh on startup; all other modules depend on config variables being populated; spec-12)

## 3. State Management

- [x] Write the `initialize()` function that creates `.automaton/`, `.automaton/agents/`, `.automaton/worktrees/`, `.automaton/inbox/` directories, initializes `state.json` with zeroed counters, and creates an empty `session.log` (WHY: every iteration reads/writes state files; initialization must happen before the first agent runs; spec-10)
- [x] Write the `log()` function that appends timestamped `[ISO-8601] [COMPONENT] MESSAGE` lines to `.automaton/session.log` and echoes to stdout (WHY: every module calls log(); it must exist before anything that produces output; spec-10)
- [x] Write `write_state()` using atomic temp-file-then-mv pattern to update `state.json` after each iteration (WHY: crash-safe state persistence is critical for resume support; spec-10)
- [x] Write `read_state()` for the `--resume` path that parses `state.json` with jq and restores phase, iteration, phase_iteration, stall_count, and other counters into shell variables, resetting consecutive_failures to 0 (WHY: resume must restore exact position in the phase sequence; spec-10)
- [x] Write agent history file creation: after each agent invocation, write a `{phase}-{NNN}.json` file to `.automaton/agents/` recording phase, iteration, model, tokens, cost, duration, task, status, files_changed, and git_commit (WHY: per-agent history enables debugging and post-run analysis; spec-10)

## 4. Token Tracking & Budget

- [x] Write `initialize_budget()` that creates `.automaton/budget.json` from config limits with zeroed usage counters and an empty history array (WHY: budget tracking starts on first iteration; the file must exist before any agent runs; spec-07)
- [x] Write `extract_tokens()` that parses the stream-json result string to find the `"type":"result"` line and extracts input_tokens, output_tokens, cache_creation_input_tokens, and cache_read_input_tokens using jq (WHY: this is the raw data source for all cost tracking; called after every agent invocation; spec-07)
- [x] Write `estimate_cost()` that takes a model name and four token counts, applies the pricing table (opus/sonnet/haiku rates from spec-07), and returns the estimated USD cost (WHY: cost estimation feeds into budget enforcement and display; spec-07)
- [x] Write `update_budget()` that adds iteration tokens to cumulative totals in budget.json, appends a history entry, and recalculates estimated_cost_usd using atomic write (WHY: budget.json is the single source of truth for cost tracking across the entire run; spec-07)
- [x] Write `check_budget()` that enforces four rules: per-iteration warning, per-phase force-transition, total-token hard stop (exit 2), and cost-USD hard stop (exit 2), logging the appropriate message for each (WHY: budget enforcement prevents runaway costs; the four tiers ensure graceful degradation rather than abrupt failure; spec-07)

## 5. Rate Limiting

- [x] Write `handle_rate_limit()` implementing exponential backoff: starting at cooldown_seconds, retrying up to 5 times with backoff_multiplier, capping at max_backoff_seconds, and triggering a 10-minute pause after 5 consecutive failures (WHY: rate limits are the most common transient failure; proper backoff prevents wasted iterations; spec-08)
- [x] Write `check_pacing()` that calculates token velocity over the last 3 iterations from budget.json history and inserts a sleep if velocity exceeds 80% of tokens_per_minute (WHY: proactive pacing avoids rate limits rather than reacting to them; spec-08)

## 6. Error Handling & Recovery

- [x] Write `is_rate_limit()` and `is_network_error()` classification helpers that grep agent output for known error signatures (WHY: error classification determines which recovery path to take; must exist before the main iteration loop; spec-09)
- [x] Write the CLI crash handler: increment consecutive_failures on non-zero exit that is not a rate limit or network error, retry with delay up to max_consecutive_failures, then save state and exit 1 (WHY: transient CLI crashes should not abort the entire run; spec-09)
- [x] Write stall detection: after each build iteration, check `git diff --stat HEAD~1` for emptiness, increment stall_count if empty, reset on changes, force re-plan after stall_threshold consecutive stalls, escalate after 2 re-plans (WHY: stall detection catches agents that claim progress without producing code; spec-09)
- [x] Write plan corruption guard: checkpoint IMPLEMENTATION_PLAN.md before each iteration, verify [x] count did not decrease after, restore from checkpoint if corrupted, escalate after 2 corruptions (WHY: agents occasionally rewrite the plan and destroy completed work; this is the safety net; spec-09)
- [x] Write `escalate()` function that logs the escalation, appends an ESCALATION section to IMPLEMENTATION_PLAN.md, saves state, commits, and exits with code 3 (WHY: when automated recovery fails, the system must stop cleanly and hand off to a human; spec-09)
- [x] Write optional phase timeout check: compare elapsed wallclock time against phase_timeout_seconds from config, force phase transition if exceeded (WHY: safety net for unattended runs where a phase might loop indefinitely; spec-09)
- [x] Write repeated test failure detection (Error #8): add `is_test_failure()` classifier and `check_test_failures()` that tracks consecutive build iterations with test failure indicators, forces transition to review phase after 3 consecutive failures, persists `test_failure_count` in state.json (WHY: spec-09 Error #8 defines this as a distinct error category; without it the build phase could loop indefinitely on the same broken test; spec-09)

## 7. Quality Gates

- [x] Write `gate_check()` wrapper that calls the named gate function, logs PASS/FAIL, and returns the gate's exit code (WHY: uniform gate invocation with logging; called at every phase transition; spec-11)
- [x] Write `gate_spec_completeness()` checking for at least one spec file, non-empty PRD.md, and AGENTS.md without placeholder values (WHY: Gate 1 prevents starting autonomous work on incomplete inputs; spec-11)
- [x] Write `gate_research_completeness()` checking AGENTS.md growth and absence of TBD/TODO in specs (WHY: Gate 2 ensures research actually resolved unknowns before planning begins; spec-11)
- [x] Write `gate_plan_validity()` checking for at least 5 unchecked tasks, plan length over 10 lines, and heuristic spec references (WHY: Gate 3 ensures the plan is substantive enough to drive a build phase; spec-11)
- [x] Write `gate_build_completion()` checking for zero unchecked tasks, git commit existence, and test file presence (WHY: Gate 4 confirms the build phase actually produced complete work; spec-11)
- [x] Write `gate_review_pass()` checking for zero unchecked tasks and no ESCALATION markers (WHY: Gate 5 is the final quality check that determines COMPLETE vs return-to-build; spec-11)

## 8. Prompt Files

- [x] Write `PROMPT_converse.md` for Phase 0: instruct Claude to interview the user, challenge vague requirements, write numbered spec files with Purpose/Requirements/Acceptance Criteria/Dependencies sections, write PRD.md, update AGENTS.md with project name and tech fields, and signal handoff when specs are complete (WHY: the conversation phase prompt defines the entire requirements-gathering UX; spec-02)
- [x] Write `PROMPT_research.md` for Phase 1: instruct Claude to read all specs and PRD.md, identify TBD/TODO/unknown markers, web search to resolve them, enrich specs with concrete technology decisions and rationale, update AGENTS.md with language/framework/commands, and output COMPLETE when done (WHY: the research prompt drives autonomous technology decision-making; spec-03)
- [x] Write `PROMPT_review.md` for Phase 4: instruct Claude to read all specs, run the full validation suite (test/lint/typecheck/build from AGENTS.md), perform spec coverage analysis, check code quality, and either output COMPLETE or create new [ ] tasks in IMPLEMENTATION_PLAN.md (WHY: the review prompt is the independent verification that closes the loop; spec-06)

## 9. Orchestrator Main Script (automaton.sh)

- [x] Write CLI argument parsing for `--resume`, `--skip-research`, `--skip-review`, `--config FILE`, and `--dry-run`, storing flags in variables (WHY: argument parsing is the entry point; it determines which code paths execute; spec-01)
- [x] Write system dependency checks for claude, jq, and git with clear install instructions on failure (WHY: automaton.sh depends on all three; failing fast with a helpful message prevents confusing errors later; spec-13)
- [x] Write signal handlers for SIGINT (save state, log interruption, exit 130), SIGTERM (same as SIGINT), and SIGHUP (ignored for background execution) (WHY: graceful shutdown preserves state for resume; spec-01)
- [x] Write the startup banner displaying version, current phase, budget limits, config file path, and git branch (WHY: the banner orients the user at launch; spec-01)
- [x] Write the `run_agent()` function that invokes `claude -p` with the appropriate prompt file, model, --dangerously-skip-permissions, --output-format=stream-json, and --verbose flags, captures the result, and returns the exit code (WHY: centralizes agent invocation so token extraction, error handling, and logging happen consistently; spec-01)
- [x] Write the phase sequence controller: a loop that progresses through research, plan, build, review with gate checks at each transition, handles --skip-research and --skip-review, transitions back to build on review failure, and declares COMPLETE when Gate 5 passes (WHY: this is the core orchestration logic that ties all modules together; spec-01)
- [x] Write the per-iteration post-processing pipeline: extract tokens, update budget, check budget limits, check pacing, detect stalls (build phase only), check plan integrity (build phase only), write state, write agent history, log iteration summary, emit one-line stdout status, and push to git if configured (WHY: this pipeline runs after every agent invocation and integrates all subsystems; spec-01, spec-05, spec-07, spec-08, spec-09, spec-10)
- [x] Wire the `--resume` path: read state, restore counters, skip to the saved phase, log RESUMED, and enter the phase sequence loop at the correct point (WHY: resume support is essential for long-running autonomous sessions that may be interrupted; spec-10)
- [x] Implement `--dry-run` mode: load config, run Gate 1, display the startup banner with all resolved settings, show which phases would run, and exit 0 without invoking any agents (WHY: dry-run lets users verify configuration before committing to a potentially expensive autonomous run; spec-01)

## 10. Templates Directory Finalization

- [x] Copy all scaffoldable files into `templates/`: automaton.sh, automaton.config.json, PROMPT_converse.md, PROMPT_research.md, PROMPT_plan.md, PROMPT_build.md, PROMPT_review.md, AGENTS.md, IMPLEMENTATION_PLAN.md, CLAUDE.md, PRD.md (WHY: bin/cli.js copies from templates/; every file the user gets must have a template source; spec-13)
- [x] Update `templates/AGENTS.md` to replace "thesis-map" with a generic placeholder like "your-project" and set language/framework to "(to be filled by conversation phase)" (WHY: the template should not reference a specific project; it is a blank starting point for any new user; spec-02)
- [x] Fix 5 stale variable names in `--dry-run` display block: BUDGET_ITER_WARNING->BUDGET_PER_ITERATION, RATE_TOKENS_PER_MIN->RATE_TOKENS_PER_MINUTE, RATE_COOLDOWN_SEC->RATE_COOLDOWN_SECONDS, RATE_BACKOFF_MULT->RATE_BACKOFF_MULTIPLIER, RATE_MAX_BACKOFF_SEC->RATE_MAX_BACKOFF_SECONDS (WHY: dry-run was displaying blank values for budget and rate-limit settings; fixed in both automaton.sh and templates/automaton.sh)

---

## 11. Parallel Configuration (spec-14)

- [x] Add `parallel` section to `automaton.config.json` template with keys: `enabled` (false), `max_builders` (3), `tmux_session_name` ("automaton"), `stagger_seconds` (15), `wave_timeout_seconds` (600), `dashboard` (true) (WHY: every v2 module reads parallel config; the schema must exist in the template before load_config can reference it; spec-14)
  <!-- files: templates/automaton.config.json -->
- [x] Extend `load_config()` to read all `parallel.*` keys into shell variables `PARALLEL_ENABLED`, `MAX_BUILDERS`, `TMUX_SESSION_NAME`, `PARALLEL_STAGGER_SECONDS`, `WAVE_TIMEOUT_SECONDS`, `PARALLEL_DASHBOARD`, with defaults matching spec-14 (WHY: all conductor and builder code depends on these variables; they must be available before any parallel function is called; spec-14, spec-12)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Extend `load_config()` hardcoded-defaults branch (no config file path) with the same `PARALLEL_*` defaults so the system works even without a config file (WHY: load_config has two branches -- file-present and defaults-only -- both must set parallel vars; spec-12)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 12. Parallel Dependency Checks (spec-14)

- [x] Add tmux availability check in the dependency-check section: when `PARALLEL_ENABLED` is `true`, verify `tmux` is on PATH; if missing, print install instructions and exit 1 (WHY: tmux is required for multi-window mode; failing at startup is better than failing mid-build; spec-14)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Add git worktree version check: when `PARALLEL_ENABLED` is `true`, verify `git --version` is 2.5+ (supports `git worktree`); if too old, print upgrade message and exit 1 (WHY: git worktrees are the isolation mechanism for parallel builders; older git versions lack the feature; spec-14)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 13. Parallel State Infrastructure (spec-14, spec-10)

- [x] Extend `initialize()` to create `.automaton/wave/` and `.automaton/wave/results/` directories when `PARALLEL_ENABLED` is `true` (WHY: wave execution writes assignments and results to these directories; they must exist before the first wave; spec-14, spec-10)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Extend `initialize()` to create `.automaton/wave-history/` directory when `PARALLEL_ENABLED` is `true` (WHY: cleanup_wave archives wave data here for post-run debugging; spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Create `.automaton/dashboard.txt` with a placeholder message during `initialize()` when `PARALLEL_ENABLED` is `true` (WHY: the dashboard window runs `watch cat .automaton/dashboard.txt`; the file must exist before the watch command starts; spec-14, spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Create `.automaton/rate.json` with zeroed initial state (window_start, window_tokens=0, window_requests=0, builders_active=0, last_rate_limit=null, backoff_until=null, history=[]) during `initialize()` when `PARALLEL_ENABLED` is `true` (WHY: the conductor reads rate.json for pacing decisions; it must exist before the first wave; spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 14. Extended State for Waves (spec-15, spec-10)

- [x] Extend `write_state()` to include `wave_number` and `wave_history` fields in state.json when `PARALLEL_ENABLED` is `true` (WHY: wave state must persist across interruptions for resume; the conductor reads wave_number to determine which wave to run next; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Extend `read_state()` to restore `wave_number`, `wave_history`, and `consecutive_wave_failures` from state.json when resuming a parallel run (WHY: resume must restore wave position so the conductor continues from the correct wave; spec-15, spec-10)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 15. Task Partitioning (spec-18)

- [x] Write the planning prompt extension block: when `PARALLEL_ENABLED` is `true`, append file-ownership annotation instructions to a temp copy of `PROMPT_plan.md` before running the planning agent, instructing the planner to add `<!-- files: ... -->` comments after each task (WHY: file annotations are the data source for conflict detection; without them all tasks run sequentially; spec-18)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `build_conflict_graph()` that parses `IMPLEMENTATION_PLAN.md` using awk to extract all incomplete (`[ ]`) tasks with their `<!-- files: ... -->` annotations, then pipes through jq to produce `.automaton/wave/tasks.json` as a JSON array of `{line, task, files[]}` objects (WHY: the conflict graph is the input to task selection; it must be rebuilt before each wave since completed tasks change the set; spec-18)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `tasks_conflict()` that takes two comma-separated file lists and returns 0 (conflict) if they share any file or if either list is empty (unannotated), 1 (no conflict) otherwise (WHY: pairwise conflict check is the core predicate used by select_wave_tasks; spec-18)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `select_wave_tasks()` implementing the greedy plan-order algorithm: iterate incomplete tasks from tasks.json, skip if files overlap with already-selected tasks, stop at max_builders; return selected tasks as JSON; if only unannotated tasks remain, return the first one alone for single-builder execution (WHY: this is the algorithm that determines how many tasks can run in parallel per wave; spec-18)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `log_partition_quality()` that calculates the annotation coverage percentage (annotated incomplete tasks / total incomplete tasks), logs the coverage, and emits a warning if coverage is below 50% (WHY: low annotation coverage means limited parallelism; the warning helps humans understand why builds are slow; spec-18)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 16. Builder Wrapper Script (spec-17)

- [x] Write `generate_builder_wrapper()` that creates `.automaton/wave/builder-wrapper.sh` before each wave, containing the full builder lifecycle: read assignment from assignments.json, generate task-specific prompt header with builder number/wave/task/file-ownership rules, prepend header to PROMPT_build.md in a temp file, run `claude -p`, extract tokens from stream-json, determine status (success/error/rate_limited/partial), capture git commit and files_changed, calculate duration, write result JSON to `.automaton/wave/results/builder-N.json`, clean up temp prompt (WHY: the builder wrapper is the executable that runs in each tmux window; it must be generated fresh each wave because assignments change; spec-17)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `check_ownership()` that compares a builder's `files_changed` from its result file against `files_owned` from assignments.json, logs any violations, returns 1 if violations found (WHY: file ownership is a soft constraint enforced by prompt; post-build checking catches violations before merge; spec-17)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Add ownership violation handling to the merge path: if `check_ownership()` detects violations, check whether violated files were also modified by another builder in the same wave; allow if no conflict, drop violating builder's changes to conflicting files and re-queue if conflict exists (WHY: ownership violations must be handled gracefully to avoid silent merge corruption; spec-17)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 17. Merge Protocol (spec-19)

- [x] Write `create_worktree()` that removes any stale worktree at the path, deletes any stale branch, then runs `git worktree add` to create `.automaton/worktrees/builder-N` on branch `automaton/wave-{W}-builder-{N}` from HEAD (WHY: each builder needs an isolated working copy; stale cleanup prevents errors from interrupted previous runs; spec-19)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `cleanup_worktree()` that runs `git worktree remove --force`, `git branch -D` for the builder branch, and `git worktree prune` (WHY: worktrees and branches must be cleaned up after each wave to avoid disk/ref accumulation; spec-19)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `handle_coordination_conflict()` for IMPLEMENTATION_PLAN.md: on conflict, take ours, then extract `[x]` marked tasks from the builder's branch version and apply those checkbox changes to ours, then `git add` the file (WHY: multiple builders marking different tasks [x] is the most common merge conflict; auto-resolving it is essential for parallelism; spec-19)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `handle_coordination_conflict()` for AGENTS.md: on conflict, take ours, append the builder's new additions, then `git add` the file (WHY: builders may append operational learnings to AGENTS.md; the append-both strategy preserves all content; spec-19)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `handle_source_conflict()` that aborts the merge, marks the builder's task for re-queue in assignments.json, and logs the conflicting files (WHY: real source conflicts mean the task partitioning missed a file overlap; the task must be re-queued for single-builder execution to resolve it; spec-19)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `merge_wave()` implementing the three-tier strategy: iterate builders in order, skip non-success/partial, attempt `git merge --no-ff`, on conflict check each file with `handle_coordination_conflict()`, fall through to `handle_source_conflict()` for real conflicts, log tier and counts (WHY: merge_wave is called after every wave and is the highest-risk operation; the three tiers ensure maximal work preservation; spec-19)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 18. Parallel Budget Management (spec-20)

- [x] Write per-builder TPM/RPM allocation logic: calculate `per_builder_tpm = RATE_TOKENS_PER_MINUTE / active_builder_count` and `per_builder_rpm = RATE_REQUESTS_PER_MINUTE / active_builder_count`, pass these to the builder wrapper as environment variables (WHY: N builders sharing the same rate limit must each consume only 1/N of the allocation to avoid 429 errors; spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `check_wave_budget()` that estimates whether the budget can sustain N builders (N * BUDGET_PER_ITERATION tokens, N * estimated_cost), reduces builder count if budget is tight but can afford at least 2, returns 1 if budget is insufficient for even 1 builder (WHY: launching a wave that will exhaust the budget wastes tokens and leaves partial work; pre-wave checks prevent this; spec-20, spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `handle_wave_rate_limit()` that detects rate-limited builders from result files, sets `backoff_until` in rate.json, sleeps for the cooldown period, then clears the backoff (WHY: rate limits during a wave affect the entire API account; the next wave must wait for the backoff period; spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `handle_midwave_budget_exhaustion()` that lets running builders finish, collects and merges their results, then saves state and exits with code 2 (WHY: already-spent tokens should not be wasted; collecting completed work before stopping preserves maximum value; spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `check_wave_pacing()` that calculates aggregate TPM from the last wave's total token consumption and duration, sleeps if velocity exceeds 80% of RATE_TOKENS_PER_MINUTE (WHY: inter-wave pacing prevents rate limits across consecutive waves; this is the wave-level equivalent of per-iteration check_pacing; spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `aggregate_wave_budget()` that iterates all builder result files for a wave, extracts token counts and cost from each, calls `update_budget()` for each builder, and copies result files to agent history as `build-{NNN}-builder-{M}.json` (WHY: builder tokens must be aggregated into the shared budget.json so total/phase budget enforcement works correctly; spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 19. Observability (spec-21)

- [x] Write `write_dashboard()` that generates `.automaton/dashboard.txt` with box-drawing format showing: phase, wave number, estimated total waves, budget remaining, per-builder status bars (running/done/error with elapsed time and task name), task completion counts, token and cost summary, and the 6 most recent session.log events (WHY: the dashboard is the primary human interface during parallel builds; it must be updated after every significant event; spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `format_builder_status()` helper that reads the current wave's assignments.json and any available result files to produce formatted status lines for each builder (running with elapsed time, DONE with duration, ERROR, etc.) (WHY: builder status bars are the core of the dashboard; they require combining assignment data with result data; spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `estimate_remaining_waves()` that calculates `remaining_tasks / max_builders + 1` (WHY: the wave estimate gives humans a sense of progress and expected completion; the +1 accounts for rounding and re-queued tasks; spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Extend the `log()` function to support the enhanced component tag format for parallel mode: `CONDUCTOR`, `BUILD:WN:BN`, `MERGE:WN` (WHY: structured tags enable filtering by wave, builder, or operation type in session.log; spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write stdout one-line wave status output for non-tmux mode: emit `[WAVE N/~M] builder summaries` to stdout after each builder completion and wave completion (WHY: users not in tmux still need progress visibility; this is the wave-level equivalent of per-iteration stdout output; spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 20. Wave Execution Lifecycle (spec-16)

- [x] Write `write_assignments()` that creates `.automaton/wave/assignments.json` with wave number, created_at timestamp, and an assignments array containing builder number, task text, task_line, files_owned, worktree path, and branch name for each selected task (WHY: assignments.json is the contract between conductor and builders; builders read it to get their task; spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `collect_results()` that reads and validates all builder result files from `.automaton/wave/results/`, checks for required fields (builder, wave, status, tokens, exit_code), and returns aggregated results as JSON (WHY: result collection is the handoff point between builder execution and merge; validation catches corrupt or missing result files; spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `verify_wave()` that runs post-merge checks: execute build command if configured, grep for unresolved conflict markers (`<<<<<<<`) in source files, verify completed task count did not decrease (plan integrity); return false if any check fails (WHY: post-wave verification catches merge corruption before the next wave builds on top of it; spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write `cleanup_wave()` that removes worktrees via `cleanup_worktree()` for each builder, archives assignments.json and results/ to `.automaton/wave-history/wave-{N}-*`, clears the wave directory, and kills tmux builder windows (WHY: cleanup prevents disk accumulation and stale tmux windows; archived data enables post-run debugging; spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [x] Write plan update logic after merge: for each successful builder, find the task by `task_line` in IMPLEMENTATION_PLAN.md and mark it `[x]`, incorporate any new tasks discovered by builders, commit the updated plan with message `"automaton: wave N complete (M/N tasks)"` (WHY: the plan is the single source of truth for progress; it must reflect merged work before the next wave selects tasks; spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 21. Conductor - tmux Session Management (spec-15)

- [ ] Write `start_tmux_session()` that creates a tmux session named `$TMUX_SESSION_NAME` with a "conductor" window (or attaches to an existing session if already inside tmux), then creates a "dashboard" window running `watch -n2 cat .automaton/dashboard.txt` if `PARALLEL_DASHBOARD` is true (WHY: the tmux session is the container for all parallel windows; it must exist before builders can be spawned; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Write `cleanup_tmux_session()` that kills any remaining builder windows and the dashboard window within the tmux session, without killing the session itself (WHY: cleanup on exit prevents orphaned tmux windows; the session is preserved because the conductor may still be running in window 0; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 22. Conductor - Builder Spawning and Monitoring (spec-15)

- [ ] Write `spawn_builders()` that iterates the assignments, creates a worktree via `create_worktree()` for each builder, spawns a tmux window named `builder-N` running the builder-wrapper.sh with builder number, wave number, and project root as arguments, and staggers starts by sleeping `PARALLEL_STAGGER_SECONDS` between spawns (WHY: spawning is the step that launches parallel work; staggered timing distributes API load; spec-15, spec-20)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Write `poll_builders()` that loops every 5 seconds checking for result files in `.automaton/wave/results/`, calls `write_dashboard()` on each poll cycle, checks for wave timeout against `WAVE_TIMEOUT_SECONDS`, and returns when all builders have written result files or timeout is reached (WHY: polling is how the conductor detects builder completion; the 5s interval balances responsiveness with overhead; spec-15, spec-16)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Write `handle_wave_timeout()` that identifies builders without result files, sends SIGTERM to their tmux windows via `tmux send-keys C-c`, waits 10 seconds for graceful shutdown, kills remaining windows, and writes timeout result files for incomplete builders (WHY: timed-out builders must be terminated to prevent infinite waves; writing timeout results ensures the conductor has complete data for all builders; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 23. Conductor - Wave Error Handling (spec-15, spec-09)

- [ ] Write wave-level error handling: on single builder failure, merge successful builders' work and re-queue the failed task; on all-builders-fail, increment `consecutive_wave_failures`, fall back to single-builder for 1 iteration, retry wave if single-builder succeeds; escalate per spec-09 after 3 consecutive wave failures (WHY: wave errors are distinct from v1 iteration errors; the system must degrade gracefully from parallel to single-builder before escalating; spec-15, spec-09)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Write `run_single_builder_iteration()` as the v1 fallback: invoke claude -p with PROMPT_build.md and MODEL_BUILDING, run standard post-iteration checks (tokens, budget, stall, plan integrity), identical to the v1 build loop body (WHY: when parallelism fails, the system must still make forward progress; this is the proven single-builder path; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 24. Conductor - Main Wave Dispatch Loop (spec-15)

- [ ] Write `run_parallel_build()` implementing the 10-step wave dispatch loop: (1) select tasks via `select_wave_tasks`, (2) write assignments via `write_assignments`, (3) budget checkpoint via `check_wave_budget`, (4) generate builder wrapper via `generate_builder_wrapper`, (5) spawn builders via `spawn_builders`, (6) poll via `poll_builders`, (7) collect results via `collect_results`, (8) merge via `merge_wave`, (9) verify via `verify_wave`, (10) update state/dashboard/budget; loop until all tasks complete or limits hit; fall back to `run_single_builder_iteration` when no parallelizable tasks remain (WHY: this is the core conductor loop that replaces the v1 build loop; it ties together all parallel subsystems; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Write `update_wave_state()` to update state.json after each wave: increment iteration by the number of successful builders, update phase_iteration, set last_iteration_at, add wave summary to `wave_history` array with wave number, builder count, success/fail counts, tasks completed, duration, and merge tier breakdown (WHY: wave state enables resume and post-run analysis of parallelism effectiveness; spec-15, spec-21)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 25. Main Loop Integration (spec-14, spec-15)

- [ ] Wire parallel build into the phase sequence controller: when `PARALLEL_ENABLED` is `true` and the current phase is `build`, call `run_parallel_build()` instead of the v1 single-builder loop; when `PARALLEL_ENABLED` is `false`, behavior is identical to v1 (WHY: this is the switch point between v1 and v2; it must be a clean conditional so the two modes are completely independent; spec-14, spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Wire tmux session lifecycle into the main script: call `start_tmux_session()` after dependency checks when `PARALLEL_ENABLED` is `true`, call `cleanup_tmux_session()` in signal handlers and on clean exit (WHY: the tmux session must be created before the build phase and cleaned up on any exit path; spec-15)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Extend `--dry-run` output to display parallel configuration: show `parallel.enabled`, `max_builders`, `tmux_session_name`, `stagger_seconds`, `wave_timeout_seconds`, `dashboard`, and whether tmux/git-worktree dependencies are satisfied (WHY: dry-run must reflect all configuration including v2 settings so users can verify before a parallel run; spec-14, spec-01)
  <!-- files: automaton.sh, templates/automaton.sh -->
- [ ] Update the startup banner to show parallel mode status: display "Mode: parallel (N builders)" or "Mode: single-builder" after loading config (WHY: the banner is the first thing users see; they need to know which mode is active; spec-14)
  <!-- files: automaton.sh, templates/automaton.sh -->

## 26. Templates Sync

- [ ] Copy updated `automaton.config.json` (with `parallel` section) into `templates/automaton.config.json` (WHY: new projects scaffolded via bin/cli.js must get the v2 config schema; spec-13, spec-14)
  <!-- files: templates/automaton.config.json -->
- [ ] Copy updated `automaton.sh` (with all parallel functions) into `templates/automaton.sh` (WHY: new projects scaffolded via bin/cli.js must get the v2 orchestrator; spec-13)
  <!-- files: templates/automaton.sh -->

## Deferred / Future Work

<!-- These are spec requirements that are explicitly deferred or represent minor gaps. Not blocking completion. -->

- `models.primary` fallback (spec-12): phase-specific models are used directly; `models.primary` is loaded but not used as a fallback when phase models are unset
- `MODEL_SUBAGENT_DEFAULT` (spec-12): loaded but never referenced by any orchestrator logic
- `requests_per_minute` RPM enforcement (spec-08): variable loaded but never enforced in v1; in v2 it is divided across builders but the per-builder RPM is passed as an environment variable without active enforcement inside the builder wrapper
- `.automaton/` gitignore runtime check (spec-10): only enforced at scaffold time by bin/cli.js; `initialize()` does not verify .gitignore
- Phase timeout for build has a minor edge case (spec-09): defaults to 0 (disabled), so the timeout code path is not reachable without explicit configuration
- Dependency-aware task selection (spec-18): the v2 algorithm uses file-level conflict detection only; explicit task dependency annotations (`<!-- depends: line N -->`) are noted as a future enhancement
- `parallel.post_wave_test_command` (spec-19): mentioned in post-wave verification but not defined in the config schema; deferred until the config schema is extended
