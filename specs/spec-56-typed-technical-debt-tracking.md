# Spec 56: Typed Technical Debt Tracking

## Priority

P3 — When P0-P2 are Battle-Tested. Debt tracking is a visibility feature, not a correctness feature. The system works without it, but debt from autonomous code generation accumulates silently until it causes failures. Once the core build/QA/review pipeline is solid, this makes the invisible visible.

## Competitive Sources

- **SWE-AF**: Typed debt tracking — during code generation, explicitly track known shortcuts and technical debt with typed categories. Makes debt visible and actionable rather than hidden in TODO comments scattered across the codebase.

## Purpose

Build agents take shortcuts. They hardcode values, skip error handling, stub out edge cases, and leave TODO comments promising future work that never arrives. In a human codebase this debt is at least visible during code review. In an autonomous pipeline, it is invisible — the agent that wrote the shortcut has already exited, and the next agent has no memory of the compromise.

This spec adds a post-build debt scanning step that greps generated code for known debt markers, classifies each finding by type, records them in a structured ledger, and surfaces counts in the run summary. No Claude API calls required — pure grep + jq.

## Requirements

### 1. Debt Marker Scanning

After each build iteration, scan all modified files for these debt markers: `TODO`, `FIXME`, `HACK`, `DEBT`, `WORKAROUND`, `TEMPORARY`. Each is matched via `grep -n`. Scanning targets only files changed in the current run (via `git diff --name-only` against the run's starting commit). This keeps scan time proportional to work done, not repo size.

### 2. Debt Type Classification

Each marker is classified into exactly one debt type based on keyword context and surrounding text:

| Type | Description | Heuristic |
|------|-------------|-----------|
| `error_handling` | Missing or incomplete error handling | Line contains `error`, `catch`, `exception`, `fail`, `retry` |
| `hardcoded` | Hardcoded values that should be configurable | Line contains `hardcode`, `magic`, `config`, `constant`, `literal` |
| `performance` | Known performance shortcuts | Line contains `slow`, `O(n`, `performance`, `optimize`, `cache` |
| `test_coverage` | Missing tests for generated code | Line contains `test`, `coverage`, `assert`, `spec`, `verify` |
| `cleanup` | Temporary code that should be refactored | Default — any marker not matching the above types |

Classification is done in bash via cascading `grep -qi` checks on the marker line text. No Claude call needed. The `cleanup` type is the catch-all default.

### 3. Debt Ledger

Findings are appended to `.automaton/debt-ledger.jsonl` (one JSON object per line):

```json
{"type":"hardcoded","file":"src/config.sh","line":42,"marker":"TODO","marker_text":"TODO: hardcoded timeout, should read from config","iteration":3,"timestamp":"2026-03-03T10:15:00Z"}
```

Fields: `type` (one of the five debt types), `file` (relative path), `line` (line number), `marker` (which marker matched), `marker_text` (full line text), `iteration` (build iteration number), `timestamp` (ISO 8601). JSONL format chosen over JSON array so entries can be appended with `>>` without parsing the existing file.

### 4. Debt Summary

At run completion, generate `.automaton/debt-summary.md`:

```markdown
# Technical Debt Summary
Run: 2026-03-03T10:00:00Z | Total: 14 items

## By Type
| Type | Count |
|------|-------|
| cleanup | 6 |
| error_handling | 4 |
| hardcoded | 2 |
| test_coverage | 1 |
| performance | 1 |

## Top Files
| File | Items |
|------|-------|
| src/build.sh | 5 |
| src/config.sh | 4 |
```

Generated via `jq` aggregation over the ledger file.

### 5. Run Summary Integration

Append debt counts to the existing run summary output:

```
Technical debt: 14 items (cleanup:6 error_handling:4 hardcoded:2 test_coverage:1 performance:1)
```

This single line goes into the run summary alongside token counts and test results, making debt visible without requiring a separate report check.

### 6. Debt Threshold Warning

Optional configurable threshold. When total debt items exceed the threshold, emit a warning:

```
WARNING: Technical debt (14 items) exceeds threshold (10). Review .automaton/debt-summary.md
```

Default threshold: 20 items. Set to 0 to disable. The warning is informational only — it does not block the run. The QA loop (spec-46) can optionally treat the threshold as a quality gate criterion.

### 7. Review Agent Integration

The review agent (spec-06) receives `.automaton/debt-summary.md` as context input. This lets the reviewer prioritize which debt items to flag — a persistent `error_handling` debt item is more urgent than a `cleanup` marker in test scaffolding. The review agent does not need to re-scan; it reads the pre-computed summary.

### 8. Configuration

New `debt_tracking` section in `automaton.config.json`:

```json
{
  "debt_tracking": {
    "enabled": true,
    "threshold": 20,
    "markers": ["TODO", "FIXME", "HACK", "DEBT", "WORKAROUND", "TEMPORARY"]
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable debt scanning after build iterations |
| `threshold` | number | 20 | Warn when total items exceed this count (0 to disable) |
| `markers` | string[] | See above | Debt markers to scan for (customizable) |

## Acceptance Criteria

- [ ] Modified files scanned for all six default debt markers after each build iteration
- [ ] Each finding classified into exactly one of: error_handling, hardcoded, performance, test_coverage, cleanup
- [ ] Findings appended to `.automaton/debt-ledger.jsonl` as valid JSONL
- [ ] `.automaton/debt-summary.md` generated at run completion with per-type and per-file counts
- [ ] Total and per-type debt counts included in run summary output
- [ ] Warning emitted when total debt exceeds configured threshold
- [ ] Review agent receives debt summary as context input
- [ ] Scanning uses only grep and jq — no Claude API calls
- [ ] Scanning targets only files changed in current run (not entire repo)
- [ ] Debt tracking disableable via `debt_tracking.enabled: false`

## Design Considerations

The scanning function is a single `_scan_technical_debt()` in automaton.sh, targeting <60 lines of bash. It pipes `git diff --name-only` into a `while read` loop, greps each file for markers, classifies via cascading string matches, and appends JSONL entries with `jq -nc`. The summary generation is a separate `_generate_debt_summary()` function (<30 lines) that aggregates the ledger with `jq -s 'group_by(.type)'`. No new dependencies — only grep, jq, and git, all already in automaton's dependency set. All state lives in `.automaton/` as cat-able plain text, consistent with the file-based state model.

## Dependencies

- Depends on: spec-05 (build phase — scanning runs after each build iteration)
- Depends on: spec-10 (state management — ledger and summary stored in `.automaton/`)
- Extends: spec-06 (review phase — review agent receives debt summary as context)
- Related: spec-46 (QA loop — debt threshold can serve as a quality gate criterion)
- Related: spec-43 (growth metrics — debt count is a candidate quality metric)
- Related: spec-11 (quality gates — debt threshold is a soft quality gate)

## Files to Modify

- `automaton.sh` — add `_scan_technical_debt()` and `_generate_debt_summary()` functions, wire scanning into build phase after each iteration, add debt counts to run summary output
- `automaton.config.json` — add `debt_tracking` configuration section
- `.automaton/debt-ledger.jsonl` — new file: append-only debt findings (one JSON object per line)
- `.automaton/debt-summary.md` — new file: human-readable debt report generated at run completion
