#!/usr/bin/env bash
# lib/safety.sh — Safety systems: branch management, circuit breakers, sandboxing, and rollback.
# Spec references: spec-41 (safety branches), spec-44 (safety preflight)

_safety_branch_get_name() {
    local cycle_id="$1"
    local idea_id="$2"
    echo "automaton/evolve-${cycle_id}-${idea_id}"
}

# Create an evolution branch for the IMPLEMENT phase.
# Saves the current branch as WORKING_BRANCH, then creates and switches to
# a new branch named automaton/evolve-{cycle_id}-{idea_id}.
# Returns 0 on success, 1 on failure.
_safety_branch_create() {
    local cycle_id="$1"
    local idea_id="$2"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    # Save the current branch so merge/abandon can return to it
    WORKING_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

    # Refuse to nest evolution branches
    if _safety_branch_is_evolution; then
        log "SAFETY" "ERROR: Already on an evolution branch ($WORKING_BRANCH). Cannot nest."
        return 1
    fi

    if ! git checkout -b "$branch" 2>/dev/null; then
        log "SAFETY" "ERROR: Failed to create evolution branch $branch"
        return 1
    fi

    log "SAFETY" "Created evolution branch $branch (working branch: $WORKING_BRANCH)"
    return 0
}

# Merge the evolution branch back into the working branch.
# Switches to WORKING_BRANCH, merges the evolution branch, then returns.
# Returns 0 on success, 1 on merge failure.
_safety_branch_merge() {
    local cycle_id="$1"
    local idea_id="$2"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    if [ -z "$WORKING_BRANCH" ]; then
        log "SAFETY" "ERROR: No WORKING_BRANCH recorded — cannot merge"
        return 1
    fi

    # Switch back to the working branch
    if ! git checkout "$WORKING_BRANCH" 2>/dev/null; then
        log "SAFETY" "ERROR: Failed to switch to working branch $WORKING_BRANCH"
        return 1
    fi

    # Merge the evolution branch (fast-forward preferred, three-way if needed)
    if ! git merge "$branch" --no-edit 2>/dev/null; then
        log "SAFETY" "ERROR: Merge of $branch into $WORKING_BRANCH failed — resolve manually"
        return 1
    fi

    log "SAFETY" "Merged evolution branch $branch into $WORKING_BRANCH"
    return 0
}

# Abandon the evolution branch without merging.
# Switches back to WORKING_BRANCH and leaves the evolution branch intact
# for debugging — the branch is never deleted.
# Returns 0 on success, 1 on checkout failure.
_safety_branch_abandon() {
    local cycle_id="$1"
    local idea_id="$2"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    if [ -z "$WORKING_BRANCH" ]; then
        log "SAFETY" "ERROR: No WORKING_BRANCH recorded — cannot abandon"
        return 1
    fi

    # Switch back to working branch
    if ! git checkout "$WORKING_BRANCH" 2>/dev/null; then
        log "SAFETY" "ERROR: Failed to switch back to $WORKING_BRANCH during abandon"
        return 1
    fi

    # Do NOT delete the branch — preserved for debugging
    log "SAFETY" "Abandoned evolution branch $branch (preserved for debugging)"
    return 0
}

# Check whether the current branch is an evolution branch.
# Returns 0 if on an evolution branch, 1 otherwise.
_safety_branch_is_evolution() {
    local current
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    [[ "$current" =~ ^automaton/evolve- ]]
}

# ---------------------------------------------------------------------------
# Safety: Sandbox Testing (spec-45 §2)
# ---------------------------------------------------------------------------

