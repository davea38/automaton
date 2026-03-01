#!/usr/bin/env bash
# tests/test_constitution_checker_agent.sh — Tests for spec-40 §3 constitution checker agent
# Verifies that the evolve-constitution-checker.md agent definition exists in .claude/agents/
# with correct YAML frontmatter and required sections for deep compliance analysis.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

agents_dir="$SCRIPT_DIR/../.claude/agents"
file="$agents_dir/evolve-constitution-checker.md"

# --- Test 1: Agent file exists ---
assert_file_exists "$file" "evolve-constitution-checker.md exists"

# --- Test 2: Starts with YAML frontmatter ---
first_line=$(head -1 "$file")
assert_equals "---" "$first_line" "starts with YAML frontmatter"

# --- Test 3: Has correct name field ---
name=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^name:' | head -1)
assert_contains "$name" "evolve-constitution-checker" "has correct name"

# --- Test 4: Uses sonnet model (lightweight analysis) ---
model=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^model:' | head -1)
assert_contains "$model" "sonnet" "uses sonnet model"

# --- Test 5: Has no tools (read-only) ---
tools_line=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^tools:' | head -1)
if [ -n "$tools_line" ]; then
    assert_contains "$tools_line" "[]" "has empty tools list (read-only)"
else
    echo "PASS: has no tools section (read-only)"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 6: Has maxTurns: 1 (single-shot) ---
max_turns=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^maxTurns:' | head -1)
assert_contains "$max_turns" "1" "has maxTurns: 1"

# --- Test 7: References constitution/compliance in content ---
content=$(cat "$file")
assert_contains "$content" "constitution" "references constitution"

# --- Test 8: References per-article assessment ---
assert_contains "$content" "article" "references per-article assessment"

# --- Test 9: Describes diff analysis ---
assert_contains "$content" "diff" "describes diff analysis"

# --- Test 10: Has JSON output format ---
assert_contains "$content" '"result"' "documents result output field"

# --- Test 11: Has compliance report structure ---
assert_contains "$content" "compliance" "documents compliance assessment"

# --- Test 12: Has READ-ONLY constraint ---
assert_contains "$content" "READ-ONLY" "has READ-ONLY constraint"

# --- Test 13: Mentions spirit vs letter distinction ---
assert_contains "$content" "spirit" "mentions spirit of articles (not just letter)"

test_summary
