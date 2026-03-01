#!/usr/bin/env bash
# tests/test_garden_bloom.sh — Tests for _garden_get_bloom_candidates() (spec-38 §2)
# Verifies that bloom candidate retrieval returns sprout-stage ideas meeting
# evidence and priority thresholds, sorted by priority descending.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _garden_get_bloom_candidates function exists in automaton.sh ---
grep_result=$(grep -c '^_garden_get_bloom_candidates()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_get_bloom_candidates() function exists in automaton.sh"

# --- Test 2: Function references bloom threshold ---
func_body=$(sed -n '/^_garden_get_bloom_candidates()/,/^}/p' "$script_file")
assert_contains "$func_body" "GARDEN_BLOOM_THRESHOLD" "function checks bloom evidence threshold"

# --- Test 3: Function references bloom priority threshold ---
assert_contains "$func_body" "GARDEN_BLOOM_PRIORITY_THRESHOLD" "function checks bloom priority threshold"

# --- Test 4: Function sorts by priority ---
assert_contains "$func_body" "sort\|priority" "function sorts results by priority"

# --- Functional tests using temp garden ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":5,"by_stage":{"seed":1,"sprout":3,"bloom":0,"harvest":0,"wilt":1},"bloom_candidates":[],"recent_activity":[],"next_id":6,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Sprout with 4 evidence items, priority 50 — eligible
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'EOF'
{"id":"idea-001","title":"Optimize token usage","description":"desc","stage":"sprout","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[{"type":"metric","observation":"e1","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"metric","observation":"e2","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"metric","observation":"e3","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"signal","observation":"e4","added_by":"test","added_at":"2026-01-01T00:00:00Z"}],"tags":["performance"],"priority":50,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Sprout with 3 evidence items, priority 60 — eligible (higher priority)
cat > "$TMPDIR_TEST/garden/idea-002.json" << 'EOF'
{"id":"idea-002","title":"Improve cache ratio","description":"desc","stage":"sprout","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[{"type":"metric","observation":"e1","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"metric","observation":"e2","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"signal","observation":"e3","added_by":"test","added_at":"2026-01-01T00:00:00Z"}],"tags":["caching"],"priority":60,"estimated_complexity":"low","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Sprout with 1 evidence item, priority 45 — NOT eligible (below bloom_threshold of 3)
cat > "$TMPDIR_TEST/garden/idea-003.json" << 'EOF'
{"id":"idea-003","title":"Refactor logging","description":"desc","stage":"sprout","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[{"type":"metric","observation":"e1","added_by":"test","added_at":"2026-01-01T00:00:00Z"}],"tags":["quality"],"priority":45,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Seed with 3 evidence items, priority 70 — NOT eligible (wrong stage)
cat > "$TMPDIR_TEST/garden/idea-004.json" << 'EOF'
{"id":"idea-004","title":"Add metrics dashboard","description":"desc","stage":"seed","origin":{"type":"human","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[{"type":"metric","observation":"e1","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"metric","observation":"e2","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"signal","observation":"e3","added_by":"test","added_at":"2026-01-01T00:00:00Z"}],"tags":["metrics"],"priority":70,"estimated_complexity":"high","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Wilted sprout with sufficient evidence/priority — NOT eligible (wilted)
cat > "$TMPDIR_TEST/garden/idea-005.json" << 'EOF'
{"id":"idea-005","title":"Dead idea","description":"desc","stage":"wilt","origin":{"type":"metric","source":"test","created_by":"test","created_at":"2026-01-01T00:00:00Z"},"evidence":[{"type":"metric","observation":"e1","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"metric","observation":"e2","added_by":"test","added_at":"2026-01-01T00:00:00Z"},{"type":"signal","observation":"e3","added_by":"test","added_at":"2026-01-01T00:00:00Z"}],"tags":["dead"],"priority":80,"estimated_complexity":"low","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"test"},{"stage":"wilt","entered_at":"2026-01-01T01:00:00Z","reason":"expired"}],"vote_id":null,"implementation":null,"updated_at":"2026-01-01T01:00:00Z"}
EOF

# Extract the function for testing
log_func='log() { :; }'
bloom_code=$(sed -n '/^_garden_get_bloom_candidates()/,/^}/p' "$script_file")

# --- Test 5: Functional - returns eligible candidates ---
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=40
$bloom_code
_garden_get_bloom_candidates
" 2>&1) || true

assert_contains "$result" "idea-001" "includes eligible sprout idea-001 (4 evidence, priority 50)"
assert_contains "$result" "idea-002" "includes eligible sprout idea-002 (3 evidence, priority 60)"

# --- Test 6: Functional - does NOT include ideas below evidence threshold ---
if echo "$result" | grep -q 'idea-003'; then
    echo "FAIL: should NOT include idea-003 (only 1 evidence, below threshold 3)" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: correctly excludes idea-003 (insufficient evidence)"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 7: Functional - does NOT include seeds or wilted ---
if echo "$result" | grep -q 'idea-004'; then
    echo "FAIL: should NOT include idea-004 (seed stage, not sprout)" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: correctly excludes idea-004 (seed stage)"
    ((_TEST_PASS_COUNT++))
fi

if echo "$result" | grep -q 'idea-005'; then
    echo "FAIL: should NOT include idea-005 (wilted)" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: correctly excludes idea-005 (wilted)"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 8: Functional - sorted by priority descending (idea-002 first) ---
# idea-002 has priority 60, idea-001 has priority 50
first_line=$(echo "$result" | head -1)
if echo "$first_line" | grep -q 'idea-002'; then
    echo "PASS: highest priority idea-002 (60) comes first"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: expected idea-002 first (priority 60), got: $first_line" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Functional - returns nothing when no candidates exist ---
result_empty=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_BLOOM_THRESHOLD=10
GARDEN_BLOOM_PRIORITY_THRESHOLD=40
$bloom_code
_garden_get_bloom_candidates
" 2>&1)
exit_code=$?

if [ -z "$result_empty" ] && [ "$exit_code" -ne 0 ]; then
    echo "PASS: returns non-zero and no output when no candidates exist"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: should return non-zero with no output when no candidates (got exit=$exit_code, output='$result_empty')" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Functional - respects priority threshold ---
result_high_prio=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=55
$bloom_code
_garden_get_bloom_candidates
" 2>&1) || true

# Only idea-002 (priority 60) should pass the 55 threshold; idea-001 (priority 50) should not
assert_contains "$result_high_prio" "idea-002" "includes idea-002 when priority threshold is 55"

if echo "$result_high_prio" | grep -q 'idea-001'; then
    echo "FAIL: should NOT include idea-001 (priority 50 < threshold 55)" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: correctly excludes idea-001 when priority threshold is 55"
    ((_TEST_PASS_COUNT++))
fi

test_summary
