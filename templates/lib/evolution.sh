#!/usr/bin/env bash
# lib/evolution.sh — Evolution loop: reflect, ideate, evaluate, implement, observe cycles.
# Spec references: spec-41 (evolution system), spec-44 (evolution CLI)

_evolve_reflect() {
    local cycle_id="${1:?_evolve_reflect requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "REFLECT phase starting (cycle=$cycle_id)"

    local signals_emitted=0
    local ideas_seeded=0
    local ideas_pruned=0
    local signals_decayed=0
    local metric_alerts="[]"

    # 1. Analyze metric trends
    local trends
    trends=$(_metrics_analyze_trends "${METRICS_TREND_WINDOW:-5}")

    # Extract degrading metrics with alerts
    metric_alerts=$(echo "$trends" | jq '[.[] | select(.alert == true)]' 2>/dev/null || echo "[]")
    local alert_count
    alert_count=$(echo "$metric_alerts" | jq 'length' 2>/dev/null || echo 0)

    if [ "$alert_count" -gt 0 ]; then
        log "EVOLVE" "REFLECT: $alert_count metric alerts detected"
    fi

    # 2. Emit signals for degrading metrics
    local i=0
    while [ "$i" -lt "$alert_count" ]; do
        local metric_name metric_dir consec_deg category
        metric_name=$(echo "$metric_alerts" | jq -r ".[$i].metric")
        metric_dir=$(echo "$metric_alerts" | jq -r ".[$i].direction")
        consec_deg=$(echo "$metric_alerts" | jq -r ".[$i].consecutive_degrading")
        category=$(echo "$metric_alerts" | jq -r ".[$i].category")

        _signal_emit "attention_needed" \
            "Degrading metric: $metric_name" \
            "$metric_name has been $metric_dir for $consec_deg consecutive cycles (category: $category)" \
            "evolve-reflect" "$cycle_id" \
            "metric=$metric_name,direction=$metric_dir,consecutive=$consec_deg" \
            && signals_emitted=$((signals_emitted + 1))

        i=$((i + 1))
    done

    # 3. Auto-seed garden ideas from metric threshold breaches
    if [ "${GARDEN_AUTO_SEED_METRICS:-true}" = "true" ] && [ "$alert_count" -gt 0 ]; then
        i=0
        while [ "$i" -lt "$alert_count" ]; do
            local metric_name category
            metric_name=$(echo "$metric_alerts" | jq -r ".[$i].metric")
            category=$(echo "$metric_alerts" | jq -r ".[$i].category")

            local tags="auto-seed,metrics,$category,$metric_name"
            local dup_id
            dup_id=$(_garden_find_duplicates "$tags" 2>/dev/null) || true

            if [ -z "$dup_id" ]; then
                local seed_id
                seed_id=$(_garden_plant_seed \
                    "Improve $metric_name" \
                    "Metric $metric_name in category $category has been degrading. Investigate root cause and implement improvement." \
                    "metric_alert" "evolve-reflect" "evolve-reflect" \
                    "medium" "$tags") && ideas_seeded=$((ideas_seeded + 1))
                log "EVOLVE" "REFLECT: Auto-seeded idea from metric alert: $metric_name"
            else
                _garden_water "$dup_id" "metric_trend" \
                    "Metric $metric_name still degrading (cycle $cycle_id)" \
                    "evolve-reflect"
                log "EVOLVE" "REFLECT: Watered existing idea $dup_id for metric: $metric_name"
            fi

            i=$((i + 1))
        done
    fi

    # 4. Auto-seed garden ideas from strong unlinked signals
    if [ "${GARDEN_AUTO_SEED_SIGNALS:-true}" = "true" ]; then
        local unlinked_signals
        unlinked_signals=$(_signal_get_unlinked 2>/dev/null || echo "[]")
        local unlinked_count
        unlinked_count=$(echo "$unlinked_signals" | jq 'length' 2>/dev/null || echo 0)

        local seed_threshold="${GARDEN_SIGNAL_SEED_THRESHOLD:-0.7}"
        local j=0
        while [ "$j" -lt "$unlinked_count" ]; do
            local sig_strength sig_title sig_desc sig_id sig_type
            sig_strength=$(echo "$unlinked_signals" | jq -r ".[$j].strength")
            sig_title=$(echo "$unlinked_signals" | jq -r ".[$j].title")
            sig_desc=$(echo "$unlinked_signals" | jq -r ".[$j].description")
            sig_id=$(echo "$unlinked_signals" | jq -r ".[$j].id")
            sig_type=$(echo "$unlinked_signals" | jq -r ".[$j].type")

            local above_threshold
            above_threshold=$(awk -v s="$sig_strength" -v t="$seed_threshold" \
                'BEGIN { print (s >= t) ? "1" : "0" }')

            if [ "$above_threshold" = "1" ]; then
                local tags="auto-seed,signal,$sig_type"
                local dup_id
                dup_id=$(_garden_find_duplicates "$tags" 2>/dev/null) || true

                if [ -z "$dup_id" ]; then
                    local seed_id
                    seed_id=$(_garden_plant_seed \
                        "Address: $sig_title" \
                        "$sig_desc (auto-seeded from strong unlinked signal $sig_id)" \
                        "signal" "evolve-reflect" "evolve-reflect" \
                        "medium" "$tags")
                    if [ -n "$seed_id" ]; then
                        _signal_link_idea "$sig_id" "$seed_id"
                        ideas_seeded=$((ideas_seeded + 1))
                        log "EVOLVE" "REFLECT: Auto-seeded idea $seed_id from signal $sig_id"
                    fi
                else
                    _garden_water "$dup_id" "signal_observation" \
                        "Signal $sig_id ($sig_title) still strong at $sig_strength" \
                        "evolve-reflect"
                    _signal_link_idea "$sig_id" "$dup_id"
                    log "EVOLVE" "REFLECT: Watered existing idea $dup_id from signal $sig_id"
                fi
            fi

            j=$((j + 1))
        done
    fi

    # 5. Prune expired garden items
    local pre_prune_total=0
    if [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local index_file="$AUTOMATON_DIR/garden/_index.json"
        if [ -f "$index_file" ]; then
            pre_prune_total=$(jq '.total // 0' "$index_file" 2>/dev/null || echo 0)
        fi
        _garden_prune_expired
        if [ -f "$index_file" ]; then
            local post_prune_total
            post_prune_total=$(jq '.total // 0' "$index_file" 2>/dev/null || echo 0)
            # Note: wilt increases total, so pruned = ideas that moved to wilt
            # We track via the rebuild count difference
        fi
        _garden_rebuild_index
    fi
    log "EVOLVE" "REFLECT: Garden pruning complete"

    # 6. Decay all signals
    local pre_decay_count=0
    if [ -f "$AUTOMATON_DIR/signals.json" ]; then
        pre_decay_count=$(jq '.signals | length' "$AUTOMATON_DIR/signals.json" 2>/dev/null || echo 0)
    fi
    _signal_decay_all 2>/dev/null || true
    local post_decay_count=0
    if [ -f "$AUTOMATON_DIR/signals.json" ]; then
        post_decay_count=$(jq '.signals | length' "$AUTOMATON_DIR/signals.json" 2>/dev/null || echo 0)
    fi
    signals_decayed=$((pre_decay_count - post_decay_count))
    if [ "$signals_decayed" -lt 0 ]; then signals_decayed=0; fi

    # 7. Build recommendation from metric alerts
    local recommendation="No significant issues detected"
    if [ "$alert_count" -gt 0 ]; then
        local top_metric
        top_metric=$(echo "$metric_alerts" | jq -r '.[0].metric // "unknown"')
        recommendation="Focus on $top_metric — degrading trend detected"
    fi

    # 8. Write reflect.json
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson metric_alerts "$metric_alerts" \
        --argjson signals_emitted "$signals_emitted" \
        --argjson ideas_seeded "$ideas_seeded" \
        --argjson ideas_pruned "$ideas_pruned" \
        --argjson signals_decayed "$signals_decayed" \
        --arg recommendation "$recommendation" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            metric_alerts: $metric_alerts,
            signals_emitted: $signals_emitted,
            ideas_seeded: $ideas_seeded,
            ideas_pruned: $ideas_pruned,
            signals_decayed: $signals_decayed,
            recommendation: $recommendation
        }' > "$cycle_dir/reflect.json"

    log "EVOLVE" "REFLECT phase complete: signals_emitted=$signals_emitted ideas_seeded=$ideas_seeded signals_decayed=$signals_decayed"
    return 0
}

