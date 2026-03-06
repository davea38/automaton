#!/usr/bin/env bash
# tests/test_display_constitution.sh — Tests for spec-44 §44.2 _display_constitution()
# Verifies that the constitution display function exists and produces correctly
# formatted output with version, article count, amendments, per-article protection
# levels, and footer guidance.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# ============================================================
# Function existence
# ============================================================

# --- Test 1: _display_constitution function is defined ---
grep_result=$(grep -c '^_display_constitution()' "$script_file" || true)
assert_equals "1" "$grep_result" "_display_constitution() function is defined"

# ============================================================
# Integration tests with test constitution data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create a constitution.md matching the default format
cat > "$TEST_DIR/constitution.md" << 'EOF'
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

This constitution may be amended through the following process.
EOF

# Create constitution-history.json with version 1 and no amendments
cat > "$TEST_DIR/constitution-history.json" << 'EOF'
{
  "version": 1,
  "amendments": [],
  "current_version": 1
}
EOF

# Stub minimal functions needed by _display_constitution
source_display_constitution() {
    AUTOMATON_DIR="$TEST_DIR"
    CONFIG_FILE="$TEST_DIR/config.json"
    echo '{}' > "$CONFIG_FILE"

    log() { :; }
    export -f log

    # Extract _display_constitution function
    eval "$(sed -n '/^_display_constitution()/,/^}/p' "$script_file")"
}

source_display_constitution

# Capture output
output=$(_display_constitution 2>/dev/null)

# --- Test 2: Header line contains CONSTITUTION ---
assert_contains "$output" "AUTOMATON CONSTITUTION" "Header contains AUTOMATON CONSTITUTION"

# --- Test 3: Header shows version ---
assert_contains "$output" "v1" "Header shows version v1"

# --- Test 4: Header shows ratification date ---
assert_contains "$output" "2026-03-01" "Header shows ratification date"

# --- Test 5: Shows article count ---
assert_contains "$output" "8 articles" "Shows article count"

# --- Test 6: Shows amendment count ---
assert_contains "$output" "0 amendments" "Shows 0 amendments"

# --- Test 7: Shows Article I with unanimous protection ---
assert_contains "$output" "Safety First" "Shows Article I title"
assert_contains "$output" "unanimous" "Shows unanimous protection"

# --- Test 8: Shows Article II ---
assert_contains "$output" "Human Sovereignty" "Shows Article II title"

# --- Test 9: Shows Article VI with majority protection ---
assert_contains "$output" "Incremental Growth" "Shows Article VI title"
assert_contains "$output" "majority" "Shows majority protection"

# --- Test 10: Shows Article VIII ---
assert_contains "$output" "Amendment Protocol" "Shows Article VIII title"

# --- Test 11: Footer shows guidance ---
assert_contains "$output" "--amend" "Footer mentions --amend"

# --- Test 12: Footer references constitution file ---
assert_contains "$output" "constitution.md" "Footer references constitution.md"

# ============================================================
# Test with amendments
# ============================================================

cat > "$TEST_DIR/constitution-history.json" << 'EOF'
{
  "version": 3,
  "amendments": [
    {"amendment_id": "amend-001", "article": "III"},
    {"amendment_id": "amend-002", "article": "V"}
  ],
  "current_version": 3
}
EOF

output2=$(_display_constitution 2>/dev/null)

# --- Test 13: Shows updated version ---
assert_contains "$output2" "v3" "Shows updated version v3"

# --- Test 14: Shows amendment count ---
assert_contains "$output2" "2 amendments" "Shows 2 amendments"

# ============================================================
# Test with missing constitution
# ============================================================

rm -f "$TEST_DIR/constitution.md"

output3=$(_display_constitution 2>/dev/null)

# --- Test 15: Shows message when no constitution exists ---
assert_contains "$output3" "No constitution" "Shows message when constitution is missing"

# Print summary
test_summary
