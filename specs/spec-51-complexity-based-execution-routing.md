# Spec 51: Complexity-Based Execution Routing

## Priority

P2 (Worth Building). Same pipeline depth for a typo fix vs an architectural change wastes tokens. A cheap pre-classification step can cut token spend on simple tasks by 80% while reserving deeper analysis for tasks that actually need it.

## Competitive Sources

- **Auto-Claude**: AI-based complexity scoring that classifies tasks and adjusts pipeline depth accordingly.
- **zeroshot**: 2D task classification (complexity axis x task type axis) where simple tasks skip phases entirely.
- **SWE-AF**: Three nested loops for complex tasks vs a single pass for simple ones.
- **wshobson/agents**: 3-tier model strategy (haiku for simple, sonnet for medium, opus for complex).

## Purpose

Assess task complexity before execution and route through an appropriately-sized pipeline. Typo fixes should not burn through research, opus-grade builds, and multiple review iterations. Architectural changes should not skip validation steps that catch cross-file breakage.

## Requirements

### 1. Complexity Assessment Call

A single Claude call using haiku runs before the main execution pipeline. Input is the task description and any referenced spec files. Output is a structured JSON classification. This call must be cheap -- under 1k input tokens, under 200 output tokens. The prompt asks the model to classify the task and provide a one-line rationale.

### 2. Tier Definitions

Three tiers with concrete heuristics:

| Tier | Label | Examples | Signals |
|------|-------|----------|---------|
| 1 | SIMPLE | Typo fix, config value change, comment update, version bump | Single file, no logic change, no new tests needed |
| 2 | MODERATE | Single feature, bug fix, add a test, refactor one function | 1-3 files, contained logic change, existing patterns |
| 3 | COMPLEX | Multi-file architecture change, new subsystem, cross-cutting concern | 4+ files, new patterns, dependency changes, API surface change |

### 3. Execution Routing Per Tier

**SIMPLE tier:**
- Skip the research phase entirely.
- Use sonnet for the build step.
- Cap review at 1 iteration maximum.
- Skip blind validation (spec-54).
- Skip steelman critique.
- Target token budget: <20% of COMPLEX.

**MODERATE tier:**
- Run the standard pipeline as currently implemented.
- Use sonnet for the build step.
- Allow up to 2 review iterations (spec-46 QA loop default).
- Skip blind validation.

**COMPLEX tier:**
- Run full research phase.
- Use opus for the build step.
- Allow up to 4 review iterations (spec-46 extended).
- Enable blind validation (spec-54).
- Enable steelman critique in review.
- No token budget cap.

### 4. State File

Classification is stored in `.automaton/complexity.json` with the following structure:

```json
{
  "tier": "SIMPLE",
  "rationale": "Single config value change in one file",
  "assessed_at": "2026-03-03T14:30:00Z",
  "override": false
}
```

This file is written once per task invocation. It is readable by all downstream pipeline stages to adjust their behavior. The file is plain text and cat-able per Automaton conventions.

### 5. CLI Override

A `--complexity=simple|moderate|complex` flag bypasses the assessment call entirely. When used, the `override` field in `complexity.json` is set to `true`. This is useful when the user knows the scope upfront and wants to skip the assessment cost, or when the classifier gets it wrong.

### 6. Budget Guardrails

Approximate token targets per tier (build step only, excludes assessment):

| Tier | Input Tokens | Output Tokens | Model |
|------|-------------|---------------|-------|
| SIMPLE | ~4k | ~2k | sonnet |
| MODERATE | ~16k | ~8k | sonnet |
| COMPLEX | ~32k | ~16k | opus |

The assessment call itself should never exceed 1.5k total tokens regardless of tier.

### 7. Fallback Behavior

If the assessment call fails (network error, malformed response, timeout), default to MODERATE. Log the failure to `.automaton/errors.log` and continue. Never block execution on a failed classification.

## Acceptance Criteria

- [ ] Single haiku call classifies task into SIMPLE, MODERATE, or COMPLEX before pipeline runs.
- [ ] Classification is written to `.automaton/complexity.json` with tier, rationale, timestamp, and override flag.
- [ ] SIMPLE tasks skip research phase and cap review at 1 iteration.
- [ ] COMPLEX tasks use opus for build and allow up to 4 review iterations.
- [ ] `--complexity=simple|moderate|complex` flag overrides the assessment call.
- [ ] Assessment call uses under 1.5k total tokens.
- [ ] SIMPLE tasks use less than 20% of a COMPLEX task's token budget.
- [ ] Failed assessment defaults to MODERATE without blocking execution.
- [ ] All routing logic is implementable within automaton.sh (no external scripts).

## Design Considerations

The assessment is a single `claude` CLI call with `--model haiku` piped through `jq` to extract the tier. The routing logic is a bash `case` statement on the tier value that sets variables consumed by downstream functions (e.g., `BUILD_MODEL`, `MAX_REVIEW_ITERATIONS`, `SKIP_RESEARCH`). This keeps the implementation under the 100-line-per-feature budget.

The `complexity.json` file follows the same pattern as other `.automaton/` state files -- written with a simple `cat <<EOF >` redirect, read with `jq` where structured access is needed or `grep` for quick checks.

Pipeline stages that vary by tier should read the tier from `complexity.json` rather than accepting it as a function argument. This keeps function signatures stable and allows any stage to adjust behavior independently.

## Dependencies

- **Depends on: spec-46 (QA loop)** -- tier determines `MAX_REVIEW_ITERATIONS` (1 for SIMPLE, 2 for MODERATE, 4 for COMPLEX).
- **Depends on: spec-54 (Blind validation)** -- only COMPLEX tasks enable blind validation; the routing decision lives here.
- **Related: automaton.config.json** -- tier thresholds and token budgets may become configurable in a future spec.

## Files to Modify

- `automaton.sh` -- Add `assess_complexity()` function (~30 lines), add routing `case` block (~20 lines), add CLI flag parsing for `--complexity` (~10 lines), modify pipeline entry point to call assessment before execution (~5 lines).
- `.automaton/complexity.json` -- New state file, created per task invocation.
