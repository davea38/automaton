#!/usr/bin/env bash
# tests/test_constitution_immutable.sh — Tests for immutable constraint enforcement (spec-40 §2)
# Verifies code-enforced immutability:
#   - unanimous articles cannot have their protection level reduced
#   - Article VIII cannot be removed or weakened
#   - These constraints are enforced independently of the constitution text

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# --- Test 1: _constitution_validate_amendment function exists ---
grep_result=$(grep -c '^_constitution_validate_amendment()' "$script_file" || true)
assert_equals "1" "$grep_result" "_constitution_validate_amendment() function exists in automaton.sh"

# --- Setup: create temp directory and harness ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create constitution with known protection levels
mkdir -p "$TMPDIR_TEST"
cat > "$TMPDIR_TEST/constitution.md" << 'CONSTEOF'
# Automaton Constitution
## Ratified: 2026-03-01

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority.

### Article III: Measurable Progress
**Protection: supermajority**

Every implemented change must target a measurable improvement.

### Article IV: Transparency
**Protection: supermajority**

All autonomous decisions must be fully auditable.

### Article V: Budget Discipline
**Protection: supermajority**

Evolution must operate within defined resource constraints.

### Article VI: Incremental Growth
**Protection: majority**

Evolution proceeds through small, reversible steps.

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution.

### Article VIII: Amendment Protocol
**Protection: unanimous**

This constitution may be amended through the following process:
1. An amendment idea is planted in the garden with tags: ["constitutional"]
2. The idea progresses through normal lifecycle stages
3. At bloom, the quorum evaluates with constitutional_amendment threshold (4/5 supermajority)
4. If approved, the amendment is applied to constitution.md
5. The amendment is recorded in constitution-history.json
6. Articles with unanimous protection cannot have their protection level reduced
7. This article (Article VIII) cannot be removed or modified to reduce amendment requirements
CONSTEOF

# Create a harness that sources the function
cat > "$TMPDIR_TEST/_test_harness.sh" << 'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
script_file="$2"
article="$3"
amendment_type="$4"
new_protection="${5:-}"
new_text="${6:-}"

log() { :; }

eval "$(sed -n '/^_constitution_validate_amendment()/,/^}/p' "$script_file")"

_constitution_validate_amendment "$article" "$amendment_type" "$new_protection" "$new_text"
HARNESS
chmod +x "$TMPDIR_TEST/_test_harness.sh"

run_harness() {
    bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$@" 2>/dev/null
    echo $?
}

# --- Test 2: Reducing Article I (unanimous) protection to supermajority is rejected ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "I" "protection_change" "supermajority" "" 2>/dev/null)
exit_code=$?
assert_equals "1" "$exit_code" "Reducing Article I protection from unanimous to supermajority is rejected"

# --- Test 3: Reducing Article II (unanimous) protection to majority is rejected ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "II" "protection_change" "majority" "" 2>/dev/null)
exit_code=$?
assert_equals "1" "$exit_code" "Reducing Article II protection from unanimous to majority is rejected"

# --- Test 4: Reducing Article VIII (unanimous) protection to supermajority is rejected ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "VIII" "protection_change" "supermajority" "" 2>/dev/null)
exit_code=$?
assert_equals "1" "$exit_code" "Reducing Article VIII protection from unanimous to supermajority is rejected"

# --- Test 5: Removing Article VIII is rejected ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "VIII" "remove" "" "" 2>/dev/null)
exit_code=$?
assert_equals "1" "$exit_code" "Removing Article VIII is rejected"

# --- Test 6: Modifying Article VIII to weaken amendment requirements is rejected ---
# Weakening = changing threshold to lower values like "majority" or "3/5"
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "VIII" "modify" "" "This constitution may be amended by simple majority vote." 2>/dev/null)
exit_code=$?
assert_equals "1" "$exit_code" "Weakening Article VIII amendment requirements is rejected"

# --- Test 7: Modifying Article III (supermajority) text is allowed ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "III" "modify" "" "Updated measurable progress text." 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Modifying Article III text is allowed"

# --- Test 8: Changing Article VI (majority) protection to supermajority is allowed (upgrade) ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "VI" "protection_change" "supermajority" "" 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Upgrading Article VI protection from majority to supermajority is allowed"

# --- Test 9: Changing Article III (supermajority) protection to unanimous is allowed (upgrade) ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "III" "protection_change" "unanimous" "" 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Upgrading Article III protection from supermajority to unanimous is allowed"

# --- Test 10: Changing Article VI (majority) protection to majority is allowed (no change) ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "VI" "protection_change" "majority" "" 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Keeping Article VI protection at majority is allowed"

# --- Test 11: Removing a non-VIII article is allowed ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "VI" "remove" "" "" 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Removing Article VI is allowed"

# --- Test 12: Modifying Article I text (without protection change) is allowed ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "I" "modify" "" "Updated safety text with stronger requirements." 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Modifying Article I text (without protection change) is allowed"

# --- Test 13: Reducing Article III (supermajority) protection to majority is allowed ---
output=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "III" "protection_change" "majority" "" 2>/dev/null)
exit_code=$?
assert_equals "0" "$exit_code" "Reducing Article III protection from supermajority to majority is allowed"

test_summary
