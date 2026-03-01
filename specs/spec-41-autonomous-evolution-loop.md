# Spec 41: Autonomous Evolution Loop

## Purpose

Specs 25-26 enable manual self-improvement: the human runs `--self`, picks a backlog item, and automaton implements it. This spec transforms automaton from a tool the human drives into an organism that proposes its own improvements, evaluates them collectively, implements approved changes, and observes results — all within a single `--evolve` invocation. The evolution loop is a 5-phase cycle (REFLECT → IDEATE → EVALUATE → IMPLEMENT → OBSERVE) that runs repeatedly until convergence, budget exhaustion, or human interruption. Each cycle produces at most one implemented change, ensuring incremental growth (Article VI of the constitution, spec-40).

## Requirements

### 1. `--evolve` CLI Flag

New CLI mode that activates the autonomous evolution loop:

```bash
./automaton.sh --evolve              # Run evolution until convergence or budget exhaustion
./automaton.sh --evolve --cycles 5   # Run exactly 5 evolution cycles
./automaton.sh --evolve --dry-run    # Show what REFLECT would find without acting
```

`--evolve` implies `--self` (self-build mode is required). It additionally:
- Sets `ARG_EVOLVE=true`
- Enables garden (spec-38), quorum (spec-39), constitution (spec-40), signals (spec-42), metrics (spec-43)
- Creates `.automaton/evolution/` for per-cycle ephemeral artifacts
- Loads or creates the constitution (spec-40)
- Takes a pre-cycle metrics snapshot (spec-43)

### 2. Evolution Cycle Architecture

Each cycle follows 5 phases:

```
┌─────────┐    ┌─────────┐    ┌──────────┐    ┌───────────┐    ┌─────────┐
│ REFLECT  │───▶│ IDEATE  │───▶│ EVALUATE │───▶│ IMPLEMENT │───▶│ OBSERVE │
│          │    │         │    │          │    │           │    │         │
│ Analyze  │    │ Plant & │    │ Quorum   │    │ Build on  │    │ Compare │
│ metrics, │    │ water   │    │ votes on │    │ dedicated │    │ before/ │
│ signals, │    │ ideas,  │    │ bloom    │    │ branch    │    │ after   │
│ journal  │    │ promote │    │ cands    │    │ (spec-22) │    │ metrics │
└─────────┘    └─────────┘    └──────────┘    └───────────┘    └─────────┘
     │                                                               │
     └───────────────────── next cycle ◄─────────────────────────────┘
```

### 3. Phase 1: REFLECT

The REFLECT phase analyzes automaton's current state to identify what needs attention. It runs as a dedicated Claude agent using `PROMPT_evolve_reflect.md`:

**Inputs:**
- Latest metrics snapshot (spec-43)
- Metrics trend analysis (last N snapshots)
- Active signals (spec-42), especially strong and unlinked signals
- Recent run journal entries (spec-26)
- Garden state (_index.json from spec-38)
- Constitution summary (spec-40)

**Actions:**
1. Analyze metric trends — identify degrading or stagnant metrics
2. Review active signals — identify patterns requiring attention
3. Emit new signals for observed patterns (spec-42)
4. Auto-seed garden ideas from metric threshold breaches (spec-38)
5. Auto-seed garden ideas from strong unlinked signals (spec-38)
6. Prune expired seeds and sprouts (spec-38)
7. Decay all signals (spec-42)

**Output:** A reflection summary written to `.automaton/evolution/cycle-{N}/reflect.json`:

```json
{
  "cycle_id": 5,
  "timestamp": "2026-03-02T14:00:00Z",
  "metric_alerts": [
    {"metric": "tokens_per_task", "direction": "degrading", "consecutive_cycles": 3}
  ],
  "signals_emitted": 2,
  "ideas_seeded": 1,
  "ideas_pruned": 0,
  "signals_decayed": 5,
  "recommendation": "Focus on token efficiency — degrading trend detected"
}
```

**Agent definition:** `.claude/agents/evolve-reflect.md` — a Sonnet agent with read-only access to `.automaton/` files. It emits signals and seeds ideas by producing structured JSON output that the orchestrator processes (the agent does not write files directly).

### 4. Phase 2: IDEATE

The IDEATE phase enriches existing ideas with new evidence and promotes mature ideas toward bloom. It runs as a dedicated Claude agent using `PROMPT_evolve_ideate.md`:

