#!/usr/bin/env bash
# tests/test_constitution_amend.sh — Tests for _constitution_amend() (spec-40 §3)
# Verifies:
#   - Amendment modifies the correct article text in constitution.md
#   - Amendment history is recorded in constitution-history.json with full audit fields
#   - Immutable constraint violations are rejected (delegates to _constitution_validate_amendment)
#   - Version is incremented after each amendment
#   - Protection level changes update the article header

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _constitution_amend function exists ---
grep_result=$(grep -c '^_constitution_amend()' "$script_file" || true)
assert_equals "1" "$grep_result" "_constitution_amend() function exists in automaton.sh"

# --- Setup: create temp directory and harness ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

setup_constitution() {
    # Preserve harness file during cleanup
    rm -f "$TMPDIR_TEST/constitution.md" "$TMPDIR_TEST/constitution-history.json"
    cat > "$TMPDIR_TEST/constitution.md" << 'CONSTEOF'
# Automaton Constitution
## Ratified: 2026-03-01

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.
No evolution cycle may disable, weaken, or bypass:
- Self-build safety protocol (spec-22)
- Syntax validation gates
- Smoke test requirements
- Circuit breakers (spec-45)
- Budget enforcement (spec-23)

A modification that degrades safety must be rejected regardless of other benefits.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority over automaton's evolution.
- All evolution can be paused via `--pause-evolution` (spec-44)
- The human can override any quorum decision via `--override` (spec-44)
- The human can amend the constitution via `--amend` (spec-44)
- No autonomous action may remove or restrict human control mechanisms
- The evolution loop must halt if it cannot reach the human operator

### Article III: Measurable Progress
**Protection: supermajority**

Every implemented change must target a measurable improvement:
- Token efficiency (tokens per completed task)
- Quality (test pass rate, rollback rate)
- Capability (new specs, functions, or test coverage)
- Reliability (stall rate, error rate)

Changes that cannot be measured against at least one metric must not be implemented.
The OBSERVE phase (spec-41) must compare before/after metrics for every implementation.

### Article IV: Transparency
**Protection: supermajority**

All autonomous decisions must be fully auditable:
- Every quorum vote is recorded with reasoning (spec-39)
- Every garden idea has a traceable origin (spec-38)
- Every signal has observation history (spec-42)
- Every implementation records its branch, commits, and metric deltas
- The human can inspect any decision via `--inspect` (spec-44)

Hidden or obfuscated decision-making is a constitutional violation.

### Article V: Budget Discipline
**Protection: supermajority**

Evolution must operate within defined resource constraints:
- Each evolution cycle has a budget ceiling (spec-45)
- Quorum voting has per-cycle cost limits (spec-39)
- The evolution loop must halt when budget is exhausted, not proceed on debt
- Budget overruns in one cycle reduce the next cycle's allocation
- Weekly allowance limits (spec-23) apply to evolution cycles

### Article VI: Incremental Growth
**Protection: majority**

Evolution proceeds through small, reversible steps:
- Each cycle implements at most one idea
- Each implementation modifies at most `self_build.max_files_per_iteration` files (spec-22)
- Each implementation changes at most `self_build.max_lines_changed_per_iteration` lines (spec-22)
- Complex ideas must be decomposed into smaller sub-ideas before implementation
- The system prefers many small improvements over few large changes

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution:
- Test pass rate must remain >= the pre-evolution baseline
- New functionality must include corresponding tests
- Removing a test requires quorum approval as a separate decision
- The OBSERVE phase must run the full test suite after every implementation
- Test count may increase but must never decrease without explicit justification

### Article VIII: Amendment Protocol
**Protection: unanimous**

This constitution may be amended through the following process:
1. An amendment idea is planted in the garden (spec-38) with `tags: ["constitutional"]`
2. The idea progresses through normal lifecycle stages (seed -> sprout -> bloom)
3. At bloom, the quorum evaluates with `constitutional_amendment` threshold (4/5 supermajority)
4. If approved, the amendment is applied to constitution.md
5. The amendment is recorded in constitution-history.json with before/after text
6. Articles with `unanimous` protection cannot have their protection level reduced
7. This article (Article VIII) cannot be removed or modified to reduce amendment requirements
CONSTEOF

    # Initialize history
    cat > "$TMPDIR_TEST/constitution-history.json" << 'HISTEOF'
{
  "version": 1,
  "amendments": [],
  "current_version": 1
}
HISTEOF
}

# Create a harness that sources _constitution_amend and _constitution_validate_amendment
cat > "$TMPDIR_TEST/_test_harness.sh" << 'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
script_file="$2"
shift 2
action="$1"
shift

log() { echo "[LOG] $1: $2" >&2; }

# Extract both functions from automaton.sh
eval "$(sed -n '/^_constitution_validate_amendment()/,/^}/p' "$script_file")"
eval "$(sed -n '/^_constitution_amend()/,/^}/p' "$script_file")"

case "$action" in
    amend)
        _constitution_amend "$@"
        ;;
esac
HARNESS
chmod +x "$TMPDIR_TEST/_test_harness.sh"

