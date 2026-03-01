# Spec 38: Idea Garden

## Purpose

The flat `.automaton/backlog.md` (spec-25) stores improvement ideas as unstructured markdown checkboxes. This works for human-curated lists but cannot support autonomous evolution — ideas need metadata (origin, evidence, confidence, lifecycle stage), relationships (which ideas relate to which signals/metrics), and a progression model that lets ideas mature through stages before implementation. The Idea Garden replaces the flat backlog with a structured repository where ideas are born as seeds, accumulate evidence as sprouts, reach bloom when ready for evaluation, and are harvested (implemented) or wilted (rejected). This organic lifecycle creates a natural filter: only ideas with sufficient evidence and quorum approval advance to implementation.

## Requirements

### 1. Garden Directory Structure

Ideas live as individual JSON files in `.automaton/garden/`:

```
.automaton/garden/
  _index.json          # Summary index of all ideas (regenerated)
  idea-001.json        # Individual idea files
  idea-002.json
  idea-003.json
  ...
```

The `_index.json` file is regenerated whenever an idea changes state. It provides a lightweight summary for the bootstrap manifest (spec-37) without reading every idea file.

### 2. Idea Schema

Each idea is a JSON file with this schema:

```json
{
  "id": "idea-001",
  "title": "Reduce prompt overhead in build phase",
  "description": "Build prompts contain 4K tokens of rules that are identical every iteration. Extract static rules to a cached preamble.",
  "stage": "sprout",
  "origin": {
    "type": "metric",
    "source": "prompt_overhead_ratio > 0.50",
    "created_by": "evolve-reflect",
    "created_at": "2026-03-01T10:00:00Z"
  },
  "evidence": [
    {
      "type": "metric",
      "observation": "Prompt overhead ratio has been >50% for 5 consecutive runs",
      "added_by": "evolve-reflect",
      "added_at": "2026-03-01T10:05:00Z"
    },
    {
      "type": "signal",
      "observation": "Signal SIG-007 (recurring_pattern: high prompt overhead) strength 0.8",
      "added_by": "evolve-ideate",
      "added_at": "2026-03-01T10:10:00Z"
    }
  ],
  "tags": ["performance", "prompts", "token-efficiency"],
  "priority": 0,
  "estimated_complexity": "medium",
  "related_specs": [29, 30, 37],
  "related_signals": ["SIG-007"],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-03-01T10:00:00Z", "reason": "Auto-seeded from metric threshold"},
    {"stage": "sprout", "entered_at": "2026-03-01T10:10:00Z", "reason": "2 evidence items accumulated"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-03-01T10:10:00Z"
}
```

Schema fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique identifier (idea-NNN, auto-incremented) |
| `title` | string | yes | One-line summary (max 120 chars) |
| `description` | string | yes | Detailed explanation of the idea |
| `stage` | enum | yes | `seed`, `sprout`, `bloom`, `harvest`, `wilt` |
| `origin.type` | enum | yes | `metric`, `signal`, `human`, `review`, `agent` |
| `origin.source` | string | yes | What triggered this idea |
| `origin.created_by` | string | yes | Agent or user who planted the seed |
| `origin.created_at` | string | yes | ISO 8601 timestamp |
| `evidence` | array | yes | Evidence items supporting the idea (can be empty for seeds) |
| `tags` | array | no | Categorization tags |
| `priority` | number | yes | Computed priority score (0-100, higher = more urgent) |
| `estimated_complexity` | enum | yes | `trivial`, `low`, `medium`, `high`, `epic` |
| `related_specs` | array | no | Spec numbers this idea relates to |
| `related_signals` | array | no | Signal IDs from stigmergic coordination (spec-42) |
| `related_ideas` | array | no | IDs of related ideas |
| `stage_history` | array | yes | Audit trail of stage transitions |
| `vote_id` | string | null | Reference to quorum vote that advanced this idea (spec-39) |
| `implementation` | object | null | Set when harvested: `{branch, commit, cycle_id}` |
| `updated_at` | string | yes | ISO 8601 timestamp of last modification |

### 3. Lifecycle Stages

Ideas progress through five stages:

```
seed → sprout → bloom → harvest
                    ↘ wilt
```

**Seed** — A newly planted idea. Minimal information: title, description, origin. No evidence yet. Seeds that receive no attention for `garden.seed_ttl_days` (default: 14) are auto-wilted.

