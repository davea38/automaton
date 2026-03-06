# Spec 58: Design Principles & Anti-Pattern Guard Rails

## Priority

P3 — When P0-P2 are Battle-Tested. Guard rails are not needed until the system has enough surface area to drift. Codifying principles early is cheap; enforcing them matters once features land.

## Competitive Sources

All 17 competitor analyses contributed. The top 10 anti-patterns distilled from the full survey:

1. **Complexity Spiral** — ruflo (393K LOC), Auto-Claude (451K LOC) grow until complexity itself is the primary bug source.
2. **Silent Failures** — gastown, claude-octopus swallow errors, leaving the user guessing.
3. **Dependency Hell** — sparc (9/13 open issues are install bugs), crewAI (75+ deps).
4. **Prompt-as-Code Fragility** — claude-octopus, wshobson/agents use prompts for deterministic control flow.
5. **Dashboard/GUI Bloat** — Auto-Claude (250K LOC Electron), Claude-Code-Workflow (169K LOC React).
6. **Tmux/Terminal Dependency** — gastown, oh-my-claudecode, zeroshot couple to terminal multiplexers.
7. **Feature Claims Without Implementation** — ruflo, sparc advertise features that do not exist.
8. **Scattered State Management** — oh-my-claudecode, ruflo spread state across dotfiles, databases, and config dirs.
9. **Over-Investment in TUI** — zeroshot (Rust TUI), MassGen (Textual TUI) spend most LOC on interface.
10. **Multi-Model Complexity** — oh-my-claudecode, claude-octopus add model-routing logic that rarely justifies its cost.

## Purpose

Without codified rules, development drifts toward competitor complexity. This spec creates two artifacts: a principles document that states the rules, and automated guard rail functions that enforce them. The guard rails run during review (spec-06), self-build (spec-25), and evolution (spec-41) phases, catching violations before they merge.

## Requirements

### 1. Design Principles Document

A file at `.automaton/DESIGN_PRINCIPLES.md` codifies the seven inviolable rules:

| # | Principle | Threshold / Rule |
|---|-----------|-----------------|
| 1 | Size Ceiling | `automaton.sh` must stay under 5,000 lines |
| 2 | Zero External Dependencies | Only bash, git, claude CLI, jq permitted |
| 3 | Plain Text State | All state lives in `.automaton/` as cat-able text files |
| 4 | Loud Failure | Every script uses `set -euo pipefail`; no silent swallowing |
| 5 | stdout is the UI | No TUI frameworks, no dashboards, no GUIs |
| 6 | Claude for Creativity Only | Bash handles deterministic logic; Claude handles ambiguous/creative tasks |
| 7 | No Feature Without Tests | Every new function must have a corresponding test in the test suite |

The file is human-readable markdown, version-controlled, and referenced by the constitution (spec-40) as an operational annex.

### 2. Automated Guard Rail Functions

A set of bash functions inside `automaton.sh` that run cheap, zero-API-call checks. Each function returns 0 on pass, 1 on violation, and appends details to the violations report.

**`guardrail_check_size`** — Runs `wc -l automaton.sh` and fails if the count exceeds 5,000. Reports the current line count and the delta from the ceiling.

**`guardrail_check_dependencies`** — Greps generated code and plan files for dependency-introducing commands: `apt-get`, `npm`, `pip`, `pip3`, `brew`, `cargo`, `gem`, `go get`, `curl | sh`, `wget | sh`. Any match is a violation.

**`guardrail_check_silent_errors`** — Greps for patterns that swallow errors without handling them: `2>/dev/null` without a preceding `||`, bare `|| true` without a comment explaining why, and `set +e` without a corresponding `set -e` restoration within 20 lines.

**`guardrail_check_state_location`** — Scans for state writes outside `.automaton/`. Greps for file writes (redirects `>`, `>>`, `tee`) whose target path does not start with `.automaton/`, `$AUTOMATON_DIR`, or standard output locations (`/dev/stdout`, `/dev/stderr`).

**`guardrail_check_tui_deps`** — Greps for TUI/GUI library imports or commands: `curses`, `tput cup`, `dialog`, `whiptail`, `electron`, `react`, `textual`. Any match is a violation.

**`guardrail_check_prompt_logic`** — Flags prompts that embed deterministic control flow (if/then/else, loops, counters) rather than delegating that to bash. Implemented as a grep for control-flow keywords inside heredoc prompt blocks.

### 3. Guard Rail Orchestration

