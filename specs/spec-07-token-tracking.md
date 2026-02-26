# Spec 07: Token Tracking & Budget System

## Purpose

Track every token consumed across all agents and phases. Enforce budget limits to prevent runaway costs. Provide real-time cost estimates in logs and stdout.

## Data Source

Claude CLI's `--output-format stream-json` emits NDJSON. The final result message contains usage:

```json
{
  "type": "result",
  "subtype": "success",
  "usage": {
    "input_tokens": 15234,
    "output_tokens": 3421,
    "cache_creation_input_tokens": 8000,
    "cache_read_input_tokens": 12000
  }
}
```

The orchestrator extracts this by grep/jq from the stream-json output after each agent invocation.

## Token Extraction

```bash
# Extract usage from stream-json output
usage=$(echo "$result" | grep '"type":"result"' | tail -1)
input_tokens=$(echo "$usage" | jq -r '.usage.input_tokens // 0')
output_tokens=$(echo "$usage" | jq -r '.usage.output_tokens // 0')
cache_create=$(echo "$usage" | jq -r '.usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$usage" | jq -r '.usage.cache_read_input_tokens // 0')
```

Dependency: `jq` must be available. The CLI entry point should check for jq and warn if missing.

## Budget File (`.automaton/budget.json`)

```json
{
  "limits": {
    "max_total_tokens": 10000000,
    "max_cost_usd": 50.00,
    "per_phase": {
      "research": 500000,
      "plan": 1000000,
      "build": 7000000,
      "review": 1500000
    },
    "per_iteration": 500000
  },
  "used": {
    "total_input": 0,
    "total_output": 0,
    "total_cache_create": 0,
    "total_cache_read": 0,
    "by_phase": {
      "research": { "input": 0, "output": 0 },
      "plan": { "input": 0, "output": 0 },
      "build": { "input": 0, "output": 0 },
      "review": { "input": 0, "output": 0 }
    },
    "estimated_cost_usd": 0.00
  },
  "history": []
}
```

### History Entries

Each iteration appends to the `history` array:

```json
{
  "iteration": 7,
  "phase": "build",
  "model": "sonnet",
  "input_tokens": 112000,
  "output_tokens": 24000,
  "cache_create": 5000,
  "cache_read": 80000,
  "estimated_cost": 2.04,
  "duration_seconds": 145,
  "task": "Add auth middleware",
  "status": "success",
  "timestamp": "2026-02-26T10:30:00Z"
}
```

## Cost Estimation

Pricing table (update as prices change):

| Model | Input $/M | Output $/M | Cache Write $/M | Cache Read $/M |
|-------|----------|-----------|----------------|---------------|
| opus | 15.00 | 75.00 | 18.75 | 1.50 |
| sonnet | 3.00 | 15.00 | 3.75 | 0.30 |
| haiku | 0.80 | 4.00 | 1.00 | 0.08 |

Formula:
```
cost = (input_tokens * input_rate / 1_000_000)
     + (output_tokens * output_rate / 1_000_000)
     + (cache_create * cache_write_rate / 1_000_000)
     + (cache_read * cache_read_rate / 1_000_000)
```

## Enforcement Rules

### Per-Iteration Limit
- After each iteration, check if tokens used in that iteration exceeded `budget.per_iteration`
- If exceeded: Log warning, continue (the iteration already completed)
- Purpose: Alerting, not killing mid-iteration

### Per-Phase Limit
- After each iteration, check cumulative phase tokens against `budget.per_phase.[phase]`
- If exceeded: Force phase transition
- The current iteration's work is kept (already committed)
- Log: `[ORCHESTRATOR] Phase budget exhausted for [phase]. Transitioning to next phase.`
- This is NOT fatal. The project moves forward with whatever was accomplished.

### Total Token Limit
- After each iteration, check cumulative total against `budget.max_total_tokens`
- If exceeded: Graceful shutdown
- Save state for resume
- Exit code 2
- Log: `[ORCHESTRATOR] Total token budget exhausted. Run --resume after adjusting budget.`

### Cost Limit
- After each iteration, check estimated cost against `budget.max_cost_usd`
- If exceeded: Same behavior as total token limit
- Exit code 2

## Initialization

On first run, the orchestrator creates `.automaton/budget.json` with limits from `automaton.config.json` (or defaults) and zeroed usage counters.

On `--resume`, the orchestrator reads the existing budget.json and continues accumulating.

## Budget Display

Session log entries include cost:
```
[2026-02-26T10:30:00Z] [BUILD] Iteration 7: 112K in / 24K out (~$2.04) | Phase: $18.60 / $105.00 | Total: $31.40 / $50.00
```

Stdout one-liner includes remaining budget:
```
[BUILD 7/~20] Task: Add auth middleware | ~$2.04 | budget: $18.60 remaining
```
