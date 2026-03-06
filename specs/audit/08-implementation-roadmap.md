# Audit Finding 08: Implementation Roadmap

## For the implementing agent

This document sequences the audit findings into a buildable plan. Each wave is independent of later waves but may depend on earlier ones.

---

## Wave 1: Foundation (No code changes to orchestrator)

### 1A. Test Suite Runner
**From:** audit/04-A
**Action:** Create `run_tests.sh` that discovers and runs all `tests/test_*.sh`, counts pass/fail, exits non-zero on failure.
**Output:** `run_tests.sh` in project root
**Effort:** ~50 lines bash

### 1B. ShellCheck Gate
**From:** audit/04-B
**Action:** Add `shellcheck automaton.sh lib/*.sh` to PROMPT_review.md as a mandatory check.
**Output:** Updated PROMPT_review.md
**Effort:** 5 lines in prompt

### 1C. Edge Case Section in Spec Template
**From:** audit/07-#4
**Action:** Add `## Edge Cases` section to `templates/PROMPT_converse.md` spec template. Update the conversation prompt to push for edge case enumeration.
**Output:** Updated PROMPT_converse.md, updated spec template
**Effort:** ~20 lines in prompts

---

## Wave 2: Spec Traceability (Prompt changes + plan format)

### 2A. Acceptance Criteria Extraction Format
**From:** audit/01-A
**Action:** Update PROMPT_plan.md to require acceptance criteria from specs to be extracted into the plan as `AC-XX-Y` items grouped under each spec section.
**Output:** Updated PROMPT_plan.md with new format requirements
**Effort:** ~30 lines in prompt

### 2B. Review Traceability Pass
**From:** audit/01-B
**Action:** Add a new phase to PROMPT_review.md: "For each AC-XX-Y, verify implementation evidence." Before the existing code review steps.
**Output:** Updated PROMPT_review.md
**Effort:** ~20 lines in prompt

### 2C. Traceability Report
**From:** audit/01-C
**Action:** Add instruction to PROMPT_review.md to generate `.automaton/traceability.json` mapping each AC to pass/fail with evidence.
**Output:** Updated PROMPT_review.md
**Effort:** ~15 lines in prompt

---

## Wave 3: Test-Driven Spec Compliance (Prompt + light orchestrator changes)

### 3A. Plan Phase Test Skeleton Generation
**From:** audit/06-A
**Action:** Update PROMPT_plan.md to generate test skeleton files (failing tests) from acceptance criteria. Each AC becomes a test function with `assert_fail "Not yet implemented"`.
**Output:** Updated PROMPT_plan.md
**Effort:** ~25 lines in prompt

### 3B. Red-Before-Green Gate
**From:** audit/07-#2
**Action:** In the orchestrator build loop, after plan phase completes, run the test suite and record failure count. After build completes, verify failure count decreased. Log the delta.
**Output:** ~30 lines in lib/lifecycle.sh or lib/qa.sh
**Effort:** Low

### 3C. Build Against Existing Tests
**From:** audit/06-B
**Action:** Update PROMPT_build.md to instruct: "Find pre-existing test skeletons. Implement code to make them pass. Do NOT modify skeleton test assertions."
**Output:** Updated PROMPT_build.md
**Effort:** ~10 lines in prompt

---

## Wave 4: Incremental Verification (Orchestrator changes)

### 4A. Post-Task Micro-Validation
**From:** audit/02-A
**Action:** After each build iteration, add a lightweight Sonnet call that checks: (1) task-specific test passes, (2) lint passes, (3) the task's AC is met. This is NOT a full review — it's a 2K-token sanity check.
**Output:** New micro-validation prompt (~30 lines), ~50 lines in orchestrator build loop
**Effort:** Moderate

### 4B. Per-Task Diff Tracking
**From:** audit/02-B
**Action:** Track `git diff --stat` per iteration in `.automaton/agents/`. Provide per-task diffs to review instead of full project diff.
**Output:** ~30 lines in orchestrator, updated review context assembly
**Effort:** Low

### 4C. Early Escalation
**From:** audit/02-C
**Action:** If micro-validation fails 2 consecutive tasks, force transition to review phase.
**Output:** ~15 lines in orchestrator build loop (extends existing stall detection)
**Effort:** Low

---

## Wave 5: Token Optimization (Orchestrator + prompt changes)

### 5A. Tiered Review (Mechanical + Judgment)
**From:** audit/05-A
**Action:** Split review into two calls: (1) Sonnet mechanical pass (tests/lint/typecheck), (2) Opus judgment pass (only if mechanical passes). The mechanical pass is cheap; judgment is expensive.
**Output:** New mechanical review prompt, orchestrator review phase split, ~80 lines
**Effort:** Moderate

### 5B. Delta-Only Review Context
**From:** audit/05-B
**Action:** When assembling review context, include only changed files and their related specs (via traceability map). Not the entire codebase.
**Output:** ~40 lines in context assembly
**Effort:** Low-Moderate (depends on Wave 2 being complete)

### 5C. QA Oscillation Detection
**From:** audit/05-D
**Action:** In the QA loop, track the set of failing tests per iteration. If a previously-fixed test re-fails, detect oscillation and escalate.
**Output:** ~25 lines in lib/qa.sh
**Effort:** Low

---

## Wave 6: Advanced Process (Optional, after Waves 1-5 proven)

### 6A. Review Confidence Score
**From:** audit/07-#3
**Action:** Update PROMPT_review.md to output a confidence score (1-5) across 4 dimensions. Orchestrator uses this for completion decision.
**Output:** Prompt change + ~20 lines parsing
**Effort:** Low

### 6B. Feedback Level Routing
**From:** audit/07-#5
**Action:** Review agent classifies issues as spec-level, test-level, or implementation-level. Spec-level issues create spec amendment proposals instead of build tasks.
**Output:** Prompt change + ~40 lines routing logic
**Effort:** Moderate

### 6C. Living Spec Amendments
**From:** audit/07-#6
**Action:** Build agent can propose spec amendments to `.automaton/spec-amendments.json`. Review evaluates them. Approved amendments update specs.
**Output:** New amendment workflow, ~60 lines orchestrator + prompt changes
**Effort:** Moderate

---

## What NOT to Build

- **No new evolution features** (audit/03) — freeze until core pipeline proven on 5+ projects
- **No formal verification** (audit/07) — wrong level of assurance for a general factory
- **No mutation testing** — too expensive for the value at current maturity
- **No TypeScript rewrite** (audit/04-D) — only if codebase exceeds 25K lines
- **No multi-model adversarial loop** — single review pass with confidence scoring is sufficient

---

## Success Metrics

After implementing Waves 1-5, measure on 3+ real projects:

| Metric | Current (estimated) | Target |
|---|---|---|
| Spec coverage (ACs verified) | Unknown | >90% |
| First-pass review success | ~40% (guess) | >70% |
| Tokens per completed task | Unknown | Track baseline, then reduce 30% |
| Build->Review round trips | ~2-3 | <1.5 average |
| QA oscillation incidents | Unknown | 0 |
