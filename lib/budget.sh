#!/usr/bin/env bash
# lib/budget.sh — Budget initialization, tracking, allowance management, and enforcement.
# Spec references: spec-07 (budget enforcement), spec-23 (weekly allowance),
#                  spec-35 (daily pacing, cross-project budgets)

initialize_budget() {
    local tmp="$AUTOMATON_DIR/budget.json.tmp"

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Allowance mode (spec-23): weekly token tracking for Max subscription
        local week_start week_end effective_allowance
        week_start=$(_allowance_week_start)
        week_end=$(_allowance_week_end "$week_start")
        effective_allowance=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')

        # Calculate initial daily budget for pacing (spec-35)
        local today today_epoch end_epoch days_left initial_daily_budget
        today=$(date +%Y-%m-%d)
        today_epoch=$(date -d "$today" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$today" +%s 2>/dev/null || echo 0)
        end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s 2>/dev/null || echo 0)
        if [ "$today_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
            days_left=$(( (end_epoch - today_epoch) / 86400 + 1 ))
        else
            days_left=1
        fi
        [ "$days_left" -lt 1 ] && days_left=1
        initial_daily_budget=$(awk -v eff="$effective_allowance" -v days="$days_left" \
            'BEGIN { printf "%d", eff / days }')

        jq -n \
            --arg mode "allowance" \
            --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
            --argjson effective_allowance "$effective_allowance" \
            --arg week_start "$week_start" \
            --arg week_end "$week_end" \
            --argjson reserve "$BUDGET_RESERVE_PERCENTAGE" \
            --argjson per_iteration "$BUDGET_PER_ITERATION" \
            --argjson daily_budget "$initial_daily_budget" \
            '{
                mode: $mode,
                limits: {
                    weekly_allowance_tokens: $weekly_allowance,
                    effective_allowance: $effective_allowance,
                    reserve_percentage: $reserve,
                    per_iteration: $per_iteration,
                    daily_budget: $daily_budget,
                    phase_proportions: {
                        research: 0.05,
                        plan: 0.10,
                        build: 0.70,
                        review: 0.15
                    }
                },
                week_start: $week_start,
                week_end: $week_end,
                tokens_used_this_week: 0,
                tokens_remaining: ($effective_allowance | tonumber),
                used: {
                    total_input: 0,
                    total_output: 0,
                    total_cache_create: 0,
                    total_cache_read: 0,
                    by_phase: {
                        research: { input: 0, output: 0 },
                        plan: { input: 0, output: 0 },
                        build: { input: 0, output: 0 },
                        review: { input: 0, output: 0 }
                    },
                    estimated_cost_usd: 0.00
                },
                history: [],
                allowance_history: []
            }' > "$tmp"
    else
        # API mode (default): original USD-based budget
        jq -n \
            --arg mode "api" \
            --argjson max_tokens "$BUDGET_MAX_TOKENS" \
            --argjson max_usd "$BUDGET_MAX_USD" \
            --argjson phase_research "$BUDGET_PHASE_RESEARCH" \
            --argjson phase_plan "$BUDGET_PHASE_PLAN" \
            --argjson phase_build "$BUDGET_PHASE_BUILD" \
            --argjson phase_review "$BUDGET_PHASE_REVIEW" \
            --argjson per_iteration "$BUDGET_PER_ITERATION" \
            '{
                mode: $mode,
                limits: {
                    max_total_tokens: $max_tokens,
                    max_cost_usd: $max_usd,
                    per_phase: {
                        research: $phase_research,
                        plan: $phase_plan,
                        build: $phase_build,
                        review: $phase_review
                    },
                    per_iteration: $per_iteration
                },
                used: {
                    total_input: 0,
                    total_output: 0,
                    total_cache_create: 0,
                    total_cache_read: 0,
                    by_phase: {
                        research: { input: 0, output: 0 },
                        plan: { input: 0, output: 0 },
                        build: { input: 0, output: 0 },
                        review: { input: 0, output: 0 }
                    },
                    estimated_cost_usd: 0.00
                },
                history: []
            }' > "$tmp"
    fi
    mv "$tmp" "$AUTOMATON_DIR/budget.json"

    # Initialize cross-project allowance tracking (spec-35 §5)
    _init_cross_project_allowance
}

# Returns the start of the current allowance week (ISO date) based on reset day.
_allowance_week_start() {
    local reset_day="$BUDGET_ALLOWANCE_RESET_DAY"
    local today today_dow target_dow days_back

    today=$(date +%Y-%m-%d)
    today_dow=$(date +%u)  # 1=Monday, 7=Sunday

    case "$reset_day" in
        monday)    target_dow=1 ;;
        tuesday)   target_dow=2 ;;
        wednesday) target_dow=3 ;;
        thursday)  target_dow=4 ;;
        friday)    target_dow=5 ;;
        saturday)  target_dow=6 ;;
        sunday)    target_dow=7 ;;
        *)         target_dow=1 ;;
    esac

    days_back=$(( (today_dow - target_dow + 7) % 7 ))
    date -d "$today - $days_back days" +%Y-%m-%d 2>/dev/null || \
        date -v-"${days_back}d" +%Y-%m-%d 2>/dev/null || echo "$today"
}

# Returns the end of the current allowance week (ISO date).
_allowance_week_end() {
    local week_start="$1"
    date -d "$week_start + 6 days" +%Y-%m-%d 2>/dev/null || \
        date -v+6d -jf "%Y-%m-%d" "$week_start" +%Y-%m-%d 2>/dev/null || echo "$week_start"
}

