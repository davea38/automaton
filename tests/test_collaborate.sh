#!/usr/bin/env bash
# tests/test_collaborate.sh — Tests for spec-61 Collaboration Mode
# Covers: lib/collaborate.sh creation (33.1), checkpoint wiring (33.3),
# educational annotation injection (33.4), and [r]esearch checkpoint option (34.5).
# These tests FAIL initially (no implementation exists yet).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

COLLABORATE_SH="$_PROJECT_DIR/lib/collaborate.sh"

# ============================================================
# 33.1: lib/collaborate.sh exists and has core functions
# ============================================================

# AC-61: lib/collaborate.sh file exists
assert_file_exists "$COLLABORATE_SH" "33.1: lib/collaborate.sh exists"

# AC-61-1: checkpoint() function defined
grep -q '^checkpoint()' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: checkpoint() function defined in lib/collaborate.sh"

# AC-61-3: generate_checkpoint_summary() function defined
grep -q 'generate_checkpoint_summary' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: generate_checkpoint_summary() function defined"

# AC-61-5: handle_modify() function defined
grep -q 'handle_modify' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: handle_modify() function defined"

# AC-61-6: handle_pause() function defined
grep -q 'handle_pause' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: handle_pause() function defined"

# AC-61-7: handle_abort() function defined
grep -q 'handle_abort' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: handle_abort() function defined"

# AC-61-8: TTY check present (autonomous mode bypass)
grep -q 'autonomous' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: autonomous mode bypass present in checkpoint()"

# AC-61-8: TTY detection present
grep -q '\-t 0' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: TTY detection (-t 0) present in checkpoint()"

# AC-61-9: checkpoint audit dir reference
grep -q 'checkpoints' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.1: checkpoint audit directory reference exists"

# Templates: templates/lib/collaborate.sh exists
assert_file_exists "$_PROJECT_DIR/templates/lib/collaborate.sh" \
    "33.1: templates/lib/collaborate.sh exists"

# ============================================================
# 33.3: checkpoint() wired into automaton.sh phase transitions
# ============================================================

# AC-61-1: after_research checkpoint call present
grep -q 'checkpoint.*after_research\|checkpoint "after_research"' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.3: checkpoint 'after_research' called in automaton.sh"

# AC-61-1: after_plan checkpoint call present
grep -q 'checkpoint.*after_plan\|checkpoint "after_plan"' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.3: checkpoint 'after_plan' called in automaton.sh"

# AC-61-1: after_review checkpoint call present
grep -q 'checkpoint.*after_review\|checkpoint "after_review"' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.3: checkpoint 'after_review' called in automaton.sh"

# AC-61: lib/collaborate.sh sourced in automaton.sh
grep -q 'collaborate\.sh' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.3: lib/collaborate.sh sourced in automaton.sh"

# AC-61-6: checkpoint_paused_at resume handling present
grep -q 'checkpoint_paused_at' "$_PROJECT_DIR/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.3: --resume detects checkpoint_paused_at in automaton.sh"

# Templates: automaton.sh template also has checkpoint calls
grep -q 'checkpoint.*after_research\|checkpoint "after_research"' "$_PROJECT_DIR/templates/automaton.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.3: templates/automaton.sh has checkpoint 'after_research'"

# ============================================================
# 33.4: Educational annotation injection in lib/context.sh
# ============================================================

# AC-61-11: COLLABORATION_MODE gate in lib/context.sh
grep -q 'COLLABORATION_MODE' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.4: lib/context.sh references COLLABORATION_MODE"

# AC-61-11: Educational injection for research phase
grep -q 'Why This Matters\|Why this matters' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.4: 'Why This Matters' research annotation injected in context.sh"

# AC-61-11: Educational injection for plan phase (Rationale)
grep -q 'Rationale\|rationale' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.4: Rationale annotation injected for plan phase in context.sh"

# AC-61-11: Educational injection for review phase
grep -q 'Learning Opportunity\|learning opportunity' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.4: 'Learning Opportunity' review annotation injected in context.sh"

# AC-61-11: Annotations absent in autonomous mode (gated on != autonomous)
grep -q 'autonomous' "$_PROJECT_DIR/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.4: autonomous mode bypass present in lib/context.sh annotation injection"

# Templates sync
grep -q 'COLLABORATION_MODE' "$_PROJECT_DIR/templates/lib/context.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.4: templates/lib/context.sh references COLLABORATION_MODE"

# ============================================================
# 34.5: [r]esearch option in after_research checkpoint
# ============================================================

# AC-63-9: [r]esearch option in checkpoint choices
grep -q '\[r\]esearch\|r).*research\|research' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.5: [r]esearch option present in lib/collaborate.sh checkpoint"

# AC-63-9: after_research checkpoint specifically offers [r]esearch
grep -q 'after_research' "$COLLABORATE_SH" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "34.5: after_research checkpoint logic present in lib/collaborate.sh"

test_summary