# Run the 4-step sandbox validation sequence on an evolution branch before
# merging: (1) syntax check, (2) smoke test, (3) full test suite, (4) test
# pass rate comparison against pre-cycle baseline. Also checks for protected
# function modifications.
#
# Usage: _safety_sandbox_test "automaton/evolve-001-42"
# Returns: 0 if all checks pass, 1 if any check fails
_safety_sandbox_test() {
    local branch="${1:-}"

    # Skip if sandbox testing is disabled
    if [ "${SAFETY_SANDBOX_TESTING_ENABLED:-true}" != "true" ]; then
        log "SAFETY" "Sandbox testing disabled — skipping validation"
        return 0
    fi

    log "SAFETY" "Starting sandbox validation on branch ${branch:-current}"

    # Step 1: Syntax check
    log "SAFETY" "Step 1/4: Syntax check (bash -n automaton.sh)"
    if ! bash -n automaton.sh 2>/dev/null; then
        log "SAFETY" "FAIL: Syntax check failed — automaton.sh has syntax errors"
        return 1
    fi
    log "SAFETY" "Step 1/4: Syntax check passed"

    # Step 2: Smoke test (--dry-run)
    log "SAFETY" "Step 2/4: Smoke test (--dry-run)"
    if ! ./automaton.sh --dry-run >/dev/null 2>&1; then
        log "SAFETY" "FAIL: Smoke test failed — automaton.sh --dry-run returned non-zero"
        return 1
    fi
    log "SAFETY" "Step 2/4: Smoke test passed"

    # Step 3: Full test suite
    log "SAFETY" "Step 3/4: Running full test suite"
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    for test_file in tests/test_*.sh; do
        [ -f "$test_file" ] || continue
        total_tests=$((total_tests + 1))
        if bash "$test_file" >/dev/null 2>&1; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
            log "SAFETY" "Test failed: $test_file"
        fi
    done

    local pass_rate="0.00"
    if [ "$total_tests" -gt 0 ]; then
        pass_rate=$(awk -v p="$passed_tests" -v t="$total_tests" 'BEGIN { printf "%.2f", p/t }')
    fi
    log "SAFETY" "Step 3/4: Test suite complete — $passed_tests/$total_tests passed (rate: $pass_rate)"

    # Step 4: Compare test pass rate against pre-cycle baseline
    log "SAFETY" "Step 4/4: Comparing pass rate against baseline"
    local baseline_snapshot
    baseline_snapshot=$(_metrics_get_latest 2>/dev/null || echo "")

    if [ -n "$baseline_snapshot" ] && [ "$baseline_snapshot" != "null" ]; then
        local baseline_rate
        baseline_rate=$(echo "$baseline_snapshot" | jq -r '.quality.test_pass_rate // 0' 2>/dev/null || echo "0")

        if [ -n "$baseline_rate" ] && [ "$baseline_rate" != "0" ] && [ "$baseline_rate" != "null" ]; then
            local is_regression
            is_regression=$(awk -v current="$pass_rate" -v baseline="$baseline_rate" \
                'BEGIN { print (current < baseline) ? "1" : "0" }')
            if [ "$is_regression" = "1" ]; then
                log "SAFETY" "FAIL: Test regression detected — pass rate $pass_rate < baseline $baseline_rate"
                return 1
            fi
        fi
    fi
    log "SAFETY" "Step 4/4: Pass rate check passed"

    # Step 5: Check for protected function modifications
    if [ -n "$branch" ]; then
        local working="${WORKING_BRANCH:-master}"
        IFS=',' read -ra protected <<< "${SELF_BUILD_PROTECTED_FUNCTIONS:-run_orchestration,_handle_shutdown}"
        for func in "${protected[@]}"; do
            local changes
            changes=$(git diff "${working}...${branch}" -- automaton.sh 2>/dev/null | grep -c "^[-+].*${func}()" || true)
            if [ "${changes:-0}" -gt 0 ]; then
                log "SAFETY" "FAIL: Protected function '${func}' modified without explicit approval"
                return 1
            fi
        done
        log "SAFETY" "Protected function check passed"
    fi

    log "SAFETY" "Sandbox validation passed — all checks successful"
    return 0
}

# ---------------------------------------------------------------------------
# Safety: Circuit Breakers (spec-45 §2)
# ---------------------------------------------------------------------------

# Path to the circuit breakers state file (ephemeral, resets each evolution run).
_BREAKERS_FILE="${AUTOMATON_DIR:-.automaton}/evolution/circuit-breakers.json"

