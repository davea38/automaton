# Spec 35: Max Plan Optimization

## Purpose

Spec-23 defines dual budget mode (API vs. allowance) but does not address Max Plan economics: zero token cost within the allowance, different rate limits, ability to afford more parallelism, need for allowance pacing across the week, and multi-project partitioning. This spec defines Max Plan-specific optimizations that leverage the flat-rate subscription model.

## Requirements

### 1. Max Plan Rate Limit Presets

Max Plan subscribers have higher rate limits than API-tier users. Define presets that the orchestrator uses when `budget.mode` is `"allowance"`:

```json
{
  "rate_limits_presets": {
    "api_default": {
      "tokens_per_minute": 80000,
      "requests_per_minute": 50,
      "cooldown_seconds": 60,
      "backoff_multiplier": 2,
      "max_backoff_seconds": 300
    },
    "max_plan": {
      "tokens_per_minute": 200000,
      "requests_per_minute": 100,
      "cooldown_seconds": 30,
      "backoff_multiplier": 1.5,
      "max_backoff_seconds": 120
    }
  }
}
```

When `budget.mode` is `"allowance"`, automatically apply `max_plan` rate limit presets unless the user has explicitly overridden `rate_limits` in config.

### 2. Allowance Pacing

Max Plan allowance resets weekly. Without pacing, a single large automaton run on Monday could exhaust the entire week's allowance. Define a daily budget calculation:

```
daily_budget = remaining_allowance_tokens / days_until_reset
```

Where:
- `remaining_allowance_tokens` = `weekly_allowance_tokens - tokens_used_this_week`
- `days_until_reset` = days remaining until `allowance_reset_day` (minimum 1)

The orchestrator uses `daily_budget` as the run-level token ceiling:
- Before starting a run: check if `daily_budget` is sufficient (at least 500K tokens)
- If insufficient: warn and suggest deferring: `[ORCHESTRATOR] WARNING: Daily budget is 320K tokens (allowance resets in 4 days). Run may be cut short. Proceed? [y/N]`
- During a run: enforce `daily_budget` as the hard token limit (replacing `max_total_tokens` from API mode)

### 3. Budget Check CLI Command

Add `--budget-check` CLI flag that shows weekly allowance status without starting a run:

