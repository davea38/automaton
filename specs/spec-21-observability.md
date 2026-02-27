# Spec 21: Observability

## Purpose

Define human-facing visibility into the multi-window parallel system. When multiple builders are running simultaneously, the human needs to see what's happening without attaching to individual windows. This spec covers the dashboard window, enhanced session logging with wave/builder identifiers, tmux window naming and navigation, and progress estimation.

## Dashboard Window

The dashboard is a passive tmux window that displays `.automaton/dashboard.txt` using `watch`:

```bash
# Created by conductor on startup (spec-15)
tmux new-window -t "$session" -n "dashboard" \
    "watch -n2 cat .automaton/dashboard.txt"
```

The conductor writes `.automaton/dashboard.txt` after each significant event (builder spawn, builder completion, wave completion, merge). The dashboard window auto-refreshes every 2 seconds.

### Dashboard Format

```
╔══════════════════════════════════════════════════════════════╗
║  automaton v2.0 — parallel build                            ║
╠══════════════════════════════════════════════════════════════╣
║  Phase: BUILD  │  Wave: 3/~5  │  Budget: $31.40 remaining  ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  Wave 3 Progress                                             ║
║  ──────────────                                              ║
║  builder-1  ██████████████░░░░  running  2m15s  JWT auth     ║
║  builder-2  ████████████████░░  running  1m50s  DB migration ║
║  builder-3  ████████████████████ DONE     3m10s  API errors   ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║  Tasks: 8/15 complete  │  Waves: 3 done, ~2 remaining       ║
║  Tokens: 2.1M used     │  Cost: $18.60 / $50.00             ║
╠══════════════════════════════════════════════════════════════╣
║  Recent Events                                               ║
║  ─────────────                                               ║
║  10:34:56  builder-3 complete (success, 3m10s, ~$1.91)      ║
║  10:33:40  builder-1 spawned → JWT token generation          ║
║  10:33:25  builder-2 spawned → DB migration                  ║
║  10:33:10  builder-3 spawned → API error utils               ║
║  10:33:09  Wave 3 started (3 builders)                       ║
║  10:33:08  Wave 2 complete: 2/2 tasks, merge OK              ║
╚══════════════════════════════════════════════════════════════╝
```

### Dashboard Writer

```bash
write_dashboard() {
    local dash=".automaton/dashboard.txt"
    local tmp="${dash}.tmp"

    # Collect current state
    local phase=$(jq -r '.phase' .automaton/state.json)
    local wave=$(jq -r '.wave_number // 0' .automaton/state.json)
    local remaining_usd=$(get_remaining_budget_usd)
    local total_tasks=$(grep -c '\[ \]\|\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    local completed_tasks=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    local estimated_waves=$(estimate_remaining_waves)

    cat > "$tmp" <<EOF
$(printf '═%.0s' {1..62})
  automaton v2.0 — parallel build
$(printf '═%.0s' {1..62})
  Phase: $(echo "$phase" | tr '[:lower:]' '[:upper:]')  |  Wave: $wave/~$estimated_waves  |  Budget: \$${remaining_usd} remaining
$(printf '═%.0s' {1..62})

  Wave $wave Progress
  $(printf '─%.0s' {1..14})
$(format_builder_status)

$(printf '═%.0s' {1..62})
  Tasks: $completed_tasks/$total_tasks complete  |  Waves: $wave done, ~$((estimated_waves - wave)) remaining
  Tokens: $(format_tokens_used) used  |  Cost: \$$(get_cost_used) / \$$(get_cost_limit)
$(printf '═%.0s' {1..62})
  Recent Events
  $(printf '─%.0s' {1..13})
$(tail -6 .automaton/session.log | tac | sed 's/\[.*\] \[/  /' | sed 's/\] /  /')
$(printf '═%.0s' {1..62})
EOF

    mv "$tmp" "$dash"
}
```

The dashboard is purely informational — it has no side effects and is safe to read at any time.

## Enhanced Session Log

When running in parallel mode, session log entries include wave and builder identifiers:

### Log Format Extension

```
[ISO-8601] [COMPONENT:CONTEXT] MESSAGE
```

New component tags for parallel mode:

| Component Tag | Used By | Example |
|---------------|---------|---------|
| `CONDUCTOR` | Conductor (wave management) | `[CONDUCTOR] Wave 3: starting with 3 builders` |
| `BUILD:W3:B1` | Builder 1 in wave 3 | `[BUILD:W3:B1] Task: Implement JWT auth` |
| `BUILD:W3:B2` | Builder 2 in wave 3 | `[BUILD:W3:B2] Task: Add DB migration` |
| `MERGE:W3` | Merge operations for wave 3 | `[MERGE:W3] builder-1 merged cleanly` |

### Example Parallel Session Log

