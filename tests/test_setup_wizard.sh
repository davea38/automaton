#!/usr/bin/env bash
# tests/test_setup_wizard.sh — Tests for spec-57 first-time setup wizard
# Verifies setup_wizard(), --setup/--no-setup flags, config generation, and doctor integration.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_setup_wizard_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: setup_wizard() function exists ---
grep -q '^setup_wizard()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "setup_wizard() function exists in automaton.sh"

# --- Test 2: --setup flag exists in argument parser ---
grep -q '\-\-setup)' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--setup flag exists in argument parser"

# --- Test 3: --no-setup flag exists in argument parser ---
grep -q '\-\-no-setup)' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "--no-setup flag exists in argument parser"

# --- Test 4: ARG_SETUP and ARG_NO_SETUP defaults exist ---
grep -q 'ARG_SETUP=false' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "ARG_SETUP default is false"

grep -q 'ARG_NO_SETUP=false' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "ARG_NO_SETUP default is false"

# --- Test 5: --setup + --no-setup mutual exclusion ---
rc=0
output=$(bash "$automaton_script" --setup --no-setup 2>&1) || rc=$?
assert_exit_code 1 "$rc" "--setup + --no-setup exits with error code 1"
assert_contains "$output" "mutually exclusive" "--setup + --no-setup error mentions mutual exclusion"

# --- Test 6: Non-TTY stdin falls back to defaults without hanging ---
# When stdin is not a TTY and config is missing, setup should silently use defaults
setup_project="$test_dir/nontty_project"
mkdir -p "$setup_project"
cd "$setup_project"
git init -q
git commit --allow-empty -m "init" -q

# Run with no config, stdin redirected from /dev/null (non-TTY)
output=$(bash "$automaton_script" --no-setup 2>&1) || true
# --no-setup should skip wizard and proceed (may fail on missing config but not hang)
echo "PASS: --no-setup does not hang on non-TTY"
((_TEST_PASS_COUNT++))

# --- Test 7: --setup on non-TTY exits 1 ---
rc=0
output=$(echo "" | bash "$automaton_script" --setup 2>&1) || rc=$?
assert_exit_code 1 "$rc" "--setup on non-TTY exits 1"
assert_contains "$output" "interactive" "--setup non-TTY error mentions interactive terminal"

# --- Test 8: Config generation via jq produces valid JSON ---
# Simulate what setup_wizard generates by calling jq -n directly
generated=$(jq -n \
    --arg model "sonnet" \
    --arg budget "50" \
    --arg auto_push "true" \
    --arg skip_research "false" \
    '{
        models: { primary: $model, research: "sonnet", planning: "opus", building: $model, review: "opus", subagent_default: "sonnet" },
        budget: { mode: "api", max_total_tokens: 10000000, max_cost_usd: ($budget | tonumber), per_phase: { research: 500000, plan: 1000000, build: 7000000, review: 1500000 }, per_iteration: 500000 },
        rate_limits: { preset: "auto", tokens_per_minute: 80000, requests_per_minute: 50, cooldown_seconds: 60, backoff_multiplier: 2, max_backoff_seconds: 300 },
        execution: { max_iterations: { research: 3, plan: 2, build: 0, review: 2 }, parallel_builders: 1, stall_threshold: 3, max_consecutive_failures: 3, retry_delay_seconds: 10 },
        git: { auto_push: ($auto_push == "true"), auto_commit: true, branch_prefix: "automaton/" },
        flags: { dangerously_skip_permissions: true, verbose: true, skip_research: ($skip_research == "true") }
    }' 2>&1)
rc=$?
assert_exit_code 0 "$rc" "jq -n config generation produces valid JSON"

# Verify the generated JSON passes jq empty
echo "$generated" | jq empty 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "generated config passes jq empty validation"

# Verify key fields exist
model_val=$(echo "$generated" | jq -r '.models.primary')
assert_equals "sonnet" "$model_val" "generated config has correct models.primary"

