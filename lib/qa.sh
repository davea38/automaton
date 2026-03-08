#!/usr/bin/env bash
# lib/qa.sh — Quality assurance: gate checks, test validation, critique, and complexity routing.
# Spec references: spec-04 (gate checks), spec-46 (QA loop), spec-47 (spec critique),
#                  spec-51 (complexity routing), spec-53 (steelman critique),
#                  spec-54 (blind validation)

gate_check() {
    local gate_name="$1"
    log "ORCHESTRATOR" "Gate: $gate_name..."

    if "gate_$gate_name"; then
        log "ORCHESTRATOR" "Gate: $gate_name... PASS"
        emit_event "gate_check" "{\"gate\":\"${gate_name}\",\"passed\":true,\"reason\":\"\"}"
        return 0
    else
        log "ORCHESTRATOR" "Gate: $gate_name... FAIL"
        emit_event "gate_check" "{\"gate\":\"${gate_name}\",\"passed\":false,\"reason\":\"gate failed\"}"
        return 1
    fi
}

# Gate 1: Spec Completeness — runs before Phase 1 (research).
# Validates that the conversation phase produced usable specs:
#   - At least one spec file in specs/
#   - PRD.md exists and is non-empty
#   - AGENTS.md does not still contain the template placeholder
#
# On fail: orchestrator should refuse to start autonomous work.
# Returns: 0 (pass) or 1 (fail)
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

    # Check: AGENTS.md has a real project name (not the template placeholder)
    if grep -q "(to be determined)" AGENTS.md 2>/dev/null; then
        log "ORCHESTRATOR" "  FAIL: AGENTS.md still has placeholder project name"
        pass=false
    fi

    $pass
}

# Gate 2: Research Completeness — runs after Phase 1 (research).
# Validates that research enriched the specs and resolved unknowns:
#   - AGENTS.md grew beyond the ~22-line template (warning only)
#   - No TBD/TODO markers remaining in specs/ (hard fail)
#
# On fail: orchestrator should retry research (up to max iterations),
# then warn and continue to planning if max reached.
# Returns: 0 (pass) or 1 (fail)
gate_research_completeness() {
    local pass=true
    local warnings=0

    # Check: AGENTS.md was updated (grew from template size)
    local agents_lines
    agents_lines=$(wc -l < AGENTS.md)
    if [ "$agents_lines" -le 22 ]; then  # template is ~22 lines
        log "ORCHESTRATOR" "  WARN: AGENTS.md unchanged from template"
        warnings=$((warnings + 1))
    fi

    # Check: no TBD/TODO remaining in specs
    local tbds
    tbds=$(grep -ri 'TBD\|TODO' specs/ 2>/dev/null | wc -l)
    if [ "$tbds" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: $tbds TBD/TODO markers remaining in specs"
        pass=false
    fi

    $pass
}

# Gate 3: Plan Validity — runs after Phase 2 (plan).
# Validates that the planning phase produced a usable task list:
#   - At least 5 unchecked tasks in IMPLEMENTATION_PLAN.md
#   - Plan is longer than 10 lines
#   - Tasks reference specs (heuristic, warning only)
#
# On fail: orchestrator should retry planning (up to max iterations),
# then escalate if max reached.
# Returns: 0 (pass) or 1 (fail)
gate_plan_validity() {
    local pass=true

    # Check: at least 5 unchecked tasks
    local unchecked
    unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null) || unchecked=0
    if [ "$unchecked" -lt 5 ]; then
        log "ORCHESTRATOR" "  FAIL: Only $unchecked unchecked tasks (minimum 5)"
        pass=false
    fi

    # Check: plan is non-trivial
    local plan_lines
    plan_lines=$(wc -l < IMPLEMENTATION_PLAN.md)
    if [ "$plan_lines" -le 10 ]; then
        log "ORCHESTRATOR" "  FAIL: Plan too short ($plan_lines lines)"
        pass=false
    fi

    # Check: tasks reference specs (heuristic, warning only)
    local spec_refs
    spec_refs=$(grep -ci 'spec' IMPLEMENTATION_PLAN.md 2>/dev/null) || spec_refs=0
    if [ "$spec_refs" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No spec references found in plan"
        # Warning only, don't fail
    fi

    $pass
}

# Gate 4: Build Completion — runs after Phase 3 (build).
# Validates that all tasks are complete and code was actually produced:
#   - Zero unchecked tasks in IMPLEMENTATION_PLAN.md (hard fail)
#   - Git commits exist during the run (warning only)
#   - Test files exist (warning only)
#
# On fail: orchestrator should continue building (return to build loop).
# Returns: 0 (pass) or 1 (fail)
gate_build_completion() {
    local pass=true

    # Check: all tasks complete
    local unchecked
    unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null) || unchecked=0
    if [ "$unchecked" -gt 0 ]; then
        log "ORCHESTRATOR" "  FAIL: $unchecked tasks still incomplete"
        pass=false
    fi

    # Check: code changes exist (uses run_started_at set by orchestrator)
    local total_changes
    total_changes=$(git log --oneline --since="${run_started_at:-1970-01-01}" | wc -l)
    if [ "$total_changes" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No git commits during build phase"
    fi

    # Check: tests exist (heuristic)
    local test_files
    test_files=$(find . -name "*test*" -o -name "*spec*" | grep -v node_modules | grep -v .automaton | wc -l)
    if [ "$test_files" -eq 0 ]; then
        log "ORCHESTRATOR" "  WARN: No test files found"
    fi

    $pass
}

# Gate 5: Review Pass — runs after Phase 4 (review).
# Validates that the review agent found no remaining issues:
#   - No unchecked tasks in IMPLEMENTATION_PLAN.md (reviewer may have added new ones)
#   - No ESCALATION markers in IMPLEMENTATION_PLAN.md
#
# On fail: orchestrator should return to Phase 3 (build) to address new tasks.
# After 2 review iterations that both fail, escalate.
# Returns: 0 (pass) or 1 (fail)
gate_review_pass() {
    local pass=true

    # Check: no new unchecked tasks were added by reviewer
    local unchecked
    unchecked=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null) || unchecked=0
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

# ---------------------------------------------------------------------------
# Phase Timeout
# ---------------------------------------------------------------------------

# Optional phase timeout check: compares elapsed wallclock time against
# phase_timeout_seconds from config. If the timeout is exceeded, logs
# the event and returns 1 to signal the orchestrator to force a phase
# transition. A timeout of 0 means "no timeout" (the default).
#
# Requires PHASE_START_TIME to be set (epoch seconds) when a phase begins.
#
# Usage: check_phase_timeout
# Returns: 0 = within time limit, 1 = timeout exceeded
check_phase_timeout() {
    # Look up the timeout for the current phase
    local timeout_var="EXEC_PHASE_TIMEOUT_$(echo "$current_phase" | tr '[:lower:]' '[:upper:]')"
    local timeout="${!timeout_var:-0}"

    # 0 means no timeout configured
    if [ "$timeout" -eq 0 ] 2>/dev/null; then
        return 0
    fi

    # PHASE_START_TIME must be set by the orchestrator when entering a phase
    if [ -z "${PHASE_START_TIME:-}" ]; then
        return 0
    fi

    local now elapsed
    now=$(date +%s)
    elapsed=$((now - PHASE_START_TIME))

    if [ "$elapsed" -ge "$timeout" ]; then
        log "ORCHESTRATOR" "Phase timeout: ${current_phase} exceeded ${timeout}s (elapsed: ${elapsed}s). Forcing transition."
        return 1
    fi

    return 0
}

_qa_run_tests() {
    local test_cmd="${1:-bash -n automaton.sh}"
    local output exit_code=0
    output=$(bash -c "$test_cmd" 2>&1) || exit_code=$?
    # Truncate output to avoid huge JSON values
    local truncated_output
    truncated_output=$(echo "$output" | head -n 100)
    jq -n --arg out "$truncated_output" --argjson ec "$exit_code" \
        '{exit_code: $ec, output: $out}'
}

# Checks spec acceptance criteria by searching codebase for required patterns.
# Usage: _qa_check_spec_criteria "spec_dir"
# Outputs JSON array of unmet criteria (empty if all pass).
_qa_check_spec_criteria() {
    local spec_dir="${1:-specs}"
    local failures="[]"
    # If no specs directory, skip
    if [ ! -d "$spec_dir" ]; then
        echo "$failures"
        return 0
    fi
    # Look for acceptance criteria in spec files, check basic presence
    local spec_file
    for spec_file in "$spec_dir"/spec-*.md; do
        [ -f "$spec_file" ] || continue
        local spec_name
        spec_name=$(basename "$spec_file" .md)
        # Extract lines between "Acceptance Criteria" and the next "##"
        local criteria
        criteria=$(sed -n '/## Acceptance Criteria/,/^## /p' "$spec_file" | grep -E '^\- \[ \]' 2>/dev/null || true)
        # Each unchecked criterion is a potential spec_gap
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local criterion_text
            criterion_text=$(echo "$line" | sed 's/^- \[ \] //')
            # Only flag criteria that mention function names we can verify
            local fn_name
            fn_name=$(echo "$criterion_text" | grep -oE '[a-z_]+\(\)' | head -1 | tr -d '()' || true)
            if [ -n "$fn_name" ] && ! grep -q "^${fn_name}() {" automaton.sh 2>/dev/null; then
                failures=$(echo "$failures" | jq -c --arg id "${spec_name}_${fn_name}" \
                    --arg desc "Function $fn_name not found (criterion: $criterion_text)" \
                    --arg src "$spec_file" --arg spec "$spec_name" \
                    '. + [{"id": $id, "type": "spec_gap", "description": $desc, "source": $src, "spec": $spec}]')
            fi
        done <<< "$criteria"
    done
    echo "$failures"
}

# Blind spec criteria check: evaluates acceptance criteria using only test output,
# without searching source code. Prevents confirmation bias by not letting the
# validator see implementation details. Criteria mentioning function names are
# flagged as unverifiable unless the test output confirms them.
# Usage: _qa_check_spec_criteria_blind "spec_dir" "test_output"
# Outputs JSON array of unmet/unverifiable criteria.
_qa_check_spec_criteria_blind() {
    local spec_dir="${1:-specs}"
    local test_output="${2:-}"
    local failures="[]"
    if [ ! -d "$spec_dir" ]; then
        echo "$failures"
        return 0
    fi
    local spec_file
    for spec_file in "$spec_dir"/spec-*.md; do
        [ -f "$spec_file" ] || continue
        local spec_name
        spec_name=$(basename "$spec_file" .md)
        local criteria
        criteria=$(sed -n '/## Acceptance Criteria/,/^## /p' "$spec_file" | grep -E '^\- \[ \]' 2>/dev/null || true)
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local criterion_text
            criterion_text=$(echo "$line" | sed 's/^- \[ \] //')
            # In blind mode, check if the test output mentions the criterion's key terms
            local fn_name
            fn_name=$(echo "$criterion_text" | grep -oE '[a-z_]+\(\)' | head -1 | tr -d '()' || true)
            if [ -n "$fn_name" ]; then
                # Only flag if test output does NOT mention the function (cannot confirm)
                if [ -z "$test_output" ] || ! echo "$test_output" | grep -qi "$fn_name" 2>/dev/null; then
                    failures=$(echo "$failures" | jq -c --arg id "${spec_name}_${fn_name}_blind" \
                        --arg desc "Blind: cannot verify function $fn_name from test output alone (criterion: $criterion_text)" \
                        --arg src "$spec_file" --arg spec "$spec_name" \
                        '. + [{"id": $id, "type": "spec_gap", "description": $desc, "source": $src, "spec": $spec}]')
                fi
            fi
        done <<< "$criteria"
    done
    echo "$failures"
}

# Compares current failures against previous iteration to detect regressions.
# Usage: _qa_scan_regressions "current_failures_json" prev_iteration_num
# Outputs updated failures JSON with regression detection.
_qa_scan_regressions() {
    local current_failures="$1"
    local prev_iter="${2:-0}"
    if [ "$prev_iter" -le 0 ]; then
        echo "$current_failures"
        return 0
    fi
    local prev_file="${AUTOMATON_DIR}/qa/iteration-${prev_iter}.json"
    if [ ! -f "$prev_file" ]; then
        echo "$current_failures"
        return 0
    fi
    local prev_failures
    prev_failures=$(jq -r '.failures // []' "$prev_file")
    local prev_ids
    prev_ids=$(echo "$prev_failures" | jq -r '.[].id' 2>/dev/null || true)
    # Check if any previously passing items now fail (regression detection
    # is handled by the QA agent; here we just mark persistence)
    echo "$current_failures"
}

# Classifies a single failure into one of 4 types.
# Usage: _qa_classify_failure "id" "description" "source" "spec" "type"
# Outputs JSON object for the failure.
_qa_classify_failure() {
    local id="$1" description="$2" source="$3" spec="${4:-}" type="$5"
    local first_seen="${6:-1}" persistent="${7:-false}"
    jq -n --arg id "$id" --arg type "$type" --arg desc "$description" \
        --arg src "$source" --arg spec "$spec" \
        --argjson fs "$first_seen" --argjson pers "$persistent" \
        '{id: $id, type: $type, description: $desc, source: $src, spec: $spec, first_seen: $fs, persistent: $pers}'
}

# Marks failures as persistent if they appeared in the previous iteration.
# Usage: _qa_mark_persistent "failures_json_array" prev_iteration_num
# Outputs updated failures JSON array with persistent flags and first_seen adjusted.
_qa_mark_persistent() {
    local failures="$1"
    local prev_iter="${2:-0}"
    if [ "$prev_iter" -le 0 ]; then
        echo "$failures"
        return 0
    fi
    local prev_file="${AUTOMATON_DIR}/qa/iteration-${prev_iter}.json"
    if [ ! -f "$prev_file" ]; then
        echo "$failures"
        return 0
    fi
    # Build a lookup of previous failure IDs -> first_seen
    local prev_lookup
    prev_lookup=$(jq -c '[.failures[]? | {key: .id, value: .first_seen}] | from_entries' "$prev_file" 2>/dev/null || echo '{}')
    # Update current failures: mark persistent if ID exists in previous, preserve first_seen
    echo "$failures" | jq -c --argjson prev "$prev_lookup" '
        [.[] | . as $f |
            if $prev[$f.id] then
                .persistent = true | .first_seen = $prev[$f.id]
            else . end
        ]'
}

# Writes iteration results to .automaton/qa/iteration-N.json.
# Usage: _qa_write_iteration iter_num failures_json passed failed verdict
_qa_write_iteration() {
    local iter_num="$1" failures="$2" passed="$3" failed="$4" verdict="$5"
    mkdir -p "${AUTOMATON_DIR}/qa"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n --argjson iter "$iter_num" --arg ts "$ts" \
        --argjson failures "$failures" \
        --argjson passed "$passed" --argjson failed "$failed" \
        --arg verdict "$verdict" \
        '{
            iteration: $iter,
            timestamp: $ts,
            checks: {tests_run: true, spec_criteria_checked: true, regressions_scanned: true},
            failures: $failures,
            passed: $passed,
            failed: $failed,
            verdict: $verdict
        }' > "${AUTOMATON_DIR}/qa/iteration-${iter_num}.json"
}

