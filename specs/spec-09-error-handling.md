# Spec 09: Error Handling & Recovery

## Purpose

Define how automaton detects, classifies, and recovers from every category of error. The goal is maximum resilience: automaton should complete its work despite transient failures, and save state for resume when failures are persistent.

## Error Taxonomy

| # | Error | Detection | Response | Max Retries |
|---|-------|-----------|----------|-------------|
| 1 | CLI crash | `$? != 0`, no rate limit signal | Retry with delay | 3 |
| 2 | Rate limit | `$? != 0`, output has `429`/`rate_limit`/`overloaded` | Exponential backoff | 5 (see spec-08) |
| 3 | Budget exhausted | budget.json check after iteration | Graceful stop, save state, exit 2 | 0 |
| 4 | Stall | `git diff --stat HEAD~1` is empty | After 3 stalls, re-plan | 3 then escalate |
| 5 | Plan corruption | `[x]` count decreased after iteration | Restore from checkpoint | 1 then escalate |
| 6 | Network error | `$? != 0`, output has `network`/`connection`/`timeout` | Backoff like rate limit | 5 |
| 7 | Test failure (single) | Agent reports test failure in output | Agent handles in-iteration | N/A |
| 8 | Test failure (repeated) | Same test fails 3+ iterations | Escalate to review phase | 3 |
| 9 | Phase timeout | Wallclock timer exceeded | Force phase transition | 0 |

## Error #1: CLI Crash

```bash
exit_code=$?
if [ $exit_code -ne 0 ]; then
    if ! is_rate_limit "$result" && ! is_network_error "$result"; then
        consecutive_failures=$((consecutive_failures + 1))
        log "[ORCHESTRATOR] CLI error (exit $exit_code), attempt $consecutive_failures/$max_failures"
        if [ $consecutive_failures -ge $max_consecutive_failures ]; then
            log "[ORCHESTRATOR] Max consecutive failures reached. Saving state."
            save_state
            exit 1
        fi
        sleep $retry_delay_seconds
        continue  # retry the iteration
    fi
fi
```

Reset `consecutive_failures` to 0 on any successful iteration.

## Error #4: Stall Detection

After each build iteration:

```bash
# Check if the iteration produced any code changes
diff_stat=$(git diff --stat HEAD~1 2>/dev/null)
if [ -z "$diff_stat" ]; then
    stall_count=$((stall_count + 1))
    log "[ORCHESTRATOR] Stall detected ($stall_count/$stall_threshold). No code changes."
else
    stall_count=0  # reset on any change
fi

if [ $stall_count -ge $stall_threshold ]; then
    log "[ORCHESTRATOR] $stall_threshold consecutive stalls. Forcing re-plan."
    stall_count=0
    transition_to_phase "plan"  # return to Phase 2
fi
```

If re-plan also produces a build loop that stalls again, escalate:
```bash
if [ $replan_count -ge 2 ]; then
    escalate "Agent stalled after re-planning. Manual intervention required."
fi
```

## Error #5: Plan Corruption Guard

Before each iteration:
```bash
cp IMPLEMENTATION_PLAN.md .automaton/plan_checkpoint.md
completed_before=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
```

After each iteration:
```bash
completed_after=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)

if [ "$completed_after" -lt "$completed_before" ]; then
    log "[ORCHESTRATOR] PLAN CORRUPTION: completed count dropped from $completed_before to $completed_after"
    cp .automaton/plan_checkpoint.md IMPLEMENTATION_PLAN.md
    git add IMPLEMENTATION_PLAN.md
    git commit -m "automaton: restore plan from corruption"
    corruption_count=$((corruption_count + 1))
    if [ $corruption_count -ge 2 ]; then
        escalate "Plan corruption detected twice. Agent may be rewriting the plan."
    fi
fi
```

## Error #9: Phase Timeout

Optional wallclock timer per phase:

```bash
phase_start=$(date +%s)
phase_timeout=${config_phase_timeout:-0}  # 0 = no timeout

# Inside iteration loop:
if [ $phase_timeout -gt 0 ]; then
    elapsed=$(( $(date +%s) - phase_start ))
    if [ $elapsed -ge $phase_timeout ]; then
        log "[ORCHESTRATOR] Phase timeout after ${elapsed}s. Forcing transition."
        break  # exit phase loop
    fi
fi
```

Phase timeouts are not configured by default. They're a safety net for unattended runs.

## Escalation Protocol

When errors exceed recovery capacity:

```bash
escalate() {
    local description="$1"
    log "[ORCHESTRATOR] ESCALATION: $description"

    # Mark in the plan file for visibility
    echo "" >> IMPLEMENTATION_PLAN.md
    echo "## ESCALATION" >> IMPLEMENTATION_PLAN.md
    echo "" >> IMPLEMENTATION_PLAN.md
    echo "ESCALATION: $description" >> IMPLEMENTATION_PLAN.md
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> IMPLEMENTATION_PLAN.md
    echo "Phase: $current_phase, Iteration: $iteration" >> IMPLEMENTATION_PLAN.md

    save_state
    git add -A
    git commit -m "automaton: escalation - $description"
    exit 3  # escalation exit code
}
```

Human resolves the issue, then runs `./automaton.sh --resume`.

## Error Classification Helper

```bash
is_rate_limit() {
    echo "$1" | grep -qi 'rate_limit\|429\|overloaded'
}

is_network_error() {
    echo "$1" | grep -qi 'network\|connection\|timeout\|ECONNREFUSED\|ETIMEDOUT'
}
```

## Recovery State Machine

```
Normal Operation
    |
    +--> CLI Error --> retry (up to 3) --> persistent? --> save state, exit 1
    |
    +--> Rate Limit --> backoff (up to 5) --> persistent? --> long pause, retry
    |
    +--> Stall --> re-plan (up to 2) --> still stalled? --> escalate, exit 3
    |
    +--> Plan Corruption --> restore checkpoint --> repeated? --> escalate, exit 3
    |
    +--> Budget Exhausted --> save state, exit 2
    |
    +--> Phase Timeout --> force transition
```
