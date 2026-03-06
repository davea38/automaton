#!/usr/bin/env bash
# lib/metrics.sh — Health metrics: snapshots, baselines, trend analysis, and health dashboard.
# Spec references: spec-43 (health dashboard), spec-44 (metrics display)

_metrics_snapshot() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local cycle_id="${1:?_metrics_snapshot requires cycle_id}"
    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Initialize metrics file if it doesn't exist
    if [ ! -f "$metrics_file" ]; then
        echo '{"version":1,"snapshots":[],"baselines":{}}' > "$metrics_file"
    fi

    # --- Capability metrics ---
    local total_lines=0 total_functions=0 total_specs=0 total_tests=0
    local test_assertions=0 cli_flags=0 agent_definitions=0 skills=0 hooks=0

    if [ -f "${SCRIPT_PATH:-automaton.sh}" ]; then
        total_lines=$(wc -l < "${SCRIPT_PATH:-automaton.sh}" 2>/dev/null || true)
        total_functions=$(grep -c '^[a-z_]*()' "${SCRIPT_PATH:-automaton.sh}" 2>/dev/null || true)
        cli_flags=$(grep -c -- '--[a-z]' "${SCRIPT_PATH:-automaton.sh}" 2>/dev/null || true)
    fi
    if [ -d "${PROJECT_ROOT:-.}/specs" ]; then
        total_specs=$(find "${PROJECT_ROOT:-.}/specs" -name 'spec-*.md' 2>/dev/null | wc -l)
    fi
    if [ -d "${PROJECT_ROOT:-.}/tests" ]; then
        total_tests=$(find "${PROJECT_ROOT:-.}/tests" -name 'test_*.sh' -type f 2>/dev/null | wc -l)
        test_assertions=$(grep -r -c 'assert_' "${PROJECT_ROOT:-.}/tests/" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
    fi
    if [ -d "${PROJECT_ROOT:-.}/.claude/agents" ]; then
        agent_definitions=$(find "${PROJECT_ROOT:-.}/.claude/agents" -name '*.md' 2>/dev/null | wc -l)
    fi
    if [ -d "${PROJECT_ROOT:-.}/.claude/skills" ]; then
        skills=$(find "${PROJECT_ROOT:-.}/.claude/skills" -name '*.md' 2>/dev/null | wc -l)
    fi
    if [ -d "${PROJECT_ROOT:-.}/.claude/hooks" ]; then
        hooks=$(find "${PROJECT_ROOT:-.}/.claude/hooks" -name '*.sh' 2>/dev/null | wc -l)
    fi

    # --- Efficiency metrics ---
    local tokens_per_task=0 tokens_per_iteration=0 cache_hit_ratio="0.00"
    local stall_rate="0.00" prompt_overhead_ratio="0.00"
    local bootstrap_time_ms=0 avg_iteration_duration_s=0

    local budget_file="$AUTOMATON_DIR/budget.json"
    local state_file="$AUTOMATON_DIR/state.json"
    if [ -f "$budget_file" ]; then
        local total_input total_output total_tokens cache_read history_count
        total_input=$(jq '.used.total_input // 0' "$budget_file" 2>/dev/null || echo 0)
        total_output=$(jq '.used.total_output // 0' "$budget_file" 2>/dev/null || echo 0)
        total_tokens=$((total_input + total_output))
        cache_read=$(jq '.used.total_cache_read // 0' "$budget_file" 2>/dev/null || echo 0)
        history_count=$(jq '.history | length' "$budget_file" 2>/dev/null || echo 0)

        local tasks_completed
        tasks_completed=$(jq '[.history[] | select(.phase == "build" and .status == "success")] | length' "$budget_file" 2>/dev/null || echo 0)

        if [ "$tasks_completed" -gt 0 ]; then
            tokens_per_task=$((total_tokens / tasks_completed))
        fi
        if [ "$history_count" -gt 0 ]; then
            tokens_per_iteration=$((total_tokens / history_count))
            avg_iteration_duration_s=$(jq '[.history[].duration_seconds // 0] | add / length | floor' "$budget_file" 2>/dev/null || echo 0)
        fi
        if [ "$total_input" -gt 0 ]; then
            cache_hit_ratio=$(awk -v cr="$cache_read" -v ti="$total_input" 'BEGIN { printf "%.2f", cr/ti }')
        fi
    fi

    if [ -f "$state_file" ]; then
        local stall_count total_build_iters
        stall_count=$(jq '.stall_count // 0' "$state_file" 2>/dev/null || echo 0)
        total_build_iters=$(jq '[.history[] | select(.phase == "build")] | length' "$budget_file" 2>/dev/null || echo 0)
        if [ "$total_build_iters" -gt 0 ]; then
            stall_rate=$(awk -v s="$stall_count" -v t="$total_build_iters" 'BEGIN { printf "%.2f", s/t }')
        fi
    fi

    # --- Quality metrics ---
    local test_pass_rate="0.00" first_pass_success_rate="0.00"
    local rollback_count=0 syntax_errors_caught=0
    local review_rework_rate="0.00" constitution_violations=0

    local results_file="$AUTOMATON_DIR/test_results.json"
    if [ -f "$results_file" ]; then
        local passed failed
        passed=$(jq '.passed // 0' "$results_file" 2>/dev/null || echo 0)
        failed=$(jq '.failed // 0' "$results_file" 2>/dev/null || echo 0)
        local total_tests_run=$((passed + failed))
        if [ "$total_tests_run" -gt 0 ]; then
            test_pass_rate=$(awk -v p="$passed" -v t="$total_tests_run" 'BEGIN { printf "%.2f", p/t }')
        fi
    fi

    if [ -f "$state_file" ]; then
        local replan_count tasks_done
        replan_count=$(jq '.replan_count // 0' "$state_file" 2>/dev/null || echo 0)
        tasks_done=$(jq '[.history[] | select(.phase == "build" and .status == "success")] | length' "$budget_file" 2>/dev/null || echo 0)
        if [ "$tasks_done" -gt 0 ]; then
            local successful=$((tasks_done - replan_count))
            [ "$successful" -lt 0 ] && successful=0
            first_pass_success_rate=$(awk -v s="$successful" -v t="$tasks_done" 'BEGIN { printf "%.2f", s/t }')
            review_rework_rate=$(awk -v r="$replan_count" -v t="$tasks_done" 'BEGIN { printf "%.2f", r/t }')
        fi
    fi

    local mods_file="$AUTOMATON_DIR/self_modifications.json"
    if [ -f "$mods_file" ]; then
        rollback_count=$(jq '[.[] | select(.type == "rollback")] | length' "$mods_file" 2>/dev/null || echo 0)
        syntax_errors_caught=$(jq '[.[] | select(.type == "syntax_error")] | length' "$mods_file" 2>/dev/null || echo 0)
    fi

    # --- Innovation metrics ---
    local garden_seeds=0 garden_sprouts=0 garden_blooms=0
    local garden_harvested=0 garden_wilted=0
    local active_signals=0 quorum_votes_cast=0
    local ideas_implemented_total=0 cycles_since_last_harvest=0

    local garden_index="$AUTOMATON_DIR/garden/_index.json"
    if [ -f "$garden_index" ]; then
        garden_seeds=$(jq '.by_stage.seed // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_sprouts=$(jq '.by_stage.sprout // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_blooms=$(jq '.by_stage.bloom // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_harvested=$(jq '.by_stage.harvest // 0' "$garden_index" 2>/dev/null || echo 0)
        garden_wilted=$(jq '.by_stage.wilt // 0' "$garden_index" 2>/dev/null || echo 0)
    fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ -f "$signals_file" ]; then
        active_signals=$(jq '[.signals[] | select(.strength > 0.05)] | length' "$signals_file" 2>/dev/null || echo 0)
    fi

    local votes_dir="$AUTOMATON_DIR/votes"
    if [ -d "$votes_dir" ]; then
        quorum_votes_cast=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | wc -l)
    fi

    ideas_implemented_total=$garden_harvested

    # cycles_since_last_harvest: scan existing snapshots for last harvest
    if [ -f "$metrics_file" ]; then
        local last_harvest_cycle
        last_harvest_cycle=$(jq '[.snapshots[] | select(.innovation.garden_harvested > 0)] | last | .cycle_id // 0' "$metrics_file" 2>/dev/null || echo 0)
        if [ "$last_harvest_cycle" -gt 0 ]; then
            cycles_since_last_harvest=$((cycle_id - last_harvest_cycle))
        else
            cycles_since_last_harvest=$cycle_id
        fi
    fi

    # --- Health indicators ---
    local budget_utilization="0.00" weekly_allowance_remaining="0.00"
    local convergence_risk="low" circuit_breaker_trips=0
    local consecutive_no_improvement=0 error_rate="0.00"
    local self_modification_count=0

    if [ -f "$budget_file" ]; then
        local cost_used cost_limit
        cost_used=$(jq '.used.estimated_cost_usd // 0' "$budget_file" 2>/dev/null || echo 0)
        cost_limit=$(jq '.limits.max_cost_usd // 50' "$budget_file" 2>/dev/null || echo 50)
        if [ "$(echo "$cost_limit" | awk '{print ($1 > 0)}')" = "1" ]; then
            budget_utilization=$(awk -v u="$cost_used" -v l="$cost_limit" 'BEGIN { printf "%.2f", u/l }')
        fi

        if [ "$(jq -r '.mode // "api"' "$budget_file" 2>/dev/null)" = "allowance" ]; then
            local tokens_remaining effective_allowance
            tokens_remaining=$(jq '.tokens_remaining // 0' "$budget_file" 2>/dev/null || echo 0)
            effective_allowance=$(jq '.limits.effective_allowance // 1' "$budget_file" 2>/dev/null || echo 1)
            weekly_allowance_remaining=$(awk -v r="$tokens_remaining" -v e="$effective_allowance" 'BEGIN { printf "%.2f", r/e }')
        fi
    fi

    if [ -f "$mods_file" ]; then
        self_modification_count=$(jq 'length' "$mods_file" 2>/dev/null || echo 0)
    fi

    local breakers_file="$AUTOMATON_DIR/evolution/circuit-breakers.json"
    if [ -f "$breakers_file" ]; then
        circuit_breaker_trips=$(jq '[.[] | select(.tripped == true)] | length' "$breakers_file" 2>/dev/null || echo 0)
    fi

    # consecutive_no_improvement from previous snapshots
    if [ -f "$metrics_file" ]; then
        consecutive_no_improvement=$(jq '.snapshots | last | .health.consecutive_no_improvement // 0' "$metrics_file" 2>/dev/null || echo 0)
    fi

    # convergence_risk based on consecutive_no_improvement
    if [ "$consecutive_no_improvement" -ge 5 ]; then
        convergence_risk="high"
    elif [ "$consecutive_no_improvement" -ge 3 ]; then
        convergence_risk="medium"
    fi

    # --- Build and append the snapshot ---
    local snapshot
    snapshot=$(jq -n \
        --argjson cycle_id "$cycle_id" \
        --arg timestamp "$now" \
        --argjson total_lines "$total_lines" \
        --argjson total_functions "$total_functions" \
        --argjson total_specs "$total_specs" \
        --argjson total_tests "$total_tests" \
        --argjson test_assertions "$test_assertions" \
        --argjson cli_flags "$cli_flags" \
        --argjson agent_definitions "$agent_definitions" \
        --argjson skills "$skills" \
        --argjson hooks "$hooks" \
        --argjson tokens_per_task "$tokens_per_task" \
        --argjson tokens_per_iteration "$tokens_per_iteration" \
        --arg cache_hit_ratio "$cache_hit_ratio" \
        --arg stall_rate "$stall_rate" \
        --arg prompt_overhead_ratio "$prompt_overhead_ratio" \
        --argjson bootstrap_time_ms "$bootstrap_time_ms" \
        --argjson avg_iteration_duration_s "$avg_iteration_duration_s" \
        --arg test_pass_rate "$test_pass_rate" \
        --arg first_pass_success_rate "$first_pass_success_rate" \
        --argjson rollback_count "$rollback_count" \
        --argjson syntax_errors_caught "$syntax_errors_caught" \
        --arg review_rework_rate "$review_rework_rate" \
        --argjson constitution_violations "$constitution_violations" \
        --argjson garden_seeds "$garden_seeds" \
        --argjson garden_sprouts "$garden_sprouts" \
        --argjson garden_blooms "$garden_blooms" \
        --argjson garden_harvested "$garden_harvested" \
        --argjson garden_wilted "$garden_wilted" \
        --argjson active_signals "$active_signals" \
        --argjson quorum_votes_cast "$quorum_votes_cast" \
        --argjson ideas_implemented_total "$ideas_implemented_total" \
        --argjson cycles_since_last_harvest "$cycles_since_last_harvest" \
        --arg budget_utilization "$budget_utilization" \
        --arg weekly_allowance_remaining "$weekly_allowance_remaining" \
        --arg convergence_risk "$convergence_risk" \
        --argjson circuit_breaker_trips "$circuit_breaker_trips" \
        --argjson consecutive_no_improvement "$consecutive_no_improvement" \
        --arg error_rate "$error_rate" \
        --argjson self_modification_count "$self_modification_count" \
        '{
            cycle_id: $cycle_id,
            timestamp: $timestamp,
            capability: {
                total_lines: $total_lines,
                total_functions: $total_functions,
                total_specs: $total_specs,
                total_tests: $total_tests,
                test_assertions: $test_assertions,
                cli_flags: $cli_flags,
                agent_definitions: $agent_definitions,
                skills: $skills,
                hooks: $hooks
            },
            efficiency: {
                tokens_per_task: $tokens_per_task,
                tokens_per_iteration: $tokens_per_iteration,
                cache_hit_ratio: ($cache_hit_ratio | tonumber),
                stall_rate: ($stall_rate | tonumber),
                prompt_overhead_ratio: ($prompt_overhead_ratio | tonumber),
                bootstrap_time_ms: $bootstrap_time_ms,
                avg_iteration_duration_s: $avg_iteration_duration_s
            },
            quality: {
                test_pass_rate: ($test_pass_rate | tonumber),
                first_pass_success_rate: ($first_pass_success_rate | tonumber),
                rollback_count: $rollback_count,
                syntax_errors_caught: $syntax_errors_caught,
                review_rework_rate: ($review_rework_rate | tonumber),
                constitution_violations: $constitution_violations
            },
            innovation: {
                garden_seeds: $garden_seeds,
                garden_sprouts: $garden_sprouts,
                garden_blooms: $garden_blooms,
                garden_harvested: $garden_harvested,
                garden_wilted: $garden_wilted,
                active_signals: $active_signals,
                quorum_votes_cast: $quorum_votes_cast,
                ideas_implemented_total: $ideas_implemented_total,
                cycles_since_last_harvest: $cycles_since_last_harvest
            },
            health: {
                budget_utilization: ($budget_utilization | tonumber),
                weekly_allowance_remaining: ($weekly_allowance_remaining | tonumber),
                convergence_risk: $convergence_risk,
                circuit_breaker_trips: $circuit_breaker_trips,
                consecutive_no_improvement: $consecutive_no_improvement,
                error_rate: ($error_rate | tonumber),
                self_modification_count: $self_modification_count
            }
        }')

    # Append snapshot to metrics file atomically
    local tmp="${metrics_file}.tmp"
    jq --argjson snap "$snapshot" '.snapshots += [$snap]' "$metrics_file" > "$tmp" && mv "$tmp" "$metrics_file"

    # Enforce snapshot retention: prune oldest snapshots when count exceeds limit
    local retention="${METRICS_SNAPSHOT_RETENTION:-100}"
    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -gt "$retention" ]; then
        local excess=$((snap_count - retention))
        jq --argjson n "$excess" '.snapshots = .snapshots[$n:]' "$metrics_file" > "$tmp" && mv "$tmp" "$metrics_file"
        log "METRICS" "Pruned $excess oldest snapshot(s), retaining $retention"
    fi

    log "METRICS" "Snapshot recorded for cycle $cycle_id"
    echo "$metrics_file"
}

