#!/usr/bin/env bash
# tests/test_garden_water.sh — Tests for _garden_water() (spec-38 §1)
# Verifies that watering an idea adds evidence, updates updated_at,
# and calls _garden_advance_stage() when thresholds are met.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _garden_water function exists in automaton.sh ---
grep_result=$(grep -c '^_garden_water()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_water() function exists in automaton.sh"

# --- Test 2: Function references evidence ---
func_body=$(grep -A 60 '^_garden_water()' "$script_file" || true)
assert_contains "$func_body" "evidence" "function handles evidence"

# --- Test 3: Function updates updated_at ---
assert_contains "$func_body" "updated_at" "function updates updated_at"

# --- Test 4: Function calls _garden_advance_stage or checks thresholds ---
if echo "$func_body" | grep -q '_garden_advance_stage\|sprout_threshold\|GARDEN_SPROUT_THRESHOLD'; then
    echo "PASS: function triggers stage advancement check"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should call _garden_advance_stage or check thresholds" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Function calls _garden_rebuild_index ---
if echo "$func_body" | grep -q '_garden_rebuild_index'; then
    echo "PASS: function rebuilds the garden index"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should rebuild the garden index after watering" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Functional tests ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":1,"by_stage":{"seed":1,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":2,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Create a seed idea to water
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'IDEAEOF'
{
  "id": "idea-001",
  "title": "Test idea",
  "description": "An idea for testing",
  "stage": "seed",
  "origin": {
    "type": "human",
    "source": "manual entry",
    "created_by": "test-user",
    "created_at": "2026-01-01T00:00:00Z"
  },
  "evidence": [],
  "tags": ["testing"],
  "priority": 0,
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

# Extract all needed functions from automaton.sh
rebuild_code=$(sed -n '/^_garden_rebuild_index()/,/^}/p' "$script_file")
plant_code=$(sed -n '/^_garden_plant_seed()/,/^}/p' "$script_file")
water_code=$(sed -n '/^_garden_water()/,/^}/p' "$script_file")
advance_code=$(sed -n '/^_garden_advance_stage()/,/^}/p' "$script_file")
log_func='log() { :; }'

# --- Test 6: Functional - water adds an evidence item ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_SPROUT_THRESHOLD=2
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=40
$rebuild_code
$advance_code
$water_code
_garden_water 'idea-001' 'metric' 'Stall rate is 25%' 'evolve-reflect'
" 2>&1) || true

evidence_count=$(jq '.evidence | length' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "1" "$evidence_count" "watering adds one evidence item"

# --- Test 7: Functional - evidence has correct type ---
ev_type=$(jq -r '.evidence[0].type' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "metric" "$ev_type" "evidence item has correct type"

# --- Test 8: Functional - evidence has correct observation ---
ev_obs=$(jq -r '.evidence[0].observation' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "Stall rate is 25%" "$ev_obs" "evidence item has correct observation"

# --- Test 9: Functional - evidence has added_by ---
ev_by=$(jq -r '.evidence[0].added_by' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "evolve-reflect" "$ev_by" "evidence item has correct added_by"

# --- Test 10: Functional - updated_at was changed ---
updated=$(jq -r '.updated_at' "$TMPDIR_TEST/garden/idea-001.json")
if [ "$updated" != "2026-01-01T00:00:00Z" ]; then
    echo "PASS: updated_at was changed from original"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: updated_at should be updated after watering" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Functional - stage still seed (threshold=2, only 1 evidence) ---
stage=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "seed" "$stage" "stage remains seed with insufficient evidence"

# --- Test 12: Functional - second watering triggers sprout transition ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_SPROUT_THRESHOLD=2
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=40
$rebuild_code
$advance_code
$water_code
_garden_water 'idea-001' 'signal' 'Strong signal SIG-001 observed' 'evolve-ideate'
" 2>&1) || true

evidence_count=$(jq '.evidence | length' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "2" "$evidence_count" "second watering adds second evidence item"

stage=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "sprout" "$stage" "stage advances to sprout at threshold=2"

# --- Test 13: Functional - stage_history records sprout transition ---
history_len=$(jq '.stage_history | length' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "2" "$history_len" "stage_history has entry for sprout transition"

sprout_stage=$(jq -r '.stage_history[1].stage' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "sprout" "$sprout_stage" "stage_history[1] records sprout transition"

# --- Test 14: Functional - watering nonexistent idea returns error ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_SPROUT_THRESHOLD=2
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=40
$rebuild_code
$advance_code
$water_code
_garden_water 'idea-999' 'metric' 'some observation' 'test'
echo \"exit:\$?\"
" 2>&1) || true

if echo "$result" | grep -q 'exit:1\|not found\|does not exist'; then
    echo "PASS: watering nonexistent idea returns error"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: watering nonexistent idea should return error (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
