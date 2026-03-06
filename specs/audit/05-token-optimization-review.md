# Audit Finding 05: Token Waste in Review Phase and Agent Invocations

## Problem

Several areas of the pipeline burn tokens unnecessarily:

### A. Review Phase Uses Opus on Full Diff
The review agent (Opus) reads the entire codebase diff, all specs, and all test results. For a 20-task project, this can be 100K+ input tokens at $15/M = $1.50+ per review iteration. Most of the review is confirming "yes this is fine."

### B. Fresh Context = No Cache Reuse Across Iterations
The PRD chose fresh context per iteration (from RALPH). This is correct for preventing context pollution. But it means every build iteration re-reads the same specs, the same plan, the same AGENTS.md. The prompt caching optimization (spec-30) mitigates this with static prefix caching, but the dynamic context (plan state, budget) still invalidates caches.

### C. Research Phase May Over-Explore
The research agent has no budget sub-limit per search. It can spawn subagents to web-search broad topics, consuming research budget on tangential information. The 3-iteration cap helps but doesn't prevent expensive individual iterations.

### D. QA Loop Can Thrash
The QA loop (spec-46) runs up to 5 validate->fix cycles. If the fix agent doesn't understand the failure type, it can make changes that create new failures, leading to oscillation. Each cycle costs ~50K tokens.

## What VSDD Gets Right Here

VSDD uses different model families for different roles (builder vs adversary). Automaton already does model routing (Sonnet for build, Opus for review). But VSDD also proposes "Purity Boundary Map" — separating deterministic core from effectful shell. Applied to automaton: separate "check if tests pass" (deterministic, Haiku) from "review code quality" (judgment, Opus).

## Recommended Fixes

### A. Tiered Review
Split review into two passes:
1. **Mechanical pass (Sonnet, cheap):** Run tests, lint, typecheck. Binary pass/fail.
2. **Judgment pass (Opus, expensive):** Only runs if mechanical pass succeeds. Reviews spec coverage, architectural concerns.

This saves Opus tokens on runs that fail mechanically.

### B. Delta-Only Review Context
Instead of the full diff, give the review agent:
- Only the files that changed since last successful review
- Only the specs relevant to those changes (via traceability map from audit/01)
- Test results (always)

### C. Research Budget Sub-Limits
Add `budget.per_search` limit (e.g., 50K tokens) to prevent individual research queries from consuming the entire research budget.

### D. QA Oscillation Detection
Track the set of failing tests across QA iterations. If the same test fails -> gets "fixed" -> a different test fails -> that gets "fixed" -> original test fails again, detect the oscillation and escalate instead of continuing.

## Token Impact Estimates
- Tiered review: 40-60% reduction in review cost
- Delta-only context: 30-50% reduction in review input tokens
- Research sub-limits: Prevents 10x cost spikes
- QA oscillation detection: Prevents 2-3 wasted QA cycles ($0.50-1.50 saved)

## Complexity
A: Moderate (new review prompt split, orchestrator changes)
B: Low (context assembly changes)
C: Low (config + budget check)
D: Low (set comparison in QA loop)

## Dependencies
A depends on audit/02 (incremental verification gives mechanical pass data).
B depends on audit/01 (traceability map).
