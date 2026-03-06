#!/usr/bin/env bash
# tests/test_constitution_create.sh — Tests for spec-40 _constitution_create_default()
# Verifies that _constitution_create_default() creates constitution.md with 8 articles
# and the correct protection levels, initializes constitution-history.json, and that
# _constitution_get_summary() returns a correct summary object.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# Create a temp directory to act as AUTOMATON_DIR
AUTOMATON_DIR="$(mktemp -d)"
trap 'rm -rf "$AUTOMATON_DIR"' EXIT

# --- Test 1: _constitution_create_default creates constitution.md ---
# Source the function from automaton.sh by extracting it
# We simulate the environment the function expects
_constitution_create_default_exists=$(grep -c '^_constitution_create_default()' "$script_file" || true)
assert_equals "1" "$_constitution_create_default_exists" \
  "automaton.sh contains _constitution_create_default function"

# --- Test 2: Function creates constitution.md when called ---
# We'll create a minimal harness that sources the function and calls it
cat > "$AUTOMATON_DIR/_test_harness.sh" << 'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"

# Stub log function
log() { :; }

# Extract _constitution_create_default from automaton.sh
eval "$(sed -n '/^_constitution_create_default()/,/^}/p' "$2")"

# Also extract _constitution_get_summary if present
if grep -q '^_constitution_get_summary()' "$2"; then
    eval "$(sed -n '/^_constitution_get_summary()/,/^}/p' "$2")"
fi

_constitution_create_default
HARNESS
chmod +x "$AUTOMATON_DIR/_test_harness.sh"

bash "$AUTOMATON_DIR/_test_harness.sh" "$AUTOMATON_DIR" "$script_file"
assert_file_exists "$AUTOMATON_DIR/constitution.md" \
  "_constitution_create_default creates constitution.md"

# --- Test 3: constitution.md contains all 8 articles ---
article_count=$(grep -c '^### Article' "$AUTOMATON_DIR/constitution.md" || true)
assert_equals "8" "$article_count" "constitution.md contains 8 articles"

# --- Test 4: Article I has unanimous protection ---
art1_protection=$(grep -A1 'Article I:' "$AUTOMATON_DIR/constitution.md" | grep -o 'unanimous' || true)
assert_equals "unanimous" "$art1_protection" "Article I has unanimous protection"

# --- Test 5: Article II has unanimous protection ---
art2_protection=$(grep -A1 'Article II:' "$AUTOMATON_DIR/constitution.md" | grep -o 'unanimous' || true)
assert_equals "unanimous" "$art2_protection" "Article II has unanimous protection"

# --- Test 6: Article VIII has unanimous protection ---
art8_protection=$(grep -A1 'Article VIII:' "$AUTOMATON_DIR/constitution.md" | grep -o 'unanimous' || true)
assert_equals "unanimous" "$art8_protection" "Article VIII has unanimous protection"

# --- Test 7: Article III has supermajority protection ---
art3_protection=$(grep -A1 'Article III:' "$AUTOMATON_DIR/constitution.md" | grep -o 'supermajority' || true)
assert_equals "supermajority" "$art3_protection" "Article III has supermajority protection"

# --- Test 8: Article VI has majority protection ---
art6_protection=$(grep -A1 'Article VI:' "$AUTOMATON_DIR/constitution.md" | grep -o 'majority' || true)
assert_equals "majority" "$art6_protection" "Article VI has majority protection"

# --- Test 9: constitution-history.json is created ---
assert_file_exists "$AUTOMATON_DIR/constitution-history.json" \
  "_constitution_create_default creates constitution-history.json"

# --- Test 10: constitution-history.json has correct structure ---
hist_version=$(jq -r '.version' "$AUTOMATON_DIR/constitution-history.json")
assert_equals "1" "$hist_version" "constitution-history.json has version=1"

hist_amendments=$(jq -r '.amendments | length' "$AUTOMATON_DIR/constitution-history.json")
assert_equals "0" "$hist_amendments" "constitution-history.json has empty amendments array"

hist_current=$(jq -r '.current_version' "$AUTOMATON_DIR/constitution-history.json")
assert_equals "1" "$hist_current" "constitution-history.json has current_version=1"

# --- Test 11: constitution.md contains Safety First article ---
assert_contains "$(cat "$AUTOMATON_DIR/constitution.md")" "Safety First" \
  "constitution.md contains Article I: Safety First"

# --- Test 12: constitution.md contains Human Sovereignty article ---
assert_contains "$(cat "$AUTOMATON_DIR/constitution.md")" "Human Sovereignty" \
  "constitution.md contains Article II: Human Sovereignty"

# --- Test 13: constitution.md contains Amendment Protocol article ---
assert_contains "$(cat "$AUTOMATON_DIR/constitution.md")" "Amendment Protocol" \
  "constitution.md contains Article VIII: Amendment Protocol"

# --- Test 14: constitution.md references spec-22 safety ---
assert_contains "$(cat "$AUTOMATON_DIR/constitution.md")" "spec-22" \
  "constitution.md references self-build safety (spec-22)"

# --- Test 15: constitution.md references spec-45 circuit breakers ---
assert_contains "$(cat "$AUTOMATON_DIR/constitution.md")" "spec-45" \
  "constitution.md references circuit breakers (spec-45)"

# --- Test 16: Does not overwrite existing constitution ---
echo "EXISTING CONTENT" > "$AUTOMATON_DIR/constitution.md"
bash "$AUTOMATON_DIR/_test_harness.sh" "$AUTOMATON_DIR" "$script_file"
existing_content=$(cat "$AUTOMATON_DIR/constitution.md")
assert_contains "$existing_content" "EXISTING CONTENT" \
  "_constitution_create_default does not overwrite existing constitution"

# --- Test 17: _constitution_get_summary returns correct JSON ---
rm -f "$AUTOMATON_DIR/constitution.md"
bash "$AUTOMATON_DIR/_test_harness.sh" "$AUTOMATON_DIR" "$script_file"
# Create a harness that calls _constitution_get_summary
cat > "$AUTOMATON_DIR/_test_summary.sh" << 'SUMHARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
log() { :; }
eval "$(sed -n '/^_constitution_create_default()/,/^}/p' "$2")"
if grep -q '^_constitution_get_summary()' "$2"; then
    eval "$(sed -n '/^_constitution_get_summary()/,/^}/p' "$2")"
    _constitution_get_summary
else
    echo "FUNCTION_NOT_FOUND"
fi
SUMHARNESS
chmod +x "$AUTOMATON_DIR/_test_summary.sh"
summary_output=$(bash "$AUTOMATON_DIR/_test_summary.sh" "$AUTOMATON_DIR" "$script_file")
if [ "$summary_output" != "FUNCTION_NOT_FOUND" ]; then
    summary_articles=$(echo "$summary_output" | jq -r '.articles')
    assert_equals "8" "$summary_articles" "_constitution_get_summary reports 8 articles"
    summary_version=$(echo "$summary_output" | jq -r '.version')
    assert_equals "1" "$summary_version" "_constitution_get_summary reports version 1"
    summary_constraints=$(echo "$summary_output" | jq -r '.key_constraints | length')
    assert_equals "4" "$summary_constraints" "_constitution_get_summary reports 4 key constraints"
else
    echo "SKIP: _constitution_get_summary not yet implemented"
fi

test_summary
