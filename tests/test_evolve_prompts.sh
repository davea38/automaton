#!/usr/bin/env bash
# tests/test_evolve_prompts.sh — Tests for spec-41 §14 evolution prompt files
# Verifies that all 3 evolution prompt files exist with correct spec-29 XML
# structure, static content markers, phase-specific sections, and output format.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

root_dir="$SCRIPT_DIR/.."

PROMPTS=("PROMPT_evolve_reflect" "PROMPT_evolve_ideate" "PROMPT_evolve_observe")

# --- Test 1-3: All evolution prompt files exist ---
for prompt in "${PROMPTS[@]}"; do
    assert_file_exists "$root_dir/${prompt}.md" "${prompt}.md exists"
done

# --- Test 4-6: Each prompt has static content marker (spec-29/30 cache boundary) ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<!-- STATIC CONTENT" "${prompt}.md has static content marker"
done

# --- Test 7-9: Each prompt has <context> section ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<context>" "${prompt}.md has <context> section"
done

# --- Test 10-12: Each prompt has <identity> section ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<identity>" "${prompt}.md has <identity> section"
done

# --- Test 13-15: Each prompt has <rules> section ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<rules>" "${prompt}.md has <rules> section"
done

# --- Test 16-18: Each prompt has <instructions> section ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<instructions>" "${prompt}.md has <instructions> section"
done

# --- Test 19-21: Each prompt has <output_format> section ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<output_format>" "${prompt}.md has <output_format> section"
done

# --- Test 22-24: Each prompt has <dynamic_context> section ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<dynamic_context>" "${prompt}.md has <dynamic_context> section"
done

# --- Test 25-27: Each prompt has DYNAMIC CONTEXT BELOW separator ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "<!-- DYNAMIC CONTEXT BELOW" "${prompt}.md has dynamic context separator"
done

# --- Test 28-30: Each prompt documents JSON output with cycle_id ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "cycle_id" "${prompt}.md documents cycle_id in output"
done

# --- REFLECT-specific tests ---
reflect="$root_dir/PROMPT_evolve_reflect.md"
reflect_content=$(cat "$reflect")

# Test 31: REFLECT references metrics analysis
assert_contains "$reflect_content" "metric" "REFLECT prompt references metrics"

# Test 32: REFLECT references signal emission format
assert_contains "$reflect_content" "signal" "REFLECT prompt references signals"

# Test 33: REFLECT references auto-seed criteria
assert_contains "$reflect_content" "auto-seed" "REFLECT prompt references auto-seed"

# --- IDEATE-specific tests ---
ideate="$root_dir/PROMPT_evolve_ideate.md"
ideate_content=$(cat "$ideate")

# Test 34: IDEATE references evidence evaluation
assert_contains "$ideate_content" "evidence" "IDEATE prompt references evidence"

# Test 35: IDEATE references promotion criteria
assert_contains "$ideate_content" "promot" "IDEATE prompt references promotion"

# Test 36: IDEATE references priority scoring
assert_contains "$ideate_content" "priority" "IDEATE prompt references priority"

# --- OBSERVE-specific tests ---
observe="$root_dir/PROMPT_evolve_observe.md"
observe_content=$(cat "$observe")

# Test 37: OBSERVE references before/after comparison
assert_contains "$observe_content" "before" "OBSERVE prompt references before comparison"

# Test 38: OBSERVE references harvest/wilt criteria
assert_contains "$observe_content" "harvest" "OBSERVE prompt references harvest"

# Test 39: OBSERVE references signal emission
assert_contains "$observe_content" "signal" "OBSERVE prompt references signal emission"

# --- Test 40-42: Each prompt mentions READ-ONLY constraint ---
for prompt in "${PROMPTS[@]}"; do
    file="$root_dir/${prompt}.md"
    content=$(cat "$file")
    assert_contains "$content" "READ-ONLY" "${prompt}.md has READ-ONLY constraint"
done

test_summary