# Displays a weekly summary when resuming after a week boundary (spec-35 §7).
# Shows tokens used, runs, tasks completed, estimated API-equivalent savings,
# and the fresh allowance for the new week. Called from _allowance_check_rollover()
# BEFORE resetting counters so old week data is still available.
_display_weekly_summary() {
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ ! -f "$budget_file" ]; then
        return 0
    fi

    local old_week_start old_week_end tokens_used_week
    old_week_start=$(jq -r '.week_start // ""' "$budget_file")
    old_week_end=$(jq -r '.week_end // ""' "$budget_file")
    tokens_used_week=$(jq '.tokens_used_this_week // 0' "$budget_file")
    local weekly_allowance="$BUDGET_WEEKLY_ALLOWANCE"

    if [ -z "$old_week_start" ] || [ -z "$old_week_end" ]; then
        return 0
    fi

    # Format dates for display
    local ws_display we_display
    ws_display=$(date -d "$old_week_start" "+%b %d" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$old_week_start" "+%b %d" 2>/dev/null || echo "$old_week_start")
    we_display=$(date -d "$old_week_end" "+%b %d, %Y" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$old_week_end" "+%b %d, %Y" 2>/dev/null || echo "$old_week_end")

    # Use cross-project data when available for accurate totals
    local total_runs=0 project_count=1
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)
    if [ -f "$allowance_file" ]; then
        local cross_total
        cross_total=$(jq '.current_week.total_used // 0' "$allowance_file" 2>/dev/null || echo 0)
        if [ "$cross_total" -gt "$tokens_used_week" ]; then
            tokens_used_week="$cross_total"
        fi
        project_count=$(jq '.current_week.projects | length' "$allowance_file" 2>/dev/null || echo 1)
        total_runs=$(jq '[.current_week.projects[].runs] | add // 0' "$allowance_file" 2>/dev/null || echo 0)
    fi
    [ "$project_count" -lt 1 ] && project_count=1
    [ "$total_runs" -lt 1 ] && total_runs=1

    # Usage percentage
    local usage_pct
    usage_pct=$(awk -v used="$tokens_used_week" -v total="$weekly_allowance" \
        'BEGIN { if (total > 0) printf "%.0f", used * 100 / total; else printf "0" }')

    # Tasks completed (from plan file)
    local tasks_completed=0
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    if [ -f "$plan_file" ]; then
        tasks_completed=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null) || tasks_completed=0
    fi

    # Estimate API-equivalent cost from budget-history.json run entries within the week
    local estimated_savings="0.00"
    local history_file="$AUTOMATON_DIR/budget-history.json"
    if [ -f "$history_file" ]; then
        local run_prefix_start day_after_end run_prefix_end
        run_prefix_start="run-${old_week_start}"
        day_after_end=$(date -d "$old_week_end + 1 day" +%Y-%m-%d 2>/dev/null || \
            date -jf "%Y-%m-%d" -v+1d "$old_week_end" +%Y-%m-%d 2>/dev/null || echo "9999-99-99")
        run_prefix_end="run-${day_after_end}"
        estimated_savings=$(jq --arg start "$run_prefix_start" --arg end "$run_prefix_end" '
            [.runs[] | select(.run_id >= $start and .run_id < $end) | .estimated_cost_usd] |
            add // 0 | . * 100 | round / 100
        ' "$history_file" 2>/dev/null || echo "0.00")
    fi

    # New week boundaries
    local new_week_start new_week_end new_ws_display new_we_display
    new_week_start=$(_allowance_week_start)
    new_week_end=$(_allowance_week_end "$new_week_start")
    new_ws_display=$(date -d "$new_week_start" "+%b %d" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$new_week_start" "+%b %d" 2>/dev/null || echo "$new_week_start")
    new_we_display=$(date -d "$new_week_end" "+%b %d, %Y" 2>/dev/null || \
        date -jf "%Y-%m-%d" "$new_week_end" "+%b %d, %Y" 2>/dev/null || echo "$new_week_end")

    # Fresh allowance for new week
    local effective_allowance
    effective_allowance=$(awk -v total="$weekly_allowance" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
        'BEGIN { printf "%d", total * (1 - reserve/100) }')

    _fmt_num() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Weekly Summary: $ws_display — $we_display"
    printf " Total tokens used:  %s / %s (%s%%)\n" "$(_fmt_num "$tokens_used_week")" "$(_fmt_num "$weekly_allowance")" "$usage_pct"
    printf " Runs:               %s across %s project%s\n" "$total_runs" "$project_count" "$([ "$project_count" -ne 1 ] && echo 's' || echo '')"
    printf " Tasks completed:    %s\n" "$tasks_completed"
    printf " Estimated savings:  \$%s vs API pricing\n" "$estimated_savings"
    echo " New week started:   $new_ws_display — $new_we_display"
    printf " Fresh allowance:    %s tokens\n" "$(_fmt_num "$effective_allowance")"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Checks if the current date is past the stored week_end in budget.json.
# If so, archives the current week and resets counters.
# Called during --resume in allowance mode.
_allowance_check_rollover() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ ! -f "$budget_file" ]; then
        return 0
    fi

    local stored_week_end today
    stored_week_end=$(jq -r '.week_end // ""' "$budget_file")
    today=$(date +%Y-%m-%d)

    if [ -z "$stored_week_end" ]; then
        return 0
    fi

    # Compare dates: if today > week_end, rollover needed
    if [[ "$today" > "$stored_week_end" ]]; then
        # Display weekly summary before resetting counters (spec-35 §7)
        _display_weekly_summary

        log "ORCHESTRATOR" "Allowance week rollover: $stored_week_end has passed. Resetting weekly counters."

        local new_week_start new_week_end effective_allowance tmp
        new_week_start=$(_allowance_week_start)
        new_week_end=$(_allowance_week_end "$new_week_start")
        effective_allowance=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')
        tmp="$AUTOMATON_DIR/budget.json.tmp"

        jq \
            --arg ws "$new_week_start" \
            --arg we "$new_week_end" \
            --argjson eff "$effective_allowance" \
            '
            # Archive current week
            .allowance_history += [{
                week_start: .week_start,
                week_end: .week_end,
                tokens_used: .tokens_used_this_week,
                effective_allowance: .limits.effective_allowance
            }] |
            # Reset for new week
            .week_start = $ws |
            .week_end = $we |
            .tokens_used_this_week = 0 |
            .tokens_remaining = $eff |
            .limits.effective_allowance = $eff
            ' "$budget_file" > "$tmp"
        mv "$tmp" "$budget_file"

        log "ORCHESTRATOR" "New allowance week: $new_week_start to $new_week_end ($effective_allowance effective tokens)"

        # Also roll over the cross-project allowance file
        _cross_project_rollover "$stored_week_end"
    fi
}

