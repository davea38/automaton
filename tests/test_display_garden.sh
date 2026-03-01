#!/usr/bin/env bash
# tests/test_display_garden.sh — Tests for spec-44 §44.2 _display_garden()
# Verifies that the garden summary display function exists and produces
# correctly formatted output with proper sorting (bloom first, then by priority).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _display_garden function is defined ---
grep_result=$(grep -c '^_display_garden()' "$script_file" || true)
assert_equals "1" "$grep_result" "_display_garden() function is defined"

# ============================================================
# Integration tests with temp garden data
# ============================================================

# Create a temporary AUTOMATON_DIR with test garden data
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"

# Create test idea files with different stages and priorities

# Bloom idea — high priority
cat > "$GARDEN_DIR/idea-001.json" << 'EOF'
{
  "id": "idea-001",
  "title": "Reduce prompt overhead",
  "description": "Extract static rules to a cached preamble.",
  "stage": "bloom",
  "origin": {"type": "metric", "source": "evolve-reflect", "created_by": "evolve-reflect", "created_at": "2026-02-20T00:00:00Z"},
  "evidence": [{"type": "metric", "content": "evidence 1"}, {"type": "signal", "content": "evidence 2"}, {"type": "metric", "content": "evidence 3"}],
  "tags": ["efficiency"],
  "priority": 72,
  "estimated_complexity": "medium",
  "related_specs": [29, 30],
  "related_signals": ["SIG-007"],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-20T00:00:00Z", "reason": "Auto-seeded"},
    {"stage": "sprout", "entered_at": "2026-02-22T00:00:00Z", "reason": "Threshold met"},
    {"stage": "bloom", "entered_at": "2026-02-25T00:00:00Z", "reason": "Priority threshold met"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-25T00:00:00Z"
}
EOF

# Sprout idea — medium priority
cat > "$GARDEN_DIR/idea-002.json" << 'EOF'
{
  "id": "idea-002",
  "title": "Cache static sections",
  "description": "Cache repeated sections.",
  "stage": "sprout",
  "origin": {"type": "signal", "source": "evolve-ideate", "created_by": "evolve-ideate", "created_at": "2026-02-22T00:00:00Z"},
  "evidence": [{"type": "metric", "content": "evidence 1"}, {"type": "signal", "content": "evidence 2"}],
  "tags": ["caching"],
  "priority": 45,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-22T00:00:00Z", "reason": "Seeded"},
    {"stage": "sprout", "entered_at": "2026-02-24T00:00:00Z", "reason": "Evidence threshold"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-24T00:00:00Z"
}
EOF

# Seed idea — low priority
cat > "$GARDEN_DIR/idea-003.json" << 'EOF'
{
  "id": "idea-003",
  "title": "Improve error messages",
  "description": "Better error messages for users.",
  "stage": "seed",
  "origin": {"type": "human", "source": "cli", "created_by": "human", "created_at": "2026-02-27T00:00:00Z"},
  "evidence": [],
  "tags": ["ux"],
  "priority": 18,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-27T00:00:00Z", "reason": "Human planted"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-27T00:00:00Z"
}
EOF

# Wilted idea — should NOT appear
cat > "$GARDEN_DIR/idea-004.json" << 'EOF'
{
  "id": "idea-004",
  "title": "Wilted idea",
  "description": "This was rejected.",
  "stage": "wilt",
  "origin": {"type": "metric", "source": "evolve-reflect", "created_by": "evolve-reflect", "created_at": "2026-02-15T00:00:00Z"},
  "evidence": [],
  "tags": [],
  "priority": 5,
  "estimated_complexity": "low",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-15T00:00:00Z", "reason": "Seeded"},
    {"stage": "wilt", "entered_at": "2026-02-20T00:00:00Z", "reason": "Expired"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-20T00:00:00Z"
}
EOF

# Second bloom idea — lower priority than idea-001
cat > "$GARDEN_DIR/idea-005.json" << 'EOF'
{
  "id": "idea-005",
  "title": "Parallel review capability",
  "description": "Add parallel review.",
  "stage": "bloom",
  "origin": {"type": "metric", "source": "evolve-reflect", "created_by": "evolve-reflect", "created_at": "2026-02-18T00:00:00Z"},
  "evidence": [{"type": "metric", "content": "evidence 1"}, {"type": "signal", "content": "evidence 2"}],
  "tags": ["parallel"],
  "priority": 65,
  "estimated_complexity": "high",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-18T00:00:00Z", "reason": "Auto-seeded"},
    {"stage": "bloom", "entered_at": "2026-02-23T00:00:00Z", "reason": "Promoted"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-23T00:00:00Z"
}
EOF

# Harvested idea — should NOT appear
cat > "$GARDEN_DIR/idea-006.json" << 'EOF'
{
  "id": "idea-006",
  "title": "Harvested idea",
  "description": "Already implemented.",
  "stage": "harvest",
  "origin": {"type": "metric", "source": "evolve-reflect", "created_by": "evolve-reflect", "created_at": "2026-02-10T00:00:00Z"},
  "evidence": [],
  "tags": [],
  "priority": 90,
  "estimated_complexity": "medium",
  "related_specs": [],
  "related_signals": [],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-10T00:00:00Z", "reason": "Seeded"},
    {"stage": "harvest", "entered_at": "2026-02-15T00:00:00Z", "reason": "Merged"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-15T00:00:00Z"
}
EOF

# Create _index.json (the display function reads idea files, not just index)
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":6,"by_stage":{"seed":1,"sprout":1,"bloom":2,"harvest":1,"wilt":1},"bloom_candidates":[{"id":"idea-001","title":"Reduce prompt overhead","priority":72},{"id":"idea-005","title":"Parallel review capability","priority":65}],"recent_activity":[],"next_id":7,"updated_at":"2026-02-27T00:00:00Z"}
EOF

# Source the function in isolation by extracting it
# We'll test by running _display_garden with AUTOMATON_DIR set

# --- Test 2: _display_garden output contains header line with counts ---
# We need to source the function. We'll create a small wrapper script.
cat > "$TEST_DIR/run_display.sh" << WRAPPER
#!/usr/bin/env bash
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=true
# Define a minimal log function
log() { :; }
# Source only the function we need by extracting it
eval "\$(sed -n '/^_display_garden()/,/^}/p' '$script_file')"
_display_garden
WRAPPER
chmod +x "$TEST_DIR/run_display.sh"

output=$(bash "$TEST_DIR/run_display.sh" 2>&1) || true

# --- Test 2: Output contains header with idea counts ---
assert_contains "$output" "GARDEN" "Output contains GARDEN header"

# --- Test 3: Output shows non-wilted/non-harvested idea count ---
# 4 non-wilted/non-harvested ideas: idea-001 (bloom), idea-002 (sprout), idea-003 (seed), idea-005 (bloom)
assert_contains "$output" "seed" "Output mentions seed stage"

# --- Test 4: Output contains bloom ideas ---
assert_contains "$output" "idea-001" "Output contains bloom idea-001"
assert_contains "$output" "idea-005" "Output contains bloom idea-005"

# --- Test 5: Output contains sprout idea ---
assert_contains "$output" "idea-002" "Output contains sprout idea-002"

# --- Test 6: Output contains seed idea ---
assert_contains "$output" "idea-003" "Output contains seed idea-003"

# --- Test 7: Wilted idea is NOT in output ---
if echo "$output" | grep -qF "idea-004"; then
    echo "FAIL: Wilted idea-004 should not appear in garden display" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: Wilted idea-004 excluded from display"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 8: Harvested idea is NOT in output ---
if echo "$output" | grep -qF "idea-006"; then
    echo "FAIL: Harvested idea-006 should not appear in garden display" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: Harvested idea-006 excluded from display"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 9: Bloom ideas appear before seed/sprout ideas ---
bloom_line=$(echo "$output" | grep -n "idea-001" | head -1 | cut -d: -f1)
seed_line=$(echo "$output" | grep -n "idea-003" | head -1 | cut -d: -f1)
if [ -n "$bloom_line" ] && [ -n "$seed_line" ] && [ "$bloom_line" -lt "$seed_line" ]; then
    echo "PASS: Bloom ideas appear before seed ideas (line $bloom_line < $seed_line)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Bloom ideas should appear before seed ideas (bloom=$bloom_line, seed=$seed_line)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Higher priority bloom appears before lower priority bloom ---
bloom1_line=$(echo "$output" | grep -n "idea-001" | head -1 | cut -d: -f1)
bloom5_line=$(echo "$output" | grep -n "idea-005" | head -1 | cut -d: -f1)
if [ -n "$bloom1_line" ] && [ -n "$bloom5_line" ] && [ "$bloom1_line" -lt "$bloom5_line" ]; then
    echo "PASS: Higher priority bloom (idea-001, pri=72) before lower (idea-005, pri=65)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: idea-001 (pri=72) should appear before idea-005 (pri=65)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Output shows bloom candidates count ---
assert_contains "$output" "Bloom candidates" "Output shows bloom candidates count"

# --- Test 12: Output shows guidance for detail/plant commands ---
assert_contains "$output" "--garden-detail" "Output shows --garden-detail hint"

# --- Test 13: Output shows idea titles ---
assert_contains "$output" "Reduce prompt overhead" "Output shows idea title"
assert_contains "$output" "Cache static sections" "Output shows sprout title"

# --- Test 14: Output shows priority values ---
assert_contains "$output" "72" "Output shows priority 72"
assert_contains "$output" "45" "Output shows priority 45"

# ============================================================
# Edge case: empty garden
# ============================================================

EMPTY_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR" "$EMPTY_DIR"' EXIT
mkdir -p "$EMPTY_DIR/garden"
cat > "$EMPTY_DIR/garden/_index.json" << 'EOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
EOF

cat > "$EMPTY_DIR/run_empty.sh" << WRAPPER
#!/usr/bin/env bash
AUTOMATON_DIR="$EMPTY_DIR"
GARDEN_ENABLED=true
log() { :; }
eval "\$(sed -n '/^_display_garden()/,/^}/p' '$script_file')"
_display_garden
WRAPPER
chmod +x "$EMPTY_DIR/run_empty.sh"

empty_output=$(bash "$EMPTY_DIR/run_empty.sh" 2>&1) || true

# --- Test 15: Empty garden shows helpful message ---
assert_contains "$empty_output" "--plant" "Empty garden suggests --plant command"

test_summary
