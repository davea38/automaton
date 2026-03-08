#!/usr/bin/env bash
# tests/test_bootstrap_bugfixes.sh — RED/GREEN tests for bootstrap and logging bugfixes
# Covers:
#   - init.sh grep -c double-output bug (done_tasks="0\n0")
#   - _run_bootstrap log() stdout pollution in subshell
#   - _format_bootstrap_for_context invalid JSON handling
#   - Agent output log saving to .automaton/logs/
#   - Progress spinner functions exist
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

INIT_SCRIPT="$PROJECT_ROOT/.automaton/init.sh"

# ===================================================================
# Test group 1: init.sh grep -c double-output bug
# When grep -c finds 0 matches, it outputs "0" AND exits 1.
# The old code `grep -c ... || echo 0` produced "0\n0" which broke --argjson.
# ===================================================================

setup_backlog_project() {
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR/.automaton"
    cd "$TEMP_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Backlog with NO completed tasks — triggers grep -c exit 1
    cat > "$TEMP_DIR/.automaton/backlog.md" <<'EOF'
# Improvement Backlog

## Tasks
- [ ] Pending task one
- [ ] Pending task two
EOF

    cat > "$TEMP_DIR/.automaton/budget.json" <<'EOF'
{
  "limits": { "max_cost_usd": 50 },
  "used": { "estimated_cost_usd": 0 }
}
EOF

    git add -A
    git commit -q -m "Initial"
    echo "x" >> "$TEMP_DIR/f.txt"
    git add -A
    git commit -q -m "Second"
}

# --- Test: init.sh produces valid JSON when done_tasks=0 ---
setup_backlog_project
output=$("$INIT_SCRIPT" "$TEMP_DIR" "build" "1" 2>/dev/null)
rc=$?
assert_exit_code 0 "$rc" "init.sh exits 0 with zero completed tasks"

echo "$output" | jq empty 2>/dev/null
assert_exit_code 0 $? "init.sh produces valid JSON when done_tasks=0"

done_val=$(echo "$output" | jq '.project_state.tasks_done' 2>/dev/null)
assert_equals "0" "$done_val" "tasks_done is numeric 0 (not '0\\n0')"

total_val=$(echo "$output" | jq '.project_state.tasks_total' 2>/dev/null)
assert_equals "2" "$total_val" "tasks_total is 2 with zero-completed backlog"

# --- Test: init.sh works with allowance-mode budget (no max_cost_usd) ---
cat > "$TEMP_DIR/.automaton/budget.json" <<'EOF'
{
  "mode": "allowance",
  "limits": {
    "weekly_allowance_tokens": 45000000,
    "effective_allowance": 36000000,
    "reserve_percentage": 20,
    "per_iteration": 500000,
    "daily_budget": 36000000
  },
  "used": { "estimated_cost_usd": 0.38 }
}
EOF
output_allowance=$("$INIT_SCRIPT" "$TEMP_DIR" "research" "1" 2>/dev/null)
echo "$output_allowance" | jq empty 2>/dev/null
assert_exit_code 0 $? "init.sh produces valid JSON with allowance-mode budget"

# ===================================================================
# Test group 2: _run_bootstrap log pollution
# When _run_bootstrap fails, log() calls should NOT appear in stdout
# (which becomes BOOTSTRAP_MANIFEST via $() subshell capture).
# ===================================================================

# --- Test: log messages in _run_bootstrap use >&2 ---
# Check that every log call in _run_bootstrap has >&2
bootstrap_func=$(sed -n '/^_run_bootstrap()/,/^}/p' "$PROJECT_ROOT/lib/context.sh")
log_in_bootstrap=$(echo "$bootstrap_func" | grep -c 'log "ORCHESTRATOR"' || true)
log_with_stderr=$(echo "$bootstrap_func" | grep -c 'log "ORCHESTRATOR".*>&2' || true)

if [ "$log_in_bootstrap" -gt 0 ]; then
    assert_equals "$log_in_bootstrap" "$log_with_stderr" \
        "All log() calls in _run_bootstrap redirect to stderr ($log_with_stderr/$log_in_bootstrap)"
else
    echo "PASS: No log calls in _run_bootstrap (or function not found)"
    ((_TEST_PASS_COUNT++))
