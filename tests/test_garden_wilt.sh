#!/usr/bin/env bash
# tests/test_garden_wilt.sh — Tests for _garden_wilt() (spec-38 §1)
# Verifies that wilting an idea moves it to the wilt stage with a reason,
# records the stage_history entry, and updates the index.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _garden_wilt function exists in automaton.sh ---
grep_result=$(grep -c '^_garden_wilt()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_wilt() function exists in automaton.sh"

# --- Test 2: Function references stage wilt ---
func_body=$(sed -n '/^_garden_wilt()/,/^}/p' "$script_file" || true)
assert_contains "$func_body" "wilt" "function handles wilt stage"

# --- Test 3: Function records reason ---
assert_contains "$func_body" "reason" "function records reason"

# --- Test 4: Function updates stage_history ---
assert_contains "$func_body" "stage_history" "function updates stage_history"

# --- Test 5: Function calls _garden_rebuild_index ---
if echo "$func_body" | grep -q '_garden_rebuild_index'; then
    echo "PASS: function rebuilds the garden index"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should rebuild the garden index after wilting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Functional tests ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":2,"by_stage":{"seed":1,"sprout":1,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":3,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Create a seed idea to wilt
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'IDEAEOF'
{
  "id": "idea-001",
  "title": "Stale seed idea",
  "description": "An idea that will be wilted",
  "stage": "seed",
  "origin": {
    "type": "metric",
    "source": "stall_rate",
    "created_by": "evolve-reflect",
    "created_at": "2026-01-01T00:00:00Z"
  },
  "evidence": [],
  "tags": ["performance"],
  "priority": 5,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-01-01T00:00:00Z", "reason": "Planted as new seed"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-01T00:00:00Z"
}
IDEAEOF

# Create a sprout idea (should not be affected)
cat > "$TMPDIR_TEST/garden/idea-002.json" << 'IDEAEOF'
{
  "id": "idea-002",
  "title": "Active sprout",
  "description": "A sprout that should not be affected",
  "stage": "sprout",
  "origin": {
    "type": "human",
    "source": "manual",
    "created_by": "user",
    "created_at": "2026-01-01T00:00:00Z"
  },
  "evidence": [{"type": "metric", "observation": "test", "added_by": "test", "added_at": "2026-01-02T00:00:00Z"}, {"type": "signal", "observation": "test2", "added_by": "test", "added_at": "2026-01-03T00:00:00Z"}],
  "tags": ["quality"],
  "priority": 20,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-01-01T00:00:00Z", "reason": "Planted"},
    {"stage": "sprout", "entered_at": "2026-01-03T00:00:00Z", "reason": "Threshold met"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-03T00:00:00Z"
}
IDEAEOF

# Extract all needed functions from automaton.sh
rebuild_code=$(sed -n '/^_garden_rebuild_index()/,/^}/p' "$script_file")
wilt_code=$(sed -n '/^_garden_wilt()/,/^}/p' "$script_file")
log_func='log() { :; }'

# --- Test 6: Functional - wilt changes stage to wilt ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$rebuild_code
$wilt_code
_garden_wilt 'idea-001' 'TTL expired: no evidence after 14 days'
" 2>&1) || true

stage=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "wilt" "$stage" "wilting changes stage to wilt"

# --- Test 7: Functional - stage_history records wilt entry ---
history_len=$(jq '.stage_history | length' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "2" "$history_len" "stage_history has wilt entry added"

wilt_stage=$(jq -r '.stage_history[1].stage' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "wilt" "$wilt_stage" "stage_history records wilt stage"

# --- Test 8: Functional - stage_history wilt entry has reason ---
wilt_reason=$(jq -r '.stage_history[1].reason' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "TTL expired: no evidence after 14 days" "$wilt_reason" "stage_history records wilt reason"

# --- Test 9: Functional - updated_at was changed ---
updated=$(jq -r '.updated_at' "$TMPDIR_TEST/garden/idea-001.json")
if [ "$updated" != "2026-01-01T00:00:00Z" ]; then
    echo "PASS: updated_at was changed after wilting"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: updated_at should be updated after wilting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Functional - other ideas not affected ---
other_stage=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-002.json")
assert_equals "sprout" "$other_stage" "other ideas not affected by wilt"

# --- Test 11: Functional - index updated with wilt count ---
wilt_count=$(jq '.by_stage.wilt' "$TMPDIR_TEST/garden/_index.json")
assert_equals "1" "$wilt_count" "index reflects wilt count of 1"

seed_count=$(jq '.by_stage.seed' "$TMPDIR_TEST/garden/_index.json")
assert_equals "0" "$seed_count" "index reflects seed count reduced to 0"

# --- Test 12: Functional - wilting nonexistent idea returns error ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$rebuild_code
$wilt_code
_garden_wilt 'idea-999' 'some reason'
echo \"exit:\$?\"
" 2>&1) || true

if echo "$result" | grep -q 'exit:1\|not found\|does not exist'; then
    echo "PASS: wilting nonexistent idea returns error"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: wilting nonexistent idea should return error (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: Functional - wilting an already-wilted idea still works ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$rebuild_code
$wilt_code
_garden_wilt 'idea-001' 'Double wilt test'
echo \"exit:\$?\"
" 2>&1) || true

history_len=$(jq '.stage_history | length' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "3" "$history_len" "re-wilting adds another stage_history entry"

test_summary
