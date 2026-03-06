#!/usr/bin/env bash
# tests/test_cli_override.sh — Tests for spec-44 §44.3 _cli_override()
# Verifies that _cli_override() lists recently rejected ideas, accepts an
# override selection with confirmation, re-promotes the idea to bloom, and
# logs the override in the vote record and constitution history.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"


# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_override function is defined ---
grep_result=$(grep -c '^_cli_override()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_override() function is defined"

# ============================================================
# Integration tests with temp garden, votes, and constitution
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

GARDEN_DIR="$TEST_DIR/garden"
VOTES_DIR="$TEST_DIR/votes"
mkdir -p "$GARDEN_DIR" "$VOTES_DIR"

# Create an _index.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":2,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":2},"bloom_candidates":[],"recent_activity":[],"next_id":3,"updated_at":"2026-01-01T00:00:00Z"}
EOF

# Create a wilted idea (rejected by quorum)
cat > "$GARDEN_DIR/idea-001.json" << 'EOF'
{"id":"idea-001","title":"Investigate token regression","description":"Analyze token regression","stage":"wilt","origin":{"type":"metric","source":"efficiency"},"evidence":[{"type":"metric","observation":"tokens/task increased","added_at":"2026-01-01T00:00:00Z"},{"type":"signal","observation":"reinforced by signal-003","added_at":"2026-01-02T00:00:00Z"}],"tags":["efficiency"],"priority":45,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"auto-seeded"},{"stage":"sprout","entered_at":"2026-01-02T00:00:00Z","reason":"threshold met"},{"stage":"bloom","entered_at":"2026-01-03T00:00:00Z","reason":"threshold met"},{"stage":"wilt","entered_at":"2026-01-04T00:00:00Z","reason":"Quorum rejected (vote-001)"}],"vote_id":"vote-001","implementation":null,"updated_at":"2026-01-04T00:00:00Z"}
EOF

