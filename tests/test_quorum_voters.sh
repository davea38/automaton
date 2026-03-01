#!/usr/bin/env bash
# tests/test_quorum_voters.sh — Tests for spec-39 §1 voter agent definitions
# Verifies that all 5 voter agent definition files exist in .claude/agents/
# with correct YAML frontmatter and required sections.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

agents_dir="$SCRIPT_DIR/../.claude/agents"

VOTERS=("conservative" "ambitious" "efficiency" "quality" "advocate")

# --- Test 1-5: All voter agent files exist ---
for voter in "${VOTERS[@]}"; do
    assert_file_exists "$agents_dir/voter-${voter}.md" "voter-${voter}.md exists"
done

# --- Test 6-10: Each voter has YAML frontmatter with required fields ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    # Check frontmatter delimiter
    first_line=$(head -1 "$file")
    assert_equals "---" "$first_line" "voter-${voter}.md starts with YAML frontmatter"
done

# --- Test 11-15: Each voter has name field ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    name=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^name:' | head -1)
    assert_contains "$name" "voter-${voter}" "voter-${voter}.md has correct name"
done

# --- Test 16-20: Each voter uses sonnet model ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    model=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^model:' | head -1)
    assert_contains "$model" "sonnet" "voter-${voter}.md uses sonnet model"
done

# --- Test 21-25: Each voter has no tools (read-only) ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    # Should not have a tools section or should have empty tools
    tools_line=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^tools:' | head -1)
    if [ -n "$tools_line" ]; then
        # If tools is present, it should be empty (tools: [])
        assert_contains "$tools_line" "[]" "voter-${voter}.md has empty tools list"
    else
        echo "PASS: voter-${voter}.md has no tools section (read-only)"
        ((_TEST_PASS_COUNT++))
    fi
done

# --- Test 26-30: Each voter has the JSON output format section ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    content=$(cat "$file")
    assert_contains "$content" '"vote"' "voter-${voter}.md documents vote output field"
done

# --- Test 31-35: Each voter has the correct perspective keyword ---
declare -A PERSPECTIVES=(
    [conservative]="risk"
    [ambitious]="growth"
    [efficiency]="cost"
    [quality]="test"
    [advocate]="user"
)
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    content=$(cat "$file")
    keyword="${PERSPECTIVES[$voter]}"
    assert_contains "$content" "$keyword" "voter-${voter}.md references its perspective keyword '$keyword'"
done

# --- Test 36-40: Each voter has Constraints section ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    content=$(cat "$file")
    assert_contains "$content" "READ-ONLY" "voter-${voter}.md has READ-ONLY constraint"
done

# --- Test 41-45: Each voter has maxTurns: 1 (single-shot) ---
for voter in "${VOTERS[@]}"; do
    file="$agents_dir/voter-${voter}.md"
    max_turns=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^maxTurns:' | head -1)
    assert_contains "$max_turns" "1" "voter-${voter}.md has maxTurns: 1"
done

test_summary
