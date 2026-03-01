#!/usr/bin/env bash
# tests/test_cli_args.sh — Tests for spec-44 §44.1 argument parsing
# Verifies that all 15 new CLI flags are correctly parsed with their
# variable defaults, case branches, and argument handling.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Variable defaults (ARG_ declarations)
# ============================================================

# --evolve and --cycles already tested in test_evolve_cli.sh; verify new ones

# --- Test 1: ARG_PLANT defaults to empty ---
grep_result=$(grep -c '^ARG_PLANT=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_PLANT defaults to empty string"

# --- Test 2: ARG_GARDEN defaults to false ---
grep_result=$(grep -c '^ARG_GARDEN=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_GARDEN defaults to false"

# --- Test 3: ARG_GARDEN_DETAIL defaults to empty ---
grep_result=$(grep -c '^ARG_GARDEN_DETAIL=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_GARDEN_DETAIL defaults to empty string"

# --- Test 4: ARG_WATER_ID defaults to empty ---
grep_result=$(grep -c '^ARG_WATER_ID=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_WATER_ID defaults to empty string"

# --- Test 5: ARG_WATER_EVIDENCE defaults to empty ---
grep_result=$(grep -c '^ARG_WATER_EVIDENCE=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_WATER_EVIDENCE defaults to empty string"

# --- Test 6: ARG_PRUNE_ID defaults to empty ---
grep_result=$(grep -c '^ARG_PRUNE_ID=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_PRUNE_ID defaults to empty string"

# --- Test 7: ARG_PRUNE_REASON defaults to empty ---
grep_result=$(grep -c '^ARG_PRUNE_REASON=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_PRUNE_REASON defaults to empty string"

# --- Test 8: ARG_PROMOTE defaults to empty ---
grep_result=$(grep -c '^ARG_PROMOTE=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_PROMOTE defaults to empty string"

# --- Test 9: ARG_INSPECT defaults to empty ---
grep_result=$(grep -c '^ARG_INSPECT=""' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_INSPECT defaults to empty string"

# --- Test 10: ARG_CONSTITUTION defaults to false ---
grep_result=$(grep -c '^ARG_CONSTITUTION=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_CONSTITUTION defaults to false"

# --- Test 11: ARG_AMEND defaults to false ---
grep_result=$(grep -c '^ARG_AMEND=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_AMEND defaults to false"

# --- Test 12: ARG_OVERRIDE defaults to false ---
grep_result=$(grep -c '^ARG_OVERRIDE=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_OVERRIDE defaults to false"

# --- Test 13: ARG_PAUSE_EVOLUTION defaults to false ---
grep_result=$(grep -c '^ARG_PAUSE_EVOLUTION=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_PAUSE_EVOLUTION defaults to false"

# --- Test 14: ARG_SIGNALS defaults to false ---
grep_result=$(grep -c '^ARG_SIGNALS=false' "$script_file" || true)
assert_equals "1" "$grep_result" "ARG_SIGNALS defaults to false"

# ============================================================
# Case branches in argument parser
# ============================================================

# --- Test 15: --plant case exists ---
grep_result=$(grep -c '^\s*--plant)' "$script_file" || true)
assert_equals "1" "$grep_result" "--plant case exists in argument parser"

# --- Test 16: --plant sets ARG_PLANT from $2 ---
grep_result=$(grep -A3 '^\s*--plant)' "$script_file" | grep -c 'ARG_PLANT=' || true)
assert_equals "1" "$grep_result" "--plant sets ARG_PLANT"

# --- Test 17: --garden case exists ---
grep_result=$(grep -c '^\s*--garden)' "$script_file" || true)
assert_equals "1" "$grep_result" "--garden case exists in argument parser"

# --- Test 18: --garden sets ARG_GARDEN=true ---
grep_result=$(grep -A3 '^\s*--garden)' "$script_file" | grep -c 'ARG_GARDEN=true' || true)
assert_equals "1" "$grep_result" "--garden sets ARG_GARDEN=true"

# --- Test 19: --garden-detail case exists ---
grep_result=$(grep -c '^\s*--garden-detail)' "$script_file" || true)
assert_equals "1" "$grep_result" "--garden-detail case exists in argument parser"

# --- Test 20: --garden-detail sets ARG_GARDEN_DETAIL from $2 ---
grep_result=$(grep -A3 '^\s*--garden-detail)' "$script_file" | grep -c 'ARG_GARDEN_DETAIL=' || true)
assert_equals "1" "$grep_result" "--garden-detail sets ARG_GARDEN_DETAIL"

# --- Test 21: --water case exists ---
grep_result=$(grep -c '^\s*--water)' "$script_file" || true)
assert_equals "1" "$grep_result" "--water case exists in argument parser"

# --- Test 22: --water sets ARG_WATER_ID ---
grep_result=$(grep -A3 '^\s*--water)' "$script_file" | grep -c 'ARG_WATER_ID=' || true)
assert_equals "1" "$grep_result" "--water sets ARG_WATER_ID"

# --- Test 23: --water sets ARG_WATER_EVIDENCE ---
grep_result=$(grep -A5 '^\s*--water)' "$script_file" | grep -c 'ARG_WATER_EVIDENCE=' || true)
assert_equals "1" "$grep_result" "--water sets ARG_WATER_EVIDENCE"

# --- Test 24: --prune case exists ---
grep_result=$(grep -c '^\s*--prune)' "$script_file" || true)
assert_equals "1" "$grep_result" "--prune case exists in argument parser"

# --- Test 25: --prune sets ARG_PRUNE_ID ---
grep_result=$(grep -A3 '^\s*--prune)' "$script_file" | grep -c 'ARG_PRUNE_ID=' || true)
assert_equals "1" "$grep_result" "--prune sets ARG_PRUNE_ID"

# --- Test 26: --prune sets ARG_PRUNE_REASON ---
grep_result=$(grep -A5 '^\s*--prune)' "$script_file" | grep -c 'ARG_PRUNE_REASON=' || true)
assert_equals "1" "$grep_result" "--prune sets ARG_PRUNE_REASON"

# --- Test 27: --promote case exists ---
grep_result=$(grep -c '^\s*--promote)' "$script_file" || true)
assert_equals "1" "$grep_result" "--promote case exists in argument parser"

# --- Test 28: --promote sets ARG_PROMOTE from $2 ---
grep_result=$(grep -A3 '^\s*--promote)' "$script_file" | grep -c 'ARG_PROMOTE=' || true)
assert_equals "1" "$grep_result" "--promote sets ARG_PROMOTE"

# --- Test 29: --inspect case exists ---
grep_result=$(grep -c '^\s*--inspect)' "$script_file" || true)
assert_equals "1" "$grep_result" "--inspect case exists in argument parser"

# --- Test 30: --inspect sets ARG_INSPECT from $2 ---
grep_result=$(grep -A3 '^\s*--inspect)' "$script_file" | grep -c 'ARG_INSPECT=' || true)
assert_equals "1" "$grep_result" "--inspect sets ARG_INSPECT"

# --- Test 31: --constitution case exists ---
grep_result=$(grep -c '^\s*--constitution)' "$script_file" || true)
assert_equals "1" "$grep_result" "--constitution case exists in argument parser"

# --- Test 32: --constitution sets ARG_CONSTITUTION=true ---
grep_result=$(grep -A3 '^\s*--constitution)' "$script_file" | grep -c 'ARG_CONSTITUTION=true' || true)
assert_equals "1" "$grep_result" "--constitution sets ARG_CONSTITUTION=true"

# --- Test 33: --amend case exists ---
grep_result=$(grep -c '^\s*--amend)' "$script_file" || true)
assert_equals "1" "$grep_result" "--amend case exists in argument parser"

# --- Test 34: --amend sets ARG_AMEND=true ---
grep_result=$(grep -A3 '^\s*--amend)' "$script_file" | grep -c 'ARG_AMEND=true' || true)
assert_equals "1" "$grep_result" "--amend sets ARG_AMEND=true"

# --- Test 35: --override case exists ---
grep_result=$(grep -c '^\s*--override)' "$script_file" || true)
assert_equals "1" "$grep_result" "--override case exists in argument parser"

# --- Test 36: --override sets ARG_OVERRIDE=true ---
grep_result=$(grep -A3 '^\s*--override)' "$script_file" | grep -c 'ARG_OVERRIDE=true' || true)
assert_equals "1" "$grep_result" "--override sets ARG_OVERRIDE=true"

# --- Test 37: --pause-evolution case exists ---
grep_result=$(grep -c '^\s*--pause-evolution)' "$script_file" || true)
assert_equals "1" "$grep_result" "--pause-evolution case exists in argument parser"

# --- Test 38: --pause-evolution sets ARG_PAUSE_EVOLUTION=true ---
grep_result=$(grep -A3 '^\s*--pause-evolution)' "$script_file" | grep -c 'ARG_PAUSE_EVOLUTION=true' || true)
assert_equals "1" "$grep_result" "--pause-evolution sets ARG_PAUSE_EVOLUTION=true"

# --- Test 39: --signals case exists ---
grep_result=$(grep -c '^\s*--signals)' "$script_file" || true)
assert_equals "1" "$grep_result" "--signals case exists in argument parser"

# --- Test 40: --signals sets ARG_SIGNALS=true ---
grep_result=$(grep -A3 '^\s*--signals)' "$script_file" | grep -c 'ARG_SIGNALS=true' || true)
assert_equals "1" "$grep_result" "--signals sets ARG_SIGNALS=true"

# ============================================================
# Help text includes new commands
# ============================================================

# --- Test 41: Help text includes --plant ---
grep_result=$(grep -c '\-\-plant' "$script_file" || true)
[ "$grep_result" -ge 2 ] && has_plant="1" || has_plant="0"
assert_equals "1" "$has_plant" "Help text mentions --plant"

# --- Test 42: Help text includes --garden ---
grep_result=$(grep -c '\-\-garden ' "$script_file" || true)
[ "$grep_result" -ge 2 ] && has_garden="1" || has_garden="0"
assert_equals "1" "$has_garden" "Help text mentions --garden"

# --- Test 43: Help text includes --signals ---
grep_result=$(grep -c '\-\-signals' "$script_file" || true)
[ "$grep_result" -ge 2 ] && has_signals="1" || has_signals="0"
assert_equals "1" "$has_signals" "Help text mentions --signals"

# --- Test 44: Help text includes --constitution ---
grep_result=$(grep -c '\-\-constitution' "$script_file" || true)
[ "$grep_result" -ge 2 ] && has_constitution="1" || has_constitution="0"
assert_equals "1" "$has_constitution" "Help text mentions --constitution"

# --- Test 45: Help text includes --pause-evolution ---
grep_result=$(grep -c '\-\-pause-evolution' "$script_file" || true)
[ "$grep_result" -ge 2 ] && has_pause="1" || has_pause="0"
assert_equals "1" "$has_pause" "Help text mentions --pause-evolution"

# ============================================================
# No duplicate flag conflicts
# ============================================================

# --- Test 46: No duplicate --plant case (only one definition) ---
grep_result=$(grep -c '^\s*--plant)' "$script_file" || true)
assert_equals "1" "$grep_result" "Only one --plant case branch (no conflict)"

# --- Test 47: No duplicate --garden case (only one definition) ---
grep_result=$(grep -c '^\s*--garden)' "$script_file" || true)
assert_equals "1" "$grep_result" "Only one --garden case branch (no conflict)"

test_summary
