#!/usr/bin/env bash
# tests/test_signals_functional.sh — Functional tests for lib/signals.sh
# Tests signal emission, reinforcement, decay, matching, and pruning.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

_log_output=""
log() { _log_output+="[$1] $2"$'\n'; }

STIGMERGY_ENABLED="true"
STIGMERGY_INITIAL_STRENGTH="0.3"
STIGMERGY_MATCH_THRESHOLD="0.6"
STIGMERGY_PRUNE_BELOW="0.05"
STIGMERGY_MAX_SIGNALS=100

source "$_PROJECT_DIR/lib/signals.sh"

# --- Test: _signal_enabled ---

assert_equals "0" "$(_signal_enabled && echo 0 || echo 1)" "signals enabled when STIGMERGY_ENABLED=true"

STIGMERGY_ENABLED="false"
assert_equals "1" "$(_signal_enabled && echo 0 || echo 1)" "signals disabled when STIGMERGY_ENABLED=false"
STIGMERGY_ENABLED="true"

# --- Test: _signal_default_decay_rate ---

assert_equals "0.10" "$(_signal_default_decay_rate "attention_needed")" "decay rate for attention_needed"
assert_equals "0.05" "$(_signal_default_decay_rate "promising_approach")" "decay rate for promising_approach"
assert_equals "0.05" "$(_signal_default_decay_rate "recurring_pattern")" "decay rate for recurring_pattern"
assert_equals "0.08" "$(_signal_default_decay_rate "efficiency_opportunity")" "decay rate for efficiency_opportunity"
assert_equals "0.07" "$(_signal_default_decay_rate "quality_concern")" "decay rate for quality_concern"
assert_equals "0.05" "$(_signal_default_decay_rate "unknown_type")" "decay rate defaults to 0.05"

# --- Test: _signal_init_file creates signals.json ---

_signal_init_file
assert_file_exists "$AUTOMATON_DIR/signals.json" "init creates signals.json"

signals=$(cat "$AUTOMATON_DIR/signals.json")
assert_json_valid "$signals" "signals.json is valid JSON"
assert_json_field "$signals" '.version' "1" "signals version is 1"

sig_count=$(echo "$signals" | jq '.signals | length')
assert_equals "0" "$sig_count" "starts with empty signals array"

# --- Test: _signal_init_file doesn't overwrite existing ---

echo '{"version":1,"signals":[{"id":"SIG-001"}],"next_id":2,"updated_at":"test"}' > "$AUTOMATON_DIR/signals.json"
_signal_init_file
sig_count=$(jq '.signals | length' "$AUTOMATON_DIR/signals.json")
assert_equals "1" "$sig_count" "init preserves existing signals file"

# Reset for next tests
rm -f "$AUTOMATON_DIR/signals.json"

# --- Test: _signal_emit creates a new signal ---

signal_id=$(_signal_emit "attention_needed" "Test flakiness" "Tests are intermittently failing" "builder" "1" "")
assert_matches "$signal_id" '^SIG-[0-9]+$' "emit returns signal ID"

signals=$(cat "$AUTOMATON_DIR/signals.json")
sig_count=$(echo "$signals" | jq '.signals | length')
assert_equals "1" "$sig_count" "emit creates one signal"

sig=$(echo "$signals" | jq '.signals[0]')
assert_json_field "$sig" '.type' "attention_needed" "signal has correct type"
assert_json_field "$sig" '.title' "Test flakiness" "signal has correct title"
assert_json_field "$sig" '.description' "Tests are intermittently failing" "signal has correct description"
assert_json_field "$sig" '.id' "$signal_id" "signal ID matches returned ID"

strength=$(echo "$sig" | jq -r '.strength')
assert_equals "0.3" "$strength" "signal has initial strength"

# --- Test: _signal_emit with different types ---

signal_id2=$(_signal_emit "quality_concern" "Code coverage low" "Only 45% coverage" "reviewer" "2" "")
signals=$(cat "$AUTOMATON_DIR/signals.json")
sig_count=$(echo "$signals" | jq '.signals | length')
assert_equals "2" "$sig_count" "second emit creates second signal"

# --- Test: _signal_emit when disabled returns error ---

STIGMERGY_ENABLED="false"
rc=0
_signal_emit "attention_needed" "Test" "Desc" "agent" "1" "" || rc=$?
assert_equals "1" "$rc" "emit returns 1 when disabled"
STIGMERGY_ENABLED="true"

# --- Test: _signal_get_active returns all signals ---

result=$(_signal_get_active)
assert_json_valid "$result" "get_active returns valid JSON"

query_count=$(echo "$result" | jq 'length')
assert_equals "2" "$query_count" "get_active returns all signals"

# --- Test: _signal_get_by_type filters ---

result=$(_signal_get_by_type "quality_concern")
query_count=$(echo "$result" | jq 'length')
assert_equals "1" "$query_count" "get_by_type filters correctly"
assert_json_field "$(echo "$result" | jq '.[0]')" '.title' "Code coverage low" "filtered signal has correct title"

# --- Test: _signal_decay_all reduces strength ---

# Get current strength
before=$(jq '.signals[0].strength' "$AUTOMATON_DIR/signals.json")

_signal_decay_all || true

after=$(jq '.signals[0].strength' "$AUTOMATON_DIR/signals.json")

# After decay, strength should be lower
if awk -v b="$before" -v a="$after" 'BEGIN { exit !(a < b) }'; then
    echo "PASS: decay reduces signal strength"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: decay did not reduce strength (before=$before, after=$after)"
    ((_TEST_FAIL_COUNT++))
fi

# --- Test: _signal_decay_all removes signals below floor ---

# Set one signal strength to just above decay_rate so next decay drops below floor
# Floor is 0.05, decay_rate for attention_needed is 0.10
jq '.signals[0].strength = 0.06 | .signals[0].decay_rate = 0.10 | .signals[1].strength = 0.5 | .signals[1].decay_rate = 0.05' \
    "$AUTOMATON_DIR/signals.json" > "$AUTOMATON_DIR/signals.json.tmp"
mv "$AUTOMATON_DIR/signals.json.tmp" "$AUTOMATON_DIR/signals.json"

STIGMERGY_DECAY_FLOOR="0.05"
_signal_decay_all || true

signals=$(cat "$AUTOMATON_DIR/signals.json")
sig_count=$(echo "$signals" | jq '.signals | length')
assert_equals "1" "$sig_count" "decay_all removes signal that falls below floor"

# The remaining signal should be the quality_concern one
remaining=$(echo "$signals" | jq -r '.signals[0].type')
assert_equals "quality_concern" "$remaining" "decay_all keeps signal above floor"

# --- Test: _signal_prune when under max ---

rc=0
_signal_prune || rc=$?
assert_equals "0" "$rc" "prune is no-op when under max_signals"

test_summary
