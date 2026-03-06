#!/usr/bin/env bash
# tests/test_signal_prune.sh — Tests for _signal_prune() (spec-42 §2)
# Verifies that _signal_prune() enforces max_signals by removing the
# weakest signals when the limit is exceeded.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _signal_prune function exists in automaton.sh ---
grep_result=$(grep -c '^_signal_prune()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_prune() function defined in automaton.sh"

# --- Test 2: _signal_prune checks stigmergy enabled guard ---
prune_func=$(sed -n '/^_signal_prune()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')
if echo "$prune_func" | grep -q '_signal_enabled\|STIGMERGY_ENABLED'; then
    echo "PASS: _signal_prune checks stigmergy enabled guard"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_prune should check stigmergy enabled guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _signal_prune references max_signals ---
if echo "$prune_func" | grep -q 'max_signals\|STIGMERGY_MAX_SIGNALS'; then
    echo "PASS: _signal_prune uses max_signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_prune should use max_signals limit" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _signal_prune sorts by strength ---
if echo "$prune_func" | grep -q 'strength\|sort'; then
    echo "PASS: _signal_prune considers signal strength"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_prune should sort/filter by strength to remove weakest" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _signal_prune operates on signals.json ---
if echo "$prune_func" | grep -q 'signals.json'; then
    echo "PASS: _signal_prune operates on signals.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_prune should operate on signals.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Functional Tests ---
# Set up a temp directory with signals exceeding max_signals
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export AUTOMATON_DIR="$TMPDIR_TEST"
export STIGMERGY_ENABLED=true
export STIGMERGY_MAX_SIGNALS=3
export PROJECT_DIR="$TMPDIR_TEST"
export LOG_FILE="$TMPDIR_TEST/automaton.log"
export RUN_LOG="$TMPDIR_TEST/run.log"
export LOG_LEVEL=1

# Create signals.json with 5 signals (exceeding max of 3)
cat > "$TMPDIR_TEST/signals.json" << 'EOF'
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "attention_needed",
      "title": "Strongest signal",
      "description": "Should survive",
      "strength": 0.9,
      "decay_rate": 0.10,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-002",
      "type": "quality_concern",
      "title": "Weakest signal",
      "description": "Should be pruned first",
      "strength": 0.1,
      "decay_rate": 0.07,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-003",
      "type": "recurring_pattern",
      "title": "Medium signal",
      "description": "Should survive",
      "strength": 0.5,
      "decay_rate": 0.05,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-004",
      "type": "efficiency_opportunity",
      "title": "Second weakest",
      "description": "Should be pruned second",
      "strength": 0.2,
      "decay_rate": 0.08,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-005",
      "type": "promising_approach",
      "title": "Strong signal",
      "description": "Should survive",
      "strength": 0.7,
      "decay_rate": 0.05,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    }
  ],
  "next_id": 6,
  "updated_at": "2026-01-01T00:00:00Z"
}
EOF

# Source the needed functions
eval "$(sed -n '/^log()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_enabled()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_prune()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')"

# Run prune
_signal_prune

# --- Test 6: Signal count reduced to max_signals ---
signal_count=$(jq '.signals | length' "$TMPDIR_TEST/signals.json")
assert_equals "3" "$signal_count" "Signal count reduced to max_signals (3)"

# --- Test 7: Strongest signals survive ---
sig1_exists=$(jq -r '.signals[] | select(.id == "SIG-001") | .id' "$TMPDIR_TEST/signals.json")
assert_equals "SIG-001" "$sig1_exists" "Strongest signal (SIG-001, strength 0.9) survives"

# --- Test 8: Second strongest survives ---
sig5_exists=$(jq -r '.signals[] | select(.id == "SIG-005") | .id' "$TMPDIR_TEST/signals.json")
assert_equals "SIG-005" "$sig5_exists" "Second strongest (SIG-005, strength 0.7) survives"

# --- Test 9: Third strongest survives ---
sig3_exists=$(jq -r '.signals[] | select(.id == "SIG-003") | .id' "$TMPDIR_TEST/signals.json")
assert_equals "SIG-003" "$sig3_exists" "Third strongest (SIG-003, strength 0.5) survives"

# --- Test 10: Weakest signals were removed ---
sig2_exists=$(jq -r '.signals[] | select(.id == "SIG-002") | .id' "$TMPDIR_TEST/signals.json")
if [ -z "$sig2_exists" ]; then
    echo "PASS: Weakest signal (SIG-002, strength 0.1) was pruned"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Weakest signal (SIG-002) should have been pruned" >&2
    ((_TEST_FAIL_COUNT++))
fi

sig4_exists=$(jq -r '.signals[] | select(.id == "SIG-004") | .id' "$TMPDIR_TEST/signals.json")
if [ -z "$sig4_exists" ]; then
    echo "PASS: Second weakest signal (SIG-004, strength 0.2) was pruned"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Second weakest signal (SIG-004) should have been pruned" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: No-op when under limit ---
export STIGMERGY_MAX_SIGNALS=10
_signal_prune
signal_count_after=$(jq '.signals | length' "$TMPDIR_TEST/signals.json")
assert_equals "3" "$signal_count_after" "No signals removed when under max_signals limit"

test_summary