```bash
./automaton.sh --budget-check
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Automaton Weekly Budget Status
 Week:       Feb 24 — Mar 02, 2026
 Allowance:  45,000,000 tokens
 Used:       12,400,000 tokens (27.6%)
 Remaining:  32,600,000 tokens
 Reserve:    9,000,000 tokens (20%)
 Available:  23,600,000 tokens
 Days left:  3
 Daily pace: 7,866,667 tokens/day
 Recommended run budget: 5,000,000 tokens
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

`Recommended run budget` = min(daily_budget, available_tokens * 0.5) — reserves half for potential re-runs or other work.

### 4. Higher Parallel Defaults for Max Plan

Max Plan users can afford more parallelism since there is no per-token cost within the allowance. Define higher defaults when in allowance mode:

| Setting | API Default | Max Plan Default |
|---------|------------|-----------------|
| `parallel.max_builders` | 3 | 5 |
| `parallel.stagger_seconds` | 15 | 5 |
| `execution.max_iterations.build` | 0 (unlimited) | 0 (unlimited) |
| `execution.max_iterations.research` | 3 | 5 |

These defaults are applied automatically when `budget.mode` is `"allowance"` unless the user has explicitly set the values in their config.

### 5. Multi-Project Allowance Tracking

Max Plan users may run automaton on multiple projects sharing the same weekly allowance. Track cross-project usage in a user-level file:

```
~/.automaton/allowance.json
```

```json
{
  "weekly_allowance_tokens": 45000000,
  "allowance_reset_day": "monday",
  "current_week": {
    "week_start": "2026-02-24",
    "week_end": "2026-03-02",
    "projects": {
      "/home/user/project-a": {
        "tokens_used": 8400000,
        "runs": 2,
        "last_run": "2026-02-28T14:30:00Z"
      },
      "/home/user/project-b": {
        "tokens_used": 4000000,
        "runs": 1,
        "last_run": "2026-02-27T09:00:00Z"
      }
    },
    "total_used": 12400000
  },
  "history": []
}
```

The orchestrator:
- Reads `~/.automaton/allowance.json` at startup
- Updates it after each iteration with current project's usage
- Uses `total_used` (across all projects) for pacing calculations
- Archives `current_week` to `history` on week rollover

### 6. Max Plan Config Preset

Add a config shortcut for Max Plan users that applies all recommended settings at once:

```json
{
  "max_plan_preset": true
}
```

When `max_plan_preset` is `true`, automatically apply:
- `budget.mode`: `"allowance"`
- `models.research`: `"opus"` (can afford Opus for all phases)
- `models.building`: `"opus"`
- `parallel.max_builders`: 5
- `parallel.stagger_seconds`: 5
- Rate limits: `max_plan` preset

Individual config overrides still take precedence. The preset is a convenience that sets sensible defaults for Max Plan subscribers who want maximum capability.

### 7. Weekly Summary on Resume

When resuming after a week boundary (current date is past `week_end`), display a weekly summary before starting:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Weekly Summary: Feb 24 — Mar 02, 2026
 Total tokens used:  34,200,000 / 45,000,000 (76%)
 Runs:               5 across 2 projects
 Tasks completed:    23
 Estimated savings:  $85.50 vs API pricing
 New week started:   Mar 03 — Mar 09, 2026
 Fresh allowance:    45,000,000 tokens
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The "estimated savings" compares what the tokens would have cost at API rates versus the Max Plan flat rate, reinforcing the value of the subscription.

### 8. Allowance Exhaustion Behavior

When the weekly allowance is exhausted mid-run:

1. Complete the current iteration (do not interrupt mid-agent)
2. Save state for resume
3. Display: `[ORCHESTRATOR] Weekly allowance exhausted. Resets on [day]. Run --resume after reset.`
4. Exit code 2 (same as budget exhaustion in API mode)

Unlike API mode, there is no fallback to paying per-token. The orchestrator does not offer to continue at API rates — that would require billing configuration changes outside automaton's scope.

### 9. Opus-Everywhere Strategy

Max Plan removes the cost incentive to use cheaper models. Document the trade-offs:

| Strategy | Config | Benefit | Risk |
|----------|--------|---------|------|
| Opus everywhere | `max_plan_preset: true` | Best quality for all phases | Faster allowance consumption, higher rate limit pressure |
| Opus critical only | Default (opus for plan/review, sonnet for research/build) | Balanced consumption | Research may miss nuance, build may need more iterations |
| Sonnet everywhere | All models to sonnet | Maximum token efficiency | Lower quality per iteration, more iterations needed |

The preset uses Opus everywhere. Users who find their allowance depleting too fast can selectively downgrade research or build to Sonnet.

## Acceptance Criteria

- [ ] Max Plan rate limit presets applied automatically in allowance mode
- [ ] Daily budget pacing calculated from remaining allowance and days until reset
- [ ] `--budget-check` displays weekly allowance status without starting a run
- [ ] Parallel defaults higher (5 builders, 5s stagger) when in allowance mode
- [ ] `~/.automaton/allowance.json` tracks cross-project usage
- [ ] `max_plan_preset: true` config shortcut applies all Max Plan defaults
- [ ] Weekly summary displayed on resume after week boundary
- [ ] Allowance exhaustion exits gracefully with resume date

## Dependencies

- Extends: spec-23 (allowance mode pacing, multi-project tracking)
- Extends: spec-08 (rate limit presets)
- Extends: spec-12 (config preset, new parallel defaults)
- Extends: spec-20 (parallel budget allocation for higher builder counts)
- Uses: spec-07 (token tracking for allowance consumption)

## Files to Modify

- `automaton.sh` — `load_config()` for preset expansion, `check_budget()` for daily pacing, `--budget-check` CLI handler, weekly summary on resume
- `automaton.config.json` — add `max_plan_preset`, document Max Plan defaults
- `~/.automaton/allowance.json` — new file: cross-project allowance tracking
- `specs/spec-23-weekly-allowance-budget.md` — update to reference pacing and multi-project