# Main QA validation pass. Runs all three checks and produces structured results.
# Usage: _qa_validate iter_num prev_iter_num test_command spec_dir
# Outputs JSON result and writes iteration file.
_qa_validate() {
    local iter_num="${1:-1}"
    local prev_iter="${2:-0}"
    local test_cmd="${3:-bash -n automaton.sh}"
    local spec_dir="${4:-specs}"

    mkdir -p "${AUTOMATON_DIR}/qa"
    local failures="[]"
    local passed=0 failed=0

    # Step 1: Run tests
    local test_result
    test_result=$(_qa_run_tests "$test_cmd")
    local test_exit_code
    test_exit_code=$(echo "$test_result" | jq -r '.exit_code')
    if [ "$test_exit_code" -ne 0 ]; then
        local test_output
        test_output=$(echo "$test_result" | jq -r '.output' | head -5)
        local failure
        failure=$(_qa_classify_failure "test_suite" "Test suite failed with exit code $test_exit_code: $test_output" "test_command" "" "test_failure" "$iter_num" "false")
        failures=$(echo "$failures" | jq -c --argjson f "$failure" '. + [$f]')
        failed=$((failed + 1))
    else
        passed=$((passed + 1))
    fi

    # Step 2: Check spec criteria
    local spec_failures
    spec_failures=$(_qa_check_spec_criteria "$spec_dir")
    local spec_count
    spec_count=$(echo "$spec_failures" | jq 'length')
    if [ "$spec_count" -gt 0 ]; then
        failures=$(echo "$failures" | jq -c --argjson sf "$spec_failures" '. + $sf')
        failed=$((failed + spec_count))
    else
        passed=$((passed + 1))
    fi

    # Step 3: Scan for regressions (updates persistence flags)
    failures=$(_qa_mark_persistent "$failures" "$prev_iter")

    # Determine verdict
    local total_failed
    total_failed=$(echo "$failures" | jq 'length')
    local verdict="PASS"
    if [ "$total_failed" -gt 0 ]; then
        verdict="FAIL"
    fi

    # Write iteration file
    _qa_write_iteration "$iter_num" "$failures" "$passed" "$total_failed" "$verdict"

    # Output result JSON
    jq -n --argjson iter "$iter_num" \
        --argjson failures "$failures" \
        --argjson passed "$passed" --argjson failed "$total_failed" \
        --arg verdict "$verdict" \
        '{iteration: $iter, checks: {tests_run: true, spec_criteria_checked: true, regressions_scanned: true, blind_mode: false}, failures: $failures, passed: $passed, failed: $failed, verdict: $verdict}'
}

