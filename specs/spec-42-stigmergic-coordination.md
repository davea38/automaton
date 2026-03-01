# Spec 42: Stigmergic Coordination

## Purpose

In biological systems, stigmergy enables complex coordination without direct communication — ants leave pheromone trails that guide other ants, creating emergent collective intelligence. Automaton's agents currently have no way to leave persistent observations for other agents or future runs. Each agent starts fresh, re-discovering the same issues. This spec introduces a signal-based coordination mechanism where agents emit typed signals into a shared environment (`.automaton/signals.json`). Signals decay over time but strengthen through reinforcement — if multiple agents or runs observe the same pattern, the signal grows stronger. This creates natural prioritization: frequently-observed problems accumulate strong signals while one-off observations fade, directing the evolution loop's attention to the most pressing issues without explicit orchestration.

## Requirements

### 1. Signal Data Structure

Signals are stored in `.automaton/signals.json`:

```json
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "recurring_pattern",
      "title": "High prompt overhead in build phase",
      "description": "Build phase prompt_overhead_ratio consistently >50% across runs",
      "strength": 0.8,
      "decay_rate": 0.05,
      "observations": [
        {
          "agent": "evolve-reflect",
          "cycle": 3,
          "timestamp": "2026-03-01T10:00:00Z",
          "detail": "prompt_overhead_ratio = 0.54 in run-2026-03-01"
        },
        {
          "agent": "evolve-reflect",
          "cycle": 5,
          "timestamp": "2026-03-02T14:00:00Z",
          "detail": "prompt_overhead_ratio = 0.57 in run-2026-03-02"
        }
      ],
      "related_ideas": ["idea-003"],
      "created_at": "2026-03-01T10:00:00Z",
      "last_reinforced_at": "2026-03-02T14:00:00Z",
      "last_decayed_at": "2026-03-02T14:00:00Z"
    }
  ],
  "next_id": 2,
  "updated_at": "2026-03-02T14:00:00Z"
}
```

### 2. Signal Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique identifier (SIG-NNN) |
| `type` | enum | yes | Signal type (see Signal Types below) |
| `title` | string | yes | One-line summary (max 120 chars) |
| `description` | string | yes | Detailed observation |
| `strength` | number | yes | Current strength (0.0-1.0) |
| `decay_rate` | number | yes | Strength lost per decay cycle (0.0-1.0) |
| `observations` | array | yes | List of observation events that reinforce this signal |
| `related_ideas` | array | no | Garden idea IDs related to this signal |
| `created_at` | string | yes | ISO 8601 timestamp |
| `last_reinforced_at` | string | yes | ISO 8601 timestamp of last reinforcement |
| `last_decayed_at` | string | yes | ISO 8601 timestamp of last decay application |

### 3. Signal Types

| Type | Description | Default Decay Rate | Example |
|------|-------------|-------------------|---------|
| `attention_needed` | Something requires investigation | 0.10 | "Test test_budget_pacing.sh failing for 3 runs" |
| `promising_approach` | A technique that worked well | 0.05 | "Caching static prompt sections saved 20K tokens" |
| `recurring_pattern` | A pattern observed multiple times | 0.05 | "Build phase consistently stalls at iteration 7+" |
| `efficiency_opportunity` | A potential optimization | 0.08 | "Review phase reads entire codebase when only 3 files changed" |
| `quality_concern` | A quality or reliability issue | 0.07 | "Self-modifications occasionally break syntax check" |
| `complexity_warning` | Growing complexity that may need attention | 0.06 | "automaton.sh has grown past 8,500 lines" |

### 4. Signal Lifecycle

**Emission** — Agents emit signals by calling `_signal_emit()`. If a signal with the same type and similar title already exists (fuzzy match using tag overlap), the existing signal is reinforced instead of creating a duplicate. New signals start at strength `stigmergy.initial_strength` (default: 0.3).

**Reinforcement** — When an agent observes something that matches an existing signal, it reinforces it by adding an observation. Each reinforcement increases strength by `stigmergy.reinforce_increment` (default: 0.15), capped at 1.0. This is the core mechanism: repeated observations make signals louder.

**Decay** — At the start of each evolution cycle, all signals decay by their `decay_rate`. Signals whose strength drops below `stigmergy.decay_floor` (default: 0.05) are removed. Decay ensures that one-off observations fade naturally while persistent issues remain visible.

**Linking** — When a garden idea (spec-38) is created from a signal, the signal's `related_ideas` field is updated and the idea's `related_signals` field references the signal ID. This bidirectional link enables the evolution loop to trace why an idea exists.

### 5. Signal Emission Points

Agents emit signals at these integration points:

