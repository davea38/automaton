#!/usr/bin/env bash
# lib/errors.sh — Error classification, rate-limit handling, crash recovery, and stall detection.
# Spec references: spec-08 (error handling), spec-09 (test failure escalation),
#                  spec-10 (rate limiting), spec-11 (stall detection)

handle_rate_limit() {
    local delay="$RATE_COOLDOWN_SECONDS"

    local max_retries="${RATE_MAX_RETRIES:-5}"
    for ((attempt = 1; attempt <= max_retries; attempt++)); do
        log "ORCHESTRATOR" "Rate limit detected. Backing off ${delay}s (attempt ${attempt}/${max_retries})"
        sleep "$delay"

        # Retry — the called function sets AGENT_RESULT and AGENT_EXIT_CODE
        "$@"

        if [ "${AGENT_EXIT_CODE:-1}" -eq 0 ]; then
            log "ORCHESTRATOR" "Rate limit retry succeeded."
            return 0
        fi

        # If the error is no longer rate-limit-related, stop retrying here
        if ! echo "${AGENT_RESULT:-}" | grep -qi 'rate_limit\|429\|overloaded\|rate limit'; then
            log "ORCHESTRATOR" "Retry failed with non-rate-limit error (exit ${AGENT_EXIT_CODE})."
            return 1
        fi

        # Exponential backoff capped at max_backoff_seconds
        delay=$(awk -v d="$delay" -v m="$RATE_BACKOFF_MULTIPLIER" -v cap="$RATE_MAX_BACKOFF_SECONDS" \
            'BEGIN { nd = int(d * m); print (nd > cap) ? cap : nd }')
    done

    # All retries exhausted — enter extended pause
    local extended_pause="${RATE_EXTENDED_PAUSE_SECONDS:-600}"
    log "ORCHESTRATOR" "Persistent rate limiting. Pausing for ${extended_pause}s."
    write_state
    sleep "$extended_pause"

    return 1
}

# Proactive pacing: calculates token velocity over the last 3 iterations from
# budget.json history and sleeps if velocity exceeds 80% of tokens_per_minute.
# This avoids rate limits by slowing down before hitting them.
# When parallel_builders > 1, the per-builder share of TPM is used as the limit.
#
# Returns: 0 always (pacing is advisory, never fatal)
check_pacing() {
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ ! -f "$budget_file" ]; then
        return 0
    fi

    local history_len
    history_len=$(jq '.history | length' "$budget_file")
    if [ "$history_len" -lt 1 ]; then
        return 0
    fi

    # Use last 3 iterations (or fewer if not enough history)
    local window=3
    if [ "$history_len" -lt "$window" ]; then
        window="$history_len"
    fi

    # Sum tokens and duration over the window
    local recent
    recent=$(jq --argjson w "$window" '
        .history[-$w:] |
        {
            tokens: (map(.input_tokens + .output_tokens) | add),
            duration: (map(.duration_seconds) | add)
        }
    ' "$budget_file")

    local recent_tokens recent_duration
    recent_tokens=$(echo "$recent" | jq '.tokens')
    recent_duration=$(echo "$recent" | jq '.duration')

    # Guard against zero/null duration (avoid division by zero)
    if [ -z "$recent_duration" ] || [ "$recent_duration" = "null" ] || [ "$recent_duration" = "0" ]; then
        return 0
    fi

    # Adjust limit for parallel builders
    local effective_tpm="$RATE_TOKENS_PER_MINUTE"
    if [ "${EXEC_PARALLEL_BUILDERS:-1}" -gt 1 ]; then
        effective_tpm=$((RATE_TOKENS_PER_MINUTE / EXEC_PARALLEL_BUILDERS))
    fi

    # Calculate velocity and 80% threshold using awk for floating-point math
    local should_pace cooldown_secs velocity_display
    read -r should_pace cooldown_secs velocity_display < <(
        awk -v tokens="$recent_tokens" -v dur="$recent_duration" \
            -v tpm="$effective_tpm" \
            'BEGIN {
                velocity = tokens * 60 / dur
                threshold = tpm * 0.80
                if (velocity > threshold) {
                    # Time needed to consume these tokens at the TPM limit
                    needed = tokens * 60 / tpm
                    cooldown = needed - dur
                    if (cooldown < 1) cooldown = 1
                    printf "yes %.0f %.0f\n", cooldown, velocity
                } else {
                    printf "no 0 %.0f\n", velocity
                }
            }'
    )

    if [ "$should_pace" = "yes" ]; then
        log "ORCHESTRATOR" "Proactive pacing: velocity ${velocity_display} TPM, waiting ${cooldown_secs}s."
        sleep "$cooldown_secs"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Error Handling & Recovery
