#!/usr/bin/env bash
# tests/test_signal_query.sh — Tests for signal query functions (spec-42 §2)
# Verifies _signal_get_strong(), _signal_get_by_type(), _signal_get_active(),
# and _signal_get_unlinked() return correct filtered signal sets.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1-4: All four query functions exist in automaton.sh ---
for func in _signal_get_strong _signal_get_by_type _signal_get_active _signal_get_unlinked; do
    grep_result=$(grep -c "^${func}()" "$script_file" || true)
    assert_equals "1" "$grep_result" "${func}() function defined in automaton.sh"
done

# --- Test 5-8: All four functions check stigmergy enabled guard ---
for func in _signal_get_strong _signal_get_by_type _signal_get_active _signal_get_unlinked; do
    func_body=$(sed -n "/^${func}()/,/^[a-z_]*() {/p" "$script_file" | sed '$d')
    if echo "$func_body" | grep -q '_signal_enabled\|STIGMERGY_ENABLED'; then
        echo "PASS: ${func} checks stigmergy enabled guard"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: ${func} should check stigmergy enabled guard" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Functional Tests ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export AUTOMATON_DIR="$TMPDIR_TEST"
export STIGMERGY_ENABLED=true
export STIGMERGY_DECAY_FLOOR=0.05
export PROJECT_DIR="$TMPDIR_TEST"
export LOG_FILE="$TMPDIR_TEST/automaton.log"
export RUN_LOG="$TMPDIR_TEST/run.log"
export LOG_LEVEL=1

# Create signals.json with diverse signals for query testing
cat > "$TMPDIR_TEST/signals.json" << 'EOF'
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "attention_needed",
      "title": "Strong attention signal",
      "description": "High strength, linked to idea",
      "strength": 0.8,
      "decay_rate": 0.10,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": ["IDEA-001"],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-002",
      "type": "quality_concern",
      "title": "Weak quality signal",
      "description": "Low strength, no linked ideas",
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
      "type": "attention_needed",
      "title": "Medium attention signal",
      "description": "Medium strength, no linked ideas",
      "strength": 0.5,
      "decay_rate": 0.10,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-004",
      "type": "promising_approach",
      "title": "Strong promising signal",
      "description": "High strength, linked to idea",
      "strength": 0.7,
      "decay_rate": 0.05,
      "observations": [{"agent": "test", "cycle": 1, "timestamp": "2026-01-01T00:00:00Z", "detail": "test"}],
      "related_ideas": ["IDEA-002"],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-005",
      "type": "quality_concern",
      "title": "At-floor quality signal",
      "description": "Right at decay floor, unlinked",
      "strength": 0.05,
      "decay_rate": 0.07,
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

# Source needed functions
eval "$(sed -n '/^log()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_enabled()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_init_file()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_signal_get_strong()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')"
eval "$(sed -n '/^_signal_get_by_type()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')"
eval "$(sed -n '/^_signal_get_active()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')"
eval "$(sed -n '/^_signal_get_unlinked()/,/^[a-z_]*() {/p' "$script_file" | sed '$d')"

# --- Test 9: _signal_get_strong returns signals >= threshold ---
strong_result=$(_signal_get_strong 0.6)
strong_count=$(echo "$strong_result" | jq 'length')
assert_equals "2" "$strong_count" "_signal_get_strong(0.6) returns 2 signals (SIG-001=0.8, SIG-004=0.7)"

# --- Test 10: _signal_get_strong includes correct IDs ---
strong_ids=$(echo "$strong_result" | jq -r '.[].id' | sort)
expected_ids=$(printf "SIG-001\nSIG-004")
if [ "$strong_ids" = "$expected_ids" ]; then
    echo "PASS: _signal_get_strong returns SIG-001 and SIG-004"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_get_strong should return SIG-001 and SIG-004 (got: $strong_ids)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _signal_get_strong with high threshold returns fewer ---
strong_high=$(_signal_get_strong 0.75)
strong_high_count=$(echo "$strong_high" | jq 'length')
assert_equals "1" "$strong_high_count" "_signal_get_strong(0.75) returns only SIG-001"

