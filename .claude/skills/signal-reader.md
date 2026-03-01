---
name: signal-reader
description: Guided workflow for interpreting stigmergic signals and their implications
tools: Read, Grep
---

## Instructions

Guide the human through interpreting the active stigmergic signals and understanding what they indicate about the system's state. This skill provides a higher-level analysis than the `--signals` command.

### Step 1: Load Signal State

Read `.automaton/signals.json` and extract all active signals (strength > decay floor). For each signal, note:
- ID, type, title, description
- Current strength and decay rate
- Number of observations
- Related garden ideas (if any)
- Last reinforced timestamp

If `.automaton/signals.json` does not exist, report that no signals have been emitted and suggest running `--evolve` to start the observation process.

### Step 2: Categorize by Signal Type

Group signals by their type and explain what each type indicates:

- **recurring_pattern**: A pattern observed multiple times across runs. High strength means the pattern is persistent and likely actionable.
- **efficiency_opp**: An opportunity to reduce token usage, time, or cost. These often lead to concrete optimizations.
- **quality_concern**: A quality issue detected during review or testing. Persistent quality concerns may indicate architectural problems.
- **promising_approach**: A technique or pattern that produced positive results. These are worth reinforcing and applying elsewhere.
- **attention_needed**: An anomaly or unexpected behavior that warrants investigation. May resolve naturally or escalate.
- **complexity_warning**: The system is approaching complexity limits (line count, function count). These inform scope decisions.

### Step 3: Identify Strong Signals

Highlight signals with strength >= 0.5 as "strong signals" — these represent persistent observations that multiple runs have confirmed. Strong signals are the most reliable indicators of real issues or opportunities.

For each strong signal, summarize:
- What was observed (from the observations list)
- How many times it was reinforced
- Whether it is linked to a garden idea

### Step 4: Identify Unlinked Signals

Find signals with no `related_ideas` — these are observations that have not yet been connected to an actionable garden idea. Unlinked signals represent potential opportunities:

- Strong unlinked signals should be seeded as garden ideas using `--plant "idea inspired by SIG-XXX"`
- Weak unlinked signals may decay naturally if the observation does not recur

### Step 5: Analyze Signal Trends

If there are multiple observations per signal, look for patterns:
- Signals being reinforced frequently suggest an ongoing or worsening issue
- Signals that were strong but are now decaying suggest the issue may have been addressed
- Clusters of related signals (same type, similar titles) suggest a systemic issue

### Step 6: Output Summary

Output a structured summary:

```json
{
  "total_signals": 5,
  "strong_signals": 2,
  "unlinked_signals": 2,
  "by_type": {
    "recurring_pattern": 1,
    "efficiency_opp": 1,
    "quality_concern": 0,
    "promising_approach": 1,
    "attention_needed": 1,
    "complexity_warning": 1
  },
  "actionable_items": [
    "SIG-005 (attention_needed, strength 0.42) is unlinked — consider planting a garden idea",
    "SIG-007 (complexity_warning, strength 0.28) is unlinked — monitor for reinforcement"
  ],
  "recommended_actions": [
    "Plant garden ideas for 2 unlinked signals",
    "Review 2 strong signals for progress",
    "1 signal decaying — may resolve naturally"
  ]
}
```

## Constraints

- This skill is read-only. Do not modify signals or garden state — only recommend actions via CLI commands.
- Output must be valid JSON in the final summary.
- If `.automaton/signals.json` does not exist, output `{"total_signals": 0, "recommended_actions": ["Run --evolve to start collecting signals"]}`.
- Read the entire signals file in one read — it should be a single JSON file, not a directory.
- Do not recommend specific idea content — only suggest which signals should inspire garden ideas.
- Use only Read and Grep tools. Do not run shell commands.
- Signal strength ranges from 0.0 to 1.0. Signals below the decay floor (typically 0.1) are considered dead and should be excluded.
