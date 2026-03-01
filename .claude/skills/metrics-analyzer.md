---
name: metrics-analyzer
description: Guided workflow for analyzing health metrics and interpreting trends
tools: Read, Grep
---

## Instructions

Guide the human through understanding their system's health metrics, trends, and what actions the data suggests. This skill provides deeper analysis than the `--health` dashboard.

### Step 1: Load Metrics Data

Read `.automaton/evolution-metrics.json` and extract:
- The baselines (first recorded snapshot values)
- The most recent snapshot
- The last N snapshots (where N is the configured `trend_window`, typically 5)

If `.automaton/evolution-metrics.json` does not exist, report that no metrics have been collected and suggest running `--evolve` to start collecting snapshots.

### Step 2: Analyze Each Metric Category

For each of the 5 metric categories, compare current values against baselines:

#### Capability
- **line_count**: Total lines in `automaton.sh`. Growth is expected but excessive growth signals complexity.
- **function_count**: Total functions. More functions is fine if each is focused.
- **spec_count**: Number of implemented specs. This should only increase.
- **test_count**: Number of test files. Should grow proportionally with features.

#### Efficiency
- **tokens_per_task**: Average tokens consumed per task. Lower is better.
- **cache_hit_ratio**: Prompt cache hit rate. Higher means better prompt reuse.
- **stall_rate**: How often builds stall or need retry. Lower is better.

#### Quality
- **test_pass_rate**: Percentage of tests passing. Should stay near 100%.
- **rollback_count**: Number of evolution rollbacks. Increasing suggests risky changes.
- **syntax_errors**: Syntax check failures. Should be 0 in a healthy system.

#### Innovation
- **garden_ideas**: Total ideas in the garden. Healthy gardens have active seeds and sprouts.
- **signal_count**: Active signal count. Too few means low observability; too many means noise.
- **vote_count**: Total quorum votes conducted. Shows governance activity.

#### Health
- **budget_utilization**: Percentage of budget consumed. Should be tracked against plan.
- **convergence_risk**: Whether the system is approaching convergence (no more improvements).
- **circuit_breakers**: Number of tripped circuit breakers. Any tripped breaker needs attention.
- **error_rate**: Overall error rate across recent runs.

### Step 3: Identify Trends

For each metric, determine the trend direction over the last N snapshots:
- **improving**: The metric is moving in the desired direction
- **degrading**: The metric is moving away from the desired direction
- **stable**: The metric has not changed significantly

Flag any metric that has been degrading for 3+ consecutive snapshots — these are alert conditions that may trigger automatic signal emission.

### Step 4: Compare Against Baselines

For each metric, calculate the delta from baseline:
- Show percentage change for numeric metrics
- Highlight metrics that have improved > 20% from baseline (celebrate wins)
- Highlight metrics that have degraded > 10% from baseline (flag concerns)

### Step 5: Provide Actionable Insights

Based on the trend analysis, suggest specific actions:
- Degrading test_pass_rate: "Focus on test maintenance before adding new features"
- High tokens_per_task: "Consider prompt optimization or task decomposition"
- Low cache_hit_ratio: "Check if prompt static sections are being modified between iterations"
- Rising complexity: "Consider refactoring before adding more functions"
- Tripped circuit breakers: "Address the breaker condition before continuing evolution"

### Step 6: Output Summary

Output a structured summary:

```json
{
  "snapshots_analyzed": 5,
  "baseline_date": "2026-02-25T00:00:00Z",
  "latest_date": "2026-03-01T00:00:00Z",
  "categories": {
    "capability": {"trend": "improving", "delta_from_baseline": "+15%"},
    "efficiency": {"trend": "stable", "delta_from_baseline": "+2%"},
    "quality": {"trend": "stable", "delta_from_baseline": "0%"},
    "innovation": {"trend": "improving", "delta_from_baseline": "+25%"},
    "health": {"trend": "stable", "delta_from_baseline": "-3%"}
  },
  "alerts": [],
  "wins": ["Capability metrics improved 15% from baseline"],
  "concerns": [],
  "recommended_actions": [
    "System is healthy — continue evolution cycles",
    "Monitor health category for further decline"
  ]
}
```

## Constraints

- This skill is read-only. Do not modify metrics files — only analyze and recommend actions.
- Output must be valid JSON in the final summary.
- If `.automaton/evolution-metrics.json` does not exist, output `{"snapshots_analyzed": 0, "recommended_actions": ["Run --evolve to start collecting metrics"]}`.
- Use only Read and Grep tools. Do not run shell commands.
- When calculating trends, use at least 3 data points. With fewer snapshots, report "insufficient data" instead of a trend direction.
- Do not make predictions about future metric values — only report observed trends and their current direction.
- Keep percentage calculations to whole numbers for readability.
