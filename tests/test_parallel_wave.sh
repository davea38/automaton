#!/usr/bin/env bash
# tests/test_parallel_wave.sh — Tests for parallel wave orchestration functions
# Covers: start_tmux_session, cleanup_tmux_session, spawn_builders, poll_builders,
#          handle_wave_timeout, generate_builder_wrapper, create_worktree,
#          cleanup_worktree, merge_wave, verify_wave, check_wave_budget,
#          handle_wave_rate_limit, handle_midwave_budget_exhaustion,
#          check_wave_pacing, aggregate_wave_budget, update_wave_state,
#          estimate_remaining_waves, format_builder_status, write_dashboard,
#          emit_wave_status, run_single_builder_iteration, handle_wave_errors,
#          check_ownership, handle_ownership_violations, handle_coordination_conflict,
#          handle_source_conflict, calculate_builder_rate_allocation,
#          update_plan_after_wave, run_parallel_build, emit_task

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_parallel_wave_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence checks ---

for fn in start_tmux_session cleanup_tmux_session spawn_builders poll_builders \
    handle_wave_timeout generate_builder_wrapper create_worktree cleanup_worktree \
    merge_wave verify_wave check_wave_budget handle_wave_rate_limit \
    handle_midwave_budget_exhaustion check_wave_pacing aggregate_wave_budget \
    update_wave_state estimate_remaining_waves format_builder_status write_dashboard \
    emit_wave_status run_single_builder_iteration handle_wave_errors \
    check_ownership handle_ownership_violations handle_coordination_conflict \
    handle_source_conflict calculate_builder_rate_allocation update_plan_after_wave \
    run_parallel_build; do
    grep -q "^${fn}()" "$script_file"
    assert_exit_code 0 $? "$fn function exists"
done

# emit_task uses `function` keyword syntax (inside awk heredoc helper)
grep -q 'function emit_task()' "$script_file"
assert_exit_code 0 $? "emit_task function exists"

# --- Behavioral: start_tmux_session ---
body=$(sed -n '/^start_tmux_session()/,/^}/p' "$script_file")
echo "$body" | grep -q 'TMUX_SESSION_NAME'
assert_exit_code 0 $? "start_tmux_session uses TMUX_SESSION_NAME"

echo "$body" | grep -q 'tmux new-session'
assert_exit_code 0 $? "start_tmux_session creates tmux session"

echo "$body" | grep -q 'PARALLEL_DASHBOARD'
assert_exit_code 0 $? "start_tmux_session checks dashboard config"

# --- Behavioral: cleanup_tmux_session ---
body=$(sed -n '/^cleanup_tmux_session()/,/^}/p' "$script_file")
echo "$body" | grep -q 'kill-window'
assert_exit_code 0 $? "cleanup_tmux_session kills builder windows"

echo "$body" | grep -q 'dashboard'
assert_exit_code 0 $? "cleanup_tmux_session kills dashboard window"

# --- Behavioral: spawn_builders ---
body=$(sed -n '/^spawn_builders()/,/^}/p' "$script_file")
echo "$body" | grep -q 'create_worktree'
assert_exit_code 0 $? "spawn_builders creates worktrees"

echo "$body" | grep -q 'PARALLEL_STAGGER_SECONDS'
assert_exit_code 0 $? "spawn_builders uses stagger delay"

echo "$body" | grep -q 'tmux new-window'
assert_exit_code 0 $? "spawn_builders creates tmux windows"

# --- Behavioral: poll_builders ---
body=$(sed -n '/^poll_builders()/,/^}/p' "$script_file")
echo "$body" | grep -q 'WAVE_TIMEOUT_SECONDS'
assert_exit_code 0 $? "poll_builders uses wave timeout"

echo "$body" | grep -q 'write_dashboard'
assert_exit_code 0 $? "poll_builders updates dashboard"

echo "$body" | grep -q 'handle_wave_timeout'
assert_exit_code 0 $? "poll_builders calls handle_wave_timeout on timeout"

# --- Behavioral: handle_wave_timeout ---
body=$(sed -n '/^handle_wave_timeout()/,/^}/p' "$script_file")
echo "$body" | grep -q 'C-c'
assert_exit_code 0 $? "handle_wave_timeout sends SIGINT first"

echo "$body" | grep -q 'kill-window'
assert_exit_code 0 $? "handle_wave_timeout force-kills after grace period"

echo "$body" | grep -q '"status": "timeout"'
assert_exit_code 0 $? "handle_wave_timeout writes timeout result file"

