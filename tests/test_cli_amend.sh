#!/usr/bin/env bash
# tests/test_cli_amend.sh — Tests for spec-44 §44.3 _cli_amend()
# Verifies that _cli_amend() guides the human through the amendment process:
# select article, show current text, accept proposed change, create garden
# idea tagged 'constitutional', and display next steps.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_amend function is defined ---
grep_result=$(grep -c '^_cli_amend()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_amend() function is defined"

# ============================================================
# Integration tests with temp garden and constitution
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
mkdir -p "$GARDEN_DIR"

# Create an _index.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a minimal constitution
cat > "$TEST_DIR/constitution.md" << 'CONSTEOF'
# Automaton Constitution
## Ratified: 2026-03-01

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority over automaton's evolution.

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
Each cycle implements at most one idea.

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution.

### Article VIII: Amendment Protocol
**Protection: unanimous**

This constitution may be amended through the following process.
CONSTEOF

# Create constitution history
cat > "$TEST_DIR/constitution-history.json" << 'EOF'
{"version": 1, "amendments": [], "current_version": 1}
EOF

# Build a wrapper that sources the relevant functions
cat > "$TEST_DIR/run_amend.sh" << WRAPPER
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=true
GARDEN_SEED_TTL_DAYS=30
GARDEN_SPROUT_TTL_DAYS=60
GARDEN_SPROUT_THRESHOLD=2
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=50
GARDEN_MAX_ACTIVE_IDEAS=50

# Minimal log function
log() { :; }

# Extract needed functions from automaton.sh
eval "\$(sed -n '/^_garden_plant_seed()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_constitution_validate_amendment()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_amend()/,/^}/p' '$script_file')"

_cli_amend
WRAPPER
chmod +x "$TEST_DIR/run_amend.sh"

# --- Test 2: Amend Article VI with confirmation ---
# Provide interactive input: article=VI, proposed_change=..., y
output=$(printf 'VI\nIncrease max files from 3 to 5\ny\n' | bash "$TEST_DIR/run_amend.sh" 2>&1) || true
assert_contains "$output" "CONSTITUTIONAL AMENDMENT" "Shows amendment header"

# --- Test 3: Output shows current article text ---
assert_contains "$output" "Article VI" "Output shows Article VI reference"

# --- Test 4: Output shows the protection level ---
assert_contains "$output" "majority" "Output shows protection level"

# --- Test 5: Output shows 'constitutional' tag ---
assert_contains "$output" "constitutional" "Output mentions constitutional tag"

# --- Test 6: A garden idea was created ---
idea_count=$(ls "$GARDEN_DIR"/idea-*.json 2>/dev/null | wc -l)
assert_equals "1" "$(echo "$idea_count" | tr -d ' ')" "One garden idea created"

# --- Test 7: The garden idea has the constitutional tag ---
idea_file=$(ls "$GARDEN_DIR"/idea-*.json 2>/dev/null | head -1)
has_tag=$(jq -r '.tags | index("constitutional") != null' "$idea_file" 2>/dev/null || echo "false")
assert_equals "true" "$has_tag" "Garden idea has constitutional tag"

# --- Test 8: Garden idea title references the article ---
idea_title=$(jq -r '.title' "$idea_file" 2>/dev/null || echo "")
echo "$idea_title" | grep -qi "article vi" || echo "$idea_title" | grep -qi "VI"
title_check=$?
if [ "$title_check" -eq 0 ]; then
    echo "PASS: Idea title references Article VI"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Idea title does not reference Article VI (got: $idea_title)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Output shows next steps (how to promote) ---
assert_contains "$output" "promote" "Output shows promotion guidance"

# --- Test 10: Abort when user says 'n' ---
# Reset garden for next test
rm -f "$GARDEN_DIR"/idea-*.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":2,"updated_at":"2026-01-01T00:00:00Z"}
EOF

abort_output=$(printf 'III\nSome proposed change\nn\n' | bash "$TEST_DIR/run_amend.sh" 2>&1) || true
abort_count=$(ls "$GARDEN_DIR"/idea-*.json 2>/dev/null | wc -l)
assert_equals "0" "$(echo "$abort_count" | tr -d ' ')" "No idea created when user aborts"

# --- Test 11: Error when constitution does not exist ---
cat > "$TEST_DIR/run_amend_noconst.sh" << WRAPPER2
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$(mktemp -d)"
GARDEN_ENABLED=true
GARDEN_SEED_TTL_DAYS=30
GARDEN_SPROUT_TTL_DAYS=60
GARDEN_SPROUT_THRESHOLD=2
GARDEN_BLOOM_THRESHOLD=3
GARDEN_BLOOM_PRIORITY_THRESHOLD=50
GARDEN_MAX_ACTIVE_IDEAS=50
mkdir -p "\$AUTOMATON_DIR/garden"
cat > "\$AUTOMATON_DIR/garden/_index.json" << 'IXEOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"2026-01-01T00:00:00Z"}
IXEOF
log() { :; }
eval "\$(sed -n '/^_garden_plant_seed()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_constitution_validate_amendment()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_amend()/,/^}/p' '$script_file')"
_cli_amend
WRAPPER2
chmod +x "$TEST_DIR/run_amend_noconst.sh"

noconst_output=$(printf 'VI\nSome change\ny\n' | bash "$TEST_DIR/run_amend_noconst.sh" 2>&1) || true
assert_contains "$noconst_output" "Error" "Error when constitution does not exist"

# --- Test 12: Error when garden is disabled ---
cat > "$TEST_DIR/run_amend_disabled.sh" << WRAPPER3
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=false
log() { :; }
eval "\$(sed -n '/^_garden_plant_seed()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_constitution_validate_amendment()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_amend()/,/^}/p' '$script_file')"
_cli_amend
WRAPPER3
chmod +x "$TEST_DIR/run_amend_disabled.sh"

disabled_output=$(bash "$TEST_DIR/run_amend_disabled.sh" 2>&1) || true
assert_contains "$disabled_output" "not enabled" "Error when garden disabled"

# --- Test 13: 'new' article input for proposing a new article ---
# Reset garden
rm -f "$GARDEN_DIR"/idea-*.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":3,"updated_at":"2026-01-01T00:00:00Z"}
EOF

new_output=$(printf 'new\nNew article about code review requirements\ny\n' | bash "$TEST_DIR/run_amend.sh" 2>&1) || true
new_idea_count=$(ls "$GARDEN_DIR"/idea-*.json 2>/dev/null | wc -l)
assert_equals "1" "$(echo "$new_idea_count" | tr -d ' ')" "Garden idea created for new article proposal"

new_idea_file=$(ls "$GARDEN_DIR"/idea-*.json 2>/dev/null | head -1)
new_has_tag=$(jq -r '.tags | index("constitutional") != null' "$new_idea_file" 2>/dev/null || echo "false")
assert_equals "true" "$new_has_tag" "New article idea has constitutional tag"

# ============================================================
# Summary
# ============================================================
test_summary
