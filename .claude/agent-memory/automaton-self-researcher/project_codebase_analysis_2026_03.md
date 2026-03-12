---
name: Codebase analysis March 2026
description: Key metrics, run performance data, and findings from automaton codebase analysis as of 2026-03-12
type: project
---

## Codebase Metrics (2026-03-12)

- automaton.sh: ~1,486 lines
- lib/*.sh total: 18,478 lines (after parallel.sh split)
- Prompt files: 1,653 total lines across 13 PROMPT_*.md files
- Test files: 158 (24,129 lines)
- Specs: 64 total (1-60 implemented, 61-64 pending)

## Run Performance Data

### Run 3 (2026-03-11, most complete run)
- 25 iterations, 66 minutes, $12.85 cost, 58 tasks completed
- Token mix: 95.5% cache reads, 3.6% cache creates, 0.8% output
- Cost per task: $0.22
- Output tokens dominate actual cost: 158K output at $15/M = $2.38
- Cache reads nearly free: 18.9M at $0.30/M = $5.68

### Performance Patterns
- Research phase always 0 file changes for self-build (wasteful)
- Research ran 5 iterations despite config max of 3
- Build iteration times: 64s to 505s (high variance)
- files_changed always 0 (tracking bug)
- Token fields missing from work-log iteration_end events

## Key Gaps (updated 2026-03-12)

1. **Work-log token tracking RESOLVED** (as of 2026-03-12T14:00Z): `automaton.sh:1032` now emits all 6 token fields (`exit_code`, `files_changed`, `input_tokens`, `output_tokens`, `cache_create`, `cache_read`). Current work-log entries confirm. Gap is closed.
2. **Complexity assessment root cause identified**: `lib/qa.sh:1290` and `templates/lib/qa.sh:1290` use `{"tier": "SIMPLE|MODERATE|COMPLEX", "rationale": ...}` as the JSON template. Haiku returns this literal string as the tier value; bash `case "SIMPLE|MODERATE|COMPLEX" in SIMPLE|MODERATE|COMPLEX)` does NOT match (pipe = OR in case patterns). Fix: replace placeholder with concrete example, e.g., `{"tier": "MODERATE", "rationale": "one-line reason"}`.
3. **files_changed hardcoded to 0** in `automaton.sh:1032` emit_event — actual git change count not computed.
4. **Research phase waste**: 5 iterations, 0 changes, ~7 min wasted per run
5. **Agent failure diagnostics missing**: Exit code only, no stderr capture
6. **When all plan tasks done**, complexity assessment falls back to "General project task" task_desc (`automaton.sh:1481`)

## Config vs Template: Identical (no drift). Specs 61-64 config sections already present.

**Why:** This data enables future self-research iterations to compare against baseline metrics and track whether fixes actually improved performance.

**How to apply:** Reference these numbers when evaluating whether a proposed optimization is worth implementing. Focus on items that reduce the 95.5% cache read volume or the output token cost.
