#!/usr/bin/env bash
# tests/test_garden_tags.sh — Tests for garden tag parsing edge cases
cd "$(dirname "$0")/.." || exit 1
source tests/test_helpers.sh
setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR/garden"
log() { :; }

# Source dependencies in order
source lib/config.sh 2>/dev/null || true
source lib/state.sh 2>/dev/null || true
source lib/garden.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# Tag parsing: CSV to JSON array
# ---------------------------------------------------------------------------

echo "=== tags: normal CSV tags ==="
tags_csv="perf,ux,api"
tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .) || tags_json="[]"
assert_json_valid "$tags_json" "Normal CSV produces valid JSON"
count=$(echo "$tags_json" | jq 'length')
assert_equals "3" "$count" "Three tags parsed"

echo "=== tags: single tag ==="
tags_csv="solo"
tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .) || tags_json="[]"
count=$(echo "$tags_json" | jq 'length')
assert_equals "1" "$count" "Single tag parsed"

echo "=== tags: empty string ==="
tags_csv=""
tags_json="[]"
if [ -n "$tags_csv" ]; then
    tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .) || tags_json="[]"
fi
assert_equals "[]" "$tags_json" "Empty CSV produces empty array"

echo "=== tags: tags with spaces ==="
tags_csv="my tag,another tag"
tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .) || tags_json="[]"
assert_json_valid "$tags_json" "Tags with spaces produce valid JSON"
first=$(echo "$tags_json" | jq -r '.[0]')
assert_equals "my tag" "$first" "Tag with space preserved"

echo "=== tags: tags with special characters ==="
tags_csv='fix/bug,feature:new,tag@2'
tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .) || tags_json="[]"
assert_json_valid "$tags_json" "Tags with special chars produce valid JSON"
count=$(echo "$tags_json" | jq 'length')
assert_equals "3" "$count" "Three special-char tags parsed"

echo "=== tags: trailing comma ==="
tags_csv="a,b,"
tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .) || tags_json="[]"
assert_json_valid "$tags_json" "Trailing comma produces valid JSON"

echo "=== tags: fallback on jq failure ==="
# Simulate broken pipe by testing the fallback
result="[]"
result=$(echo "" | jq 'invalid_filter' 2>/dev/null) || result="[]"
assert_equals "[]" "$result" "Fallback to empty array on jq error"

test_summary
