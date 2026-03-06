# Spec 34: Structured State via Git

## Purpose

All `.automaton/` files are currently gitignored — if the directory is lost, all orchestration history is gone. Claude Code best practices recommend using git for state tracking across sessions. Additionally, AGENTS.md learnings are unstructured free text with a 60-line limit, making them hard to query or categorize. This spec splits `.automaton/` into ephemeral (gitignored) and persistent (git-tracked) state, and replaces unstructured learnings with a structured schema.

## Requirements

### 1. Ephemeral vs Persistent State Split

Split `.automaton/` into two categories based on whether the data must survive directory loss:

**Ephemeral State (gitignored)** — runtime-only data that is recreated on each run:

| File/Directory | Purpose | Why Ephemeral |
|----------------|---------|---------------|
| `state.json` | Current phase, iteration, status | Recreated from git log + persistent state on resume |
| `rate.json` | Rate limit tracking | Reset each session |
| `wave/` | Current wave assignments and results | Cleared between waves |
| `worktrees/` | Builder git worktrees | Destroyed after merge |
| `dashboard.txt` | Live dashboard display | Regenerated continuously |
| `session.log` | Current session log | New log per session |
| `self_checksums.json` | Pre-iteration checksums | Computed fresh each iteration |
| `progress.txt` | Cross-window progress (spec-33) | Regenerated each iteration |

**Persistent State (git-tracked)** — data that accumulates across runs and provides project history:

| File/Directory | Purpose | Why Persistent |
|----------------|---------|---------------|
| `budget-history.json` | Token/cost history across all runs | Budget trends, cost analysis |
| `learnings.json` | Structured operational learnings | Cross-session knowledge |
| `run-summaries/` | Per-run summary files | Audit trail, resume context |
| `test_results.json` | Accumulated test results (spec-31) | Test history, regression tracking |
| `self_modifications.json` | Self-build audit trail (spec-22) | Safety audit |

### 2. Gitignore Changes

Update `.gitignore` to track persistent state:

```gitignore
# Automaton ephemeral state (runtime only)
.automaton/state.json
.automaton/rate.json
.automaton/wave/
.automaton/worktrees/
.automaton/dashboard.txt
.automaton/session.log
.automaton/self_checksums.json
.automaton/progress.txt
.automaton/context_summary.md
.automaton/iteration_memory.md

# Automaton persistent state (git-tracked — DO NOT gitignore)
# .automaton/budget-history.json
# .automaton/learnings.json
# .automaton/run-summaries/
# .automaton/test_results.json
# .automaton/self_modifications.json
```

The persistent files are explicitly NOT in `.gitignore`. They are committed by the orchestrator at phase transitions and run completion.

### 3. Structured Learnings Schema

Replace the unstructured AGENTS.md learnings section with `.automaton/learnings.json`:

```json
{
  "version": 1,
  "entries": [
    {
      "id": "learn-001",
      "category": "convention",
      "summary": "Use kebab-case for all spec filenames",
      "detail": "Discovered during research phase — all 26 existing specs use spec-NN-name.md format",
      "confidence": "high",
      "source_phase": "research",
      "source_iteration": 2,
      "created_at": "2026-03-01T10:00:00Z",
      "updated_at": "2026-03-01T10:00:00Z",
      "tags": ["naming", "specs"],
      "active": true
    }
  ]
}
```

Schema fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique identifier (learn-NNN) |
| `category` | enum | yes | One of: `convention`, `architecture`, `debugging`, `tooling`, `performance`, `safety` |
| `summary` | string | yes | One-line summary (max 120 chars) |
| `detail` | string | no | Extended explanation |
| `confidence` | enum | yes | `high`, `medium`, `low` |
| `source_phase` | string | yes | Phase that discovered this learning |
| `source_iteration` | number | yes | Iteration number |
| `created_at` | string | yes | ISO 8601 timestamp |
| `updated_at` | string | yes | ISO 8601 timestamp |
| `tags` | array | no | Categorization tags |
| `active` | boolean | yes | False = superseded or retracted |

### 4. AGENTS.md as Generated View

`AGENTS.md` becomes a generated file rather than a manually-appended one. The orchestrator regenerates it at each phase transition from:

- Project metadata (name, current phase, run count)
- Active learnings from `learnings.json` (filtered by `active: true`, sorted by confidence)
- Recent run summary from `run-summaries/`

Template:
```markdown
# AGENTS.md — Automaton Operational Guide

## Project: [name]
## Current Phase: [phase]
## Total Runs: [count]

## Learnings
[Generated from learnings.json — high confidence first, max 40 lines]

## Recent Activity
[Generated from latest run-summary — last 3 runs, max 20 lines]
```

