# Spec 08: Rate Limiting

## Purpose

Prevent hitting Anthropic API rate limits by proactively pacing agent invocations. When rate limits are hit, back off exponentially. When running parallel builders, share rate capacity across agents.

## Configuration Defaults

```json
{
  "rate_limits": {
    "tokens_per_minute": 80000,
    "requests_per_minute": 50,
    "cooldown_seconds": 60,
    "backoff_multiplier": 2,
    "max_backoff_seconds": 300
  }
}
```

## Rate Limit Detection

Rate limits are detected reactively from Claude CLI output:

```bash
# After each agent invocation
if [ $exit_code -ne 0 ]; then
    if echo "$result" | grep -qi 'rate_limit\|429\|overloaded\|rate limit'; then
        handle_rate_limit
    fi
fi
```

Detection signals:
1. CLI exit code != 0 AND output contains rate limit indicators
2. Output contains `429` HTTP status code
3. Output contains `overloaded` error message

## Reactive Backoff (On Rate Limit Hit)

```
delay = cooldown_seconds (default 60)
for attempt in 1..5:
    log "[ORCHESTRATOR] Rate limited. Waiting ${delay}s (attempt $attempt/5)"
    sleep $delay
    retry the agent invocation
    if success:
        break
    delay = min(delay * backoff_multiplier, max_backoff_seconds)
```

Maximum 5 retries for rate limit errors (separate from the 3-retry limit for general CLI errors).

After 5 consecutive rate limit failures:
- Save state
- Log: `[ORCHESTRATOR] Persistent rate limiting. Pausing for 10 minutes.`
- Sleep 600 seconds
- Resume

## Proactive Pacing (Inter-Iteration)

After each iteration, the orchestrator checks token velocity:

```bash
# Calculate tokens per minute over last 3 iterations
recent_tokens=$(sum of last 3 iterations' total tokens from budget.json history)
recent_duration=$(sum of last 3 iterations' durations in seconds)
velocity_tpm=$((recent_tokens * 60 / recent_duration))

# If velocity exceeds 80% of limit, insert delay
threshold=$((tokens_per_minute * 80 / 100))
if [ $velocity_tpm -gt $threshold ]; then
    cooldown=$((60 - recent_duration * 60 / recent_tokens))
    log "[ORCHESTRATOR] Proactive rate limiting: waiting ${cooldown}s"
    sleep $cooldown
fi
```

This avoids rate limits by slowing down before hitting them. It only activates when consumption velocity is high (>80% of TPM limit).

## Parallel Agent Rate Sharing

When `execution.parallel_builders` > 1:

```
per_builder_tpm = tokens_per_minute / parallel_builders
```

| Builders | TPM per builder (at 80K total) |
|----------|-------------------------------|
| 1 | 80,000 |
| 2 | 40,000 |
| 3 | 26,667 |
| 4 | 20,000 |

The orchestrator staggers parallel builder start times:
```
stagger_delay = 60 / parallel_builders  # seconds between starts
```

For 2 builders: start builder-2 30 seconds after builder-1.
For 3 builders: 20-second stagger.

This distributes API load across the minute window.

## Rate Limit vs General Error

The orchestrator distinguishes rate limits from other errors:

| Signal | Classification | Handler |
|--------|---------------|---------|
| Exit != 0, output has `429` | Rate limit | Exponential backoff, 5 retries |
| Exit != 0, output has `rate_limit` | Rate limit | Exponential backoff, 5 retries |
| Exit != 0, output has `overloaded` | Rate limit | Exponential backoff, 5 retries |
| Exit != 0, no rate limit signal | General error | Retry with delay, 3 retries |
| Exit == 0 | Success | Continue |

## Logging

All rate limit events are logged:
```
[2026-02-26T10:30:00Z] [ORCHESTRATOR] Rate limit detected. Backing off 60s (attempt 1/5)
[2026-02-26T10:31:00Z] [ORCHESTRATOR] Rate limit retry succeeded.
[2026-02-26T10:32:00Z] [ORCHESTRATOR] Proactive pacing: velocity 72K TPM, waiting 8s.
```
