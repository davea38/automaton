# Spec 47: Pre-Flight Spec Critique

## Priority

P1 — Prevent User Frustration. Ambiguous specs cause the build agent to guess wrong. Review catches the mismatch, the orchestrator loops, and tokens burn on rework that a single upfront critique pass would have prevented. This is the cheapest possible quality intervention: one Claude call before planning begins.

## Competitive Sources

- **Auto-Claude**: 4-agent pipeline (gatherer, researcher, writer, critic) where the critic agent reviews specs before execution begins. Automaton adapts the critic concept but uses a single Claude call instead of a dedicated agent.
- **oh-my-claudecode**: `/deep-interview` command uses Socratic questioning to iteratively refine specs with the user. Automaton borrows the "challenge the spec" posture but runs it non-interactively.
- **wshobson/agents**: Interactive Q&A loop before execution where the agent asks clarifying questions. Automaton takes the "find the gaps" intent but produces a written report instead of blocking on human input.

## Purpose

An optional pre-planning phase that reads all spec files, runs a single Claude critique call, and produces a structured report identifying ambiguities, missing requirements, contradictions, and untestable criteria. The user reviews the report and decides whether to fix specs or proceed. This catches spec quality problems at the cheapest possible moment — before planning and building consume their token budgets.

## Requirements

### 1. Critique Trigger

The critique runs in two modes:

- **Standalone**: `./automaton.sh --critique-specs` runs critique only, produces the report, and exits.
- **Pre-flight**: When `config.critique.auto_preflight` is `true` (default: `false`), the orchestrator runs critique automatically before the Plan phase. If critique finds issues at severity `error`, the orchestrator halts and prompts the user. If only `warning` severity, the orchestrator logs and proceeds.

### 2. Spec Collection

The critique function gathers all `specs/spec-*.md` files, concatenates them with filename headers, and passes them as context to a single Claude call. Files are sorted by spec number to preserve reading order. The combined payload must fit within a single context window — if total spec content exceeds 80K tokens (estimated via `wc -c` with a 4-chars-per-token heuristic), the critique logs a warning and processes only the first N specs that fit.

### 3. Critique Prompt

The critique uses a dedicated prompt section (appended to `PROMPT_critique.md` or inlined in `automaton.sh`) that instructs Claude to evaluate specs against these dimensions:

- **Ambiguous requirements**: Vague language ("fast", "user-friendly", "scalable") without measurable criteria.
- **Missing acceptance criteria**: Requirements that lack a testable condition.
- **Inter-spec contradictions**: Two specs that define conflicting behavior for the same area.
- **Missing dependency declarations**: A spec references functionality from another spec without declaring the dependency.
- **Untestable criteria**: Acceptance criteria that cannot be verified programmatically or by inspection.
- **Scope gaps**: Features implied by the PRD or AGENTS.md that no spec covers.

The prompt outputs structured JSON so the report generator can format it deterministically.

### 4. Critique Output Format

The critique produces `.automaton/SPEC_CRITIQUE.md` with this structure:

```
# Spec Critique Report
Generated: [timestamp]
Specs analyzed: [count]

## Summary
- Errors: [count]
- Warnings: [count]
- Info: [count]

## Findings

### [ERROR] spec-05: Ambiguous requirement
**Requirement 3** uses "should be fast" without defining a latency target.
Suggestion: Add a measurable threshold (e.g., "responds within 200ms").

### [WARNING] spec-12 vs spec-07: Potential contradiction
spec-12 defines a per-phase budget but spec-07 defines per-iteration tracking.
Clarify which budget boundary the orchestrator enforces first.

### [INFO] spec-03: Missing dependency
References "enriched context" but does not declare dependency on spec-02.
```

Severity levels:
- **ERROR**: Likely to cause build failure or review rejection. Blocks pre-flight if auto mode is on.
- **WARNING**: May cause rework but build can proceed. Logged but non-blocking.
- **INFO**: Stylistic or minor. Never blocks.