# ---------------------------------------------------------------------------

# Handles a CLI crash (non-zero exit that is NOT a rate limit or network error).
# Increments consecutive_failures counter, sleeps for retry_delay, and returns 0
# to signal "retry this iteration". If max consecutive failures is reached, saves
# state and exits with code 1 (resumable).
#
# The caller is responsible for classifying the error first (is_rate_limit /
# is_network_error) and only calling this function for unclassified CLI failures.
#
# Usage: handle_cli_crash exit_code [agent_output]
# Returns: 0 = retry the iteration
# Exits:   1 = max consecutive failures reached (state saved for --resume)
handle_cli_crash() {
    local exit_code="$1"
    local agent_output="${2:-}"

    consecutive_failures=$((consecutive_failures + 1))
    log "ORCHESTRATOR" "CLI error (exit $exit_code), attempt $consecutive_failures/$EXEC_MAX_CONSECUTIVE_FAILURES"

    if [ "$consecutive_failures" -ge "$EXEC_MAX_CONSECUTIVE_FAILURES" ]; then
        log "ORCHESTRATOR" "Max consecutive failures reached ($EXEC_MAX_CONSECUTIVE_FAILURES). Saving state."
        write_state
        exit 1
    fi

    log "ORCHESTRATOR" "Retrying in ${EXEC_RETRY_DELAY_SECONDS}s..."
    sleep "$EXEC_RETRY_DELAY_SECONDS"
    return 0
}

# Resets the consecutive failure counter after a successful agent iteration.
# Should be called at the end of every successful iteration so that subsequent
# failures start counting from zero. Only logs when recovering from prior failures.
#
# Usage: reset_failure_count
reset_failure_count() {
    if [ "$consecutive_failures" -gt 0 ]; then
        log "ORCHESTRATOR" "Recovered after $consecutive_failures failure(s). Resetting counter."
    fi
    consecutive_failures=0
}

# Classifies whether agent output indicates an API rate limit error.
# Checks for known Anthropic rate limit signatures in the output text.
# Usage: if is_rate_limit "$agent_output"; then ...
# Returns: 0 if rate limit detected, 1 otherwise
is_rate_limit() {
    local output="${1:-}"
    echo "$output" | grep -qi 'rate_limit\|rate limit\|429\|overloaded'
}

# Classifies whether agent output indicates a network/connectivity error.
# Checks for known network failure signatures in the output text.
# Usage: if is_network_error "$agent_output"; then ...
# Returns: 0 if network error detected, 1 otherwise
is_network_error() {
    local output="${1:-}"
    echo "$output" | grep -qi 'network\|connection\|timeout\|ECONNREFUSED\|ETIMEDOUT\|ENOTFOUND\|EHOSTUNREACH\|getaddrinfo'
}

# Classifies whether agent output indicates a test failure.
# Checks for common test failure patterns across popular test frameworks.
# Usage: if is_test_failure "$agent_output"; then ...
# Returns: 0 if test failure detected, 1 otherwise
is_test_failure() {
    local output="${1:-}"
    echo "$output" | grep -qi 'tests\? failed\|test.*fail\|FAIL:\|failing tests\|assertion.*error\|AssertionError\|expected.*but.*received\|npm test.*exit code\|jest.*failed\|pytest.*failed\|test suite failed'
}

# Plan corruption guard: checkpoint IMPLEMENTATION_PLAN.md before each iteration
# so we can detect if an agent rewrites the plan and destroys completed work.
# Sets PLAN_CHECKPOINT_COMPLETED_COUNT for post-iteration comparison.
#
# Usage: checkpoint_plan   (call before each iteration)
checkpoint_plan() {
    if [ ! -f "IMPLEMENTATION_PLAN.md" ]; then
        PLAN_CHECKPOINT_COMPLETED_COUNT=0
        return 0
    fi

    cp IMPLEMENTATION_PLAN.md "$AUTOMATON_DIR/plan_checkpoint.md"
    PLAN_CHECKPOINT_COMPLETED_COUNT=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null) || PLAN_CHECKPOINT_COMPLETED_COUNT=0
}