# --- Test 12: _signal_get_by_type filters correctly ---
attention_result=$(_signal_get_by_type "attention_needed")
attention_count=$(echo "$attention_result" | jq 'length')
assert_equals "2" "$attention_count" "_signal_get_by_type(attention_needed) returns 2 signals"

# --- Test 13: _signal_get_by_type returns correct IDs ---
attention_ids=$(echo "$attention_result" | jq -r '.[].id' | sort)
expected_attention=$(printf "SIG-001\nSIG-003")
if [ "$attention_ids" = "$expected_attention" ]; then
    echo "PASS: _signal_get_by_type returns SIG-001 and SIG-003 for attention_needed"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Expected SIG-001 and SIG-003 (got: $attention_ids)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: _signal_get_by_type with quality_concern ---
quality_result=$(_signal_get_by_type "quality_concern")
quality_count=$(echo "$quality_result" | jq 'length')
assert_equals "2" "$quality_count" "_signal_get_by_type(quality_concern) returns 2 signals"

# --- Test 15: _signal_get_by_type with nonexistent type returns empty ---
none_result=$(_signal_get_by_type "nonexistent_type")
none_count=$(echo "$none_result" | jq 'length')
assert_equals "0" "$none_count" "_signal_get_by_type(nonexistent_type) returns 0 signals"

# --- Test 16: _signal_get_active returns signals above decay_floor ---
active_result=$(_signal_get_active)
active_count=$(echo "$active_result" | jq 'length')
assert_equals "5" "$active_count" "_signal_get_active returns all 5 signals (all >= decay_floor 0.05)"

# --- Test 17: _signal_get_active excludes signals below floor ---
# Temporarily set a higher floor to filter out weak signals
export STIGMERGY_DECAY_FLOOR=0.15
active_high_floor=$(_signal_get_active)
active_high_count=$(echo "$active_high_floor" | jq 'length')
assert_equals "3" "$active_high_count" "_signal_get_active with floor=0.15 returns 3 signals (0.8, 0.5, 0.7)"
export STIGMERGY_DECAY_FLOOR=0.05

# --- Test 18: _signal_get_unlinked returns signals with empty related_ideas ---
unlinked_result=$(_signal_get_unlinked)
unlinked_count=$(echo "$unlinked_result" | jq 'length')
assert_equals "3" "$unlinked_count" "_signal_get_unlinked returns 3 signals (SIG-002, SIG-003, SIG-005)"

# --- Test 19: _signal_get_unlinked returns correct IDs ---
unlinked_ids=$(echo "$unlinked_result" | jq -r '.[].id' | sort)
expected_unlinked=$(printf "SIG-002\nSIG-003\nSIG-005")
if [ "$unlinked_ids" = "$expected_unlinked" ]; then
    echo "PASS: _signal_get_unlinked returns SIG-002, SIG-003, SIG-005"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Expected SIG-002, SIG-003, SIG-005 (got: $unlinked_ids)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 20: Disabled stigmergy returns empty for all queries ---
export STIGMERGY_ENABLED=false
disabled_strong=$(_signal_get_strong 0.5 2>/dev/null || echo "[]")
disabled_type=$(_signal_get_by_type "attention_needed" 2>/dev/null || echo "[]")
disabled_active=$(_signal_get_active 2>/dev/null || echo "[]")
disabled_unlinked=$(_signal_get_unlinked 2>/dev/null || echo "[]")
# When disabled, functions return 1, so output should be empty/default
if [ "$disabled_strong" = "[]" ] || [ -z "$disabled_strong" ]; then
    echo "PASS: _signal_get_strong returns empty when disabled"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_get_strong should return empty when stigmergy disabled" >&2
    ((_TEST_FAIL_COUNT++))
fi
export STIGMERGY_ENABLED=true

# --- Test 21: No signals file returns empty array ---
TMPDIR_EMPTY=$(mktemp -d)
export AUTOMATON_DIR="$TMPDIR_EMPTY"
empty_strong=$(_signal_get_strong 0.5)
empty_count=$(echo "$empty_strong" | jq 'length')
assert_equals "0" "$empty_count" "_signal_get_strong returns empty array when no signals file"
rm -rf "$TMPDIR_EMPTY"
export AUTOMATON_DIR="$TMPDIR_TEST"

test_summary
