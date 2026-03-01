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
        next_task=$(grep -m1 '^\- \[ \]' "$plan_file" | sed 's/^- \[ \] //' || echo "")
        total_tasks=$(grep -c '^\- \[' "$plan_file" 2>/dev/null || echo 0)
        done_tasks=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null || echo 0)
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

    echo "$manifest" | jq .
}

check_dependencies
validate_state
generate_context