**Inputs:**
- Reflection summary from Phase 1
- All non-wilted garden ideas
- Active signals
- Recent successful approaches (from journal)

**Actions:**
1. Water existing sprouts with new evidence from metrics/signals
2. Evaluate sprout → bloom transitions (check thresholds from spec-38)
3. Suggest new ideas based on patterns in the reflection
4. Link ideas to related signals
5. Recompute priority scores

**Output:** An ideation summary written to `.automaton/evolution/cycle-{N}/ideate.json`:

```json
{
  "cycle_id": 5,
  "ideas_watered": 3,
  "ideas_promoted_to_bloom": 1,
  "ideas_created": 1,
  "bloom_candidates": [
    {"id": "idea-003", "title": "Reduce prompt overhead", "priority": 72}
  ]
}
```

**Agent definition:** `.claude/agents/evolve-ideate.md` — a Sonnet agent with read-only access. Produces structured JSON output for the orchestrator to process.

### 5. Phase 3: EVALUATE

The EVALUATE phase runs the agent quorum (spec-39) on bloom-stage ideas:

**Inputs:**
- Bloom candidates from IDEATE phase (sorted by priority)
- Full proposal context for each candidate

**Actions:**
1. Select the highest-priority bloom candidate
2. Invoke the 5-voter quorum (spec-39)
3. If approved: advance idea to harvest stage, record conditions
4. If rejected: wilt the idea, record reasoning
5. If no bloom candidates: skip to OBSERVE (no implementation this cycle)

**Output:** Vote record in `.automaton/votes/` (spec-39) and evaluation summary in `.automaton/evolution/cycle-{N}/evaluate.json`:

```json
{
  "cycle_id": 5,
  "bloom_candidates_count": 2,
  "evaluated": "idea-003",
  "vote_id": "vote-005",
  "result": "approved",
  "conditions": ["Must pass syntax check", "Update tests"],
  "tokens_used": 15200
}
```

If multiple bloom candidates exist, only the highest-priority one is evaluated per cycle (Article VI: incremental growth). Remaining candidates carry over to the next cycle.

### 6. Phase 4: IMPLEMENT

The IMPLEMENT phase uses the existing build pipeline (spec-05) to implement the approved idea on a dedicated branch:

**Setup:**
1. Create a dedicated git branch: `automaton/evolve-{cycle_id}-{idea_id}`
2. Generate an implementation plan from the approved idea's description and conditions
3. Write the plan to `IMPLEMENTATION_PLAN.md` on the evolution branch

**Execution:**
4. Run the standard build pipeline (spec-05) with self-build safety (spec-22)
5. Run the standard review pipeline (spec-06)
6. Run the constitutional compliance check (spec-40) on the resulting diff
7. If compliance check fails: abandon branch, wilt idea, emit `quality_concern` signal

**Constraints:**
- Maximum files changed: `self_build.max_files_per_iteration` (spec-22)
- Maximum lines changed: `self_build.max_lines_changed_per_iteration` (spec-22)
- Protected functions: `self_build.protected_functions` (spec-22)
- Syntax validation and smoke test required (spec-22)

**Output:** Implementation summary in `.automaton/evolution/cycle-{N}/implement.json`:

```json
{
  "cycle_id": 5,
  "idea_id": "idea-003",
  "branch": "automaton/evolve-5-idea-003",
  "iterations": 4,
  "files_changed": 2,
  "lines_changed": 85,
  "tests_added": 2,
  "syntax_check": "passed",
  "smoke_test": "passed",
  "constitution_check": "passed",
  "tokens_used": 180000
}
```

### 7. Phase 5: OBSERVE

The OBSERVE phase measures the impact of the implementation and decides whether to keep or revert it. It runs as a dedicated Claude agent using `PROMPT_evolve_observe.md`:

**Inputs:**
- Pre-cycle metrics snapshot (taken before REFLECT)
- Post-implementation metrics snapshot (taken now)
- Implementation summary from Phase 4
- The approved idea and its target metrics

**Actions:**
1. Take a post-cycle metrics snapshot (spec-43)
2. Compare pre and post snapshots on the idea's target metrics
3. Run the full test suite
4. If improvement detected: merge the evolution branch into the working branch, record as harvest
5. If regression detected: abandon the branch, wilt the idea, emit `quality_concern` signal, trigger rollback protocol (spec-45)
6. If neutral (no measurable change): merge but emit `attention_needed` signal for future cycles to monitor
7. Emit `promising_approach` signal for techniques that improved metrics
8. Update the garden index

