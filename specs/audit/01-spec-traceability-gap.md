# Audit Finding 01: Spec-to-Code Traceability Gap

## Problem

The PRD (section 10, Gate 5) calls for "spec-to-code traceability check" in the review phase. The implementation plan mentions it. But the actual PROMPT_review.md does not enforce it, and no tooling exists to perform it.

Currently:
- Specs define requirements with acceptance criteria
- The plan references specs loosely (spec numbers in task names)
- Build agents implement tasks
- Review agents check "does the code work" but NOT "does the code cover all spec requirements"

This means a spec requirement can be silently dropped. A task might be marked [x] while only partially implementing its spec. The review agent has no structured way to verify coverage.

## Impact on Hit Rate

This is the single biggest risk to goal achievement. Without traceability:
- Requirements drift silently during build
- Partial implementations pass review
- The system claims COMPLETE while specs are unmet
- Token spend is wasted on building things that don't match the ask

## What VSDD Gets Right Here

The VSDD gist describes a "Contract Chain": `Spec Requirement -> Test Case -> Implementation -> Review -> Proof`. Every spec item is traced through the entire pipeline. This is the core idea automaton is missing.

## Recommended Fix

### A. Acceptance Criteria Extraction
During the plan phase, extract each spec's acceptance criteria into a structured checklist in `IMPLEMENTATION_PLAN.md`. Format:

```
### Spec 03: Authentication
Acceptance Criteria:
- [ ] AC-03-1: Login endpoint returns JWT within 200ms
- [ ] AC-03-2: Invalid credentials return 401
- [ ] AC-03-3: Token expires after configured TTL
Tasks:
- [ ] Implement login endpoint
- [ ] Add JWT generation
```

### B. Review Phase Traceability Pass
Add a dedicated step to PROMPT_review.md where the review agent walks each AC-XX-Y item and verifies it against the code. Not "does the code look good" but "is AC-03-1 satisfied — show me the evidence."

### C. Traceability Report
Generate `.automaton/traceability.json` mapping each AC to its verification status. This becomes the definitive answer to "are we done?"

## Complexity
Moderate — prompt changes + plan format change + one new report. No orchestrator code changes needed.

## Dependencies
None — can be implemented immediately.