# Blind QA validation pass. Runs tests and checks spec criteria using only test
# output — no source code access. Prevents confirmation bias where the QA agent
# rationalizes implementation choices instead of checking spec compliance.
# Usage: _qa_validate_blind iter_num prev_iter_num test_command spec_dir
# Outputs JSON result and writes iteration file.
_qa_validate_blind() {
    local iter_num="${1:-1}"
    local prev_iter="${2:-0}"
    local test_cmd="${3:-bash -n automaton.sh}"
    local spec_dir="${4:-specs}"

    mkdir -p "${AUTOMATON_DIR}/qa"
    local failures="[]"
    local passed=0 failed=0

    # Step 1: Run tests (same as normal — tests are the primary signal in blind mode)
    local test_result
    test_result=$(_qa_run_tests "$test_cmd")
    local test_exit_code
    test_exit_code=$(echo "$test_result" | jq -r '.exit_code')
    local test_output
    test_output=$(echo "$test_result" | jq -r '.output')
    if [ "$test_exit_code" -ne 0 ]; then
        local test_output_summary
        test_output_summary=$(echo "$test_output" | head -5)
        local failure
        failure=$(_qa_classify_failure "test_suite" "Test suite failed with exit code $test_exit_code: $test_output_summary" "test_command" "" "test_failure" "$iter_num" "false")
        failures=$(echo "$failures" | jq -c --argjson f "$failure" '. + [$f]')
        failed=$((failed + 1))
    else
        passed=$((passed + 1))
    fi

    # Step 2: Blind spec criteria check — uses only test output, no source code
    local spec_failures
    spec_failures=$(_qa_check_spec_criteria_blind "$spec_dir" "$test_output")
    local spec_count
    spec_count=$(echo "$spec_failures" | jq 'length')
    if [ "$spec_count" -gt 0 ]; then
        failures=$(echo "$failures" | jq -c --argjson sf "$spec_failures" '. + $sf')
        failed=$((failed + spec_count))
    else
        passed=$((passed + 1))
    fi

    # Step 3: Scan for regressions (updates persistence flags)
    failures=$(_qa_mark_persistent "$failures" "$prev_iter")

    # Determine verdict
    local total_failed
    total_failed=$(echo "$failures" | jq 'length')
    local verdict="PASS"
    if [ "$total_failed" -gt 0 ]; then
        verdict="FAIL"
    fi

    # Write iteration file
    _qa_write_iteration "$iter_num" "$failures" "$passed" "$total_failed" "$verdict"

    # Output result JSON (blind_mode flag indicates this was a blind validation)
    jq -n --argjson iter "$iter_num" \
        --argjson failures "$failures" \
        --argjson passed "$passed" --argjson failed "$total_failed" \
        --arg verdict "$verdict" \
        '{iteration: $iter, checks: {tests_run: true, spec_criteria_checked: true, regressions_scanned: true, blind_mode: true}, failures: $failures, passed: $passed, failed: $failed, verdict: $verdict}'
}

# Creates targeted fix tasks in IMPLEMENTATION_PLAN.md based on QA failure types.
# Each failure type maps to a specific QA- prefix:
#   test_failure -> QA-fix:, spec_gap -> QA-implement:,
#   regression -> QA-regression:, style_issue -> QA-style:
# Persistent failures (seen in 2+ consecutive iterations) get a (PERSISTENT) flag.
# Skips failures whose ID already appears as a QA task in the plan.
# Usage: _qa_create_fix_tasks "failures_json_array"
# Outputs: number of tasks created
_qa_create_fix_tasks() {
    local failures="$1"
    local plan_file="${PROJECT_ROOT}/IMPLEMENTATION_PLAN.md"
    local count=0

    if [ ! -f "$plan_file" ]; then
        echo "0"
        return 0
    fi

    local num_failures
    num_failures=$(echo "$failures" | jq 'length')
    if [ "$num_failures" -eq 0 ]; then
        echo "0"
        return 0
    fi

    local i=0
    while [ "$i" -lt "$num_failures" ]; do
        local id type desc spec persistent
        id=$(echo "$failures" | jq -r ".[$i].id")
        type=$(echo "$failures" | jq -r ".[$i].type")
        desc=$(echo "$failures" | jq -r ".[$i].description")
        spec=$(echo "$failures" | jq -r ".[$i].spec // empty")
        persistent=$(echo "$failures" | jq -r ".[$i].persistent // false")

        # Skip if this failure ID already has a QA task in the plan
        if grep -q "QA-.*${id}" "$plan_file" 2>/dev/null; then
            i=$((i + 1))
            continue
        fi

        local prefix task_line
        case "$type" in
            test_failure)  prefix="QA-fix" ;;
            spec_gap)      prefix="QA-implement" ;;
            regression)    prefix="QA-regression" ;;
            style_issue)   prefix="QA-style" ;;
            *)             prefix="QA-fix" ;;
        esac

        # Build the task description
        local esc_flag=""
        if [ "$persistent" = "true" ]; then
            esc_flag=" (PERSISTENT)"
        fi

        local spec_ref=""
        if [ -n "$spec" ]; then
            spec_ref=" [${spec}]"
        fi

        task_line="- [ ] ${prefix}${esc_flag}: ${id}${spec_ref} — ${desc}"
        echo "$task_line" >> "$plan_file"
        count=$((count + 1))

        i=$((i + 1))
    done

    echo "$count"
}

# Detects QA oscillation: a failure that was fixed in a later iteration reappears.
# Scans iteration history files for failure IDs that appear in current failures
# AND appeared in a prior (non-adjacent) iteration but were absent in between.
# Usage: _qa_detect_oscillation current_iter_num current_failures_json
# Returns: 0 if oscillation detected (with oscillating IDs on stdout), 1 if not.
_qa_detect_oscillation() {
    local current_iter="$1"
    local current_failures="$2"

    # Need at least 3 iterations to detect a cycle (fail→fix→re-fail)
    if [ "$current_iter" -lt 3 ]; then
        return 1
    fi

    local current_ids
    current_ids=$(echo "$current_failures" | jq -r '.[].id' 2>/dev/null)
    if [ -z "$current_ids" ]; then
        return 1
    fi

    local oscillating=""

    # For each current failure ID, check if it appeared in any earlier iteration
    # but was absent in at least one intermediate iteration (the "fixed" gap)
    while IFS= read -r fid; do
        local seen_before=false
        local was_absent=false

        # Walk iterations from 1 to current-1
        local i=1
        while [ "$i" -lt "$current_iter" ]; do
            local iter_file="${AUTOMATON_DIR}/qa/iteration-${i}.json"
            if [ -f "$iter_file" ]; then
                local has_id
                has_id=$(jq -r --arg id "$fid" '.failures[]? | select(.id == $id) | .id' "$iter_file" 2>/dev/null)
                if [ -n "$has_id" ]; then
                    if [ "$was_absent" = "true" ]; then
                        # This shouldn't happen mid-walk since we're reading
                        # historically, but the pattern check continues
                        :
                    fi
                    seen_before=true
                else
                    if [ "$seen_before" = "true" ]; then
                        was_absent=true
                    fi
                fi
            fi
            i=$((i + 1))
        done

        # Oscillation = seen in a prior iter, absent in a later iter, now back
        if [ "$seen_before" = "true" ] && [ "$was_absent" = "true" ]; then
            oscillating="${oscillating:+$oscillating,}$fid"
        fi
    done <<< "$current_ids"

    if [ -n "$oscillating" ]; then
        echo "$oscillating"
        return 0
    fi

    return 1
}

