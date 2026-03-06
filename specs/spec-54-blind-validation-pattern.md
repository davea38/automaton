# Spec 54: Blind Validation Pattern

## Priority

P2 (Worth Building) -- Reviewers who see implementation context develop confirmation bias, evaluating code through the builder's framing rather than against the spec. Blind validation forces an independent assessment, catching structural misses that contextual review overlooks.

## Competitive Sources

- **zeroshot**: Blind validation where validators never see the implementer's context. They receive only spec requirements and final output (test results, code diff), preventing bias from implementation details.

## Purpose

Provide an alternative validation mode where a separate Claude invocation reviews changes with no access to the builder's reasoning, implementation plan, commit messages, or previous review feedback. The validator sees only three things: the spec acceptance criteria, test results, and the raw code diff. This forces evaluation against what was *asked for*, not what was *intended*.

### Problem

spec-06 (Review Phase) currently loads IMPLEMENTATION_PLAN.md, all specs, and the full codebase into the reviewer's context. The reviewer sees everything the builder saw. This creates several failure modes:

1. **Confirmation bias** -- the reviewer follows the builder's reasoning and agrees with it
2. **Framing effects** -- the builder's commit messages and plan prime the reviewer to look for specific things, missing what falls outside that frame
3. **Surface-level validation** -- reviewer checks "did they do what they said they'd do" instead of "did they do what the spec requires"

### Solution

A blind validation pass where a fresh Claude invocation answers one question: "Do the changes satisfy the spec requirements? If not, what's missing?"

## Requirements

### 1. Separate Claude Invocation

The blind validator MUST run as its own `claude` CLI call, completely isolated from the builder and the normal reviewer. No shared context, no session continuity. This is the core guarantee -- the validator has never seen the implementation plan or the builder's reasoning.

### 2. Restricted Input Set

The blind validator receives exactly three inputs, concatenated into its prompt:

- **Spec acceptance criteria** -- extracted from the relevant spec file, specifically the `## Acceptance Criteria` section. If the spec lacks this section, fall back to `## Requirements`.
- **Test results** -- stdout/stderr from the most recent test run, stored in `.automaton/test-results.log`. If no test results exist, this section is omitted with a note.
- **Git diff** -- output of `git diff` for the changes under review. Only code changes, no commit messages.

Nothing else. No IMPLEMENTATION_PLAN.md, no builder commit messages, no previous review feedback, no full codebase beyond the diff.

### 3. Excluded Context

The following MUST NOT be provided to the blind validator:

- `IMPLEMENTATION_PLAN.md`
- Builder's commit messages (use `git diff` not `git log`)
- Previous review feedback from spec-06
- The builder's prompt or system instructions
- Any `.automaton/` state files beyond test results

### 4. Structured Verdict

The validator produces a verdict in a fixed format:

```
VERDICT: PASS | FAIL
CRITERIA_MET: [list of acceptance criteria satisfied]
CRITERIA_MISSED: [list of acceptance criteria not satisfied, with reasoning]
ISSUES: [any problems found that fall outside listed criteria]
```

This format is parseable by bash/jq for downstream automation.

### 5. Flag-Gated Activation

Enabled via configuration flag `flags.blind_validation: true` in `automaton.config.json`. Default is `false`. When disabled, the review phase runs exactly as spec-06 defines. When enabled, blind validation runs as an additional pass after the normal spec-06 review, not as a replacement.

### 6. Result Storage

Validator output is written to `.automaton/blind-validation.md` as plain text. Each run overwrites the previous result. The file includes a timestamp and the spec number being validated.

### 7. Budget Awareness

Blind validation adds exactly one Claude CLI call per review cycle. The prompt should be compact -- acceptance criteria plus diff plus test output, no padding. For large diffs, truncation to the last N lines (configurable, default 500) keeps token usage bounded.

## Acceptance Criteria

- [ ] Blind validator runs as a separate `claude` CLI invocation with no shared session state
- [ ] Validator prompt contains only: spec acceptance criteria, test results, and git diff
- [ ] Validator prompt does NOT contain: IMPLEMENTATION_PLAN.md, commit messages, prior review feedback
- [ ] Validator outputs structured verdict (PASS/FAIL with criteria mapping)
- [ ] Feature is gated behind `flags.blind_validation: true` in config
- [ ] Runs after spec-06 review, not instead of it
- [ ] Results stored in `.automaton/blind-validation.md`
- [ ] Adds at most one additional Claude CLI call per review cycle
- [ ] Diff truncation applies when changes exceed configured line limit
- [ ] Works within single bash file constraint using only bash, git, claude CLI, jq

## Design Considerations

### Fits Single Bash File

Implementation is a single function (e.g., `run_blind_validation()`) that:
1. Reads the flag from config via `jq`
2. Extracts acceptance criteria from the spec file via `sed`/`grep`
3. Captures `git diff` output
4. Reads `.automaton/test-results.log` if it exists
5. Concatenates these into a prompt string
6. Calls `claude` CLI with that prompt
7. Writes output to `.automaton/blind-validation.md`

Estimated size: 40-60 lines of bash.

### Fits File-Based State

All inputs are already files (spec markdown, test log, git diff output). The result is a single markdown file. No new state format needed.

### Integration with Review Flow

The blind validation function is called at the end of the existing review phase, gated by a flag check. If the blind validator returns FAIL, the overall review status should reflect that -- even if spec-06's contextual review passed.

### Diff Truncation Strategy

Large diffs are truncated from the top, keeping the most recent changes. This biases toward files modified last, which correlates with final integration work. The truncation limit is read from config (`blind_validation.max_diff_lines`, default 500).

## Dependencies

- **Depends on**: spec-06 (Review Phase) -- blind validation hooks into the review phase as an additional pass
- **Related**: spec-46 (QA Loop) -- blind validation can serve as one of the validators in a multi-validator QA loop
- **Related**: spec-01 (Config) -- uses `flags.blind_validation` and `blind_validation.max_diff_lines` config keys

## Files to Modify

- `automaton.sh` -- add `run_blind_validation()` function, call it at end of review phase when flag is set
- `automaton.config.json` -- add `flags.blind_validation` (boolean) and `blind_validation.max_diff_lines` (integer) config keys