| Phase/Agent | Signal Type | Trigger |
|-------------|-------------|---------|
| REFLECT (spec-41) | `recurring_pattern` | Same metric threshold breached 3+ consecutive cycles |
| REFLECT | `attention_needed` | Test failures persisting across cycles |
| REFLECT | `efficiency_opportunity` | Token usage trending upward |
| REFLECT | `quality_concern` | Rollback occurred in previous cycle |
| IDEATE (spec-41) | `promising_approach` | Idea with evidence from successful implementation |
| OBSERVE (spec-41) | `promising_approach` | Implementation improved target metric |
| OBSERVE | `quality_concern` | Implementation caused regression |
| Review phase (spec-06) | `complexity_warning` | File exceeds complexity thresholds |
| Build phase (spec-05) | `attention_needed` | Same build error recurring across iterations |

### 6. Signal Matching

To determine if a new emission matches an existing signal (for reinforcement vs. creation), use tag-based similarity:

1. Extract key terms from the new signal's title and description
2. Compare against existing signals of the same type
3. If overlap score exceeds `stigmergy.match_threshold` (default: 0.6), reinforce existing signal
4. Otherwise, create new signal

The matching function `_signal_find_match()` uses simple word overlap — no external dependencies needed:

```bash
# Pseudocode for signal matching
overlap = |words_new ∩ words_existing| / |words_new ∪ words_existing|
if overlap >= match_threshold: reinforce existing
else: create new
```

### 7. Signal Querying

Functions for querying signals:

| Function | Description |
|----------|-------------|
| `_signal_get_strong()` | Return signals with strength >= threshold (default: 0.5) |
| `_signal_get_by_type()` | Return signals filtered by type |
| `_signal_get_active()` | Return all signals with strength > decay_floor |
| `_signal_get_unlinked()` | Return signals with no related garden ideas |

The REFLECT phase queries `_signal_get_strong()` and `_signal_get_unlinked()` to identify issues that have accumulated evidence but no corresponding garden idea.

### 8. Bootstrap Manifest Integration

Extend the bootstrap manifest (spec-37) with an `active_signals` field:

```json
{
  "active_signals": {
    "total": 5,
    "strong": 2,
    "strongest": {"id": "SIG-001", "title": "High prompt overhead", "strength": 0.8},
    "unlinked_count": 1
  }
}
```

### 9. Configuration

New `stigmergy` section in `automaton.config.json`:

```json
{
  "stigmergy": {
    "enabled": true,
    "initial_strength": 0.3,
    "reinforce_increment": 0.15,
    "decay_floor": 0.05,
    "match_threshold": 0.6,
    "max_signals": 100
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable stigmergic coordination |
| `initial_strength` | number | 0.3 | Starting strength for new signals |
| `reinforce_increment` | number | 0.15 | Strength added per reinforcement |
| `decay_floor` | number | 0.05 | Signals below this strength are removed |
| `match_threshold` | number | 0.6 | Word overlap threshold for signal matching |
| `max_signals` | number | 100 | Maximum active signals before oldest-weakest are pruned |

### 10. Persistent State

`.automaton/signals.json` is persistent (git-tracked, extending spec-34). It is committed alongside other persistent state at phase transitions and run completion. The file is created on first signal emission, not during initialization.

## Acceptance Criteria

- [ ] `.automaton/signals.json` stores typed signals with strength and decay
- [ ] Agents can emit signals via `_signal_emit()`
- [ ] Duplicate signals are reinforced instead of duplicated (tag-based matching)
- [ ] Signal strength increases on reinforcement, capped at 1.0
- [ ] Signals decay at the start of each evolution cycle
- [ ] Signals below decay_floor are automatically removed
- [ ] Signals link bidirectionally to garden ideas
- [ ] REFLECT phase queries signals to identify unlinked strong signals
- [ ] Bootstrap manifest includes `active_signals` summary
- [ ] Signal operations are idempotent when called with identical parameters
- [ ] `max_signals` limit enforced by pruning weakest signals

## Dependencies

- Depends on: spec-34 (persistent state — signals.json is git-tracked)
- Depends on: spec-37 (bootstrap manifest — active_signals field)
- Integrates with: spec-38 (garden ideas link to signals, signals trigger auto-seeding)
- Depended on by: spec-41 (evolution loop emits and queries signals)
- Depended on by: spec-43 (growth metrics track signal activity)
- Depended on by: spec-44 (CLI — `--signals` command)
- Depended on by: spec-45 (safety — emit quality_concern on rollback)

## Files to Modify

- `automaton.sh` — add signal functions (`_signal_emit()`, `_signal_reinforce()`, `_signal_decay_all()`, `_signal_find_match()`, `_signal_get_strong()`, `_signal_get_by_type()`, `_signal_get_active()`, `_signal_get_unlinked()`, `_signal_prune()`), integrate emission points into build/review phases
- `automaton.config.json` — add `stigmergy` configuration section
- `.automaton/init.sh` — add `active_signals` to bootstrap manifest
- `.gitignore` — add `.automaton/signals.json` as persistent (git-tracked) state
