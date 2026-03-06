#!/usr/bin/env bash
# tests/test_display_garden_detail.sh — Tests for spec-44 §44.2 _display_garden_detail()
# Verifies that the garden detail display function renders full idea information
# including description, evidence, related items, stage history, and vote status.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# ============================================================
# Function existence
# ============================================================

# --- Test 1: _display_garden_detail function is defined ---
grep_result=$(grep -c '^_display_garden_detail()' "$script_file" || true)
assert_equals "1" "$grep_result" "_display_garden_detail() function is defined"

# ============================================================
# Integration tests with temp garden data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"
mkdir -p "$TEST_DIR/votes"

# Create a bloom idea with full details
cat > "$GARDEN_DIR/idea-006.json" << 'EOF'
{
  "id": "idea-006",
  "title": "Reduce prompt overhead",
  "description": "Build prompts contain 4K tokens of static rules identical every iteration.\nExtract static rules to a cached preamble, reducing per-iteration overhead.",
  "stage": "bloom",
  "origin": {"type": "metric", "source": "evolve-reflect", "created_by": "evolve-reflect", "created_at": "2026-02-25T00:00:00Z"},
  "evidence": [
    {"type": "metric", "content": "Prompt overhead ratio >50% for 5 consecutive runs", "source": "evolve-reflect", "added_at": "2026-02-25T00:00:00Z"},
    {"type": "signal", "content": "SIG-007 strength 0.8: recurring high prompt overhead", "source": "evolve-ideate", "added_at": "2026-02-26T00:00:00Z"},
    {"type": "metric", "content": "Cache hit ratio could increase 15% with static preamble", "source": "evolve-reflect", "added_at": "2026-02-27T00:00:00Z"},
    {"type": "human", "content": "This is the most impactful optimization available", "source": "human", "added_at": "2026-02-28T00:00:00Z"}
  ],
  "tags": ["efficiency", "caching"],
  "priority": 72,
  "estimated_complexity": "medium",
  "related_specs": [29, 30, 37],
  "related_signals": ["SIG-007"],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-25T00:00:00Z", "reason": "Auto-seeded from metric threshold"},
    {"stage": "sprout", "entered_at": "2026-02-26T00:00:00Z", "reason": "2 evidence items accumulated"},
    {"stage": "bloom", "entered_at": "2026-02-28T00:00:00Z", "reason": "Priority 72, 4 evidence items, human promoted"}
  ],
  "vote_id": null,
  "implementation": null,
  "updated_at": "2026-02-28T00:00:00Z"
}
EOF

# Create a seed idea with minimal details
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

# Create a harvested idea with vote_id set
cat > "$GARDEN_DIR/idea-010.json" << 'EOF'
{
  "id": "idea-010",
  "title": "Already harvested idea",
  "description": "This was implemented and merged.",
  "stage": "harvest",
  "origin": {"type": "metric", "source": "evolve-reflect", "created_by": "evolve-reflect", "created_at": "2026-02-10T00:00:00Z"},
  "evidence": [
    {"type": "metric", "content": "Metric breach detected", "source": "evolve-reflect", "added_at": "2026-02-10T00:00:00Z"}
  ],
  "tags": ["reliability"],
  "priority": 80,
  "estimated_complexity": "high",
  "related_specs": [22],
  "related_signals": ["SIG-001"],
  "related_ideas": [],
  "stage_history": [
    {"stage": "seed", "entered_at": "2026-02-10T00:00:00Z", "reason": "Seeded"},
    {"stage": "bloom", "entered_at": "2026-02-12T00:00:00Z", "reason": "Promoted"},
    {"stage": "harvest", "entered_at": "2026-02-15T00:00:00Z", "reason": "Merged"}
  ],
  "vote_id": "vote-005",
  "implementation": {"branch": "automaton/evolve-1-idea-010", "cycle_id": 1},
  "updated_at": "2026-02-15T00:00:00Z"
}
EOF

