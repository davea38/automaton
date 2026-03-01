#!/usr/bin/env bash
# tests/test_cli_promote.sh — Tests for spec-44 §44.3 _cli_promote()
# Verifies that _cli_promote() calls _garden_advance_stage() with force=true,
# bypasses normal thresholds, displays the new stage, and handles errors.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_promote function is defined ---
grep_result=$(grep -c '^_cli_promote()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_promote() function is defined"

# ============================================================
# Integration tests with temp garden data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"

# Create an _index.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":3,"by_stage":{"seed":2,"sprout":1,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":4,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a seed idea (no evidence — would NOT advance normally)
cat > "$GARDEN_DIR/idea-001.json" << 'EOF'
{
  "id": "idea-001",
  "title": "Add rate limit retry backoff",
  "description": "Add exponential backoff for rate-limited API calls",
  "stage": "seed",
  "origin": {"type": "human", "source": "cli", "trigger": "human"},
  "evidence": [],
  "tags": [],
  "priority": 5,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [{"from": "new", "to": "seed", "reason": "Planted", "timestamp": "2026-01-01T00:00:00Z"}],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-01T00:00:00Z"
}
EOF

# Create a sprout idea (low priority — would NOT advance to bloom normally)
cat > "$GARDEN_DIR/idea-002.json" << 'EOF'
{
  "id": "idea-002",
  "title": "Improve cache invalidation",
  "description": "Better cache invalidation strategy",
  "stage": "sprout",
  "origin": {"type": "metric", "source": "efficiency", "trigger": "degradation"},
  "evidence": [
    {"type": "observation", "observation": "First evidence", "added_by": "system", "added_at": "2026-01-01T00:00:00Z"},
    {"type": "observation", "observation": "Second evidence", "added_by": "system", "added_at": "2026-01-02T00:00:00Z"}
  ],
  "tags": [],
  "priority": 10,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [{"from": "new", "to": "seed", "reason": "Planted", "timestamp": "2026-01-01T00:00:00Z"}, {"stage": "sprout", "entered_at": "2026-01-02T00:00:00Z", "reason": "threshold met"}],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-02T00:00:00Z"
}
EOF

# Create a wilted idea (should not be promotable)
cat > "$GARDEN_DIR/idea-003.json" << 'EOF'
{
  "id": "idea-003",
  "title": "Old rejected idea",
  "description": "This was already rejected",
  "stage": "wilt",
  "origin": {"type": "human", "source": "cli", "trigger": "human"},
  "evidence": [],
  "tags": [],
  "priority": 0,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [{"from": "new", "to": "seed", "reason": "Planted", "timestamp": "2026-01-01T00:00:00Z"}, {"stage": "wilt", "entered_at": "2026-01-03T00:00:00Z", "reason": "No longer needed"}],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-01-03T00:00:00Z"
}
EOF

# Build a wrapper that sources the relevant functions
cat > "$TEST_DIR/run_promote.sh" << WRAPPER
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=true
GARDEN_SEED_TTL_DAYS=30
GARDEN_SPROUT_TTL_DAYS=60
GARDEN_SPROUT_THRESHOLD=2
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=50
GARDEN_MAX_ACTIVE_IDEAS=50

# Minimal log function
log() { :; }

# Extract needed functions from automaton.sh
eval "\$(sed -n '/^_garden_advance_stage()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_promote()/,/^}/p' '$script_file')"

_cli_promote "\$@"
WRAPPER
chmod +x "$TEST_DIR/run_promote.sh"

# --- Test 2: Promote a seed directly to bloom ---
output=$(bash "$TEST_DIR/run_promote.sh" "idea-001" 2>&1) || true
assert_contains "$output" "idea-001" "Output contains the idea ID"

# --- Test 3: Output shows the idea title ---
assert_contains "$output" "Add rate limit retry backoff" "Output shows idea title"

# --- Test 4: Output indicates bloom stage ---
assert_contains "$output" "bloom" "Output indicates bloom stage"

# --- Test 5: Output mentions bypassed/force/human promotion ---
assert_contains "$output" "human promotion" "Output mentions human promotion"

# --- Test 6: Idea stage actually changed to bloom ---
stage=$(jq -r '.stage' "$GARDEN_DIR/idea-001.json")
assert_equals "bloom" "$stage" "Seed idea stage changed to bloom"

# --- Test 7: Stage history records forced bloom transition ---
last_stage=$(jq -r '.stage_history[-1].stage // .stage_history[-1].to' "$GARDEN_DIR/idea-001.json")
assert_equals "bloom" "$last_stage" "Stage history records bloom transition"

# --- Test 8: Promote a sprout to bloom ---
output2=$(bash "$TEST_DIR/run_promote.sh" "idea-002" 2>&1) || true
assert_contains "$output2" "idea-002" "Output contains sprout idea ID"
assert_contains "$output2" "bloom" "Sprout promoted to bloom"
stage2=$(jq -r '.stage' "$GARDEN_DIR/idea-002.json")
assert_equals "bloom" "$stage2" "Sprout idea stage changed to bloom"

# --- Test 9: Output mentions quorum evaluation readiness ---
assert_contains "$output2" "quorum" "Output mentions quorum evaluation readiness"

# --- Test 10: Error on nonexistent idea ---
err_output=$(bash "$TEST_DIR/run_promote.sh" "idea-999" 2>&1) || true
assert_contains "$err_output" "Error" "Error message for nonexistent idea"

# --- Test 11: Error when garden disabled ---
cat > "$TEST_DIR/run_promote_disabled.sh" << WRAPPER2
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=false
log() { :; }
eval "\$(sed -n '/^_garden_advance_stage()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_promote()/,/^}/p' '$script_file')"
_cli_promote "\$@"
WRAPPER2
chmod +x "$TEST_DIR/run_promote_disabled.sh"
disabled_output=$(bash "$TEST_DIR/run_promote_disabled.sh" "idea-001" 2>&1) || true
assert_contains "$disabled_output" "not enabled" "Error when garden disabled"

# ============================================================
# Summary
# ============================================================
test_summary
