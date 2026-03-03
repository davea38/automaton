#!/usr/bin/env bash
# tests/test_qa_prompt.sh — Tests for spec-46 QA prompt file
# Verifies that PROMPT_qa.md exists, follows spec-29 XML structure,
# and contains the required failure classification instructions.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

prompt_file="$SCRIPT_DIR/../PROMPT_qa.md"

# --- Test 1: PROMPT_qa.md exists ---
assert_file_exists "$prompt_file" "PROMPT_qa.md exists"

# --- Test 2: Has static content marker (spec-29/30) ---
grep -q '<!-- STATIC CONTENT' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has static content marker"

# --- Test 3: Has dynamic context separator (spec-29/30) ---
grep -q '<!-- DYNAMIC CONTEXT BELOW' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has dynamic context separator"

# --- Test 4: Has XML-tagged identity section ---
grep -q '<identity>' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has <identity> section"

# --- Test 5: Has XML-tagged rules section ---
grep -q '<rules>' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has <rules> section"

# --- Test 6: Has XML-tagged instructions section ---
grep -q '<instructions>' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has <instructions> section"

# --- Test 7: Contains failure classification types ---
grep -q 'test_failure' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md mentions test_failure classification"

grep -q 'spec_gap' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md mentions spec_gap classification"

grep -q 'regression' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md mentions regression classification"

grep -q 'style_issue' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md mentions style_issue classification"

# --- Test 8: Contains structured JSON output format ---
grep -q 'failures' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md describes failures output structure"

# --- Test 9: Contains verdict output ---
grep -q 'verdict' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md describes verdict output"

# --- Test 10: Has output_format section ---
grep -q '<output_format>' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has <output_format> section"

# --- Test 11: Contains parallel tool calling directive (spec-29) ---
grep -q 'parallel' "$prompt_file"
rc=$?
assert_exit_code 0 "$rc" "PROMPT_qa.md has parallel tool calling directive"

test_summary
