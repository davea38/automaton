# Spec 45: Safety and Reversibility

## Purpose

Autonomous self-modification is inherently risky. A single bad change can cascade — breaking the test suite, corrupting state, or degrading performance in ways that compound over subsequent cycles. Spec-22 provides basic self-build safety (checkpointing, syntax check, smoke test), but the evolution loop needs additional layers: every implementation runs on a dedicated git branch (not the working branch), circuit breakers automatically halt evolution when thresholds are crossed, sandbox testing validates changes before merge, and a rollback protocol cleanly abandons failed implementations. This spec ensures that the worst case of any evolution cycle is "nothing changed" — never "everything broke."

## Requirements

### 1. Branch-Based Isolation

Every IMPLEMENT phase (spec-41) runs on a dedicated git branch:

```
automaton/evolve-{cycle_id}-{idea_id}
```

Branch lifecycle:
1. **Create**: At the start of IMPLEMENT, branch from the current working branch
2. **Build**: All build iterations happen on the evolution branch
3. **Test**: Full test suite runs on the evolution branch
4. **Compliance**: Constitutional compliance check runs on the branch diff
5. **Merge**: On successful OBSERVE, merge into the working branch (fast-forward or three-way)
6. **Abandon**: On failure, the branch is left unmerged (not deleted — preserved for debugging)

The working branch is never directly modified during an evolution cycle. This means a failed cycle has zero impact on the codebase.

### 2. Sandbox Testing

Before merging an evolution branch, run a sandbox validation sequence:

```bash
_safety_sandbox_test() {
    local branch="$1"

    # 1. Syntax check
    bash -n automaton.sh || return 1

    # 2. Smoke test (--dry-run)
    ./automaton.sh --dry-run || return 1

    # 3. Full test suite
    local test_results
    test_results=$(_run_test_suite)
    local pass_rate=$(echo "$test_results" | jq '.pass_rate')

    # 4. Compare test pass rate against pre-cycle baseline
    local baseline_rate=$(_metrics_get_latest '.quality.test_pass_rate')
    if (( $(echo "$pass_rate < $baseline_rate" | bc -l) )); then
        log "SAFETY" "Test regression detected: $pass_rate < $baseline_rate"
        return 1
    fi

    # 5. Check for protected function modifications
    local protected_changes
    protected_changes=$(git diff main..."$branch" -- automaton.sh | grep -c "^[-+].*\($(echo "${PROTECTED_FUNCTIONS[@]}" | tr ' ' '|')\)")
    if [ "$protected_changes" -gt 0 ]; then
        log "SAFETY" "Protected function modified without explicit approval"
        return 1
    fi

    return 0
}
```

Sandbox testing runs on the evolution branch before any merge attempt.

### 3. Circuit Breakers

Five circuit breakers automatically halt evolution when safety thresholds are crossed:

#### 3.1 Budget Ceiling Breaker

**Trigger**: Evolution cycle cost exceeds `evolution.max_cost_per_cycle_usd` (spec-41)
**Action**: Halt current phase immediately. Save state for resume. Log budget exhaustion.
**Recovery**: Resume with `--evolve --resume` (starts new budget allocation)

#### 3.2 Error Cascade Breaker

**Trigger**: 3 consecutive evolution phases fail (any combination of REFLECT/IDEATE/EVALUATE/IMPLEMENT/OBSERVE failures)
**Action**: Halt evolution loop. Emit `attention_needed` signal. Log error cascade.
**Recovery**: Human must investigate errors before resuming. `--evolve --resume` resets the failure counter.

#### 3.3 Regression Cascade Breaker

**Trigger**: 2 consecutive cycles produce test regressions (OBSERVE phase detects lower test_pass_rate)
**Action**: Halt evolution loop. Emit `quality_concern` signal. Wilt both responsible ideas. Log regression cascade.
**Recovery**: Human reviews the regression pattern. May need to adjust the garden or constitution.

#### 3.4 Complexity Ceiling Breaker

**Trigger**: `automaton.sh` exceeds `safety.max_total_lines` (default: 15000 lines) or total function count exceeds `safety.max_total_functions` (default: 300)
**Action**: Halt evolution. Emit `complexity_warning` signal. Auto-seed "Refactoring needed" idea in garden.
**Recovery**: Refactoring must occur before evolution resumes. The human or a future cycle must reduce complexity.

#### 3.5 Test Degradation Breaker

**Trigger**: `test_pass_rate` drops below `safety.min_test_pass_rate` (default: 0.80) at any point during an evolution cycle
**Action**: Immediately abandon current implementation branch. Halt evolution. Emit `quality_concern` signal.
**Recovery**: Tests must be fixed before evolution resumes.

Circuit breaker state is tracked in `.automaton/evolution/circuit-breakers.json`:

```json
{
  "budget_ceiling": { "tripped": false, "trip_count": 0, "last_trip": null },
  "error_cascade": { "tripped": false, "consecutive_failures": 0, "last_trip": null },
  "regression_cascade": { "tripped": false, "consecutive_regressions": 0, "last_trip": null },
  "complexity_ceiling": { "tripped": false, "trip_count": 0, "last_trip": null },
  "test_degradation": { "tripped": false, "trip_count": 0, "last_trip": null }
}
```

### 4. Rollback Protocol

When OBSERVE detects regression or a circuit breaker trips during IMPLEMENT:

```bash
_safety_rollback() {
    local cycle_id="$1"
    local idea_id="$2"
    local reason="$3"
    local branch="automaton/evolve-${cycle_id}-${idea_id}"

    # 1. Switch back to working branch
    git checkout "$WORKING_BRANCH"

    # 2. Do NOT delete the evolution branch (preserve for debugging)
    log "SAFETY" "Rollback: branch $branch preserved for debugging"

    # 3. Wilt the responsible idea
    _garden_wilt "$idea_id" "Rollback: $reason"

    # 4. Emit quality_concern signal
    _signal_emit "quality_concern" \
        "Implementation of idea-${idea_id} caused regression" \
        "Rollback triggered: $reason"

    # 5. Record in self_modifications.json (spec-22)
    _self_mod_log "rollback" "$cycle_id" "$idea_id" "$reason"

    # 6. Increment circuit breaker counters
    _safety_update_breaker "regression_cascade"
}
```

The rollback protocol ensures:
- The working branch is untouched (branch isolation means nothing to revert)
- The failed idea is wilted so it's not re-attempted without new evidence
- The failure is signaled for future cycles to learn from
- Full audit trail is preserved

### 5. Evolution Safety Guard Hook

A Claude Code hook that runs before every commit during evolution:

File: `.claude/hooks/evolution-safety-guard.sh`

```bash
#!/usr/bin/env bash
# Evolution Safety Guard — runs as pre-commit hook during --evolve
set -euo pipefail

# Only active during evolution mode
[ "${AUTOMATON_EVOLVE:-false}" = "true" ] || exit 0

AUTOMATON_DIR="${1:-.automaton}"

# Check 1: Are we on an evolution branch?
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ ! "$current_branch" =~ ^automaton/evolve- ]]; then
    echo "SAFETY VIOLATION: Evolution commit attempted on non-evolution branch: $current_branch"
    exit 1
fi

# Check 2: Constitutional compliance
if [ -f "$AUTOMATON_DIR/constitution.md" ]; then
    # Run lightweight compliance check
    diff_content=$(git diff --cached)

    # Check for protected function modifications
    protected_functions=$(jq -r '.self_build.protected_functions[]' automaton.config.json 2>/dev/null)
    for func in $protected_functions; do
        if echo "$diff_content" | grep -q "^[-+].*${func}()"; then
            echo "SAFETY WARNING: Protected function '$func' modified. Requires review."
        fi
    done
fi

# Check 3: Scope limits
files_changed=$(git diff --cached --name-only | wc -l)
max_files=$(jq -r '.self_build.max_files_per_iteration // 3' automaton.config.json 2>/dev/null)
if [ "$files_changed" -gt "$max_files" ]; then
    echo "SAFETY VIOLATION: $files_changed files changed (max: $max_files)"
    exit 1
fi

exit 0
```

This hook is registered in `.claude/settings.json` under hooks:

```json
{
  "hooks": {
    "pre-commit": [
      {
        "command": ".claude/hooks/evolution-safety-guard.sh",
        "enabled": true,
        "description": "Evolution safety guard — enforces branch isolation and scope limits"
      }
    ]
  }
}
```

### 6. Pre-Evolution Safety Check

Before the first evolution cycle begins, run a safety preflight:

```bash
_safety_preflight() {
    # 1. Verify clean working tree (no uncommitted changes)
    if ! git diff --quiet HEAD; then
        log "SAFETY" "Working tree has uncommitted changes. Commit or stash before --evolve."
        return 1
    fi

    # 2. Verify test suite passes on current working branch
    local test_results
    test_results=$(_run_test_suite)
    local pass_rate=$(echo "$test_results" | jq '.pass_rate')
    if (( $(echo "$pass_rate < 0.80" | bc -l) )); then
        log "SAFETY" "Test pass rate $pass_rate below minimum 0.80. Fix tests before evolving."
        return 1
    fi

    # 3. Verify constitution exists or can be created
    # 4. Verify budget is sufficient for at least one cycle
    local budget_remaining=$(_budget_get_remaining)
    local min_cycle_cost=1.00  # Minimum expected cycle cost
    if (( $(echo "$budget_remaining < $min_cycle_cost" | bc -l) )); then
        log "SAFETY" "Insufficient budget ($budget_remaining USD) for evolution cycle."
        return 1
    fi

    # 5. Check no circuit breakers are tripped
    if _safety_any_breaker_tripped; then
        log "SAFETY" "Circuit breaker tripped. Reset with --evolve --reset-breakers or investigate."
        return 1
    fi

    return 0
}
```

### 7. Emergency Stop