# Records the first snapshot's values as baselines in the metrics file.
# Baselines are set once and never updated automatically — they establish the
# reference point for all improvement/regression comparisons. If baselines
# already exist (non-empty object), this function is a no-op.
#
# Usage: _metrics_set_baselines
_metrics_set_baselines() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then return 0; fi

    # Check if baselines already exist (non-empty object)
    local existing
    existing=$(jq '.baselines // {}' "$metrics_file" 2>/dev/null)
    if [ -n "$existing" ] && [ "$existing" != "{}" ] && [ "$existing" != "null" ]; then
        return 0
    fi

    # Check if there are any snapshots to use
    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -eq 0 ]; then return 0; fi

    # Extract baselines from first snapshot
    local tmp="${metrics_file}.tmp"
    jq '.baselines = {
        capability: {
            total_lines: .snapshots[0].capability.total_lines,
            total_functions: .snapshots[0].capability.total_functions,
            total_specs: .snapshots[0].capability.total_specs,
            total_tests: .snapshots[0].capability.total_tests
        },
        efficiency: {
            tokens_per_task: .snapshots[0].efficiency.tokens_per_task,
            stall_rate: .snapshots[0].efficiency.stall_rate
        },
        quality: {
            test_pass_rate: .snapshots[0].quality.test_pass_rate,
            rollback_count: .snapshots[0].quality.rollback_count
        }
    }' "$metrics_file" > "$tmp" && mv "$tmp" "$metrics_file"

    log "METRICS" "Baselines recorded from first snapshot"
}

