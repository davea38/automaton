# Spec 23: Weekly Allowance Budget Model

## Purpose

The current budget system tracks USD costs against API pricing tiers. Max subscription provides a flat weekly token allowance with no per-call cost. The system needs a dual-mode budget: `"api"` (existing behavior, default) and `"allowance"` (weekly token tracking for Max subscription users).

## Requirements

### 1. `budget.mode` Config Field

Two values: `"api"` (default, current behavior unchanged) and `"allowance"` (weekly token tracking).

### 2. Allowance Config

When mode is `"allowance"`:
```json
"budget": {
  "mode": "allowance",
  "weekly_allowance_tokens": 45000000,
  "allowance_reset_day": "monday",
  "reserve_percentage": 20
}
```
Effective budget = `weekly_allowance_tokens * (1 - reserve_percentage/100)`.

### 3. Allowance Tracking in budget.json

Tracks `week_start`, `week_end`, `total_allowance`, `effective_allowance`, `tokens_used_this_week`, `tokens_remaining`.

### 4. Allowance Enforcement

Replace the four USD-based rules in `check_budget()` with token equivalents in allowance mode:
- Pre-iteration: estimate if enough remains, warn/pause if not
- Post-iteration: update `tokens_used_this_week`, exit 2 if exceeded
- Phase proportioning: allocate percentages (research 5%, plan 10%, build 70%, review 15%) as soft limits for phase transitions

### 5. Week Rollover on `--resume`

If current date is past `week_end`, reset weekly counters. Archive previous week to `allowance_history` array.

### 6. Backward Compatibility

`"api"` mode default. `estimate_cost()` still runs in allowance mode for informational logging. All existing API-mode behavior preserved.

## Acceptance Criteria

- [ ] `budget.mode: "allowance"` switches enforcement logic to token-based
- [ ] Weekly allowance correctly tracks remaining tokens
- [ ] Phase transitions triggered by proportional token limits
- [ ] `--resume` across week boundary resets counters
- [ ] `estimate_cost()` still produces informational data in allowance mode
- [ ] Exhausted weekly budget → exit 2 with reset date displayed
- [ ] `budget.mode: "api"` behavior completely unchanged

## Dependencies

- Depends on: none
- Depended on by: spec-24, spec-26

## Files to Modify

- `automaton.sh` — `load_config()`, `initialize_budget()`, `estimate_cost()`, `update_budget()`, `check_budget()`, `emit_status_line()`, `print_banner()`
- `automaton.config.json` — add allowance fields
- `specs/spec-07-token-tracking.md` — update to document dual-mode
