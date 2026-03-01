#!/usr/bin/env bash
# tests/test_cli_prune.sh — Tests for spec-44 §44.3 _cli_prune()
# Verifies that _cli_prune() calls _garden_wilt() with the provided reason,
# displays confirmation with idea title and reason, and prevents accidental deletions.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_prune function is defined ---
grep_result=$(grep -c '^_cli_prune()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_prune() function is defined"

# ============================================================
# Integration tests with temp garden data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"

# Create an _index.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":2,"by_stage":{"seed":1,"sprout":1,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":3,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a seed idea
cat > "$GARDEN_DIR/idea-001.json" << 'EOF'
{
  "id": "idea-001",
  "title": "Improve error message clarity",
  "description": "Make error messages more user-friendly",
  "stage": "seed",
  "origin": {"type": "human", "source": "cli", "trigger": "human"},
  "evidence": [
    {"type": "observation", "observation": "Initial planting evidence", "added_by": "human", "added_at": "2026-01-01T00:00:00Z"}
  ],
  "tags": [],
  "priority": 10,
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

# Create a sprout idea
cat > "$GARDEN_DIR/idea-002.json" << 'EOF'
{
  "id": "idea-002",
  "title": "Add retry logic for API calls",
  "description": "Retry transient failures",
  "stage": "sprout",
  "origin": {"type": "metric", "source": "efficiency", "trigger": "degradation"},
  "evidence": [
    {"type": "observation", "observation": "First evidence", "added_by": "system", "added_at": "2026-01-01T00:00:00Z"},
    {"type": "observation", "observation": "Second evidence", "added_by": "system", "added_at": "2026-01-02T00:00:00Z"}
  ],
  "tags": [],
  "priority": 25,
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

# Build a wrapper that sources the relevant functions
cat > "$TEST_DIR/run_prune.sh" << WRAPPER
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
eval "\$(sed -n '/^_garden_wilt()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_prune()/,/^}/p' '$script_file')"

_cli_prune "\$@"
WRAPPER
chmod +x "$TEST_DIR/run_prune.sh"

# --- Test 2: _cli_prune displays confirmation with idea title ---
output=$(bash "$TEST_DIR/run_prune.sh" "idea-001" "No longer relevant after spec-37 changes" 2>&1) || true
assert_contains "$output" "idea-001" "Output contains the idea ID"

# --- Test 3: Output shows idea title ---
assert_contains "$output" "Improve error message clarity" "Output shows idea title"

# --- Test 4: Output contains wilted status ---
assert_contains "$output" "wilt" "Output indicates wilted status"

# --- Test 5: Output shows the reason ---
assert_contains "$output" "No longer relevant after spec-37 changes" "Output shows the prune reason"

# --- Test 6: Idea stage changed to wilt ---
stage=$(jq -r '.stage' "$GARDEN_DIR/idea-001.json")
assert_equals "wilt" "$stage" "Idea stage changed to wilt"

# --- Test 7: Stage history records wilt with reason ---
last_stage=$(jq -r '.stage_history[-1].stage' "$GARDEN_DIR/idea-001.json")
assert_equals "wilt" "$last_stage" "Stage history records wilt transition"

last_reason=$(jq -r '.stage_history[-1].reason' "$GARDEN_DIR/idea-001.json")
assert_equals "No longer relevant after spec-37 changes" "$last_reason" "Stage history records prune reason"

# --- Test 8: Prune a sprout idea ---
output2=$(bash "$TEST_DIR/run_prune.sh" "idea-002" "Superseded by better approach" 2>&1) || true
assert_contains "$output2" "idea-002" "Output contains sprout idea ID"
assert_contains "$output2" "Add retry logic for API calls" "Output shows sprout idea title"

stage2=$(jq -r '.stage' "$GARDEN_DIR/idea-002.json")
assert_equals "wilt" "$stage2" "Sprout idea stage changed to wilt"

# --- Test 9: Error on nonexistent idea ---
err_output=$(bash "$TEST_DIR/run_prune.sh" "idea-999" "some reason" 2>&1) || true
assert_contains "$err_output" "Error" "Error message for nonexistent idea"

# --- Test 10: Error when garden disabled ---
cat > "$TEST_DIR/run_prune_disabled.sh" << WRAPPER2
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=false
log() { :; }
eval "\$(sed -n '/^_garden_wilt()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_prune()/,/^}/p' '$script_file')"
_cli_prune "\$@"
WRAPPER2
chmod +x "$TEST_DIR/run_prune_disabled.sh"
disabled_output=$(bash "$TEST_DIR/run_prune_disabled.sh" "idea-001" "reason" 2>&1) || true
assert_contains "$disabled_output" "not enabled" "Error when garden disabled"

# ============================================================
# Summary
# ============================================================
test_summary