# Returns the most recent snapshot from evolution-metrics.json as JSON on stdout.
# Returns nothing if no snapshots exist or the metrics file is missing.
#
# Usage: latest=$(_metrics_get_latest)
_metrics_get_latest() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then return 0; fi

    local result
    result=$(jq '.snapshots | last // empty' "$metrics_file" 2>/dev/null)
    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
    fi
}

# Analyzes trends across the last N snapshots. For each tracked metric computes
# direction (improving/degrading/stable), rate of change per cycle, and alert
# status when degrading for degradation_alert_threshold consecutive cycles.
# Returns a JSON array of trend observations.
#
# Usage: trends=$(_metrics_analyze_trends [window])
_metrics_analyze_trends() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then echo "[]"; return 0; fi

    local window="${1:-5}"
    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then echo "[]"; return 0; fi

    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -lt 2 ]; then echo "[]"; return 0; fi

    # Use jq to compute all trends in a single pass
    jq --argjson window "$window" '
        # Metrics config: [category, metric_name, higher_is_better]
        def tracked_metrics: [
            ["capability", "total_lines", true],
            ["capability", "total_functions", true],
            ["capability", "total_specs", true],
            ["capability", "total_tests", true],
            ["efficiency", "tokens_per_task", false],
            ["efficiency", "cache_hit_ratio", true],
            ["efficiency", "stall_rate", false],
            ["quality", "test_pass_rate", true],
            ["quality", "first_pass_success_rate", true],
            ["quality", "rollback_count", false],
            ["quality", "review_rework_rate", false],
            ["health", "error_rate", false]
        ];

        .snapshots[-$window:] as $snaps |
        .baselines as $baselines |

        if ($snaps | length) < 2 then []
        else
            [tracked_metrics[] | . as [$cat, $metric, $higher_better] |
                # Extract values for this metric from the window
                [$snaps[] | .[$cat][$metric] // 0] as $values |
                ($values | length) as $n |

                # First and last values in window
                $values[0] as $first |
                $values[$n - 1] as $last |

                # Rate of change: percentage change per cycle
                (if $first == 0 then
                    (if $last == 0 then 0 else 100 end)
                else
                    (($last - $first) / $first * 100 / ($n - 1))
                end) as $rate |

                # Check if stable relative to baseline (within 5%)
                ($baselines[$cat][$metric] // null) as $baseline |
                (if $baseline != null and $baseline != 0 then
                    ((($last - $baseline) / $baseline) | fabs) < 0.05
                else
                    false
                end) as $within_baseline |

                # Count consecutive degrading cycles from the end
                (reduce range($n - 1; 0; -1) as $i (
                    0;
                    if . >= 0 then
                        ($values[$i] - $values[$i - 1]) as $delta |
                        if ($higher_better and $delta < 0) or ($higher_better | not and $delta > 0) then
                            . + 1
                        else
                            -1  # stop counting
                        end
                    else .
                    end
                ) | if . < 0 then 0 else . end) as $consec_degrading |

                # Determine direction
                (if $within_baseline and ($rate | fabs) < 5 then
                    "stable"
                elif ($higher_better and $last > $first) or ($higher_better | not and $last < $first) then
                    "improving"
                elif ($higher_better and $last < $first) or ($higher_better | not and $last > $first) then
                    "degrading"
                else
                    "stable"
                end) as $direction |

                # Alert if degrading for 3+ consecutive cycles
                ($direction == "degrading" and $consec_degrading >= 3) as $alert |

                {
                    category: $cat,
                    metric: $metric,
                    direction: $direction,
                    rate: ($rate * 100 | round / 100),
                    alert: $alert,
                    current: $last,
                    baseline: ($baseline // null),
                    consecutive_degrading: $consec_degrading
                }
            ]
        end
    ' "$metrics_file"
}

# Compares two snapshots (pre-cycle and post-cycle) and computes per-metric
# deltas with direction indicators. Used by the OBSERVE phase to determine
# whether a cycle's implementation improved, degraded, or had no effect.
#
# Usage: result=$(_metrics_compare "$pre_snapshot" "$post_snapshot")
# Both arguments are JSON snapshot objects (not cycle IDs).
# Returns: JSON object with "deltas" array and "summary" counts.
_metrics_compare() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then
        echo '{"deltas":[],"summary":{"improved":0,"degraded":0,"unchanged":0}}'
        return 0
    fi

    local pre_snapshot="${1:?_metrics_compare requires pre_snapshot}"
    local post_snapshot="${2:?_metrics_compare requires post_snapshot}"

    jq -n --argjson pre "$pre_snapshot" --argjson post "$post_snapshot" '
        # Metrics config: [category, metric_name, higher_is_better]
        def tracked_metrics: [
            ["capability", "total_lines", true],
            ["capability", "total_functions", true],
            ["capability", "total_specs", true],
            ["capability", "total_tests", true],
            ["capability", "test_assertions", true],
            ["capability", "cli_flags", true],
            ["efficiency", "tokens_per_task", false],
            ["efficiency", "tokens_per_iteration", false],
            ["efficiency", "cache_hit_ratio", true],
            ["efficiency", "stall_rate", false],
            ["quality", "test_pass_rate", true],
            ["quality", "first_pass_success_rate", true],
            ["quality", "rollback_count", false],
            ["quality", "review_rework_rate", false],
            ["innovation", "garden_seeds", true],
            ["innovation", "garden_sprouts", true],
            ["innovation", "garden_blooms", true],
            ["innovation", "garden_harvested", true],
            ["innovation", "active_signals", true],
            ["health", "budget_utilization", false],
            ["health", "error_rate", false]
        ];

        [tracked_metrics[] | . as [$cat, $metric, $higher_better] |
            ($pre[$cat][$metric] // 0) as $before |
            ($post[$cat][$metric] // 0) as $after |
            ($after - $before) as $delta |

            # Percentage change (avoid division by zero)
            (if $before == 0 then
                (if $after == 0 then 0 else 100 end)
            else
                (($delta / $before) * 100 | round)
            end) as $pct |

            # Direction: did this metric improve, degrade, or stay unchanged?
            (if $delta == 0 then
                "unchanged"
            elif ($higher_better and $delta > 0) or ($higher_better | not and $delta < 0) then
                "improved"
            else
                "degraded"
            end) as $direction |

            {
                category: $cat,
                metric: $metric,
                before: $before,
                after: $after,
                delta: $delta,
                percent_change: $pct,
                direction: $direction
            }
        ] as $deltas |

        {
            deltas: $deltas,
            summary: {
                improved: ([$deltas[] | select(.direction == "improved")] | length),
                degraded: ([$deltas[] | select(.direction == "degraded")] | length),
                unchanged: ([$deltas[] | select(.direction == "unchanged")] | length)
            }
        }
    '
}

# Renders the terminal health dashboard showing all 5 metric categories with
# current/baseline/trend columns, bar charts for utilization metrics, and
# trend indicators. This is the primary human interface for understanding the
# system's quantitative state at a glance.
#
# Usage: _metrics_display_health
_metrics_display_health() {
    if [ "${METRICS_ENABLED:-true}" != "true" ]; then return 0; fi

    local metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ ! -f "$metrics_file" ]; then
        echo "No metrics data available. Run an evolution cycle first."
        return 0
    fi

    local snap_count
    snap_count=$(jq '.snapshots | length' "$metrics_file" 2>/dev/null || echo 0)
    if [ "$snap_count" -eq 0 ]; then
        echo "No metrics snapshots found."
        return 0
    fi

    # Extract latest snapshot and baselines in a single jq call
    local data
    data=$(jq '{
        snap: .snapshots[-1],
        baselines: .baselines,
        snap_count: (.snapshots | length),
        prev: (if (.snapshots | length) >= 2 then .snapshots[-2] else null end)
    }' "$metrics_file" 2>/dev/null)

    local W=60  # dashboard width

    # Helper: format a number with commas
    _fmt_num() {
        local n="$1"
        if [ -z "$n" ] || [ "$n" = "null" ] || [ "$n" = "" ]; then echo ""; return; fi
        echo "$n" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta'
    }

    # Helper: compute trend string between prev and current values
    # Args: current baseline prev higher_is_better
    _trend_str() {
        local cur="$1" base="$2" prev="$3" hib="$4"
        if [ -z "$base" ] || [ "$base" = "null" ]; then
            echo "—"
            return
        fi
        # Percentage change from baseline
        local pct
        pct=$(awk -v c="$cur" -v b="$base" 'BEGIN {
            if (b == 0) { if (c == 0) print "0.0"; else print "100.0" }
            else printf "%.1f", ((c - b) / b) * 100
        }')
        local sign="+"
        if echo "$pct" | grep -q '^-'; then
            sign=""
        fi
        # Determine arrow and improvement marker
        local arrow="—" mark=""
        if [ "$prev" != "null" ] && [ -n "$prev" ]; then
            local cmp
            cmp=$(awk -v c="$cur" -v p="$prev" 'BEGIN { if (c > p) print "up"; else if (c < p) print "down"; else print "same" }')
            if [ "$cmp" = "up" ]; then
                arrow="▲"
                [ "$hib" = "true" ] && mark=" ✓"
                [ "$hib" = "false" ] && mark=""
            elif [ "$cmp" = "down" ]; then
                arrow="▼"
                [ "$hib" = "false" ] && mark=" ✓"
                [ "$hib" = "true" ] && mark=""
            fi
        fi
        if [ "$pct" = "0.0" ]; then
            echo "— stable"
        else
            echo "${arrow} ${sign}${pct}%${mark}"
        fi
    }

    # Helper: render a bar chart (width 10 chars)
    _bar() {
        local pct="$1"
        local filled
        filled=$(awk -v p="$pct" 'BEGIN { printf "%d", p / 10 }')
        local empty=$((10 - filled))
        local bar=""
        local i
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = 0; i < empty; i++)); do bar+="░"; done
        echo "$bar"
    }

    # Extract values from data using jq
    _val() { echo "$data" | jq -r "$1" 2>/dev/null; }

    # Print header
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                   AUTOMATON HEALTH                       ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║                                                          ║"

    # --- CAPABILITY ---
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "CAPABILITY" "Current" "Baseline" "Trend"

    local cap_lines cap_funcs cap_specs cap_tests
    cap_lines=$(_val '.snap.capability.total_lines')
    cap_funcs=$(_val '.snap.capability.total_functions')
    cap_specs=$(_val '.snap.capability.total_specs')
    cap_tests=$(_val '.snap.capability.total_tests')

    local bl_lines bl_funcs bl_specs bl_tests
    bl_lines=$(_val '.baselines.capability.total_lines // ""')
    bl_funcs=$(_val '.baselines.capability.total_functions // ""')
    bl_specs=$(_val '.baselines.capability.total_specs // ""')
    bl_tests=$(_val '.baselines.capability.total_tests // ""')

    local prev_lines prev_funcs prev_specs prev_tests
    prev_lines=$(_val '.prev.capability.total_lines // null')
    prev_funcs=$(_val '.prev.capability.total_functions // null')
    prev_specs=$(_val '.prev.capability.total_specs // null')
    prev_tests=$(_val '.prev.capability.total_tests // null')

    local tr
    tr=$(_trend_str "$cap_lines" "$bl_lines" "$prev_lines" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Lines of code" "$(_fmt_num "$cap_lines")" "$(_fmt_num "$bl_lines")" "$tr"
    tr=$(_trend_str "$cap_funcs" "$bl_funcs" "$prev_funcs" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Functions" "$(_fmt_num "$cap_funcs")" "$(_fmt_num "$bl_funcs")" "$tr"
    tr=$(_trend_str "$cap_specs" "$bl_specs" "$prev_specs" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Specs" "$(_fmt_num "$cap_specs")" "$(_fmt_num "$bl_specs")" "$tr"
    tr=$(_trend_str "$cap_tests" "$bl_tests" "$prev_tests" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Tests" "$(_fmt_num "$cap_tests")" "$(_fmt_num "$bl_tests")" "$tr"

    echo "║                                                          ║"

    # --- EFFICIENCY ---
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "EFFICIENCY" "Current" "Baseline" "Trend"

    local eff_tpt eff_stall eff_cache
    eff_tpt=$(_val '.snap.efficiency.tokens_per_task')
    eff_stall=$(_val '.snap.efficiency.stall_rate')
    eff_cache=$(_val '.snap.efficiency.cache_hit_ratio')

    local bl_tpt bl_stall
    bl_tpt=$(_val '.baselines.efficiency.tokens_per_task // ""')
    bl_stall=$(_val '.baselines.efficiency.stall_rate // ""')

    local prev_tpt prev_stall prev_cache
    prev_tpt=$(_val '.prev.efficiency.tokens_per_task // null')
    prev_stall=$(_val '.prev.efficiency.stall_rate // null')
    prev_cache=$(_val '.prev.efficiency.cache_hit_ratio // null')

    tr=$(_trend_str "$eff_tpt" "$bl_tpt" "$prev_tpt" "false")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Tokens/task" "$(_fmt_num "$eff_tpt")" "$(_fmt_num "$bl_tpt")" "$tr"
    tr=$(_trend_str "$eff_stall" "$bl_stall" "$prev_stall" "false")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Stall rate" "$eff_stall" "$bl_stall" "$tr"
    tr=$(_trend_str "$eff_cache" "" "$prev_cache" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Cache hit ratio" "$eff_cache" "" "$tr"

    echo "║                                                          ║"

    # --- QUALITY ---
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "QUALITY" "Current" "Baseline" "Trend"

    local qual_tpr qual_rollback
    qual_tpr=$(_val '.snap.quality.test_pass_rate')
    qual_rollback=$(_val '.snap.quality.rollback_count')

    local bl_tpr bl_rollback
    bl_tpr=$(_val '.baselines.quality.test_pass_rate // ""')
    bl_rollback=$(_val '.baselines.quality.rollback_count // ""')

    local prev_tpr prev_rollback
    prev_tpr=$(_val '.prev.quality.test_pass_rate // null')
    prev_rollback=$(_val '.prev.quality.rollback_count // null')

    tr=$(_trend_str "$qual_tpr" "$bl_tpr" "$prev_tpr" "true")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Test pass rate" "$qual_tpr" "$bl_tpr" "$tr"
    tr=$(_trend_str "$qual_rollback" "$bl_rollback" "$prev_rollback" "false")
    printf "║  %-16s %-10s %-11s %-15s  ║\n" "Rollbacks" "$qual_rollback" "$bl_rollback" "$tr"

    echo "║                                                          ║"

    # --- INNOVATION ---
    printf "║  %-16s %-39s  ║\n" "INNOVATION" "Current"

    local inn_seeds inn_sprouts inn_blooms inn_harvested inn_signals inn_strong
    inn_seeds=$(_val '.snap.innovation.garden_seeds')
    inn_sprouts=$(_val '.snap.innovation.garden_sprouts')
    inn_blooms=$(_val '.snap.innovation.garden_blooms')
    inn_harvested=$(_val '.snap.innovation.ideas_implemented_total')
    inn_signals=$(_val '.snap.innovation.active_signals')

    printf "║  Garden: %d seeds, %d sprouts, %d blooms%-17s  ║\n" \
        "$inn_seeds" "$inn_sprouts" "$inn_blooms" ""
    printf "║  Signals: %d active%-36s  ║\n" "$inn_signals" ""
    printf "║  Harvested: %d ideas total%-30s  ║\n" "$inn_harvested" ""

    echo "║                                                          ║"

    # --- HEALTH ---
    printf "║  %-16s %-39s  ║\n" "HEALTH" "Status"

    local h_budget h_weekly h_risk h_breakers h_cycles
    h_budget=$(_val '.snap.health.budget_utilization')
    h_weekly=$(_val '.snap.health.weekly_allowance_remaining')
    h_risk=$(_val '.snap.health.convergence_risk')
    h_breakers=$(_val '.snap.health.circuit_breaker_trips')
    h_cycles=$(_val '.snap.cycle_id')

    local budget_pct
    budget_pct=$(awk -v b="$h_budget" 'BEGIN { printf "%d", b * 100 }')
    local weekly_pct
    weekly_pct=$(awk -v w="$h_weekly" 'BEGIN { printf "%d", w * 100 }')

    printf "║  Budget utilization  %3d%% %s%-20s  ║\n" "$budget_pct" "$(_bar "$budget_pct")" ""
    printf "║  Weekly allowance    %3d%% remaining%-21s  ║\n" "$weekly_pct" ""
    printf "║  Convergence risk    %-35s  ║\n" "$(echo "$h_risk" | tr '[:lower:]' '[:upper:]')"
    printf "║  Circuit breakers    %d trips%-29s  ║\n" "$h_breakers" ""
    printf "║  Evolution cycles    %d completed%-25s  ║\n" "$h_cycles" ""

    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"

    local last_ts
    last_ts=$(_val '.snap.timestamp')
    echo "  Last snapshot: ${last_ts} (cycle ${h_cycles})"
}
