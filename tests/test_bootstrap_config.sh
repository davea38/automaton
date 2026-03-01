#!/usr/bin/env bash
# tests/test_bootstrap_config.sh — Verify bootstrap config fields in automaton.config.json
# Spec-37: execution.bootstrap_enabled, execution.bootstrap_script, execution.bootstrap_timeout_ms

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Test 1: Root config contains bootstrap_enabled ---
val=$(jq -r '.execution.bootstrap_enabled' "$PROJECT_ROOT/automaton.config.json")
assert_equals "true" "$val" "root config has bootstrap_enabled=true"

# --- Test 2: Root config contains bootstrap_script ---
val=$(jq -r '.execution.bootstrap_script' "$PROJECT_ROOT/automaton.config.json")
assert_equals ".automaton/init.sh" "$val" "root config has bootstrap_script"

# --- Test 3: Root config contains bootstrap_timeout_ms ---
val=$(jq -r '.execution.bootstrap_timeout_ms' "$PROJECT_ROOT/automaton.config.json")
assert_equals "2000" "$val" "root config has bootstrap_timeout_ms=2000"

# --- Test 4: Template config contains bootstrap_enabled ---
val=$(jq -r '.execution.bootstrap_enabled' "$PROJECT_ROOT/templates/automaton.config.json")
assert_equals "true" "$val" "template config has bootstrap_enabled=true"

# --- Test 5: Template config contains bootstrap_script ---
val=$(jq -r '.execution.bootstrap_script' "$PROJECT_ROOT/templates/automaton.config.json")
assert_equals ".automaton/init.sh" "$val" "template config has bootstrap_script"

# --- Test 6: Template config contains bootstrap_timeout_ms ---
val=$(jq -r '.execution.bootstrap_timeout_ms' "$PROJECT_ROOT/templates/automaton.config.json")
assert_equals "2000" "$val" "template config has bootstrap_timeout_ms=2000"

# --- Test 7: automaton.sh reads bootstrap_enabled from config ---
grep -q 'bootstrap_enabled' "$PROJECT_ROOT/automaton.sh"
assert_exit_code 0 $? "automaton.sh references bootstrap_enabled"

# --- Test 8: Both config files are valid JSON ---
jq empty "$PROJECT_ROOT/automaton.config.json" 2>/dev/null
assert_exit_code 0 $? "root config is valid JSON"
jq empty "$PROJECT_ROOT/templates/automaton.config.json" 2>/dev/null
assert_exit_code 0 $? "template config is valid JSON"

test_summary