**Output:** Observation summary in `.automaton/evolution/cycle-{N}/observe.json`:

```json
{
  "cycle_id": 5,
  "idea_id": "idea-003",
  "pre_metrics": { "tokens_per_task": 45000 },
  "post_metrics": { "tokens_per_task": 38000 },
  "delta": { "tokens_per_task": -7000 },
  "test_pass_rate": 0.97,
  "outcome": "harvest",
  "signals_emitted": 1
}
```

**Agent definition:** `.claude/agents/evolve-observe.md` — a Sonnet agent with read-only access. Produces structured JSON output for the orchestrator to process.

### 8. Cycle Control

The evolution loop continues cycling until one of these conditions is met:

| Condition | Action |
|-----------|--------|
| `--cycles N` reached | Stop after N cycles (default: unlimited) |
| Budget exhausted | Stop with exit code 2 (resumable) |
| Convergence detected | Stop with message (spec-26) |
| No bloom candidates for 3 consecutive cycles | Stop with "garden needs seeding" message |
| Circuit breaker tripped (spec-45) | Stop with safety halt message |
| Human interruption (Ctrl+C) | Save state, stop with exit code 130 (resumable) |

Convergence is detected when `consecutive_no_improvement >= evolution.convergence_threshold` (default: 5 cycles with no metric improvement).

### 9. Per-Cycle Budget

Each evolution cycle has a budget allocation:

```
cycle_budget = min(evolution.max_cost_per_cycle_usd, remaining_weekly_allowance / estimated_remaining_cycles)
```

Budget breakdown per phase:

| Phase | Typical % | Agent Model |
|-------|-----------|-------------|
| REFLECT | 10% | Sonnet |
| IDEATE | 10% | Sonnet |
| EVALUATE | 15% | Sonnet (5 voters × ~500 tokens each) |
| IMPLEMENT | 55% | Sonnet (build) + Opus (review) |
| OBSERVE | 10% | Sonnet |

If a phase exceeds its budget allocation, subsequent phases receive proportionally less. If the cycle budget is exhausted before OBSERVE, the implementation is abandoned and the idea returns to bloom stage.

### 10. Evolution State

Per-cycle ephemeral state stored in `.automaton/evolution/`:

```
.automaton/evolution/
  cycle-001/
    reflect.json
    ideate.json
    evaluate.json
    implement.json
    observe.json
  cycle-002/
    ...
```

This directory is ephemeral (gitignored). The persistent record is the metrics snapshots (spec-43), vote records (spec-39), and garden state (spec-38).

### 11. Resume Support

`./automaton.sh --evolve --resume` resumes an interrupted evolution run:

1. Read the last cycle directory in `.automaton/evolution/`
2. Determine which phase was interrupted (find the last written summary file)
3. Resume from the interrupted phase
4. If IMPLEMENT was interrupted, the evolution branch may exist — check git and resume build

### 12. Configuration

New `evolution` section in `automaton.config.json`:

```json
{
  "evolution": {
    "enabled": false,
    "max_cycles": 0,
    "max_cost_per_cycle_usd": 5.00,
    "convergence_threshold": 5,
    "idle_garden_threshold": 3,
    "branch_prefix": "automaton/evolve-",
    "auto_merge": true,
    "reflect_model": "sonnet",
    "ideate_model": "sonnet",
    "observe_model": "sonnet"
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | false | Enable evolution loop (set true by --evolve) |
| `max_cycles` | number | 0 | Maximum cycles per run (0 = unlimited) |
| `max_cost_per_cycle_usd` | number | 5.00 | Budget ceiling per evolution cycle |
| `convergence_threshold` | number | 5 | Cycles without improvement before convergence halt |
| `idle_garden_threshold` | number | 3 | Consecutive cycles with no bloom candidates before halt |
| `branch_prefix` | string | "automaton/evolve-" | Git branch prefix for evolution branches |
| `auto_merge` | boolean | true | Auto-merge successful implementations |
| `reflect_model` | string | "sonnet" | Model for REFLECT agent |
| `ideate_model` | string | "sonnet" | Model for IDEATE agent |
| `observe_model` | string | "sonnet" | Model for OBSERVE agent |

### 13. Evolution Agent Definitions

Three evolution agents in `.claude/agents/`:

| Agent File | Phase | Model | Access |
|------------|-------|-------|--------|
| `evolve-reflect.md` | REFLECT | Sonnet | Read-only: `.automaton/`, `specs/` |
| `evolve-ideate.md` | IDEATE | Sonnet | Read-only: `.automaton/`, `specs/` |
| `evolve-observe.md` | OBSERVE | Sonnet | Read-only: `.automaton/`, `specs/`, test results |

All evolution agents produce structured JSON output that the orchestrator parses and acts on. Agents do not write files or execute commands — the orchestrator handles all state mutations.

### 14. Evolution Prompts

Three new prompt files:

| Prompt File | Phase | Key Sections |
|-------------|-------|-------------|
| `PROMPT_evolve_reflect.md` | REFLECT | Metrics analysis rules, signal emission format, auto-seed criteria |
| `PROMPT_evolve_ideate.md` | IDEATE | Evidence evaluation rules, promotion criteria, priority scoring |
| `PROMPT_evolve_observe.md` | OBSERVE | Before/after comparison rules, harvest/wilt criteria, signal emission |

Each follows the existing prompt template structure (spec-29): `<context>`, `<identity>`, `<rules>`, `<instructions>`, `<output_format>`, `<dynamic_context>`.

## Acceptance Criteria

- [ ] `--evolve` CLI flag activates autonomous evolution loop
- [ ] `--evolve --cycles N` limits to N cycles
- [ ] `--evolve --dry-run` shows REFLECT analysis without acting
- [ ] REFLECT phase analyzes metrics, signals, and journal; emits signals and seeds ideas
- [ ] IDEATE phase waters ideas, promotes mature ones to bloom
- [ ] EVALUATE phase runs quorum on highest-priority bloom candidate
- [ ] IMPLEMENT phase builds on dedicated branch with self-build safety
- [ ] OBSERVE phase compares before/after metrics and decides harvest/wilt
- [ ] Convergence detection halts after N cycles without improvement
- [ ] Budget enforcement stops cycles when exhausted
- [ ] Per-cycle artifacts stored in `.automaton/evolution/cycle-{N}/`
- [ ] Resume support restores interrupted evolution from last completed phase
- [ ] All three evolution agents produce valid structured JSON
- [ ] At most one idea implemented per cycle (Article VI compliance)

## Dependencies

- Depends on: spec-22 (self-build safety — branch management, scope limits)
- Depends on: spec-25 (self-targeting mode — `--self` foundation)
- Depends on: spec-26 (improvement loop — journal, performance metrics)
- Depends on: spec-38 (garden — idea lifecycle management)
- Depends on: spec-39 (quorum — EVALUATE phase voting)
- Depends on: spec-40 (constitution — compliance check in IMPLEMENT)
- Depends on: spec-42 (signals — REFLECT emits/decays, OBSERVE emits)
- Depends on: spec-43 (metrics — snapshots, trend analysis, before/after comparison)
- Depends on: spec-45 (safety — circuit breakers, branch management, rollback)
- Depended on by: spec-44 (CLI — `--evolve` and related commands)

## Files to Modify

- `automaton.sh` — add `_evolve_run_cycle()`, `_evolve_reflect()`, `_evolve_ideate()`, `_evolve_evaluate()`, `_evolve_implement()`, `_evolve_observe()`, `_evolve_check_convergence()`, `_evolve_check_budget()`, CLI argument parsing for `--evolve` and `--cycles`
- `automaton.config.json` — add `evolution` configuration section
- `PROMPT_evolve_reflect.md` — new file: REFLECT phase prompt
- `PROMPT_evolve_ideate.md` — new file: IDEATE phase prompt
- `PROMPT_evolve_observe.md` — new file: OBSERVE phase prompt
- `.claude/agents/evolve-reflect.md` — new file: REFLECT agent definition
- `.claude/agents/evolve-ideate.md` — new file: IDEATE agent definition
- `.claude/agents/evolve-observe.md` — new file: OBSERVE agent definition
- `.automaton/evolution/` — new directory: per-cycle artifacts (ephemeral, gitignored)
- `.gitignore` — add `.automaton/evolution/` as ephemeral state
- `PROMPT_build.md` — add evolution safety rules (build on evolution branch)
- `PROMPT_review.md` — add evolution review guidelines (constitutional compliance)