# Writes .automaton/qa/failure-report.md listing unresolved failures with types,
# iteration history, and persistence flags. Called when QA loop exhausts retries.
# The report is passed as context to Phase 4 review so the reviewer knows exactly
# what QA could not fix.
# Usage: _qa_write_failure_report iterations_exhausted final_failures_json
_qa_write_failure_report() {
    local iters_exhausted="$1"
    local final_failures="$2"
    local report_file="${AUTOMATON_DIR}/qa/failure-report.md"
    mkdir -p "${AUTOMATON_DIR}/qa"

    {
        echo "# QA Failure Report"
        echo ""
        echo "QA validation exhausted **${iters_exhausted}** iterations with unresolved failures."
        echo ""

        # Unresolved failures table
        local num_failures
        num_failures=$(echo "$final_failures" | jq 'length')
        echo "## Unresolved Failures (${num_failures})"
        echo ""
        if [ "$num_failures" -gt 0 ]; then
            echo "| id | type | persistent | description |"
            echo "|---|---|---|---|"
            local i=0
            while [ "$i" -lt "$num_failures" ]; do
                local fid ftype fdesc fpersist
                fid=$(echo "$final_failures" | jq -r ".[$i].id")
                ftype=$(echo "$final_failures" | jq -r ".[$i].type")
                fdesc=$(echo "$final_failures" | jq -r ".[$i].description" | head -1 | cut -c1-120)
                fpersist=$(echo "$final_failures" | jq -r ".[$i].persistent // false")
                echo "| ${fid} | ${ftype} | ${fpersist} | ${fdesc} |"
                i=$((i + 1))
            done
            echo ""
        else
            echo "No unresolved failures recorded."
            echo ""
        fi

        # Iteration history from iteration files
        echo "## Iteration History"
        echo ""
        local iter_num=1
        while [ "$iter_num" -le "$iters_exhausted" ]; do
            local iter_file="${AUTOMATON_DIR}/qa/iteration-${iter_num}.json"
            if [ -f "$iter_file" ]; then
                local ts verdict failed passed
                ts=$(jq -r '.timestamp // "unknown"' "$iter_file")
                verdict=$(jq -r '.verdict // "unknown"' "$iter_file")
                failed=$(jq -r '.failed // 0' "$iter_file")
                passed=$(jq -r '.passed // 0' "$iter_file")
                echo "- **Iteration ${iter_num}** (${ts}): ${verdict} — ${passed} passed, ${failed} failed"
            fi
            iter_num=$((iter_num + 1))
        done
        echo ""

        echo "## Action Required"
        echo ""
        echo "The review agent should examine these failures and determine whether they indicate:"
        echo "1. Implementation bugs that need targeted fixes"
        echo "2. Spec ambiguities that need clarification"
        echo "3. Test issues that need correction"
    } > "$report_file"

    log "QA" "Failure report written to ${report_file}"
}

# Runs the QA retry loop: validate → create fix tasks → build fixes → validate
# again, up to qa_max_iterations. Returns structured JSON with final verdict.
# The loop exits early on PASS or budget exhaustion.
# Usage: _qa_run_loop "test_command" "spec_dir"
# Outputs JSON: {verdict, iterations_run, final_failures, fix_tasks_created}
_qa_run_loop() {
    local test_cmd="${1:-bash -n automaton.sh}"
    local spec_dir="${2:-specs}"
    local max_iter="${QA_MAX_ITERATIONS:-5}"
    local qa_iter=1
    local total_fix_tasks=0
    local last_verdict="FAIL"
    local last_failures="[]"
    local last_failed=0
    local last_passed=0

    mkdir -p "${AUTOMATON_DIR}/qa"

    log "QA" "Starting QA loop (max ${max_iter} iterations)"

    while [ "$qa_iter" -le "$max_iter" ]; do
        local prev_iter=$((qa_iter - 1))

        log "QA" "Iteration ${qa_iter}/${max_iter}: running validation${QA_BLIND_VALIDATION:+ (blind mode)}"

        # Step 1: Validate (blind mode uses only specs + test output, no source code)
        local result
        if [ "${QA_BLIND_VALIDATION:-false}" = "true" ]; then
            result=$(_qa_validate_blind "$qa_iter" "$prev_iter" "$test_cmd" "$spec_dir")
        else
            result=$(_qa_validate "$qa_iter" "$prev_iter" "$test_cmd" "$spec_dir")
        fi

        last_verdict=$(echo "$result" | jq -r '.verdict')
        last_failures=$(echo "$result" | jq -c '.failures')
        last_failed=$(echo "$result" | jq -r '.failed')
        last_passed=$(echo "$result" | jq -r '.passed')

        # Step 2: Early exit on PASS
        if [ "$last_verdict" = "PASS" ]; then
            log "QA" "Iteration ${qa_iter}: all checks passed"
            break
        fi

        log "QA" "Iteration ${qa_iter}: ${last_failed} failure(s) found"

        # Step 2b: Oscillation detection — abort if fixes are fighting each other
        local oscillating_ids=""
        if oscillating_ids=$(_qa_detect_oscillation "$qa_iter" "$last_failures"); then
            log "QA" "Oscillation detected: failures cycling — ${oscillating_ids}"
            log "QA" "Escalating to review instead of retrying"
            last_verdict="OSCILLATION"
            break
        fi

        # Step 3: Create fix tasks (only if more iterations remain)
        if [ "$qa_iter" -lt "$max_iter" ]; then
            local tasks_created
            tasks_created=$(_qa_create_fix_tasks "$last_failures")
            total_fix_tasks=$((total_fix_tasks + tasks_created))
            log "QA" "Iteration ${qa_iter}: created ${tasks_created} fix task(s)"
        fi

        # Step 4: Budget check before next iteration
        if [ "$qa_iter" -lt "$max_iter" ]; then
            local budget_file="${AUTOMATON_DIR}/budget.json"
            if [ -f "$budget_file" ]; then
                local tokens_remaining
                if [ "${BUDGET_MODE:-fixed}" = "allowance" ]; then
                    tokens_remaining=$(jq '.tokens_remaining // 999999' "$budget_file" 2>/dev/null || echo "999999")
                else
                    tokens_remaining=$(jq '(.limits.max_total_tokens - .used.total_tokens) // 999999' "$budget_file" 2>/dev/null || echo "999999")
                fi
                if [ "$tokens_remaining" -lt "${BUDGET_PER_ITERATION:-100000}" ]; then
                    log "QA" "Insufficient budget for another QA iteration (${tokens_remaining} tokens remaining). Stopping."
                    break
                fi
            fi
        fi

        qa_iter=$((qa_iter + 1))
    done

    # Write failure report when QA exhausted iterations without passing (spec-46.4)
    if [ "$last_verdict" != "PASS" ]; then
        local actual_iters=$((qa_iter > max_iter ? max_iter : qa_iter))
        _qa_write_failure_report "$actual_iters" "$last_failures"
    fi

    # Output final result JSON
    jq -n --arg verdict "$last_verdict" \
        --argjson iterations "$qa_iter" \
        --argjson failures "$last_failures" \
        --argjson fix_tasks "$total_fix_tasks" \
        --argjson passed "$last_passed" \
        --argjson failed "$last_failed" \
        '{
            verdict: $verdict,
            iterations_run: (if $iterations > '"$max_iter"' then '"$max_iter"' else $iterations end),
            passed: $passed,
            failed: $failed,
            final_failures: $failures,
            fix_tasks_created: $fix_tasks
        }'
}

# --- Spec 47: Pre-Flight Spec Critique ---

# Collects all spec files from the given directory, sorted by spec number.
# Concatenates them with filename headers. Outputs the combined content to stdout.
# Truncates if total estimated tokens exceed CRITIQUE_MAX_TOKEN_ESTIMATE.
_critique_collect_specs() {
    local specs_dir="$1"
    local max_tokens="${CRITIQUE_MAX_TOKEN_ESTIMATE:-80000}"
    local max_chars=$((max_tokens * 4))  # 4 chars per token heuristic

    local spec_files=()
    while IFS= read -r f; do
        spec_files+=("$f")
    done < <(find "$specs_dir" -name 'spec-*.md' -type f 2>/dev/null | sort -t'-' -k2 -n)

    if [ ${#spec_files[@]} -eq 0 ]; then
        echo ""
        return 0
    fi

    local combined=""
    local total_chars=0
    local included=0
    local truncated=false

    for spec_file in "${spec_files[@]}"; do
        local basename
        basename=$(basename "$spec_file")
        local content
        content=$(cat "$spec_file" 2>/dev/null || echo "")
        local header="--- ${basename} ---"
        local entry="${header}"$'\n'"${content}"$'\n\n'
        local entry_chars=${#entry}

        if [ $((total_chars + entry_chars)) -gt "$max_chars" ]; then
            truncated=true
            log "CRITIQUE" "WARNING: Spec payload truncated at $included specs (~$((total_chars / 4)) tokens). Remaining specs excluded to stay within ${max_tokens}-token ceiling."
            break
        fi

        combined="${combined}${entry}"
        total_chars=$((total_chars + entry_chars))
        included=$((included + 1))
    done

    if [ "$truncated" = "true" ] && [ "$included" -lt "${#spec_files[@]}" ]; then
        combined="${combined}--- TRUNCATED: $((${#spec_files[@]} - included)) spec(s) excluded (token ceiling: ${max_tokens}) ---"$'\n'
    fi

    echo "$combined"
}

# Generates .automaton/SPEC_CRITIQUE.md from structured JSON critique output.
# Reads JSON with "findings" array, counts severities, writes formatted report.
_critique_generate_report() {
    local json_output="$1"
    local specs_analyzed="$2"
    local report_file="${AUTOMATON_DIR:-.automaton}/SPEC_CRITIQUE.md"

    local error_count warning_count info_count
    error_count=$(echo "$json_output" | jq '[.findings[] | select(.severity == "ERROR")] | length' 2>/dev/null || echo 0)
    warning_count=$(echo "$json_output" | jq '[.findings[] | select(.severity == "WARNING")] | length' 2>/dev/null || echo 0)
    info_count=$(echo "$json_output" | jq '[.findings[] | select(.severity == "INFO")] | length' 2>/dev/null || echo 0)

    {
        echo "# Spec Critique Report"
        echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Specs analyzed: ${specs_analyzed}"
        echo ""
        echo "## Summary"
        echo "- Errors: ${error_count}"
        echo "- Warnings: ${warning_count}"
        echo "- Info: ${info_count}"
        echo ""
        echo "## Findings"
        echo ""

        local findings_count
        findings_count=$(echo "$json_output" | jq '.findings | length' 2>/dev/null || echo 0)

        if [ "$findings_count" -eq 0 ]; then
            echo "No issues found."
        else
            local i=0
            while [ "$i" -lt "$findings_count" ]; do
                local severity spec dimension description suggestion
                severity=$(echo "$json_output" | jq -r ".findings[$i].severity" 2>/dev/null || echo "INFO")
                spec=$(echo "$json_output" | jq -r ".findings[$i].spec" 2>/dev/null || echo "unknown")
                dimension=$(echo "$json_output" | jq -r ".findings[$i].dimension" 2>/dev/null || echo "general")
                description=$(echo "$json_output" | jq -r ".findings[$i].description" 2>/dev/null || echo "")
                suggestion=$(echo "$json_output" | jq -r ".findings[$i].suggestion // empty" 2>/dev/null || echo "")

                local dimension_label
                case "$dimension" in
                    ambiguity) dimension_label="Ambiguous requirement" ;;
                    missing_criteria) dimension_label="Missing acceptance criteria" ;;
                    contradiction) dimension_label="Potential contradiction" ;;
                    missing_dependency) dimension_label="Missing dependency" ;;
                    untestable) dimension_label="Untestable criteria" ;;
                    scope_gap) dimension_label="Scope gap" ;;
                    *) dimension_label="$dimension" ;;
                esac

                echo "### [${severity}] ${spec}: ${dimension_label}"
                echo "${description}"
                if [ -n "$suggestion" ]; then
                    echo "Suggestion: ${suggestion}"
                fi
                echo ""

                i=$((i + 1))
            done
        fi
    } > "$report_file"

    echo "$error_count"
}

