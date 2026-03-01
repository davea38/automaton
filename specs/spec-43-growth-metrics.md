# Spec 43: Growth Metrics

## Purpose

Spec-26 tracks per-run performance (tokens/task, stall rate, first-pass success). But a self-evolving system needs deeper self-awareness — not just "how did this run go?" but "how is the organism growing over time?" This spec introduces 5 metric categories that together create a quantitative self-portrait: capability (what can it do?), efficiency (how well does it do it?), quality (how reliably?), innovation (how actively is it evolving?), and health (is the system stable?). Metrics are snapshotted each evolution cycle, enabling trend analysis that drives the REFLECT phase (spec-41) and feeds the garden's auto-seeding (spec-38). A `--health` CLI dashboard provides human-readable system status at a glance.

## Requirements

### 1. Metrics Storage

Metrics snapshots are stored in `.automaton/evolution-metrics.json`:

```json
{
  "version": 1,
  "snapshots": [
    {
      "cycle_id": 5,
      "timestamp": "2026-03-02T14:30:00Z",
      "capability": {
        "total_lines": 8610,
        "total_functions": 142,
        "total_specs": 37,
        "total_tests": 28,
        "test_assertions": 156,
        "cli_flags": 8,
        "agent_definitions": 3,
        "skills": 0,
        "hooks": 1
      },
      "efficiency": {
        "tokens_per_task": 45000,
        "tokens_per_iteration": 120000,
        "cache_hit_ratio": 0.68,
        "stall_rate": 0.12,
        "prompt_overhead_ratio": 0.48,
        "bootstrap_time_ms": 380,
        "avg_iteration_duration_s": 45
      },
      "quality": {
        "test_pass_rate": 0.96,
        "first_pass_success_rate": 0.80,
        "rollback_count": 0,
        "syntax_errors_caught": 1,
        "review_rework_rate": 0.15,
        "constitution_violations": 0
      },
      "innovation": {
        "garden_seeds": 4,
        "garden_sprouts": 3,
        "garden_blooms": 2,
        "garden_harvested": 2,
        "garden_wilted": 1,
        "active_signals": 5,
        "quorum_votes_cast": 3,
        "ideas_implemented_total": 2,
        "cycles_since_last_harvest": 0
      },
      "health": {
        "budget_utilization": 0.65,
        "weekly_allowance_remaining": 0.42,
        "convergence_risk": "low",
        "circuit_breaker_trips": 0,
        "consecutive_no_improvement": 0,
        "error_rate": 0.02,
        "self_modification_count": 5
      }
    }
  ],
  "baselines": {
    "capability": { "total_lines": 8610, "total_functions": 142, "total_specs": 37, "total_tests": 28 },
    "efficiency": { "tokens_per_task": 50000, "stall_rate": 0.15 },
    "quality": { "test_pass_rate": 0.93, "rollback_count": 0 }
  }
}
```

### 2. Metric Categories

#### 2.1 Capability Metrics

Measures what automaton can do — its size and surface area:

| Metric | Source | How Computed |
|--------|--------|-------------|
| `total_lines` | `automaton.sh` | `wc -l automaton.sh` |
| `total_functions` | `automaton.sh` | `grep -c '^[a-z_]*()' automaton.sh` |
| `total_specs` | `specs/` | `ls specs/spec-*.md \| wc -l` |
| `total_tests` | test files | `grep -r -c 'assert_' tests/ \| wc -l` (test files count) |
| `test_assertions` | test files | `grep -r -c 'assert_' tests/` (total assertions) |
| `cli_flags` | `automaton.sh` | Count of `--` flags in argument parser |
| `agent_definitions` | `.claude/agents/` | `ls .claude/agents/*.md \| wc -l` |
| `skills` | `.claude/skills/` | `ls .claude/skills/*.md \| wc -l` |
| `hooks` | `.claude/hooks/` | `ls .claude/hooks/*.sh \| wc -l` |

#### 2.2 Efficiency Metrics

Measures how well automaton uses its resources:

| Metric | Source | How Computed |
|--------|--------|-------------|
| `tokens_per_task` | `run_metadata.json` (spec-26) | Total tokens / completed tasks |
| `tokens_per_iteration` | `run_metadata.json` | Total tokens / total iterations |
| `cache_hit_ratio` | `budget.json` | cache_read_tokens / total_input_tokens |
| `stall_rate` | `state.json` | stall_count / total_build_iterations |
| `prompt_overhead_ratio` | `run_metadata.json` | prompt_tokens / total_input_tokens |
| `bootstrap_time_ms` | `init.sh` timing | Measured during bootstrap execution |
| `avg_iteration_duration_s` | `session.log` | Average time between iteration start/end markers |