# ---------------------------------------------------------------------------
# Cross-Project Allowance Tracking (spec-35 §5)
# ---------------------------------------------------------------------------
# Tracks token usage across multiple projects sharing one Max Plan allowance.
# WHY: Max Plan users running automaton on different projects share a single
# weekly allowance; cross-project tracking prevents over-allocation.

# Returns the path to the cross-project allowance file.
_cross_project_allowance_file() {
    echo "${HOME}/.automaton/allowance.json"
}

# Initializes ~/.automaton/allowance.json if missing or if the current week
# has rolled over. Called from initialize_budget() in allowance mode.
_init_cross_project_allowance() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local allowance_file
    allowance_file=$(_cross_project_allowance_file)
    local allowance_dir
    allowance_dir=$(dirname "$allowance_file")

    # Create ~/.automaton/ directory if needed
    mkdir -p "$allowance_dir"

    local week_start week_end
    week_start=$(_allowance_week_start)
    week_end=$(_allowance_week_end "$week_start")

    if [ ! -f "$allowance_file" ] || [ ! -s "$allowance_file" ]; then
        # Create fresh allowance file
        jq -n \
            --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
            --arg reset_day "$BUDGET_ALLOWANCE_RESET_DAY" \
            --arg week_start "$week_start" \
            --arg week_end "$week_end" \
            '{
                weekly_allowance_tokens: $weekly_allowance,
                allowance_reset_day: $reset_day,
                current_week: {
                    week_start: $week_start,
                    week_end: $week_end,
                    projects: {},
                    total_used: 0
                },
                history: []
            }' > "$allowance_file"
        log "ORCHESTRATOR" "Cross-project allowance tracking initialized: $allowance_file"
        return 0
    fi

    # Check if stored week has rolled over
    local stored_week_end
    stored_week_end=$(jq -r '.current_week.week_end // ""' "$allowance_file" 2>/dev/null || echo "")

    if [ -n "$stored_week_end" ] && [[ "$(date +%Y-%m-%d)" > "$stored_week_end" ]]; then
        _cross_project_rollover "$stored_week_end"
    fi

    # Update config values in case they changed
    local tmp="${allowance_file}.tmp"
    jq \
        --argjson weekly_allowance "$BUDGET_WEEKLY_ALLOWANCE" \
        --arg reset_day "$BUDGET_ALLOWANCE_RESET_DAY" \
        '.weekly_allowance_tokens = $weekly_allowance | .allowance_reset_day = $reset_day' \
        "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"
}

# Archives the current week in ~/.automaton/allowance.json and resets for a new week.
# Args: old_week_end (ISO date of the week that just ended)
_cross_project_rollover() {
    local old_week_end="$1"
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ ! -f "$allowance_file" ]; then
        return 0
    fi

    local new_week_start new_week_end
    new_week_start=$(_allowance_week_start)
    new_week_end=$(_allowance_week_end "$new_week_start")

    local tmp="${allowance_file}.tmp"
    jq \
        --arg ws "$new_week_start" \
        --arg we "$new_week_end" \
        '
        # Archive current week to history
        .history += [{
            week_start: .current_week.week_start,
            week_end: .current_week.week_end,
            projects: .current_week.projects,
            total_used: .current_week.total_used
        }] |
        # Reset for new week
        .current_week = {
            week_start: $ws,
            week_end: $we,
            projects: {},
            total_used: 0
        }
        ' "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"

    log "ORCHESTRATOR" "Cross-project allowance rolled over to week $new_week_start — $new_week_end"
}

# Updates ~/.automaton/allowance.json with token usage for the current project.
# Called from update_budget() after each iteration in allowance mode.
# Args: tokens_used (input + output tokens for this iteration)
_update_cross_project_allowance() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local tokens_used="${1:-0}"
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ ! -f "$allowance_file" ]; then
        _init_cross_project_allowance
    fi

    local project_dir
    project_dir=$(pwd)
    local now_ts
    now_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp="${allowance_file}.tmp"
    jq \
        --arg project "$project_dir" \
        --argjson tokens "$tokens_used" \
        --arg last_run "$now_ts" \
        '
        # Update or create project entry
        if .current_week.projects[$project] then
            .current_week.projects[$project].tokens_used += $tokens |
            .current_week.projects[$project].last_run = $last_run
        else
            .current_week.projects[$project] = {
                tokens_used: $tokens,
                runs: 0,
                last_run: $last_run
            }
        end |
        # Recalculate total from all projects
        .current_week.total_used = ([.current_week.projects[].tokens_used] | add // 0)
        ' "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"
}

# Increments the run count for the current project in ~/.automaton/allowance.json.
# Called from write_run_summary() at run completion.
_increment_cross_project_run_count() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ ! -f "$allowance_file" ]; then
        return 0
    fi

    local project_dir
    project_dir=$(pwd)

    local tmp="${allowance_file}.tmp"
    jq \
        --arg project "$project_dir" \
        '
        if .current_week.projects[$project] then
            .current_week.projects[$project].runs += 1
        else . end
        ' "$allowance_file" > "$tmp" && mv "$tmp" "$allowance_file"
}

# Returns total tokens used across all projects this week.
# Reads from ~/.automaton/allowance.json if available, falls back to local budget.json.
# WHY: Pacing calculations must account for all projects sharing the allowance.
_get_cross_project_total_used() {
    local allowance_file
    allowance_file=$(_cross_project_allowance_file)

    if [ -f "$allowance_file" ]; then
        jq '.current_week.total_used // 0' "$allowance_file" 2>/dev/null || echo 0
    else
        # Fall back to local project usage
        local budget_file="$AUTOMATON_DIR/budget.json"
        if [ -f "$budget_file" ]; then
            jq '.tokens_used_this_week // 0' "$budget_file" 2>/dev/null || echo 0
        else
            echo 0
        fi
    fi
}