**Sprout** — An idea that has accumulated at least `garden.sprout_threshold` evidence items (default: 2). Sprouts represent ideas with supporting observations but not yet ready for evaluation. Sprouts that receive no new evidence for `garden.sprout_ttl_days` (default: 30) are auto-wilted.

**Bloom** — An idea ready for quorum evaluation. Transition requires either: (a) at least `garden.bloom_threshold` evidence items (default: 3) and priority score >= `garden.bloom_priority_threshold` (default: 40), or (b) manual promotion via `--promote` CLI command (spec-44). Blooms are evaluated by the agent quorum (spec-39) during the EVALUATE phase of the evolution loop (spec-41).

**Harvest** — An idea that passed quorum evaluation and was successfully implemented. Records the implementation branch, commit hash, and evolution cycle ID. Harvested ideas are kept as historical records.

**Wilt** — An idea that was rejected (quorum vote failed), abandoned (TTL expired), or whose implementation caused regression and was rolled back (spec-45). Records the reason for wilting.

### 4. Priority Scoring

Priority is computed automatically based on:

```
priority = (evidence_weight * 30) + (signal_strength * 25) + (metric_severity * 25) + (age_bonus * 10) + (human_boost * 10)
```

| Component | Range | Description |
|-----------|-------|-------------|
| `evidence_weight` | 0-1.0 | `min(evidence_count / bloom_threshold, 1.0)` |
| `signal_strength` | 0-1.0 | Max strength of related signals (spec-42), 0 if none |
| `metric_severity` | 0-1.0 | Normalized severity of originating metric threshold breach |
| `age_bonus` | 0-1.0 | `min(days_since_creation / 30, 1.0)` — older ideas get slight boost |
| `human_boost` | 0 or 1.0 | 1.0 if origin.type == "human" (human-planted ideas get priority) |

Priority is recomputed whenever evidence is added or signals change. The orchestrator calls `_garden_recompute_priorities()` at the start of each evolution cycle.

### 5. Auto-Seeding from Metrics

The REFLECT phase of the evolution loop (spec-41) auto-seeds ideas when metric thresholds are breached. Seeding rules:

| Metric Condition | Seed Title Template | Tags |
|-----------------|--------------------|----|
| `stall_rate > 0.20` | "Reduce stall rate (currently {value})" | `performance`, `stalls` |
| `prompt_overhead_ratio > 0.50` | "Reduce prompt overhead (currently {value})" | `performance`, `prompts` |
| `tokens_per_task` increasing 3+ runs | "Investigate token efficiency regression" | `performance`, `tokens` |
| `test_pass_rate < 0.90` | "Improve test pass rate (currently {value})" | `quality`, `tests` |
| `rollback_count > 0` in last 3 cycles | "Address recurring rollbacks" | `quality`, `stability` |

Before auto-seeding, check for existing non-wilted ideas with the same tags to avoid duplicates. If a matching idea exists, add evidence to it instead of creating a new seed.

### 6. Auto-Seeding from Signals

Strong stigmergic signals (spec-42) with strength >= `garden.signal_seed_threshold` (default: 0.7) and no existing related idea trigger auto-seeding. The signal's type and description become the seed's origin and initial evidence.

### 7. Garden Index

`_index.json` provides a lightweight summary for the bootstrap manifest:

```json
{
  "total": 12,
  "by_stage": {
    "seed": 4,
    "sprout": 3,
    "bloom": 2,
    "harvest": 2,
    "wilt": 1
  },
  "bloom_candidates": [
    {"id": "idea-003", "title": "Reduce prompt overhead", "priority": 72},
    {"id": "idea-007", "title": "Add parallel review", "priority": 65}
  ],
  "recent_activity": [
    {"id": "idea-012", "action": "seeded", "at": "2026-03-01T10:00:00Z"},
    {"id": "idea-003", "action": "watered", "at": "2026-03-01T09:30:00Z"}
  ],
  "next_id": 13,
  "updated_at": "2026-03-01T10:00:00Z"
}
```

### 8. Garden Operations

Functions added to `automaton.sh`:

| Function | Description |
|----------|-------------|
| `_garden_plant_seed()` | Create a new idea file in seed stage |
| `_garden_water()` | Add evidence to an existing idea |
| `_garden_advance_stage()` | Transition an idea to the next stage |
| `_garden_wilt()` | Move idea to wilt stage with reason |
| `_garden_recompute_priorities()` | Recalculate priority scores for all active ideas |
| `_garden_rebuild_index()` | Regenerate `_index.json` from all idea files |
| `_garden_prune_expired()` | Auto-wilt ideas that have exceeded their TTL |
| `_garden_find_duplicates()` | Check for existing ideas before creating new ones |
| `_garden_get_bloom_candidates()` | Return ideas eligible for bloom transition |