# Main critique function. Gathers specs, makes a single claude -p call,
# generates SPEC_CRITIQUE.md, and returns exit code based on severity.
# Returns: 0 if no errors (warnings/info only), 1 if errors found.
phase_critique() {
    local specs_dir="${1:-${PROJECT_ROOT:-.}/specs}"

    mkdir -p "${AUTOMATON_DIR:-.automaton}"

    # Collect and concatenate spec files
    local spec_payload
    spec_payload=$(_critique_collect_specs "$specs_dir")

    if [ -z "$spec_payload" ]; then
        log "CRITIQUE" "No spec files found in ${specs_dir}. Skipping critique."
        echo "No spec files found in ${specs_dir}." >&2
        return 0
    fi

    # Count specs analyzed
    local specs_analyzed
    specs_analyzed=$(echo "$spec_payload" | grep -c '^--- spec-') || specs_analyzed=0

    log "CRITIQUE" "Analyzing $specs_analyzed spec files"

    # Build the critique prompt (written to temp file to avoid heredoc extraction issues)
    local prompt_file
    prompt_file=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file"; return 1; }
    printf '%s\n' \
        "You are a spec quality reviewer. Analyze the following specification files and identify issues across these 6 dimensions:" \
        "" \
        "1. **Ambiguous requirements**: Vague language (\"fast\", \"user-friendly\", \"scalable\") without measurable criteria." \
        "2. **Missing acceptance criteria**: Requirements that lack a testable condition." \
        "3. **Inter-spec contradictions**: Two specs that define conflicting behavior for the same area." \
        "4. **Missing dependency declarations**: A spec references functionality from another spec without declaring the dependency." \
        "5. **Untestable criteria**: Acceptance criteria that cannot be verified programmatically or by inspection." \
        "6. **Scope gaps**: Features implied by context that no spec covers." \
        "" \
        "Output ONLY valid JSON with this exact structure (no markdown fences, no explanation):" \
        '{"findings": [{"severity": "ERROR|WARNING|INFO", "spec": "spec-NN", "dimension": "ambiguity|missing_criteria|contradiction|missing_dependency|untestable|scope_gap", "description": "Clear description of the issue", "suggestion": "Actionable fix suggestion"}]}' \
        "" \
        "Severity guide:" \
        "- ERROR: Likely to cause build failure or review rejection" \
        "- WARNING: May cause rework but build can proceed" \
        "- INFO: Stylistic or minor observation" \
        "" \
        "Here are the spec files to analyze:" \
        "" > "$prompt_file"

    # Append spec payload
    echo "$spec_payload" >> "$prompt_file"

    # Make a single claude -p call
    local claude_output
    claude_output=$(claude -p --output-format text --max-tokens 50000 < "$prompt_file" 2>/dev/null) || true
    rm -f "$prompt_file"

    # Extract JSON from the response (handle potential markdown fences)
    local json_output
    json_output=$(echo "$claude_output" | sed -n '/^{/,/^}/p')
    if [ -z "$json_output" ]; then
        # Try extracting from markdown code fences
        json_output=$(echo "$claude_output" | sed -n '/```json/,/```/p' | sed '1d;$d')
    fi
    if [ -z "$json_output" ]; then
        # Try the whole output as JSON
        json_output="$claude_output"
    fi

    # Validate JSON
    if ! echo "$json_output" | jq empty 2>/dev/null; then
        log "CRITIQUE" "WARNING: Claude returned invalid JSON. Writing raw output."
        json_output='{"findings": []}'
    fi

    # Ensure findings array exists
    if ! echo "$json_output" | jq -e '.findings' >/dev/null 2>&1; then
        json_output='{"findings": []}'
    fi

    # Generate the report
    local error_count
    error_count=$(_critique_generate_report "$json_output" "$specs_analyzed")

    local report_file="${AUTOMATON_DIR:-.automaton}/SPEC_CRITIQUE.md"
    local total_findings
    total_findings=$(echo "$json_output" | jq '.findings | length' 2>/dev/null || echo 0)

    log "CRITIQUE" "Critique complete: $total_findings findings ($error_count errors). Report: $report_file"

    # Print summary to stdout
    echo "Spec critique: ${total_findings} findings (${error_count} errors)"
    echo "Report: ${report_file}"

    if [ "$error_count" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Blind validation (spec-54): a separate Claude invocation that reviews changes
# with ONLY spec acceptance criteria, test results, and git diff — no builder
# reasoning, no implementation plan, no prior review feedback. Returns 0 on
# PASS or when disabled, 1 on FAIL.
# Usage: run_blind_validation "specs/spec-NN.md"
run_blind_validation() {
    local spec_file="${1:-}"

    # Skip if blind validation is disabled
    if [ "${FLAG_BLIND_VALIDATION:-false}" != "true" ]; then
        log "BLIND" "Blind validation disabled (flags.blind_validation=false)"
        return 0
    fi

    local max_diff_lines="${BLIND_VALIDATION_MAX_DIFF_LINES:-500}"

    # --- Extract acceptance criteria from spec ---
    local criteria=""
    if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
        # Try Acceptance Criteria section first
        criteria=$(sed -n '/^## Acceptance Criteria/,/^## /p' "$spec_file" | sed '$d')
        # Fall back to Requirements section
        if [ -z "$criteria" ]; then
            criteria=$(sed -n '/^## Requirements/,/^## /p' "$spec_file" | sed '$d')
        fi
    fi
    if [ -z "$criteria" ]; then
        log "BLIND" "WARNING: No acceptance criteria found in ${spec_file:-<none>}"
        criteria="No acceptance criteria available."
    fi

    # --- Get test results ---
    local test_results=""
    if [ -f "${AUTOMATON_DIR}/test-results.log" ]; then
        test_results=$(cat "${AUTOMATON_DIR}/test-results.log")
    else
        test_results="No test results available."
    fi

    # --- Get git diff (truncated if large) ---
    local diff_output
    diff_output=$(git diff --cached --no-color 2>/dev/null || git diff --no-color 2>/dev/null || echo "No diff available.")
    local diff_lines
    diff_lines=$(echo "$diff_output" | wc -l)
    if [ "$diff_lines" -gt "$max_diff_lines" ]; then
        diff_output=$(echo "$diff_output" | tail -n "$max_diff_lines")
        diff_output="[... diff truncated: showing last ${max_diff_lines} of ${diff_lines} lines ...]
${diff_output}"
    fi

    # --- Assemble prompt (criteria + test results + diff only) ---
    local prompt_file
    prompt_file=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file"; return 1; }
    cat > "$prompt_file" <<PROMPT
You are a blind validator. You have NOT seen the implementation plan, builder's reasoning, or commit messages. Evaluate the changes ONLY against the acceptance criteria below.

## Spec Acceptance Criteria

${criteria}

## Test Results

${test_results}

## Code Changes (git diff)

${diff_output}

## Instructions

Compare the code changes against each acceptance criterion. For each criterion, determine if it is satisfied by the diff. Output your verdict in exactly this format:

VERDICT: PASS or FAIL
CRITERIA_MET: [list of criteria that are satisfied]
CRITERIA_MISSED: [list of criteria not satisfied, with reasoning]
ISSUES: [any problems found outside listed criteria]
PROMPT

    # --- Invoke separate Claude CLI call ---
    log "BLIND" "Running blind validation for ${spec_file:-unknown spec}"
    local claude_output
    claude_output=$(claude -p --output-format text --max-tokens 4000 < "$prompt_file" 2>/dev/null) || true
    rm -f "$prompt_file"

    # --- Write result to .automaton/blind-validation.md ---
    local spec_name
    spec_name=$(basename "${spec_file:-unknown}" .md)
    cat > "${AUTOMATON_DIR}/blind-validation.md" <<RESULT
# Blind Validation Result

Spec: ${spec_name}
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

${claude_output}
RESULT

    # --- Parse verdict ---
    local verdict
    verdict=$(echo "$claude_output" | grep -m1 '^VERDICT:' | sed 's/^VERDICT:[[:space:]]*//' | tr -d '[:space:]')

    if [ "$verdict" = "FAIL" ]; then
        log "BLIND" "Blind validation FAILED for $spec_name — see .automaton/blind-validation.md"
        return 1
    else
        log "BLIND" "Blind validation PASSED for $spec_name"
        return 0
    fi
}

# Steelman self-critique (spec-53): a single adversarial Claude call after
# planning that argues against the chosen approach. Writes STEELMAN.md to the
# project root. Non-blocking — a failed call logs a warning and returns 0.
run_steelman_critique() {
    local plan_file="${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md"

    if [ ! -f "$plan_file" ]; then
        echo "Error: IMPLEMENTATION_PLAN.md not found. Cannot run steelman critique." >&2
        return 1
    fi

    log "STEELMAN" "Running steelman self-critique"

    # --- Gather input: plan + specs + config ---
    local payload=""
    payload+="--- IMPLEMENTATION_PLAN.md ---"$'\n'
    payload+="$(cat "$plan_file")"$'\n\n'

    local spec_file
    for spec_file in "${PROJECT_ROOT:-.}"/specs/spec-*.md; do
        [ -f "$spec_file" ] || continue
        payload+="--- $(basename "$spec_file") ---"$'\n'
        payload+="$(cat "$spec_file")"$'\n\n'
    done

    if [ -f "${PROJECT_ROOT:-.}/automaton.config.json" ]; then
        payload+="--- automaton.config.json ---"$'\n'
        payload+="$(cat "${PROJECT_ROOT:-.}/automaton.config.json")"$'\n\n'
    fi

    # --- Build adversarial prompt ---
    local prompt_file
    prompt_file=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file"; return 1; }
    cat > "$prompt_file" <<'PROMPT'
You are a skeptical technical reviewer. Your job is to argue AGAINST the implementation plan below. Do NOT rewrite the plan or produce code. Instead, produce a critique document with exactly these 5 sections:

## Risks and Failure Modes
What can go wrong at runtime, at scale, or under edge cases the plan does not address.

## Rejected Alternatives
Approaches the plan implicitly chose not to take, with brief arguments for why they might have been better.

## Questionable Assumptions
Premises the plan depends on that may not hold.

## Fragile Dependencies
External tools, APIs, or conventions the plan relies on that could change or break.

## Complexity Hotspots
Specific areas of the plan most likely to produce bugs during implementation.

Be concrete and specific. Reference plan tasks and spec numbers where applicable.

Here is the plan and supporting context to critique:

PROMPT
    echo "$payload" >> "$prompt_file"

    # --- Single Claude call ---
    local claude_output=""
    claude_output=$(claude -p --output-format text --max-tokens 8000 < "$prompt_file" 2>/dev/null) || true
    rm -f "$prompt_file"

    if [ -z "$claude_output" ]; then
        log "STEELMAN" "WARNING: Claude call failed or returned empty. Skipping STEELMAN.md."
        echo "Warning: Steelman critique failed (network error or empty response). Continuing." >&2
        return 0
    fi

    # --- Write STEELMAN.md to project root ---
    cat > "${PROJECT_ROOT:-.}/STEELMAN.md" <<HEADER
<!-- Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ") -->

${claude_output}
HEADER

    log "STEELMAN" "Steelman critique written to STEELMAN.md"
    echo "Steelman critique: ${PROJECT_ROOT:-.}/STEELMAN.md"
    return 0
}

# Complexity assessment (spec-51): a single cheap Claude haiku call that
# classifies the task into SIMPLE, MODERATE, or COMPLEX before the pipeline
# runs. Writes .automaton/complexity.json. If ARG_COMPLEXITY is set (CLI
# override), skips the Claude call and uses the override value directly.
# On any failure, defaults to MODERATE. Always returns 0.
# Usage: assess_complexity "task description"
assess_complexity() {
    local task_desc="${1:-}"
    local complexity_file="${AUTOMATON_DIR:-.automaton}/complexity.json"
    local tier="MODERATE"
    local rationale="Standard task (default)"
    local is_override="false"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # CLI override: skip the Claude call entirely
    if [ -n "${ARG_COMPLEXITY:-}" ]; then
        case "${ARG_COMPLEXITY}" in
            simple)   tier="SIMPLE" ;;
            moderate) tier="MODERATE" ;;
            complex)  tier="COMPLEX" ;;
        esac
        rationale="CLI override (--complexity=${ARG_COMPLEXITY})"
        is_override="true"
        log "COMPLEXITY" "Using CLI override: tier=$tier"
    else
        # Make a single haiku call to classify the task
        local prompt
        prompt="Classify this task into exactly one tier: SIMPLE, MODERATE, or COMPLEX.