# Calculates daily budget for allowance pacing (spec-35).
# Returns the number of tokens available per day based on remaining allowance
# and days until the weekly reset. Minimum 1 day to avoid division by zero.
# Prints the daily budget to stdout.
_calculate_daily_budget() {
    local budget_file="$AUTOMATON_DIR/budget.json"

    # Calculate remaining tokens using cross-project totals when available.
    # WHY: Pacing must account for all projects sharing the weekly allowance.
    local remaining effective_allowance cross_project_used
    effective_allowance=$(awk -v total="$BUDGET_WEEKLY_ALLOWANCE" -v reserve="$BUDGET_RESERVE_PERCENTAGE" \
        'BEGIN { printf "%d", total * (1 - reserve/100) }')
    cross_project_used=$(_get_cross_project_total_used)
    if [ "$cross_project_used" -gt 0 ]; then
        remaining=$((effective_allowance - cross_project_used))
        [ "$remaining" -lt 0 ] && remaining=0
    elif [ -f "$budget_file" ] && [ "$(jq -r '.mode // ""' "$budget_file")" = "allowance" ]; then
        remaining=$(jq '.tokens_remaining // 0' "$budget_file")
    else
        remaining="$effective_allowance"
    fi

    # Calculate days until reset (minimum 1)
    local week_end today days_left
    if [ -f "$budget_file" ]; then
        week_end=$(jq -r '.week_end // ""' "$budget_file")
    fi
    if [ -z "${week_end:-}" ]; then
        local ws
        ws=$(_allowance_week_start)
        week_end=$(_allowance_week_end "$ws")
    fi
    today=$(date +%Y-%m-%d)

    # Calculate difference in days
    local today_epoch end_epoch
    today_epoch=$(date -d "$today" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$today" +%s 2>/dev/null || echo 0)
    end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s 2>/dev/null || echo 0)

    if [ "$today_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
        days_left=$(( (end_epoch - today_epoch) / 86400 + 1 ))
    else
        days_left=1
    fi
    [ "$days_left" -lt 1 ] && days_left=1

    # daily_budget = remaining / days_left
    awk -v rem="$remaining" -v days="$days_left" \
        'BEGIN { printf "%d", rem / days }'
}

# Checks daily budget at run startup and warns if it's below 500K tokens.
# Called from run_orchestration() after budget initialization.
_check_daily_budget_pacing() {
    if [ "$BUDGET_MODE" != "allowance" ]; then
        return 0
    fi

    local daily_budget
    daily_budget=$(_calculate_daily_budget)

    # Store daily budget in budget.json for enforcement
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ -f "$budget_file" ]; then
        local tmp="$AUTOMATON_DIR/budget.json.tmp"
        jq --argjson db "$daily_budget" \
            '.limits.daily_budget = $db' "$budget_file" > "$tmp"
        mv "$tmp" "$budget_file"
    fi

    if [ "$daily_budget" -lt 500000 ]; then
        local week_end
        week_end=$(jq -r '.week_end // "unknown"' "$budget_file" 2>/dev/null || echo "unknown")
        local days_left remaining
        remaining=$(jq '.tokens_remaining // 0' "$budget_file" 2>/dev/null || echo 0)
        log "ORCHESTRATOR" "WARNING: Daily budget is ${daily_budget} tokens (allowance resets after ${week_end}). Run may be cut short."
    else
        log "ORCHESTRATOR" "Daily budget pacing: ${daily_budget} tokens/day"
    fi
}

