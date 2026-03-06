# Spec 55: Structured Work Logs (JSONL)

## Priority

P3 (When P0-P2 are Battle-Tested). The current `session.log` works for human debugging but cannot be queried, aggregated, or fed into dashboards. Structured logs unlock automated analysis and cross-run comparisons without replacing anything — this is purely additive.

## Competitive Sources

- **sparc**: Structured work logs — machine-readable execution logs that can be replayed, audited, or analyzed after the fact.
- **gastown**: "Capability ledger" — structured log of all agent actions and outcomes, used for capability tracking over time.
- **claude-code-by-agents**: JSONL history — append-only structured log format enabling post-hoc analysis of multi-agent runs.

## Purpose

Write a JSONL (JSON Lines) structured log alongside the existing human-readable `session.log`. Each line is one self-contained JSON object representing a discrete orchestrator event. The file is append-only, queryable with `jq` and `grep`, and imposes no measurable overhead on execution. The human-readable log remains unchanged.

## Requirements

### 1. Log File Location and Naming

Each orchestrator run produces a new file at `.automaton/work-log-{run-id}.jsonl` where `run-id` matches the timestamp format used by run summaries (e.g., `work-log-2026-03-03T14-30-00Z.jsonl`). A symlink `.automaton/work-log.jsonl` always points to the latest run's file. The symlink is updated atomically at run start.

### 2. Event Schema

Every line is a single JSON object with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | string | yes | ISO 8601 timestamp with timezone (`2026-03-03T14:30:00Z`) |
| `event` | enum | yes | One of the defined event types (see below) |
| `phase` | string | yes | Current phase (`converse`, `research`, `plan`, `build`, `review`) or `orchestrator` for system-level events |
| `iteration` | number | no | Current iteration number within the phase (null for orchestrator events) |
| `elapsed_s` | number | yes | Seconds elapsed since run start |
| `tokens` | object | no | Token counts: `{ "input": N, "output": N, "cache_read": N }` |
| `details` | object | no | Event-specific payload (varies by event type) |

### 3. Event Types

Nine event types covering the full orchestrator lifecycle:

| Event Type | When Emitted | Details Payload |
|------------|-------------|-----------------|
| `phase_start` | Phase begins | `{ "phase_config": {} }` |
| `phase_end` | Phase completes | `{ "exit_code": 0, "iterations": N }` |
| `iteration_start` | Iteration begins within a phase | `{ "task": "description" }` |
| `iteration_end` | Iteration completes | `{ "exit_code": 0, "files_changed": N }` |
| `error` | Recoverable or fatal error | `{ "message": "...", "fatal": bool }` |
| `gate_check` | Quality gate evaluated | `{ "gate": "name", "passed": bool, "reason": "..." }` |
| `budget_update` | Token or cost budget changes | `{ "tokens_used": N, "budget_remaining": N, "cost_usd": N }` |
| `escalation` | Issue escalated to user or higher model | `{ "reason": "...", "target": "user" }` |
| `completion` | Run finishes (success or failure) | `{ "status": "success", "total_iterations": N, "total_tokens": N }` |

### 4. Log Verbosity Levels

A `--log-level` flag controls which events are written to the JSONL file:

| Level | Events Included | Use Case |
|-------|----------------|----------|
| `minimal` | `phase_start`, `phase_end`, `completion`, `error` (fatal only) | Lightweight audit trail |
| `normal` | All of `minimal` plus `iteration_start`, `iteration_end`, `escalation` | Default — good balance of signal and size |
| `verbose` | All events including `gate_check` and `budget_update` | Debugging and detailed analysis |

Default is `normal`. The level is stored in `automaton.config.json` under `log_level` and can be overridden per-run via the CLI flag.

### 5. Write Mechanics

Each event is written as a single `echo '{"ts":"...","event":"..."}' >> "$WORK_LOG"` call. No buffering, no batching. Append-only writes to a local file are effectively free — this must not add measurable latency to any pipeline stage.

