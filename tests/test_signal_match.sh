#!/usr/bin/env bash
# tests/test_signal_match.sh — Tests for _signal_find_match() (spec-42 §1)
# Verifies word-overlap similarity matching: same-type signals with
# sufficient term overlap are matched, different types or low overlap are not.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _signal_find_match function exists ---
grep_result=$(grep -c '^_signal_find_match()' "$script_file" || true)
assert_equals "1" "$grep_result" "_signal_find_match() function defined in automaton.sh"

# --- Test 2: Function references match_threshold ---
match_body=$(sed -n '/^_signal_find_match()/,/^[a-z_]*() {/p' "$script_file")
if echo "$match_body" | grep -q 'STIGMERGY_MATCH_THRESHOLD\|match_threshold'; then
    echo "PASS: _signal_find_match uses match_threshold"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_find_match should reference match_threshold" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Function filters by type ---
if echo "$match_body" | grep -q 'type'; then
    echo "PASS: _signal_find_match filters by signal type"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _signal_find_match should filter by signal type" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Functional test — matching signal found ---
# Create a temp dir and signals.json, source relevant functions, test matching
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/signals.json" <<'EOF'
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "quality_concern",
      "title": "High prompt overhead in build phase",
      "description": "Build phase prompt_overhead_ratio consistently above 50%",
      "strength": 0.5,
      "decay_rate": 0.07,
      "observations": [],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    },
    {
      "id": "SIG-002",
      "type": "recurring_pattern",
      "title": "Build stalls at iteration seven",
      "description": "Build phase consistently stalls at iteration 7 or above",
      "strength": 0.6,
      "decay_rate": 0.05,
      "observations": [],
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

# Extract functions we need and test matching
# Source a minimal harness that defines the function + dependencies
cat > "$tmpdir/harness.sh" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$tmpdir"
STIGMERGY_ENABLED="true"
STIGMERGY_MATCH_THRESHOLD="0.6"
# Extract _signal_find_match and _signal_enabled from automaton.sh
$(sed -n '/^_signal_enabled()/,/^}/p' "$script_file")
$(sed -n '/^_signal_find_match()/,/^}/p' "$script_file")
HARNESS

# Test 4a: Same type, high overlap should match SIG-001
result=$(bash -c "source $tmpdir/harness.sh; _signal_find_match 'quality_concern' 'High prompt overhead in build phase' 'prompt_overhead_ratio above 50% in build'" 2>/dev/null || true)
if [ "$result" = "SIG-001" ]; then
    echo "PASS: High-overlap same-type signal matched SIG-001"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Expected SIG-001 for high-overlap same-type match, got '$result'" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Different type should not match ---
result=$(bash -c "source $tmpdir/harness.sh; _signal_find_match 'recurring_pattern' 'High prompt overhead in build phase' 'prompt overhead'" 2>/dev/null || true)
if [ -z "$result" ]; then
    echo "PASS: Different type does not match even with same title"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Expected no match for different type, got '$result'" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Low overlap should not match ---
result=$(bash -c "source $tmpdir/harness.sh; _signal_find_match 'quality_concern' 'Database connection timeout errors' 'database queries taking too long'" 2>/dev/null || true)
if [ -z "$result" ]; then
    echo "PASS: Low-overlap signal not matched"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Expected no match for low overlap, got '$result'" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Empty signals file returns no match ---
cat > "$tmpdir/signals_empty.json" <<'EOF'
{"version":1,"signals":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
EOF

cat > "$tmpdir/harness_empty.sh" <<HARNESS2
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$tmpdir"
STIGMERGY_ENABLED="true"
STIGMERGY_MATCH_THRESHOLD="0.6"
$(sed -n '/^_signal_enabled()/,/^}/p' "$script_file")

# Override signals file path
_signal_find_match_empty() {
    local signals_file="$tmpdir/signals_empty.json"
    local type="\$1" title="\$2" description="\$3"
    local threshold="\${STIGMERGY_MATCH_THRESHOLD:-0.6}"
    local count
    count=\$(jq -r '.signals | length' "\$signals_file")
    if [ "\$count" -eq 0 ]; then echo ""; return 0; fi
    echo ""
}
HARNESS2

result=$(bash -c "source $tmpdir/harness.sh; AUTOMATON_DIR=$tmpdir; cp $tmpdir/signals_empty.json $tmpdir/signals.json; _signal_find_match 'quality_concern' 'anything' 'anything'" 2>/dev/null || true)
# Restore original signals.json
cat > "$tmpdir/signals.json" <<'EOF2'
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "quality_concern",
      "title": "High prompt overhead in build phase",
      "description": "Build phase prompt_overhead_ratio consistently above 50%",
      "strength": 0.5,
      "decay_rate": 0.07,
      "observations": [],
      "related_ideas": [],
      "created_at": "2026-01-01T00:00:00Z",
      "last_reinforced_at": "2026-01-01T00:00:00Z",
      "last_decayed_at": "2026-01-01T00:00:00Z"
    }
  ],
  "next_id": 2,
  "updated_at": "2026-01-01T00:00:00Z"
}
EOF2

if [ -z "$result" ]; then
    echo "PASS: Empty signals file returns no match"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Expected no match for empty signals, got '$result'" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
