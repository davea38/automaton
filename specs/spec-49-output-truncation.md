# Spec 49: Output Truncation (Head/Tail)

## Priority

P1 — Prevent User Frustration. Current head-only truncation silently discards error messages and stack traces that appear at the end of command output. This causes agents to miss the most actionable part of a failure, leading to blind retries and wasted iterations.

## Competitive Sources

- **mini-swe-agent**: Uses an observation template that keeps both the head and tail of command output, preserving start context alongside error messages at the end. Their 156-line core achieves >74% on SWE-bench, partly attributed to never losing error context during truncation.

## Purpose

When the orchestrator captures output from Claude CLI invocations (or any subcommand), long output is truncated to fit within context limits. The current approach keeps only the first N lines, which discards the tail — exactly where errors, stack traces, test failures, and summary lines appear.

This spec replaces head-only truncation with a head+tail strategy: keep the first N lines for initial context (command echo, early output) and the last M lines for error context (failures, stack traces, exit messages). A clear marker between the two sections tells the agent that content was omitted.

## Requirements

### 1. Full Output Capture

All command output must first be captured in full to a temp file before any truncation is applied. This ensures no data is lost during the truncation decision.

```
command_output=$(mktemp)
claude ... > "$command_output" 2>&1
```

The temp file is used for both truncation and archival (see Requirement 6).

### 2. Line Count Threshold

Count lines in the captured output. If the count exceeds the configurable maximum (`execution.output_max_lines`, default: 200), apply head+tail truncation. If the count is at or below the threshold, pass the output through unmodified.

```
total_lines=$(wc -l < "$command_output")
if [ "$total_lines" -gt "$max_lines" ]; then
    # truncate
fi
```

### 3. Head + Tail Split

When truncation is needed, keep:
- **Head**: first `execution.output_head_lines` lines (default: 50)
- **Tail**: last `execution.output_tail_lines` lines (default: 150)

The defaults weight toward the tail (50 head + 150 tail = 200 total) because error messages, stack traces, test results, and summary lines cluster at the end.

```
head -n "$head_lines" "$command_output"
echo "... [$truncated_count lines truncated] ..."
tail -n "$tail_lines" "$command_output"
```

### 4. Truncation Marker

Insert a single, clearly visible marker line between head and tail sections:

```
... [1437 lines truncated] ...
```

This marker:
- Tells the agent that content was omitted (not that the command produced only 200 lines)
- Shows the exact number of omitted lines so the agent can judge severity
- Uses a format unlikely to be confused with actual command output

### 5. Apply to All Orchestrator-Captured Output

Truncation applies to every output capture point in the orchestrator where Claude CLI output is stored for logging or context injection. This includes:
- Build phase iteration output
- Review phase iteration output
- Research phase iteration output
- Any `run_agent()` or equivalent function that captures CLI stdout/stderr

The truncation function should be a single reusable bash function called at each capture point.

### 6. Full Output Archival

Store the complete untruncated output in `.automaton/logs/` for post-mortem debugging:

```
cp "$command_output" ".automaton/logs/output_${phase}_${iteration}_$(date +%s).log"
```

This ensures that truncation is a display/context optimization only — no information is permanently lost. Log files are plain text and can be inspected with standard tools.

### 7. Configuration

Three new keys under the `execution` section of `automaton.config.json`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `execution.output_max_lines` | integer | 200 | Truncation threshold |
| `execution.output_head_lines` | integer | 50 | Lines to keep from start |
| `execution.output_tail_lines` | integer | 150 | Lines to keep from end |

Validation rules:
- `head_lines + tail_lines` must equal `max_lines` (enforced at config load)
- All values must be positive integers
- If any key is missing, use the default

### 8. Edge Cases

- **Output exactly at threshold**: Do not truncate. Only truncate when `total_lines > max_lines`.
- **Output shorter than tail_lines**: Pass through unmodified (the head+tail would overlap).
- **Empty output**: Pass through as-is. Do not insert a truncation marker for empty output.
- **Binary or non-text output**: `wc -l` handles this gracefully; binary output with few newlines will likely fall under the threshold.

## Acceptance Criteria

- [ ] Output exceeding `max_lines` is truncated to head+tail with marker
- [ ] Output at or below `max_lines` passes through unmodified
- [ ] Truncation marker shows the exact number of omitted lines
- [ ] Full untruncated output is archived in `.automaton/logs/`
- [ ] All three config keys are read from `automaton.config.json` with defaults
- [ ] `head_lines + tail_lines == max_lines` is validated at config load
- [ ] Truncation is applied at every output capture point in the orchestrator
- [ ] Implementation uses only POSIX utilities (`head`, `tail`, `wc`)
- [ ] Total implementation is under 100 lines of bash (including the function and all call sites)
- [ ] Error messages at the end of long output are preserved in the truncated version

## Design Considerations

- **Single bash file**: The truncation function is defined once in `automaton.sh` and called wherever output is captured. No external scripts.
- **Zero dependencies**: Uses only `head`, `tail`, `wc -l`, and `mktemp` — all POSIX standard utilities already available on any system that runs bash.
- **File-based state**: Archived logs go to `.automaton/logs/` as plain text files, consistent with the project's cat-able state philosophy.
- **Simplicity**: The core logic is approximately 15 lines of bash. The function signature is `truncate_output <input_file> <output_variable>` or similar.
- **No performance concern**: `wc -l`, `head`, and `tail` are O(n) single-pass operations on files already in the filesystem buffer. Even for megabyte-scale output, this adds negligible overhead compared to the Claude CLI invocation itself.

## Dependencies

- Depends on: spec-12 (configuration system for reading `execution.*` keys)
- Depends on: spec-09 (error handling — truncated output must still be parseable by error classification)
- Related: spec-21 (observability — log archival complements the observability framework)
- Related: spec-24 (context efficiency — truncation is a form of context size management)

## Files to Modify

- `automaton.sh` — Add `truncate_output()` function; call it at each output capture point in `run_agent()` and phase execution functions
- `automaton.config.json` — Add `execution.output_max_lines`, `execution.output_head_lines`, `execution.output_tail_lines` defaults