# Initialize the circuit breakers state file with all 5 breakers in un-tripped state.
# Called by _safety_reset_breakers and on first access when the file does not exist.
_safety_init_breakers_file() {
    local dir
    dir="$(dirname "$_BREAKERS_FILE")"
    mkdir -p "$dir"
    cat > "$_BREAKERS_FILE" <<'BREAKERS_EOF'
{
  "budget_ceiling": { "tripped": false, "trip_count": 0, "last_trip": null },
  "error_cascade": { "tripped": false, "consecutive_failures": 0, "last_trip": null },
  "regression_cascade": { "tripped": false, "consecutive_regressions": 0, "last_trip": null },
  "complexity_ceiling": { "tripped": false, "trip_count": 0, "last_trip": null },
  "test_degradation": { "tripped": false, "trip_count": 0, "last_trip": null }
}
BREAKERS_EOF
}

# Ensure the breakers file exists, creating it with defaults if needed.
_safety_ensure_breakers_file() {
    if [ ! -f "$_BREAKERS_FILE" ]; then
        _safety_init_breakers_file
    fi
}

# Check all 5 circuit breakers against current system state and trip any that
# exceed their thresholds. This is called during evolution cycles to detect
# safety violations proactively.
#
# Breakers checked:
#   1. budget_ceiling   — evolution cycle cost exceeds max_cost_per_cycle_usd
#   2. error_cascade    — consecutive_failures >= SAFETY_MAX_CONSECUTIVE_FAILURES
#   3. regression_cascade — consecutive_regressions >= SAFETY_MAX_CONSECUTIVE_REGRESSIONS
#   4. complexity_ceiling — automaton.sh lines > SAFETY_MAX_TOTAL_LINES or
#                           function count > SAFETY_MAX_TOTAL_FUNCTIONS
#   5. test_degradation — test pass rate < SAFETY_MIN_TEST_PASS_RATE
#
# Returns: 0 always (tripped breakers are recorded in state, use
#          _safety_any_breaker_tripped to check)
_safety_check_breakers() {
    _safety_ensure_breakers_file

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # --- 1. Budget ceiling ---
    # Budget ceiling is checked externally by _evolve_check_budget (spec-41).
    # Here we just read the state — it is tripped by _safety_update_breaker.

    # --- 2. Error cascade ---
    local consecutive_failures
    consecutive_failures=$(jq -r '.error_cascade.consecutive_failures // 0' "$_BREAKERS_FILE")
    if [ "$consecutive_failures" -ge "${SAFETY_MAX_CONSECUTIVE_FAILURES:-3}" ]; then
        jq --arg ts "$now" '.error_cascade.tripped = true | .error_cascade.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: error_cascade ($consecutive_failures consecutive failures)"
    fi

    # --- 3. Regression cascade ---
    local consecutive_regressions
    consecutive_regressions=$(jq -r '.regression_cascade.consecutive_regressions // 0' "$_BREAKERS_FILE")
    if [ "$consecutive_regressions" -ge "${SAFETY_MAX_CONSECUTIVE_REGRESSIONS:-2}" ]; then
        jq --arg ts "$now" '.regression_cascade.tripped = true | .regression_cascade.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: regression_cascade ($consecutive_regressions consecutive regressions)"
    fi

    # --- 4. Complexity ceiling ---
    local total_lines=0 total_functions=0
    if [ -f "automaton.sh" ]; then
        total_lines=$(wc -l < automaton.sh)
        total_functions=$(grep -c '^[a-zA-Z_][a-zA-Z0-9_]*()' automaton.sh || true)
    fi
    if [ "$total_lines" -gt "${SAFETY_MAX_TOTAL_LINES:-15000}" ] || \
       [ "$total_functions" -gt "${SAFETY_MAX_TOTAL_FUNCTIONS:-300}" ]; then
        jq --arg ts "$now" \
            '.complexity_ceiling.tripped = true | .complexity_ceiling.trip_count += 1 | .complexity_ceiling.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: complexity_ceiling (lines=$total_lines, functions=$total_functions)"
    fi

    # --- 5. Test degradation ---
    local pass_rate="1.00"
    local latest_snapshot
    latest_snapshot=$(_metrics_get_latest 2>/dev/null || echo "")
    if [ -n "$latest_snapshot" ] && [ "$latest_snapshot" != "null" ]; then
        pass_rate=$(echo "$latest_snapshot" | jq -r '.quality.test_pass_rate // 1.0' 2>/dev/null || echo "1.00")
    fi
    local is_degraded
    is_degraded=$(awk -v rate="$pass_rate" -v min="${SAFETY_MIN_TEST_PASS_RATE:-0.80}" \
        'BEGIN { print (rate < min) ? "1" : "0" }')
    if [ "$is_degraded" = "1" ]; then
        jq --arg ts "$now" \
            '.test_degradation.tripped = true | .test_degradation.trip_count += 1 | .test_degradation.last_trip = $ts' \
            "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
        log "SAFETY" "BREAKER TRIPPED: test_degradation (pass_rate=$pass_rate < min=${SAFETY_MIN_TEST_PASS_RATE:-0.80})"
    fi

    return 0
}