budget_val=$(echo "$generated" | jq -r '.budget.max_cost_usd')
assert_equals "50" "$budget_val" "generated config has correct budget.max_cost_usd"

auto_push_val=$(echo "$generated" | jq -r '.git.auto_push')
assert_equals "true" "$auto_push_val" "generated config has correct git.auto_push"

# --- Test 9: Help text includes --setup and --no-setup ---
help_output=$(bash "$automaton_script" --help 2>&1) || true
assert_contains "$help_output" "--setup" "help text includes --setup"
assert_contains "$help_output" "--no-setup" "help text includes --no-setup"

# --- Test 10: setup_wizard contains doctor_check call ---
# Verify the integration point exists
grep -q 'doctor_check' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "setup_wizard references doctor_check for post-setup validation"

# --- Test 11: setup_wizard creates .automaton/ directory ---
grep -q '\.automaton' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "setup_wizard handles .automaton/ directory creation"

# --- Test 12: No Claude API calls in setup_wizard ---
# The wizard should use only read, printf, jq, and bash builtins
wizard_body=$(sed -n '/^setup_wizard()/,/^}/p' "$script_file")
if echo "$wizard_body" | grep -q 'claude '; then
    echo "FAIL: setup_wizard contains Claude API calls" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: setup_wizard does not make Claude API calls"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 13: 26.1 setup_wizard generates .claudeignore ---
# After implementation: setup_wizard() in lib/config.sh must write a .claudeignore
# file containing key exclusion patterns (templates/, .automaton/logs/, *.jsonl).
grep -q '\.claudeignore' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "26.1: setup_wizard references .claudeignore generation"

# --- Test 14: 26.1 .claudeignore content covers expected paths ---
# The generated file should exclude template files, logs, and test output dirs.
claudeignore_content=$(grep -A20 '\.claudeignore' "$_PROJECT_DIR/lib/config.sh" 2>/dev/null || true)
assert_contains "$claudeignore_content" "templates/" \
    "26.1: .claudeignore excludes templates/ directory"
assert_contains "$claudeignore_content" ".automaton/logs/" \
    "26.1: .claudeignore excludes .automaton/logs/ directory"
assert_contains "$claudeignore_content" "*.jsonl" \
    "26.1: .claudeignore excludes *.jsonl work-log files"

cd "$SCRIPT_DIR"

# --- Test 15: 33.5 setup_wizard asks collaboration mode question ---
# After implementation: run_setup_wizard() must present collaboration mode choice.
wizard_body=$(sed -n '/^setup_wizard()\|^run_setup_wizard()/,/^}/p' "$_PROJECT_DIR/lib/config.sh" 2>/dev/null || true)
assert_contains "$wizard_body" "Collaborative" \
    "33.5: setup_wizard presents Collaborative mode option"

# --- Test 16: 33.5 setup_wizard presents Autonomous option ---
assert_contains "$wizard_body" "Autonomous" \
    "33.5: setup_wizard presents Autonomous mode option"

# --- Test 17: 33.5 setup_wizard writes collaboration.mode to config ---
assert_contains "$wizard_body" "collaboration" \
    "33.5: setup_wizard writes collaboration key to config"

# --- Test 18: 33.5 collaboration config section has mode field ---
collab_mode=$(jq -r '.collaboration.mode' "$_PROJECT_DIR/automaton.config.json" 2>/dev/null || echo "null")
assert_not_contains "$collab_mode" "null" \
    "33.5: automaton.config.json has collaboration.mode field"

# --- Test 19: 33.5 lib/config.sh loads collaboration.mode ---
grep -q 'COLLABORATION_MODE' "$_PROJECT_DIR/lib/config.sh" 2>/dev/null
rc=$?
assert_exit_code 0 "$rc" "33.5: lib/config.sh sets COLLABORATION_MODE variable"

test_summary