# Displays weekly allowance budget status without starting a run (spec-35).
# Shows: week dates, allowance, used, remaining, reserve, available,
# days left, daily pace, and recommended run budget.
# In API mode, shows API budget info instead.
# Called by --budget-check CLI command.
display_budget_check() {
    local budget_file="$AUTOMATON_DIR/budget.json"

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Calculate week boundaries
        local week_start week_end
        if [ -f "$budget_file" ] && [ "$(jq -r '.mode // ""' "$budget_file")" = "allowance" ]; then
            week_start=$(jq -r '.week_start // ""' "$budget_file")
            week_end=$(jq -r '.week_end // ""' "$budget_file")
        fi
        if [ -z "${week_start:-}" ]; then
            week_start=$(_allowance_week_start)
        fi
        if [ -z "${week_end:-}" ]; then
            week_end=$(_allowance_week_end "$week_start")
        fi

        # Format dates for display (e.g., "Feb 24" / "Mar 02")
        local ws_display we_display
        ws_display=$(date -d "$week_start" "+%b %d" 2>/dev/null || \
            date -jf "%Y-%m-%d" "$week_start" "+%b %d" 2>/dev/null || echo "$week_start")
        we_display=$(date -d "$week_end" "+%b %d, %Y" 2>/dev/null || \
            date -jf "%Y-%m-%d" "$week_end" "+%b %d, %Y" 2>/dev/null || echo "$week_end")

        # Get usage data
        local weekly_allowance used_tokens remaining effective_allowance reserve_pct
        weekly_allowance="$BUDGET_WEEKLY_ALLOWANCE"
        reserve_pct="$BUDGET_RESERVE_PERCENTAGE"

        effective_allowance=$(awk -v total="$weekly_allowance" -v reserve="$reserve_pct" \
            'BEGIN { printf "%d", total * (1 - reserve/100) }')

        # Use cross-project total when available for accurate pacing
        local cross_total
        cross_total=$(_get_cross_project_total_used)
        if [ "$cross_total" -gt 0 ]; then
            used_tokens="$cross_total"
        elif [ -f "$budget_file" ] && [ "$(jq -r '.mode // ""' "$budget_file")" = "allowance" ]; then
            used_tokens=$(jq '.tokens_used_this_week // 0' "$budget_file")
        else
            used_tokens=0
        fi
        remaining=$((effective_allowance - used_tokens))
        [ "$remaining" -lt 0 ] && remaining=0

        # Calculate reserve tokens and available (remaining after reserve)
        local reserve_tokens
        reserve_tokens=$(awk -v total="$weekly_allowance" -v reserve="$reserve_pct" \
            'BEGIN { printf "%d", total * reserve / 100 }')

        # Calculate days left
        local today today_epoch end_epoch days_left
        today=$(date +%Y-%m-%d)
        today_epoch=$(date -d "$today" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$today" +%s 2>/dev/null || echo 0)
        end_epoch=$(date -d "$week_end" +%s 2>/dev/null || date -jf "%Y-%m-%d" "$week_end" +%s 2>/dev/null || echo 0)
        if [ "$today_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ]; then
            days_left=$(( (end_epoch - today_epoch) / 86400 + 1 ))
        else
            days_left=1
        fi
        [ "$days_left" -lt 1 ] && days_left=1

        # Calculate daily pace and recommended run budget
        local daily_pace recommended_run
        daily_pace=$(awk -v rem="$remaining" -v days="$days_left" \
            'BEGIN { printf "%d", rem / days }')
        # Recommended = min(daily_pace, remaining * 0.5)
        local half_remaining
        half_remaining=$(awk -v rem="$remaining" 'BEGIN { printf "%d", rem * 0.5 }')
        if [ "$daily_pace" -lt "$half_remaining" ]; then
            recommended_run="$daily_pace"
        else
            recommended_run="$half_remaining"
        fi

        # Calculate usage percentage
        local used_pct
        used_pct=$(awk -v used="$used_tokens" -v total="$weekly_allowance" \
            'BEGIN { if (total > 0) printf "%.1f", used * 100 / total; else printf "0.0" }')

        # Format numbers with commas using printf
        _fmt_num() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " Automaton Weekly Budget Status"
        echo " Week:       $ws_display — $we_display"
        printf " Allowance:  %s tokens\n" "$(_fmt_num "$weekly_allowance")"
        printf " Used:       %s tokens (%s%%)\n" "$(_fmt_num "$used_tokens")" "$used_pct"
        printf " Remaining:  %s tokens\n" "$(_fmt_num "$remaining")"
        printf " Reserve:    %s tokens (%s%%)\n" "$(_fmt_num "$reserve_tokens")" "$reserve_pct"
        printf " Available:  %s tokens\n" "$(_fmt_num "$remaining")"
        echo " Days left:  $days_left"
        printf " Daily pace: %s tokens/day\n" "$(_fmt_num "$daily_pace")"
        printf " Recommended run budget: %s tokens\n" "$(_fmt_num "$recommended_run")"

        # Show cross-project usage if available (spec-35 §5)
        local allowance_file
        allowance_file=$(_cross_project_allowance_file)
        if [ -f "$allowance_file" ]; then
            local project_count cross_total
            project_count=$(jq '.current_week.projects | length' "$allowance_file" 2>/dev/null || echo 0)
            cross_total=$(jq '.current_week.total_used // 0' "$allowance_file" 2>/dev/null || echo 0)
            if [ "$project_count" -gt 1 ] || [ "$cross_total" -gt 0 ]; then
                echo "─────────── Cross-Project Usage ────────"
                printf " Projects:   %s\n" "$project_count"
                printf " Total used: %s tokens (all projects)\n" "$(_fmt_num "$cross_total")"
                # List individual projects
                local projects_list
                projects_list=$(jq -r '.current_week.projects | to_entries[] | "\(.key)\t\(.value.tokens_used)\t\(.value.runs)"' "$allowance_file" 2>/dev/null || true)
                if [ -n "$projects_list" ]; then
                    while IFS=$'\t' read -r proj_path proj_tokens proj_runs; do
                        local proj_name
                        proj_name=$(basename "$proj_path")
                        printf "   %s: %s tokens (%s runs)\n" "$proj_name" "$(_fmt_num "$proj_tokens")" "$proj_runs"
                    done <<< "$projects_list"
                fi
            fi
        fi

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    else
        # API mode: show API budget summary
        local total_used total_cost
        if [ -f "$budget_file" ]; then
            total_used=$(jq '(.used.total_input // 0) + (.used.total_output // 0)' "$budget_file")
            total_cost=$(jq '.used.estimated_cost_usd // 0' "$budget_file")
        else
            total_used=0
            total_cost=0
        fi

        _fmt_num() { printf "%'d" "$1" 2>/dev/null || echo "$1"; }

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " Automaton API Budget Status"
        echo " Mode:       api (pay-per-token)"
        printf " Max tokens: %s\n" "$(_fmt_num "$BUDGET_MAX_TOKENS")"
        printf " Max cost:   \$%s\n" "$BUDGET_MAX_USD"
        printf " Used:       %s tokens\n" "$(_fmt_num "$total_used")"
        printf " Cost:       \$%s\n" "$total_cost"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    exit 0
}

# Extracts token usage from Claude CLI stream-json output.
# Parses the final "type":"result" line for input, output, cache_create, cache_read.
# Sets global variables: LAST_INPUT_TOKENS, LAST_OUTPUT_TOKENS,
#   LAST_CACHE_CREATE, LAST_CACHE_READ
extract_tokens() {
    local result_output="$1"
    local usage_line
    usage_line=$(echo "$result_output" | grep '"type":"result"' | tail -1 || true)

    if [ -z "$usage_line" ]; then
        LAST_INPUT_TOKENS=0
        LAST_OUTPUT_TOKENS=0
        LAST_CACHE_CREATE=0
        LAST_CACHE_READ=0
        return
    fi

    LAST_INPUT_TOKENS=$(echo "$usage_line" | jq -r '.usage.input_tokens // 0')
    LAST_OUTPUT_TOKENS=$(echo "$usage_line" | jq -r '.usage.output_tokens // 0')
    LAST_CACHE_CREATE=$(echo "$usage_line" | jq -r '.usage.cache_creation_input_tokens // 0')
    LAST_CACHE_READ=$(echo "$usage_line" | jq -r '.usage.cache_read_input_tokens // 0')
}

# Detects auto-compaction by finding input_tokens drops between turns in
# stream-json output. Auto-compaction at ~95% context capacity compresses the
# conversation, causing a significant drop in input_tokens on the next turn.
# Sets global: LAST_AUTO_COMPACTION_DETECTED (true/false)
# WHY: Knowing when compaction occurred helps explain unexpected behavior and
# informs task sizing decisions (spec-33).
detect_auto_compaction() {
    local result_output="$1"
    LAST_AUTO_COMPACTION_DETECTED=false

    # Extract all input_tokens values from lines containing usage data
    local token_values
    token_values=$(echo "$result_output" \
        | grep '"input_tokens"' \
        | jq -r '.usage.input_tokens // empty' 2>/dev/null \
        | grep -v '^$' || true)

    [ -z "$token_values" ] && return 0

    # Need at least 2 data points to detect a drop
    local count
    count=$(echo "$token_values" | wc -l)
    [ "$count" -lt 2 ] && return 0

    # Check for any drop where input_tokens decreases by more than 20%
    local prev_tokens=0
    local current_tokens
    while IFS= read -r current_tokens; do
        [ -z "$current_tokens" ] && continue
        if [ "$prev_tokens" -gt 0 ] && [ "$current_tokens" -lt "$prev_tokens" ]; then
            # Calculate drop percentage
            local drop_pct
            drop_pct=$(awk -v prev="$prev_tokens" -v curr="$current_tokens" \
                'BEGIN { printf "%.0f", ((prev - curr) / prev) * 100 }')
            if [ "$drop_pct" -ge 20 ]; then
                LAST_AUTO_COMPACTION_DETECTED=true
                log "ORCHESTRATOR" "WARNING: Auto-compaction detected in ${current_phase} iteration ${phase_iteration} (input_tokens dropped from ${prev_tokens} to ${current_tokens}, -${drop_pct}%). Uncommitted work may have been lost."
                # --- Mitigation: protect uncommitted work and refresh context ---
                mitigate_compaction
                return 0
            fi
        fi
        prev_tokens="$current_tokens"
    done <<< "$token_values"
}

# Mitigates auto-compaction by committing uncommitted work, refreshing
# progress.txt, and flagging the next iteration for reduced dynamic context.
# Without mitigation, auto-compaction can silently lose uncommitted changes
# and leave the agent in a confused state with stale context.
mitigate_compaction() {
    # 1. Force-commit any uncommitted work to prevent data loss
    local uncommitted_files
    uncommitted_files=$(git diff --name-only 2>/dev/null | wc -l)
    local untracked_files
    untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)

    if [ "$uncommitted_files" -gt 0 ] || [ "$untracked_files" -gt 0 ]; then
        log "ORCHESTRATOR" "Compaction mitigation: committing $uncommitted_files modified + $untracked_files untracked files"
        git add -A 2>/dev/null || true
        git commit -m "auto-save: compaction detected in ${current_phase} iteration ${phase_iteration}" \
            --allow-empty 2>/dev/null || true
    fi

    # 2. Regenerate progress.txt so next iteration has fresh state awareness
    generate_progress_txt 2>/dev/null || true

    # 3. Set flag to reduce dynamic context in the next iteration
    # When this flag is set, inject_dynamic_context will omit verbose sections
    # (iteration memory, full git diffs) to keep the prompt lean
    COMPACTION_REDUCE_CONTEXT=true

    # 4. Log the mitigation action
    log "ORCHESTRATOR" "Compaction mitigation complete: committed work, refreshed progress.txt, reducing next iteration context"
}

# Returns estimated USD cost for a given model and token counts.
# Uses the pricing table from spec-07.
# Usage: cost=$(estimate_cost "sonnet" 112000 24000 5000 80000)
estimate_cost() {
    local model="$1"
    local input="${2:-0}" output="${3:-0}" cache_create="${4:-0}" cache_read="${5:-0}"

    local input_rate output_rate cache_write_rate cache_read_rate
    case "$model" in
        opus)
            input_rate=15.00
            output_rate=75.00
            cache_write_rate=18.75
            cache_read_rate=1.50
            ;;
        sonnet)
            input_rate=3.00
            output_rate=15.00
            cache_write_rate=3.75
            cache_read_rate=0.30
            ;;
        haiku)
            input_rate=0.80
            output_rate=4.00
            cache_write_rate=1.00
            cache_read_rate=0.08
            ;;
        *)
            input_rate=3.00
            output_rate=15.00
            cache_write_rate=3.75
            cache_read_rate=0.30
            ;;
    esac

    awk -v inp="$input" -v out="$output" -v cc="$cache_create" -v cr="$cache_read" \
        -v ir="$input_rate" -v or_rate="$output_rate" -v cwr="$cache_write_rate" -v crr="$cache_read_rate" \
        'BEGIN { printf "%.4f", (inp*ir + out*or_rate + cc*cwr + cr*crr) / 1000000 }'
}

