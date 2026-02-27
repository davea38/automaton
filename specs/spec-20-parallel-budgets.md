# Spec 20: Parallel Budgets

## Purpose

Define how rate limiting and budget enforcement work across N concurrent builder windows. In v1, a single builder consumes the full TPM/RPM allocation. In v2, N builders must share the allocation without triggering rate limits. This spec covers per-builder TPM/RPM allocation, staggered start timing, shared rate state, per-wave budget checkpoints, rate-limit-triggered pauses, and budget exhaustion mid-wave.

## Per-Builder Rate Allocation

When `parallel.enabled` is `true`, the conductor divides rate capacity across active builders:

```
per_builder_tpm = tokens_per_minute / active_builder_count
per_builder_rpm = requests_per_minute / active_builder_count
```

| Builders | TPM per builder (at 80K total) | RPM per builder (at 50 total) |
|----------|-------------------------------|-------------------------------|
| 1 | 80,000 | 50 |
| 2 | 40,000 | 25 |
| 3 | 26,667 | 16 |
| 4 | 20,000 | 12 |

This is a conservative allocation — it assumes worst-case simultaneous consumption. In practice, builders' token usage is bursty (heavy at start, light during code generation), so actual utilization will be lower than the limit.

## Staggered Start Timing

Builders are spawned with a configurable delay between them to avoid burst spikes:

```
stagger_delay = parallel.stagger_seconds (default: 15)
```

| Builders | Stagger (at 15s) | Total spawn time |
|----------|-----------------|------------------|
| 2 | 15s | 15s |
| 3 | 15s | 30s |
| 4 | 15s | 45s |

The conductor spawns builder-1 immediately, waits `stagger_seconds`, spawns builder-2, waits again, etc.

```bash
spawn_builders_staggered() {
    local wave=$1
    local builder_count=$2
    local stagger="$PARALLEL_STAGGER_SECONDS"

    for i in $(seq 1 "$builder_count"); do
        spawn_single_builder "$wave" "$i"
        log "CONDUCTOR" "Wave $wave: spawned builder-$i"

        if [ "$i" -lt "$builder_count" ]; then
            log "CONDUCTOR" "Wave $wave: stagger delay ${stagger}s before next builder"
            sleep "$stagger"
        fi
    done
}
```

The stagger serves two purposes:
1. **Distributes API load** — prevents N simultaneous large prompt submissions.
2. **Spreads token consumption** — each builder's first request hits the API at different times within the minute window.

## Shared Rate State File

The conductor maintains a shared rate state file that tracks aggregate consumption:

### `.automaton/rate.json`

