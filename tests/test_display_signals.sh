#!/usr/bin/env bash
# tests/test_display_signals.sh — Tests for spec-44 §44.2 _display_signals()
# Verifies that the signals display function exists and produces correctly
# formatted output with signal details, strength, linking status, and summaries.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _display_signals function is defined ---
grep_result=$(grep -c '^_display_signals()' "$script_file" || true)
assert_equals "1" "$grep_result" "_display_signals() function is defined"

# ============================================================
# Integration tests with test signal data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create signals.json with test data matching spec-44 example output
cat > "$TEST_DIR/signals.json" << 'EOF'
{
  "signals": [
    {
      "id": "SIG-001",
      "type": "recurring_pattern",
      "title": "High prompt overhead",
      "description": "Prompt overhead consistently above 50%",
      "strength": 0.80,
      "decay_rate": 0.05,
      "observations": [
        {"agent": "evolve-reflect", "cycle": 1, "timestamp": "2026-02-25T00:00:00Z", "detail": "obs1"},
        {"agent": "evolve-reflect", "cycle": 2, "timestamp": "2026-02-26T00:00:00Z", "detail": "obs2"},
        {"agent": "evolve-ideate", "cycle": 3, "timestamp": "2026-02-27T00:00:00Z", "detail": "obs3"},
        {"agent": "evolve-reflect", "cycle": 4, "timestamp": "2026-02-28T00:00:00Z", "detail": "obs4"}
      ],
      "related_ideas": ["idea-006"],
      "created_at": "2026-02-25T00:00:00Z",
      "last_reinforced_at": "2026-02-28T00:00:00Z",
      "last_decayed_at": "2026-02-28T00:00:00Z"
    },
    {
      "id": "SIG-003",
      "type": "efficiency_opp",
      "title": "Review reads entire codebase",
      "description": "Review phase reads too many files",
      "strength": 0.65,
      "decay_rate": 0.05,
      "observations": [
        {"agent": "evolve-reflect", "cycle": 2, "timestamp": "2026-02-26T00:00:00Z", "detail": "obs1"},
        {"agent": "evolve-ideate", "cycle": 3, "timestamp": "2026-02-27T00:00:00Z", "detail": "obs2"}
      ],
      "related_ideas": ["idea-007"],
      "created_at": "2026-02-26T00:00:00Z",
      "last_reinforced_at": "2026-02-27T00:00:00Z",
      "last_decayed_at": "2026-02-27T00:00:00Z"
    },
    {
      "id": "SIG-005",
      "type": "attention_needed",
      "title": "Test flakiness in budget tests",
      "description": "Budget tests intermittently fail",
      "strength": 0.42,
      "decay_rate": 0.08,
      "observations": [
        {"agent": "evolve-reflect", "cycle": 1, "timestamp": "2026-02-25T00:00:00Z", "detail": "obs1"},
        {"agent": "evolve-reflect", "cycle": 2, "timestamp": "2026-02-26T00:00:00Z", "detail": "obs2"},
        {"agent": "evolve-reflect", "cycle": 4, "timestamp": "2026-02-28T00:00:00Z", "detail": "obs3"}
      ],
      "related_ideas": [],
      "created_at": "2026-02-25T00:00:00Z",
      "last_reinforced_at": "2026-02-28T00:00:00Z",
      "last_decayed_at": "2026-02-28T00:00:00Z"
    },
    {
      "id": "SIG-006",
      "type": "promising_approach",
      "title": "Caching reduced token usage 20%",
      "description": "Cache approach showed improvement",
      "strength": 0.35,
      "decay_rate": 0.10,
      "observations": [
        {"agent": "evolve-observe", "cycle": 3, "timestamp": "2026-02-27T00:00:00Z", "detail": "obs1"}
      ],
      "related_ideas": ["idea-004"],
      "created_at": "2026-02-27T00:00:00Z",
      "last_reinforced_at": "2026-02-27T00:00:00Z",
      "last_decayed_at": "2026-02-27T00:00:00Z"
    },
    {
      "id": "SIG-007",
      "type": "complexity_warning",
      "title": "automaton.sh approaching 9K lines",
      "description": "File size growing rapidly",
      "strength": 0.28,
      "decay_rate": 0.05,
      "observations": [
        {"agent": "evolve-reflect", "cycle": 4, "timestamp": "2026-02-28T00:00:00Z", "detail": "obs1"}
      ],
      "related_ideas": [],
      "created_at": "2026-02-28T00:00:00Z",
      "last_reinforced_at": "2026-02-28T00:00:00Z",
      "last_decayed_at": "2026-02-28T00:00:00Z"
    }
  ],
  "next_id": 8,
  "updated_at": "2026-02-28T00:00:00Z"
}
EOF

# Create wrapper script that sources and runs _display_signals
cat > "$TEST_DIR/run_display.sh" << WRAPPER
#!/usr/bin/env bash
AUTOMATON_DIR="$TEST_DIR"
STIGMERGY_ENABLED=true
STIGMERGY_DECAY_FLOOR=0.05
log() { :; }
eval "\$(sed -n '/^_display_signals()/,/^}/p' '$script_file')"
_display_signals
WRAPPER
chmod +x "$TEST_DIR/run_display.sh"

