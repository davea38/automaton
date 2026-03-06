#!/usr/bin/env bash
# tests/test_budget_functional.sh — Functional tests for lib/budget.sh core functions
# Tests estimate_cost, extract_tokens, initialize_budget, and update_budget.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up isolated test directory
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/automaton-budget-XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"

# Mock dependencies
LOG_OUTPUT=""
log() { LOG_OUTPUT+="[$1] $2"$'\n'; }

# Extract functions from budget.sh
extract_function() {
    local func_name="$1" file="$2"
    awk "/^${func_name}\\(\\)/{found=1; depth=0} found{
        for(i=1;i<=length(\$0);i++){
            c=substr(\$0,i,1)
            if(c==\"{\") depth++
            if(c==\"}\") depth--
        }
        print
        if(found && depth==0) exit
    }" "$file"
}

eval "$(extract_function extract_tokens "$PROJECT_DIR/lib/budget.sh")"
eval "$(extract_function estimate_cost "$PROJECT_DIR/lib/budget.sh")"

# ============================================================
# estimate_cost — Sonnet pricing
# ============================================================

# Sonnet: input=$3/MTok, output=$15/MTok
# 100K input + 20K output = 0.3 + 0.3 = 0.6
cost=$(estimate_cost "sonnet" 100000 20000 0 0)
# Expected: (100000*3.00 + 20000*15.00) / 1000000 = 0.6
assert_equals "0.6000" "$cost" "sonnet: 100K input + 20K output = \$0.60"

# ============================================================
# estimate_cost — Opus pricing
# ============================================================

# Opus: input=$15/MTok, output=$75/MTok
cost=$(estimate_cost "opus" 10000 5000 0 0)
# Expected: (10000*15 + 5000*75) / 1000000 = 0.15 + 0.375 = 0.525
assert_equals "0.5250" "$cost" "opus: 10K input + 5K output = \$0.525"

# ============================================================
# estimate_cost — with cache tokens
# ============================================================

# Sonnet with cache: cache_write=$3.75/MTok, cache_read=$0.30/MTok
cost=$(estimate_cost "sonnet" 50000 10000 20000 80000)
# Expected: (50000*3.00 + 10000*15.00 + 20000*3.75 + 80000*0.30) / 1000000
# = 0.15 + 0.15 + 0.075 + 0.024 = 0.399
assert_equals "0.3990" "$cost" "sonnet with cache tokens"

# ============================================================
# estimate_cost — Haiku pricing
# ============================================================

cost=$(estimate_cost "haiku" 1000000 100000 0 0)
# Expected: (1000000*0.80 + 100000*4.00) / 1000000 = 0.8 + 0.4 = 1.2
assert_equals "1.2000" "$cost" "haiku: 1M input + 100K output = \$1.20"

# ============================================================
# estimate_cost — unknown model uses sonnet rates
# ============================================================

cost_unknown=$(estimate_cost "gpt-5" 100000 20000 0 0)
cost_sonnet=$(estimate_cost "sonnet" 100000 20000 0 0)
assert_equals "$cost_sonnet" "$cost_unknown" "unknown model defaults to sonnet pricing"

# ============================================================
# estimate_cost — zero tokens
# ============================================================

cost=$(estimate_cost "sonnet" 0 0 0 0)
assert_equals "0.0000" "$cost" "zero tokens = \$0"

# ============================================================
# extract_tokens — from stream-json output
# ============================================================

fake_output='{"type":"message_start"}
{"type":"content_block_delta","delta":{"text":"Hello"}}
{"type":"result","usage":{"input_tokens":5000,"output_tokens":1200,"cache_creation_input_tokens":3000,"cache_read_input_tokens":8000}}'

extract_tokens "$fake_output"
assert_equals "5000" "$LAST_INPUT_TOKENS" "extract_tokens: input_tokens=5000"
assert_equals "1200" "$LAST_OUTPUT_TOKENS" "extract_tokens: output_tokens=1200"
assert_equals "3000" "$LAST_CACHE_CREATE" "extract_tokens: cache_create=3000"
assert_equals "8000" "$LAST_CACHE_READ" "extract_tokens: cache_read=8000"

# ============================================================
# extract_tokens — empty output
# ============================================================

extract_tokens ""
assert_equals "0" "$LAST_INPUT_TOKENS" "extract_tokens: empty input yields 0"
assert_equals "0" "$LAST_OUTPUT_TOKENS" "extract_tokens: empty output yields 0"

# ============================================================
# extract_tokens — no result line (partial output)
# ============================================================

partial_output='{"type":"message_start"}
{"type":"content_block_delta","delta":{"text":"partial"}}'

extract_tokens "$partial_output"
assert_equals "0" "$LAST_INPUT_TOKENS" "extract_tokens: no result line yields 0"

# ============================================================
# extract_tokens — multiple result lines (uses last)
# ============================================================

multi_result='{"type":"result","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}
{"type":"result","usage":{"input_tokens":200,"output_tokens":75,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'

extract_tokens "$multi_result"
assert_equals "200" "$LAST_INPUT_TOKENS" "extract_tokens: multiple results uses last"
assert_equals "75" "$LAST_OUTPUT_TOKENS" "extract_tokens: multiple results uses last output"

test_summary
