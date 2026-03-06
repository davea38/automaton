#!/usr/bin/env bash
# tests/test_cleanup_wave.sh — Verify cleanup_wave() behavior
# Tests parallel wave cleanup: worktree removal, archiving, hook cleanup.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"
setup_test_dir

# --- Verify cleanup_wave function structure ---

# Test 1: Function exists
assert_contains "$(grep -c 'cleanup_wave()' "$script_file")" "1" "cleanup_wave() defined exactly once"

# Test 2: Extract function body
fn_body=$(sed -n '/^cleanup_wave()/,/^[a-z_]*().*{/p' "$script_file" | head -50)

# Test 3: Guards against missing assignments file
assert_contains "$fn_body" "assignments_file" "cleanup_wave checks assignments file"
assert_contains "$fn_body" '! -f' "cleanup_wave guards against missing file"

# Test 4: Calls cleanup_worktree for each builder
assert_contains "$fn_body" "cleanup_worktree" "cleanup_wave removes worktrees"

# Test 5: Archives wave data
assert_contains "$fn_body" "wave-history" "cleanup_wave archives to wave-history"
assert_contains "$fn_body" "cp " "cleanup_wave copies assignments for archival"

# Test 6: Clears current wave directory
assert_contains "$fn_body" "rm -rf" "cleanup_wave clears wave results"
assert_contains "$fn_body" "rm -f" "cleanup_wave removes assignments.json"

# Test 7: Cleans up dynamic hooks
assert_contains "$fn_body" "cleanup_wave_hooks" "cleanup_wave removes dynamic hooks"

# Test 8: Kills tmux builder windows
assert_contains "$fn_body" "tmux kill-window" "cleanup_wave kills tmux windows"

# Test 9: Suppresses tmux errors (for non-tmux runs)
assert_contains "$fn_body" "2>/dev/null || true" "cleanup_wave suppresses tmux errors"

test_summary