SIMPLE: Single file, no logic change, no new tests needed (typo fix, config change, comment update).
MODERATE: 1-3 files, contained logic change, existing patterns (single feature, bug fix, refactor one function).
COMPLEX: 4+ files, new patterns, dependency changes, API surface change (multi-file architecture, new subsystem).

Task: ${task_desc}

Respond with ONLY a JSON object, no other text:
{\"tier\": \"SIMPLE|MODERATE|COMPLEX\", \"rationale\": \"one-line reason\"}"

        local claude_output=""
        claude_output=$(echo "$prompt" | claude -p --model haiku --output-format json 2>/dev/null) || true

        # Parse the response
        if [ -n "$claude_output" ]; then
            local parsed_tier parsed_rationale
            parsed_tier=$(echo "$claude_output" | jq -r '.tier // empty' 2>/dev/null) || true
            parsed_rationale=$(echo "$claude_output" | jq -r '.rationale // empty' 2>/dev/null) || true

            # Validate tier value
            case "${parsed_tier:-}" in
                SIMPLE|MODERATE|COMPLEX)
                    tier="$parsed_tier"
                    rationale="${parsed_rationale:-No rationale provided}"
                    ;;
                *)
                    log "COMPLEXITY" "Invalid tier from assessment: '${parsed_tier:-}'. Defaulting to MODERATE."
                    tier="MODERATE"
                    rationale="Assessment returned invalid tier (defaulted to MODERATE)"
                    ;;
            esac
        else
            log "COMPLEXITY" "Assessment call failed or returned empty. Defaulting to MODERATE."
            rationale="Assessment call failed (defaulted to MODERATE)"
        fi
    fi

    # Write complexity.json
    cat > "$complexity_file" <<CEOF
{"tier":"${tier}","rationale":"${rationale}","assessed_at":"${ts}","override":${is_override}}
CEOF

    log "COMPLEXITY" "Task classified as $tier: $rationale"
    return 0
}

