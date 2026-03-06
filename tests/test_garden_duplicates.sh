#!/usr/bin/env bash
# tests/test_garden_duplicates.sh — Tests for _garden_find_duplicates() (spec-38 §2)
# Verifies that duplicate detection checks for existing non-wilted ideas with
# matching tags before creating a new seed, returning the existing idea ID if found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _garden_find_duplicates function exists in automaton.sh ---
grep_result=$(grep -c '^_garden_find_duplicates()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_find_duplicates() function exists in automaton.sh"

# --- Test 2: Function accepts tags parameter ---
func_body=$(grep -A 40 '^_garden_find_duplicates()' "$script_file")
assert_contains "$func_body" "tags" "function accepts tags parameter"

# --- Test 3: Function checks idea stage (filters out wilted) ---
assert_contains "$func_body" "wilt" "function filters wilted ideas"

# --- Test 4: Function reads from garden directory ---
assert_contains "$func_body" "garden" "function references garden directory"

# --- Test 5: Function outputs idea ID on match ---
if echo "$func_body" | grep -q 'echo.*idea\|printf.*idea\|idea_id'; then
    echo "PASS: function outputs matching idea ID"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should output matching idea ID" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Functional tests using temp garden ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":3,"by_stage":{"seed":1,"sprout":1,"bloom":0,"harvest":0,"wilt":1},"bloom_candidates":[],"recent_activity":[],"next_id":4,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Create a seed idea with tags: performance, prompts
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'EOF'
{"id":"idea-001","title":"Reduce prompt overhead","description":"desc","stage":"seed","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[],"tags":["performance","prompts"],"priority":0,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a sprout idea with tags: quality, tests
cat > "$TMPDIR_TEST/garden/idea-002.json" << 'EOF'
{"id":"idea-002","title":"Improve test coverage","description":"desc","stage":"sprout","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[],"tags":["quality","tests"],"priority":10,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a wilted idea with tags: performance, prompts (should be ignored)
cat > "$TMPDIR_TEST/garden/idea-003.json" << 'EOF'
{"id":"idea-003","title":"Old prompt idea","description":"desc","stage":"wilt","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[],"tags":["performance","prompts"],"priority":0,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"},{"stage":"wilt","entered_at":"2026-01-01T01:00:00Z","reason":"expired"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T01:00:00Z"}
EOF

# Extract the function for testing
log_func='log() { :; }'
find_dup_code=$(sed -n '/^_garden_find_duplicates()/,/^}/p' "$script_file")

# --- Test 6: Functional - finds existing seed with matching tags ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$find_dup_code
_garden_find_duplicates 'performance,prompts'
" 2>&1) || true

if echo "$result" | grep -q 'idea-001'; then
    echo "PASS: found existing idea-001 with matching tags performance,prompts"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should find idea-001 with matching tags (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Functional - finds existing sprout with matching tags ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$find_dup_code
_garden_find_duplicates 'quality,tests'
" 2>&1) || true

if echo "$result" | grep -q 'idea-002'; then
    echo "PASS: found existing idea-002 with matching tags quality,tests"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should find idea-002 with matching tags (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Functional - does NOT match wilted ideas ---
# Remove the seed so only the wilted one has performance,prompts
rm -f "$TMPDIR_TEST/garden/idea-001.json"
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$find_dup_code
_garden_find_duplicates 'performance,prompts'
" 2>&1) || true

if echo "$result" | grep -q 'idea-003'; then
    echo "FAIL: should NOT match wilted idea-003" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: correctly ignores wilted idea-003"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 9: Functional - returns empty/non-zero for no match ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$find_dup_code
_garden_find_duplicates 'nonexistent,tags'
" 2>&1)
exit_code=$?

if [ -z "$result" ] || ! echo "$result" | grep -q 'idea-'; then
    echo "PASS: returns empty/no idea when no match found"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should return empty when no match found (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Functional - partial tag overlap also matches ---
# Restore idea-001
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'EOF'
{"id":"idea-001","title":"Reduce prompt overhead","description":"desc","stage":"seed","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[],"tags":["performance","prompts"],"priority":0,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Search with tags that include one matching and one new — should match if any tag overlaps
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$find_dup_code
_garden_find_duplicates 'performance,newstuff'
" 2>&1) || true

if echo "$result" | grep -q 'idea-001'; then
    echo "PASS: partial tag overlap matches idea-001"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: partial tag overlap should match (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Functional - works with empty garden ---
rm -f "$TMPDIR_TEST/garden/idea-"*.json
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
$find_dup_code
_garden_find_duplicates 'performance,prompts'
" 2>&1) || true

if [ -z "$result" ] || ! echo "$result" | grep -q 'idea-'; then
    echo "PASS: handles empty garden gracefully"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should handle empty garden (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
