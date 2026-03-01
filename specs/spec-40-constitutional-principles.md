# Spec 40: Constitutional Principles

## Purpose

Autonomous self-modification without governance is dangerous — an evolution loop could optimize for token efficiency by gutting safety checks, or chase novelty by making unnecessary architectural changes. Inspired by Constitutional AI (Anthropic), this spec defines a constitution that governs all autonomous evolution. The constitution is a set of inviolable principles organized into articles with protection levels. Every self-modification must pass a constitutional compliance check before committing. The constitution itself can be amended, but only through supermajority quorum vote (spec-39) with full audit trail. This creates a stable foundation for safe evolution: the system can grow in any direction the constitution permits, but cannot undermine its own safety constraints.

## Requirements

### 1. Constitution File

The constitution lives at `.automaton/constitution.md`, a human-readable markdown file:

```markdown
# Automaton Constitution
## Ratified: 2026-03-01

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.
No evolution cycle may disable, weaken, or bypass:
- Self-build safety protocol (spec-22)
- Syntax validation gates
- Smoke test requirements
- Circuit breakers (spec-45)
- Budget enforcement (spec-23)

A modification that degrades safety must be rejected regardless of other benefits.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority over automaton's evolution.
- All evolution can be paused via `--pause-evolution` (spec-44)
- The human can override any quorum decision via `--override` (spec-44)
- The human can amend the constitution via `--amend` (spec-44)
- No autonomous action may remove or restrict human control mechanisms
- The evolution loop must halt if it cannot reach the human operator

### Article III: Measurable Progress
**Protection: supermajority**

Every implemented change must target a measurable improvement:
- Token efficiency (tokens per completed task)
- Quality (test pass rate, rollback rate)
- Capability (new specs, functions, or test coverage)
- Reliability (stall rate, error rate)

Changes that cannot be measured against at least one metric must not be implemented.
The OBSERVE phase (spec-41) must compare before/after metrics for every implementation.

### Article IV: Transparency
**Protection: supermajority**

All autonomous decisions must be fully auditable:
- Every quorum vote is recorded with reasoning (spec-39)
- Every garden idea has a traceable origin (spec-38)
- Every signal has observation history (spec-42)
- Every implementation records its branch, commits, and metric deltas
- The human can inspect any decision via `--inspect` (spec-44)

Hidden or obfuscated decision-making is a constitutional violation.

### Article V: Budget Discipline
**Protection: supermajority**

Evolution must operate within defined resource constraints:
- Each evolution cycle has a budget ceiling (spec-45)
- Quorum voting has per-cycle cost limits (spec-39)
- The evolution loop must halt when budget is exhausted, not proceed on debt
- Budget overruns in one cycle reduce the next cycle's allocation
- Weekly allowance limits (spec-23) apply to evolution cycles

### Article VI: Incremental Growth
**Protection: majority**

Evolution proceeds through small, reversible steps:
- Each cycle implements at most one idea
- Each implementation modifies at most `self_build.max_files_per_iteration` files (spec-22)
- Each implementation changes at most `self_build.max_lines_changed_per_iteration` lines (spec-22)
- Complex ideas must be decomposed into smaller sub-ideas before implementation
- The system prefers many small improvements over few large changes

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution:
- Test pass rate must remain >= the pre-evolution baseline
- New functionality must include corresponding tests
- Removing a test requires quorum approval as a separate decision
- The OBSERVE phase must run the full test suite after every implementation
- Test count may increase but must never decrease without explicit justification

### Article VIII: Amendment Protocol
**Protection: unanimous**

This constitution may be amended through the following process:
1. An amendment idea is planted in the garden (spec-38) with `tags: ["constitutional"]`
2. The idea progresses through normal lifecycle stages (seed → sprout → bloom)
3. At bloom, the quorum evaluates with `constitutional_amendment` threshold (4/5 supermajority)
4. If approved, the amendment is applied to constitution.md
5. The amendment is recorded in constitution-history.json with before/after text
6. Articles with `unanimous` protection cannot have their protection level reduced
7. This article (Article VIII) cannot be removed or modified to reduce amendment requirements
```

### 2. Protection Levels

Each article has a protection level that determines the quorum threshold required to amend it:

| Protection Level | Quorum Threshold | Articles |
|-----------------|-----------------|----------|
| `unanimous` | 5/5 (all voters must approve) | I (Safety), II (Human Sovereignty), VIII (Amendment) |
| `supermajority` | 4/5 (spec-39 `constitutional_amendment` threshold) | III (Progress), IV (Transparency), V (Budget) |
| `majority` | 3/5 | VI (Incremental), VII (Test Coverage) |

Immutable constraints:
- `unanimous` articles cannot have their protection level reduced
- Article VIII cannot be removed or modified to weaken amendment requirements
- These immutable constraints are enforced in code, not just in the constitution text

### 3. Constitutional Compliance Check

A compliance function runs before every self-modification commit during evolution:

```bash
_constitution_check() {
    local diff_file="$1"      # Path to git diff of proposed changes
    local idea_id="$2"        # The garden idea being implemented
    local cycle_id="$3"       # Current evolution cycle

    # Check 1: Safety preservation (Article I)
    # - Diff must not remove or modify safety-related functions
    # - Protected functions list from self_build.protected_functions

    # Check 2: Human control preservation (Article II)
    # - Diff must not remove CLI flags: --pause-evolution, --override, --amend
    # - Diff must not modify _handle_human_override()

    # Check 3: Measurability (Article III)
    # - Idea must have at least one metric target in its description

    # Check 4: Scope limits (Article VI)
    # - Count files changed, lines changed
    # - Compare against self_build limits

    # Check 5: Test coverage (Article VII)
    # - If tests were removed, flag as violation
    # - If new functions were added without tests, flag as warning

    # Return: pass | warn | fail
    # warn = non-blocking, logged for human review
    # fail = blocks commit, wilts the idea
}
```

The compliance check is invoked by the evolution safety guard hook (spec-45) and by the orchestrator before committing any evolution-cycle changes.

### 4. Constitutional Compliance Agent

A dedicated agent definition at `.claude/agents/evolve-constitution-checker.md` performs deep compliance analysis when the automated checks are insufficient. This agent:

- Receives the proposed diff and the full constitution text
- Analyzes whether the change violates the spirit (not just the letter) of each article
- Produces a compliance report with per-article assessment

This agent is invoked only when the automated `_constitution_check()` returns `warn`, not on every commit.

### 5. Amendment History

All constitutional changes are recorded in `.automaton/constitution-history.json`:

```json
{
  "version": 1,
  "amendments": [
    {
      "amendment_id": "amend-001",
      "article": "VI",
      "type": "modify",
      "description": "Increase max_files_per_iteration from 3 to 5",
      "before_text": "Each implementation modifies at most 3 files",
      "after_text": "Each implementation modifies at most 5 files",
      "vote_id": "vote-012",
      "proposed_by": "human",
      "approved_at": "2026-03-15T10:00:00Z",
      "cycle_id": 12
    }
  ],
  "current_version": 1
}
```

Each amendment records the before/after text, the vote that approved it, and who proposed it. The `current_version` increments with each amendment, matching the version header in `constitution.md`.

### 6. Initial Ratification

On first `--evolve` run, if `.automaton/constitution.md` does not exist, the orchestrator creates it with the default 8 articles above and logs: `[EVOLUTION] Constitution ratified with 8 articles. Use --constitution to view, --amend to modify.`

The initial constitution is not subject to quorum vote — it is the bootstrap state. Only subsequent modifications require quorum approval.

### 7. Constitution in Prompts

The constitution is injected into evolution agent prompts (REFLECT, IDEATE, OBSERVE) so agents are aware of the governing principles. This is done via the bootstrap manifest (spec-37), not by reading the file:

```json
{
  "constitution_summary": {
    "articles": 8,
    "version": 1,
    "key_constraints": [
      "Safety mechanisms must be preserved (Art. I)",
      "Human retains override authority (Art. II)",
      "Changes must target measurable metrics (Art. III)",
      "Each cycle implements at most 1 idea (Art. VI)"
    ]
  }
}
```

### 8. Configuration

No dedicated config section — the constitution is self-contained. Protection levels and amendment rules are defined in the constitution itself, not in `automaton.config.json`. The only config interaction is through existing sections:

- `quorum.thresholds.constitutional_amendment` (spec-39) — threshold for amendments
- `self_build.protected_functions` (spec-22) — functions protected by Article I
- `self_build.max_files_per_iteration` / `max_lines_changed_per_iteration` — limits referenced by Article VI

## Acceptance Criteria

- [ ] `.automaton/constitution.md` created on first `--evolve` run with 8 articles
- [ ] Each article has an explicit protection level (unanimous/supermajority/majority)
- [ ] `_constitution_check()` runs before every evolution commit
- [ ] Compliance check blocks commits that violate `unanimous` or `supermajority` articles
- [ ] Compliance check warns (but does not block) on `majority` article concerns
- [ ] Constitutional amendments require quorum vote at the appropriate threshold
- [ ] Amendment history recorded in `constitution-history.json` with before/after text
- [ ] `unanimous` articles cannot have their protection level reduced (enforced in code)
- [ ] Article VIII cannot be weakened (self-protection of amendment process)
- [ ] Evolution agents receive constitution summary in their prompt context
- [ ] `--constitution` CLI command displays current constitution (spec-44)
- [ ] `--amend` CLI command initiates amendment process (spec-44)

## Dependencies

- Depends on: spec-22 (self-build safety — protected functions, scope limits)
- Depends on: spec-39 (quorum — amendment voting thresholds)
- Depends on: spec-37 (bootstrap manifest — constitution summary injection)
- Integrates with: spec-38 (garden — constitutional amendment ideas tagged `constitutional`)
- Depended on by: spec-41 (evolution loop — compliance check before commit)
- Depended on by: spec-44 (CLI — `--constitution` and `--amend` commands)
- Depended on by: spec-45 (safety — compliance check integrated into safety guard)

## Files to Modify

- `automaton.sh` — add `_constitution_check()`, `_constitution_create_default()`, `_constitution_amend()`, `_constitution_get_summary()`, integrate compliance check into evolution commit flow
- `.automaton/constitution.md` — new file: the constitution (created on first --evolve)
- `.automaton/constitution-history.json` — new file: amendment audit trail
- `.automaton/init.sh` — add `constitution_summary` to bootstrap manifest
- `.claude/agents/evolve-constitution-checker.md` — new file: deep compliance analysis agent
- `.gitignore` — add `.automaton/constitution.md` and `.automaton/constitution-history.json` as persistent state