# Create a vote record for idea-010
cat > "$TEST_DIR/votes/vote-005.json" << 'EOF'
{
  "id": "vote-005",
  "idea_id": "idea-010",
  "result": "approved",
  "tally": {"approve": 4, "reject": 1, "abstain": 0}
}
EOF

# Helper to run _display_garden_detail with a given idea ID
run_detail() {
    local idea_id="$1"
    cat > "$TEST_DIR/run_detail.sh" << WRAPPER
#!/usr/bin/env bash
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=true
log() { :; }
eval "\$(sed -n '/^_display_garden_detail()/,/^}/p' '$script_file')"
_display_garden_detail "$idea_id"
WRAPPER
    chmod +x "$TEST_DIR/run_detail.sh"
    bash "$TEST_DIR/run_detail.sh" 2>&1
}

# ============================================================
# Test bloom idea with full details
# ============================================================

output=$(run_detail "idea-006") || true

# --- Test 2: Output contains idea ID and title ---
assert_contains "$output" "idea-006" "Output contains idea ID"
assert_contains "$output" "Reduce prompt overhead" "Output contains idea title"

# --- Test 3: Output shows stage and priority ---
assert_contains "$output" "bloom" "Output shows bloom stage"
assert_contains "$output" "72" "Output shows priority 72"

# --- Test 4: Output shows complexity ---
assert_contains "$output" "medium" "Output shows complexity"

# --- Test 5: Output shows description ---
assert_contains "$output" "Description" "Output has Description section"
assert_contains "$output" "static rules" "Output shows description content"

# --- Test 6: Output shows evidence list ---
assert_contains "$output" "Evidence" "Output has Evidence section"
assert_contains "$output" "4" "Output shows evidence count"
assert_contains "$output" "metric" "Output shows evidence type"
assert_contains "$output" "Prompt overhead ratio" "Output shows first evidence content"
assert_contains "$output" "human" "Output shows human evidence type"

# --- Test 7: Output shows related specs and signals ---
assert_contains "$output" "29" "Output shows related spec 29"
assert_contains "$output" "30" "Output shows related spec 30"
assert_contains "$output" "SIG-007" "Output shows related signal"

# --- Test 8: Output shows stage history ---
assert_contains "$output" "Stage History" "Output has Stage History section"
assert_contains "$output" "seed" "Output shows seed in stage history"
assert_contains "$output" "sprout" "Output shows sprout in stage history"
assert_contains "$output" "Auto-seeded" "Output shows stage history reason"

# --- Test 9: Output shows vote status ---
assert_contains "$output" "not yet evaluated" "Output shows vote status for unevaluated idea"

# ============================================================
# Test seed idea with minimal details
# ============================================================

output_seed=$(run_detail "idea-003") || true

# --- Test 10: Seed idea shows correctly ---
assert_contains "$output_seed" "idea-003" "Seed output contains idea ID"
assert_contains "$output_seed" "Improve error messages" "Seed output contains title"
assert_contains "$output_seed" "seed" "Seed output shows seed stage"
assert_contains "$output_seed" "18" "Seed output shows priority"

# --- Test 11: Empty evidence shows 0 count ---
assert_contains "$output_seed" "0" "Seed output shows 0 evidence"

# ============================================================
# Test harvested idea with vote reference
# ============================================================

output_harvest=$(run_detail "idea-010") || true

# --- Test 12: Harvested idea shows vote reference ---
assert_contains "$output_harvest" "idea-010" "Harvested output contains idea ID"
assert_contains "$output_harvest" "harvest" "Harvested output shows harvest stage"
assert_contains "$output_harvest" "vote-005" "Harvested output shows vote ID reference"

# ============================================================
# Test non-existent idea
# ============================================================

output_missing=$(run_detail "idea-999") || true

# --- Test 13: Non-existent idea shows error ---
assert_contains "$output_missing" "not found" "Non-existent idea shows not found message"

# ============================================================
# Test with bare ID (without idea- prefix)
# ============================================================

output_bare=$(run_detail "006") || true

# --- Test 14: Bare ID (without prefix) works ---
assert_contains "$output_bare" "Reduce prompt overhead" "Bare ID lookup finds the idea"

test_summary