_evolve_ideate() {
    local cycle_id="${1:?_evolve_ideate requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "IDEATE phase starting (cycle=$cycle_id)"

    local ideas_watered=0
    local ideas_promoted_to_bloom=0
    local ideas_created=0
    local ideas_linked=0

    # 1. Read reflection summary from REFLECT phase
    local reflect_file="$cycle_dir/reflect.json"
    local metric_alerts="[]"
    local reflect_recommendation=""
    if [ -f "$reflect_file" ]; then
        metric_alerts=$(jq '.metric_alerts // []' "$reflect_file" 2>/dev/null || echo "[]")
        reflect_recommendation=$(jq -r '.recommendation // ""' "$reflect_file" 2>/dev/null || echo "")
    else
        log "EVOLVE" "IDEATE: No reflect.json found, proceeding without reflection summary"
    fi

    # 2. Gather active signals for cross-referencing
    local active_signals="[]"
    active_signals=$(_signal_get_active 2>/dev/null || echo "[]")
    local active_signal_count
    active_signal_count=$(echo "$active_signals" | jq 'length' 2>/dev/null || echo 0)

    # 3. Water existing sprouts with evidence from metric alerts
    local alert_count
    alert_count=$(echo "$metric_alerts" | jq 'length' 2>/dev/null || echo 0)

    if [ "$alert_count" -gt 0 ] && [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local garden_dir="$AUTOMATON_DIR/garden"
        local sprout_files
        sprout_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

        for idea_file in $sprout_files; do
            [ -f "$idea_file" ] || continue
            local stage idea_id idea_tags
            stage=$(jq -r '.stage' "$idea_file" 2>/dev/null)
            [ "$stage" = "seed" ] || [ "$stage" = "sprout" ] || continue

            idea_id=$(jq -r '.id' "$idea_file" 2>/dev/null)
            idea_tags=$(jq -r '.tags // [] | join(",")' "$idea_file" 2>/dev/null)

            # Check if any metric alert relates to this idea's tags
            local i=0
            while [ "$i" -lt "$alert_count" ]; do
                local metric_name
                metric_name=$(echo "$metric_alerts" | jq -r ".[$i].metric" 2>/dev/null)

                if echo "$idea_tags" | grep -qi "$metric_name" 2>/dev/null; then
                    _garden_water "$idea_id" "ideate_evidence" \
                        "Metric $metric_name still alerting in cycle $cycle_id (IDEATE enrichment)" \
                        "evolve-ideate" 2>/dev/null && ideas_watered=$((ideas_watered + 1))
                    break
                fi
                i=$((i + 1))
            done
        done
    fi

    # 4. Water ideas with evidence from active signals
    if [ "$active_signal_count" -gt 0 ] && [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local garden_dir="$AUTOMATON_DIR/garden"
        local idea_files
        idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

        local s=0
        while [ "$s" -lt "$active_signal_count" ]; do
            local sig_id sig_title sig_related_ideas
            sig_id=$(echo "$active_signals" | jq -r ".[$s].id" 2>/dev/null)
            sig_title=$(echo "$active_signals" | jq -r ".[$s].title" 2>/dev/null)
            sig_related_ideas=$(echo "$active_signals" | jq -r ".[$s].related_ideas // [] | .[]" 2>/dev/null)

            # Water ideas already linked to this signal
            for linked_id in $sig_related_ideas; do
                [ -n "$linked_id" ] || continue
                local linked_file="$garden_dir/${linked_id}.json"
                [ -f "$linked_file" ] || continue
                local linked_stage
                linked_stage=$(jq -r '.stage' "$linked_file" 2>/dev/null)
                if [ "$linked_stage" = "seed" ] || [ "$linked_stage" = "sprout" ]; then
                    _garden_water "$linked_id" "signal_reinforcement" \
                        "Signal $sig_id ($sig_title) still active in cycle $cycle_id" \
                        "evolve-ideate" 2>/dev/null && ideas_watered=$((ideas_watered + 1))
                fi
            done

            # Link unlinked signals to ideas with matching tags
            if [ -z "$sig_related_ideas" ]; then
                local sig_type
                sig_type=$(echo "$active_signals" | jq -r ".[$s].type" 2>/dev/null)
                for idea_file in $idea_files; do
                    [ -f "$idea_file" ] || continue
                    local idea_stage idea_id idea_tags
                    idea_stage=$(jq -r '.stage' "$idea_file" 2>/dev/null)
                    [ "$idea_stage" = "seed" ] || [ "$idea_stage" = "sprout" ] || continue

                    idea_tags=$(jq -r '.tags // [] | join(" ")' "$idea_file" 2>/dev/null)
                    idea_id=$(jq -r '.id' "$idea_file" 2>/dev/null)

                    if echo "$idea_tags" | grep -qi "$sig_type" 2>/dev/null; then
                        _signal_link_idea "$sig_id" "$idea_id" 2>/dev/null && ideas_linked=$((ideas_linked + 1))
                        break
                    fi
                done
            fi

            s=$((s + 1))
        done
    fi

    # 5. Create new ideas from reflection patterns not yet in garden
    if [ -n "$reflect_recommendation" ] && [ "$reflect_recommendation" != "No significant issues detected" ] && [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        local tags="auto-seed,ideate,reflection"
        local dup_id
        dup_id=$(_garden_find_duplicates "$tags" 2>/dev/null) || true

        if [ -z "$dup_id" ]; then
            local seed_id
            seed_id=$(_garden_plant_seed \
                "From reflection: $reflect_recommendation" \
                "Auto-seeded from IDEATE phase based on REFLECT recommendation: $reflect_recommendation (cycle $cycle_id)" \
                "ideate" "evolve-ideate" "evolve-ideate" \
                "medium" "$tags") && ideas_created=$((ideas_created + 1))
            if [ -n "$seed_id" ]; then
                log "EVOLVE" "IDEATE: Created idea $seed_id from reflection recommendation"
            fi
        fi
    fi

    # 6. Evaluate sprout-to-bloom transitions and collect bloom candidates
    local bloom_candidates_json="[]"
    if [ "${GARDEN_ENABLED:-true}" = "true" ]; then
        _garden_recompute_priorities 2>/dev/null || true

        local bloom_ids
        bloom_ids=$(_garden_get_bloom_candidates 2>/dev/null) || true

        if [ -n "$bloom_ids" ]; then
            local candidates_arr="["
            local first=true
            for bid in $bloom_ids; do
                local bfile="$AUTOMATON_DIR/garden/${bid}.json"
                [ -f "$bfile" ] || continue
                local btitle bpriority
                btitle=$(jq -r '.title' "$bfile" 2>/dev/null)
                bpriority=$(jq -r '.priority // 0' "$bfile" 2>/dev/null)
                ideas_promoted_to_bloom=$((ideas_promoted_to_bloom + 1))

                if [ "$first" = "true" ]; then
                    first=false
                else
                    candidates_arr="${candidates_arr},"
                fi
                candidates_arr="${candidates_arr}{\"id\":\"$bid\",\"title\":$(echo "$btitle" | jq -Rs .),\"priority\":$bpriority}"
            done
            candidates_arr="${candidates_arr}]"
            bloom_candidates_json="$candidates_arr"
        fi

        _garden_rebuild_index 2>/dev/null || true
    fi

    # 7. Write ideate.json
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson ideas_watered "$ideas_watered" \
        --argjson ideas_promoted_to_bloom "$ideas_promoted_to_bloom" \
        --argjson ideas_created "$ideas_created" \
        --argjson ideas_linked "$ideas_linked" \
        --argjson bloom_candidates "$bloom_candidates_json" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            ideas_watered: $ideas_watered,
            ideas_promoted_to_bloom: $ideas_promoted_to_bloom,
            ideas_created: $ideas_created,
            ideas_linked: $ideas_linked,
            bloom_candidates: $bloom_candidates
        }' > "$cycle_dir/ideate.json"

    log "EVOLVE" "IDEATE phase complete: watered=$ideas_watered promoted=$ideas_promoted_to_bloom created=$ideas_created linked=$ideas_linked"
    return 0
}

# EVALUATE phase (spec-41 §5): runs the agent quorum on bloom-stage ideas.
# Selects the highest-priority bloom candidate, invokes _quorum_evaluate_bloom(),
# and writes evaluate.json to the cycle directory. Skips to OBSERVE if no bloom
# candidates exist. Only the highest-priority candidate is evaluated per cycle
# (Article VI: incremental growth).
#
# Usage: _evolve_evaluate <cycle_id>
# Args:  cycle_id — the current evolution cycle number
_evolve_evaluate() {
    local cycle_id="${1:?_evolve_evaluate requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "EVALUATE phase starting (cycle=$cycle_id)"

    # Read ideate.json for bloom candidates context
    local ideate_file="$cycle_dir/ideate.json"
    local bloom_candidates_count=0
    if [ -f "$ideate_file" ]; then
        bloom_candidates_count=$(jq '.bloom_candidates | length' "$ideate_file" 2>/dev/null || echo 0)
    fi

    # Get bloom candidates from the garden
    local candidates=""
    candidates=$(_garden_get_bloom_candidates 2>/dev/null) || true

    if [ -z "$candidates" ]; then
        log "EVOLVE" "EVALUATE: No bloom candidates — skipping to OBSERVE"

        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq -n \
            --argjson cycle_id "$cycle_id" \
            --arg timestamp "$now" \
            --argjson bloom_candidates_count "$bloom_candidates_count" \
            --arg evaluated "none" \
            --arg vote_id "none" \
            --arg result "skipped" \
            --arg conditions "[]" \
            --argjson tokens_used 0 \
            '{
                cycle_id: $cycle_id,
                timestamp: $timestamp,
                bloom_candidates_count: $bloom_candidates_count,
                evaluated: $evaluated,
                vote_id: $vote_id,
                result: $result,
                conditions: $conditions,
                tokens_used: $tokens_used
            }' > "$cycle_dir/evaluate.json"

        return 0
    fi

    # Select highest-priority candidate (first line from sorted output)
    local idea_id
    idea_id=$(echo "$candidates" | head -1)
    local candidate_count
    candidate_count=$(echo "$candidates" | wc -l | tr -d ' ')
    bloom_candidates_count=$candidate_count

    log "EVOLVE" "EVALUATE: $candidate_count bloom candidate(s), evaluating $idea_id"

    # Reset quorum cycle token counter for this evaluation
    _QUORUM_CYCLE_TOKENS=0

    # Invoke the quorum evaluation (handles voting, vote record, and idea advancement/wilting)
    local vote_file=""
    vote_file=$(_quorum_evaluate_bloom 2>/dev/null) || true

    # Extract vote result from the vote record
    local vote_id="none"
    local eval_result="unknown"
    local conditions="[]"
    local tokens_used="${_QUORUM_CYCLE_TOKENS:-0}"

    if [ -n "$vote_file" ] && [ -f "$vote_file" ]; then
        vote_id=$(jq -r '.vote_id // "none"' "$vote_file" 2>/dev/null || echo "none")
        eval_result=$(jq -r '.tally.result // "unknown"' "$vote_file" 2>/dev/null || echo "unknown")
        conditions=$(jq '.tally.conditions // []' "$vote_file" 2>/dev/null || echo "[]")
    elif [ "${QUORUM_ENABLED:-true}" != "true" ]; then
        eval_result="approved"
        vote_id="auto-approved"
    fi

    # Write evaluate.json
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson bloom_candidates_count "$bloom_candidates_count" \
        --arg evaluated "$idea_id" \
        --arg vote_id "$vote_id" \
        --arg result "$eval_result" \
        --argjson conditions "$conditions" \
        --argjson tokens_used "$tokens_used" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            bloom_candidates_count: $bloom_candidates_count,
            evaluated: $evaluated,
            vote_id: $vote_id,
            result: $result,
            conditions: $conditions,
            tokens_used: $tokens_used
        }' > "$cycle_dir/evaluate.json"

    log "EVOLVE" "EVALUATE phase complete: evaluated=$idea_id result=$eval_result vote=$vote_id tokens=$tokens_used"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution: IMPLEMENT Phase (spec-41 §6)
# ---------------------------------------------------------------------------

# Implements the approved idea on a dedicated evolution branch using the
# standard build pipeline with self-build safety constraints. Runs review
# and constitutional compliance check on the resulting diff. If compliance
# fails, abandons the branch and wilts the idea with a quality_concern signal.
#
# Reads evaluate.json from the cycle directory to determine which idea was
# approved and what conditions were set. Writes implement.json with results.
#
# Usage: _evolve_implement "001"
# Returns: 0 on success (including skipped), 1 on unrecoverable error
_evolve_implement() {
    local cycle_id="${1:?_evolve_implement requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "IMPLEMENT phase starting (cycle=$cycle_id)"

    # Read evaluate.json to determine approved idea and conditions
    local eval_file="$cycle_dir/evaluate.json"
    if [ ! -f "$eval_file" ]; then
        log "EVOLVE" "IMPLEMENT: No evaluate.json found — skipping"
        _write_implement_json "$cycle_dir" "$cycle_id" "" "" 0 0 0 0 "skipped" "skipped" "skipped" "skipped" 0
        return 0
    fi

    local eval_result
    eval_result=$(jq -r '.result // "unknown"' "$eval_file" 2>/dev/null || echo "unknown")
    local idea_id
    idea_id=$(jq -r '.evaluated // "none"' "$eval_file" 2>/dev/null || echo "none")
    local conditions
    conditions=$(jq -r '.conditions // "[]"' "$eval_file" 2>/dev/null || echo "[]")

    # Skip if no idea was approved
    if [ "$eval_result" != "approved" ] || [ "$idea_id" = "none" ]; then
        log "EVOLVE" "IMPLEMENT: No approved idea (result=$eval_result) — skipping"
        _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "" 0 0 0 0 "skipped" "skipped" "skipped" "skipped" 0
        return 0
    fi

    log "EVOLVE" "IMPLEMENT: Building idea=$idea_id on evolution branch"

    # 1. Create a dedicated evolution branch
    if ! _safety_branch_create "$cycle_id" "$idea_id"; then
        log "EVOLVE" "IMPLEMENT: Failed to create evolution branch — aborting"
        _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "" 0 0 0 0 "failed" "skipped" "skipped" "failed" 0
        return 1
    fi

    local branch
    branch=$(_safety_branch_get_name "$cycle_id" "$idea_id")

    # 2. Generate an implementation plan from the approved idea
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    local idea_title="" idea_description=""
    if [ -f "$idea_file" ]; then
        idea_title=$(jq -r '.title // "Untitled"' "$idea_file" 2>/dev/null || echo "Untitled")
        idea_description=$(jq -r '.description // ""' "$idea_file" 2>/dev/null || echo "")
    fi

    # Write a minimal implementation plan on the evolution branch
    local plan_content="# Evolution Implementation Plan\n\n"
    plan_content+="## Cycle ${cycle_id} — ${idea_title}\n\n"
    plan_content+="${idea_description}\n\n"
    if [ "$conditions" != "[]" ] && [ -n "$conditions" ]; then
        plan_content+="### Conditions from Quorum\n\n"
        plan_content+="$conditions\n\n"
    fi
    plan_content+="## Tasks\n\n- [ ] Implement: ${idea_title}\n"
    printf "%b" "$plan_content" > IMPLEMENTATION_PLAN.md
    git add IMPLEMENTATION_PLAN.md 2>/dev/null || true
    git commit -m "Evolution cycle $cycle_id: plan for $idea_id — $idea_title" --allow-empty 2>/dev/null || true

    # 3. Run the build pipeline with self-build safety
    local build_iterations=0
    local max_build_iterations="${EVOLVE_MAX_BUILD_ITERATIONS:-3}"
    local build_success="false"
    local build_tokens=0

    while [ "$build_iterations" -lt "$max_build_iterations" ]; do
        build_iterations=$((build_iterations + 1))
        log "EVOLVE" "IMPLEMENT: Build iteration $build_iterations/$max_build_iterations"

        run_agent "PROMPT_build.md" "${EVOLUTION_BUILD_MODEL:-sonnet}"

        if [ "$AGENT_EXIT_CODE" -eq 0 ]; then
            build_success="true"
            break
        fi
    done

    # 4. Count changes on the evolution branch
    local files_changed=0 lines_changed=0 tests_added=0
    local diff_stat
    diff_stat=$(git diff --stat "$WORKING_BRANCH"...HEAD 2>/dev/null || echo "")
    if [ -n "$diff_stat" ]; then
        files_changed=$(echo "$diff_stat" | tail -1 | grep -oP '\d+ files?' | grep -oP '\d+' || echo 0)
        lines_changed=$(echo "$diff_stat" | tail -1 | grep -oP '\d+ insertion|deletion' | grep -oP '\d+' | paste -sd+ - | bc 2>/dev/null || echo 0)
        tests_added=$(git diff "$WORKING_BRANCH"...HEAD --name-only 2>/dev/null | grep -c '^tests/') || tests_added=0
    fi

    # 5. Run syntax check
    local syntax_result="passed"
    if ! bash -n automaton.sh 2>/dev/null; then
        syntax_result="failed"
    fi

    # 6. Run sandbox testing
    local sandbox_result="passed"
    if ! _safety_sandbox_test "$branch" 2>/dev/null; then
        sandbox_result="failed"
    fi

    # 7. Run review pipeline
    local review_result="passed"
    run_agent "PROMPT_review.md" "${EVOLUTION_REVIEW_MODEL:-opus}" 2>/dev/null || true

    # 8. Run constitutional compliance check on the resulting diff
    local constitution_result="passed"
    local diff_file="$cycle_dir/implement_diff.tmp"
    git diff "$WORKING_BRANCH"...HEAD > "$diff_file" 2>/dev/null || true

    if [ -s "$diff_file" ]; then
        constitution_result=$(_constitution_check "$diff_file" "$idea_id" "$cycle_id" 2>/dev/null || echo "warn")
    fi
    rm -f "$diff_file"

    # 9. Handle failures: abandon branch and wilt idea
    if [ "$syntax_result" = "failed" ] || [ "$constitution_result" = "fail" ] || [ "$sandbox_result" = "failed" ]; then
        local fail_reason="compliance"
        [ "$syntax_result" = "failed" ] && fail_reason="syntax check failed"
        [ "$sandbox_result" = "failed" ] && fail_reason="sandbox testing failed"
        [ "$constitution_result" = "fail" ] && fail_reason="constitutional compliance failed"

        log "EVOLVE" "IMPLEMENT: Compliance failure ($fail_reason) — rolling back"

        # _safety_rollback handles: abandon branch, wilt idea, emit quality_concern signal
        if ! _safety_rollback "$cycle_id" "$idea_id" "$fail_reason" 2>/dev/null; then
            # Fallback: emit quality_concern signal directly if rollback failed
            _signal_emit "quality_concern" \
                "Implementation of $idea_id failed" \
                "Compliance failure: $fail_reason" \
                "evolve" "$cycle_id" "" 2>/dev/null || true
        fi

        _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "$branch" \
            "$build_iterations" "$files_changed" "$lines_changed" "$tests_added" \
            "$syntax_result" "$sandbox_result" "$constitution_result" "failed" "$build_tokens"
        return 0
    fi

    # Success — stay on evolution branch for OBSERVE to decide merge
    _write_implement_json "$cycle_dir" "$cycle_id" "$idea_id" "$branch" \
        "$build_iterations" "$files_changed" "$lines_changed" "$tests_added" \
        "$syntax_result" "$sandbox_result" "$constitution_result" "completed" "$build_tokens"

    log "EVOLVE" "IMPLEMENT phase complete: idea=$idea_id branch=$branch files=$files_changed lines=$lines_changed syntax=$syntax_result constitution=$constitution_result"
    return 0
}

# Helper: write implement.json with all required fields.
_write_implement_json() {
    local cycle_dir="$1" cycle_id="$2" idea_id="$3" branch="$4"
    local iterations="$5" files_changed="$6" lines_changed="$7" tests_added="$8"
    local syntax_check="$9" smoke_test="${10}" constitution_check="${11}"
    local status="${12}" tokens_used="${13}"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "${cycle_id:-0}" \
        --arg timestamp "$now" \
        --arg idea_id "${idea_id:-none}" \
        --arg branch "${branch:-none}" \
        --argjson iterations "${iterations:-0}" \
        --argjson files_changed "${files_changed:-0}" \
        --argjson lines_changed "${lines_changed:-0}" \
        --argjson tests_added "${tests_added:-0}" \
        --arg syntax_check "${syntax_check:-skipped}" \
        --arg smoke_test "${smoke_test:-skipped}" \
        --arg constitution_check "${constitution_check:-skipped}" \
        --arg status "${status:-unknown}" \
        --argjson tokens_used "${tokens_used:-0}" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            idea_id: $idea_id,
            branch: $branch,
            iterations: $iterations,
            files_changed: $files_changed,
            lines_changed: $lines_changed,
            tests_added: $tests_added,
            syntax_check: $syntax_check,
            smoke_test: $smoke_test,
            constitution_check: $constitution_check,
            status: $status,
            tokens_used: $tokens_used
        }' > "$cycle_dir/implement.json"
}

