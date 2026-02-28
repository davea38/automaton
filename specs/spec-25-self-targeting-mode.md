# Spec 25: Self-Targeting Mode

## Purpose

Automaton assumes it's building a different project. The pipeline (converse -> research -> plan -> build -> review) doesn't work for self-improvement. This spec defines `--self` mode: skips converse (specs exist), replaces research with Claude-best-practices focus, restructures plan to work from an improvement backlog, and adds self-build guardrails.

## Requirements

### 1. `--self` CLI Flag

Activates self-build mode:
- Sets `self_build.enabled = true`
- Skips Gate 1 (specs already exist)
- Defaults to allowance budget mode
- Reads improvement backlog from `.automaton/backlog.md` instead of IMPLEMENTATION_PLAN.md

### 2. Improvement Backlog (`.automaton/backlog.md`)

Markdown file with categorized improvement tasks (Prompt Improvements, Architecture Improvements, Configuration Improvements, Performance Improvements). Populated by: review phase, orchestrator auto-generation from performance data, manual user additions.

### 3. Self-Research Phase

`--self` mode uses `PROMPT_self_research.md` (new file) instead of `PROMPT_research.md`. Focus: Claude CLI best practices, analyzing own performance data from `.automaton/budget.json`, comparing prompt strategies for token efficiency.

### 4. Self-Plan Phase

Reads backlog (not specs). Prioritizes by estimated token savings. Constrains tasks to modify no more than one function in `automaton.sh` per iteration.

### 5. Self-Review Phase

Additionally runs `bash -n automaton.sh`, `./automaton.sh --dry-run`, and compares token usage current vs previous run. Adds new backlog items for regressions.

### 6. Scope Controls

Config:
```json
"self_build": {
  "max_files_per_iteration": 3,
  "max_lines_changed_per_iteration": 200,
  "protected_functions": ["run_orchestration", "_handle_shutdown"],
  "require_smoke_test": true
}
```

## Acceptance Criteria

- [ ] `./automaton.sh --self` runs full self-build pipeline
- [ ] `.automaton/backlog.md` used for task selection in self-build mode
- [ ] `PROMPT_self_research.md` used instead of `PROMPT_research.md`
- [ ] Plan phase prioritizes tasks by estimated token savings
- [ ] Review phase runs syntax check and dry-run smoke test
- [ ] Scope limits enforced with warnings
- [ ] Complete `--self` run produces measurable improvements or new backlog items

## Dependencies

- Depends on: spec-22, spec-23, spec-24
- Depended on by: spec-26

## Files to Modify

- `automaton.sh` — CLI parsing, `run_orchestration()`, `get_phase_prompt()`
- New file: `PROMPT_self_research.md`
- `automaton.config.json` — add `self_build` section
- `PROMPT_build.md` — add self-build rules section
- `PROMPT_review.md` — add self-build review criteria
