#!/usr/bin/env bash
# tests/test_constitution_bootstrap.sh — Tests for spec-40 §3 constitution_summary in bootstrap manifest
# Verifies that .automaton/init.sh includes constitution_summary field sourced from
# constitution.md and constitution-history.json with articles, version, and key_constraints.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

init_script="$SCRIPT_DIR/../.automaton/init.sh"

# --- Test 1: init.sh contains constitution_summary code path ---
grep_result=$(grep -c 'constitution_summary' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh contains constitution_summary code path"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should contain constitution_summary code path" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 2: init.sh reads from constitution.md ---
grep_result=$(grep -c 'constitution.md' "$init_script" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: init.sh reads constitution.md"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: init.sh should read constitution.md" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Functional test — constitution_summary with default constitution ---
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

# Create a constitution.md with 8 articles
cat > "$tmpdir/.automaton/constitution.md" <<'CONSTEOF'
# Automaton Constitution

### Article I — Safety First
Protection: unanimous
All safety mechanisms must be preserved.

### Article II — Human Sovereignty
Protection: unanimous
The human retains ultimate override authority.

### Article III — Measurable Progress
Protection: supermajority
Every change must target a measurable metric.

### Article IV — Transparency
Protection: majority
All decisions must be logged and auditable.

### Article V — Budget Discipline
Protection: supermajority
Spending must stay within configured limits.

### Article VI — Incremental Growth
Protection: majority
Each cycle implements at most 1 idea.

### Article VII — Test Coverage
Protection: supermajority
No change may reduce test pass rate.

### Article VIII — Amendment Protocol
Protection: unanimous
This article cannot be removed or weakened.
CONSTEOF

# Create constitution-history.json with version 1
cat > "$tmpdir/.automaton/constitution-history.json" <<'HISTEOF'
{
  "current_version": 1,
  "amendments": []
}
HISTEOF

manifest=$(bash "$init_script" "$tmpdir" "build" "1" 2>/dev/null)

# Check constitution_summary.articles
val=$(echo "$manifest" | jq -r '.constitution_summary.articles // empty')
assert_equals "8" "$val" "constitution_summary.articles is 8"

# Check constitution_summary.version
val=$(echo "$manifest" | jq -r '.constitution_summary.version // empty')
assert_equals "1" "$val" "constitution_summary.version is 1"

# Check constitution_summary.key_constraints is an array with items
val=$(echo "$manifest" | jq -r '.constitution_summary.key_constraints | length // empty')
assert_equals "4" "$val" "constitution_summary.key_constraints has 4 items"

# Check specific constraint content
val=$(echo "$manifest" | jq -r '.constitution_summary.key_constraints[0] // empty')
if echo "$val" | grep -q "Safety"; then
    echo "PASS: First key_constraint mentions Safety"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: First key_constraint should mention Safety, got: $val" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Functional test — no constitution means no constitution_summary ---
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
val=$(echo "$manifest2" | jq -r '.constitution_summary // "absent"')
assert_equals "absent" "$val" "No constitution_summary when constitution.md absent"

# --- Test 5: Functional test — constitution with amendments has higher version ---
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

# Constitution with 8 articles
cat > "$tmpdir3/.automaton/constitution.md" <<'CONSTEOF'
# Automaton Constitution

### Article I — Safety First
Protection: unanimous
All safety mechanisms must be preserved.

### Article II — Human Sovereignty
Protection: unanimous
The human retains ultimate override authority.

### Article III — Measurable Progress
Protection: supermajority
Every change must target a measurable metric.

### Article IV — Transparency
Protection: majority
All decisions must be logged and auditable.

### Article V — Budget Discipline
Protection: supermajority
Spending must stay within configured limits.

### Article VI — Incremental Growth
Protection: majority
Each cycle implements at most 1 idea.

### Article VII — Test Coverage
Protection: supermajority
No change may reduce test pass rate.

### Article VIII — Amendment Protocol
Protection: unanimous
This article cannot be removed or weakened.
CONSTEOF

# Version 3 after amendments
cat > "$tmpdir3/.automaton/constitution-history.json" <<'HISTEOF'
{
  "current_version": 3,
  "amendments": [
    {"amendment_id": 1, "article": "IV"},
    {"amendment_id": 2, "article": "V"}
  ]
}
HISTEOF

manifest3=$(bash "$init_script" "$tmpdir3" "build" "1" 2>/dev/null)
val=$(echo "$manifest3" | jq -r '.constitution_summary.version // empty')
assert_equals "3" "$val" "constitution_summary.version is 3 after amendments"

val=$(echo "$manifest3" | jq -r '.constitution_summary.articles // empty')
assert_equals "8" "$val" "constitution_summary.articles is still 8"

test_summary
