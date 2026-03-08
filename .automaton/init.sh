#!/usr/bin/env bash
# .automaton/init.sh — Session Bootstrap (spec-37)
# Runs BEFORE each agent invocation. Outputs JSON manifest to stdout.
# The manifest provides pre-assembled context so agents skip Phase 0 file reads.
#
# Usage: .automaton/init.sh [PROJECT_ROOT] [PHASE] [ITERATION]
# Defaults: PROJECT_ROOT=., PHASE=build, ITERATION=1
set -euo pipefail

PROJECT_ROOT="${1:-.}"
PHASE="${2:-build}"
ITERATION="${3:-1}"
AUTOMATON_DIR="$PROJECT_ROOT/.automaton"

# Dependency check — jq and git are required
check_dependencies() {
    local missing=""
    for cmd in jq git; do
        command -v "$cmd" &>/dev/null || missing="$missing $cmd"
    done
    if [ -n "$missing" ]; then
        echo "{\"error\": \"Missing dependencies:$missing\"}"
        exit 1
    fi
}

# Validate state.json if it exists
validate_state() {
    local state_file="$AUTOMATON_DIR/state.json"
    if [ -f "$state_file" ]; then
        jq empty "$state_file" 2>/dev/null || {
            echo "{\"error\": \"state.json is invalid JSON\"}"
            exit 1
        }
    fi
}

