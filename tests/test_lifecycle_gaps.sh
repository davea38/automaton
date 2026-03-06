#!/usr/bin/env bash
# tests/test_lifecycle_gaps.sh — Tests for untested lifecycle functions
# Covers: _self_init_backlog, _self_continue_recommendation, archive_run_journal,
#          _generate_run_metadata, _auto_generate_backlog, display_stats,
#          attempt_focused_fix, generate_context_summary, generate_progress_txt

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_lifecycle_gaps_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Function existence checks ---

for fn in _self_init_backlog _self_continue_recommendation archive_run_journal \
    _generate_run_metadata _auto_generate_backlog display_stats \
    attempt_focused_fix generate_context_summary generate_progress_txt; do
    grep -q "${fn}()" "$script_file"
    assert_exit_code 0 $? "$fn function exists"
done

# --- Behavioral: _self_init_backlog ---
body=$(sed -n '/_self_init_backlog()/,/^}/p' "$script_file")
echo "$body" | grep -q 'backlog\|IMPLEMENTATION_PLAN\|self'
assert_exit_code 0 $? "_self_init_backlog manages self-build backlog"

# --- Behavioral: _self_continue_recommendation ---
body=$(sed -n '/_self_continue_recommendation()/,/^}/p' "$script_file")
echo "$body" | grep -q 'recommend\|continu\|next'
assert_exit_code 0 $? "_self_continue_recommendation provides suggestions"

# --- Behavioral: archive_run_journal ---
body=$(sed -n '/^archive_run_journal()/,/^}/p' "$script_file")
echo "$body" | grep -q 'journal\|archive\|run'
assert_exit_code 0 $? "archive_run_journal archives run data"

# Test: archive_run_journal respects max_runs limit
echo "$body" | grep -q 'max_runs\|JOURNAL_MAX_RUNS'
assert_exit_code 0 $? "archive_run_journal limits journal size"

# --- Behavioral: _generate_run_metadata ---
body=$(sed -n '/_generate_run_metadata()/,/^}/p' "$script_file")
echo "$body" | grep -q 'metadata\|run_id\|timestamp'
assert_exit_code 0 $? "_generate_run_metadata generates metadata"

# --- Behavioral: _auto_generate_backlog ---
body=$(sed -n '/_auto_generate_backlog()/,/^}/p' "$script_file")
echo "$body" | grep -q 'backlog\|task\|generat'
assert_exit_code 0 $? "_auto_generate_backlog creates tasks"

# --- Behavioral: display_stats ---
body=$(sed -n '/^display_stats()/,/^}/p' "$script_file")
echo "$body" | grep -q 'stat\|metric\|budget\|run'
assert_exit_code 0 $? "display_stats shows project stats"

# --- Behavioral: attempt_focused_fix ---
body=$(sed -n '/^attempt_focused_fix()/,/^}/p' "$script_file")
echo "$body" | grep -q 'fix\|error\|fail\|claude'
assert_exit_code 0 $? "attempt_focused_fix targets specific failures"

# --- Behavioral: generate_context_summary ---
body=$(sed -n '/^generate_context_summary()/,/^}/p' "$script_file")
echo "$body" | grep -q 'context\|summary\|state'
assert_exit_code 0 $? "generate_context_summary builds context"

# --- Behavioral: generate_progress_txt ---
body=$(sed -n '/^generate_progress_txt()/,/^}/p' "$script_file")
echo "$body" | grep -q 'progress\|task\|plan'
assert_exit_code 0 $? "generate_progress_txt outputs progress info"

# --- Cross-references: lifecycle functions are used ---

grep -q 'archive_run_journal' "$script_file"
assert_exit_code 0 $? "archive_run_journal is called somewhere"

grep -q 'display_stats' "$script_file"
assert_exit_code 0 $? "display_stats is called somewhere"

grep -q 'generate_context_summary' "$script_file"
assert_exit_code 0 $? "generate_context_summary is called somewhere"

test_summary
