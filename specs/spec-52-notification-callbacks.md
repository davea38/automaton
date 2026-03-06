# Spec 52: Notification Callbacks

## Priority

P2 -- Worth Building. Users walk away during long autonomous runs with no way to
know when they finish or fail. Not P1 because the system functions without them;
this is quality-of-life for unattended operation.

## Competitive Sources

- **oh-my-claudecode** (Notification callbacks) -- Telegram, Discord, and Slack
  webhooks for run completion/failure events.
- **agent-orchestrator** (Notification routing) -- HTTP status updates to
  configured endpoints with event-type filtering.

Both treat notifications as opt-in and fire-and-forget.

## Purpose

Opt-in notification system that POSTs to a webhook URL and/or runs a local shell
command on key orchestration events. Lets users get alerts in Slack, Discord, or
Telegram without watching a terminal. Strictly fire-and-forget: failure never
blocks execution.

## Requirements

### 1. Configuration Schema

Add a `notifications` section to `automaton.config.json`:

```json
{
  "notifications": {
    "webhook_url": "",
    "events": ["run_started", "phase_completed", "run_completed", "run_failed", "escalation"],
    "command": "",
    "timeout_seconds": 5
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| webhook_url | string | `""` | HTTP(S) endpoint for POST payloads. Empty disables webhooks. |
| events | array | all five | Which events trigger notifications. Omit for all. |
| command | string | `""` | Shell command to run on events. Empty disables. |
| timeout_seconds | number | 5 | Max seconds for webhook POST before giving up. |

Both empty (the default) means notifications are completely disabled.

### 2. Supported Events

| Event | Trigger Point |
|-------|---------------|
| `run_started` | After config load and state initialization |
| `phase_completed` | After a phase (research, plan, build, review) exits successfully |
| `run_completed` | After the final phase completes successfully |
| `run_failed` | On unrecoverable error or budget exhaustion |
| `escalation` | When human intervention is needed (spec-44) |

### 3. Webhook Payload

POST with `Content-Type: application/json`:

```json
{
  "event": "phase_completed",
  "project": "my-project",
  "phase": "build",
  "status": "success",
  "message": "Build phase completed in 12m34s (wave 3/3, 8/8 tasks)",
  "timestamp": "2026-03-03T14:22:10Z"
}
```

Fields: `event` (one of five types), `project` (directory basename), `phase`
(current phase or `"all"`), `status` (`"success"`/`"failure"`/`"info"`),
`message` (human-readable summary), `timestamp` (ISO 8601 UTC). Built with
`jq -n --arg` (no string templating).

### 4. Webhook Delivery

- `curl -s -m $timeout -X POST -H "Content-Type: application/json" -d "$payload" "$webhook_url"`
- Background subshell (`&`) with stdout/stderr to `/dev/null`. Never check exit code.
- Log to `session.log`: `[NOTIFY] POST run_completed to hooks.example.com` (hostname only).

### 5. Command Execution

Run the configured command with event details as environment variables:

```bash
AUTOMATON_EVENT="run_completed" \
AUTOMATON_PROJECT="my-project" \
AUTOMATON_PHASE="all" \
AUTOMATON_STATUS="success" \
AUTOMATON_MESSAGE="Run completed successfully" \
$command >/dev/null 2>&1 &
```

Same fire-and-forget semantics as webhook delivery. Use cases: `say "Build
complete"` (macOS), `notify-send "Automaton" "$AUTOMATON_MESSAGE"` (Linux).

### 6. Event Filtering

Only events listed in `notifications.events` trigger notifications. If absent
or empty, all five events fire. Simple membership check against the list.

### 7. Implementation Constraints

- One function: `send_notification "$event" "$phase" "$status" "$message"`.
- Early return if both `NOTIFY_WEBHOOK_URL` and `NOTIFY_COMMAND` are empty.
- Total implementation: 60-80 lines of bash including config loading.
- No retry logic. No delivery guarantees. Fire-and-forget only.

## Acceptance Criteria

- [ ] `notifications.webhook_url` causes a POST on `run_completed`.
- [ ] `notifications.command` causes command execution on `run_completed`.
- [ ] Unreachable webhook URL does not block or fail the run.
- [ ] Failing command does not block or fail the run.
- [ ] Only events in `notifications.events` trigger notifications.
- [ ] Omitting `notifications.events` delivers all five event types.
- [ ] Empty config produces zero notification overhead.
- [ ] Webhook payload is valid JSON with all six fields.
- [ ] Notification attempts are logged to `session.log`.
- [ ] Implementation fits within 80 lines of bash.

## Design Considerations

- **Single bash file**: `send_notification()` lives in `automaton.sh`, called
  at five existing event points in the orchestration loop.
- **Zero dependencies**: Uses `curl` (POSIX-standard) and `jq` (already
  required). No additional binaries.
- **File-based state**: Writes nothing to `.automaton/` except a debug line
  in `session.log`.
- **Non-blocking**: Background subshells ensure the main loop never waits on I/O.
- **Security**: Webhook URLs (which may contain auth tokens) are truncated to
  hostname in log entries.

## Dependencies

- Depends on: spec-12 (configuration schema and `load_config()`)
- Related: spec-09 (`run_failed` event), spec-21 (observability),
  spec-44 (`escalation` event)

## Files to Modify

- `automaton.sh` -- Add `send_notification()` (~60-80 lines), five call sites,
  config loading in `load_config()`.
- `automaton.config.json` -- New `notifications` section (spec-12 extension).
