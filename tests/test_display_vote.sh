#!/usr/bin/env bash
# tests/test_display_vote.sh — Tests for spec-44 §44.2 _display_vote()
# Verifies that the vote display function exists and produces correctly
# formatted output with per-voter breakdown, tally, conditions, and cost.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _display_vote function is defined ---
grep_result=$(grep -c '^_display_vote()' "$script_file" || true)
assert_equals "1" "$grep_result" "_display_vote() function is defined"

# ============================================================
# Integration tests with test vote data
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create votes directory with a test vote record matching spec-44 example
mkdir -p "$TEST_DIR/votes"
cat > "$TEST_DIR/votes/vote-005.json" << 'EOF'
{
  "vote_id": "vote-005",
  "idea_id": "idea-003",
  "type": "bloom_implementation",
  "proposal": {
    "idea": {
      "title": "Reduce prompt overhead",
      "description": "Reduce prompt overhead by 30%",
      "priority": 72
    }
  },
  "votes": {
    "conservative": {
      "vote": "approve",
      "confidence": 0.70,
      "reasoning": "Evidence is strong, medium risk acceptable",
      "conditions": ["Must pass syntax check"],
      "risk_assessment": "medium"
    },
    "ambitious": {
      "vote": "approve",
      "confidence": 0.90,
      "reasoning": "Opens door to further optimizations",
      "conditions": ["Rollback plan required"],
      "risk_assessment": "low"
    },
    "efficiency": {
      "vote": "approve",
      "confidence": 0.95,
      "reasoning": "Estimated 20K tokens saved per iteration",
      "conditions": [],
      "risk_assessment": "low"
    },
    "quality": {
      "vote": "approve",
      "confidence": 0.60,
      "reasoning": "Acceptable if tests maintained",
      "conditions": ["Update tests"],
      "risk_assessment": "medium"
    },
    "advocate": {
      "vote": "reject",
      "confidence": 0.50,
      "reasoning": "Low user-visible impact, low priority",
      "conditions": [],
      "risk_assessment": "low"
    }
  },
  "tally": {
    "approve": 4,
    "reject": 1,
    "abstain": 0,
    "threshold": 3,
    "result": "approved",
    "conditions_merged": ["Must pass syntax check", "Rollback plan required", "Update tests"]
  },
  "created_at": "2026-03-01T10:00:00Z"
}
EOF

# Create a garden directory with idea-003 so lookup by idea ID can work
mkdir -p "$TEST_DIR/garden"
cat > "$TEST_DIR/garden/idea-003.json" << 'EOF'
{
  "id": "idea-003",
  "title": "Reduce prompt overhead",
  "vote_id": "vote-005"
}
EOF

# Stub minimal functions needed by _display_vote
source_display_vote() {
    # Source only the function we need by extracting it
    AUTOMATON_DIR="$TEST_DIR"
    CONFIG_FILE="$TEST_DIR/config.json"
    echo '{}' > "$CONFIG_FILE"

    # Source the log function (stub)
    log() { :; }
    export -f log

    # Extract _display_vote function
    eval "$(sed -n '/^_display_vote()/,/^}/p' "$script_file")"
}

source_display_vote

# --- Test 2: Display by vote ID shows header with vote ID and idea ---
output=$(_display_vote "vote-005" 2>/dev/null)
assert_contains "$output" "VOTE: vote-005" "Header shows vote ID"

# --- Test 3: Header contains idea title ---
assert_contains "$output" "Reduce prompt overhead" "Header shows idea title"

# --- Test 4: Shows vote type ---
assert_contains "$output" "bloom_implementation" "Shows vote type"

# --- Test 5: Shows result ---
assert_contains "$output" "APPROVED" "Shows result status"

# --- Test 6: Shows per-voter breakdown ---
assert_contains "$output" "conservative" "Shows conservative voter"
assert_contains "$output" "ambitious" "Shows ambitious voter"
assert_contains "$output" "efficiency" "Shows efficiency voter"
assert_contains "$output" "quality" "Shows quality voter"
assert_contains "$output" "advocate" "Shows advocate voter"

