# Spec 50: Config Pre-Flight Validation

## Priority

P1 — Prevent User Frustration. Invalid configuration values cause failures deep into
execution after tokens and budget have already been spent. Catching bad config before
any phase runs is the single highest-leverage quality-of-life improvement.

## Competitive Sources

- **zeroshot** — `config-validator.js` validates model names, detects conflicting
  options, and identifies unreachable states before any agent execution begins.
- **crewAI** — Pydantic-based config validation provides type-checked fields with
  clear, human-readable error messages emitted at startup.

Both competitors treat config validation as a distinct pre-flight step rather than
inline error handling during execution. This spec adopts the same pattern.

## Purpose

Define a `validate_config()` function that runs automatically before any phase begins.
It checks JSON syntax, types, value ranges, enum membership, and cross-field conflicts,
then reports every error at once so the user can fix them in a single pass. No Claude
API calls or token spend occurs if validation fails.

## Why spec-12 Is Not Sufficient

Spec-12 (Configuration) defines the schema and `load_config()`. Loading uses jq
defaults for missing fields but performs no validation. A user can set
`max_total_tokens` to `-5`, `primary` model to `"gpt-4"`, or `per_iteration` to a
value exceeding every phase budget — all silently accepted until they cause cryptic
failures mid-run.

## Requirements

### 1. JSON Syntax Validation

Parse `automaton.config.json` with `jq empty`. If parsing fails, emit the jq error
message verbatim and exit 1. No further checks run — the file must parse before
field-level validation is possible.

### 2. Type Checking

Verify each field matches its expected JSON type:

| Section       | Field                    | Expected Type |
|---------------|--------------------------|---------------|
| models.*      | primary, research, etc.  | string        |
| budget        | max_total_tokens         | number        |
| budget        | max_cost_usd             | number        |
| budget        | per_iteration            | number        |
| budget        | per_phase.*              | number        |
| rate_limits   | tokens_per_minute        | number        |
| rate_limits   | cooldown_seconds         | number        |
| rate_limits   | backoff_multiplier       | number        |
| execution     | max_iterations.*         | number        |
| execution     | stall_threshold          | number        |
| execution     | max_consecutive_failures | number        |
| git           | auto_push, auto_commit   | boolean       |
| git           | branch_prefix            | string        |
| flags         | dangerously_skip_permissions, verbose | boolean |

Use jq `type` checks. Collect all type mismatches before reporting.

### 3. Range Validation

Enforce value constraints on numeric fields:

- `budget.max_total_tokens` > 0
- `budget.max_cost_usd` > 0
- `budget.per_iteration` > 0
- `budget.per_phase.*` >= 0
- `rate_limits.tokens_per_minute` > 0
- `rate_limits.cooldown_seconds` >= 0
- `rate_limits.backoff_multiplier` > 1.0
- `execution.max_iterations.*` >= 0
- `execution.stall_threshold` >= 1
- `execution.max_consecutive_failures` >= 1

### 4. Enum Validation

Model names (`models.*`) must be one of: `"opus"`, `"sonnet"`, `"haiku"`.
Report the invalid value and the field path (e.g., `models.primary: "gpt-4"`).

### 5. Cross-Field Conflict Detection

Errors (exit 1):
- Any `budget.per_phase.*` value exceeds `budget.max_total_tokens`.
- `budget.per_iteration` exceeds the smallest `budget.per_phase.*` value.

### 6. Warnings for Unusual Values

Warnings (stderr, do not cause exit 1):
- `execution.max_iterations.build` > 50 — likely unintentional infinite loop risk.
- `budget.max_cost_usd` > 200 — unusually high spend limit.
- All phase timeouts set to 0 — no timeout protection on any phase.
- `rate_limits.backoff_multiplier` > 10 — aggressive backoff, likely a typo.
- `execution.stall_threshold` equals `execution.max_consecutive_failures` — stall
  detection and failure abort will trigger simultaneously.

### 7. Aggregate Error Reporting

Collect all errors into an array. After all checks complete, print every error with
its field path and a human-readable message. Format:

```
CONFIG ERROR: budget.max_total_tokens must be > 0 (got: -5)
CONFIG ERROR: models.primary must be one of opus|sonnet|haiku (got: "gpt-4")
CONFIG WARNING: budget.max_cost_usd is $500.00 — unusually high
Found 2 config errors. Fix automaton.config.json and re-run.
```

### 8. Invocation

- **Automatic**: `validate_config()` runs inside `main()` after `load_config()` and
  before any phase dispatch. Failure exits with code 1.
- **Explicit**: `automaton.sh --validate-config` runs validation only, prints results,
  and exits. Useful for CI and editor integration.

### 9. No API Calls

Validation uses only bash builtins and jq. Zero network calls, zero token spend,
zero Claude CLI invocations. The function must work fully offline.

## Acceptance Criteria

- [ ] Missing config file produces a clear error naming the expected path.
- [ ] Malformed JSON produces the jq parse error and exits 1.
- [ ] Each type mismatch (string where number expected, etc.) is reported.
- [ ] Out-of-range values produce errors naming the field, constraint, and actual value.
- [ ] Invalid model names are rejected with the list of valid options.
- [ ] per_phase budget exceeding max_total_tokens is caught.
- [ ] per_iteration exceeding smallest per_phase budget is caught.
- [ ] Multiple errors are reported in a single run (not fail-on-first).
- [ ] Warnings print to stderr and do not cause a non-zero exit.
- [ ] `--validate-config` flag works standalone without starting execution.
- [ ] Valid config passes silently (no output) and allows execution to proceed.
- [ ] No network calls or token spend during validation.

## Design Considerations

- Implementation lives in a single `validate_config()` function inside `automaton.sh`.
  Target < 80 lines of bash. Heavy lifting is done by jq expressions that return
  arrays of error strings, minimizing bash loop complexity.
- Errors accumulate in a bash array (`CONFIG_ERRORS+=(...)`). Warnings go directly
  to stderr. Final error count determines exit code.
- No new files in `.automaton/` — validation is stateless and produces no artifacts.
- jq is the only tool used for JSON inspection. No python, no node, no external
  validators.

## Dependencies

- **Depends on**: spec-12 (Configuration) — defines the schema, field names, and
  `load_config()` function that runs before `validate_config()`.
- **Related**: spec-01 (Core Loop) — `main()` must call `validate_config()` after
  config load and before phase dispatch.

## Files to Modify

- `automaton.sh` — add `validate_config()` function; add call site in `main()` after
  `load_config()`; add `--validate-config` flag handling in argument parser.
