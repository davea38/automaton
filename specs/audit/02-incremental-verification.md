# Audit Finding 02: Missing Incremental Verification

## Problem

The current flow is: build ALL tasks -> then review EVERYTHING. This is a batch-and-check pattern. The review agent sees the entire codebase diff and must reason about everything at once. This causes:

1. **Context overload** — Review agent reads hundreds/thousands of lines of changes
2. **Bug compounding** — A bug in task 3 causes task 7 to build on broken foundations. By review time, the fix requires unwinding multiple tasks.
3. **Token waste** — Opus review of a large diff is expensive. Most of the diff is fine; the review agent spends tokens confirming good code.
4. **Late feedback** — Problems found in review require returning to build phase, re-reading context, re-understanding the codebase. Each round-trip burns a full iteration of tokens.

The QA loop (spec-46) partially addresses this by running tests between build and review. But it only catches test failures, not spec drift or architectural problems.

## What VSDD Gets Right Here

VSDD's Phase 2c (Refactor) happens after EACH test goes green, not after all tests. The adversarial review in Phase 3 operates on the complete but incrementally-verified result. The key insight: **verify small, review big.**

## Recommended Fix

### A. Post-Task Micro-Validation
After each build iteration (one task), run a lightweight check:
- Did the task's specific test pass? (already partially done via test-first)
- Does `bash -n` / lint still pass? (quick sanity)
- Has the task's acceptance criterion been met? (targeted check, not full review)

This is NOT a full review. It's a 30-second Sonnet call that checks one criterion.

### B. Accumulated Diff Tracking
Track which files changed in which task. When review runs, provide a per-task diff breakdown instead of one giant diff. This lets the review agent reason about changes in context.

### C. Early Escalation
If micro-validation fails 2 consecutive tasks, escalate to review immediately instead of waiting for all tasks to complete. This prevents the "build on broken foundations" problem.

## Token Impact
Micro-validation adds ~2K tokens per task (Sonnet). For a 20-task project, that's 40K tokens. But it prevents the 500K+ token cost of a failed review -> rebuild cycle. Net savings estimated 60-80%.

## Complexity
Moderate — new micro-validation prompt, changes to build loop, diff tracking in state.

## Dependencies
Depends on audit/01 (acceptance criteria extraction) for targeted criterion checking.