### 9. Configuration

New `garden` section in `automaton.config.json`:

```json
{
  "garden": {
    "enabled": true,
    "seed_ttl_days": 14,
    "sprout_ttl_days": 30,
    "sprout_threshold": 2,
    "bloom_threshold": 3,
    "bloom_priority_threshold": 40,
    "signal_seed_threshold": 0.7,
    "max_active_ideas": 50,
    "auto_seed_from_metrics": true,
    "auto_seed_from_signals": true
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable the idea garden |
| `seed_ttl_days` | number | 14 | Days before unwatered seeds auto-wilt |
| `sprout_ttl_days` | number | 30 | Days before stale sprouts auto-wilt |
| `sprout_threshold` | number | 2 | Evidence items needed to advance seed → sprout |
| `bloom_threshold` | number | 3 | Evidence items needed to advance sprout → bloom |
| `bloom_priority_threshold` | number | 40 | Minimum priority score for bloom eligibility |
| `signal_seed_threshold` | number | 0.7 | Minimum signal strength to trigger auto-seeding |
| `max_active_ideas` | number | 50 | Maximum non-wilted, non-harvested ideas |
| `auto_seed_from_metrics` | boolean | true | Enable metric-triggered auto-seeding |
| `auto_seed_from_signals` | boolean | true | Enable signal-triggered auto-seeding |

### 10. Bootstrap Manifest Integration

Extend the bootstrap manifest (spec-37) with a `garden_summary` field sourced from `_index.json`:

```json
{
  "garden_summary": {
    "total": 12,
    "seeds": 4,
    "sprouts": 3,
    "blooms": 2,
    "top_bloom": {"id": "idea-003", "title": "Reduce prompt overhead", "priority": 72}
  }
}
```

### 11. Backward Compatibility with Backlog

When `garden.enabled` is true, the evolution loop uses the garden instead of `.automaton/backlog.md`. When false, the system falls back to the flat backlog behavior from spec-25. If a `backlog.md` exists when the garden is first enabled, it is NOT auto-migrated — the two systems coexist until the user explicitly migrates or removes the backlog.

## Acceptance Criteria

- [ ] `.automaton/garden/` directory created during initialization when `garden.enabled` is true
- [ ] Idea JSON files conform to the schema with all required fields
- [ ] Stage transitions follow the defined lifecycle (seed → sprout → bloom → harvest/wilt)
- [ ] Priority scores computed correctly using the 5-component formula
- [ ] Auto-seeding from metrics creates ideas when thresholds are breached
- [ ] Auto-seeding from signals creates ideas when signal strength exceeds threshold
- [ ] Duplicate detection prevents redundant ideas for the same issue
- [ ] TTL-based auto-wilting removes stale seeds and sprouts
- [ ] `_index.json` regenerated accurately after every state change
- [ ] Bootstrap manifest includes `garden_summary` field
- [ ] Garden operations are idempotent (re-running with same input produces same result)
- [ ] Backward compatibility: `garden.enabled: false` falls back to backlog.md behavior

## Dependencies

- Depends on: spec-26 (performance metrics that trigger auto-seeding)
- Depends on: spec-34 (persistent state — garden is git-tracked)
- Depends on: spec-37 (bootstrap manifest — garden_summary field)
- Integrates with: spec-42 (stigmergic signals — auto-seeding from signals)
- Depended on by: spec-39 (quorum evaluates bloom candidates)
- Depended on by: spec-41 (evolution loop manages garden lifecycle)
- Depended on by: spec-43 (growth metrics — innovation metrics from garden index)
- Depended on by: spec-44 (CLI commands for garden interaction)
- Depended on by: spec-45 (safety — wilt ideas on rollback)

## Files to Modify

- `automaton.sh` — add garden functions (`_garden_plant_seed()`, `_garden_water()`, `_garden_advance_stage()`, `_garden_wilt()`, `_garden_recompute_priorities()`, `_garden_rebuild_index()`, `_garden_prune_expired()`, `_garden_find_duplicates()`, `_garden_get_bloom_candidates()`), integrate into `initialize_state()`
- `automaton.config.json` — add `garden` configuration section
- `.automaton/init.sh` — add `garden_summary` to bootstrap manifest
- `.gitignore` — add `.automaton/garden/` as persistent (git-tracked) state