A single dispatcher function `run_guardrails` calls all six checks and aggregates results:

- Runs during the review phase (spec-06) on every build cycle.
- Runs during self-build (spec-25) before accepting any self-modification.
- Runs during evolution loop (spec-41) before committing evolved code.
- Exit behavior is configurable: `guardrails_mode` in `automaton.config.json` accepts `"warn"` (log and continue) or `"block"` (fail the phase). Default is `"block"`.

### 4. Violations Report

When any guard rail check fails, `run_guardrails` produces `.automaton/principle-violations.md`:

```
# Principle Violations Report
Generated: 2026-03-03T14:22:00Z

## FAIL: Size Ceiling
automaton.sh is 5,127 lines (127 over the 5,000 limit).

## FAIL: Silent Error Swallowing
Line 412: `command 2>/dev/null` — error output discarded without fallback.
Line 789: `set +e` — not restored within 20 lines.

## PASS: Zero External Dependencies
## PASS: Plain Text State
## PASS: No TUI Dependencies
## PASS: No Prompt Logic
```

The report is plain text, cat-able, and committed to the state directory for audit. Previous reports are preserved as `.automaton/principle-violations-{timestamp}.md` so trends are visible.

### 5. Self-Build Protection Integration

When automaton operates in self-build mode (spec-25), the guard rails form a mandatory gate:

1. Self-build proposes changes to `automaton.sh`.
2. Changes are written to a staging copy (`automaton.sh.staged`).
3. `run_guardrails` executes against the staged copy.
4. If any check fails in `"block"` mode, the staged copy is rejected and the violations report explains why.
5. This prevents the system from evolving past its own design constraints.

## Acceptance Criteria

- [ ] `.automaton/DESIGN_PRINCIPLES.md` exists and documents all seven principles with measurable thresholds.
- [ ] `guardrail_check_size` correctly fails when `automaton.sh` exceeds 5,000 lines.
- [ ] `guardrail_check_dependencies` detects at least: `apt-get install`, `npm install`, `pip install`, `brew install`.
- [ ] `guardrail_check_silent_errors` flags `2>/dev/null` without error handling and unrestored `set +e`.
- [ ] `guardrail_check_state_location` flags file writes outside `.automaton/`.
- [ ] `guardrail_check_tui_deps` flags TUI/GUI library references.
- [ ] `guardrail_check_prompt_logic` flags control-flow keywords inside prompt heredocs.
- [ ] `run_guardrails` produces `.automaton/principle-violations.md` on any failure.
- [ ] Guard rails execute with zero API calls (grep/wc/awk only).
- [ ] Each individual guard rail function is under 30 lines of bash.
- [ ] `run_guardrails` dispatcher is under 40 lines of bash.
- [ ] Self-build mode (spec-25) invokes `run_guardrails` before accepting staged changes.
- [ ] `guardrails_mode` config option switches between `"warn"` and `"block"` behavior.

## Design Considerations

All guard rail functions use only bash builtins and standard unix tools (grep, wc, awk, date). No Claude API calls, no jq, no network access. This keeps them fast enough to run on every phase transition without budget impact.

The principles document is deliberately separate from the constitution (spec-40). The constitution governs evolution safety and human sovereignty. The principles document governs engineering quality. They complement each other: the constitution says "do not remove safety checks," the principles say "do not exceed 5,000 lines."

Guard rail checks are intentionally simple pattern matches. They will produce false positives (e.g., a comment mentioning `npm`). This is acceptable because violations trigger review, not automatic rejection in `"warn"` mode. In `"block"` mode, the developer inspects the report and either fixes the violation or adds a documented exception.

## Dependencies

- Depends on: spec-06 (Review Phase) -- guard rails run during review.
- Depends on: spec-25 (Self-Build Safety) -- guard rails gate self-modifications.
- Related: spec-40 (Constitutional Principles) -- complements with competitor-derived operational rules.
- Related: spec-41 (Evolution Loop) -- guard rails run before evolution commits.
- Related: spec-22 (Self-Build Safety) -- guard rails are critical during self-modification.
- Referenced by: spec-46 through spec-57 -- all new features must comply with these principles.

## Files to Modify

- `automaton.sh` -- add six `guardrail_check_*` functions and the `run_guardrails` dispatcher (~100 lines total).
- `automaton.config.json` -- add `guardrails_mode` key (`"warn"` or `"block"`, default `"block"`).
- `.automaton/DESIGN_PRINCIPLES.md` -- new file, the seven principles with thresholds (created on first run or by setup).
