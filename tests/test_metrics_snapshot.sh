#!/usr/bin/env bash
# tests/test_metrics_snapshot.sh — Tests for spec-43 §1 _metrics_snapshot()
# Verifies that _metrics_snapshot() collects all 5 metric categories and appends
# snapshots to .automaton/evolution-metrics.json.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _metrics_snapshot function exists in automaton.sh ---
grep_result=$(grep -c '^_metrics_snapshot()' "$script_file" || true)
assert_equals "1" "$grep_result" "_metrics_snapshot() function exists in automaton.sh"

# --- Test 2: Function collects capability metrics ---
grep_result=$(grep -c 'total_lines' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot references total_lines capability metric"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should reference total_lines capability metric" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Function collects efficiency metrics ---
grep_result=$(grep -c 'tokens_per_task' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot references tokens_per_task efficiency metric"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should reference tokens_per_task efficiency metric" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Function collects quality metrics ---
grep_result=$(grep -c 'test_pass_rate' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot references test_pass_rate quality metric"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should reference test_pass_rate quality metric" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Function collects innovation metrics ---
grep_result=$(grep -c 'garden_seeds' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot references garden_seeds innovation metric"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should reference garden_seeds innovation metric" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Function collects health metrics ---
grep_result=$(grep -c 'budget_utilization' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot references budget_utilization health metric"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should reference budget_utilization health metric" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Function writes to evolution-metrics.json ---
grep_result=$(grep -c 'evolution-metrics\.json' "$script_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot writes to evolution-metrics.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should write to evolution-metrics.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Function accepts cycle_id argument ---
grep_result=$(grep -A5 '^_metrics_snapshot()' "$script_file" | grep -c 'cycle_id' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot accepts cycle_id argument"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should accept cycle_id argument" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Function checks METRICS_ENABLED ---
grep_result=$(grep -A3 '^_metrics_snapshot()' "$script_file" | grep -c 'METRICS_ENABLED' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot checks METRICS_ENABLED flag"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should check METRICS_ENABLED flag" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Function initializes metrics file if it doesn't exist ---
grep_result=$(grep -A20 '^_metrics_snapshot()' "$script_file" | grep -c '"version"' || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: _metrics_snapshot initializes metrics file with version"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _metrics_snapshot should initialize metrics file with version" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Integration test — run _metrics_snapshot in isolated environment ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Set up a minimal project directory
mkdir -p "$TEST_DIR/.automaton/garden" "$TEST_DIR/.automaton/votes" "$TEST_DIR/specs" "$TEST_DIR/tests" "$TEST_DIR/.claude/agents" "$TEST_DIR/.claude/skills" "$TEST_DIR/.claude/hooks"

# Create a minimal automaton.sh to count lines/functions
cat > "$TEST_DIR/automaton.sh" << 'SCRIPTEOF'
#!/usr/bin/env bash
_func_one() { true; }
_func_two() { true; }
_func_three() { true; }
SCRIPTEOF

# Create minimal state files
echo '{"stall_count": 2, "iteration": 10, "replan_count": 1}' > "$TEST_DIR/.automaton/state.json"
cat > "$TEST_DIR/.automaton/budget.json" << 'BUDGETEOF'
{
  "mode": "api",
  "limits": {"max_cost_usd": 50},
  "used": {
    "total_input": 50000, "total_output": 10000,
    "total_cache_create": 5000, "total_cache_read": 20000,
    "estimated_cost_usd": 5.00
  },
  "history": [
    {"phase": "build", "status": "success", "duration_seconds": 30},
    {"phase": "build", "status": "success", "duration_seconds": 45},
    {"phase": "build", "status": "fail", "duration_seconds": 20}
  ]
}
BUDGETEOF

# Create minimal garden index
cat > "$TEST_DIR/.automaton/garden/_index.json" << 'GARDENEOF'
{"total":4,"by_stage":{"seed":2,"sprout":1,"bloom":1,"harvest":0,"wilt":0},"bloom_candidates":["idea-004"],"recent_activity":[],"next_id":5,"updated_at":"2026-03-01T00:00:00Z"}
GARDENEOF

# Create minimal signals file
cat > "$TEST_DIR/.automaton/signals.json" << 'SIGEOF'
{"version":1,"signals":[{"id":"sig-001","strength":0.8},{"id":"sig-002","strength":0.5},{"id":"sig-003","strength":0.01}]}
SIGEOF

# Create a spec file and test file
touch "$TEST_DIR/specs/spec-01-example.md"
cat > "$TEST_DIR/tests/test_one.sh" << 'TESTEOF'
assert_equals "1" "1" "test one"
assert_equals "2" "2" "test two"
TESTEOF

# Create test_results.json
echo '{"passed":5,"failed":1,"total":6}' > "$TEST_DIR/.automaton/test_results.json"

# Create self_modifications.json
echo '[{"type":"modification","iteration":1},{"type":"syntax_error","iteration":2}]' > "$TEST_DIR/.automaton/self_modifications.json"

# Source the real automaton.sh functions in a subshell with mocked globals
result=$(
    export AUTOMATON_DIR="$TEST_DIR/.automaton"
    export METRICS_ENABLED="true"
    export PROJECT_ROOT="$TEST_DIR"
    export SCRIPT_PATH="$TEST_DIR/automaton.sh"
    export BUDGET_MODE="api"

    # Source only the _metrics_snapshot function from the real script
    # We extract and eval it to avoid sourcing the entire orchestrator
    func_body=$(sed -n '/^_metrics_snapshot()/,/^[a-z_]*() {/{ /^[a-z_]*() {/!p; }' "$script_file")
    # Also need the log function
    log() { true; }
    eval "$func_body"
    _metrics_snapshot 1
    cat "$AUTOMATON_DIR/evolution-metrics.json"
)

# Verify the output is valid JSON with snapshots array
snapshot_count=$(echo "$result" | jq '.snapshots | length' 2>/dev/null || echo "0")
if [ "$snapshot_count" -ge 1 ]; then
    echo "PASS: Integration test — _metrics_snapshot created a snapshot"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Integration test — _metrics_snapshot should create a snapshot (got: $result)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Snapshot has all 5 categories ---
has_all=$(echo "$result" | jq '.snapshots[0] | has("capability", "efficiency", "quality", "innovation", "health")' 2>/dev/null || echo "false")
assert_equals "true" "$has_all" "Snapshot contains all 5 metric categories"

# --- Test 13: Snapshot has cycle_id and timestamp ---
has_meta=$(echo "$result" | jq '.snapshots[0] | has("cycle_id", "timestamp")' 2>/dev/null || echo "false")
assert_equals "true" "$has_meta" "Snapshot contains cycle_id and timestamp"

# --- Test 14: Capability metrics are populated ---
total_lines=$(echo "$result" | jq '.snapshots[0].capability.total_lines // 0' 2>/dev/null || echo "0")
if [ "$total_lines" -gt 0 ]; then
    echo "PASS: Capability total_lines is populated ($total_lines)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Capability total_lines should be > 0 (got $total_lines)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: Snapshot retention field in metrics file ---
has_version=$(echo "$result" | jq '.version // 0' 2>/dev/null || echo "0")
assert_equals "1" "$has_version" "Metrics file has version field"

test_summary