```json
{
  "window_start": "2026-02-26T10:30:00Z",
  "window_tokens": 45000,
  "window_requests": 12,
  "builders_active": 3,
  "last_rate_limit": null,
  "backoff_until": null,
  "history": [
    {
      "timestamp": "2026-02-26T10:30:15Z",
      "builder": 1,
      "tokens": 15000,
      "requests": 4
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| window_start | ISO 8601 | Start of current 60-second rate window |
| window_tokens | number | Total tokens consumed in current window (all builders) |
| window_requests | number | Total requests in current window (all builders) |
| builders_active | number | Number of currently running builders |
| last_rate_limit | ISO 8601/null | When the last 429 was received |
| backoff_until | ISO 8601/null | Don't start new requests until this time |
| history | array | Per-builder consumption entries in current window |

The conductor updates this file after collecting each builder's result. Builders do not write to this file — they report consumption via their result files, and the conductor aggregates.

## Per-Wave Budget Checkpoints

Before each wave, the conductor checks whether the budget can sustain N builders:

```bash
check_wave_budget() {
    local builder_count=$1

    # Read current budget state
    local remaining_tokens=$(get_remaining_budget_tokens)
    local remaining_cost=$(get_remaining_budget_usd)
    local estimated_tokens_per_builder=$BUDGET_PER_ITERATION
    local estimated_cost_per_builder=$(estimate_iteration_cost "$MODEL_BUILDING" "$estimated_tokens_per_builder")

    local wave_tokens=$((builder_count * estimated_tokens_per_builder))
    local wave_cost=$(echo "$builder_count * $estimated_cost_per_builder" | bc)

    # Check token budget
    if [ "$wave_tokens" -gt "$remaining_tokens" ]; then
        local affordable=$((remaining_tokens / estimated_tokens_per_builder))
        if [ "$affordable" -ge 2 ]; then
            log "CONDUCTOR" "Budget: reducing wave to $affordable builders (token limit)"
            echo "$affordable"
            return 0
        fi
        if [ "$affordable" -ge 1 ]; then
            log "CONDUCTOR" "Budget: single-builder only (token limit)"
            echo "1"
            return 0
        fi
        log "CONDUCTOR" "Budget: insufficient for any builder"
        return 1
    fi

    # Check cost budget
    local remaining_usd=$(get_remaining_budget_usd)
    if [ "$(echo "$wave_cost > $remaining_usd" | bc)" -eq 1 ]; then
        local affordable=$(echo "$remaining_usd / $estimated_cost_per_builder" | bc)
        if [ "$affordable" -ge 2 ]; then
            log "CONDUCTOR" "Budget: reducing wave to $affordable builders (cost limit)"
            echo "$affordable"
            return 0
        fi
        if [ "$affordable" -ge 1 ]; then
            echo "1"
            return 0
        fi
        return 1
    fi

    echo "$builder_count"
    return 0
}
```

## Rate Limit Handling During Waves

When a builder hits a 429 rate limit, the response differs from v1 because other builders may still be running.

### Detection

Builders report rate limits via their result file (`"status": "rate_limited"`). The conductor detects this during result collection.

### Response: Pause All Builders

When any builder reports a rate limit:

```bash
handle_wave_rate_limit() {
    local wave=$1
    local builder=$2
    local session="$TMUX_SESSION_NAME"

    log "CONDUCTOR" "Wave $wave: builder-$builder hit rate limit. Pausing all builders."

    # Signal all running builders to pause
    # (Builders can't be paused mid-execution, so this affects the next wave)
    local backoff="$RATE_COOLDOWN_SECONDS"
    local backoff_until=$(date -u -d "+${backoff} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

    # Update rate state
    jq --arg until "$backoff_until" '.backoff_until = $until | .last_rate_limit = (now | todate)' \
        ".automaton/rate.json" > ".automaton/rate.json.tmp"
    mv ".automaton/rate.json.tmp" ".automaton/rate.json"

    # Wait for the backoff period
    log "CONDUCTOR" "Rate limit backoff: waiting ${backoff}s"
    sleep "$backoff"

    # Clear backoff
    jq '.backoff_until = null' ".automaton/rate.json" > ".automaton/rate.json.tmp"
    mv ".automaton/rate.json.tmp" ".automaton/rate.json"
}
```

Since builders are already running when a rate limit is detected (via result files), the pause affects the **next wave**. Running builders continue — they've already consumed their tokens. The conductor delays the next wave by the backoff period.

### Escalation

If rate limits persist across 3 consecutive waves:

1. Reduce `max_builders` by 1 for subsequent waves.
2. If already at 1 builder and still hitting limits, use the v1 backoff from spec-08 (exponential, up to 5 retries).
3. If persistent, 10-minute pause per spec-08.

## Budget Exhaustion Mid-Wave

If the budget is exhausted while builders are running:

```bash
handle_midwave_budget_exhaustion() {
    local wave=$1

    log "CONDUCTOR" "Wave $wave: budget exhaustion detected mid-wave"

    # Do NOT kill running builders — they've already consumed tokens
    # Let them finish their current work

    # After all builders complete, collect and merge their results
    # (same as normal wave completion)

    # Then stop — don't start another wave
    log "CONDUCTOR" "Budget exhausted. Saving state for resume."
    save_state
    cleanup_wave "$wave"
    exit 2
}
```

The key principle: never waste work. If tokens are already spent, collect the results.

## Proactive Pacing for Waves

Between waves, the conductor checks aggregate velocity:

```bash
check_wave_pacing() {
    # Sum tokens from all builders in the last wave
    local wave_tokens=$(jq '[.history[-1].tokens] | add // 0' ".automaton/rate.json")
    local wave_duration=$(jq '.history[-1].duration_seconds // 60' ".automaton/rate.json")

    # Calculate aggregate TPM
    local velocity=$((wave_tokens * 60 / wave_duration))
    local threshold=$((RATE_TOKENS_PER_MINUTE * 80 / 100))

    if [ "$velocity" -gt "$threshold" ]; then
        local cooldown=$((60 - wave_duration))
        if [ "$cooldown" -gt 0 ]; then
            log "CONDUCTOR" "Proactive pacing: aggregate velocity ${velocity} TPM, waiting ${cooldown}s"
            sleep "$cooldown"
        fi
    fi
}
```

This is the wave-level equivalent of the per-iteration pacing in spec-08. It runs between waves, not between individual builders.

## Budget Tracking Across Builders

After each wave, the conductor aggregates token usage from all builder results into `budget.json`:

```bash
aggregate_wave_budget() {
    local wave=$1
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")

    for i in $(seq 1 "$builder_count"); do
        local result=".automaton/wave/results/builder-${i}.json"
        if [ ! -f "$result" ]; then continue; fi

        local input=$(jq '.tokens.input // 0' "$result")
        local output=$(jq '.tokens.output // 0' "$result")
        local cache_create=$(jq '.tokens.cache_create // 0' "$result")
        local cache_read=$(jq '.tokens.cache_read // 0' "$result")
        local cost=$(jq '.estimated_cost // 0' "$result")

        # Update budget.json
        update_budget "$input" "$output" "$cache_create" "$cache_read" "$cost" "build"

        # Write agent history file
        local iteration=$(jq '.iteration' .automaton/state.json)
        cp "$result" ".automaton/agents/build-$(printf '%03d' $iteration)-builder-${i}.json"
    done
}
```

Each builder's tokens are tracked individually in the history, but count against the shared phase and total budgets.

## Configuration

Rate limit settings use existing config keys from spec-12, plus new parallel-specific keys:

| Key | Default | Description |
|-----|---------|-------------|
| `rate_limits.tokens_per_minute` | 80000 | Total TPM shared across all builders |
| `rate_limits.requests_per_minute` | 50 | Total RPM shared across all builders |
| `parallel.stagger_seconds` | 15 | Delay between spawning builders |
| `rate_limits.cooldown_seconds` | 60 | Backoff on rate limit |

No new rate limit config keys are needed — the conductor divides the existing allocations.

## Dependencies on Other Specs

- Extends: spec-07-token-tracking (aggregate budget tracking across builders)
- Extends: spec-08-rate-limiting (per-builder allocation, wave-level pacing)
- Used by: spec-15-conductor (budget checkpoints), spec-16-wave-execution (budget checks)
- Extends: spec-10-state-management (new `.automaton/rate.json` file)
- Uses: spec-12-configuration (rate limit settings)
