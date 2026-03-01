#!/usr/bin/env bash
# tests/test_garden_priority.sh — Tests for _garden_recompute_priorities() (spec-38 §2)
# Verifies that priorities are recomputed using the 5-component formula:
# (evidence_weight*30) + (signal_strength*25) + (metric_severity*25) + (age_bonus*10) + (human_boost*10)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _garden_recompute_priorities function exists ---
grep_result=$(grep -c '^_garden_recompute_priorities()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_recompute_priorities() function exists in automaton.sh"

# --- Test 2: Function references the 5-component formula elements ---
func_body=$(sed -n '/^_garden_recompute_priorities()/,/^}/p' "$script_file")
assert_contains "$func_body" "evidence_weight" "function computes evidence_weight"
assert_contains "$func_body" "signal_strength" "function computes signal_strength"
assert_contains "$func_body" "metric_severity" "function computes metric_severity"
assert_contains "$func_body" "age_bonus" "function computes age_bonus"
assert_contains "$func_body" "human_boost" "function computes human_boost"

# --- Functional tests ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":3,"by_stage":{"seed":1,"sprout":1,"bloom":0,"harvest":0,"wilt":1},"bloom_candidates":[],"recent_activity":[],"next_id":4,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Idea 1: seed with 1 evidence, metric origin, old (30 days ago)
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'EOF'
{
  "id": "idea-001",
  "title": "Old metric seed",
  "description": "A seed with metric origin",
  "stage": "seed",
  "origin": {
    "type": "metric",
    "source": "stall_rate > 0.25",
    "created_by": "evolve-reflect",
    "created_at": "2026-01-01T00:00:00Z"
  },
  "evidence": [
    {"type": "metric", "observation": "Stall rate 25%", "added_by": "reflect", "added_at": "2026-01-15T00:00:00Z"}
  ],
  "tags": ["performance"],
  "priority": 0,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-01-01T00:00:00Z", "reason": "Planted"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-15T00:00:00Z"
}
EOF

# Idea 2: sprout with 3 evidence, human origin
cat > "$TMPDIR_TEST/garden/idea-002.json" << 'EOF'
{
  "id": "idea-002",
  "title": "Human sprout",
  "description": "A human-planted sprout with lots of evidence",
  "stage": "sprout",
  "origin": {
    "type": "human",
    "source": "manual entry",
    "created_by": "user",
    "created_at": "2026-02-15T00:00:00Z"
  },
  "evidence": [
    {"type": "metric", "observation": "obs1", "added_by": "reflect", "added_at": "2026-02-16T00:00:00Z"},
    {"type": "signal", "observation": "obs2", "added_by": "ideate", "added_at": "2026-02-17T00:00:00Z"},
    {"type": "metric", "observation": "obs3", "added_by": "reflect", "added_at": "2026-02-18T00:00:00Z"}
  ],
  "tags": ["quality"],
  "priority": 0,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-15T00:00:00Z", "reason": "Planted"},
    {"stage": "sprout", "entered_at": "2026-02-17T00:00:00Z", "reason": "Threshold met"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-18T00:00:00Z"
}
EOF

# Idea 3: wilted - should be skipped
cat > "$TMPDIR_TEST/garden/idea-003.json" << 'EOF'
{
  "id": "idea-003",
  "title": "Wilted idea",
  "description": "Should not have priority recomputed",
  "stage": "wilt",
  "origin": {
    "type": "metric",
    "source": "some metric",
    "created_by": "reflect",
    "created_at": "2026-01-01T00:00:00Z"
  },
  "evidence": [
    {"type": "metric", "observation": "obs", "added_by": "reflect", "added_at": "2026-01-02T00:00:00Z"}
  ],
  "tags": [],
  "priority": 50,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-01-01T00:00:00Z", "reason": "Planted"},
    {"stage": "wilt", "entered_at": "2026-01-10T00:00:00Z", "reason": "Expired"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-10T00:00:00Z"
}
EOF

# Extract function code
recompute_code=$(sed -n '/^_garden_recompute_priorities()/,/^}/p' "$script_file")
rebuild_code=$(sed -n '/^_garden_rebuild_index()/,/^}/p' "$script_file")
log_func='log() { :; }'

# --- Test 7: Functional - recompute sets priority > 0 for active ideas ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_BLOOM_THRESHOLD=3
$rebuild_code
$recompute_code
_garden_recompute_priorities
" 2>&1) || true

p1=$(jq '.priority' "$TMPDIR_TEST/garden/idea-001.json")
if [ "$p1" -gt 0 ] 2>/dev/null; then
    echo "PASS: idea-001 (seed) has priority > 0 after recompute ($p1)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: idea-001 should have priority > 0 after recompute (got $p1)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Functional - human-origin idea gets human_boost ---
p2=$(jq '.priority' "$TMPDIR_TEST/garden/idea-002.json")
if [ "$p2" -gt "$p1" ] 2>/dev/null; then
    echo "PASS: idea-002 (human, 3 evidence) has higher priority ($p2) than idea-001 ($p1)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: idea-002 should have higher priority than idea-001 (got $p2 vs $p1)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Functional - wilted idea is not recomputed ---
p3=$(jq '.priority' "$TMPDIR_TEST/garden/idea-003.json")
assert_equals "50" "$p3" "wilted idea-003 priority unchanged (still 50)"

# --- Test 10: Functional - priority is an integer in range 0-100 ---
if [ "$p2" -ge 0 ] && [ "$p2" -le 100 ] 2>/dev/null; then
    echo "PASS: idea-002 priority ($p2) is in range 0-100"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: priority should be 0-100 (got $p2)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Functional - verify evidence_weight component ---
# idea-002 has 3 evidence items, bloom_threshold=3, so evidence_weight=1.0 -> contributes 30 points
# idea-001 has 1 evidence item, so evidence_weight=1/3=0.33 -> contributes ~10 points
# The difference should reflect the evidence weight component
evidence_diff=$((p2 - p1))
if [ "$evidence_diff" -gt 0 ] 2>/dev/null; then
    echo "PASS: more evidence leads to higher priority (diff=$evidence_diff)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: more evidence should increase priority (diff=$evidence_diff)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Functional - human_boost gives exactly 10 points ---
# Create two identical ideas, one human-origin and one agent-origin (no metric_severity), fresh (age=0)
cat > "$TMPDIR_TEST/garden/idea-004.json" << EOF
{
  "id": "idea-004",
  "title": "Agent idea fresh",
  "description": "Fresh agent idea",
  "stage": "seed",
  "origin": {"type": "agent", "source": "test", "created_by": "test", "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"},
  "evidence": [],
  "tags": [],
  "priority": 0,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [{"stage": "seed", "entered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "reason": "test"}],
  "vote_id": null,
  "implementation": null,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

cat > "$TMPDIR_TEST/garden/idea-005.json" << EOF
{
  "id": "idea-005",
  "title": "Human idea fresh",
  "description": "Fresh human idea",
  "stage": "seed",
  "origin": {"type": "human", "source": "test", "created_by": "test", "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"},
  "evidence": [],
  "tags": [],
  "priority": 0,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [{"stage": "seed", "entered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "reason": "test"}],
  "vote_id": null,
  "implementation": null,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_BLOOM_THRESHOLD=3
$rebuild_code
$recompute_code
_garden_recompute_priorities
" 2>&1) || true

p4=$(jq '.priority' "$TMPDIR_TEST/garden/idea-004.json")
p5=$(jq '.priority' "$TMPDIR_TEST/garden/idea-005.json")
human_diff=$((p5 - p4))
assert_equals "10" "$human_diff" "human_boost contributes exactly 10 points (agent=$p4, human=$p5)"

test_summary
