#!/usr/bin/env bash
# tests/test_garden_plant.sh — Tests for _garden_plant_seed() (spec-38 §1)
# Verifies that planting a seed creates a valid idea JSON file in .automaton/garden/
# with the complete schema, auto-increments the ID from _index.json, and updates the index.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _garden_plant_seed function exists in automaton.sh ---
grep_result=$(grep -c '^_garden_plant_seed()' "$script_file" || true)
assert_equals "1" "$grep_result" "_garden_plant_seed() function exists in automaton.sh"

# --- Test 2: Function creates idea JSON file with correct filename pattern ---
# Check that the function writes to .automaton/garden/idea-NNN.json
grep_result=$(grep -c 'idea-.*\.json' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: function references idea-NNN.json filename pattern"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should reference idea-NNN.json filename pattern" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Function reads next_id from _index.json ---
grep_result=$(grep -c 'next_id' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: function uses next_id from index"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should use next_id from _index.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Function sets stage to 'seed' ---
assert_contains "$(grep '_garden_plant_seed' "$script_file" -A 80)" '"seed"' "function sets initial stage to seed"

# --- Test 5: Function includes all required schema fields ---
# Check for key schema fields in the jq template used by _garden_plant_seed
# Use grep -A to capture enough of the function body (includes the jq template)
func_body=$(grep -A 120 '^_garden_plant_seed()' "$script_file")
for field in title description stage origin evidence tags priority estimated_complexity related_specs related_signals related_ideas stage_history vote_id implementation updated_at; do
    if echo "$func_body" | grep -q "$field"; then
        echo "PASS: function includes field '$field'"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: function should include schema field '$field'" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Test 6: Function auto-increments ID ---
# The function should increment next_id after creating the idea
assert_contains "$(grep -A 80 '_garden_plant_seed()' "$script_file")" "next_id" "function handles next_id for auto-increment"

# --- Test 7: Function accepts title, description, origin_type, origin_source, created_by as parameters ---
# Check that function processes input parameters
func_header=$(grep -A 5 '_garden_plant_seed()' "$script_file")
assert_contains "$func_header" "title" "function accepts title parameter"

# --- Test 8: Function calls _garden_rebuild_index or updates the index ---
func_full=$(grep -A 120 '^_garden_plant_seed()' "$script_file")
if echo "$func_full" | grep -q '_garden_rebuild_index\|_index.json'; then
    echo "PASS: function updates the garden index"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should update the garden index after planting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Function outputs the new idea ID ---
if echo "$func_full" | grep -q 'echo.*idea\|printf.*idea'; then
    echo "PASS: function outputs the new idea ID"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should output the new idea ID" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Function sets priority to 0 for new seeds ---
assert_contains "$func_full" "priority" "function sets initial priority"

# --- Functional test: Create a temp garden dir and test planting ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create minimal garden dir and index
mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/_index.json" << 'INDEXEOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"2026-01-01T00:00:00Z"}
INDEXEOF

# Source just the function we need (extract it)
# We test by calling the function with AUTOMATON_DIR set to our temp dir
export AUTOMATON_DIR="$TMPDIR_TEST"

# Extract and source garden functions
func_code=$(sed -n '/^_garden_plant_seed()/,/^}/p' "$script_file")
rebuild_code=$(sed -n '/^_garden_rebuild_index()/,/^}/p' "$script_file")
log_func='log() { :; }'

# Source helper + function in a subshell for safety
result=$(bash -c "
$log_func
AUTOMATON_DIR='$TMPDIR_TEST'
GARDEN_BLOOM_THRESHOLD=3
$rebuild_code
$func_code
_garden_plant_seed 'Test idea title' 'Test idea description' 'human' 'manual entry' 'test-user' 'low' 'testing,ideas'
" 2>&1) || true

# --- Test 11: Functional - idea file was created ---
if ls "$TMPDIR_TEST/garden/idea-001.json" 2>/dev/null; then
    echo "PASS: idea-001.json was created"
    ((_TEST_PASS_COUNT++))

    # --- Test 12: Functional - idea file has correct title ---
    file_title=$(jq -r '.title' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "Test idea title" "$file_title" "idea file has correct title"

    # --- Test 13: Functional - idea file has stage=seed ---
    file_stage=$(jq -r '.stage' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "seed" "$file_stage" "idea file has stage=seed"

    # --- Test 14: Functional - idea file has correct origin.type ---
    file_origin_type=$(jq -r '.origin.type' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "human" "$file_origin_type" "idea file has correct origin.type"

    # --- Test 15: Functional - idea file has empty evidence array ---
    evidence_count=$(jq '.evidence | length' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "0" "$evidence_count" "idea file has empty evidence array"

    # --- Test 16: Functional - idea file has priority=0 ---
    file_priority=$(jq -r '.priority' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "0" "$file_priority" "idea file has priority=0"

    # --- Test 17: Functional - idea file has id=idea-001 ---
    file_id=$(jq -r '.id' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "idea-001" "$file_id" "idea file has id=idea-001"

    # --- Test 18: Functional - idea file has stage_history with seed entry ---
    stage_history_len=$(jq '.stage_history | length' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "1" "$stage_history_len" "idea file has one stage_history entry"

    # --- Test 19: Functional - stage_history[0].stage is seed ---
    first_stage=$(jq -r '.stage_history[0].stage' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "seed" "$first_stage" "stage_history[0].stage is seed"

    # --- Test 20: Functional - vote_id is null ---
    vote_id=$(jq -r '.vote_id' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "null" "$vote_id" "vote_id is null for new seed"

    # --- Test 21: Functional - implementation is null ---
    impl=$(jq -r '.implementation' "$TMPDIR_TEST/garden/idea-001.json")
    assert_equals "null" "$impl" "implementation is null for new seed"
else
    echo "FAIL: idea-001.json was not created" >&2
    ((_TEST_FAIL_COUNT++))
    # Skip dependent tests
    for i in $(seq 12 21); do
        echo "SKIP: test $i (depends on idea file creation)"
    done
fi

# --- Test 22: Functional - function output contains idea ID ---
if echo "$result" | grep -q 'idea-001'; then
    echo "PASS: function output contains idea-001"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: function should output the planted idea ID (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
