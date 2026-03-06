#!/usr/bin/env bash
# tests/test_budget_checks.sh — Tests for budget enforcement, cache hit ratio,
# context utilization, and display_budget_check functions.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-budget-checks-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Mock log
LOG_OUTPUT=""
log() { LOG_OUTPUT+="[$1] $2"$'\n'; }

# Mock write_state, write_run_summary, commit_persistent_state, send_notification, emit_event
write_state() { :; }
write_run_summary() { :; }
commit_persistent_state() { :; }
send_notification() { :; }
emit_event() { :; }

# Source budget functions
source "$PROJECT_DIR/lib/budget.sh"

# ============================================================
# estimate_cost — default (unknown) model uses sonnet pricing
# ============================================================
cost=$(estimate_cost "unknown_model" 100000 20000 0 0)
assert_equals "0.6000" "$cost" "unknown model falls back to sonnet pricing"

# ============================================================
# estimate_cost — haiku pricing
# ============================================================
cost=$(estimate_cost "haiku" 1000000 0 0 0)
# 1M input * $0.80/MTok = $0.80
assert_equals "0.8000" "$cost" "haiku: 1M input = \$0.80"

# ============================================================
# estimate_cost — with cache tokens
# ============================================================
cost=$(estimate_cost "sonnet" 0 0 100000 100000)
# cache_create: 100K * $3.75/MTok = 0.375; cache_read: 100K * $0.30/MTok = 0.030
assert_equals "0.4050" "$cost" "sonnet: 100K cache_create + 100K cache_read"

# ============================================================
# check_cache_hit_ratio — no budget file
# ============================================================
current_phase="build"
rm -f "$AUTOMATON_DIR/budget.json"
LOG_OUTPUT=""
check_cache_hit_ratio
assert_equals "0" "$?" "check_cache_hit_ratio returns 0 when no budget file"

# ============================================================
# check_cache_hit_ratio — too few iterations
# ============================================================
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{
  "history": [
    {"phase": "build", "cache_hit_ratio": 0.10},
    {"phase": "build", "cache_hit_ratio": 0.20}
  ]
}
EOF
LOG_OUTPUT=""
check_cache_hit_ratio
assert_not_contains "$LOG_OUTPUT" "WARNING" "no warning when < 3 iterations"

# ============================================================
# check_cache_hit_ratio — low ratio triggers warning
# ============================================================
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{
  "history": [
    {"phase": "build", "cache_hit_ratio": 0.10},
    {"phase": "build", "cache_hit_ratio": 0.20},
    {"phase": "build", "cache_hit_ratio": 0.15}
  ]
}
EOF
LOG_OUTPUT=""
check_cache_hit_ratio
assert_contains "$LOG_OUTPUT" "WARNING" "low cache ratio emits warning"
assert_contains "$LOG_OUTPUT" "Cache hit ratio" "warning mentions cache hit ratio"

# ============================================================
# check_cache_hit_ratio — high ratio no warning
# ============================================================
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{
  "history": [
    {"phase": "build", "cache_hit_ratio": 0.80},
    {"phase": "build", "cache_hit_ratio": 0.70},
    {"phase": "build", "cache_hit_ratio": 0.75}
  ]
}
EOF
LOG_OUTPUT=""
check_cache_hit_ratio
assert_not_contains "$LOG_OUTPUT" "WARNING" "high cache ratio no warning"

# ============================================================
# check_context_utilization — within ceiling
# ============================================================
current_phase="build"
phase_iteration=1
LOG_OUTPUT=""
# build ceiling is 80%. 100K total of 200K window = 50%
check_context_utilization 80000 20000 "sonnet"
assert_not_contains "$LOG_OUTPUT" "WARNING" "50% utilization within 80% ceiling"

# ============================================================
# check_context_utilization — exceeds ceiling
# ============================================================
LOG_OUTPUT=""
# 180K total of 200K = 90%, exceeds 80% build ceiling
check_context_utilization 160000 20000 "sonnet"
assert_contains "$LOG_OUTPUT" "WARNING" "90% utilization exceeds 80% ceiling"
assert_contains "$LOG_OUTPUT" "context utilization" "warning mentions context utilization"

# ============================================================
# check_context_utilization — zero tokens
# ============================================================
LOG_OUTPUT=""
check_context_utilization 0 0 "sonnet"
assert_not_contains "$LOG_OUTPUT" "WARNING" "zero tokens no warning"

# ============================================================
# check_context_utilization — research phase has lower ceiling (60%)
# ============================================================
current_phase="research"
LOG_OUTPUT=""
# 130K total of 200K = 65%, exceeds 60% research ceiling
check_context_utilization 100000 30000 "sonnet"
assert_contains "$LOG_OUTPUT" "WARNING" "65% exceeds research ceiling of 60%"

# ============================================================
# check_budget — API mode: within limits
# ============================================================
current_phase="build"
BUDGET_MODE="api"
BUDGET_PER_ITERATION=500000
BUDGET_MAX_TOKENS=10000000
BUDGET_MAX_USD=50
BUDGET_PHASE_BUILD=7000000
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{
  "mode": "api",
  "limits": {"max_total_tokens": 10000000, "max_cost_usd": 50},
  "used": {
    "total_input": 100000,
    "total_output": 20000,
    "estimated_cost_usd": 1.50,
    "by_phase": {
      "build": {"input": 100000, "output": 20000}
    }
  }
}
EOF
LOG_OUTPUT=""
result=0
check_budget 100000 20000 || result=$?
assert_equals "0" "$result" "API mode: within limits returns 0"

# ============================================================
# check_budget — API mode: per-iteration warning
# ============================================================
BUDGET_PER_ITERATION=100000
LOG_OUTPUT=""
check_budget 100000 20000 || true
assert_contains "$LOG_OUTPUT" "WARNING: Iteration used" "per-iteration warning emitted"

# ============================================================
# check_budget — API mode: phase budget exceeded returns 1
# ============================================================
BUDGET_PHASE_BUILD=100000
BUDGET_PER_ITERATION=500000
cat > "$AUTOMATON_DIR/budget.json" <<'EOF'
{
  "mode": "api",
  "limits": {"max_total_tokens": 10000000, "max_cost_usd": 50},
  "used": {
    "total_input": 200000,
    "total_output": 50000,
    "estimated_cost_usd": 1.50,
    "by_phase": {
      "build": {"input": 200000, "output": 50000}
    }
  }
}
EOF
LOG_OUTPUT=""
result=0
check_budget 100000 20000 || result=$?
assert_equals "1" "$result" "API mode: phase budget exceeded returns 1"
assert_contains "$LOG_OUTPUT" "Phase budget exhausted" "phase exhaustion logged"

test_summary