# --- Test 7: Shows vote values ---
assert_contains "$output" "approve" "Shows approve votes"
assert_contains "$output" "reject" "Shows reject votes"

# --- Test 8: Shows tally line ---
assert_contains "$output" "4 approve" "Tally shows 4 approvals"
assert_contains "$output" "1 reject" "Tally shows 1 rejection"

# --- Test 9: Shows conditions ---
assert_contains "$output" "Must pass syntax check" "Shows condition 1"
assert_contains "$output" "Rollback plan required" "Shows condition 2"
assert_contains "$output" "Update tests" "Shows condition 3"

# --- Test 10: Shows threshold ---
assert_contains "$output" "3" "Shows threshold value"

# ============================================================
# Lookup by idea ID
# ============================================================

# --- Test 11: Display by idea ID resolves to vote ---
output_by_idea=$(_display_vote "idea-003" 2>/dev/null)
assert_contains "$output_by_idea" "VOTE: vote-005" "Lookup by idea ID resolves to vote"

# --- Test 12: Display by bare number resolves to vote ---
output_by_num=$(_display_vote "3" 2>/dev/null)
assert_contains "$output_by_num" "VOTE: vote-005" "Lookup by bare number resolves to vote"

# ============================================================
# Edge case: rejected vote
# ============================================================

cat > "$TEST_DIR/votes/vote-006.json" << 'EOF'
{
  "vote_id": "vote-006",
  "idea_id": "idea-004",
  "type": "bloom_implementation",
  "proposal": {
    "idea": {
      "title": "Add auto-scaling feature",
      "description": "Scale agents automatically",
      "priority": 45
    }
  },
  "votes": {
    "conservative": {
      "vote": "reject",
      "confidence": 0.80,
      "reasoning": "Too risky without more testing",
      "conditions": [],
      "risk_assessment": "high"
    },
    "ambitious": {
      "vote": "approve",
      "confidence": 0.70,
      "reasoning": "Growth potential is high",
      "conditions": [],
      "risk_assessment": "medium"
    },
    "efficiency": {
      "vote": "abstain",
      "confidence": 0.40,
      "reasoning": "Unclear cost impact",
      "conditions": [],
      "risk_assessment": "medium"
    },
    "quality": {
      "vote": "reject",
      "confidence": 0.75,
      "reasoning": "Insufficient test coverage",
      "conditions": [],
      "risk_assessment": "high"
    },
    "advocate": {
      "vote": "reject",
      "confidence": 0.60,
      "reasoning": "Users did not request this",
      "conditions": [],
      "risk_assessment": "medium"
    }
  },
  "tally": {
    "approve": 1,
    "reject": 3,
    "abstain": 1,
    "threshold": 3,
    "result": "rejected",
    "conditions_merged": []
  },
  "created_at": "2026-03-01T12:00:00Z"
}
EOF

# --- Test 13: Rejected vote shows REJECTED ---
output_rejected=$(_display_vote "vote-006" 2>/dev/null)
assert_contains "$output_rejected" "REJECTED" "Rejected vote shows REJECTED"

# --- Test 14: Rejected vote shows abstain count ---
assert_contains "$output_rejected" "1 abstain" "Shows abstain count"

# ============================================================
# Edge case: vote not found
# ============================================================

# --- Test 15: Non-existent vote ID produces error ---
output_missing=$(_display_vote "vote-999" 2>/dev/null)
assert_contains "$output_missing" "not found" "Non-existent vote produces error message"

# --- Test 16: No conditions — conditions line omitted or shows none ---
# When conditions_merged is empty, the display should not show a Conditions line
# (or should show "Conditions: (none)")
if echo "$output_rejected" | grep -qF "Conditions:"; then
    # If Conditions line exists, it should say "(none)" or similar
    assert_contains "$output_rejected" "(none)" "Empty conditions shows (none)"
else
    echo "PASS: No conditions line when empty"
    ((_TEST_PASS_COUNT++))
fi

test_summary
