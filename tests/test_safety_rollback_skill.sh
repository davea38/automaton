#!/usr/bin/env bash
# tests/test_safety_rollback_skill.sh — Tests for spec-45 rollback-executor skill
# Verifies that .claude/skills/rollback-executor.md exists with the correct
# structure for guided manual rollback of a specific evolution cycle.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

skill_file="$SCRIPT_DIR/../.claude/skills/rollback-executor.md"

# --- Test 1: Skill file exists ---
assert_file_exists "$skill_file" "rollback-executor.md skill file exists"

# --- Test 2: Has YAML frontmatter with name ---
if head -5 "$skill_file" | grep -q 'name: rollback-executor'; then
    echo "PASS: Has name: rollback-executor in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should have name: rollback-executor in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Has description in frontmatter ---
if head -5 "$skill_file" | grep -q 'description:'; then
    echo "PASS: Has description in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should have description in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Has tools field in frontmatter ---
if head -5 "$skill_file" | grep -q 'tools:'; then
    echo "PASS: Has tools field in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should have tools field in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Includes Bash tool for executing git/rollback commands ---
if head -5 "$skill_file" | grep -q 'Bash'; then
    echo "PASS: Includes Bash in tools list"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should include Bash in tools list for executing rollback commands" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: References evolution branch pattern ---
grep_result=$(grep -c 'automaton/evolve-' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: References automaton/evolve- branch pattern"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should reference automaton/evolve- branch pattern" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: References self_modifications.json audit trail ---
grep_result=$(grep -c 'self_modifications' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: References self_modifications.json audit trail"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should reference self_modifications.json for audit trail" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Includes step for identifying the cycle to roll back ---
grep_result=$(grep -ci 'identify\|select\|choose.*cycle' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Includes step for identifying the target cycle"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should include a step for identifying which cycle to roll back" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Includes step for reverting the merge ---
grep_result=$(grep -ci 'revert\|git revert' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Includes git revert step"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should include a git revert step for undoing the merge" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Includes step for wilting the garden idea ---
grep_result=$(grep -ci 'wilt\|garden_wilt' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Includes garden wilt step"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should include step for wilting the responsible garden idea" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Includes step for emitting a signal ---
grep_result=$(grep -ci 'signal\|quality_concern' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Includes signal emission step"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should include step for emitting a quality_concern signal" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: References votes directory for audit trail ---
grep_result=$(grep -c 'votes/' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: References votes/ directory"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should reference .automaton/votes/ for checking vote history" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: Has Instructions section ---
grep_result=$(grep -c '## Instructions' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Has Instructions section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should have ## Instructions section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: Has Constraints section ---
grep_result=$(grep -c '## Constraints' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Has Constraints section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should have ## Constraints section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: Includes verification step (test suite after rollback) ---
grep_result=$(grep -ci 'verif\|test.*suite\|validate\|confirm' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Includes verification/validation step"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should include a verification step after rollback" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
