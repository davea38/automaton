---
name: garden-tender
description: Guided workflow for reviewing and tending the idea garden
tools: Read, Bash, Grep
---

## Instructions

Guide the human through reviewing their idea garden and taking action on ideas that need attention. This skill provides a higher-level workflow than individual `--garden`, `--water`, and `--prune` commands.

### Step 1: Load Garden State

Read `.automaton/garden/_index.json` to get the garden summary:
- Total ideas by stage (seed, sprout, bloom, harvest, wilt)
- Bloom candidates ready for quorum evaluation
- Recent activity timestamps

If `.automaton/garden/_index.json` does not exist, report that the garden is empty and suggest using `--plant "idea"` to create the first seed.

### Step 2: Identify Ideas Needing Attention

Read individual idea files from `.automaton/garden/` and categorize them:

1. **Stale seeds**: Seeds with no evidence added in the last 7 days — candidates for pruning or watering
2. **Near-threshold sprouts**: Sprouts close to bloom threshold (priority >= 30) — candidates for promotion or additional evidence
3. **Bloom candidates**: Ideas ready for quorum evaluation — present their evidence summary
4. **Unlinked ideas**: Ideas with no `related_signals` — may benefit from signal connection

Present each category with idea ID, title, stage, priority, age, and evidence count.

### Step 3: Review Each Category

For each category, provide specific guidance:

- **Stale seeds**: "These seeds have received no new evidence. Consider: (a) watering with new evidence using `--water ID 'evidence'`, or (b) pruning if no longer relevant using `--prune ID 'reason'`"
- **Near-threshold sprouts**: "These sprouts are close to bloom. Review their evidence and consider: (a) adding more evidence, (b) promoting directly with `--promote ID` if ready"
- **Bloom candidates**: "These ideas are ready for quorum evaluation. They will be evaluated in the next `--evolve` cycle, or you can promote them with `--promote ID`"
- **Unlinked ideas**: "These ideas have no related signals. Check `--signals` for signals that might relate to these ideas"

### Step 4: Check Signal Connections

If `.automaton/signals.json` exists, read it and identify:
- Strong unlinked signals (strength >= 0.5, no `related_ideas`) that could inspire new garden seeds
- Signals related to existing ideas that could provide watering evidence

Present any connections found between signals and garden ideas.

### Step 5: Output Summary

Output a structured summary:

```json
{
  "garden_health": "healthy|needs_attention|empty",
  "total_ideas": 9,
  "stale_seeds": ["idea-001", "idea-008"],
  "near_threshold_sprouts": ["idea-003"],
  "bloom_candidates": ["idea-006", "idea-007"],
  "unlinked_ideas": ["idea-009"],
  "unlinked_signals": ["SIG-005", "SIG-007"],
  "recommended_actions": [
    "Prune or water 2 stale seeds",
    "Review 1 near-threshold sprout for promotion",
    "2 bloom candidates ready for evaluation",
    "2 unlinked signals could inspire new seeds"
  ]
}
```

## Constraints

- This skill is read-only. Do not modify garden state — only recommend actions via CLI commands.
- Output must be valid JSON in the final summary.
- If `.automaton/garden/` does not exist, output `{"garden_health": "empty", "total_ideas": 0, "recommended_actions": ["Run --plant 'idea' to create your first seed"]}`.
- Read at most 20 idea files to avoid excessive context. If more exist, focus on seeds and sprouts (most actionable).
- Use age in days (calculated from `updated_at`) for staleness checks.
- Do not recommend specific idea content — only surface which ideas need attention and what actions are available.
