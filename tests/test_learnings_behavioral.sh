#!/usr/bin/env bash
# tests/test_learnings_behavioral.sh — Behavioral tests for learning CRUD functions
# Covers add_learning, update_learning, deactivate_learning, count_active_learnings.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

setup_test_dir
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

log() { :; }
current_phase="build"

source "$_PROJECT_DIR/lib/lifecycle.sh"

# --- Test 1: add_learning creates learnings.json ---
add_learning "convention" "Use set -euo pipefail" "Prevents silent failures" "high"
assert_file_exists "$AUTOMATON_DIR/learnings.json" "learnings.json created by add_learning"

# --- Test 2: added learning is valid JSON ---
result=$(cat "$AUTOMATON_DIR/learnings.json")
assert_json_valid "$result" "learnings.json is valid JSON"

# --- Test 3: learning has correct category (structure: {entries: [...]}) ---
cat_val=$(echo "$result" | jq -r '.entries[0].category')
assert_equals "convention" "$cat_val" "learning has correct category"

# --- Test 4: learning has correct summary ---
sum_val=$(echo "$result" | jq -r '.entries[0].summary')
assert_equals "Use set -euo pipefail" "$sum_val" "learning has correct summary"

# --- Test 5: learning has correct confidence ---
conf_val=$(echo "$result" | jq -r '.entries[0].confidence')
assert_equals "high" "$conf_val" "learning has correct confidence"

# --- Test 6: learning is active ---
active_val=$(echo "$result" | jq -r '.entries[0].active')
assert_equals "true" "$active_val" "learning is active by default"

# --- Test 7: count_active_learnings returns 1 ---
count=$(count_active_learnings)
assert_equals "1" "$count" "count_active_learnings returns 1"

# --- Test 8: add second learning ---
add_learning "debugging" "Check stderr for jq errors" "" "medium"
count=$(count_active_learnings)
assert_equals "2" "$count" "count_active_learnings returns 2 after adding"

# --- Test 9: update_learning changes summary ---
id=$(jq -r '.entries[0].id' "$AUTOMATON_DIR/learnings.json")
update_learning "$id" "summary" "Always use set -euo pipefail"
updated_sum=$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .summary' "$AUTOMATON_DIR/learnings.json")
assert_equals "Always use set -euo pipefail" "$updated_sum" "update_learning changes summary"

# --- Test 10: update_learning changes confidence ---
update_learning "$id" "confidence" "low"
updated_conf=$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .confidence' "$AUTOMATON_DIR/learnings.json")
assert_equals "low" "$updated_conf" "update_learning changes confidence"

# --- Test 11: update_learning rejects invalid field ---
if update_learning "$id" "invalid_field" "value" 2>/dev/null; then
    echo "FAIL: update_learning should reject invalid field" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: update_learning rejects invalid field"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 12: deactivate_learning sets active=false ---
deactivate_learning "$id" "no longer relevant"
active_val=$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .active' "$AUTOMATON_DIR/learnings.json")
assert_equals "false" "$active_val" "deactivate_learning sets active=false"

# --- Test 13: count_active_learnings decreases ---
count=$(count_active_learnings)
assert_equals "1" "$count" "count_active_learnings returns 1 after deactivation"

# --- Test 14: deactivate nonexistent learning returns error ---
if deactivate_learning "nonexistent-id" 2>/dev/null; then
    echo "FAIL: deactivate_learning should fail for nonexistent ID" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: deactivate_learning fails for nonexistent ID"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 15: count_active_learnings returns 0 for missing file ---
rm -f "$AUTOMATON_DIR/learnings.json"
count=$(count_active_learnings)
assert_equals "0" "$count" "count_active_learnings returns 0 for missing file"

test_summary