# Adds iteration token usage to cumulative totals in budget.json.
# Appends a history entry and recalculates estimated_cost_usd.
# Uses atomic write to prevent corruption.
update_budget() {
    local model="$1" input_tokens="$2" output_tokens="$3"
    local cache_create="$4" cache_read="$5"
    local iter_cost="$6" duration="$7" task_desc="$8" status="$9"

    local budget_file="$AUTOMATON_DIR/budget.json"
    local tmp="$AUTOMATON_DIR/budget.json.tmp"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local total_iter_tokens=$((input_tokens + output_tokens))

    # Calculate estimated context utilization (spec-33)
    local context_window=200000
    local estimated_utilization=0
    if [ "$total_iter_tokens" -gt 0 ]; then
        estimated_utilization=$(awk -v total="$total_iter_tokens" -v window="$context_window" \
            'BEGIN { printf "%.1f", (total / window) * 100 }')
    fi

    # Common jq update for both modes
    local jq_filter='
        .used.total_input += $input_tokens |
        .used.total_output += $output_tokens |
        .used.total_cache_create += $cache_create |
        .used.total_cache_read += $cache_read |
        .used.by_phase[$phase].input += $input_tokens |
        .used.by_phase[$phase].output += $output_tokens |
        .used.estimated_cost_usd = ((.used.estimated_cost_usd + $iter_cost) * 100 | round / 100) |
        .history += [{
            iteration: $iteration,
            phase: $phase,
            model: $model,
            input_tokens: $input_tokens,
            output_tokens: $output_tokens,
            cache_create: $cache_create,
            cache_read: $cache_read,
            cache_hit_ratio: (if ($cache_read + $input_tokens + $cache_create) > 0
                then (($cache_read / ($cache_read + $input_tokens + $cache_create)) * 100 | round / 100)
                else 0 end),
            estimated_cost: $iter_cost,
            duration_seconds: $duration,
            task: $task,
            status: $status,
            timestamp: $timestamp,
            estimated_utilization: $utilization,
            bootstrap_tokens_saved: $bootstrap_saved,
            bootstrap_time_ms: $bootstrap_ms
        }]'

    # In allowance mode, also update weekly token counters
    if [ "$BUDGET_MODE" = "allowance" ]; then
        jq_filter="${jq_filter}"'
        | .tokens_used_this_week += ($input_tokens + $output_tokens)
        | .tokens_remaining = (.limits.effective_allowance - .tokens_used_this_week)'
    fi

    jq \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson cache_create "$cache_create" \
        --argjson cache_read "$cache_read" \
        --argjson iter_cost "$iter_cost" \
        --arg phase "$current_phase" \
        --argjson iteration "$iteration" \
        --arg model "$model" \
        --argjson duration "$duration" \
        --arg task "$task_desc" \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson utilization "$estimated_utilization" \
        --argjson bootstrap_saved "${BOOTSTRAP_TOKENS_SAVED:-0}" \
        --argjson bootstrap_ms "${BOOTSTRAP_TIME_MS:-0}" \
        "$jq_filter" "$budget_file" > "$tmp"
    mv "$tmp" "$budget_file"

    # Update cross-project allowance tracking (spec-35 §5)
    if [ "$BUDGET_MODE" = "allowance" ]; then
        local iter_tokens=$((input_tokens + output_tokens))
        _update_cross_project_allowance "$iter_tokens"
    fi

    # Structured work log: budget_update (spec-55)
    local cumulative_tokens
    cumulative_tokens=$(jq -r '(.used.total_input + .used.total_output) // 0' "$budget_file" 2>/dev/null || echo 0)
    local remaining_budget
    remaining_budget=$(jq -r '(.limits.max_tokens - .used.total_input - .used.total_output) // 0' "$budget_file" 2>/dev/null || echo 0)
    emit_event "budget_update" "{\"tokens_used\":${cumulative_tokens},\"budget_remaining\":${remaining_budget},\"cost_usd\":${iter_cost}}"
}