# ---------------------------------------------------------------------------
# Evolution: OBSERVE Phase (spec-41 §7)
# ---------------------------------------------------------------------------

# Validates the impact of an evolution implementation by comparing pre-cycle
# and post-cycle metrics, running sandbox tests, and deciding the outcome:
# - harvest: merge branch, advance idea to harvest, emit promising_approach
# - wilt: rollback, emit quality_concern signal
# - neutral: merge branch, emit attention_needed signal
#
# Reads implement.json from the cycle directory to determine which idea and
# branch to evaluate. Writes observe.json with the outcome and metrics delta.
#
# Usage: _evolve_observe "001"
# Returns: 0 on success (including skipped), 1 on unrecoverable error
_evolve_observe() {
    local cycle_id="${1:?_evolve_observe requires cycle_id}"
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${cycle_id}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "OBSERVE phase starting (cycle=$cycle_id)"

    # Read implement.json to determine idea and branch
    local impl_file="$cycle_dir/implement.json"
    if [ ! -f "$impl_file" ]; then
        log "EVOLVE" "OBSERVE: No implement.json found — skipping"
        _write_observe_json "$cycle_dir" "$cycle_id" "" "{}" "{}" "{}" "0.00" "skipped" 0
        return 0
    fi

    local impl_status
    impl_status=$(jq -r '.status // "unknown"' "$impl_file" 2>/dev/null || echo "unknown")
    local idea_id
    idea_id=$(jq -r '.idea_id // "none"' "$impl_file" 2>/dev/null || echo "none")
    local branch
    branch=$(jq -r '.branch // "none"' "$impl_file" 2>/dev/null || echo "none")

    # Skip if implementation was not completed
    if [ "$impl_status" != "completed" ] || [ "$idea_id" = "none" ]; then
        log "EVOLVE" "OBSERVE: Implementation status=$impl_status — skipping observation"
        _write_observe_json "$cycle_dir" "$cycle_id" "$idea_id" "{}" "{}" "{}" "0.00" "skipped" 0
        return 0
    fi

    log "EVOLVE" "OBSERVE: Evaluating idea=$idea_id branch=$branch"

    # 1. Take a post-cycle metrics snapshot
    _metrics_snapshot "$cycle_id" 2>/dev/null || true

    # 2. Get pre-cycle and post-cycle snapshots for comparison
    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    local pre_snapshot="{}" post_snapshot="{}"

    if [ -f "$metrics_file" ]; then
        local snap_count
        snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
        if [ "$snap_count" -ge 2 ]; then
            pre_snapshot=$(jq '.snapshots[-2]' "$metrics_file" 2>/dev/null || echo "{}")
            post_snapshot=$(jq '.snapshots[-1]' "$metrics_file" 2>/dev/null || echo "{}")
        elif [ "$snap_count" -ge 1 ]; then
            post_snapshot=$(jq '.snapshots[-1]' "$metrics_file" 2>/dev/null || echo "{}")
        fi
    fi

    # 3. Compare pre and post metrics
    local comparison="{}"
    comparison=$(_metrics_compare "$pre_snapshot" "$post_snapshot" 2>/dev/null || echo '{"deltas":[],"summary":{"improved":0,"degraded":0,"unchanged":0}}')

    local improved degraded
    improved=$(echo "$comparison" | jq '.summary.improved // 0' 2>/dev/null || echo 0)
    degraded=$(echo "$comparison" | jq '.summary.degraded // 0' 2>/dev/null || echo 0)

    # 4. Run sandbox testing on the evolution branch
    local sandbox_passed="true"
    if ! _safety_sandbox_test "$branch" 2>/dev/null; then
        sandbox_passed="false"
    fi

    # 5. Compute test pass rate from post snapshot
    local test_pass_rate="0.00"
    test_pass_rate=$(echo "$post_snapshot" | jq -r '.quality.test_pass_rate // "0.00"' 2>/dev/null || echo "0.00")

    # 6. Decide outcome based on metrics delta and sandbox results
    local outcome="neutral"
    local signals_emitted=0

    if [ "$sandbox_passed" = "false" ]; then
        # Sandbox failure → regression → rollback
        outcome="wilt"
    elif [ "$degraded" -gt "$improved" ]; then
        # More metrics degraded than improved → regression
        outcome="wilt"
    elif [ "$improved" -gt 0 ] && [ "$degraded" -eq 0 ]; then
        # Improvement detected with no regression → harvest
        outcome="harvest"
    elif [ "$improved" -gt "$degraded" ]; then
        # Net improvement → harvest
        outcome="harvest"
    fi
    # Default: neutral (no measurable change or mixed results with no net direction)

    log "EVOLVE" "OBSERVE: outcome=$outcome improved=$improved degraded=$degraded sandbox=$sandbox_passed"

    # 7. Execute the outcome
    case "$outcome" in
        harvest)
            # Merge the evolution branch into working branch
            if _safety_branch_merge "$cycle_id" "$idea_id" 2>/dev/null; then
                # Advance idea to harvest stage
                _garden_advance_stage "$idea_id" "harvest" "Cycle $cycle_id: metrics improved" "true" 2>/dev/null || true

                # Emit promising_approach signal
                _signal_emit "promising_approach" \
                    "Implementation of $idea_id improved metrics" \
                    "Cycle $cycle_id: $improved metrics improved, $degraded degraded" \
                    "evolve" "$cycle_id" "" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))

                log "EVOLVE" "OBSERVE: Harvested idea=$idea_id — branch merged"
            else
                # Merge failed — treat as regression
                outcome="wilt"
                log "EVOLVE" "OBSERVE: Merge failed — falling back to rollback"
                _safety_rollback "$cycle_id" "$idea_id" "Merge failure during OBSERVE" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))
            fi
            ;;
        wilt)
            # Rollback: abandon branch, wilt idea, emit quality_concern
            _safety_rollback "$cycle_id" "$idea_id" "Regression detected in OBSERVE phase" 2>/dev/null || true
            signals_emitted=$((signals_emitted + 1))
            log "EVOLVE" "OBSERVE: Wilted idea=$idea_id — rolled back"
            ;;
        neutral)
            # Merge with attention signal
            if _safety_branch_merge "$cycle_id" "$idea_id" 2>/dev/null; then
                # Advance idea to harvest (merged but needs monitoring)
                _garden_advance_stage "$idea_id" "harvest" "Cycle $cycle_id: neutral result, merged for monitoring" "true" 2>/dev/null || true

                # Emit attention_needed signal
                _signal_emit "attention_needed" \
                    "Implementation of $idea_id had no measurable impact" \
                    "Cycle $cycle_id: $improved improved, $degraded degraded — monitor in future cycles" \
                    "evolve" "$cycle_id" "" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))

                log "EVOLVE" "OBSERVE: Merged idea=$idea_id with attention_needed signal"
            else
                outcome="wilt"
                log "EVOLVE" "OBSERVE: Merge failed for neutral outcome — falling back to rollback"
                _safety_rollback "$cycle_id" "$idea_id" "Merge failure during OBSERVE (neutral)" 2>/dev/null || true
                signals_emitted=$((signals_emitted + 1))
            fi
            ;;
    esac

    # 8. Rebuild the garden index to reflect any stage changes
    _garden_rebuild_index 2>/dev/null || true

    # 9. Build delta summary for observe.json
    local delta_json="{}"
    delta_json=$(echo "$comparison" | jq '.deltas | map({(.metric): .delta}) | add // {}' 2>/dev/null || echo "{}")

    # Extract pre/post summaries for the output
    local pre_metrics_json="{}"
    local post_metrics_json="{}"
    pre_metrics_json=$(echo "$comparison" | jq '[.deltas[] | {(.metric): .before}] | add // {}' 2>/dev/null || echo "{}")
    post_metrics_json=$(echo "$comparison" | jq '[.deltas[] | {(.metric): .after}] | add // {}' 2>/dev/null || echo "{}")

    # Write observe.json
    _write_observe_json "$cycle_dir" "$cycle_id" "$idea_id" \
        "$pre_metrics_json" "$post_metrics_json" "$delta_json" \
        "$test_pass_rate" "$outcome" "$signals_emitted"

    log "EVOLVE" "OBSERVE phase complete: idea=$idea_id outcome=$outcome signals=$signals_emitted"
    return 0
}