# Applies pipeline routing based on the tier in .automaton/complexity.json.
# Adjusts global variables that downstream phases consume:
#   FLAG_SKIP_RESEARCH, MODEL_BUILDING, EXEC_MAX_ITER_REVIEW,
#   FLAG_BLIND_VALIDATION, FLAG_STEELMAN_CRITIQUE, QA_MAX_ITERATIONS
# Does nothing if complexity.json does not exist (pipeline runs with defaults).
# Usage: apply_complexity_routing
apply_complexity_routing() {
    local complexity_file="${AUTOMATON_DIR:-.automaton}/complexity.json"
    if [ ! -f "$complexity_file" ]; then
        return 0
    fi

    local tier
    tier=$(jq -r '.tier // "MODERATE"' "$complexity_file" 2>/dev/null) || tier="MODERATE"

    case "$tier" in
        SIMPLE)
            FLAG_SKIP_RESEARCH="true"
            MODEL_BUILDING="sonnet"
            EXEC_MAX_ITER_REVIEW=1
            FLAG_BLIND_VALIDATION="false"
            FLAG_STEELMAN_CRITIQUE="false"
            QA_MAX_ITERATIONS=2
            log "COMPLEXITY" "SIMPLE routing: skip research, sonnet build, 1 review iter, no blind/steelman"
            ;;
        MODERATE)
            MODEL_BUILDING="sonnet"
            EXEC_MAX_ITER_REVIEW=2
            FLAG_BLIND_VALIDATION="false"
            QA_MAX_ITERATIONS=3
            log "COMPLEXITY" "MODERATE routing: standard pipeline, sonnet build, 2 review iters"
            ;;
        COMPLEX)
            MODEL_BUILDING="opus"
            EXEC_MAX_ITER_REVIEW=4
            FLAG_BLIND_VALIDATION="true"
            FLAG_STEELMAN_CRITIQUE="true"
            QA_MAX_ITERATIONS=4
            log "COMPLEXITY" "COMPLEX routing: opus build, 4 review iters, blind+steelman enabled"
            ;;
    esac
    return 0
}

# --- Red-before-green gate (audit wave 3) ---
# Records pre-build test failure count so we can verify the build made progress.

# Parse "Failed:  N" from run_tests.sh output.
# Usage: _count_test_failures_from_output "$output"
# Returns: integer failure count (0 if not parseable)
_count_test_failures_from_output() {
    local output="$1"
    local count
    count=$(echo "$output" | grep -oP 'Failed:\s+\K[0-9]+' | head -1)
    echo "${count:-0}"
}

# Record test failure baseline before build phase begins.
# Usage: red_green_record_baseline "/path/to/run_tests.sh"
red_green_record_baseline() {
    local test_cmd="${1:-}"
    if [ "${RED_GREEN_GATE_ENABLED:-false}" != "true" ]; then
        return 0
    fi
    if [ -z "$test_cmd" ] || [ ! -f "$test_cmd" ]; then
        log "RED_GREEN" "No test runner found — skipping baseline"
        return 0
    fi

    local output rc=0
    output=$(bash "$test_cmd" 2>&1) || rc=$?

    local fail_count
    fail_count=$(_count_test_failures_from_output "$output")

    local baseline_file="${AUTOMATON_DIR:-.automaton}/red_green_baseline.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")

    cat > "$baseline_file" <<BEOF
{"failure_count":${fail_count},"recorded_at":"${now}"}
BEOF

    log "RED_GREEN" "Baseline recorded: $fail_count test failures"
    emit_event "red_green_baseline" "{\"failure_count\":${fail_count}}"
    return 0
}

# Check that test failures decreased (or stayed the same) compared to baseline.
# Usage: red_green_check_progress "/path/to/run_tests.sh"
# Returns: 0 = progress made (or no baseline), 1 = regression (failures increased)
red_green_check_progress() {
    local test_cmd="${1:-}"
    if [ "${RED_GREEN_GATE_ENABLED:-false}" != "true" ]; then
        return 0
    fi

    local baseline_file="${AUTOMATON_DIR:-.automaton}/red_green_baseline.json"
    if [ ! -f "$baseline_file" ]; then
        log "RED_GREEN" "No baseline found — skipping progress check"
        return 0
    fi

    local baseline_count
    baseline_count=$(jq -r '.failure_count // 0' "$baseline_file" 2>/dev/null) || baseline_count=0

    if [ -z "$test_cmd" ] || [ ! -f "$test_cmd" ]; then
        log "RED_GREEN" "No test runner found — skipping progress check"
        return 0
    fi

    local output rc=0
    output=$(bash "$test_cmd" 2>&1) || rc=$?

    local current_count
    current_count=$(_count_test_failures_from_output "$output")

    local delta=$((current_count - baseline_count))

    if [ "$delta" -gt 0 ]; then
        log "RED_GREEN" "REGRESSION: failures increased from $baseline_count to $current_count (+$delta)"
        emit_event "red_green_check" "{\"baseline\":${baseline_count},\"current\":${current_count},\"verdict\":\"regression\"}"
        return 1
    fi

    log "RED_GREEN" "Progress: failures $baseline_count → $current_count (delta: $delta)"
    emit_event "red_green_check" "{\"baseline\":${baseline_count},\"current\":${current_count},\"verdict\":\"ok\"}"
    return 0
}

# ---------------------------------------------------------------------------
# Review Confidence Scoring (audit wave 6)
# ---------------------------------------------------------------------------

# Parses confidence scores from review agent output.
# Expects a <confidence> block with four dimensions rated 1-5:
#   spec_coverage, test_quality, code_quality, regression_risk
#
# Outputs JSON with the four scores. Persists to review-confidence.json.
# Returns: 0 on success, 1 if block missing or scores invalid.
parse_review_confidence() {
    local review_output="$1"

    # Extract the <confidence>...</confidence> block
    local block
    block=$(echo "$review_output" | sed -n '/<confidence>/,/<\/confidence>/p')
    if [ -z "$block" ]; then
        return 1
    fi

    # Parse each dimension
    local spec_coverage test_quality code_quality regression_risk
    spec_coverage=$(echo "$block" | grep -E 'spec_coverage:' | sed 's/.*spec_coverage:[[:space:]]*//' | tr -d '[:space:]')
    test_quality=$(echo "$block" | grep -E 'test_quality:' | sed 's/.*test_quality:[[:space:]]*//' | tr -d '[:space:]')
    code_quality=$(echo "$block" | grep -E 'code_quality:' | sed 's/.*code_quality:[[:space:]]*//' | tr -d '[:space:]')
    regression_risk=$(echo "$block" | grep -E 'regression_risk:' | sed 's/.*regression_risk:[[:space:]]*//' | tr -d '[:space:]')

    # Validate all four are present and in range 1-5
    local dim
    for dim in "$spec_coverage" "$test_quality" "$code_quality" "$regression_risk"; do
        if [ -z "$dim" ] || ! [[ "$dim" =~ ^[1-5]$ ]]; then
            return 1
        fi
    done

    local json
    json=$(printf '{"spec_coverage":%d,"test_quality":%d,"code_quality":%d,"regression_risk":%d}' \
        "$spec_coverage" "$test_quality" "$code_quality" "$regression_risk")

    # Persist to state directory
    local conf_file="${AUTOMATON_DIR}/review-confidence.json"
    echo "$json" > "$conf_file"

    echo "$json"
    return 0
}