# Checks rolling average cache hit ratio for the current phase.
# Emits a warning when the rolling average drops below 50% after 3+ iterations.
# WHY: Low cache ratio indicates the static prompt prefix is changing between
# iterations — likely a bug in prompt assembly that wastes tokens (spec-30).
check_cache_hit_ratio() {
    local budget_file="$AUTOMATON_DIR/budget.json"
    [ -f "$budget_file" ] || return 0

    local phase_count avg
    phase_count=$(jq --arg phase "$current_phase" \
        '[.history[] | select(.phase == $phase)] | length' \
        "$budget_file" 2>/dev/null || echo 0)

    # Only check after 3+ iterations in the current phase
    [ "$phase_count" -ge 3 ] || return 0

    avg=$(jq --arg phase "$current_phase" '
        [.history[] | select(.phase == $phase) | .cache_hit_ratio] |
        if length > 0 then (add / length) else 0 end
    ' "$budget_file" 2>/dev/null || echo 0)

    # Compare: avg < 0.50 means below 50%
    local below
    below=$(awk -v a="$avg" 'BEGIN { print (a < 0.50) ? 1 : 0 }')
    if [ "$below" -eq 1 ]; then
        local pct
        pct=$(awk -v a="$avg" 'BEGIN { printf "%.0f", a * 100 }')
        log "ORCHESTRATOR" "WARNING: Cache hit ratio for phase '${current_phase}' is ${pct}% (rolling avg over ${phase_count} iterations). Expected >=50%. Check that dynamic data is injected after the static prefix marker."
    fi
}

# Checks context utilization for the current iteration against per-phase ceilings.
# Logs a warning when utilization exceeds the ceiling (spec-33).
# WHY: Performance degrades as context fills; warnings alert users to split tasks
# or commit more frequently.
check_context_utilization() {
    local input_tokens="$1" output_tokens="$2" model="$3"

    # Model context window sizes (all current models are 200K)
    local context_window=200000
    case "$model" in
        opus|sonnet|haiku) context_window=200000 ;;
    esac

    # Per-phase context utilization ceilings
    local ceiling
    case "$current_phase" in
        research) ceiling=60 ;;
        plan)     ceiling=70 ;;
        build)    ceiling=80 ;;
        review)   ceiling=70 ;;
        *)        ceiling=80 ;;
    esac

    local total_tokens=$((input_tokens + output_tokens))
    [ "$total_tokens" -eq 0 ] && return 0

    local utilization_pct
    utilization_pct=$(awk -v total="$total_tokens" -v window="$context_window" \
        'BEGIN { printf "%.0f", (total / window) * 100 }')

    local exceeds
    exceeds=$(awk -v u="$utilization_pct" -v c="$ceiling" 'BEGIN { print (u > c) ? 1 : 0 }')

    if [ "$exceeds" -eq 1 ]; then
        log "ORCHESTRATOR" "WARNING: ${current_phase^} iteration ${phase_iteration} context utilization ${utilization_pct}% exceeds ceiling ${ceiling}%. Consider smaller tasks or more frequent commits."
    fi
}

