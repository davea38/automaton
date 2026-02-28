# Spec 26: Improvement Loop and Performance Tracking

## Purpose

Specs 22-25 enable a single self-build run. This spec makes self-improvement continuous by tracking performance across runs, auto-generating backlog items, and providing recommendations on when to run.

## Requirements

### 1. Run Journal

After each run, archive to `.automaton/journal/run-{NNN}/`: budget.json, state.json, session.log, context_summary.md, self_modifications.json, run_metadata.json.

### 2. Performance Metrics

`run_metadata.json` includes:
- Tokens per completed task
- Stall rate (stall_count / total_build_iterations)
- First-pass success rate (tasks completed without review rework / total tasks)
- Average iteration duration
- Prompt overhead ratio (prompt_tokens / total_input_tokens)

### 3. `--stats` Command

`./automaton.sh --stats` displays run history table and trends (tokens/task trend, stall rate trend).

### 4. Auto-Generated Backlog Entries

After each `--self` run, analyze journal:
- Token efficiency regression -> investigate task
- Stall rate > 20% -> improve prompt task
- Prompt overhead > 50% -> reduce prompt size task
- Modified-then-reverted function -> review task
Appended to `.automaton/backlog.md` under `## Auto-generated`.

### 5. `--self --continue` Command

Reads backlog, picks highest-priority items, estimates token cost, shows recommendation ("Safe to run - X% of remaining allowance"), then runs one self-build cycle.

### 6. Convergence Detection

If last 3 runs show zero measurable improvement, log warning: "Self-improvement may have converged. Consider manual review of backlog priorities."

## Acceptance Criteria

- [ ] `.automaton/journal/run-{NNN}/` created with complete data after every run
- [ ] `run_metadata.json` contains all five metrics
- [ ] `./automaton.sh --stats` displays history and trends
- [ ] Auto-generated backlog entries appear after `--self` runs
- [ ] `--self --continue` estimates cost and shows recommendation before running
- [ ] Convergence warning after 3 runs with no improvement
- [ ] Journal data sufficient to reconstruct any historical run

## Dependencies

- Depends on: spec-22, spec-23, spec-24, spec-25
- Depended on by: none (capstone)

## Files to Modify

- `automaton.sh` — journal archival after `run_orchestration()`, `--stats` CLI command, `--continue` flag, convergence logic
- `automaton.config.json` — add `journal.max_runs` retention setting
