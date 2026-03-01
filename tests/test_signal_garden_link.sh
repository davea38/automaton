#!/usr/bin/env bash
# tests/test_signal_garden_link.sh — Tests for bidirectional signal-garden linking (spec-42 §3)
# Verifies that signals and garden ideas can be linked bidirectionally:
# - _signal_link_idea() adds an idea ID to a signal's related_ideas
# - _garden_link_signal() adds a signal ID to an idea's related_signals
# - _signal_garden_link() does both in one call

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _signal_link_idea function exists ---
grep_result=$(grep -c '^_signal_link_idea()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_link_idea() function defined in automaton.sh"

# --- Test 2: _garden_link_signal function exists ---
grep_result=$(grep -c '^_garden_link_signal()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_link_signal() function defined in automaton.sh"

# --- Test 3: _signal_garden_link function exists ---
grep_result=$(grep -c '^_signal_garden_link()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_garden_link() function defined in automaton.sh"

# --- Test 4: _signal_link_idea accepts signal_id and idea_id ---
link_body=$(sed -n '/^_signal_link_idea()/,/^[a-z_]*() {/p' "$script_file" | head -10)
params_found=0
for param in "signal_id" "idea_id"; do
    if echo "$link_body" | grep -q "$param"; then
        ((params_found++))
    fi
done
if [ "$params_found" -ge 2 ]; then
    echo "PASS: _signal_link_idea accepts signal_id and idea_id"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_link_idea should accept signal_id and idea_id (found $params_found/2)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: _garden_link_signal accepts idea_id and signal_id ---
link_body=$(sed -n '/^_garden_link_signal()/,/^[a-z_]*() {/p' "$script_file" | head -10)
params_found=0
for param in "idea_id" "signal_id"; do
    if echo "$link_body" | grep -q "$param"; then
        ((params_found++))
    fi
done
if [ "$params_found" -ge 2 ]; then
    echo "PASS: _garden_link_signal accepts idea_id and signal_id"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _garden_link_signal should accept idea_id and signal_id (found $params_found/2)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: _signal_link_idea updates related_ideas in signals.json ---
link_func=$(sed -n '/^_signal_link_idea()/,/^[a-z_]*() {/p' "$script_file")
if echo "$link_func" | grep -q 'related_ideas'; then
    echo "PASS: _signal_link_idea modifies related_ideas"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_link_idea should modify related_ideas" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: _garden_link_signal updates related_signals in idea file ---
link_func=$(sed -n '/^_garden_link_signal()/,/^[a-z_]*() {/p' "$script_file")
if echo "$link_func" | grep -q 'related_signals'; then
    echo "PASS: _garden_link_signal modifies related_signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _garden_link_signal should modify related_signals" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: _signal_link_idea checks for duplicates (avoids adding same idea twice) ---
if echo "$link_func" | grep -q 'select\|contains\|index\|unique\|duplicate'; then
    echo "PASS: Duplicate prevention present in linking function"
    ((_TEST_PASS_COUNT++))
else
    # Check _signal_link_idea instead
    link_func2=$(sed -n '/^_signal_link_idea()/,/^[a-z_]*() {/p' "$script_file")
    if echo "$link_func2" | grep -q 'select\|contains\|index\|unique\|duplicate'; then
        echo "PASS: Duplicate prevention present in _signal_link_idea"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: Linking functions should prevent duplicate entries" >&2
        ((_TEST_FAIL_COUNT++))
    fi
fi

# --- Test 9: _signal_garden_link calls both _signal_link_idea and _garden_link_signal ---
bidir_func=$(sed -n '/^_signal_garden_link()/,/^[a-z_]*() {/p' "$script_file")
calls_found=0
if echo "$bidir_func" | grep -q '_signal_link_idea'; then
    ((calls_found++))
fi
if echo "$bidir_func" | grep -q '_garden_link_signal'; then
    ((calls_found++))
fi
if [ "$calls_found" -ge 2 ]; then
    echo "PASS: _signal_garden_link calls both linking functions"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_garden_link should call both _signal_link_idea and _garden_link_signal (found $calls_found/2)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: _signal_link_idea checks stigmergy enabled ---
link_func=$(sed -n '/^_signal_link_idea()/,/^[a-z_]*() {/p' "$script_file")
if echo "$link_func" | grep -q '_signal_enabled\|STIGMERGY_ENABLED'; then
    echo "PASS: _signal_link_idea checks stigmergy enabled"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_link_idea should check stigmergy enabled guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: _garden_link_signal checks garden enabled ---
link_func=$(sed -n '/^_garden_link_signal()/,/^[a-z_]*() {/p' "$script_file")
if echo "$link_func" | grep -q 'GARDEN_ENABLED'; then
    echo "PASS: _garden_link_signal checks garden enabled"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _garden_link_signal should check garden enabled guard" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Functional tests: Actually exercise the linking logic ---
# Set up a temp directory for functional testing
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Source automaton.sh to get access to functions
export AUTOMATON_DIR="$TEST_DIR"
export AUTOMATON_LOG="$TEST_DIR/test.log"
export GARDEN_ENABLED="true"
export STIGMERGY_ENABLED="true"
export STIGMERGY_INITIAL_STRENGTH="0.3"
export STIGMERGY_MATCH_THRESHOLD="0.6"

# Source just the functions we need (create a minimal environment)
# We need log(), _signal_init_file(), and related functions
eval "$(sed -n '/^log()/,/^[a-z_]*() {/p' "$script_file" | head -n -1)"
eval "$(sed -n '/^_signal_enabled()/,/^[a-z_]*() {/p' "$script_file" | head -n -1)"
eval "$(sed -n '/^_signal_init_file()/,/^[a-z_]*() {/p' "$script_file" | head -n -1)"
eval "$(sed -n '/^_signal_link_idea()/,/^[a-z_]*() {/p' "$script_file" | head -n -1)"
eval "$(sed -n '/^_garden_link_signal()/,/^[a-z_]*() {/p' "$script_file" | head -n -1)"
eval "$(sed -n '/^_signal_garden_link()/,/^[a-z_]*() {/p' "$script_file" | head -n -1)"

# --- Test 12: Functional test — _signal_link_idea adds idea to signal ---
mkdir -p "$TEST_DIR/garden"
# Create a minimal signals.json
cat > "$TEST_DIR/signals.json" << 'EOF'
{"signals":[{"id":"SIG-001","type":"recurring_pattern","title":"Test Signal","description":"A test signal","strength":0.5,"decay_rate":0.1,"observations":[],"related_ideas":[],"created_at":"2026-01-01T00:00:00Z","last_reinforced_at":"2026-01-01T00:00:00Z","last_decayed_at":"2026-01-01T00:00:00Z"}],"next_id":2,"updated_at":"2026-01-01T00:00:00Z"}
EOF

_signal_link_idea "SIG-001" "idea-001" 2>/dev/null
related=$(jq -r '.signals[0].related_ideas[0]' "$TEST_DIR/signals.json")
assert_equals "idea-001" "$related" "_signal_link_idea adds idea ID to signal's related_ideas"

# --- Test 13: Functional test — _signal_link_idea avoids duplicates ---
_signal_link_idea "SIG-001" "idea-001" 2>/dev/null
count=$(jq '.signals[0].related_ideas | length' "$TEST_DIR/signals.json")
assert_equals "1" "$count" "_signal_link_idea does not duplicate existing idea link"

# --- Test 14: Functional test — _garden_link_signal adds signal to idea ---
cat > "$TEST_DIR/garden/idea-001.json" << 'EOF'
{"id":"idea-001","title":"Test Idea","related_signals":[],"updated_at":"2026-01-01T00:00:00Z"}
EOF

_garden_link_signal "idea-001" "SIG-001" 2>/dev/null
related=$(jq -r '.related_signals[0]' "$TEST_DIR/garden/idea-001.json")
assert_equals "SIG-001" "$related" "_garden_link_signal adds signal ID to idea's related_signals"

# --- Test 15: Functional test — _garden_link_signal avoids duplicates ---
_garden_link_signal "idea-001" "SIG-001" 2>/dev/null
count=$(jq '.related_signals | length' "$TEST_DIR/garden/idea-001.json")
assert_equals "1" "$count" "_garden_link_signal does not duplicate existing signal link"

# --- Test 16: Functional test — _signal_garden_link creates bidirectional link ---
# Reset state
cat > "$TEST_DIR/signals.json" << 'EOF'
{"signals":[{"id":"SIG-002","type":"attention_needed","title":"Another Signal","description":"Another test","strength":0.4,"decay_rate":0.1,"observations":[],"related_ideas":[],"created_at":"2026-01-01T00:00:00Z","last_reinforced_at":"2026-01-01T00:00:00Z","last_decayed_at":"2026-01-01T00:00:00Z"}],"next_id":3,"updated_at":"2026-01-01T00:00:00Z"}
EOF
cat > "$TEST_DIR/garden/idea-002.json" << 'EOF'
{"id":"idea-002","title":"Another Idea","related_signals":[],"updated_at":"2026-01-01T00:00:00Z"}
EOF

_signal_garden_link "SIG-002" "idea-002" 2>/dev/null
sig_linked=$(jq -r '.signals[0].related_ideas[0]' "$TEST_DIR/signals.json")
idea_linked=$(jq -r '.related_signals[0]' "$TEST_DIR/garden/idea-002.json")
assert_equals "idea-002" "$sig_linked" "_signal_garden_link updates signal's related_ideas"
assert_equals "SIG-002" "$idea_linked" "_signal_garden_link updates idea's related_signals"

test_summary
