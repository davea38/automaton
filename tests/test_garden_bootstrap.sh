#!/usr/bin/env bash
# tests/test_garden_bootstrap.sh — Tests for spec-38 §3 garden_summary in bootstrap manifest
# Verifies that .automaton/init.sh includes garden_summary field sourced from _index.json
# with total, seeds, sprouts, blooms, and top_bloom fields.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

init_script="$SCRIPT_DIR/../.automaton/init.sh"

# --- Test 1: init.sh contains garden_summary code path ---
grep_result=$(grep -c 'garden_summary' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh contains garden_summary code path"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should contain garden_summary code path" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: init.sh reads from _index.json for garden data ---
grep_result=$(grep -c '_index.json' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh reads _index.json for garden data"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should read _index.json for garden data" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Functional test — garden_summary with populated garden ---
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Create the project directory structure (2 commits needed for HEAD~1 in init.sh)
mkdir -p "$tmpdir/.automaton/garden"
git -C "$tmpdir" init -q 2>/dev/null
touch "$tmpdir/README"
git -C "$tmpdir" add README
git -C "$tmpdir" commit -q -m "init" 2>/dev/null
touch "$tmpdir/file2"
git -C "$tmpdir" add file2
git -C "$tmpdir" commit -q -m "second" 2>/dev/null

# Create a populated _index.json
cat > "$tmpdir/.automaton/garden/_index.json" <<'IDXEOF'
{
  "total": 5,
  "by_stage": {
    "seed": 2,
    "sprout": 1,
    "bloom": 1,
    "harvest": 1,
    "wilt": 0
  },
  "bloom_candidates": [
    {"id": "idea-003", "title": "Reduce prompt overhead", "priority": 72}
  ],
  "recent_activity": [],
  "next_id": 6,
  "updated_at": "2026-03-01T10:00:00Z"
}
IDXEOF

# Run init.sh and capture output
manifest=$(bash "$init_script" "$tmpdir" "build" "1" 2>/dev/null)

# Check garden_summary.total
val=$(echo "$manifest" | jq -r '.garden_summary.total // empty')
assert_equals "5" "$val" "garden_summary.total is 5"

# Check garden_summary.seeds
val=$(echo "$manifest" | jq -r '.garden_summary.seeds // empty')
assert_equals "2" "$val" "garden_summary.seeds is 2"

# Check garden_summary.sprouts
val=$(echo "$manifest" | jq -r '.garden_summary.sprouts // empty')
assert_equals "1" "$val" "garden_summary.sprouts is 1"

# Check garden_summary.blooms
val=$(echo "$manifest" | jq -r '.garden_summary.blooms // empty')
assert_equals "1" "$val" "garden_summary.blooms is 1"

# Check garden_summary.top_bloom
val=$(echo "$manifest" | jq -r '.garden_summary.top_bloom.id // empty')
assert_equals "idea-003" "$val" "garden_summary.top_bloom.id is idea-003"

val=$(echo "$manifest" | jq -r '.garden_summary.top_bloom.title // empty')
assert_equals "Reduce prompt overhead" "$val" "garden_summary.top_bloom.title is correct"

val=$(echo "$manifest" | jq -r '.garden_summary.top_bloom.priority // empty')
assert_equals "72" "$val" "garden_summary.top_bloom.priority is 72"

# --- Test 4: Functional test — no garden dir means no garden_summary ---
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
val=$(echo "$manifest2" | jq -r '.garden_summary // "absent"')
assert_equals "absent" "$val" "No garden_summary when garden dir absent"

# --- Test 5: Functional test — empty garden produces zeroed summary ---
tmpdir3=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$tmpdir2" "$tmpdir3"' EXIT
git -C "$tmpdir3" init -q 2>/dev/null
touch "$tmpdir3/README"
git -C "$tmpdir3" add README
git -C "$tmpdir3" commit -q -m "init" 2>/dev/null
touch "$tmpdir3/file2"
git -C "$tmpdir3" add file2
git -C "$tmpdir3" commit -q -m "second" 2>/dev/null
mkdir -p "$tmpdir3/.automaton/garden"
cat > "$tmpdir3/.automaton/garden/_index.json" <<'IDXEOF'
{
  "total": 0,
  "by_stage": {"seed": 0, "sprout": 0, "bloom": 0, "harvest": 0, "wilt": 0},
  "bloom_candidates": [],
  "recent_activity": [],
  "next_id": 1,
  "updated_at": ""
}
IDXEOF

manifest3=$(bash "$init_script" "$tmpdir3" "build" "1" 2>/dev/null)
val=$(echo "$manifest3" | jq -r '.garden_summary.total // empty')
assert_equals "0" "$val" "garden_summary.total is 0 for empty garden"

val=$(echo "$manifest3" | jq -r '.garden_summary.top_bloom // "null"')
assert_equals "null" "$val" "garden_summary.top_bloom is null for empty garden"

test_summary