# Assemble the JSON manifest from project files and git state
generate_context() {
    local manifest="{}"

    # --- Project state ---
    manifest=$(echo "$manifest" | jq --arg phase "$PHASE" --argjson iter "$ITERATION" \
        '. + {project_state: {phase: $phase, iteration: $iter}}')

    # Task progress from IMPLEMENTATION_PLAN.md (or .automaton/backlog.md)
    local plan_file="$PROJECT_ROOT/IMPLEMENTATION_PLAN.md"
    if [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    if [ -f "$plan_file" ]; then
        local next_task total_tasks done_tasks
        next_task=$(grep -m1 '^\- \[ \]' "$plan_file" | sed 's/^- \[ \] //' || true)
        total_tasks=$(grep -c '^\- \[' "$plan_file" 2>/dev/null) || total_tasks=0
        done_tasks=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null) || done_tasks=0
        manifest=$(echo "$manifest" | jq \
            --arg next "$next_task" \
            --argjson total "$total_tasks" \
            --argjson done "$done_tasks" \
            '.project_state += {next_task: $next, tasks_total: $total, tasks_done: $done}')
    fi

    # --- Recent changes (last 5 commits) ---
    local recent_commits
    recent_commits=$(git -C "$PROJECT_ROOT" log --oneline -5 2>/dev/null \
        | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')
    manifest=$(echo "$manifest" | jq --argjson commits "$recent_commits" \
        '. + {recent_changes: $commits}')

    # --- Budget ---
    if [ -f "$AUTOMATON_DIR/budget.json" ]; then
        local budget_used budget_limit
        budget_used=$(jq '.used.estimated_cost_usd // 0' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo 0)
        budget_limit=$(jq '.limits.max_cost_usd // 50' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo 50)
        manifest=$(echo "$manifest" | jq \
            --argjson used "$budget_used" \
            --argjson limit "$budget_limit" \
            '. + {budget: {used_usd: $used, limit_usd: $limit, remaining_usd: ($limit - $used)}}')
    fi

    # --- Modified files since last commit ---
    local modified_files
    modified_files=$(git -C "$PROJECT_ROOT" diff --name-only HEAD~1 2>/dev/null \
        | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')
    manifest=$(echo "$manifest" | jq --argjson files "$modified_files" \
        '. + {modified_files: $files}')

    # --- Learnings (high-confidence, active only) ---
    if [ -f "$AUTOMATON_DIR/learnings.json" ]; then
        local learnings
        learnings=$(jq '[.entries[]? | select(.active == true and .confidence == "high") | .summary]' \
            "$AUTOMATON_DIR/learnings.json" 2>/dev/null || echo '[]')
        manifest=$(echo "$manifest" | jq --argjson learn "$learnings" \
            '. + {learnings: $learn}')
    fi

    # --- Test status (from test_results.json) ---
    if [ -f "$AUTOMATON_DIR/test_results.json" ]; then
        local test_data
        test_data=$(jq '{
            passed: ([.[]? | select(.status == "passed")] | length),
            failed: ([.[]? | select(.status == "failed")] | length),
            failing_tests: [.[]? | select(.status == "failed") | .test]
        }' "$AUTOMATON_DIR/test_results.json" 2>/dev/null || echo '{}')
        if [ "$test_data" != "{}" ]; then
            manifest=$(echo "$manifest" | jq --argjson tests "$test_data" \
                '. + {test_status: $tests}')
        fi
    fi

    # --- Garden summary (from garden/_index.json, spec-38 §3) ---
    local garden_index="$AUTOMATON_DIR/garden/_index.json"
    if [ -f "$garden_index" ]; then
        local garden_data
        garden_data=$(jq '{
            total: .total,
            seeds: .by_stage.seed,
            sprouts: .by_stage.sprout,
            blooms: .by_stage.bloom,
            top_bloom: (.bloom_candidates[0] // null)
        }' "$garden_index" 2>/dev/null || echo '{}')
        if [ "$garden_data" != "{}" ]; then
            manifest=$(echo "$manifest" | jq --argjson gs "$garden_data" \
                '. + {garden_summary: $gs}')
        fi
    fi

    # --- Active signals summary (from signals.json, spec-42 §3) ---
    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ -f "$signals_file" ]; then
        local signals_data
        signals_data=$(jq '{
            total: (.signals | length),
            strong: ([.signals[] | select(.strength >= 0.5)] | length),
            strongest: ([.signals | sort_by(-.strength) | .[0] // null] | .[0] | if . then {id: .id, title: .title, strength: .strength} else null end),
            unlinked_count: ([.signals[] | select((.related_ideas | length) == 0)] | length)
        }' "$signals_file" 2>/dev/null || echo '{}')
        if [ "$signals_data" != "{}" ]; then
            manifest=$(echo "$manifest" | jq --argjson as "$signals_data" \
                '. + {active_signals: $as}')
        fi
    fi

    # --- Metrics trend summary (from evolution-metrics.json, spec-43 §3) ---
    local evo_metrics_file="$AUTOMATON_DIR/evolution-metrics.json"
    if [ -f "$evo_metrics_file" ]; then
        local metrics_trend_data
        metrics_trend_data=$(jq '
            # Tracked metrics: [category, metric_name, higher_is_better]
            def tracked: [
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

            .snapshots as $snaps |
            ($snaps | length) as $n |

            # Compute trends only if 2+ snapshots
            (if $n >= 2 then
                .baselines as $baselines |
                [tracked[] | . as [$cat, $metric, $higher_better] |
                    [$snaps[] | .[$cat][$metric] // 0] as $vals |
                    ($vals | length) as $vn |
                    $vals[0] as $first | $vals[$vn - 1] as $last |
                    # Direction
                    (if ($higher_better and $last > $first) or ($higher_better | not and $last < $first) then
                        "improving"
                    elif ($higher_better and $last < $first) or ($higher_better | not and $last > $first) then
                        "degrading"
                    else "stable" end) as $dir |
                    # Count consecutive degrading from end
                    (reduce range($vn - 1; 0; -1) as $i (0;
                        if . >= 0 then
                            ($vals[$i] - $vals[$i - 1]) as $delta |
                            if ($higher_better and $delta < 0) or ($higher_better | not and $delta > 0) then . + 1
                            else -1 end
                        else . end
                    ) | if . < 0 then 0 else . end) as $consec |
                    {metric: $metric, direction: $dir, consecutive_degrading: $consec}
                ]
            else [] end) as $trends |

            # Find last harvest cycle
            ([$snaps[] | select(.innovation.cycles_since_last_harvest == 0) | .cycle_id] | last // null) as $lhc |

            {
                improving: [$trends[] | select(.direction == "improving") | .metric],
                degrading: [$trends[] | select(.direction == "degrading") | .metric],
                alerts: [$trends[] | select(.consecutive_degrading >= 3) | .metric],
                cycles_completed: $n,
                last_harvest_cycle: $lhc
            }
        ' "$evo_metrics_file" 2>/dev/null || echo '{}')
        if [ "$metrics_trend_data" != "{}" ]; then
            manifest=$(echo "$manifest" | jq --argjson mt "$metrics_trend_data" \
                '. + {metrics_trend: $mt}')
        fi
    fi

    # --- Constitution summary (from constitution.md + constitution-history.json, spec-40 §3) ---
    local const_file="$AUTOMATON_DIR/constitution.md"
    if [ -f "$const_file" ]; then
        local const_hist="$AUTOMATON_DIR/constitution-history.json"
        local article_count
        article_count=$(grep -c '^### Article' "$const_file" || echo "0")
        local version=1
        if [ -f "$const_hist" ]; then
            version=$(jq -r '.current_version // 1' "$const_hist" 2>/dev/null || echo "1")
        fi
        local const_data
        const_data=$(jq -n \
            --argjson articles "$article_count" \
            --argjson version "$version" \
            '{
                articles: $articles,
                version: $version,
                key_constraints: [
                    "Safety mechanisms must be preserved (Art. I)",
                    "Human retains override authority (Art. II)",
                    "Changes must target measurable metrics (Art. III)",
                    "Each cycle implements at most 1 idea (Art. VI)"
                ]
            }')
        manifest=$(echo "$manifest" | jq --argjson cs "$const_data" \
            '. + {constitution_summary: $cs}')
    fi

    echo "$manifest" | jq .
}

check_dependencies
validate_state
generate_context