run_amend() {
    bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" amend "$@" 2>/dev/null
}

# --- Test 2: Modifying Article VI text records amendment in history ---
setup_constitution
run_amend "VI" "modify" "Increase max files limit to 5" \
    "Evolution proceeds through small, reversible steps:\n- Each cycle implements at most one idea\n- Each implementation modifies at most 5 files" \
    "vote-001" "human"
exit_code=$?
assert_equals "0" "$exit_code" "Amending Article VI returns success"

# Check history was updated
hist_count=$(jq '.amendments | length' "$TMPDIR_TEST/constitution-history.json")
assert_equals "1" "$hist_count" "Amendment history has 1 entry after first amendment"

# Check amendment fields
amend_article=$(jq -r '.amendments[0].article' "$TMPDIR_TEST/constitution-history.json")
assert_equals "VI" "$amend_article" "Amendment records correct article"

amend_type=$(jq -r '.amendments[0].type' "$TMPDIR_TEST/constitution-history.json")
assert_equals "modify" "$amend_type" "Amendment records correct type"

amend_vote=$(jq -r '.amendments[0].vote_id' "$TMPDIR_TEST/constitution-history.json")
assert_equals "vote-001" "$amend_vote" "Amendment records vote_id"

amend_proposer=$(jq -r '.amendments[0].proposed_by' "$TMPDIR_TEST/constitution-history.json")
assert_equals "human" "$amend_proposer" "Amendment records proposed_by"

amend_id=$(jq -r '.amendments[0].amendment_id' "$TMPDIR_TEST/constitution-history.json")
assert_equals "amend-001" "$amend_id" "Amendment ID is amend-001"

# Check version was incremented
new_version=$(jq '.current_version' "$TMPDIR_TEST/constitution-history.json")
assert_equals "2" "$new_version" "Version incremented to 2 after amendment"

# Check before_text is populated
before_text=$(jq -r '.amendments[0].before_text' "$TMPDIR_TEST/constitution-history.json")
assert_contains "$before_text" "small, reversible steps" "Before text contains original article content"

# --- Test 3: Amendment updates the article text in constitution.md ---
# The constitution.md should have the new text for Article VI
const_content=$(cat "$TMPDIR_TEST/constitution.md")
assert_contains "$const_content" "at most 5 files" "Constitution.md updated with new article text"

# --- Test 4: Amending an immutable article (removing Article VIII) is rejected ---
setup_constitution
run_amend "VIII" "remove" "Remove amendment protocol" "" "vote-002" "agent"
exit_code=$?
assert_equals "1" "$exit_code" "Removing Article VIII via amend is rejected"

# History should be unchanged
hist_count=$(jq '.amendments | length' "$TMPDIR_TEST/constitution-history.json")
assert_equals "0" "$hist_count" "No amendment recorded when immutable violation blocks"

# --- Test 5: Reducing Article I protection is rejected ---
setup_constitution
run_amend "I" "protection_change" "Reduce safety protection to majority" "majority" "vote-003" "agent"
exit_code=$?
assert_equals "1" "$exit_code" "Reducing Article I protection is rejected"

# --- Test 6: Multiple amendments increment version correctly ---
setup_constitution
run_amend "VI" "modify" "First amendment" "New text for Article VI first change." "vote-010" "human"
run_amend "VII" "modify" "Second amendment" "New text for Article VII second change." "vote-011" "human"
exit_code=$?
assert_equals "0" "$exit_code" "Second amendment succeeds"

hist_count=$(jq '.amendments | length' "$TMPDIR_TEST/constitution-history.json")
assert_equals "2" "$hist_count" "History has 2 amendments after two modifications"

final_version=$(jq '.current_version' "$TMPDIR_TEST/constitution-history.json")
assert_equals "3" "$final_version" "Version incremented to 3 after two amendments"

second_id=$(jq -r '.amendments[1].amendment_id' "$TMPDIR_TEST/constitution-history.json")
assert_equals "amend-002" "$second_id" "Second amendment ID is amend-002"

# --- Test 7: Protection change amendment updates the article header ---
setup_constitution
run_amend "VI" "protection_change" "Upgrade incremental growth protection" "supermajority" "vote-020" "human"
exit_code=$?
assert_equals "0" "$exit_code" "Protection change for Article VI succeeds"

const_content=$(cat "$TMPDIR_TEST/constitution.md")
# Check that the protection line for Article VI changed
if echo "$const_content" | grep -A1 "### Article VI" | grep -q "supermajority"; then
    echo "PASS: Article VI protection updated to supermajority in constitution.md"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Article VI protection not updated in constitution.md" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: approved_at field is present and non-empty ---
setup_constitution
run_amend "III" "modify" "Tighten measurability" "Stricter metric requirements." "vote-030" "human"
approved_at=$(jq -r '.amendments[0].approved_at' "$TMPDIR_TEST/constitution-history.json")
if [ -n "$approved_at" ] && [ "$approved_at" != "null" ]; then
    echo "PASS: approved_at field is present and non-empty"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: approved_at field is missing or null" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