# Enforces budget rules after each iteration. Returns 0 to continue,
# 1 to force phase transition, or exits with code 2 for hard stops.
# In API mode: enforces per-iteration, per-phase, total token, and cost limits.
# In allowance mode (spec-23): enforces weekly token allowance and phase proportions.
check_budget() {
    local input_tokens="$1" output_tokens="$2"
    local budget_file="$AUTOMATON_DIR/budget.json"
    local total_iter_tokens=$((input_tokens + output_tokens))

    # Rule 1: Per-iteration warning (advisory, both modes)
    if [ "$total_iter_tokens" -gt "$BUDGET_PER_ITERATION" ]; then
        log "ORCHESTRATOR" "WARNING: Iteration used ${total_iter_tokens} tokens, exceeding per-iteration limit of ${BUDGET_PER_ITERATION}"
    fi

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # --- Allowance mode enforcement (spec-23) ---
        local tokens_remaining tokens_used effective_allowance week_end
        tokens_remaining=$(jq '.tokens_remaining' "$budget_file")
        tokens_used=$(jq '.tokens_used_this_week' "$budget_file")
        effective_allowance=$(jq '.limits.effective_allowance' "$budget_file")
        week_end=$(jq -r '.week_end' "$budget_file")

        # Hard stop: weekly allowance exhausted (spec-35 §8)
        # Graceful exhaustion: iteration already completed (check_budget runs in
        # post_iteration), save state and run summary, then exit code 2.
        if [ "$tokens_remaining" -le 0 ]; then
            local reset_day_name
            reset_day_name=$(date -d "$week_end + 1 day" "+%A" 2>/dev/null || \
                date -jf "%Y-%m-%d" -v+1d "$week_end" "+%A" 2>/dev/null || echo "$week_end")
            log "ORCHESTRATOR" "Weekly allowance exhausted. Resets on ${reset_day_name}. Run --resume after reset."
            write_run_summary 2 2>/dev/null || true
            commit_persistent_state "${current_phase:-build}" "${iteration:-0}" 2>/dev/null || true
            write_state
            exit 2
        fi

        # Pre-iteration warning: less than one iteration's worth of tokens left
        if [ "$tokens_remaining" -lt "$BUDGET_PER_ITERATION" ]; then
            log "ORCHESTRATOR" "WARNING: Only ${tokens_remaining} tokens remaining in weekly allowance (need ~${BUDGET_PER_ITERATION} per iteration)"
        fi

        # Daily budget pacing (spec-35): enforce daily_budget as run-level ceiling
        local daily_budget run_tokens
        daily_budget=$(jq '.limits.daily_budget // 0' "$budget_file")
        if [ "$daily_budget" -gt 0 ]; then
            run_tokens=$(jq '(.used.total_input + .used.total_output)' "$budget_file")
            if [ "$run_tokens" -ge "$daily_budget" ]; then
                log "ORCHESTRATOR" "Daily budget pacing limit reached (${run_tokens}/${daily_budget} tokens). Saving state. Run --resume tomorrow or after adjusting budget."
                write_run_summary 2 2>/dev/null || true
                commit_persistent_state "${current_phase:-build}" "${iteration:-0}" 2>/dev/null || true
                write_state
                exit 2
            fi
            # Warning at 80% of daily budget
            local warn_threshold
            warn_threshold=$(awk -v db="$daily_budget" 'BEGIN { printf "%d", db * 0.8 }')
            if [ "$run_tokens" -ge "$warn_threshold" ]; then
                local pct
                pct=$(awk -v used="$run_tokens" -v total="$daily_budget" \
                    'BEGIN { printf "%.0f", (used / total) * 100 }')
                log "ORCHESTRATOR" "WARNING: Run at ${pct}% of daily budget (${run_tokens}/${daily_budget} tokens)"
            fi
        fi

        # Phase proportioning (soft limits): check if current phase exceeded its share
        local phase_proportion phase_budget phase_input phase_output phase_tokens
        phase_proportion=$(jq --arg p "$current_phase" '.limits.phase_proportions[$p] // 0.25' "$budget_file")
        phase_budget=$(awk -v eff="$effective_allowance" -v prop="$phase_proportion" \
            'BEGIN { printf "%d", eff * prop }')
        phase_input=$(jq --arg p "$current_phase" '.used.by_phase[$p].input' "$budget_file")
        phase_output=$(jq --arg p "$current_phase" '.used.by_phase[$p].output' "$budget_file")
        phase_tokens=$((phase_input + phase_output))

        if [ "$phase_tokens" -gt "$phase_budget" ]; then
            log "ORCHESTRATOR" "Phase token proportion exhausted for ${current_phase} (${phase_tokens}/${phase_budget}). Transitioning to next phase."
            return 1
        fi
    else
        # --- API mode enforcement (original behavior) ---
        local total_input total_output total_cost
        total_input=$(jq '.used.total_input' "$budget_file")
        total_output=$(jq '.used.total_output' "$budget_file")
        total_cost=$(jq '.used.estimated_cost_usd' "$budget_file")
        local cumulative_tokens=$((total_input + total_output))

        # Rule 3: Total token hard stop
        if [ "$cumulative_tokens" -gt "$BUDGET_MAX_TOKENS" ]; then
            log "ORCHESTRATOR" "Total token budget exhausted (${cumulative_tokens}/${BUDGET_MAX_TOKENS}). Run --resume after adjusting budget."
            send_notification "run_failed" "${current_phase:-unknown}" "failure" "Token budget exhausted (${cumulative_tokens}/${BUDGET_MAX_TOKENS})"
            write_state
            exit 2
        fi

        # Rule 4: Cost hard stop
        local cost_exceeded
        cost_exceeded=$(awk -v cost="$total_cost" -v limit="$BUDGET_MAX_USD" \
            'BEGIN { print (cost > limit) ? "yes" : "no" }')
        if [ "$cost_exceeded" = "yes" ]; then
            log "ORCHESTRATOR" "Cost budget exhausted (\$${total_cost}/\$${BUDGET_MAX_USD}). Run --resume after adjusting budget."
            send_notification "run_failed" "${current_phase:-unknown}" "failure" "Cost budget exhausted (\$${total_cost}/\$${BUDGET_MAX_USD})"
            write_state
            exit 2
        fi

        # Rule 2: Per-phase force transition
        local phase_limit_var="BUDGET_PHASE_$(echo "$current_phase" | tr '[:lower:]' '[:upper:]')"
        local phase_limit="${!phase_limit_var}"
        local phase_input phase_output
        phase_input=$(jq --arg p "$current_phase" '.used.by_phase[$p].input' "$budget_file")
        phase_output=$(jq --arg p "$current_phase" '.used.by_phase[$p].output' "$budget_file")
        local phase_tokens=$((phase_input + phase_output))

        if [ "$phase_tokens" -gt "$phase_limit" ]; then
            log "ORCHESTRATOR" "Phase budget exhausted for ${current_phase} (${phase_tokens}/${phase_limit}). Transitioning to next phase."
            return 1
        fi
    fi

    return 0
}
