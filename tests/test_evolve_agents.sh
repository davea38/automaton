#!/usr/bin/env bash
# tests/test_evolve_agents.sh — Tests for spec-41 §13 evolution agent definitions
# Verifies that all 3 evolution agent definition files exist in .claude/agents/
# with correct YAML frontmatter, required sections, and structured JSON output format.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

agents_dir="$SCRIPT_DIR/../.claude/agents"

AGENTS=("evolve-reflect" "evolve-ideate" "evolve-observe")

# --- Test 1-3: All evolution agent files exist ---
for agent in "${AGENTS[@]}"; do
    assert_file_exists "$agents_dir/${agent}.md" "${agent}.md exists"
done

# --- Test 4-6: Each agent has YAML frontmatter with opening delimiter ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    first_line=$(head -1 "$file")
    assert_equals "---" "$first_line" "${agent}.md starts with YAML frontmatter"
done

# --- Test 7-9: Each agent has correct name field ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    name=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^name:' | head -1)
    assert_contains "$name" "$agent" "${agent}.md has correct name"
done

# --- Test 10-12: Each agent uses sonnet model ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    model=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^model:' | head -1)
    assert_contains "$model" "sonnet" "${agent}.md uses sonnet model"
done

# --- Test 13-15: Each agent has no tools (read-only) ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    tools_line=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^tools:' | head -1)
    if [ -n "$tools_line" ]; then
        assert_contains "$tools_line" "[]" "${agent}.md has empty tools list"
    else
        echo "PASS: ${agent}.md has no tools section (read-only)"
        ((_TEST_PASS_COUNT++))
    fi
done

# --- Test 16-18: Each agent has maxTurns: 1 (single-shot) ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    max_turns=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^maxTurns:' | head -1)
    assert_contains "$max_turns" "1" "${agent}.md has maxTurns: 1"
done

# --- Test 19-21: Each agent has JSON output format section ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    content=$(cat "$file")
    assert_contains "$content" "Output Format" "${agent}.md has Output Format section"
done

# --- Test 22-24: Each agent documents structured JSON output ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    content=$(cat "$file")
    assert_contains "$content" '"cycle_id"' "${agent}.md documents cycle_id output field"
done

# --- Test 25-27: Each agent has READ-ONLY constraint ---
for agent in "${AGENTS[@]}"; do
    file="$agents_dir/${agent}.md"
    content=$(cat "$file")
    assert_contains "$content" "READ-ONLY" "${agent}.md has READ-ONLY constraint"
done

# --- Test 28: evolve-reflect references metrics analysis ---
content=$(cat "$agents_dir/evolve-reflect.md")
assert_contains "$content" "metric" "evolve-reflect.md references metrics"

# --- Test 29: evolve-reflect references signal emission ---
assert_contains "$content" "signal" "evolve-reflect.md references signals"

# --- Test 30: evolve-ideate references evidence ---
content=$(cat "$agents_dir/evolve-ideate.md")
assert_contains "$content" "evidence" "evolve-ideate.md references evidence"

# --- Test 31: evolve-ideate references garden/ideas ---
assert_contains "$content" "idea" "evolve-ideate.md references ideas"

# --- Test 32: evolve-observe references comparison/delta ---
content=$(cat "$agents_dir/evolve-observe.md")
assert_contains "$content" "delta" "evolve-observe.md references delta comparison"

# --- Test 33: evolve-observe references harvest/wilt outcome ---
assert_contains "$content" "harvest" "evolve-observe.md references harvest outcome"

test_summary
