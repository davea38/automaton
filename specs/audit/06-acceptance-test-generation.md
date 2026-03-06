# Audit Finding 06: Missing Acceptance Test Generation from Specs

## Problem

Specs contain acceptance criteria:
```markdown
## Acceptance Criteria
- [ ] Login endpoint returns JWT within 200ms
- [ ] Invalid credentials return 401
```

The plan phase annotates tasks with `<!-- test: tests/test_auth.sh -->`. But the actual test files are written by the BUILD agent as part of "test-first" discipline (spec-36). This means:

1. The build agent writes both the test AND the implementation. Same agent, same context, same blind spots.
2. Tests tend to verify what was built, not what was specified. The agent writes a test for its implementation, not for the spec's acceptance criteria.
3. Test quality varies by task complexity. Simple tasks get good tests. Complex tasks get shallow tests because the agent is already token-constrained.

## What VSDD Gets Right Here

VSDD's Phase 2a is "Test Suite Generation" — tests are written BEFORE implementation, by a dedicated step, translating spec requirements into executable tests. The "Red Gate" requires ALL tests to fail before implementation begins. This ensures tests are spec-driven, not implementation-driven.

The critical insight: **the entity that writes the test should NOT be the entity that writes the implementation.** Separation prevents confirmation bias.

## Recommended Fix

### A. Plan Phase Generates Test Skeletons
During the plan phase (not build), generate test file skeletons from acceptance criteria. Each AC becomes a test case with:
- A descriptive name matching the AC
- A `# TODO: implement` placeholder
- The expected behavior documented in a comment

```bash
test_login_returns_jwt() {
    # AC-03-1: Login endpoint returns JWT within 200ms
    # TODO: implement
    assert_fail "Not yet implemented"
}
```

### B. Build Agent Implements Against Existing Tests
The build agent finds pre-existing test skeletons and implements code to make them pass. This is true TDD — the test exists before the code. The build agent may add MORE tests but cannot modify the skeleton tests' assertions.

### C. Review Agent Verifies AC-to-Test Mapping
The review agent checks that every AC-XX-Y has a corresponding test that passes. Not "do tests exist" but "does each acceptance criterion have a test that actually exercises it."

## Why This Matters for Hit Rate

This is the difference between "code that works" and "code that does what was asked." Without spec-driven tests, the build agent can produce working code that doesn't satisfy requirements. With spec-driven tests, the build agent has a concrete target: make these specific tests pass.

## Token Impact
- Plan phase: +5-10K tokens for test skeleton generation (Sonnet, cheap)
- Build phase: Slightly fewer tokens because tests provide clearer targets
- Review phase: Significantly fewer tokens because AC coverage is verifiable mechanically

## Complexity
Moderate — new plan phase output, changes to build prompt, review prompt changes.

## Dependencies
Depends on audit/01 (acceptance criteria extraction format).
Feeds into audit/02 (micro-validation uses these tests).