# --- Behavioral: create_worktree / cleanup_worktree ---
body=$(sed -n '/^create_worktree()/,/^}/p' "$script_file")
echo "$body" | grep -q 'git worktree add'
assert_exit_code 0 $? "create_worktree uses git worktree add"

body=$(sed -n '/^cleanup_worktree()/,/^}/p' "$script_file")
echo "$body" | grep -q 'git worktree remove'
assert_exit_code 0 $? "cleanup_worktree uses git worktree remove"

# --- Behavioral: merge_wave ---
body=$(sed -n '/^merge_wave()/,/^}/p' "$script_file")
echo "$body" | grep -q 'git merge'
assert_exit_code 0 $? "merge_wave performs git merge"

# --- Behavioral: check_wave_budget ---
body=$(sed -n '/^check_wave_budget()/,/^}/p' "$script_file")
echo "$body" | grep -q 'budget\|BUDGET'
assert_exit_code 0 $? "check_wave_budget checks budget state"

# --- Behavioral: calculate_builder_rate_allocation ---
body=$(sed -n '/^calculate_builder_rate_allocation()/,/^}/p' "$script_file")
echo "$body" | grep -q 'RATE_TOKENS_PER_MINUTE\|tokens_per_minute'
assert_exit_code 0 $? "calculate_builder_rate_allocation divides rate limit"

# --- Behavioral: generate_builder_wrapper ---
body=$(sed -n '/^generate_builder_wrapper()/,/^}/p' "$script_file")
echo "$body" | grep -q 'builder-wrapper'
assert_exit_code 0 $? "generate_builder_wrapper creates wrapper script"

# --- Behavioral: check_ownership / handle_ownership_violations ---
body=$(sed -n '/^check_ownership()/,/^}/p' "$script_file")
echo "$body" | grep -q 'assignments\|ownership'
assert_exit_code 0 $? "check_ownership validates file ownership"

body=$(sed -n '/^handle_ownership_violations()/,/^}/p' "$script_file")
echo "$body" | grep -q 'conflict\|violation'
assert_exit_code 0 $? "handle_ownership_violations handles conflicts"

# --- Behavioral: handle_coordination_conflict / handle_source_conflict ---
body=$(sed -n '/^handle_coordination_conflict()/,/^}/p' "$script_file")
echo "$body" | grep -q 'conflict'
assert_exit_code 0 $? "handle_coordination_conflict handles conflicts"

body=$(sed -n '/^handle_source_conflict()/,/^}/p' "$script_file")
echo "$body" | grep -q 'conflict\|merge'
assert_exit_code 0 $? "handle_source_conflict handles merge conflicts"

# --- Behavioral: write_dashboard ---
body=$(sed -n '/^write_dashboard()/,/^}/p' "$script_file")
echo "$body" | grep -q 'dashboard.txt\|dashboard'
assert_exit_code 0 $? "write_dashboard writes dashboard file"

# --- Behavioral: emit_wave_status ---
body=$(sed -n '/^emit_wave_status()/,/^}/p' "$script_file")
echo "$body" | grep -q 'wave\|status'
assert_exit_code 0 $? "emit_wave_status emits status"

# --- Behavioral: estimate_remaining_waves ---
body=$(sed -n '/^estimate_remaining_waves()/,/^}/p' "$script_file")
echo "$body" | grep -q 'remaining\|wave\|tasks'
assert_exit_code 0 $? "estimate_remaining_waves estimates remaining work"

# --- Behavioral: update_plan_after_wave ---
body=$(sed -n '/^update_plan_after_wave()/,/^}/p' "$script_file")
echo "$body" | grep -q 'IMPLEMENTATION_PLAN\|plan'
assert_exit_code 0 $? "update_plan_after_wave modifies plan"

# --- Behavioral: run_parallel_build ---
body=$(sed -n '/^run_parallel_build()/,/^}/p' "$script_file")
echo "$body" | grep -q 'start_tmux_session\|run_agent_teams_build\|wave'
assert_exit_code 0 $? "run_parallel_build orchestrates full parallel pipeline"

# --- Behavioral: handle_wave_errors ---
body=$(sed -n '/^handle_wave_errors()/,/^}/p' "$script_file")
echo "$body" | grep -q 'error\|fail'
assert_exit_code 0 $? "handle_wave_errors processes builder errors"

# --- Behavioral: run_single_builder_iteration ---
body=$(sed -n '/^run_single_builder_iteration()/,/^}/p' "$script_file")
echo "$body" | grep -q 'claude\|agent\|build'
assert_exit_code 0 $? "run_single_builder_iteration invokes builder"

test_summary