# Helper: write observe.json with all required fields.
_write_observe_json() {
    local cycle_dir="$1" cycle_id="$2" idea_id="$3"
    local pre_metrics="$4" post_metrics="$5" delta="$6"
    local test_pass_rate="$7" outcome="$8" signals_emitted="$9"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --argjson cycle_id "${cycle_id:-0}" \
        --arg timestamp "$now" \
        --arg idea_id "${idea_id:-none}" \
        --argjson pre_metrics "${pre_metrics:-{}}" \
        --argjson post_metrics "${post_metrics:-{}}" \
        --argjson delta "${delta:-{}}" \
        --arg test_pass_rate "${test_pass_rate:-0.00}" \
        --arg outcome "${outcome:-unknown}" \
        --argjson signals_emitted "${signals_emitted:-0}" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            idea_id: $idea_id,
            pre_metrics: $pre_metrics,
            post_metrics: $post_metrics,
            delta: $delta,
            test_pass_rate: $test_pass_rate,
            outcome: $outcome,
            signals_emitted: $signals_emitted
        }' > "$cycle_dir/observe.json"
}

# ---------------------------------------------------------------------------
# Evolution Cycle Runner (spec-41 §8)
# ---------------------------------------------------------------------------

# Orchestrates one complete evolution cycle: REFLECT → IDEATE → EVALUATE →
# IMPLEMENT → OBSERVE. Manages per-cycle budget, takes pre/post metrics
# snapshots, creates the cycle directory, and handles phase failures.
#
# Usage: _evolve_run_cycle <cycle_id>
# Returns: 0 on success, 1 on phase failure, 2 on budget exhaustion,
#          3 on circuit breaker trip
_evolve_run_cycle() {
    local cycle_id="${1:?_evolve_run_cycle requires cycle_id}"
    local padded_cycle
    padded_cycle=$(printf "%03d" "$cycle_id")
    local cycle_dir="$AUTOMATON_DIR/evolution/cycle-${padded_cycle}"
    mkdir -p "$cycle_dir"

    log "EVOLVE" "=== Cycle $cycle_id starting ==="

    # Check circuit breakers before starting the cycle
    if _safety_any_breaker_tripped 2>/dev/null; then
        log "EVOLVE" "Cycle $cycle_id aborted: circuit breaker tripped"
        jq -n --argjson cycle_id "$cycle_id" --arg status "aborted" \
            --arg reason "circuit_breaker_tripped" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{cycle_id: $cycle_id, status: $status, reason: $reason, timestamp: $timestamp}' \
            > "$cycle_dir/cycle-summary.json"
        return 3
    fi

    # Take pre-cycle metrics snapshot
    _metrics_snapshot "$cycle_id" 2>/dev/null || true

    local cycle_status="completed"
    local cycle_reason=""
    local phases_completed=0

    # --- Phase 1: REFLECT ---
    log "EVOLVE" "Cycle $cycle_id: Phase 1/5 REFLECT"
    if ! _evolve_reflect "$padded_cycle" 2>/dev/null; then
        log "EVOLVE" "Cycle $cycle_id: REFLECT phase failed — aborting cycle"
        cycle_status="failed"
        cycle_reason="reflect_phase_failed"
    fi
    phases_completed=$((phases_completed + 1))

    # Check circuit breakers after REFLECT
    if [ "$cycle_status" = "completed" ] && _safety_any_breaker_tripped 2>/dev/null; then
        log "EVOLVE" "Cycle $cycle_id: circuit breaker tripped after REFLECT"
        cycle_status="aborted"
        cycle_reason="circuit_breaker_tripped_after_reflect"
    fi

    # --- Phase 2: IDEATE ---
    if [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 2/5 IDEATE"
        if ! _evolve_ideate "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: IDEATE phase failed — aborting cycle"
            cycle_status="failed"
            cycle_reason="ideate_phase_failed"
        fi
        phases_completed=$((phases_completed + 1))
    fi

    # --- Phase 3: EVALUATE ---
    local eval_result="skipped"
    if [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 3/5 EVALUATE"
        if ! _evolve_evaluate "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: EVALUATE phase failed — aborting cycle"
            cycle_status="failed"
            cycle_reason="evaluate_phase_failed"
        else
            # Check evaluate.json to determine if we have a candidate
            local eval_file="$cycle_dir/evaluate.json"
            if [ -f "$eval_file" ]; then
                eval_result=$(jq -r '.result // "skipped"' "$eval_file" 2>/dev/null || echo "skipped")
            fi
        fi
        phases_completed=$((phases_completed + 1))
    fi

    # --- Phase 4: IMPLEMENT (skip if no approved candidate) ---
    if [ "$cycle_status" = "completed" ] && [ "$eval_result" = "approved" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 4/5 IMPLEMENT"
        if ! _evolve_implement "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: IMPLEMENT phase failed — skipping to OBSERVE"
            # Implementation failure is not fatal — OBSERVE will handle cleanup
        fi
        phases_completed=$((phases_completed + 1))
    elif [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 4/5 IMPLEMENT skipped (no approved candidate, eval_result=$eval_result)"
        phases_completed=$((phases_completed + 1))
    fi

    # --- Phase 5: OBSERVE ---
    if [ "$cycle_status" = "completed" ]; then
        log "EVOLVE" "Cycle $cycle_id: Phase 5/5 OBSERVE"
        if ! _evolve_observe "$padded_cycle" 2>/dev/null; then
            log "EVOLVE" "Cycle $cycle_id: OBSERVE phase failed"
            cycle_status="failed"
            cycle_reason="observe_phase_failed"
        fi
        phases_completed=$((phases_completed + 1))
    fi

    # Persist garden state after cycle
    _garden_rebuild_index 2>/dev/null || true

    # Write cycle summary
    local observe_outcome="none"
    local observe_file="$cycle_dir/observe.json"
    if [ -f "$observe_file" ]; then
        observe_outcome=$(jq -r '.outcome // "none"' "$observe_file" 2>/dev/null || echo "none")
    fi

    jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg status "$cycle_status" \
        --arg reason "$cycle_reason" \
        --argjson phases_completed "$phases_completed" \
        --arg eval_result "$eval_result" \
        --arg observe_outcome "$observe_outcome" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            cycle_id: $cycle_id,
            status: $status,
            reason: $reason,
            phases_completed: $phases_completed,
            eval_result: $eval_result,
            observe_outcome: $observe_outcome,
            timestamp: $timestamp
        }' > "$cycle_dir/cycle-summary.json"

    log "EVOLVE" "=== Cycle $cycle_id $cycle_status (phases=$phases_completed, eval=$eval_result, outcome=$observe_outcome) ==="

    if [ "$cycle_status" = "completed" ]; then
        return 0
    elif [ "$cycle_status" = "aborted" ]; then
        return 3
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Evolution Convergence Detection (spec-41 §8)
# ---------------------------------------------------------------------------

# Checks whether the evolution loop has converged and should stop.
# Convergence occurs when:
#   1. consecutive_no_improvement >= EVOLVE_CONVERGENCE_THRESHOLD
#      (no cycle produced a "harvest" outcome in the last N cycles)
#   2. No bloom candidates for EVOLVE_IDLE_GARDEN_THRESHOLD consecutive cycles
#      (eval_result was "skipped" meaning no bloom candidate existed)
#
# Usage: reason=$(_evolve_check_convergence)
# Returns: 0 if converged (reason on stdout), 1 if not converged
_evolve_check_convergence() {
    local evo_dir="$AUTOMATON_DIR/evolution"
    local convergence_threshold="${EVOLVE_CONVERGENCE_THRESHOLD:-5}"
    local idle_threshold="${EVOLVE_IDLE_GARDEN_THRESHOLD:-3}"

    # Collect cycle summaries sorted by cycle number (ascending)
    local cycle_dirs
    cycle_dirs=$(find "$evo_dir" -maxdepth 1 -type d -name 'cycle-*' 2>/dev/null | sort)
    [ -n "$cycle_dirs" ] || return 1

    # Walk cycle summaries in order to compute consecutive streaks
    local consecutive_no_improvement=0
    local consecutive_no_bloom=0

    while IFS= read -r cdir; do
        local summary="$cdir/cycle-summary.json"
        [ -f "$summary" ] || continue

        local observe_outcome eval_result
        observe_outcome=$(jq -r '.observe_outcome // "none"' "$summary" 2>/dev/null || echo "none")
        eval_result=$(jq -r '.eval_result // "skipped"' "$summary" 2>/dev/null || echo "skipped")

        # Track no-improvement streak (harvest resets; anything else increments)
        if [ "$observe_outcome" = "harvest" ]; then
            consecutive_no_improvement=0
        else
            consecutive_no_improvement=$((consecutive_no_improvement + 1))
        fi

        # Track idle garden streak (eval_result=skipped means no bloom candidate)
        if [ "$eval_result" = "skipped" ]; then
            consecutive_no_bloom=$((consecutive_no_bloom + 1))
        else
            consecutive_no_bloom=0
        fi
    done <<< "$cycle_dirs"

    # Check convergence conditions
    if [ "$consecutive_no_improvement" -ge "$convergence_threshold" ]; then
        log "EVOLVE" "Convergence: $consecutive_no_improvement consecutive cycles without improvement (threshold=$convergence_threshold)"
        echo "no_improvement:${consecutive_no_improvement}"
        return 0
    fi

    if [ "$consecutive_no_bloom" -ge "$idle_threshold" ]; then
        log "EVOLVE" "Convergence: $consecutive_no_bloom consecutive cycles with no bloom candidates (threshold=$idle_threshold)"
        echo "idle_garden:${consecutive_no_bloom}"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Evolution Per-Cycle Budget (spec-41 §9)
# ---------------------------------------------------------------------------

# Calculates the per-cycle budget as:
#   min(EVOLVE_MAX_COST_PER_CYCLE, remaining_budget / estimated_remaining_cycles)
# and enforces the budget_ceiling circuit breaker when there is insufficient
# budget to run even one more cycle.
#
# Usage: cycle_budget=$(_evolve_check_budget <current_cycle> <estimated_remaining_cycles>)
# Returns: 0 if budget is available (per-cycle budget on stdout), 1 if exhausted
_evolve_check_budget() {
    local current_cycle="${1:-1}"
    local estimated_remaining="${2:-1}"
    [ "$estimated_remaining" -lt 1 ] && estimated_remaining=1

    local max_per_cycle="${EVOLVE_MAX_COST_PER_CYCLE:-5.00}"
    local budget_file="$AUTOMATON_DIR/budget.json"

    if [ ! -f "$budget_file" ]; then
        log "EVOLVE" "No budget.json found — allowing cycle with max_cost_per_cycle=$max_per_cycle"
        echo "$max_per_cycle"
        return 0
    fi

    local mode remaining_usd
    mode=$(jq -r '.mode // "api"' "$budget_file" 2>/dev/null || echo "api")

    if [ "$mode" = "allowance" ]; then
        # Allowance mode: estimate remaining budget from token headroom
        # Convert token headroom to approximate USD using $3/1M input tokens
        local effective_allowance tokens_used
        effective_allowance=$(jq -r '.limits.effective_allowance // 0' "$budget_file" 2>/dev/null || echo 0)
        tokens_used=$(jq -r '.tokens_used_this_week // 0' "$budget_file" 2>/dev/null || echo 0)
        remaining_usd=$(awk -v eff="$effective_allowance" -v used="$tokens_used" \
            'BEGIN { tokens_left = eff - used; if (tokens_left < 0) tokens_left = 0; printf "%.2f", tokens_left / 1000000 * 3 }')
    else
        # API mode: remaining = max_cost_usd - estimated_cost_usd
        local max_cost_usd used_usd
        max_cost_usd=$(jq -r '.limits.max_cost_usd // 50' "$budget_file" 2>/dev/null || echo 50)
        used_usd=$(jq -r '.used.estimated_cost_usd // 0' "$budget_file" 2>/dev/null || echo 0)
        remaining_usd=$(awk -v max="$max_cost_usd" -v used="$used_usd" \
            'BEGIN { r = max - used; if (r < 0) r = 0; printf "%.2f", r }')
    fi

    # Calculate per-cycle budget: min(max_per_cycle, remaining / estimated_remaining)
    local cycle_budget
    cycle_budget=$(awk -v max="$max_per_cycle" -v rem="$remaining_usd" -v est="$estimated_remaining" \
        'BEGIN { paced = rem / est; budget = (paced < max) ? paced : max; printf "%.2f", budget }')

    # Minimum viable cycle cost threshold ($0.50)
    local min_viable="0.50"
    local is_exhausted
    is_exhausted=$(awk -v cb="$cycle_budget" -v mv="$min_viable" \
        'BEGIN { print (cb + 0 < mv + 0) ? "yes" : "no" }')

    if [ "$is_exhausted" = "yes" ]; then
        log "EVOLVE" "Budget exhausted: cycle_budget=\$$cycle_budget remaining=\$$remaining_usd (min viable=\$$min_viable)"
        _safety_update_breaker "budget_ceiling"
        return 1
    fi

    log "EVOLVE" "Cycle $current_cycle budget: \$$cycle_budget (remaining=\$$remaining_usd, max_per_cycle=\$$max_per_cycle)"
    echo "$cycle_budget"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution Resume State (spec-41 §11)
# ---------------------------------------------------------------------------

# Reads the last cycle directory in .automaton/evolution/ and determines which
# phase was interrupted by checking for phase summary files. Returns the cycle
# number and the phase to resume from via stdout (format: "cycle_id:phase").
#
# Phase files checked in order: reflect.json, ideate.json, evaluate.json,
# implement.json, observe.json. The resume phase is the first missing file.
# If IMPLEMENT was interrupted, checks for an existing evolution branch.
#
# Usage: resume_info=$(_evolve_resume_state)
#        resume_cycle="${resume_info%%:*}"
#        resume_phase="${resume_info##*:}"
# Returns: 0 on success (resume info on stdout), 1 if no previous state
_evolve_resume_state() {
    local evo_dir="$AUTOMATON_DIR/evolution"

    # Find the last cycle directory
    local last_cycle_dir
    last_cycle_dir=$(find "$evo_dir" -maxdepth 1 -type d -name 'cycle-*' 2>/dev/null | sort | tail -1)

    if [ -z "$last_cycle_dir" ]; then
        log "EVOLVE" "No previous evolution cycle found — starting fresh"
        echo "1:reflect"
        return 1
    fi

    # Extract cycle number from directory name (e.g., cycle-003 -> 3)
    local resume_cycle
    resume_cycle=$(basename "$last_cycle_dir" | sed 's/cycle-0*//')
    [ -z "$resume_cycle" ] && resume_cycle=1

    # Check cycle-summary.json — if it exists and status is "completed", start next cycle
    local summary_file="$last_cycle_dir/cycle-summary.json"
    if [ -f "$summary_file" ]; then
        local status
        status=$(jq -r '.status // "unknown"' "$summary_file" 2>/dev/null || echo "unknown")
        if [ "$status" = "completed" ]; then
            local next_cycle=$((resume_cycle + 1))
            log "EVOLVE" "Last cycle $resume_cycle completed — resuming at cycle $next_cycle"
            echo "${next_cycle}:reflect"
            return 0
        fi
    fi

    # Determine which phase was interrupted by checking for phase files
    local resume_phase="reflect"
    if [ -f "$last_cycle_dir/reflect.json" ]; then
        resume_phase="ideate"
    fi
    if [ -f "$last_cycle_dir/ideate.json" ]; then
        resume_phase="evaluate"
    fi
    if [ -f "$last_cycle_dir/evaluate.json" ]; then
        resume_phase="implement"
    fi
    if [ -f "$last_cycle_dir/implement.json" ]; then
        resume_phase="observe"
    fi
    if [ -f "$last_cycle_dir/observe.json" ]; then
        # All phases completed but cycle-summary missing or failed — re-run observe
        resume_phase="observe"
    fi

    # If IMPLEMENT was interrupted, check for an existing evolution branch
    if [ "$resume_phase" = "implement" ] || [ "$resume_phase" = "observe" ]; then
        local branch_prefix="${EVOLVE_BRANCH_PREFIX:-automaton/evolve-}"
        local evolution_branch
        evolution_branch=$(git branch --list "${branch_prefix}*" 2>/dev/null | head -1 | sed 's/^[* ]*//')
        if [ -n "$evolution_branch" ]; then
            log "EVOLVE" "Found interrupted evolution branch: $evolution_branch"
        fi
    fi

    log "EVOLVE" "Resuming cycle $resume_cycle from phase: $resume_phase"
    echo "${resume_cycle}:${resume_phase}"
    return 0
}

# ---------------------------------------------------------------------------
# Evolution Main Loop (spec-41 §8, §11)
# ---------------------------------------------------------------------------

# Orchestrates the evolution cycle loop: runs _evolve_run_cycle repeatedly
# until convergence, budget exhaustion, cycle limit, pause, or circuit breaker.
# Supports resume via start_cycle and start_phase parameters.
#
# Usage: _evolve_run_loop [start_cycle] [start_phase]
#   start_cycle: cycle number to start from (default: 1)
#   start_phase: phase to resume from within start_cycle (default: reflect)
#                When not "reflect", the cycle runner skips completed phases.
# Returns: 0 on convergence/completion, 1 on error, 2 on budget exhaustion
_evolve_run_loop() {
    local start_cycle="${1:-1}"
    local start_phase="${2:-reflect}"
    local max_cycles="${EVOLVE_MAX_CYCLES:-0}"

    # Override max_cycles from CLI if specified
    if [ "${ARG_CYCLES:-0}" -gt 0 ]; then
        max_cycles="$ARG_CYCLES"
    fi

    log "EVOLVE" "Evolution loop starting (start_cycle=$start_cycle, max_cycles=${max_cycles:-unlimited}, start_phase=$start_phase)"

    # Run safety preflight before starting cycles
    if ! _safety_preflight 2>/dev/null; then
        log "EVOLVE" "Safety preflight failed — cannot start evolution"
        return 1
    fi

    # Ensure constitution exists
    if [ ! -f "$AUTOMATON_DIR/constitution.md" ]; then
        _constitution_create_default 2>/dev/null || true
    fi

    local cycle_id="$start_cycle"
    local exit_reason=""

    while true; do
        # Check cycle limit
        if [ "$max_cycles" -gt 0 ] && [ "$cycle_id" -gt "$((start_cycle + max_cycles - 1))" ]; then
            log "EVOLVE" "Cycle limit reached ($max_cycles cycles)"
            exit_reason="cycle_limit"
            break
        fi

        # Check for pause flag
        if [ -f "$AUTOMATON_DIR/evolution/pause" ]; then
            log "EVOLVE" "Pause flag detected — stopping after current cycle"
            exit_reason="paused"
            break
        fi

        # Check per-cycle budget
        local estimated_remaining=1
        if [ "$max_cycles" -gt 0 ]; then
            estimated_remaining=$((start_cycle + max_cycles - cycle_id))
            [ "$estimated_remaining" -lt 1 ] && estimated_remaining=1
        fi
        if ! _evolve_check_budget "$cycle_id" "$estimated_remaining" >/dev/null 2>&1; then
            log "EVOLVE" "Budget exhausted — stopping evolution"
            exit_reason="budget_exhausted"
            break
        fi

        # Run the cycle
        local cycle_rc=0
        _evolve_run_cycle "$cycle_id" || cycle_rc=$?

        case "$cycle_rc" in
            0)  # Cycle completed successfully
                ;;
            1)  # Phase failure — log but continue to next cycle
                log "EVOLVE" "Cycle $cycle_id had a phase failure — continuing"
                ;;
            2)  # Budget exhaustion mid-cycle
                log "EVOLVE" "Cycle $cycle_id hit budget limit"
                exit_reason="budget_exhausted"
                break
                ;;
            3)  # Circuit breaker tripped
                log "EVOLVE" "Circuit breaker tripped during cycle $cycle_id"
                exit_reason="circuit_breaker"
                break
                ;;
        esac

        # Check convergence after each completed cycle
        local convergence_reason
        if convergence_reason=$(_evolve_check_convergence 2>/dev/null); then
            log "EVOLVE" "Convergence detected: $convergence_reason"
            exit_reason="converged:${convergence_reason}"
            break
        fi

        cycle_id=$((cycle_id + 1))
    done

    # Rebuild garden index and persist state
    _garden_rebuild_index 2>/dev/null || true

    log "EVOLVE" "Evolution loop finished (cycles_run=$((cycle_id - start_cycle + 1)), reason=${exit_reason:-completed})"

    case "$exit_reason" in
        budget_exhausted) return 2 ;;
        circuit_breaker)  return 1 ;;
        *)                return 0 ;;
    esac
}
