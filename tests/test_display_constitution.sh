#!/usr/bin/env bash
# tests/test_display_constitution.sh — Tests for spec-44 §44.2 _display_constitution()
# Verifies that the constitution display function exists and produces correctly
# formatted output with version, article count, amendments, per-article protection
# levels, and footer guidance.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

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

# Create a wrapper script that sources automaton.sh functions in isolation
cat > "$TEST_DIR/run_display.sh" << RUNEOF
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
PROJECT_ROOT="$TEST_DIR"
LOG_FILE="/dev/null"
CONFIG_FILE="/dev/null"

# Stub log function
log() { :; }

# Stub config_get (not needed for display)
config_get() { echo ""; }

# Source only the function we need by extracting it
# Instead, define AUTOMATON_DIR and source the function definition directly
eval "\$(sed -n '/^_display_constitution()/,/^[^ ]/{ /^_display_constitution()/p; /^[^ ]/!p; }' "$SCRIPT_DIR/../automaton.sh")"
_display_constitution
RUNEOF
chmod +x "$TEST_DIR/run_display.sh"

# Capture output
output=$(bash "$TEST_DIR/run_display.sh" 2>/dev/null)

# --- Test 2: Header line contains CONSTITUTION ---
echo "$output" | grep -q "AUTOMATON CONSTITUTION" || fail "Header should contain 'AUTOMATON CONSTITUTION'"
pass "Header contains AUTOMATON CONSTITUTION"

# --- Test 3: Header shows version ---
echo "$output" | grep -q "v1" || fail "Header should show version v1"
pass "Header shows version"

# --- Test 4: Header shows ratification date ---
echo "$output" | grep -q "2026-03-01" || fail "Header should show ratification date"
pass "Header shows ratification date"

# --- Test 5: Shows article count ---
echo "$output" | grep -q "8 articles" || fail "Should show 8 articles"
pass "Shows article count"

# --- Test 6: Shows amendment count ---
echo "$output" | grep -q "0 amendments" || fail "Should show 0 amendments"
pass "Shows 0 amendments"

# --- Test 7: Shows Article I with unanimous protection ---
echo "$output" | grep -q "Safety First" || fail "Should show Article I title"
echo "$output" | grep -q "unanimous" || fail "Should show unanimous protection for Article I"
pass "Shows Article I with protection level"

# --- Test 8: Shows Article II ---
echo "$output" | grep -q "Human Sovereignty" || fail "Should show Article II title"
pass "Shows Article II"

# --- Test 9: Shows Article VI with majority protection ---
echo "$output" | grep -q "Incremental Growth" || fail "Should show Article VI title"
echo "$output" | grep "Incremental Growth" | grep -q "majority" || fail "Should show majority protection for Article VI"
pass "Shows Article VI with majority protection"

# --- Test 10: Shows Article VIII ---
echo "$output" | grep -q "Amendment Protocol" || fail "Should show Article VIII title"
pass "Shows Article VIII"

# --- Test 11: Footer shows guidance ---
echo "$output" | grep -q "\-\-amend" || fail "Footer should mention --amend"
pass "Footer mentions --amend"

# --- Test 12: Footer references constitution file ---
echo "$output" | grep -q "constitution.md" || fail "Footer should reference constitution.md file"
pass "Footer references constitution.md"

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

output2=$(bash "$TEST_DIR/run_display.sh" 2>/dev/null)

# --- Test 13: Shows updated version ---
echo "$output2" | grep -q "v3" || fail "Should show version v3 after amendments"
pass "Shows updated version v3"

# --- Test 14: Shows amendment count ---
echo "$output2" | grep -q "2 amendments" || fail "Should show 2 amendments"
pass "Shows 2 amendments"

# ============================================================
# Test with missing constitution
# ============================================================

rm -f "$TEST_DIR/constitution.md"

output3=$(bash "$TEST_DIR/run_display.sh" 2>/dev/null)

# --- Test 15: Shows message when no constitution exists ---
echo "$output3" | grep -qi "no constitution\|not found\|does not exist\|not yet" || fail "Should show a message when constitution is missing"
pass "Shows message when constitution is missing"

# Print summary
echo ""
echo "All _display_constitution() tests passed."
