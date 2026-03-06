# Automaton Architectural Audit — Summary

**Date:** 2026-03-06
**Scope:** Full traversal of all logic branches, PRD alignment, competitive viability as AI coding factory, VSDD process comparison
**Total codebase:** ~17,187 lines bash (automaton.sh + 17 lib modules), 59 specs, 12 prompt files, 78 files in specs/

---

## Verdict: Does this work as an AI coding factory?

**Mostly yes, with critical gaps.** The architecture is sound — sequential phases, fresh context per iteration, file-based state, budget enforcement. These are the right foundations. But there are structural issues that will hurt hit rate, inflate token spend, and produce bugs at scale.

The system has grown from a clean 5-phase orchestrator into a 17,000-line bash monolith with an evolution subsystem that is sophisticated but untested in production. The core pipeline (converse -> research -> plan -> build -> review) is solid. The evolution layer (specs 38-45) is over-engineered relative to the core pipeline's maturity.

---

## Alignment with Original PRD Principles

| PRD Principle | Status | Notes |
|---|---|---|
| Bash orchestrator, not a server | HELD | But at 17K lines, bash is straining |
| File-based state, not SQLite | HELD | Clean implementation |
| Five phases, fixed sequence | HELD | Plus QA sub-loop and evolution loop |
| Single builder default, parallel opt-in | HELD | Both tmux and agent-teams modes |
| Conversation-first UX | HELD | PROMPT_converse.md is well-structured |
| Budget as first-class | HELD | Per-phase, per-iteration, weekly allowance |
| No MCP, no daemon, no port | HELD | Pure CLI |
| Five agent roles | STRETCHED | Now 5 core + 5 voter + 3 evolution + constitution checker = 14 agents |
| "Read entire system in 30 minutes" | BROKEN | 17K lines + 59 specs is not 30-minute readable |
| Fresh context per iteration | HELD | Core design preserved |

**Assessment:** The core principles survive but are under pressure from scope creep. The evolution subsystem (specs 38-45) added ~40% of the codebase complexity for a feature that is secondary to the primary mission of "ideation to creation."

---

## Critical Findings (7 specs follow)

1. **No spec-to-code traceability loop** — The #1 gap for hit rate
2. **No incremental verification** — Build produces bulk, review checks at the end
3. **Evolution before core hardening** — Priorities inverted
4. **Bash at scale limits** — 17K lines with no unit test harness for the orchestrator itself
5. **Token waste in the review phase** — Opus reads everything instead of targeted checks
6. **Missing acceptance test generation** — Specs have criteria but no auto-generated test scaffolds
7. **VSDD process has extractable ideas** — Adversarial review, red-before-green, convergence signals

See individual specs: `audit/01-*` through `audit/07-*`
