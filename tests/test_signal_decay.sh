#!/usr/bin/env bash
# tests/test_signal_decay.sh — Tests for _signal_decay_all() (spec-42 §2)
# Verifies that _signal_decay_all() reduces all signal strengths by their
# decay_rate and removes signals below decay_floor.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _signal_decay_all function exists in automaton.sh ---
grep_result=$(grep -c '^_signal_decay_all()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_decay_all() function defined in automaton.sh"

# --- Test 2: _signal_decay_all checks stigmergy enabled guard ---
decay_func=$(sed -n '/^_signal_decay_all()/,/^[a-z_]*() {/p' "$script_file")
if echo "$decay_func" | grep -q '_signal_enabled\|STIGMERGY_ENABLED'; then
    echo "PASS: _signal_decay_all checks stigmergy enabled guard"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_decay_all should check stigmergy enabled guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: _signal_decay_all references decay_rate ---
if echo "$decay_func" | grep -q 'decay_rate'; then
    echo "PASS: _signal_decay_all uses decay_rate"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_decay_all should use each signal's decay_rate" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: _signal_decay_all references decay_floor ---
if echo "$decay_func" | grep -q 'decay_floor\|STIGMERGY_DECAY_FLOOR'; then
    echo "PASS: _signal_decay_all uses decay_floor"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_decay_all should use decay_floor to remove weak signals" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _signal_decay_all updates last_decayed_at ---
if echo "$decay_func" | grep -q 'last_decayed_at'; then
    echo "PASS: _signal_decay_all updates last_decayed_at"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_decay_all should update last_decayed_at timestamp" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _signal_decay_all updates signals.json ---
if echo "$decay_func" | grep -q 'signals.json'; then
    echo "PASS: _signal_decay_all operates on signals.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_decay_all should operate on signals.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Functional test — decay reduces strength correctly ---
# Set up a temp directory with a signals.json containing a signal at strength 0.5 with decay_rate 0.10
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export AUTOMATON_DIR="$TMPDIR_TEST"
export STIGMERGY_ENABLED=true
export STIGMERGY_DECAY_FLOOR=0.05
export PROJECT_DIR="$TMPDIR_TEST"
export LOG_FILE="$TMPDIR_TEST/automaton.log"
export RUN_LOG="$TMPDIR_TEST/run.log"
export LOG_LEVEL=1

# Create signals.json with two test signals
cat > "$TMPDIR_TEST/signals.json" << 'EOF'
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "attention_needed",
      "title": "Test signal strong",
      "description": "Should survive decay",
      "strength": 0.5,
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
      "title": "Test signal weak",
      "description": "Should be removed by decay",
      "strength": 0.04,
      "decay_rate": 0.07,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    }
  ],
  "next_id": 3,
  "updated_at": "2026-01-01T00:00:00Z"
}
EOF

# Source the function (extract only what we need to avoid full script execution)
# We need: _signal_enabled, log, _signal_decay_all
eval "$(sed -n '/^log()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_enabled()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_decay_all()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')"

# Run the decay function
_signal_decay_all

# Check that SIG-001 survived with reduced strength (0.5 - 0.10 = 0.40)
sig1_strength=$(jq -r '.signals[] | select(.id == "SIG-001") | .strength' "$TMPDIR_TEST/signals.json")
# Allow for floating point: should be approximately 0.4
if echo "$sig1_strength" | grep -qE '^0\.3[89]|^0\.4[012]?$'; then
    echo "PASS: SIG-001 strength decayed from 0.5 to ~0.4 (got $sig1_strength)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: SIG-001 strength should be ~0.4 after decay (got $sig1_strength)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Weak signal (below decay_floor after decay) is removed ---
sig2_exists=$(jq -r '.signals[] | select(.id == "SIG-002") | .id' "$TMPDIR_TEST/signals.json")
if [ -z "$sig2_exists" ]; then
    echo "PASS: SIG-002 (below decay_floor) was removed"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: SIG-002 should have been removed (strength was 0.04, below decay_floor 0.05)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Signal count correct after decay ---
signal_count=$(jq '.signals | length' "$TMPDIR_TEST/signals.json")
assert_equals "1" "$signal_count" "Only 1 signal remains after decay (weak one removed)"

# --- Test 10: last_decayed_at was updated ---
last_decayed=$(jq -r '.signals[] | select(.id == "SIG-001") | .last_decayed_at' "$TMPDIR_TEST/signals.json")
if [ "$last_decayed" != "2026-01-01T00:00:00Z" ]; then
    echo "PASS: last_decayed_at was updated (got $last_decayed)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: last_decayed_at should have been updated from original timestamp" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
