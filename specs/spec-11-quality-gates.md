# Spec 11: Quality Gates

## Purpose

Quality gates are automated checks that run between phases. They ensure each phase produced valid output before the next phase begins. There are 5 gates, one per phase transition.

## Gate Architecture

Gates are bash functions called by the orchestrator. Each returns 0 (pass) or 1 (fail). The orchestrator decides what to do on failure (retry, warn, refuse).

```bash
gate_check() {
    local gate_name="$1"
    log "ORCHESTRATOR" "Gate: $gate_name..."

    if "gate_$gate_name"; then
        log "ORCHESTRATOR" "Gate: $gate_name... PASS"
        return 0
    else
        log "ORCHESTRATOR" "Gate: $gate_name... FAIL"
        return 1
    fi
}
```

## Gate 1: Spec Completeness (Before Phase 1)

Runs before `automaton.sh` begins any autonomous work. Validates that the conversation phase produced usable specs.

```bash
gate_spec_completeness() {
    local pass=true

    # Check: at least one spec file exists
    if ! ls specs/*.md >/dev/null 2>&1; then
        log "ORCHESTRATOR" "  FAIL: No spec files found in specs/"
        pass=false
    fi

    # Check: PRD.md exists and is non-empty
    if [ ! -s "PRD.md" ]; then
        log "ORCHESTRATOR" "  FAIL: PRD.md missing or empty"
        pass=false
    fi

    # Check: AGENTS.md has a real project name
    if grep -q "(to be determined)" AGENTS.md 2>/dev/null; then
        log "ORCHESTRATOR" "  FAIL: AGENTS.md still has placeholder project name"
        pass=false
    fi

    $pass
}
```

**On Fail:** Refuse to start. Exit with message telling human to complete the conversation phase first.

## Gate 2: Research Completeness (After Phase 1)

Validates that research enriched the specs and resolved unknowns.

```bash
gate_research_completeness() {
    local pass=true
    local warnings=0

    # Check: research agent signaled COMPLETE
    # (Checked inline by orchestrator from agent output, not re-checkable here)
    # This gate runs regardless of COMPLETE signal

    # Check: AGENTS.md was updated (grew from template size)
    local agents_lines=$(wc -l < AGENTS.md)
    if [ "$agents_lines" -le 22 ]; then  # template is ~22 lines
        log "ORCHESTRATOR" "  WARN: AGENTS.md unchanged from template"
        warnings=$((warnings + 1))
    fi

    # Check: no TBD/TODO remaining in specs
    local tbds=$(grep -ri 'TBD\|TODO' specs/ 2>/dev/null | wc -l)
    if [ "$tbds" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: $tbds TBD/TODO markers remaining in specs"
        pass=false
    fi

    $pass
}
```

**On Fail:** Retry research phase (up to max iterations). If max reached, warn and continue to planning (the planning agent may be able to work with partial research).

## Gate 3: Plan Validity (After Phase 2)

Validates that the planning phase produced a usable task list.

```bash
gate_plan_validity() {
    local pass=true

    # Check: at least 5 unchecked tasks
    local unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$unchecked" -lt 5 ]; then
        log "ORCHESTRATOR" "  FAIL: Only $unchecked unchecked tasks (minimum 5)"
        pass=false
    fi

    # Check: plan is non-trivial
    local plan_lines=$(wc -l < IMPLEMENTATION_PLAN.md)
    if [ "$plan_lines" -le 10 ]; then
        log "ORCHESTRATOR" "  FAIL: Plan too short ($plan_lines lines)"
        pass=false
    fi

    # Check: tasks reference specs (heuristic)
    local spec_refs=$(grep -ci 'spec' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$spec_refs" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No spec references found in plan"
        # Warning only, don't fail
    fi

    $pass
}
```

**On Fail:** Retry planning phase (up to max iterations). If max reached, escalate.

## Gate 4: Build Completion (After Phase 3)

Validates that all tasks are complete and code was actually produced.

```bash
gate_build_completion() {
    local pass=true

    # Check: all tasks complete
    local unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$unchecked" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: $unchecked tasks still incomplete"
        pass=false
    fi

    # Check: code changes exist
    local total_changes=$(git log --oneline --since="$run_started_at" | wc -l)
    if [ "$total_changes" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No git commits during build phase"
    fi

    # Check: tests exist (heuristic)
    local test_files=$(find . -name "*test*" -o -name "*spec*" | grep -v node_modules | grep -v .automaton | wc -l)
    if [ "$test_files" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No test files found"
    fi

    $pass
}
```

**On Fail:** Continue building (return to build loop). This gate fails when there are still incomplete tasks, meaning the build loop exited early (budget, iteration limit, or max failures).

## Gate 5: Review Pass (After Phase 4)

Validates that the review agent found no issues.

```bash
gate_review_pass() {
    local pass=true

    # Check: review agent signaled COMPLETE
    # (Checked inline by orchestrator from agent output)

    # Check: no new unchecked tasks were added by reviewer
    local unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    if [ "$unchecked" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: Review created $unchecked new tasks"
        pass=false
    fi

    # Check: no ESCALATION markers
    if grep -q 'ESCALATION:' IMPLEMENTATION_PLAN.md 2>/dev/null; then
        log "ORCHESTRATOR" "  FAIL: Escalation marker found"
        pass=false
    fi

    $pass
}
```

**On Fail:** Return to Phase 3 (build) to address new tasks created by reviewer. After 2 review iterations that both fail, escalate.

## Gate Summary

| Gate | When | Hard Fail Action | Soft Fail Action |
|------|------|-----------------|-----------------|
| 1: Spec Completeness | Before Phase 1 | Refuse to start | N/A |
| 2: Research Completeness | After Phase 1 | Retry research | Warn, continue to plan |
| 3: Plan Validity | After Phase 2 | Retry plan | Warn, continue to build |
| 4: Build Completion | After Phase 3 | Continue building | Warn, continue to review |
| 5: Review Pass | After Phase 4 | Return to build | N/A |

## Adding Custom Gates

The gate system is designed for extensibility. To add a custom gate:
1. Write a bash function `gate_your_gate_name()` that returns 0/1
2. Call it from the appropriate phase transition point in automaton.sh

No configuration for custom gates in v1. This is a code change.
