# Spec 22: Self-Build Safety Protocol

## Purpose

When automaton modifies its own `automaton.sh`, a build agent can break the running orchestrator. This spec defines checkpoint/restore, syntax validation, smoke testing, and audit logging that prevent self-modification from corrupting a live run. This is the foundation for all other self-build specs.

## Requirements

### 1. Pre-iteration Checkpointing

Before each build iteration, compute sha256 checksums of `automaton.sh`, all `PROMPT_*.md`, `automaton.config.json`, and `bin/cli.js`. Store in `.automaton/self_checksums.json`. After each iteration, compare. If any changed, log the change but do NOT reload mid-run — changes take effect on next `--resume` or fresh run.

### 2. Syntax Validation Gate

After any iteration that modifies `automaton.sh`, run `bash -n automaton.sh`. If it fails, restore from the pre-iteration checkpoint, add `[ ] Fix: automaton.sh syntax error introduced in iteration N` to IMPLEMENTATION_PLAN.md (or `.automaton/backlog.md` in self-build mode).

### 3. Smoke Test

After any iteration that modifies `automaton.sh` and passes syntax check, run `./automaton.sh --dry-run` in a subshell. If it fails, restore from checkpoint.

### 4. Self-Modification Audit Log

Maintain `.automaton/self_modifications.json` as append-only: iteration, phase, files changed, checksums before/after, syntax-check result, smoke-test result.

### 5. Build Prompt Safety Rules

Add to `PROMPT_build.md`: agents MUST NOT modify orchestrator files as a side effect of another task. Only modify them when the task explicitly targets orchestrator code.

### 6. `self_build.enabled` Config Flag

Default false. When true, activates checkpointing and validation. All self-build specs check this flag.

## Acceptance Criteria

- [ ] Modifying `automaton.sh` during a build does not crash the running orchestrator
- [ ] Syntax errors in self-modified `automaton.sh` are caught and rolled back automatically
- [ ] `--dry-run` smoke test runs after every self-modification; rollback on failure
- [ ] `.automaton/self_checksums.json` updated every iteration during self-build
- [ ] `.automaton/self_modifications.json` contains complete audit trail
- [ ] Syntax error in `automaton.sh` → new plan task to fix it, not a crash

## Dependencies

- Depends on: none
- Depended on by: spec-24, spec-25, spec-26

## Files to Modify

- `automaton.sh` — add checkpoint/restore around `post_iteration()` and before `run_agent()`
- `PROMPT_build.md` — add self-modification safety rules
- `automaton.config.json` — add `self_build.enabled` flag
