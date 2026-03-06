#!/usr/bin/env bash
# tests/test_garden_functional.sh — Functional tests for lib/garden.sh
# Tests plant, water, advance, wilt, prune, priority, and index operations.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up isolated test directory
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-garden-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Mock dependencies
LOG_OUTPUT=""
log() { LOG_OUTPUT+="[$1] $2"$'\n'; }
GARDEN_ENABLED="true"
GARDEN_SPROUT_THRESHOLD=3
GARDEN_BLOOM_THRESHOLD=5
GARDEN_BLOOM_PRIORITY_THRESHOLD=50
GARDEN_SEED_TTL_DAYS=30
GARDEN_SPROUT_TTL_DAYS=60

# Source garden.sh functions
extract_function() {
    local func_name="$1" file="$2"
    awk "/^${func_name}\\(\\)/{found=1; depth=0} found{
        for(i=1;i<=length(\$0);i++){
            c=substr(\$0,i,1)
            if(c==\"{\") depth++
            if(c==\"}\") depth--
        }
        print
        if(found && depth==0) exit
    }" "$file"
}

for fn in _garden_plant_seed _garden_water _garden_advance_stage _garden_wilt _garden_rebuild_index _garden_recompute_priorities _garden_prune_expired _garden_find_duplicates _garden_get_bloom_candidates; do
    eval "$(extract_function "$fn" "$PROJECT_DIR/lib/garden.sh")"
done

# ============================================================
# Test _garden_plant_seed
# ============================================================

idea_id=$(_garden_plant_seed "Add caching layer" "Cache API responses for speed" "observation" "review-phase" "automaton" "low" "performance,cache")
assert_equals "idea-001" "$idea_id" "first planted seed gets idea-001"

# Verify idea file was created
assert_file_exists "$AUTOMATON_DIR/garden/idea-001.json" "idea file created"

# Verify idea JSON structure
idea_json=$(cat "$AUTOMATON_DIR/garden/idea-001.json")
assert_json_valid "$idea_json" "idea JSON is valid"
assert_json_field "$idea_json" '.title' "Add caching layer" "title set correctly"
assert_json_field "$idea_json" '.stage' "seed" "initial stage is seed"
assert_json_field "$idea_json" '.origin.type' "observation" "origin type set"
assert_json_field "$idea_json" '.estimated_complexity' "low" "complexity set"

# Verify tags
tag_count=$(echo "$idea_json" | jq '.tags | length')
assert_equals "2" "$tag_count" "two tags created from CSV"

# Verify index was updated
index_json=$(cat "$AUTOMATON_DIR/garden/_index.json")
assert_json_valid "$index_json" "index JSON is valid"
assert_json_field "$index_json" '.total' "1" "index total = 1"
assert_json_field "$index_json" '.by_stage.seed' "1" "index seed count = 1"

# Plant a second seed
idea_id2=$(_garden_plant_seed "Parallel testing" "Run tests in parallel" "ideation" "evolve-phase" "automaton" "high" "")
assert_equals "idea-002" "$idea_id2" "second seed gets idea-002"

index_json=$(cat "$AUTOMATON_DIR/garden/_index.json")
assert_json_field "$index_json" '.total' "2" "index total = 2 after second plant"

# ============================================================
# Test _garden_water
# ============================================================

_garden_water "idea-001" "testing" "Reduced API calls by 40% in benchmark" "automaton"
idea_json=$(cat "$AUTOMATON_DIR/garden/idea-001.json")
evidence_count=$(echo "$idea_json" | jq '.evidence | length')
assert_equals "1" "$evidence_count" "water adds evidence item"

evidence_type=$(echo "$idea_json" | jq -r '.evidence[0].type')
assert_equals "testing" "$evidence_type" "evidence type captured"

# ============================================================
# Test _garden_advance_stage — seed to sprout after 3 evidence items
# ============================================================

_garden_water "idea-001" "testing" "Second benchmark confirms improvement" "automaton"
_garden_water "idea-001" "observation" "Users report faster responses" "review"

idea_json=$(cat "$AUTOMATON_DIR/garden/idea-001.json")
stage=$(echo "$idea_json" | jq -r '.stage')
assert_equals "sprout" "$stage" "3 evidence items advances seed to sprout"

# ============================================================
# Test _garden_wilt
# ============================================================

_garden_wilt "idea-002" "Superseded by native parallel support"
idea_json=$(cat "$AUTOMATON_DIR/garden/idea-002.json")
stage=$(echo "$idea_json" | jq -r '.stage')
assert_equals "wilt" "$stage" "wilt sets stage to wilt"

index_json=$(cat "$AUTOMATON_DIR/garden/_index.json")
assert_json_field "$index_json" '.by_stage.wilt' "1" "index wilt count = 1"

# ============================================================
# Test _garden_plant_seed with disabled garden
# ============================================================

GARDEN_ENABLED="false"
rc=0
_garden_plant_seed "Disabled idea" "Should not work" "test" "test" "test" || rc=$?
assert_equals "1" "$rc" "planting returns 1 when garden disabled"
GARDEN_ENABLED="true"

# ============================================================
# Test _garden_find_duplicates
# ============================================================

# Plant an idea with overlapping tags to test duplicate detection
_garden_plant_seed "Add response caching" "Cache responses" "observation" "test" "automaton" "low" "cache,speed"
# Search by tag that overlaps with idea-001's tags
dupe=$(_garden_find_duplicates "cache" 2>/dev/null || echo "")
if [ -n "$dupe" ]; then
    echo "PASS: find_duplicates returns match for overlapping tag"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: find_duplicates should return match for 'cache' tag" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
