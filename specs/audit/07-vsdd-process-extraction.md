# Audit Finding 07: VSDD Process Ideas Applicable to Automaton

## Source
"Verified Spec-Driven Development (VSDD)" — a methodology combining Spec-Driven Development, Test-Driven Development, and Verification-Driven Development with adversarial review.

Full gist: https://gist.github.com/dollspace-gay/d8d3bc3ecf4188df049d7a4726bb2a00

## Ideas Already Present in Automaton
- Sequential phases (VSDD Phases 1-5 map to automaton's 5 phases)
- Spec-first approach (Phase 0 conversation produces specs)
- Test integration (spec-36 test-first build strategy)
- Quality gates between phases
- Budget/cost awareness

## Ideas to Extract and Adapt

### 1. Adversarial Review with Different Model Family
**VSDD concept:** "Sarcasmotron" uses a DIFFERENT model (Gemini) to review, avoiding shared blind spots.
**Automaton gap:** Review uses Opus (same family as build's Sonnet). Both are Claude. Shared training = shared blind spots.
**Adaptation:** Add optional config for review model override. Could use Gemini via MCP, or at minimum use a different Claude model temperature/persona. Low priority but high-value for critical projects.
**Complexity:** Low (config + prompt change). Medium if adding non-Claude model support.

### 2. Red-Before-Green Gate
**VSDD concept:** "The Red Gate: All tests must fail before implementation begins."
**Automaton gap:** spec-36 has test-first discipline but no verification that tests actually FAIL before implementation. The build agent writes tests and immediately makes them pass. There's no gate ensuring the tests were red first.
**Adaptation:** After test skeleton generation (audit/06), run the tests and verify they fail. Store the failure count. After implementation, verify they pass. The delta (failures -> passes) proves the implementation did something meaningful.
**Complexity:** Low — run tests twice (before and after), compare results.

### 3. Convergence Signal (Four-Dimensional)
**VSDD concept:** Convergence is reached when spec, tests, implementation, and verification all "survive adversarial review." Work is done when the adversary is nitpicking, not finding real issues.
**Automaton gap:** Completion is binary — all checkboxes checked, tests pass, review passes. There's no gradient. A barely-passing review and a solid review look the same.
**Adaptation:** Add a review confidence score. The review agent rates confidence (1-5) across dimensions: spec coverage, test quality, code quality, regression risk. If all dimensions are 4+, complete. If any is <3, create tasks. This gives a richer signal than pass/fail.
**Complexity:** Low — prompt change + structured output parsing.

### 4. Edge Case Catalog
**VSDD concept:** "Explicitly enumerated boundary conditions, degenerate inputs" as part of the spec.
**Automaton gap:** Specs have acceptance criteria but no explicit edge case section. Edge cases are discovered (and missed) during build.
**Adaptation:** Add an "Edge Cases" section to the spec template (PROMPT_converse.md). During conversation phase, push the human to enumerate edge cases. During plan phase, each edge case becomes a test case.
**Complexity:** Low — template change + prompt update.

### 5. Feedback Integration Routing
**VSDD concept:** "Flaws route back to appropriate phases" — spec-level flaws go to Phase 1, test-level to Phase 2a, implementation-level to Phase 2c.
**Automaton gap:** Review creates tasks that go back to build. But if the review finds a SPEC problem (ambiguous requirement), it still creates a build task. The spec never gets fixed. The builder works around it.
**Adaptation:** Review agent classifies issues by level: spec, test, implementation. Spec-level issues route to a "spec amendment" step before returning to build. This prevents building against flawed specs.
**Complexity:** Moderate — new routing logic in orchestrator, spec amendment step.

### 6. Living Hypothesis (Anti-Waterfall)
**VSDD concept (from its own critique):** "Treat Phase 1 as 'living hypothesis' with parallel evolution of spec, implementation, and verification rather than sequential gates."
**Automaton gap:** Specs are frozen after Phase 0. Research may update them. But during build, if the builder discovers that a spec requirement is impossible or wrong, they "note it in the plan" and move on. The spec itself isn't updated.
**Adaptation:** Allow the build agent to propose spec amendments (not make them). Proposed amendments go into `.automaton/spec-amendments.json`. The review phase evaluates proposed amendments. Approved amendments update the spec. This keeps specs as living documents without letting the builder unilaterally change requirements.
**Complexity:** Moderate — new amendment workflow, prompt changes to build and review.

## Ideas Explicitly NOT Adopted

### Formal Verification (VSDD Phase 5)
VSDD proposes Kani, CBMC, Dafny, TLA+ for formal proofs. This is appropriate for safety-critical systems but not for a general-purpose coding factory. The overhead is too high and the tooling requires domain expertise. Automaton's test-based verification is the right level for its use case.

### Mutation Testing
VSDD proposes mutmut/Stryker for test effectiveness. Good idea in theory but adds significant execution time and token cost. Consider for v2 only after core pipeline is hardened.

### Multi-Model Adversarial Loop
VSDD's back-and-forth between builder and adversary until convergence is elegant but token-expensive. Automaton's single review pass with optional re-build is more practical. The convergence signal (idea #3 above) captures the benefit without the token cost.

## Priority Order for Adoption
1. Red-Before-Green Gate (#2) — lowest effort, highest signal improvement
2. Edge Case Catalog (#4) — spec template change, prevents missed edge cases
3. Convergence Signal (#3) — better completion detection
4. Feedback Integration Routing (#5) — prevents building against flawed specs
5. Living Hypothesis (#6) — spec evolution during build
6. Adversarial Review (#1) — model diversity for critical projects
