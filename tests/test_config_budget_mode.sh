#!/usr/bin/env bash
# tests/test_config_budget_mode.sh — Verify budget.mode enum validation
# Ensures validate_config() rejects invalid budget.mode values.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"
setup_test_dir

# Source config module (needs combined source for function extraction)
source "$_PROJECT_DIR/lib/state.sh"
source "$_PROJECT_DIR/lib/config.sh"

# Helper: create a config file with a specific budget.mode value
make_config() {
    local mode="$1"
    cat > "$TEST_DIR/test.config.json" <<EOF
{
  "models": {
    "primary": "opus",
    "research": "sonnet",
    "planning": "opus",
    "building": "sonnet",
    "review": "opus",
    "subagent_default": "sonnet"
  },
  "budget": {
    "mode": "$mode",
    "max_total_tokens": 10000000,
    "max_cost_usd": 50,
    "per_iteration": 500000,
    "per_phase": {
      "research": 500000,
      "plan": 1000000,
      "build": 7000000,
      "review": 1500000
    }
  },
  "rate_limits": {
    "tokens_per_minute": 80000,
    "cooldown_seconds": 60,
    "backoff_multiplier": 2
  },
  "execution": {
    "max_iterations": { "research": 3, "plan": 2, "build": 0, "review": 2 },
    "stall_threshold": 3,
    "max_consecutive_failures": 5,
    "qa_enabled": false,
    "qa_max_iterations": 3,
    "qa_blind_validation": false,
    "qa_model": "sonnet"
  },
  "git": {
    "auto_push": false,
    "auto_commit": true,
    "branch_prefix": "automaton/"
  },
  "flags": {
    "dangerously_skip_permissions": true,
    "verbose": false,
    "blind_validation": false
  },
  "blind_validation": {
    "max_diff_lines": 500
  }
}
EOF
}

# --- Test 1: Valid mode "api" passes ---
make_config "api"
output=$(validate_config "$TEST_DIR/test.config.json" 2>&1)
rc=$?
assert_equals "0" "$rc" "budget.mode=api passes validation"

# --- Test 2: Valid mode "allowance" passes ---
make_config "allowance"
output=$(validate_config "$TEST_DIR/test.config.json" 2>&1)
rc=$?
assert_equals "0" "$rc" "budget.mode=allowance passes validation"

# --- Test 3: Invalid mode "foobar" fails ---
make_config "foobar"
output=$(validate_config "$TEST_DIR/test.config.json" 2>&1) || true
assert_contains "$output" "budget.mode" "invalid budget.mode produces error mentioning budget.mode"
assert_contains "$output" "foobar" "invalid budget.mode error mentions the bad value"

# --- Test 4: Invalid mode "API" (wrong case) fails ---
make_config "API"
output=$(validate_config "$TEST_DIR/test.config.json" 2>&1) || true
assert_contains "$output" "budget.mode" "budget.mode=API (wrong case) rejected"

test_summary