```
[2026-02-26T10:33:09Z] [CONDUCTOR] Wave 3: starting with 3 builders
[2026-02-26T10:33:10Z] [CONDUCTOR] Wave 3: builder-1 assigned "Implement JWT token generation"
[2026-02-26T10:33:10Z] [BUILD:W3:B1] Spawned in worktree .automaton/worktrees/builder-1
[2026-02-26T10:33:25Z] [CONDUCTOR] Wave 3: builder-2 assigned "Add database migration"
[2026-02-26T10:33:25Z] [BUILD:W3:B2] Spawned in worktree .automaton/worktrees/builder-2
[2026-02-26T10:33:40Z] [CONDUCTOR] Wave 3: builder-3 assigned "Create API error utils"
[2026-02-26T10:33:40Z] [BUILD:W3:B3] Spawned in worktree .automaton/worktrees/builder-3
[2026-02-26T10:34:56Z] [BUILD:W3:B3] Complete: success, 76s, 85K in / 18K out (~$1.91)
[2026-02-26T10:36:05Z] [BUILD:W3:B1] Complete: success, 175s, 112K in / 24K out (~$2.04)
[2026-02-26T10:37:10Z] [BUILD:W3:B2] Complete: success, 225s, 98K in / 21K out (~$1.82)
[2026-02-26T10:37:11Z] [MERGE:W3] Starting merge sequence (3 builders)
[2026-02-26T10:37:12Z] [MERGE:W3] builder-1 merged (tier 1: clean)
[2026-02-26T10:37:13Z] [MERGE:W3] builder-2 merged (tier 1: clean)
[2026-02-26T10:37:14Z] [MERGE:W3] builder-3 merged (tier 2: IMPLEMENTATION_PLAN.md auto-resolved)
[2026-02-26T10:37:15Z] [CONDUCTOR] Wave 3: complete (3/3 merged, 0 conflicts, ~$5.77)
[2026-02-26T10:37:16Z] [CONDUCTOR] Wave 3: verification PASS
```

### Log Filtering

The structured tags enable filtering:

```bash
# All events for wave 3
grep 'W3' .automaton/session.log

# All builder-2 events
grep ':B2' .automaton/session.log

# All merge events
grep 'MERGE' .automaton/session.log

# All conductor decisions
grep 'CONDUCTOR' .automaton/session.log
```

## tmux Window Naming and Navigation

### Window Names

| Window | Name | Content |
|--------|------|---------|
| 0 | `conductor` | automaton.sh (orchestrator) |
| 1 | `builder-1` | Claude agent in worktree (ephemeral) |
| 2 | `builder-2` | Claude agent in worktree (ephemeral) |
| 3 | `builder-3` | Claude agent in worktree (ephemeral) |
| N+1 | `dashboard` | `watch` on dashboard.txt |

### Navigation Shortcuts

When attached to the tmux session:

| Keys | Action |
|------|--------|
| `Ctrl-b 0` | Jump to conductor window |
| `Ctrl-b 1` | Jump to builder-1 (if active) |
| `Ctrl-b 2` | Jump to builder-2 (if active) |
| `Ctrl-b n` | Next window |
| `Ctrl-b p` | Previous window |

### Attaching to Watch Builders

To observe a running builder:

```bash
# From outside tmux
tmux attach -t automaton:builder-1

# From within tmux (another window)
# Ctrl-b 1
```

Builder windows show the live `claude -p` stream-json output. The human can observe what the builder is doing in real-time without interfering.

## Progress Estimation

The dashboard shows estimated remaining waves and completion progress:

```bash
estimate_remaining_waves() {
    local remaining_tasks=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    local max_builders="$MAX_BUILDERS"

    if [ "$remaining_tasks" -eq 0 ]; then
        echo "0"
        return
    fi

    # Estimate: tasks_per_wave ≈ max_builders (optimistic)
    # Add 1 for rounding and re-queued tasks
    local estimated=$((remaining_tasks / max_builders + 1))
    echo "$estimated"
}
```

### Progress Metrics

| Metric | Source | Display |
|--------|--------|---------|
| Tasks complete | `grep -c '\[x\]' IMPLEMENTATION_PLAN.md` | `8/15 complete` |
| Tasks remaining | `grep -c '\[ \]' IMPLEMENTATION_PLAN.md` | `7 remaining` |
| Waves completed | `state.json wave_number` | `3 done` |
| Waves remaining | `remaining_tasks / max_builders + 1` | `~2 remaining` |
| Tokens used | `budget.json used.total_input + used.total_output` | `2.1M used` |
| Cost used / limit | `budget.json used.estimated_cost_usd / limits.max_cost_usd` | `$18.60 / $50.00` |
| Budget remaining | `limits.max_cost_usd - used.estimated_cost_usd` | `$31.40 remaining` |
| Current wave time | `now - wave_start_time` | `2m15s` |

## Stdout Output (Non-tmux)

When `parallel.enabled` is `true` but the user is not in tmux (running in a plain terminal), the conductor still emits one-line summaries to stdout:

```
[WAVE 3/~5] 3 builders | builder-1: JWT auth | builder-2: DB migration | builder-3: API errors
[WAVE 3/~5] builder-3 DONE (76s, ~$1.91) | 2 remaining
[WAVE 3/~5] builder-1 DONE (175s, ~$2.04) | 1 remaining
[WAVE 3/~5] COMPLETE: 3/3 merged | ~$5.77 | budget: $31.40 remaining
```

This is the wave-level equivalent of the per-iteration stdout output from spec-01.

## Wave History in State

The `state.json` wave history (spec-15) provides post-run analysis:

```json
{
  "wave_history": [
    {
      "wave": 1,
      "builders": 3,
      "succeeded": 3,
      "failed": 0,
      "tasks_completed": 3,
      "duration_seconds": 180,
      "tokens_total": 295000,
      "cost_total": 5.77,
      "merge_tier1": 2,
      "merge_tier2": 1,
      "merge_tier3": 0
    }
  ]
}
```

This enables users to evaluate parallelism effectiveness:
- High `merge_tier3` counts → improve file annotations.
- High failure rates → reduce `max_builders`.
- Low builder counts per wave → improve task partitioning.

## Dependencies on Other Specs

- Used by: spec-15-conductor (dashboard updates), spec-16-wave-execution (logging)
- Extends: spec-10-state-management (dashboard.txt, enhanced session.log, wave_history)
- Uses: spec-07-token-tracking (budget display)
- Uses: spec-14-multi-window-architecture (tmux session topology)