### 5. Single Claude Call Budget

The critique must complete in exactly one Claude call using `claude -p`. No multi-turn conversation, no subagent spawning. Target token budget: 50K output tokens max. The orchestrator tracks this call against the project token budget under a `critique` phase category.

### 6. User Decision Flow

After critique completes:

- **Standalone mode**: Print summary to stdout, write full report to `.automaton/SPEC_CRITIQUE.md`, exit with code 0 (warnings only) or code 1 (errors found).
- **Pre-flight mode**: If errors found and `config.critique.block_on_error` is `true` (default: `true`), halt with message: `Spec critique found [N] errors. Review .automaton/SPEC_CRITIQUE.md and re-run.` If no errors, log summary and continue to Plan phase.
- **Override**: `./automaton.sh --skip-critique` bypasses pre-flight critique even when auto_preflight is enabled.

### 7. Idempotent and Non-Destructive

Running critique multiple times overwrites the previous `SPEC_CRITIQUE.md` but never modifies spec files. The critique is purely advisory — it reads specs and writes a report. No spec content is altered.

## Acceptance Criteria

- [ ] `./automaton.sh --critique-specs` reads all spec files and produces `.automaton/SPEC_CRITIQUE.md`
- [ ] Critique identifies at least one finding per dimension (ambiguity, missing criteria, contradiction, missing dependency, untestable) when given intentionally flawed test specs
- [ ] Critique completes in a single `claude -p` call with no subagent invocations
- [ ] Pre-flight mode blocks plan phase when errors are found and `block_on_error` is true
- [ ] Pre-flight mode proceeds to plan phase when only warnings are found
- [ ] `--skip-critique` flag bypasses pre-flight even when `auto_preflight` is enabled
- [ ] Token usage for the critique call is tracked under the `critique` phase in `.automaton/token_log.jsonl`
- [ ] Critique report is valid markdown and parseable by downstream tooling (grep for severity tags)
- [ ] Combined spec payload respects the 80K token estimate ceiling with graceful truncation
- [ ] Running critique twice on unchanged specs produces functionally identical reports

## Design Considerations

**Single bash file**: The critique is a function (`phase_critique()`) inside `automaton.sh`, following the same pattern as `phase_plan()` and `phase_build()`. No external scripts.

**Zero dependencies**: Uses `cat`, `wc`, `jq`, and `claude -p`. The prompt is either inlined as a heredoc or read from `PROMPT_critique.md` (same pattern as other phases).

**File-based state**: Report lands in `.automaton/SPEC_CRITIQUE.md`. Token usage appends to `.automaton/token_log.jsonl`. No databases, no network state.

**Budget awareness**: Competitors like Auto-Claude use a dedicated critic agent (separate context window, separate token spend). Automaton achieves the same outcome with a single call by front-loading all specs into one prompt. This keeps the cost to roughly 1 planning-call equivalent rather than an entire agent lifecycle.

**Prompt size management**: The 80K token ceiling (estimated at ~320KB of raw text) accommodates most projects. For very large spec sets, truncation with a warning is preferable to silent failure or context overflow.

## Dependencies

- Depends on: spec-02 (Converse Phase produces the spec files that critique reads)
- Depends on: spec-07 (Token Tracking records critique phase token usage)
- Depends on: spec-12 (Configuration provides `config.critique.*` settings)
- Related: spec-04 (Plan Phase runs after critique in the pipeline)
- Related: spec-11 (Quality Gates — critique is a pre-gate, not a gate itself; gates validate phase outputs while critique validates phase inputs)

## Files to Modify

- `automaton.sh` — Add `phase_critique()` function, `--critique-specs` and `--skip-critique` CLI flags, pre-flight hook before plan phase
- `automaton.config.json` — Add `critique` section: `{ "auto_preflight": false, "block_on_error": true, "max_token_estimate": 80000 }`
- `PROMPT_critique.md` — (new file, optional) Dedicated critique prompt if not inlined as heredoc
