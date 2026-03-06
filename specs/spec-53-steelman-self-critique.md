# Spec 53: STEELMAN Self-Critique

## Priority
P2 (Worth Building) -- Plans currently receive no adversarial analysis. A single
post-planning critique call surfaces risks cheaply before any code is written.
The cost is one Claude call; the payoff is catching flawed assumptions early.

## Competitive Sources
- **claude-octopus**: `STEELMAN.md` -- after generating a plan or spec, produces
  a document that argues against the chosen approach, identifies risks, and
  proposes alternatives. Forces explicit consideration of what could go wrong.

## Purpose
After the planning phase produces `IMPLEMENTATION_PLAN.md` and associated specs,
the steelman phase runs a single adversarial Claude call that argues *against*
the chosen approach. The output is a `STEELMAN.md` file in the project root.
This document does not block execution or alter the plan. It exists purely for
awareness -- a written record of risks the team (or future agents) should watch
for during implementation.

## Requirements

### 1. Trigger Conditions
The steelman phase activates when either condition is met:
- `flags.steelman_critique` is set to `true` in `automaton.config.json`
- The `--steelman` CLI flag is passed to `automaton.sh`

When neither condition is met, the phase is skipped entirely (no Claude call,
no file output). Default is `false` (off).

### 2. Input Gathering
Before invoking Claude, the phase collects context by reading:
- `.automaton/IMPLEMENTATION_PLAN.md` (required -- abort if missing)
- All files matching `specs/*.md` in the project
- `automaton.config.json` (for project-level context)

These are concatenated into a single prompt payload. No recursive directory
walks or dependency resolution -- just cat and concatenate.

### 3. Adversarial Prompt
A single Claude call is made with a system prompt that instructs the model to
act as a skeptical reviewer. The prompt must request exactly these sections:
- **Risks and Failure Modes** -- what can go wrong at runtime, at scale, or
  under edge cases the plan does not address.
- **Rejected Alternatives** -- approaches the plan implicitly chose not to take,
  with brief arguments for why they might have been better.
- **Questionable Assumptions** -- premises the plan depends on that may not hold.
- **Fragile Dependencies** -- external tools, APIs, or conventions the plan
  relies on that could change or break.
- **Complexity Hotspots** -- specific areas of the plan most likely to produce
  bugs during implementation.

The prompt must not ask the model to rewrite the plan or produce code.

### 4. Output File
The Claude response is written to `STEELMAN.md` in the project root (not inside
`.automaton/`). If the file already exists, it is overwritten. The file includes
a header comment with the generation timestamp and the model used.

### 5. Model Selection
Uses the same model as the planning phase. In practice this means the `model`
value from `automaton.config.json` (opus by default). No separate model config
for steelman.

### 6. Non-Blocking Behavior
The steelman phase must not:
- Set any error flags that would halt subsequent phases
- Modify `IMPLEMENTATION_PLAN.md` or any spec file
- Alter `.automaton/status` or phase-tracking state

If the Claude call fails (network error, rate limit), log a warning to stderr
and continue. The absence of `STEELMAN.md` is not a fatal condition.

### 7. Standalone Invocation
`automaton.sh --steelman` runs only the steelman phase against whatever plan
and specs currently exist on disk. It does not trigger planning, spec generation,
or implementation. Exit code is 0 on success, 1 if `IMPLEMENTATION_PLAN.md` is
missing.

## Acceptance Criteria
- [ ] `automaton.sh --steelman` produces `STEELMAN.md` when `IMPLEMENTATION_PLAN.md` exists
- [ ] `automaton.sh --steelman` exits with code 1 and a clear error when no plan exists
- [ ] `STEELMAN.md` contains all five required sections
- [ ] Steelman phase is skipped when flag is `false` and `--steelman` is not passed
- [ ] Steelman phase does not modify any existing files in `.automaton/` or `specs/`
- [ ] A failed Claude call logs a warning but does not block subsequent phases
- [ ] The feature adds fewer than 100 lines of bash to `automaton.sh`
- [ ] Only bash, git, claude CLI, and jq are used (zero new dependencies)

## Design Considerations
The implementation fits Automaton's architecture naturally:
- **Single bash file**: A new function (e.g., `run_steelman_critique`) added to
  `automaton.sh`. Flag parsing in the existing CLI argument loop.
- **Zero dependencies**: Uses `claude` CLI for the model call and `cat` for
  input assembly. No new tools.
- **File-based state**: Input is read from plain text files. Output is a plain
  text file. No database, no temp dirs, no background processes.
- **Budget-aware**: Exactly one Claude call. No iterative refinement loop. The
  prompt is self-contained so the model produces the full critique in a single
  response.
- **Ordering**: Runs after spec-04 (Plan Phase) completes. Complementary to
  spec-47 (Spec Critique), which operates pre-planning on individual specs.
  The two features bracket the planning phase: spec-47 critiques inputs,
  spec-53 critiques outputs.

## Dependencies
- Depends on: spec-04 (Plan Phase) -- steelman reads the plan that spec-04 produces
- Related: spec-47 (Spec Critique) -- pre-planning critique of individual specs;
  together they form a critique bracket around the planning phase

## Files to Modify
- `automaton.sh` -- add `run_steelman_critique` function, `--steelman` flag
  parsing, conditional invocation after planning phase
- `automaton.config.json` -- add `flags.steelman_critique` boolean (default: false)
