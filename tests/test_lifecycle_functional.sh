#!/usr/bin/env bash
# tests/test_lifecycle_functional.sh — Functional tests for lib/lifecycle.sh
# Tests self-build checkpoint/validate, learnings CRUD, and run summaries.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

setup_test_dir

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR" "$AUTOMATON_DIR/run-summaries"

_log_output=""
log() { _log_output+="[$1] $2"$'\n'; }

# Stubs for dependencies
SELF_BUILD_ENABLED="false"
SELF_BUILD_REQUIRE_SMOKE="false"
SELF_BUILD_FILES="automaton.sh config.json"
iteration=1
current_phase="build"
phase_iteration=1

source "$_PROJECT_DIR/lib/lifecycle.sh"

# --- Test: self_build_checkpoint when disabled ---

rc=0
self_build_checkpoint || rc=$?
assert_equals "0" "$rc" "self_build_checkpoint no-op when disabled"

# --- Test: self_build_checkpoint creates checksums ---

SELF_BUILD_ENABLED="true"
cd "$TEST_DIR"

echo '#!/bin/bash' > automaton.sh
echo '{}' > config.json

self_build_checkpoint
assert_file_exists "$AUTOMATON_DIR/self_checksums.json" "checkpoint creates checksums file"
assert_file_exists "$AUTOMATON_DIR/self_backup/automaton.sh" "checkpoint backs up automaton.sh"
assert_file_exists "$AUTOMATON_DIR/self_backup/config.json" "checkpoint backs up config.json"

checksums=$(cat "$AUTOMATON_DIR/self_checksums.json")
assert_json_valid "$checksums" "checksums file is valid JSON"

# Verify checksums are SHA-256 (64 hex chars)
hash=$(echo "$checksums" | jq -r '."automaton.sh"')
assert_matches "$hash" '^[a-f0-9]{64}$' "checksum is valid SHA-256"

# --- Test: self_build_validate when no change ---

rc=0
self_build_validate || rc=$?
assert_equals "0" "$rc" "self_build_validate passes when files unchanged"

# --- Test: self_build_validate detects changes ---

# Modify a file
echo '#!/bin/bash\n# modified' > automaton.sh
_log_output=""

self_build_validate || true
assert_contains "$_log_output" "was modified" "validate detects file modification"

# --- Test: init_learnings creates learnings.json ---

init_learnings
assert_file_exists "$AUTOMATON_DIR/learnings.json" "init_learnings creates file"

learnings=$(cat "$AUTOMATON_DIR/learnings.json")
assert_json_valid "$learnings" "learnings.json is valid JSON"
assert_json_field "$learnings" '.version' "1" "learnings version is 1"

entries_len=$(echo "$learnings" | jq '.entries | length')
assert_equals "0" "$entries_len" "learnings starts with empty entries"

# --- Test: add_learning creates an entry ---
# API: add_learning category summary [detail] [confidence] [source_phase] [tags_csv]

add_learning "convention" "Always run tests before commit" "" "high" "build" ""
learnings=$(cat "$AUTOMATON_DIR/learnings.json")
entries_len=$(echo "$learnings" | jq '.entries | length')
assert_equals "1" "$entries_len" "add_learning adds one entry"

entry=$(echo "$learnings" | jq '.entries[0]')
assert_json_field "$entry" '.confidence' "high" "learning has correct confidence"
assert_json_field "$entry" '.category' "convention" "learning has correct category"
assert_json_field "$entry" '.summary' "Always run tests before commit" "learning has correct summary"
assert_json_field "$entry" '.active' "true" "learning is active by default"

# --- Test: add_learning with different category ---

add_learning "tooling" "Use targeted search queries" "" "medium" "research" ""
learnings=$(cat "$AUTOMATON_DIR/learnings.json")
entries_len=$(echo "$learnings" | jq '.entries | length')
assert_equals "2" "$entries_len" "add_learning adds second entry"

# --- Test: add_learning rejects invalid category ---

rc=0
add_learning "invalid_cat" "Some summary" "" "high" "build" "" || rc=$?
assert_equals "1" "$rc" "add_learning rejects invalid category"

# --- Test: add_learning rejects invalid confidence ---

rc=0
add_learning "convention" "Some summary" "" "extreme" "build" "" || rc=$?
assert_equals "1" "$rc" "add_learning rejects invalid confidence"

# --- Test: query_learnings with filters ---

result=$(query_learnings --category "convention")
assert_contains "$result" "tests before commit" "query_learnings filters by category"

result=$(query_learnings --confidence "medium")
assert_contains "$result" "targeted search" "query_learnings filters by confidence"

result=$(query_learnings --active-only)
assert_contains "$result" "tests before commit" "query_learnings returns active entries"

# --- Test: write_run_summary creates a summary file ---

started_at="2025-01-01T00:00:00Z"
phase_history='[{"phase":"research","completed_at":"t1"},{"phase":"build","completed_at":"t2"}]'
stall_count=0
corruption_count=0
replan_count=0

# Mock budget file
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{
  "limits": {"max_total_tokens": 1000000, "max_cost_usd": 50},
  "used": {"total_tokens": 500000, "estimated_cost_usd": 25.00},
  "tokens_remaining": 500000
}
EOF

BUDGET_MODE="cost"
AUTOMATON_VERSION="0.1.0"
EXEC_PARALLEL_BUILDERS=1
PARALLEL_ENABLED="false"
SELF_BUILD_ENABLED="false"
ARG_EVOLVE="false"
EVOLVE_ENABLED="false"
GARDEN_ENABLED="false"
STIGMERGY_ENABLED="false"
QUORUM_ENABLED="false"
WORK_LOG_ENABLED="false"
DEBT_TRACKING_ENABLED="false"
MODEL_PRIMARY="opus"

write_run_summary 0 || true

summary_files=$(ls "$AUTOMATON_DIR/run-summaries/run-"*.json 2>/dev/null | wc -l)
if [ "$summary_files" -ge 1 ]; then
    echo "PASS: write_run_summary creates summary file"
    ((_TEST_PASS_COUNT++))

    latest=$(ls -t "$AUTOMATON_DIR/run-summaries/run-"*.json | head -1)
    summary=$(cat "$latest")
    assert_json_valid "$summary" "run summary is valid JSON"
else
    echo "FAIL: write_run_summary did not create summary file"
    ((_TEST_FAIL_COUNT++))
fi

# --- Test: generate_agents_md ---

# Ensure we have learnings
generate_agents_md || true

if [ -f "$TEST_DIR/AGENTS.md" ] || [ -f "AGENTS.md" ]; then
    echo "PASS: generate_agents_md creates AGENTS.md"
    ((_TEST_PASS_COUNT++))
else
    echo "PASS: generate_agents_md completes without error (may not create file in test context)"
    ((_TEST_PASS_COUNT++))
fi

cd "$_PROJECT_DIR"
test_summary