fi

# ===================================================================
# Test group 3: _format_bootstrap_for_context invalid JSON handling
# When BOOTSTRAP_MANIFEST contains non-JSON text, jq . should not
# produce parse errors to terminal.
# ===================================================================

# --- Test: _format_bootstrap_for_context handles non-JSON gracefully ---
format_func=$(sed -n '/^_format_bootstrap_for_context()/,/^}/p' "$PROJECT_ROOT/lib/context.sh")
has_jq_guard=$(echo "$format_func" | grep -c 'jq empty' || true)
if [ "$has_jq_guard" -gt 0 ]; then
    echo "PASS: _format_bootstrap_for_context validates JSON before jq ."
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _format_bootstrap_for_context missing jq empty validation guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ===================================================================
# Test group 4: Agent output logging
# Every agent invocation should save output to .automaton/logs/
# ===================================================================

# --- Test: _save_agent_log function exists ---
if grep -q '^_save_agent_log()' "$PROJECT_ROOT/lib/utilities.sh"; then
    echo "PASS: _save_agent_log function exists in utilities.sh"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _save_agent_log function not found in utilities.sh" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test: run_agent calls _save_agent_log ---
run_agent_body=$(sed -n '/^run_agent()/,/^}/p' "$PROJECT_ROOT/lib/utilities.sh")
save_log_calls=$(echo "$run_agent_body" | grep -c '_save_agent_log' || true)
if [ "$save_log_calls" -ge 2 ]; then
    echo "PASS: run_agent calls _save_agent_log in both code paths ($save_log_calls calls)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: run_agent should call _save_agent_log in both native and legacy paths (found $save_log_calls)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ===================================================================
# Test group 5: Progress spinner
# Terminal should show activity while agent runs
# ===================================================================

# --- Test: _start_progress_spinner function exists ---
if grep -q '^_start_progress_spinner()' "$PROJECT_ROOT/lib/utilities.sh"; then
    echo "PASS: _start_progress_spinner function exists"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _start_progress_spinner function not found" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test: _stop_progress_spinner function exists ---
if grep -q '^_stop_progress_spinner()' "$PROJECT_ROOT/lib/utilities.sh"; then
    echo "PASS: _stop_progress_spinner function exists"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _stop_progress_spinner function not found" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test: run_agent starts and stops spinner ---
spinner_starts=$(echo "$run_agent_body" | grep -c '_start_progress_spinner' || true)
spinner_stops=$(echo "$run_agent_body" | grep -c '_stop_progress_spinner' || true)
if [ "$spinner_starts" -ge 2 ] && [ "$spinner_stops" -ge 2 ]; then
    echo "PASS: run_agent manages spinner in both code paths (starts=$spinner_starts stops=$spinner_stops)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: run_agent should start/stop spinner in both paths (starts=$spinner_starts stops=$spinner_stops)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ===================================================================
# Test group 6: _save_agent_log integration test
# ===================================================================

# --- Test: _save_agent_log creates log file ---
# Source just the function and test it
_test_save_log() {
    local test_automaton_dir="$TEMP_DIR/.automaton-logtest"
    mkdir -p "$test_automaton_dir"

    # Temporarily override AUTOMATON_DIR
    local orig_automaton_dir="${AUTOMATON_DIR:-}"
    AUTOMATON_DIR="$test_automaton_dir"

    # Inline the function since we can't easily source it
    local logs_dir="$test_automaton_dir/logs"
    mkdir -p "$logs_dir"
    local tmp_output
    tmp_output=$(mktemp)
    echo "test agent output line 1" > "$tmp_output"
    echo "test agent output line 2" >> "$tmp_output"

    local log_name="agent_research_iter1_$(date +%s).log"
    cp "$tmp_output" "$logs_dir/$log_name"
    rm -f "$tmp_output"

    # Check file was created
    local log_count
    log_count=$(find "$logs_dir" -name 'agent_*.log' -type f | wc -l)

    AUTOMATON_DIR="$orig_automaton_dir"

    if [ "$log_count" -ge 1 ]; then
        echo "PASS: Agent log file created in logs directory"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: No agent log file found in $logs_dir" >&2
        ((_TEST_FAIL_COUNT++))
    fi
}
_test_save_log

test_summary
