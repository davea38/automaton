#!/usr/bin/env bash
# tests/test_cli_water.sh — Tests for spec-44 §44.3 _cli_water()
# Verifies that _cli_water() calls _garden_water() with the provided evidence,
# displays updated evidence count and priority, and reports stage advancement.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_water function is defined ---
grep_result=$(grep -c '^_cli_water()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_water() function is defined"

# ============================================================
# Integration tests with temp garden data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"

# Create an _index.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":1,"by_stage":{"seed":1,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":2,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a seed idea with 1 evidence item
cat > "$GARDEN_DIR/idea-001.json" << 'EOF'
{
  "id": "idea-001",
  "title": "Reduce prompt overhead in build phase",
  "description": "Reduce prompt overhead in build phase",
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

# Build a wrapper that sources the relevant functions
cat > "$TEST_DIR/run_water.sh" << WRAPPER
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
eval "\$(sed -n '/^_garden_water()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_advance_stage()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_water()/,/^}/p' '$script_file')"

_cli_water "\$@"
WRAPPER
chmod +x "$TEST_DIR/run_water.sh"

# --- Test 2: _cli_water adds evidence and shows title ---
output=$(bash "$TEST_DIR/run_water.sh" "idea-001" "Measured 4.2K tokens of static rules" 2>&1) || true
assert_contains "$output" "idea-001" "Output contains the idea ID"

# --- Test 3: Output shows idea title ---
assert_contains "$output" "Reduce prompt overhead in build phase" "Output shows idea title"

# --- Test 4: Output shows evidence count ---
assert_contains "$output" "2" "Output mentions updated evidence count"

# --- Test 5: Evidence was actually added to the file ---
evidence_count=$(jq '.evidence | length' "$GARDEN_DIR/idea-001.json")
assert_equals "2" "$evidence_count" "Idea file has 2 evidence items"

# --- Test 6: Evidence has correct observation ---
last_obs=$(jq -r '.evidence[-1].observation' "$GARDEN_DIR/idea-001.json")
assert_equals "Measured 4.2K tokens of static rules" "$last_obs" "Last evidence has correct observation"

# --- Test 7: Evidence added_by is human ---
last_by=$(jq -r '.evidence[-1].added_by' "$GARDEN_DIR/idea-001.json")
assert_equals "human" "$last_by" "Evidence added_by is 'human'"

# --- Test 8: Stage advancement on threshold ---
# Water again to reach sprout_threshold=2 total evidence items — we already have 2
# The seed has 2 evidence items now, which meets sprout_threshold=2
assert_contains "$output" "sprout" "Output reports stage advancement to sprout"

# --- Test 9: Idea stage changed to sprout ---
stage=$(jq -r '.stage' "$GARDEN_DIR/idea-001.json")
assert_equals "sprout" "$stage" "Idea stage advanced to sprout"

# --- Test 10: Priority is shown in output ---
# After watering and recompute, priority should be displayed
priority=$(jq -r '.priority // 0' "$GARDEN_DIR/idea-001.json")
assert_contains "$output" "$priority" "Output shows updated priority"

# --- Test 11: Error on nonexistent idea ---
err_output=$(bash "$TEST_DIR/run_water.sh" "idea-999" "some evidence" 2>&1) || true
assert_contains "$err_output" "Error" "Error message for nonexistent idea"

# --- Test 12: Error when garden disabled ---
cat > "$TEST_DIR/run_water_disabled.sh" << WRAPPER2
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=false
log() { :; }
eval "\$(sed -n '/^_garden_water()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_advance_stage()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_water()/,/^}/p' '$script_file')"
_cli_water "\$@"
WRAPPER2
chmod +x "$TEST_DIR/run_water_disabled.sh"
disabled_output=$(bash "$TEST_DIR/run_water_disabled.sh" "idea-001" "evidence" 2>&1) || true
assert_contains "$disabled_output" "not enabled" "Error when garden disabled"

# ============================================================
# Summary
# ============================================================
test_summary