# Update a specific circuit breaker after an event (phase failure, regression,
# budget exceeded). Increments the appropriate counter and trips the breaker
# if the threshold is reached.
#
# Usage: _safety_update_breaker "error_cascade"
#        _safety_update_breaker "regression_cascade"
#        _safety_update_breaker "budget_ceiling"
#        _safety_update_breaker "complexity_ceiling"
#        _safety_update_breaker "test_degradation"
# Returns: 0 on success, 1 on unknown breaker name
_safety_update_breaker() {
    local breaker_name="$1"
    _safety_ensure_breakers_file

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    case "$breaker_name" in
        budget_ceiling)
            jq --arg ts "$now" \
                '.budget_ceiling.tripped = true | .budget_ceiling.trip_count += 1 | .budget_ceiling.last_trip = $ts' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            log "SAFETY" "BREAKER TRIPPED: budget_ceiling"
            ;;
        error_cascade)
            jq --arg ts "$now" \
                '.error_cascade.consecutive_failures += 1' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            # Check if threshold reached
            local failures
            failures=$(jq -r '.error_cascade.consecutive_failures' "$_BREAKERS_FILE")
            if [ "$failures" -ge "${SAFETY_MAX_CONSECUTIVE_FAILURES:-3}" ]; then
                jq --arg ts "$now" \
                    '.error_cascade.tripped = true | .error_cascade.last_trip = $ts' \
                    "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
                log "SAFETY" "BREAKER TRIPPED: error_cascade ($failures consecutive failures)"
            else
                log "SAFETY" "error_cascade: $failures consecutive failures (threshold: ${SAFETY_MAX_CONSECUTIVE_FAILURES:-3})"
            fi
            ;;
        regression_cascade)
            jq --arg ts "$now" \
                '.regression_cascade.consecutive_regressions += 1' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            # Check if threshold reached
            local regressions
            regressions=$(jq -r '.regression_cascade.consecutive_regressions' "$_BREAKERS_FILE")
            if [ "$regressions" -ge "${SAFETY_MAX_CONSECUTIVE_REGRESSIONS:-2}" ]; then
                jq --arg ts "$now" \
                    '.regression_cascade.tripped = true | .regression_cascade.last_trip = $ts' \
                    "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
                log "SAFETY" "BREAKER TRIPPED: regression_cascade ($regressions consecutive regressions)"
            else
                log "SAFETY" "regression_cascade: $regressions consecutive regressions (threshold: ${SAFETY_MAX_CONSECUTIVE_REGRESSIONS:-2})"
            fi
            ;;
        complexity_ceiling)
            jq --arg ts "$now" \
                '.complexity_ceiling.tripped = true | .complexity_ceiling.trip_count += 1 | .complexity_ceiling.last_trip = $ts' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            log "SAFETY" "BREAKER TRIPPED: complexity_ceiling"
            ;;
        test_degradation)
            jq --arg ts "$now" \
                '.test_degradation.tripped = true | .test_degradation.trip_count += 1 | .test_degradation.last_trip = $ts' \
                "$_BREAKERS_FILE" > "${_BREAKERS_FILE}.tmp" && mv "${_BREAKERS_FILE}.tmp" "$_BREAKERS_FILE"
            log "SAFETY" "BREAKER TRIPPED: test_degradation"
            ;;
        *)
            log "SAFETY" "ERROR: Unknown breaker name: $breaker_name"
            return 1
            ;;
    esac
    return 0
}