output=$(bash "$TEST_DIR/run_display.sh" 2>&1) || true

# --- Test 2: Output contains header with signal count ---
assert_contains "$output" "ACTIVE SIGNALS" "Output contains ACTIVE SIGNALS header"

# --- Test 3: Output shows total signal count ---
assert_contains "$output" "5" "Output shows total signal count"

# --- Test 4: Output shows strong signal count ---
# Strong signals (>= 0.5): SIG-001 (0.80) and SIG-003 (0.65) = 2
assert_contains "$output" "strong" "Output mentions strong signals"

# --- Test 5: Output contains column headers ---
assert_contains "$output" "ID" "Output contains ID column header"
assert_contains "$output" "TYPE" "Output contains TYPE column header"
assert_contains "$output" "STR" "Output contains STR column header"
assert_contains "$output" "TITLE" "Output contains TITLE column header"
assert_contains "$output" "OBS" "Output contains OBS column header"
assert_contains "$output" "LINKED" "Output contains LINKED column header"

# --- Test 6: Output shows signal IDs ---
assert_contains "$output" "SIG-001" "Output contains SIG-001"
assert_contains "$output" "SIG-003" "Output contains SIG-003"
assert_contains "$output" "SIG-005" "Output contains SIG-005"
assert_contains "$output" "SIG-006" "Output contains SIG-006"
assert_contains "$output" "SIG-007" "Output contains SIG-007"

# --- Test 7: Output shows signal types ---
assert_contains "$output" "recurring_pattern" "Output shows recurring_pattern type"
assert_contains "$output" "attention_needed" "Output shows attention_needed type"

# --- Test 8: Output shows strength values ---
assert_contains "$output" "0.80" "Output shows strength 0.80"
assert_contains "$output" "0.65" "Output shows strength 0.65"

# --- Test 9: Output shows observation counts ---
# SIG-001 has 4 observations
assert_contains "$output" "4" "Output shows observation count 4"

# --- Test 10: Output shows linked idea IDs ---
assert_contains "$output" "idea-006" "Output shows linked idea-006"
assert_contains "$output" "idea-007" "Output shows linked idea-007"

# --- Test 11: Unlinked signals show dash ---
# SIG-005 and SIG-007 have no related ideas
# The output should have a dash for unlinked signals
# We check the unlinked count summary
assert_contains "$output" "Unlinked" "Output shows unlinked signal summary"

# --- Test 12: Output shows strong signals summary ---
assert_contains "$output" "Strong" "Output shows strong signal summary"

# --- Test 13: Signals are sorted by strength descending ---
sig1_line=$(echo "$output" | grep -n "SIG-001" | head -1 | cut -d: -f1)
sig7_line=$(echo "$output" | grep -n "SIG-007" | head -1 | cut -d: -f1)
if [ -n "$sig1_line" ] && [ -n "$sig7_line" ] && [ "$sig1_line" -lt "$sig7_line" ]; then
    echo "PASS: Stronger signal SIG-001 appears before weaker SIG-007 (line $sig1_line < $sig7_line)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: SIG-001 (0.80) should appear before SIG-007 (0.28)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# Edge case: no signals file
# ============================================================

EMPTY_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR" "$EMPTY_DIR"' EXIT

cat > "$EMPTY_DIR/run_empty.sh" << WRAPPER
#!/usr/bin/env bash
AUTOMATON_DIR="$EMPTY_DIR"
STIGMERGY_ENABLED=true
STIGMERGY_DECAY_FLOOR=0.05
log() { :; }
eval "\$(sed -n '/^_display_signals()/,/^}/p' '$script_file')"
_display_signals
WRAPPER
chmod +x "$EMPTY_DIR/run_empty.sh"

empty_output=$(bash "$EMPTY_DIR/run_empty.sh" 2>&1) || true

# --- Test 14: No signals file shows helpful message ---
assert_contains "$empty_output" "No" "No-signals case shows informative message"

# ============================================================
# Edge case: empty signals array
# ============================================================

EMPTY2_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR" "$EMPTY_DIR" "$EMPTY2_DIR"' EXIT

cat > "$EMPTY2_DIR/signals.json" << 'EOF'
{"signals":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
EOF

cat > "$EMPTY2_DIR/run_empty2.sh" << WRAPPER
#!/usr/bin/env bash
AUTOMATON_DIR="$EMPTY2_DIR"
STIGMERGY_ENABLED=true
STIGMERGY_DECAY_FLOOR=0.05
log() { :; }
eval "\$(sed -n '/^_display_signals()/,/^}/p' '$script_file')"
_display_signals
WRAPPER
chmod +x "$EMPTY2_DIR/run_empty2.sh"

empty2_output=$(bash "$EMPTY2_DIR/run_empty2.sh" 2>&1) || true

# --- Test 15: Empty signals array shows helpful message ---
assert_contains "$empty2_output" "0" "Empty signals shows 0 count"

test_summary
