#!/usr/bin/env bash
# tests/test_cli_plant.sh — Tests for spec-44 §44.3 _cli_plant()
# Verifies that _cli_plant() creates a seed with human origin, displays
# the assigned ID, priority with human boost, and watering guidance.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_plant function is defined ---
grep_result=$(grep -c '^_cli_plant()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_plant() function is defined"

# ============================================================
# Integration tests with temp garden data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"

# Create an empty _index.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
EOF

# Build a wrapper that sources the relevant functions
cat > "$TEST_DIR/run_plant.sh" << WRAPPER
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
eval "\$(sed -n '/^_garden_plant_seed()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_find_duplicates()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_plant()/,/^}/p' '$script_file')"

_cli_plant "\$@"
WRAPPER
chmod +x "$TEST_DIR/run_plant.sh"

# --- Test 2: _cli_plant produces output with seed ID ---
output=$(bash "$TEST_DIR/run_plant.sh" "Add support for parallel review agents" 2>&1) || true
assert_contains "$output" "idea-001" "Output contains the assigned idea ID"

# --- Test 3: Output mentions seed stage ---
assert_contains "$output" "seed" "Output mentions seed stage"

# --- Test 4: Output mentions human origin ---
assert_contains "$output" "human" "Output mentions human origin"

# --- Test 5: Output mentions human boost in priority ---
assert_contains "$output" "10" "Output contains priority with human boost of 10"

# --- Test 6: Output contains watering guidance ---
assert_contains "$output" "--water" "Output contains watering guidance"
assert_contains "$output" "idea-001" "Watering guidance references the idea ID"

# --- Test 7: Idea file was created ---
assert_file_exists "$GARDEN_DIR/idea-001.json" "Idea file was created"

# --- Test 8: Idea has correct origin.type ---
origin_type=$(jq -r '.origin.type' "$GARDEN_DIR/idea-001.json")
assert_equals "human" "$origin_type" "Idea origin.type is 'human'"

# --- Test 9: Idea has correct origin.source ---
origin_source=$(jq -r '.origin.source' "$GARDEN_DIR/idea-001.json")
assert_equals "cli" "$origin_source" "Idea origin.source is 'cli'"

# --- Test 10: Idea title matches input ---
title=$(jq -r '.title' "$GARDEN_DIR/idea-001.json")
assert_equals "Add support for parallel review agents" "$title" "Idea title matches input"

# --- Test 11: Idea stage is seed ---
stage=$(jq -r '.stage' "$GARDEN_DIR/idea-001.json")
assert_equals "seed" "$stage" "Idea stage is 'seed'"

# --- Test 12: Second plant gets next ID ---
output2=$(bash "$TEST_DIR/run_plant.sh" "Another idea" 2>&1) || true
assert_contains "$output2" "idea-002" "Second plant gets idea-002"

# --- Test 13: Planted text appears in output (the title) ---
assert_contains "$output" "Add support for parallel review agents" "Output shows the idea title"

# ============================================================
# Summary
# ============================================================
test_summary