#### 2.3 Quality Metrics

Measures reliability and correctness:

| Metric | Source | How Computed |
|--------|--------|-------------|
| `test_pass_rate` | `test_results.json` | passed / (passed + failed) |
| `first_pass_success_rate` | `run_metadata.json` (spec-26) | Tasks done without rework / total tasks |
| `rollback_count` | `self_modifications.json` | Count of rollback entries in current cycle |
| `syntax_errors_caught` | `self_modifications.json` | Count of syntax check failures |
| `review_rework_rate` | `run_metadata.json` | Review-flagged tasks / total tasks |
| `constitution_violations` | Vote records | Count of compliance check failures |

#### 2.4 Innovation Metrics

Measures how actively the system is evolving:

| Metric | Source | How Computed |
|--------|--------|-------------|
| `garden_seeds` through `garden_wilted` | `_index.json` (spec-38) | Counts from garden index |
| `active_signals` | `signals.json` (spec-42) | Count of signals above decay floor |
| `quorum_votes_cast` | `.automaton/votes/` | Count of vote records |
| `ideas_implemented_total` | Garden harvest count | Cumulative harvested ideas |
| `cycles_since_last_harvest` | Snapshot history | Cycles since last idea was harvested |

#### 2.5 Health Indicators

Composite indicators of system stability:

| Metric | Source | How Computed |
|--------|--------|-------------|
| `budget_utilization` | `budget.json` | used / limit (0.0-1.0) |
| `weekly_allowance_remaining` | `budget-history.json` | Remaining weekly allowance fraction |
| `convergence_risk` | Snapshot history | `low/medium/high` based on consecutive_no_improvement |
| `circuit_breaker_trips` | Safety log (spec-45) | Count of circuit breaker activations |
| `consecutive_no_improvement` | Snapshot history | Cycles with no metric improvement |
| `error_rate` | `session.log` | Error log entries / total log entries |
| `self_modification_count` | `self_modifications.json` | Total self-modifications in current cycle |

### 3. Baselines

The `baselines` object records metric values at the start of the first evolution cycle. All trend analysis compares current values against baselines:

- **Improvement**: current value is better than baseline (direction depends on metric — lower tokens_per_task is better, higher test_pass_rate is better)
- **Regression**: current value is worse than baseline
- **Stable**: current value is within 5% of baseline

Baselines are set once and never updated automatically. The human can reset baselines via `--health --reset-baseline`.

### 4. Trend Analysis

The REFLECT phase (spec-41) analyzes trends across the last N snapshots (configurable, default 5):

```bash
_metrics_analyze_trends() {
    local window="${1:-5}"

    # For each metric, compute:
    # - direction: improving | degrading | stable
    # - rate: percentage change per cycle
    # - alert: true if degrading for 3+ consecutive cycles

    # Output: JSON array of trend observations
    # These feed into signal emission (spec-42) and idea auto-seeding (spec-38)
}
```

Trend alerts:

| Condition | Action |
|-----------|--------|
| Metric degrading 3+ consecutive cycles | Emit `attention_needed` signal (spec-42) |
| Metric improved 3+ consecutive cycles | Emit `promising_approach` signal |
| `convergence_risk` reaches `high` | Log convergence warning (spec-26) |
| `budget_utilization` > 0.9 | Emit `attention_needed` signal |
| `test_pass_rate` drops below baseline | Emit `quality_concern` signal |

### 5. Snapshot Timing

A metrics snapshot is taken at two points in each evolution cycle:

1. **Pre-cycle snapshot** — Before REFLECT phase begins. This is the "before" measurement.
2. **Post-cycle snapshot** — After OBSERVE phase completes. This is the "after" measurement.

The OBSERVE phase compares pre and post snapshots to determine whether the cycle's implementation improved, degraded, or had no effect on target metrics.

### 6. `--health` CLI Dashboard

`./automaton.sh --health` displays a terminal dashboard:

```
╔══════════════════════════════════════════════════════════╗
║                   AUTOMATON HEALTH                       ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  CAPABILITY          Current    Baseline    Trend        ║
║  Lines of code       9,240      8,610       ▲ +7.3%     ║
║  Functions           156        142         ▲ +9.9%     ║
║  Specs               45         37          ▲ +21.6%    ║
║  Tests               35         28          ▲ +25.0%    ║
║                                                          ║
║  EFFICIENCY          Current    Baseline    Trend        ║
║  Tokens/task         42,000     50,000      ▼ -16.0% ✓  ║
║  Stall rate          0.08       0.15        ▼ -46.7% ✓  ║
║  Cache hit ratio     0.72       0.68        ▲ +5.9%  ✓  ║
║                                                          ║
║  QUALITY             Current    Baseline    Trend        ║
║  Test pass rate      0.97       0.93        ▲ +4.3%  ✓  ║
║  Rollbacks           0          0           — stable     ║
║                                                          ║
║  INNOVATION          Current                             ║
║  Garden: 4 seeds, 3 sprouts, 2 blooms                   ║
║  Signals: 5 active (2 strong)                            ║
║  Harvested: 7 ideas total                                ║
║                                                          ║
║  HEALTH              Status                              ║
║  Budget utilization   65% ████████░░                     ║
║  Weekly allowance     42% remaining                      ║
║  Convergence risk     LOW                                ║
║  Circuit breakers     0 trips                            ║
║  Evolution cycles     12 completed                       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
  Last snapshot: 2026-03-02T14:30:00Z (cycle 12)
```

Trend indicators: `▲` = increasing, `▼` = decreasing, `—` = stable. `✓` marks improvements (direction depends on metric).

### 7. Bootstrap Manifest Integration

Extend the bootstrap manifest (spec-37) with a `metrics_trend` field:

```json
{
  "metrics_trend": {
    "improving": ["tokens_per_task", "stall_rate", "test_pass_rate"],
    "degrading": [],
    "alerts": [],
    "cycles_completed": 12,
    "last_harvest_cycle": 12
  }
}
```

### 8. Configuration

New `metrics` section in `automaton.config.json`:

```json
{
  "metrics": {
    "enabled": true,
    "trend_window": 5,
    "degradation_alert_threshold": 3,
    "snapshot_retention": 100
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable growth metrics tracking |
| `trend_window` | number | 5 | Number of snapshots for trend analysis |
| `degradation_alert_threshold` | number | 3 | Consecutive degrading cycles before alert |
| `snapshot_retention` | number | 100 | Maximum snapshots to retain (oldest pruned) |

## Acceptance Criteria

- [ ] `.automaton/evolution-metrics.json` stores per-cycle snapshots with all 5 categories
- [ ] Capability metrics accurately counted from source files
- [ ] Efficiency metrics sourced from run metadata and budget data
- [ ] Quality metrics sourced from test results and self-modification log
- [ ] Innovation metrics sourced from garden index and signal data
- [ ] Health indicators computed as composite assessments
- [ ] Baselines recorded on first evolution cycle, preserved across cycles
- [ ] Trend analysis detects improving/degrading/stable patterns
- [ ] Degradation alerts trigger signal emission after threshold cycles
- [ ] Pre-cycle and post-cycle snapshots enable before/after comparison
- [ ] `--health` dashboard displays all categories with trend indicators
- [ ] Bootstrap manifest includes `metrics_trend` summary
- [ ] Snapshot retention enforced (oldest pruned when limit exceeded)

## Dependencies

- Depends on: spec-26 (run metadata — tokens/task, stall rate, first-pass success)
- Depends on: spec-34 (persistent state — metrics file is git-tracked)
- Depends on: spec-37 (bootstrap manifest — metrics_trend field)
- Depends on: spec-38 (garden — innovation metrics from garden index)
- Depends on: spec-42 (signals — innovation metrics and trend alert emission)
- Depended on by: spec-41 (evolution loop — REFLECT uses trends, OBSERVE compares snapshots)
- Depended on by: spec-44 (CLI — `--health` command)
- Depended on by: spec-45 (safety — circuit breakers reference metric thresholds)

## Files to Modify

- `automaton.sh` — add metrics functions (`_metrics_snapshot()`, `_metrics_analyze_trends()`, `_metrics_compare()`, `_metrics_display_health()`, `_metrics_set_baselines()`, `_metrics_get_latest()`), add `--health` CLI flag, integrate snapshots into evolution cycle
- `automaton.config.json` — add `metrics` configuration section
- `.automaton/evolution-metrics.json` — new file: metrics snapshots and baselines
- `.automaton/init.sh` — add `metrics_trend` to bootstrap manifest
- `.gitignore` — add `.automaton/evolution-metrics.json` as persistent (git-tracked) state