# Create a second wilted idea (rejected by quorum)
cat > "$GARDEN_DIR/idea-002.json" << 'EOF'
{"id":"idea-002","title":"Update outdated spec refs","description":"Fix outdated spec references","stage":"wilt","origin":{"type":"signal","source":"quality"},"evidence":[{"type":"signal","observation":"spec refs outdated","added_at":"2026-01-01T00:00:00Z"}],"tags":["quality"],"priority":30,"estimated_complexity":"low","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"seed","entered_at":"2026-01-01T00:00:00Z","reason":"auto-seeded"},{"stage":"bloom","entered_at":"2026-01-02T00:00:00Z","reason":"force promoted"},{"stage":"wilt","entered_at":"2026-01-03T00:00:00Z","reason":"Quorum rejected (vote-002)"}],"vote_id":"vote-002","implementation":null,"updated_at":"2026-01-03T00:00:00Z"}
EOF

# Create vote records for the rejected ideas
cat > "$VOTES_DIR/vote-001.json" << 'EOF'
{"vote_id":"vote-001","idea_id":"idea-001","type":"bloom_implementation","proposal":{"title":"Investigate token regression"},"votes":{"voter-conservative":{"vote":"reject","confidence":0.8,"reasoning":"too risky"},"voter-ambitious":{"vote":"approve","confidence":0.6,"reasoning":"worth trying"}},"tally":{"result":"rejected","approve":1,"reject":1,"abstain":0,"threshold":0.6},"created_at":"2026-01-04T00:00:00Z"}
EOF

cat > "$VOTES_DIR/vote-002.json" << 'EOF'
{"vote_id":"vote-002","idea_id":"idea-002","type":"bloom_implementation","proposal":{"title":"Update outdated spec refs"},"votes":{"voter-quality":{"vote":"reject","confidence":0.7,"reasoning":"not enough evidence"}},"tally":{"result":"rejected","approve":0,"reject":1,"abstain":0,"threshold":0.6},"created_at":"2026-01-03T00:00:00Z"}
EOF

# Create constitution history
cat > "$TEST_DIR/constitution-history.json" << 'EOF'
{"version": 1, "amendments": [], "overrides": [], "current_version": 1}
EOF

# Build a wrapper that sources the relevant functions
cat > "$TEST_DIR/run_override.sh" << WRAPPER
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
eval "\$(sed -n '/^_garden_advance_stage()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_override()/,/^}/p' '$script_file')"

_cli_override
WRAPPER
chmod +x "$TEST_DIR/run_override.sh"

# --- Test 2: Override lists recently rejected ideas ---
output=$(printf 'idea-001\ny\n' | bash "$TEST_DIR/run_override.sh" 2>&1) || true
assert_contains "$output" "rejected" "Shows rejected ideas"

# --- Test 3: Output shows idea titles ---
assert_contains "$output" "Investigate token regression" "Shows idea title"

# --- Test 4: Output shows vote IDs ---
assert_contains "$output" "vote-001" "Shows vote ID for rejected idea"

# --- Test 5: Output shows override warning ---
assert_contains "$output" "WARNING" "Shows override warning"

# --- Test 6: Output shows Article II reference ---
assert_contains "$output" "Article II" "References Article II"

# --- Test 7: Idea is re-promoted to bloom stage ---
new_stage=$(jq -r '.stage' "$GARDEN_DIR/idea-001.json")
assert_equals "bloom" "$new_stage" "Idea re-promoted to bloom stage"

# --- Test 8: Stage history includes override entry ---
last_reason=$(jq -r '.stage_history[-1].reason' "$GARDEN_DIR/idea-001.json")
echo "$last_reason" | grep -qi "override"
override_in_history=$?
if [ "$override_in_history" -eq 0 ]; then
    echo "PASS: Stage history records override reason"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Stage history does not record override reason (got: $last_reason)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Vote record updated with override ---
has_override=$(jq 'has("override")' "$VOTES_DIR/vote-001.json")
assert_equals "true" "$has_override" "Vote record has override field"

# --- Test 10: Override logged in constitution history ---
override_count=$(jq '.overrides | length' "$TEST_DIR/constitution-history.json")
assert_equals "1" "$override_count" "Override logged in constitution history"

# --- Test 11: Abort when user says 'n' ---
# Reset idea-002 to wilt for abort test
jq '.stage = "wilt"' "$GARDEN_DIR/idea-002.json" > "$GARDEN_DIR/idea-002.json.tmp" && mv "$GARDEN_DIR/idea-002.json.tmp" "$GARDEN_DIR/idea-002.json"

abort_output=$(printf 'idea-002\nn\n' | bash "$TEST_DIR/run_override.sh" 2>&1) || true
abort_stage=$(jq -r '.stage' "$GARDEN_DIR/idea-002.json")
assert_equals "wilt" "$abort_stage" "Idea stays wilted when user aborts"

# --- Test 12: Error when garden disabled ---
cat > "$TEST_DIR/run_override_disabled.sh" << WRAPPER2
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"
GARDEN_ENABLED=false
log() { :; }
eval "\$(sed -n '/^_garden_advance_stage()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_rebuild_index()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_garden_recompute_priorities()/,/^}/p' '$script_file')"
eval "\$(sed -n '/^_cli_override()/,/^}/p' '$script_file')"
_cli_override
WRAPPER2
chmod +x "$TEST_DIR/run_override_disabled.sh"

disabled_output=$(bash "$TEST_DIR/run_override_disabled.sh" 2>&1) || true
assert_contains "$disabled_output" "not enabled" "Error when garden disabled"

# --- Test 13: Error when no rejected ideas exist ---
# Remove wilted ideas
rm -f "$GARDEN_DIR"/idea-*.json
cat > "$GARDEN_DIR/_index.json" << 'EOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":3,"updated_at":"2026-01-01T00:00:00Z"}
EOF

no_reject_output=$(printf '\n' | bash "$TEST_DIR/run_override.sh" 2>&1) || true
assert_contains "$no_reject_output" "No rejected ideas" "Error when no rejected ideas"

# --- Test 14: Error for invalid idea ID ---
# Recreate idea-001 as wilt
cat > "$GARDEN_DIR/idea-001.json" << 'EOF'
{"id":"idea-001","title":"Investigate token regression","description":"test","stage":"wilt","origin":{"type":"metric","source":"efficiency"},"evidence":[],"tags":[],"priority":0,"estimated_complexity":"medium","related_specs":[],"related_signals":[],"related_ideas":[],"stage_history":[{"stage":"wilt","entered_at":"2026-01-04T00:00:00Z","reason":"Quorum rejected (vote-001)"}],"vote_id":"vote-001","implementation":null,"updated_at":"2026-01-04T00:00:00Z"}
EOF

invalid_output=$(printf 'idea-999\ny\n' | bash "$TEST_DIR/run_override.sh" 2>&1) || true
assert_contains "$invalid_output" "not found" "Error for invalid idea ID"

# ============================================================
# Summary
# ============================================================
test_summary