# Check if any circuit breaker is currently tripped.
# Returns: 0 if at least one breaker is tripped, 1 if none are tripped
_safety_any_breaker_tripped() {
    _safety_ensure_breakers_file

    local tripped_count
    tripped_count=$(jq '[.[] | select(.tripped == true)] | length' "$_BREAKERS_FILE" 2>/dev/null || echo 0)
    [ "$tripped_count" -gt 0 ]
}

# Reset all circuit breakers to un-tripped state with zero counters.
# Called on fresh --evolve start or with --evolve --reset-breakers.
_safety_reset_breakers() {
    _safety_init_breakers_file
    log "SAFETY" "All circuit breakers reset"
}

# ---------------------------------------------------------------------------
# Rollback Protocol (spec-45 §4)
# ---------------------------------------------------------------------------

# Execute the rollback protocol when OBSERVE detects regression or a circuit
# breaker trips during IMPLEMENT. This is the recovery mechanism — it ensures
# every failure is recorded, signaled, and learned from while leaving the
# codebase untouched.
#
# Steps:
#   1. Switch back to the working branch (abandon evolution branch)
#   2. Preserve the failed evolution branch for debugging (never delete)
#   3. Wilt the responsible idea so it is not re-attempted without new evidence
#   4. Emit a quality_concern signal for future cycles to learn from
#   5. Log the rollback event to self_modifications.json (audit trail)
#   6. Increment regression_cascade circuit breaker counter
#
# Args: cycle_id idea_id reason
# Returns: 0 on success, 1 if branch abandon fails
_safety_rollback() {
    local cycle_id="${1:?_safety_rollback requires cycle_id}"
    local idea_id="${2:?_safety_rollback requires idea_id}"
    local reason="${3:?_safety_rollback requires reason}"
    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    log "SAFETY" "Rollback initiated: cycle=$cycle_id idea=$idea_id reason=$reason"

    # 1. Switch back to working branch (preserves evolution branch for debugging)
    if ! _safety_branch_abandon "$cycle_id" "$idea_id"; then
        log "SAFETY" "Rollback: WARNING — failed to abandon branch $branch"
        return 1
    fi

    # 2. Branch preserved by _safety_branch_abandon (it never deletes)
    log "SAFETY" "Rollback: branch $branch preserved for debugging"

    # 3. Wilt the responsible idea
    _garden_wilt "$idea_id" "Rollback: $reason" 2>/dev/null || true

    # 4. Emit quality_concern signal
    _signal_emit "quality_concern" \
        "Implementation of idea-${idea_id} caused regression" \
        "Rollback triggered: $reason" \
        "safety" "$cycle_id" "" 2>/dev/null || true

    # 5. Record in self_modifications.json (audit trail)
    local audit_file="$AUTOMATON_DIR/self_modifications.json"
    [ -f "$audit_file" ] || echo '[]' > "$audit_file"
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$now" --arg cid "$cycle_id" --arg iid "$idea_id" \
       --arg rsn "$reason" --arg br "$branch" \
       '. + [{timestamp:$ts, action:"rollback", cycle_id:$cid, idea_id:$iid, reason:$rsn, branch:$br}]' \
       "$audit_file" > "${audit_file}.tmp" && mv "${audit_file}.tmp" "$audit_file"

    # 6. Increment circuit breaker counters (regression_cascade)
    _safety_update_breaker "regression_cascade"

    log "SAFETY" "Rollback complete: cycle=$cycle_id idea=$idea_id"
    return 0
}