The emitting function is a single `emit_event()` bash function that accepts the event type and a details JSON string, fills in `ts`, `phase`, `iteration`, and `elapsed_s` automatically from orchestrator state, and appends one line.

### 6. Configuration

New section in `automaton.config.json`:

```json
{
  "work_log": {
    "enabled": true,
    "log_level": "normal"
  }
}
```

When `enabled` is `false`, no JSONL file is created and `emit_event()` is a no-op. This ensures zero overhead when the feature is not wanted.

### 7. Queryability

The format is designed for standard tool access:

```bash
# All errors from the latest run
jq 'select(.event == "error")' .automaton/work-log.jsonl

# Phase durations
jq 'select(.event == "phase_end") | {phase, elapsed_s}' .automaton/work-log.jsonl

# Total tokens consumed
jq 'select(.event == "completion") | .details.total_tokens' .automaton/work-log.jsonl

# Gate failures
jq 'select(.event == "gate_check" and .details.passed == false)' .automaton/work-log.jsonl
```

No custom tooling is needed. Any developer with `jq` can extract insights.

### 8. Rotation and Cleanup

Each run writes to its own file (`work-log-{run-id}.jsonl`). The symlink `work-log.jsonl` always points to the current or most recent run. Old log files are not automatically deleted — they are small (typically <100KB per run) and can be cleaned manually or by a future retention policy. Log files are ephemeral state (gitignored) per spec-34.

## Acceptance Criteria

- [ ] `emit_event()` function writes one JSON line per call to the JSONL log file.
- [ ] All nine event types are emitted at the correct points in the orchestrator lifecycle.
- [ ] Each JSON line is valid JSON and parseable by `jq` independently.
- [ ] `--log-level minimal|normal|verbose` controls which events are written.
- [ ] Default log level is `normal` (configurable in `automaton.config.json`).
- [ ] New file created per run with `work-log-{run-id}.jsonl` naming.
- [ ] Symlink `work-log.jsonl` points to the latest run's log file.
- [ ] Existing `session.log` is completely unchanged.
- [ ] `enabled: false` in config makes `emit_event()` a no-op with zero overhead.
- [ ] Feature is implementable in under 100 lines of bash within `automaton.sh`.

## Design Considerations

The `emit_event()` function is the only new function required. It reads current phase and iteration from `state.json` (already loaded into shell variables by the orchestrator), computes `elapsed_s` from `$RUN_START_TIME`, constructs a JSON string using bash variable interpolation (no `jq` needed for writes — only for reads), and appends to the log file. The log level check is a simple string comparison at the top of the function.

All nine call sites are single-line insertions at existing orchestrator control points (phase transitions, iteration boundaries, error handlers, gate checks). No restructuring of existing code is needed.

The JSONL format was chosen over a single JSON array because append-only writes never require reading or parsing the existing file. A crashed run produces a valid (if truncated) log — every line already written is independently valid.

## Dependencies

- **Depends on: spec-10 (state management)** — reads current phase and iteration from orchestrator state variables.
- **Depends on: spec-07 (token tracking)** — token counts in `budget_update` and `completion` events come from the token tracking subsystem.
- **Related: spec-34 (structured state via git)** — work log files are ephemeral state (gitignored), not persistent. Cross-run analysis uses `run-summaries/` from spec-34.
- **Related: spec-21 (observability)** — structured logs complement the dashboard; the dashboard could consume JSONL events in a future enhancement.

## Files to Modify

- `automaton.sh` — Add `emit_event()` function (~25 lines), add nine call sites at existing control points (~1 line each), add `--log-level` flag parsing (~5 lines), add symlink setup in `initialize_run()` (~5 lines).
- `automaton.config.json` — Add `work_log` section with `enabled` and `log_level` fields.
- `.automaton/work-log-{run-id}.jsonl` — New ephemeral file created per run.
- `.automaton/work-log.jsonl` — Symlink to latest run's log file.