The 60-line AGENTS.md limit is maintained by truncating the generated output. Full data lives in the structured JSON files.

### 5. Run Summary Files

After each orchestrator run (complete or interrupted), write a summary to `.automaton/run-summaries/`:

```
.automaton/run-summaries/
  run-2026-03-01T10-00-00Z.json
  run-2026-03-01T14-30-00Z.json
```

Summary format:
```json
{
  "run_id": "run-2026-03-01T10-00-00Z",
  "started_at": "2026-03-01T10:00:00Z",
  "completed_at": "2026-03-01T11:45:00Z",
  "exit_code": 0,
  "phases_completed": ["research", "plan", "build", "review"],
  "iterations_total": 14,
  "tasks_completed": 8,
  "tasks_remaining": 2,
  "tokens_used": {
    "input": 1200000,
    "output": 340000,
    "cache_read": 890000,
    "cache_create": 120000
  },
  "estimated_cost_usd": 24.50,
  "learnings_added": 3,
  "new_learnings": ["learn-004", "learn-005", "learn-006"],
  "git_commits": ["abc1234", "def5678", "ghi9012"]
}
```

### 6. Budget History File

Consolidate budget history into `.automaton/budget-history.json` (persistent, git-tracked) separate from the ephemeral `.automaton/budget.json`:

```json
{
  "runs": [
    {
      "run_id": "run-2026-03-01T10-00-00Z",
      "mode": "allowance",
      "tokens_used": 1540000,
      "estimated_cost_usd": 24.50,
      "cache_hit_ratio": 0.68,
      "phases": {
        "research": { "tokens": 120000, "iterations": 2 },
        "plan": { "tokens": 180000, "iterations": 1 },
        "build": { "tokens": 1100000, "iterations": 9 },
        "review": { "tokens": 140000, "iterations": 2 }
      }
    }
  ],
  "weekly_totals": [
    {
      "week_start": "2026-02-24",
      "week_end": "2026-03-02",
      "tokens_used": 4200000,
      "runs": 3
    }
  ]
}
```

### 7. Resume Recovery from Persistent State

On `--resume`, if ephemeral state (`state.json`) is missing but persistent state exists, the orchestrator can reconstruct runtime state:

1. Read latest `run-summaries/*.json` to determine last phase and iteration
2. Read `IMPLEMENTATION_PLAN.md` task checkboxes to determine build progress
3. Read `budget-history.json` to reconstruct budget usage
4. Read `git log` to determine latest commits and changes
5. Reconstruct `state.json` from the above
6. Log: `[ORCHESTRATOR] Ephemeral state missing. Reconstructed from persistent state and git history.`

This recovery is best-effort — some runtime data (rate limit state, wave progress) cannot be recovered. The orchestrator starts a fresh iteration from the reconstructed state.

### 8. Persistent State Commit Protocol

The orchestrator commits persistent state files at:
- Phase transitions (after quality gates pass)
- Run completion (success or interrupted)
- Every 5 build iterations (periodic checkpoint)

Commit message format:
```
automaton: state checkpoint — [phase] iteration [N]
```

These commits are on the working branch (not a separate state branch) so they're visible in normal git history.

## Acceptance Criteria

- [ ] `.automaton/` split into ephemeral (gitignored) and persistent (git-tracked) categories
- [ ] `.gitignore` updated to track persistent state files
- [ ] `learnings.json` with structured schema replaces unstructured AGENTS.md learnings
- [ ] AGENTS.md generated from `learnings.json` + project metadata at phase transitions
- [ ] Run summary written to `.automaton/run-summaries/` after each run
- [ ] `budget-history.json` accumulates cross-run budget data
- [ ] `--resume` recovers from ephemeral state loss using persistent state + git log
- [ ] Persistent state committed at phase transitions and run completion

## Dependencies

- Extends: spec-10 (state management — persistent split)
- Extends: spec-01 (AGENTS.md generation)
- Extends: spec-26 (run summaries replace improvement loop journal)
- Extends: spec-13 (gitignore changes)
- Extends: spec-22 (self_modifications.json becomes persistent)
- Depends on: spec-07 (budget data for history file)

## Files to Modify

- `.gitignore` — restructure automaton entries for ephemeral/persistent split
- `automaton.sh` — `initialize_state()` for persistent directory setup, `post_phase()` for state commits, `resume()` for recovery logic, `post_iteration()` for learnings management
- `AGENTS.md` — becomes generated output (template in automaton.sh)
- `.automaton/learnings.json` — new file: structured learnings
- `.automaton/budget-history.json` — new file: cross-run budget history
- `.automaton/run-summaries/` — new directory: per-run summary files
