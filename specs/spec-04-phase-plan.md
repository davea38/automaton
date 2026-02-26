# Spec 04: Phase 2 - Plan

## Purpose

The planning phase reads enriched specs and the existing codebase, performs gap analysis, and produces a dependency-ordered task list in `IMPLEMENTATION_PLAN.md`. This is the existing RALPH planning phase, unchanged in behavior but invoked by the orchestrator.

## How It Runs

```bash
result=$(cat PROMPT_plan.md | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model opus \
    --verbose)
```

Uses the existing `PROMPT_plan.md` from RALPH templates. The orchestrator runs up to 2 iterations.

## Prompt Behavior (Inherited from RALPH)

The planning prompt (already defined in `PROMPT_plan.md`) instructs Claude to:

1. **Load Context:** Study AGENTS.md, all specs (up to 250 parallel Sonnet subagents), and existing codebase (up to 500 parallel Sonnet subagents).
2. **Gap Analysis:** Compare spec requirements against existing code. Categorize each requirement as: already implemented, partially implemented, or not yet started.
3. **Create Implementation Plan:** Write `IMPLEMENTATION_PLAN.md` with prioritized, dependency-ordered tasks. Each task is a clear single-sentence action item with `[ ]` checkbox. Group by spec/topic. Use Opus subagent with ultrathink for priority ordering.
4. **Capture the Why:** For each task, add a brief note explaining WHY it matters.

### Rules (from RALPH)
- Do NOT implement any code
- Do NOT assume something is missing without checking code first
- Keep tasks small (one clear action per task)
- Note spec contradictions in the plan
- Output `<promise>COMPLETE</promise>` when done

## Enhancements Over Base RALPH

The planning prompt is used as-is from RALPH. The orchestrator adds:
- Token tracking of the planning iteration
- Budget enforcement (phase limit: 1M tokens default)
- Gate 3 validation after completion

## Iteration Limits

| Setting | Default | Config Key |
|---------|---------|-----------|
| Max iterations | 2 | execution.max_iterations.plan |
| Per-iteration token limit | 500K | budget.per_iteration |
| Phase token budget | 1M | budget.per_phase.plan |

## Quality Gate (Gate 3) Checks

After planning completes or hits max iterations:

| Check | Method | On Fail |
|-------|--------|---------|
| At least 5 unchecked tasks | `grep -c '\[ \]' IMPLEMENTATION_PLAN.md` >= 5 | Retry plan |
| Tasks reference spec files | `grep -ci 'spec' IMPLEMENTATION_PLAN.md` > 0 | Warning, continue |
| Plan is non-trivial | `wc -l IMPLEMENTATION_PLAN.md` > 10 | Retry plan |

## Output

`IMPLEMENTATION_PLAN.md` with structure:

```markdown
# Implementation Plan

## [Topic Group 1]

- [ ] Task description (WHY: rationale)
- [ ] Task description (WHY: rationale)

## [Topic Group 2]

- [ ] Task description (WHY: rationale)
...
```
