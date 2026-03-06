#!/usr/bin/env bash
# tests/test_config_load_behavioral.sh — Behavioral tests for load_config()
# Verifies that load_config() correctly parses config files AND falls back
# to defaults when config file is missing or has partial values.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Helper: source config.sh and load a given config file, then run assertions
_load_and_test() {
    source "$_PROJECT_DIR/lib/config.sh"
    CONFIG_FILE="$1" load_config
}

# --- Test 1: load_config with full config sets all values correctly ---
source "$_PROJECT_DIR/lib/config.sh"
CONFIG_FILE="$_PROJECT_DIR/automaton.config.json" load_config
assert_equals "opus" "$MODEL_PRIMARY" "MODEL_PRIMARY loaded from config"
assert_equals "sonnet" "$MODEL_RESEARCH" "MODEL_RESEARCH loaded from config"
assert_equals "10000000" "$BUDGET_MAX_TOKENS" "BUDGET_MAX_TOKENS loaded from config"
assert_matches "$BUDGET_MAX_USD" "^50" "BUDGET_MAX_USD loaded from config"
assert_equals "80000" "$RATE_TOKENS_PER_MINUTE" "RATE_TOKENS_PER_MINUTE loaded from config"
assert_equals "3" "$EXEC_MAX_ITER_RESEARCH" "EXEC_MAX_ITER_RESEARCH loaded from config"
assert_equals "true" "$GIT_AUTO_PUSH" "GIT_AUTO_PUSH loaded from config"
assert_equals "automaton/" "$GIT_BRANCH_PREFIX" "GIT_BRANCH_PREFIX loaded from config"
assert_equals "api" "$BUDGET_MODE" "BUDGET_MODE loaded from config"
assert_equals "false" "$SELF_BUILD_ENABLED" "SELF_BUILD_ENABLED loaded from config"
assert_equals "warn" "$GUARDRAILS_MODE" "GUARDRAILS_MODE loaded from config"

# --- Test 2: load_config falls back to defaults when no config file ---
CONFIG_FILE="/nonexistent/config.json" load_config
assert_equals "(defaults)" "$CONFIG_FILE_USED" "CONFIG_FILE_USED reports defaults"
assert_equals "opus" "$MODEL_PRIMARY" "MODEL_PRIMARY defaults to opus"
assert_equals "sonnet" "$MODEL_RESEARCH" "MODEL_RESEARCH defaults to sonnet"
assert_equals "10000000" "$BUDGET_MAX_TOKENS" "BUDGET_MAX_TOKENS defaults to 10M"
assert_equals "80000" "$RATE_TOKENS_PER_MINUTE" "RATE_TOKENS_PER_MINUTE defaults to 80K"
assert_equals "api" "$BUDGET_MODE" "BUDGET_MODE defaults to api"
assert_equals "true" "$GARDEN_ENABLED" "GARDEN_ENABLED defaults to true"
assert_equals "warn" "$GUARDRAILS_MODE" "GUARDRAILS_MODE defaults to warn"

# --- Test 3: load_config handles minimal config (only models section) ---
setup_test_dir
cat > "$TEST_DIR/minimal.json" <<'EOF'
{
    "models": {
        "primary": "haiku"
    }
}
EOF
CONFIG_FILE="$TEST_DIR/minimal.json" load_config
assert_equals "haiku" "$MODEL_PRIMARY" "partial config: MODEL_PRIMARY overridden"
assert_equals "sonnet" "$MODEL_RESEARCH" "partial config: MODEL_RESEARCH falls back to default"
assert_equals "10000000" "$BUDGET_MAX_TOKENS" "partial config: BUDGET_MAX_TOKENS falls back"
assert_equals "true" "$GARDEN_ENABLED" "partial config: GARDEN_ENABLED falls back"

# --- Test 4: load_config handles empty notifications (no field collapsing) ---
CONFIG_FILE="$_PROJECT_DIR/automaton.config.json" load_config
assert_equals "" "$NOTIFY_WEBHOOK_URL" "empty webhook URL preserved"
assert_equals "" "$NOTIFY_COMMAND" "empty notify command preserved"
assert_equals "5" "$NOTIFY_TIMEOUT" "notify timeout loaded correctly after empty fields"
assert_equals "true" "$WORK_LOG_ENABLED" "work_log.enabled correct after empty fields"
assert_equals "normal" "$WORK_LOG_LEVEL" "work_log.log_level correct after empty fields"
assert_equals "true" "$DEBT_TRACKING_ENABLED" "debt_tracking.enabled correct after empty fields"
assert_equals "20" "$DEBT_TRACKING_THRESHOLD" "debt_tracking.threshold correct after empty fields"
assert_equals "warn" "$GUARDRAILS_MODE" "guardrails_mode correct (last field)"

# --- Test 5: load_config handles non-default values ---
cat > "$TEST_DIR/custom.json" <<'EOF'
{
    "models": { "primary": "haiku", "research": "haiku", "planning": "haiku",
                "building": "haiku", "review": "haiku", "subagent_default": "haiku" },
    "budget": { "max_total_tokens": 5000000, "max_cost_usd": 25,
                "per_phase": { "research": 100000, "plan": 200000, "build": 300000, "review": 400000 },
                "per_iteration": 50000, "mode": "allowance",
                "weekly_allowance_tokens": 10000000, "allowance_reset_day": "friday",
                "reserve_percentage": 10 },
    "notifications": { "webhook_url": "https://example.com/hook", "command": "echo done",
                        "events": ["run_completed"], "timeout_seconds": 10 },
    "guardrails_mode": "block"
}
EOF
CONFIG_FILE="$TEST_DIR/custom.json" load_config
assert_equals "haiku" "$MODEL_PRIMARY" "custom: MODEL_PRIMARY"
assert_equals "5000000" "$BUDGET_MAX_TOKENS" "custom: BUDGET_MAX_TOKENS"
assert_equals "allowance" "$BUDGET_MODE" "custom: BUDGET_MODE"
assert_equals "friday" "$BUDGET_ALLOWANCE_RESET_DAY" "custom: BUDGET_ALLOWANCE_RESET_DAY"
assert_equals "https://example.com/hook" "$NOTIFY_WEBHOOK_URL" "custom: NOTIFY_WEBHOOK_URL"
assert_equals "echo done" "$NOTIFY_COMMAND" "custom: NOTIFY_COMMAND"
assert_equals "10" "$NOTIFY_TIMEOUT" "custom: NOTIFY_TIMEOUT"
assert_equals "block" "$GUARDRAILS_MODE" "custom: GUARDRAILS_MODE"

# --- Test 6: load_config with invalid JSON returns error ---
echo "not json" > "$TEST_DIR/bad.json"
if CONFIG_FILE="$TEST_DIR/bad.json" load_config 2>/dev/null; then
    echo "FAIL: load_config should fail on invalid JSON" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: load_config rejects invalid JSON"
    ((_TEST_PASS_COUNT++))
fi

test_summary