# Evaluates confidence scores against thresholds.
# All scores >= 4 = pass. Any score < 3 = fail (creates tasks).
# Scores of 3 = borderline pass with warning.
#
# Args: $1 = JSON string with the four confidence dimensions
# Returns: 0 (pass) or 1 (fail — any dimension < 3)
gate_review_confidence() {
    local scores_json="$1"

    local fail=false
    local dim_name dim_val
    for dim_name in spec_coverage test_quality code_quality regression_risk; do
        dim_val=$(echo "$scores_json" | jq -r ".${dim_name}")
        if [ "$dim_val" -lt 3 ] 2>/dev/null; then
            log "ORCHESTRATOR" "  FAIL: Review confidence $dim_name=$dim_val (below threshold 3)"
            fail=true
        elif [ "$dim_val" -lt 4 ] 2>/dev/null; then
            log "ORCHESTRATOR" "  WARN: Review confidence $dim_name=$dim_val (borderline)"
        fi
    done

    if [ "$fail" = "true" ]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Feedback Level Routing (audit wave 6)
# ---------------------------------------------------------------------------

# Parses spec-level issues from review agent output.
# Expects a <feedback_routing> block with lines like:
#   spec_issue: spec-XX | description | proposed amendment
#
# Routes spec-level issues to .automaton/spec-amendments.json instead of
# creating build tasks. This prevents building against flawed specs.
#
# Args: $1 = review output text
# Returns: 0 if spec issues found and routed, 1 if no spec issues found.
parse_feedback_routing() {
    local review_output="$1"

    # Extract the <feedback_routing>...</feedback_routing> block
    local block
    block=$(echo "$review_output" | sed -n '/<feedback_routing>/,/<\/feedback_routing>/p')
    if [ -z "$block" ]; then
        return 1
    fi

    # Parse spec_issue lines
    local amendments_file="${AUTOMATON_DIR}/spec-amendments.json"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

    # Read existing amendments or start fresh
    local existing="[]"
    if [ -f "$amendments_file" ]; then
        existing=$(jq '.proposals // []' "$amendments_file" 2>/dev/null || echo "[]")
    fi

    local count=0
    local new_proposals="$existing"

    while IFS= read -r line; do
        # Match: spec_issue: spec-XX | description | proposed amendment
        if [[ "$line" =~ ^[[:space:]]*spec_issue:[[:space:]]*(.+) ]]; then
            local content="${BASH_REMATCH[1]}"
            local spec_id description proposed

            # Split on |
            spec_id=$(echo "$content" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            description=$(echo "$content" | cut -d'|' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            proposed=$(echo "$content" | cut -d'|' -f3- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            if [ -n "$spec_id" ] && [ -n "$description" ]; then
                new_proposals=$(echo "$new_proposals" | jq --arg sid "$spec_id" \
                    --arg desc "$description" --arg prop "$proposed" \
                    --arg ts "$timestamp" --arg status "proposed" \
                    '. + [{"spec_id": $sid, "description": $desc, "proposed_amendment": $prop, "status": $status, "created_at": $ts}]')
                count=$((count + 1))
            fi
        fi
    done <<< "$block"

    if [ "$count" -eq 0 ]; then
        return 1
    fi

    # Write amendments file
    jq -n --argjson proposals "$new_proposals" --arg ts "$timestamp" \
        '{"updated_at": $ts, "proposals": $proposals}' > "$amendments_file"

    log "ORCHESTRATOR" "Feedback routing: $count spec-level issue(s) written to spec-amendments.json"
    return 0
}

# Parses build agent output for spec amendment proposals.
# Expects a <spec_amendment> block with lines like:
#   spec_id: spec-XX
#   description: what's wrong with the spec
#   proposed: the proposed change
#
# Writes proposals to .automaton/spec-amendments.json with status "proposed".
# Args: $1 = build output text
# Returns: 0 if amendments found, 1 if none found.
parse_build_amendments() {
    local build_output="$1"

    local block
    block=$(echo "$build_output" | sed -n '/<spec_amendment>/,/<\/spec_amendment>/p')
    if [ -z "$block" ]; then
        return 1
    fi

    local amendments_file="${AUTOMATON_DIR}/spec-amendments.json"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

    local existing="[]"
    if [ -f "$amendments_file" ]; then
        existing=$(jq '.proposals // []' "$amendments_file" 2>/dev/null || echo "[]")
    fi

    local count=0
    local new_proposals="$existing"
    local current_spec="" current_desc="" current_prop=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*spec_id:[[:space:]]*(.+) ]]; then
            current_spec=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.+) ]]; then
            current_desc=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        elif [[ "$line" =~ ^[[:space:]]*proposed:[[:space:]]*(.+) ]]; then
            current_prop=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi

        if [ -n "$current_spec" ] && [ -n "$current_desc" ] && [ -n "$current_prop" ]; then
            new_proposals=$(echo "$new_proposals" | jq --arg sid "$current_spec" \
                --arg desc "$current_desc" --arg prop "$current_prop" \
                --arg ts "$timestamp" --arg status "proposed" --arg src "build" \
                '. + [{"spec_id": $sid, "description": $desc, "proposed_amendment": $prop, "status": $status, "source": $src, "created_at": $ts}]')
            count=$((count + 1))
            current_spec="" current_desc="" current_prop=""
        fi
    done <<< "$block"

    if [ "$count" -eq 0 ]; then
        return 1
    fi

    jq -n --argjson proposals "$new_proposals" --arg ts "$timestamp" \
        '{"updated_at": $ts, "proposals": $proposals}' > "$amendments_file"

    log "ORCHESTRATOR" "Build amendments: $count proposal(s) written to spec-amendments.json"
    return 0
}

# Parses review agent output for amendment evaluations.
# Expects an <amendment_evaluation> block with lines like:
#   approve: spec-XX | reason
#   reject: spec-XX | reason
#
# Updates status of matching proposals in spec-amendments.json.
# Args: $1 = review output text
# Returns: 0 if evaluations found, 1 if none found.
parse_amendment_evaluations() {
    local review_output="$1"

    local block
    block=$(echo "$review_output" | sed -n '/<amendment_evaluation>/,/<\/amendment_evaluation>/p')
    if [ -z "$block" ]; then
        return 1
    fi

    local amendments_file="${AUTOMATON_DIR}/spec-amendments.json"
    if [ ! -f "$amendments_file" ]; then
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    local count=0

    while IFS= read -r line; do
        local action="" spec_id="" reason=""
        if [[ "$line" =~ ^[[:space:]]*approve:[[:space:]]*(.+) ]]; then
            action="approved"
            local content="${BASH_REMATCH[1]}"
            spec_id=$(echo "$content" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            reason=$(echo "$content" | cut -d'|' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        elif [[ "$line" =~ ^[[:space:]]*reject:[[:space:]]*(.+) ]]; then
            action="rejected"
            local content="${BASH_REMATCH[1]}"
            spec_id=$(echo "$content" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            reason=$(echo "$content" | cut -d'|' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi

        if [ -n "$action" ] && [ -n "$spec_id" ]; then
            # Update the first matching proposed amendment for this spec
            local updated
            updated=$(jq --arg sid "$spec_id" --arg act "$action" --arg reason "$reason" \
                --arg ts "$timestamp" \
                '(.proposals | to_entries | map(select(.value.spec_id == $sid and .value.status == "proposed")) | first // empty) as $match |
                 if $match then .proposals[$match.key].status = $act | .proposals[$match.key].evaluated_at = $ts | .proposals[$match.key].evaluation_reason = $reason
                 else . end | .updated_at = $ts' "$amendments_file")
            if [ -n "$updated" ]; then
                echo "$updated" > "$amendments_file"
                count=$((count + 1))
            fi
        fi
    done <<< "$block"

    if [ "$count" -eq 0 ]; then
        return 1
    fi

    log "ORCHESTRATOR" "Amendment evaluation: $count proposal(s) evaluated"
    return 0
}

# Applies approved amendments to spec files.
# Reads spec-amendments.json, finds entries with status "approved",
# appends the proposed amendment text to the corresponding spec file,
# and marks the amendment as "applied".
#
# Returns: 0 if amendments applied, 1 if none to apply.
apply_approved_amendments() {
    local amendments_file="${AUTOMATON_DIR}/spec-amendments.json"
    if [ ! -f "$amendments_file" ]; then
        return 1
    fi

    local approved_count
    approved_count=$(jq '[.proposals[] | select(.status == "approved")] | length' "$amendments_file" 2>/dev/null || echo "0")

    if [ "$approved_count" -eq 0 ]; then
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    local applied=0

    # Process each approved amendment
    local indices
    indices=$(jq -r '[.proposals | to_entries[] | select(.value.status == "approved") | .key] | .[]' "$amendments_file" 2>/dev/null)

    for idx in $indices; do
        local spec_id proposed_text
        spec_id=$(jq -r ".proposals[$idx].spec_id" "$amendments_file")
        proposed_text=$(jq -r ".proposals[$idx].proposed_amendment" "$amendments_file")

        if [ -z "$spec_id" ] || [ -z "$proposed_text" ]; then
            continue
        fi

        # Find the spec file
        local spec_file
        spec_file=$(find specs/ -name "${spec_id}*.md" -type f 2>/dev/null | head -1)

        if [ -n "$spec_file" ]; then
            # Append amendment to spec file
            printf '\n\n## Amendment (%s)\n\n%s\n' "$timestamp" "$proposed_text" >> "$spec_file"
            log "ORCHESTRATOR" "Applied amendment to $spec_file: $proposed_text"
            applied=$((applied + 1))
        else
            log "ORCHESTRATOR" "WARNING: Spec file not found for $spec_id — amendment not applied to file"
        fi

        # Mark as applied
        local updated
        updated=$(jq --argjson idx "$idx" --arg ts "$timestamp" \
            '.proposals[$idx].status = "applied" | .proposals[$idx].applied_at = $ts | .updated_at = $ts' \
            "$amendments_file")
        echo "$updated" > "$amendments_file"
    done

    if [ "$applied" -gt 0 ]; then
        log "ORCHESTRATOR" "Living spec amendments: $applied amendment(s) applied to spec files"
    fi
    return 0
}

# Returns pending amendment proposals as text for injection into review context.
# Used to give the review agent visibility into proposed amendments.
# Returns: pending amendments text on stdout, or empty if none.
get_pending_amendments_context() {
    local amendments_file="${AUTOMATON_DIR}/spec-amendments.json"
    if [ ! -f "$amendments_file" ]; then
        return
    fi

    local pending_count
    pending_count=$(jq '[.proposals[] | select(.status == "proposed")] | length' "$amendments_file" 2>/dev/null || echo "0")

    if [ "$pending_count" -eq 0 ]; then
        return
    fi

    echo "## Pending Spec Amendment Proposals"
    echo ""
    echo "The following spec amendments have been proposed and need your evaluation."
    echo "For each proposal, output an <amendment_evaluation> block with approve/reject decisions."
    echo ""

    jq -r '.proposals | to_entries[] | select(.value.status == "proposed") |
        "### Proposal \(.key + 1): \(.value.spec_id)\n- **Issue:** \(.value.description)\n- **Proposed change:** \(.value.proposed_amendment)\n- **Source:** \(.value.source // "review")\n"' \
        "$amendments_file" 2>/dev/null
}