# Plan corruption guard: verify that the [x] count did not decrease after an
# iteration. If it did, the agent rewrote the plan and lost completed tasks —
# restore from the pre-iteration checkpoint.
#
# After 2 corruption events, escalates to human (exit 3).
#
# Usage: check_plan_integrity   (call after each iteration)
# Returns: 0 = plan is intact or was restored successfully
# Exits:   3 via escalate() if corruption_count reaches 2
check_plan_integrity() {
    if [ ! -f "IMPLEMENTATION_PLAN.md" ]; then
        return 0
    fi

    local completed_after
    completed_after=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null) || completed_after=0

    if [ "$completed_after" -lt "$PLAN_CHECKPOINT_COMPLETED_COUNT" ]; then
        log "ORCHESTRATOR" "PLAN CORRUPTION: completed count dropped from $PLAN_CHECKPOINT_COMPLETED_COUNT to $completed_after"

        # Restore from checkpoint
        cp "$AUTOMATON_DIR/plan_checkpoint.md" IMPLEMENTATION_PLAN.md
        git add IMPLEMENTATION_PLAN.md 2>/dev/null || true
        git commit -m "automaton: restore plan from corruption" 2>/dev/null || true
        log "ORCHESTRATOR" "Plan restored from checkpoint."

        corruption_count=$((corruption_count + 1))
        if [ "$corruption_count" -ge 2 ]; then
            escalate "Plan corruption detected twice. Agent may be rewriting the plan."
            # escalate() exits — control never reaches here
        fi
    fi

    return 0
}

# Stall detection: checks whether the last build iteration produced any code
# changes by inspecting `git diff --stat HEAD~1`. If the diff is empty, the
# agent claimed progress without modifying files — a "stall".
#
# After stall_threshold consecutive stalls, forces a re-plan (return 1).
# After 2 re-plans that still lead to stalls, escalates to human (exit 3).
# Resets stall_count on any detected change.
#
# Usage: check_stall
# Returns: 0 = continue normally, 1 = force re-plan (transition to plan phase)
# Exits:   3 via escalate() if re-planning has failed twice
check_stall() {
    local diff_stat
    diff_stat=$(git diff --stat HEAD~1 2>/dev/null || true)

    if [ -z "$diff_stat" ]; then
        stall_count=$((stall_count + 1))
        log "ORCHESTRATOR" "Stall detected ($stall_count/$EXEC_STALL_THRESHOLD). No code changes."
    else
        stall_count=0
        return 0
    fi

    if [ "$stall_count" -ge "$EXEC_STALL_THRESHOLD" ]; then
        # Check if we've already re-planned too many times
        if [ "$replan_count" -ge 2 ]; then
            escalate "Agent stalled after $replan_count re-plans. Manual intervention required."
            # escalate() exits — control never reaches here
        fi

        log "ORCHESTRATOR" "$EXEC_STALL_THRESHOLD consecutive stalls. Forcing re-plan."
        stall_count=0
        replan_count=$((replan_count + 1))
        return 1
    fi

    return 0
}

# Repeated test failure detection (spec-09, Error #8): tracks consecutive build
# iterations where the agent output indicates test failures. If the same failure
# pattern persists across 3 iterations, the agent is stuck and we escalate to
# the review phase for independent diagnosis.
#
# Resets test_failure_count on iterations without test failure indicators.
#
# Usage: check_test_failures "$agent_output"
# Returns: 0 = continue normally, 1 = force transition to review phase
check_test_failures() {
    local agent_output="${1:-}"

    if is_test_failure "$agent_output"; then
        test_failure_count=$((test_failure_count + 1))
        log "ORCHESTRATOR" "Test failure detected ($test_failure_count/3). Agent output contains test failure indicators."
    else
        if [ "$test_failure_count" -gt 0 ]; then
            log "ORCHESTRATOR" "Test failures cleared after $test_failure_count iteration(s)."
        fi
        test_failure_count=0
        return 0
    fi

    if [ "$test_failure_count" -ge 3 ]; then
        log "ORCHESTRATOR" "Repeated test failures across 3 iterations. Escalating to review phase."
        test_failure_count=0
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Self-Build Safety (spec-22)
# ---------------------------------------------------------------------------

# List of orchestrator files to track during self-build.
SELF_BUILD_FILES="automaton.sh PROMPT_converse.md PROMPT_research.md PROMPT_plan.md PROMPT_build.md PROMPT_review.md automaton.config.json bin/cli.js"

# Computes sha256 checksums of all orchestrator files and stores them in
# .automaton/self_checksums.json. Called before each build iteration when
# self_build.enabled is true.
#