# ---------------------------------------------------------------------------
# Pre-Evolution Safety Preflight (spec-45 §6)
# ---------------------------------------------------------------------------

# Validates all preconditions before the first evolution cycle begins.
# Checks: clean working tree, test pass rate above minimum, constitution
# exists or can be created, sufficient budget for at least one cycle, and
# no tripped circuit breakers.
#
# Returns: 0 if all checks pass, 1 if any check fails
_safety_preflight() {
    # Skip if preflight is disabled
    if [ "${SAFETY_PREFLIGHT_ENABLED:-true}" != "true" ]; then
        log "SAFETY" "Preflight check disabled — skipping"
        return 0
    fi

    log "SAFETY" "Starting pre-evolution safety preflight"

    # 1. Verify clean working tree (no uncommitted changes)
    if ! git diff --quiet HEAD 2>/dev/null; then
        log "SAFETY" "PREFLIGHT FAIL: Working tree has uncommitted changes. Commit or stash before --evolve."
        return 1
    fi
    log "SAFETY" "Preflight 1/5: Clean working tree — passed"

    # 2. Verify test suite passes on current working branch
    local total_tests=0
    local passed_tests=0

    for test_file in tests/test_*.sh; do
        [ -f "$test_file" ] || continue
        total_tests=$((total_tests + 1))
        if bash "$test_file" >/dev/null 2>&1; then
            passed_tests=$((passed_tests + 1))
        fi
    done

    local pass_rate="0.00"
    if [ "$total_tests" -gt 0 ]; then
        pass_rate=$(awk -v p="$passed_tests" -v t="$total_tests" 'BEGIN { printf "%.2f", p/t }')
    fi

    local min_rate="${SAFETY_MIN_TEST_PASS_RATE:-0.80}"
    local below_min
    below_min=$(awk -v rate="$pass_rate" -v min="$min_rate" 'BEGIN { print (rate < min) ? "1" : "0" }')
    if [ "$below_min" = "1" ]; then
        log "SAFETY" "PREFLIGHT FAIL: Test pass rate $pass_rate below minimum $min_rate. Fix tests before evolving."
        return 1
    fi
    log "SAFETY" "Preflight 2/5: Test pass rate $pass_rate >= $min_rate — passed"

    # 3. Verify constitution exists or can be created
    local constitution_file="$AUTOMATON_DIR/constitution.md"
    if [ ! -f "$constitution_file" ]; then
        log "SAFETY" "Preflight 3/5: Constitution not found — will be created during first cycle"
    else
        log "SAFETY" "Preflight 3/5: Constitution exists — passed"
    fi

    # 4. Verify budget is sufficient for at least one cycle
    local budget_file="$AUTOMATON_DIR/budget.json"
    local budget_remaining="999.00"
    if [ -f "$budget_file" ]; then
        budget_remaining=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
            "$budget_file" 2>/dev/null || echo "999.00")
    fi
    local min_cycle_cost="1.00"
    local budget_insufficient
    budget_insufficient=$(awk -v rem="$budget_remaining" -v min="$min_cycle_cost" \
        'BEGIN { print (rem < min) ? "1" : "0" }')
    if [ "$budget_insufficient" = "1" ]; then
        log "SAFETY" "PREFLIGHT FAIL: Insufficient budget (\$${budget_remaining} USD) for evolution cycle (minimum \$${min_cycle_cost})."
        return 1
    fi
    log "SAFETY" "Preflight 4/5: Budget \$${budget_remaining} sufficient — passed"

    # 5. Check no circuit breakers are tripped
    if _safety_any_breaker_tripped; then
        log "SAFETY" "PREFLIGHT FAIL: Circuit breaker tripped. Reset with --evolve --reset-breakers or investigate."
        return 1
    fi
    log "SAFETY" "Preflight 5/5: No circuit breakers tripped — passed"

    log "SAFETY" "Pre-evolution safety preflight complete — all checks passed"
    return 0
}
