#!/usr/bin/env bash
# tests/test_signal_bootstrap.sh — Tests for spec-42 §3 active_signals in bootstrap manifest
# Verifies that .automaton/init.sh includes active_signals field sourced from signals.json
# with total, strong count, strongest signal, and unlinked_count fields.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

init_script="$SCRIPT_DIR/../.automaton/init.sh"

# --- Test 1: init.sh contains active_signals code path ---
grep_result=$(grep -c 'active_signals' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh contains active_signals code path"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should contain active_signals code path" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: init.sh reads from signals.json ---
grep_result=$(grep -c 'signals.json' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh reads signals.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should read signals.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Functional test — active_signals with populated signals ---
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/.automaton"
git -C "$tmpdir" init -q 2>/dev/null
touch "$tmpdir/README"
git -C "$tmpdir" add README
git -C "$tmpdir" commit -q -m "init" 2>/dev/null
touch "$tmpdir/file2"
git -C "$tmpdir" add file2
git -C "$tmpdir" commit -q -m "second" 2>/dev/null

# Create a populated signals.json with 3 signals (2 strong, 1 weak, 1 unlinked)
cat > "$tmpdir/.automaton/signals.json" <<'SIGEOF'
{
  "version": 1,
  "signals": [
    {
      "id": "SIG-001",
      "type": "performance_concern",
      "title": "High prompt overhead",
      "description": "Prompt assembly takes too long",
      "strength": 0.8,
      "decay_rate": 0.1,
      "observations": [{"agent": "build", "cycle": 1, "timestamp": "2026-03-01T10:00:00Z", "detail": ""}],
      "related_ideas": ["idea-003"],
      "created_at": "2026-03-01T10:00:00Z",
      "last_reinforced_at": "2026-03-01T10:00:00Z",
      "last_decayed_at": "2026-03-01T10:00:00Z"
    },
    {
      "id": "SIG-002",
      "type": "quality_concern",
      "title": "Test flakiness",
      "description": "Tests fail intermittently",
      "strength": 0.6,
      "decay_rate": 0.1,
      "observations": [{"agent": "review", "cycle": 2, "timestamp": "2026-03-01T11:00:00Z", "detail": ""}],
      "related_ideas": [],
      "created_at": "2026-03-01T11:00:00Z",
      "last_reinforced_at": "2026-03-01T11:00:00Z",
      "last_decayed_at": "2026-03-01T11:00:00Z"
    },
    {
      "id": "SIG-003",
      "type": "promising_approach",
      "title": "Cache hit improvement",
      "description": "Cache optimization working well",
      "strength": 0.2,
      "decay_rate": 0.05,
      "observations": [{"agent": "observe", "cycle": 3, "timestamp": "2026-03-01T12:00:00Z", "detail": ""}],
      "related_ideas": ["idea-005"],
      "created_at": "2026-03-01T12:00:00Z",
      "last_reinforced_at": "2026-03-01T12:00:00Z",
      "last_decayed_at": "2026-03-01T12:00:00Z"
    }
  ],
  "next_id": 4,
  "updated_at": "2026-03-01T12:00:00Z"
}
SIGEOF

manifest=$(bash "$init_script" "$tmpdir" "build" "1" 2>/dev/null)

# Check active_signals.total
val=$(echo "$manifest" | jq -r '.active_signals.total // empty')
assert_equals "3" "$val" "active_signals.total is 3"

# Check active_signals.strong (strength >= 0.5 by default)
val=$(echo "$manifest" | jq -r '.active_signals.strong // empty')
assert_equals "2" "$val" "active_signals.strong is 2"

# Check active_signals.strongest
val=$(echo "$manifest" | jq -r '.active_signals.strongest.id // empty')
assert_equals "SIG-001" "$val" "active_signals.strongest.id is SIG-001"

val=$(echo "$manifest" | jq -r '.active_signals.strongest.title // empty')
assert_equals "High prompt overhead" "$val" "active_signals.strongest.title is correct"

val=$(echo "$manifest" | jq -r '.active_signals.strongest.strength // empty')
assert_equals "0.8" "$val" "active_signals.strongest.strength is 0.8"

# Check active_signals.unlinked_count (SIG-002 has empty related_ideas)
val=$(echo "$manifest" | jq -r '.active_signals.unlinked_count // empty')
assert_equals "1" "$val" "active_signals.unlinked_count is 1"

# --- Test 4: Functional test — no signals.json means no active_signals ---
tmpdir2=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$tmpdir2"' EXIT
git -C "$tmpdir2" init -q 2>/dev/null
touch "$tmpdir2/README"
git -C "$tmpdir2" add README
git -C "$tmpdir2" commit -q -m "init" 2>/dev/null
touch "$tmpdir2/file2"
git -C "$tmpdir2" add file2
git -C "$tmpdir2" commit -q -m "second" 2>/dev/null

manifest2=$(bash "$init_script" "$tmpdir2" "build" "1" 2>/dev/null)
val=$(echo "$manifest2" | jq -r '.active_signals // "absent"')
assert_equals "absent" "$val" "No active_signals when signals.json absent"

# --- Test 5: Functional test — empty signals produces zeroed summary ---
tmpdir3=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$tmpdir2" "$tmpdir3"' EXIT
git -C "$tmpdir3" init -q 2>/dev/null
touch "$tmpdir3/README"
git -C "$tmpdir3" add README
git -C "$tmpdir3" commit -q -m "init" 2>/dev/null
touch "$tmpdir3/file2"
git -C "$tmpdir3" add file2
git -C "$tmpdir3" commit -q -m "second" 2>/dev/null
mkdir -p "$tmpdir3/.automaton"
cat > "$tmpdir3/.automaton/signals.json" <<'SIGEOF'
{"version":1,"signals":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
SIGEOF

manifest3=$(bash "$init_script" "$tmpdir3" "build" "1" 2>/dev/null)
val=$(echo "$manifest3" | jq -r '.active_signals.total // empty')
assert_equals "0" "$val" "active_signals.total is 0 for empty signals"

val=$(echo "$manifest3" | jq -r '.active_signals.strongest // "null"')
assert_equals "null" "$val" "active_signals.strongest is null for empty signals"

val=$(echo "$manifest3" | jq -r '.active_signals.unlinked_count // empty')
assert_equals "0" "$val" "active_signals.unlinked_count is 0 for empty signals"

test_summary