The human can halt evolution at any time:

- **Ctrl+C**: Graceful shutdown. Current phase completes, state is saved, evolution branch is preserved.
- **`--pause-evolution`** (spec-44): Sets a flag that the evolution loop checks between phases. Halts cleanly.
- **Kill signal**: Abrupt stop. The evolution branch may be in an inconsistent state but the working branch is untouched.

In all cases, the working branch is never corrupted — branch isolation guarantees this.

### 8. Configuration

New `safety` section in `automaton.config.json` (extending the existing `self_build` section):

```json
{
  "safety": {
    "max_total_lines": 15000,
    "max_total_functions": 300,
    "min_test_pass_rate": 0.80,
    "max_consecutive_failures": 3,
    "max_consecutive_regressions": 2,
    "preserve_failed_branches": true,
    "preflight_enabled": true,
    "sandbox_testing_enabled": true
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_total_lines` | number | 15000 | Complexity ceiling for automaton.sh |
| `max_total_functions` | number | 300 | Maximum function count before complexity halt |
| `min_test_pass_rate` | number | 0.80 | Test pass rate floor (breaker trips below this) |
| `max_consecutive_failures` | number | 3 | Consecutive phase failures before error cascade halt |
| `max_consecutive_regressions` | number | 2 | Consecutive regression cycles before cascade halt |
| `preserve_failed_branches` | boolean | true | Keep failed evolution branches for debugging |
| `preflight_enabled` | boolean | true | Run safety preflight before first cycle |
| `sandbox_testing_enabled` | boolean | true | Run sandbox tests before merging |

### 9. Persistent vs Ephemeral Safety State

| File | Persistence | Description |
|------|-------------|-------------|
| `.automaton/evolution/circuit-breakers.json` | Ephemeral | Resets on fresh --evolve (tripped state persists within a run) |
| `.automaton/self_modifications.json` | Persistent | Rollback records accumulate across runs (spec-22/34) |
| `.automaton/votes/` | Persistent | Rejection records provide rollback audit trail (spec-39) |
| `.claude/hooks/evolution-safety-guard.sh` | Persistent | Safety guard hook (committed to repo) |

### 10. Skills for Safety Operations

New skill definitions in `.claude/skills/`:

| Skill File | Description |
|------------|-------------|
| `rollback-executor.md` | Skill for executing manual rollback of a specific evolution cycle |

The rollback executor skill provides a guided process for the human to manually roll back a specific evolution cycle when automatic rollback is insufficient.

## Acceptance Criteria

- [ ] Every IMPLEMENT phase runs on a dedicated `automaton/evolve-{N}-{ID}` branch
- [ ] Working branch is never directly modified during evolution
- [ ] Sandbox testing (syntax + smoke + test suite + compliance) runs before merge
- [ ] Budget ceiling breaker halts cycle when cost exceeds limit
- [ ] Error cascade breaker halts after 3 consecutive phase failures
- [ ] Regression cascade breaker halts after 2 consecutive test regressions
- [ ] Complexity ceiling breaker halts when line/function count exceeds limits
- [ ] Test degradation breaker halts when pass rate drops below minimum
- [ ] Rollback protocol abandons branch, wilts idea, emits signal, and logs audit trail
- [ ] Evolution safety guard hook enforces branch isolation and scope limits
- [ ] Pre-evolution safety preflight validates clean state before first cycle
- [ ] Failed evolution branches preserved for debugging (not deleted)
- [ ] Ctrl+C and --pause-evolution halt evolution cleanly
- [ ] Circuit breaker state tracked and inspectable

## Dependencies

- Depends on: spec-22 (self-build safety — checkpointing, syntax check, smoke test, protected functions)
- Depends on: spec-34 (persistent state — self_modifications.json)
- Depends on: spec-38 (garden — wilt ideas on rollback)
- Depends on: spec-40 (constitution — compliance check in sandbox)
- Depends on: spec-42 (signals — emit quality_concern on rollback)
- Depends on: spec-43 (metrics — test_pass_rate thresholds, complexity ceiling metrics)
- Depended on by: spec-41 (evolution loop — IMPLEMENT branch management, OBSERVE rollback)
- Depended on by: spec-44 (CLI — `--pause-evolution` triggers safety halt)

## Files to Modify

- `automaton.sh` — add safety functions (`_safety_sandbox_test()`, `_safety_rollback()`, `_safety_preflight()`, `_safety_check_breakers()`, `_safety_update_breaker()`, `_safety_any_breaker_tripped()`, `_safety_reset_breakers()`), integrate into evolution IMPLEMENT and OBSERVE phases
- `automaton.config.json` — add `safety` configuration section
- `.claude/hooks/evolution-safety-guard.sh` — new file: pre-commit hook for evolution safety
- `.claude/settings.json` — register evolution-safety-guard hook
- `.claude/skills/rollback-executor.md` — new file: manual rollback skill
- `.gitignore` — add `.automaton/evolution/circuit-breakers.json` as ephemeral state
