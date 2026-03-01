#!/usr/bin/env bash
# tests/test_garden_prune.sh — Tests for _garden_prune_expired() (spec-38 §2)
# Verifies that auto-wilting seeds older than seed_ttl_days and sprouts older
# than sprout_ttl_days that have received no new evidence.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _garden_prune_expired function exists in automaton.sh ---
grep_result=$(grep -c '^_garden_prune_expired()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_prune_expired() function exists in automaton.sh"

# --- Test 2: Function references seed_ttl ---
func_body=$(sed -n '/^_garden_prune_expired()/,/^}/p' "$script_file" || true)
assert_contains "$func_body" "SEED_TTL" "function references SEED_TTL"

# --- Test 3: Function references sprout_ttl ---
assert_contains "$func_body" "SPROUT_TTL" "function references SPROUT_TTL"

# --- Test 4: Function calls _garden_wilt ---
assert_contains "$func_body" "_garden_wilt" "function calls _garden_wilt to expire ideas"

# --- Functional tests ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":5,"by_stage":{"seed":2,"sprout":2,"bloom":1,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":6,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Idea 1: old seed with NO evidence, should be pruned (older than 14 days)
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'IDEAEOF'
{
  "id": "idea-001",
  "title": "Stale seed - should be pruned",
  "description": "A seed that is older than seed_ttl_days with no evidence",
  "stage": "seed",
  "origin": {
    "type": "metric",
    "source": "stall_rate",
    "created_by": "evolve-reflect",
    "created_at": "2025-01-01T00:00:00Z"
  },
  "evidence": [],
  "tags": ["performance"],
  "priority": 5,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2025-01-01T00:00:00Z", "reason": "Planted as new seed"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2025-01-01T00:00:00Z"
}
IDEAEOF

# Idea 2: recent seed, should NOT be pruned (within seed_ttl_days)
cat > "$TMPDIR_TEST/garden/idea-002.json" << 'IDEAEOF'
{
  "id": "idea-002",
  "title": "Fresh seed - should survive",
  "description": "A seed created recently",
  "stage": "seed",
  "origin": {
    "type": "human",
    "source": "manual",
    "created_by": "user",
    "created_at": "2026-02-28T00:00:00Z"
  },
  "evidence": [],
  "tags": ["quality"],
  "priority": 10,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-28T00:00:00Z", "reason": "Planted as new seed"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-28T00:00:00Z"
}
IDEAEOF

# Idea 3: old sprout with no recent evidence, should be pruned (older than 30 days)
cat > "$TMPDIR_TEST/garden/idea-003.json" << 'IDEAEOF'
{
  "id": "idea-003",
  "title": "Stale sprout - should be pruned",
  "description": "A sprout that has not received evidence for more than sprout_ttl_days",
  "stage": "sprout",
  "origin": {
    "type": "metric",
    "source": "token_efficiency",
    "created_by": "evolve-reflect",
    "created_at": "2025-01-01T00:00:00Z"
  },
  "evidence": [
    {"type": "metric", "observation": "old evidence", "added_by": "test", "added_at": "2025-01-05T00:00:00Z"},
    {"type": "signal", "observation": "old evidence 2", "added_by": "test", "added_at": "2025-01-10T00:00:00Z"}
  ],
  "tags": ["performance"],
  "priority": 20,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2025-01-01T00:00:00Z", "reason": "Planted"},
    {"stage": "sprout", "entered_at": "2025-01-10T00:00:00Z", "reason": "Threshold met"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2025-01-10T00:00:00Z"
}
IDEAEOF

# Idea 4: sprout with recent evidence, should NOT be pruned
cat > "$TMPDIR_TEST/garden/idea-004.json" << 'IDEAEOF'
{
  "id": "idea-004",
  "title": "Active sprout - should survive",
  "description": "A sprout with recent evidence",
  "stage": "sprout",
  "origin": {
    "type": "human",
    "source": "manual",
    "created_by": "user",
    "created_at": "2025-06-01T00:00:00Z"
  },
  "evidence": [
    {"type": "metric", "observation": "evidence 1", "added_by": "test", "added_at": "2025-06-05T00:00:00Z"},
    {"type": "signal", "observation": "recent evidence", "added_by": "test", "added_at": "2026-02-28T00:00:00Z"}
  ],
  "tags": ["quality"],
  "priority": 25,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2025-06-01T00:00:00Z", "reason": "Planted"},
    {"stage": "sprout", "entered_at": "2025-06-05T00:00:00Z", "reason": "Threshold met"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-28T00:00:00Z"
}
IDEAEOF

# Idea 5: bloom stage, should NOT be pruned (TTL only applies to seeds and sprouts)
cat > "$TMPDIR_TEST/garden/idea-005.json" << 'IDEAEOF'
{
  "id": "idea-005",
  "title": "Bloom idea - immune to pruning",
  "description": "A bloom should not be affected by TTL pruning",
  "stage": "bloom",
  "origin": {
    "type": "metric",
    "source": "test_pass_rate",
    "created_by": "evolve-reflect",
    "created_at": "2025-01-01T00:00:00Z"
  },
  "evidence": [
    {"type": "metric", "observation": "ev1", "added_by": "test", "added_at": "2025-01-02T00:00:00Z"},
    {"type": "signal", "observation": "ev2", "added_by": "test", "added_at": "2025-01-03T00:00:00Z"},
    {"type": "review", "observation": "ev3", "added_by": "test", "added_at": "2025-01-04T00:00:00Z"}
  ],
  "tags": ["quality"],
  "priority": 60,
  "estimated_complexity": "high",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2025-01-01T00:00:00Z", "reason": "Planted"},
    {"stage": "sprout", "entered_at": "2025-01-03T00:00:00Z", "reason": "Threshold met"},
    {"stage": "bloom", "entered_at": "2025-01-04T00:00:00Z", "reason": "Ready for evaluation"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2025-01-04T00:00:00Z"
}
IDEAEOF

# Extract needed functions from automaton.sh
rebuild_code=$(sed -n '/^_garden_rebuild_index()/,/^}/p' "$script_file")
wilt_code=$(sed -n '/^_garden_wilt()/,/^}/p' "$script_file")
prune_code=$(sed -n '/^_garden_prune_expired()/,/^}/p' "$script_file")
log_func='log() { :; }'

# --- Test 5: Functional - prune wilts stale seed ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_SEED_TTL_DAYS=14
GARDEN_SPROUT_TTL_DAYS=30
$rebuild_code
$wilt_code
$prune_code
_garden_prune_expired
" 2>&1) || true

stage_001=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-001.json")
assert_equals "wilt" "$stage_001" "stale seed (idea-001) was wilted"

# --- Test 6: Functional - fresh seed survives pruning ---
stage_002=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-002.json")
assert_equals "seed" "$stage_002" "fresh seed (idea-002) survives pruning"

# --- Test 7: Functional - stale sprout was wilted ---
stage_003=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-003.json")
assert_equals "wilt" "$stage_003" "stale sprout (idea-003) was wilted"

# --- Test 8: Functional - sprout with recent evidence survives ---
stage_004=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-004.json")
assert_equals "sprout" "$stage_004" "sprout with recent evidence (idea-004) survives pruning"

# --- Test 9: Functional - bloom is immune to pruning ---
stage_005=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-005.json")
assert_equals "bloom" "$stage_005" "bloom (idea-005) is immune to TTL pruning"

# --- Test 10: Functional - wilted seed has TTL reason in stage_history ---
reason_001=$(jq -r '.stage_history[-1].reason' "$TMPDIR_TEST/garden/idea-001.json")
if echo "$reason_001" | grep -qi 'ttl\|expired\|stale\|prune'; then
    echo "PASS: wilted seed has TTL-related reason in stage_history"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: wilted seed should have TTL-related reason (got: $reason_001)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Functional - wilted sprout has TTL reason in stage_history ---
reason_003=$(jq -r '.stage_history[-1].reason' "$TMPDIR_TEST/garden/idea-003.json")
if echo "$reason_003" | grep -qi 'ttl\|expired\|stale\|prune'; then
    echo "PASS: wilted sprout has TTL-related reason in stage_history"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: wilted sprout should have TTL-related reason (got: $reason_003)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Functional - index updated after pruning ---
wilt_count=$(jq '.by_stage.wilt' "$TMPDIR_TEST/garden/_index.json")
assert_equals "2" "$wilt_count" "index reflects 2 wilted ideas after pruning"

# --- Test 13: Functional - prune on empty garden does not error ---
TMPDIR_EMPTY=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST" "$TMPDIR_EMPTY"' EXIT
mkdir -p "$TMPDIR_EMPTY/garden"
cat > "$TMPDIR_EMPTY/garden/_index.json" << 'INDEXEOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_EMPTY'
GARDEN_SEED_TTL_DAYS=14
GARDEN_SPROUT_TTL_DAYS=30
$rebuild_code
$wilt_code
$prune_code
_garden_prune_expired
echo 'exit:'\$?
" 2>&1) || true

if echo "$result" | grep -q 'exit:0'; then
    echo "PASS: prune on empty garden succeeds without error"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: prune on empty garden should succeed (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
