#!/usr/bin/env bash
# tests/test_bootstrap_prompt_placeholder.sh — tests for bootstrap manifest placeholder in PROMPT files (spec-37)
# Verifies that Phase 0 "Load Context" instructions are replaced with bootstrap
# manifest placeholders and agents are told not to read state files themselves.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# --- Test 1: PROMPT_build.md has BOOTSTRAP_MANIFEST placeholder in dynamic_context ---
dynamic_section=$(sed -n '/<dynamic_context>/,/<\/dynamic_context>/p' "$PROJECT_ROOT/PROMPT_build.md")
echo "$dynamic_section" | grep -q 'BOOTSTRAP_MANIFEST'
assert_exit_code 0 $? "PROMPT_build.md has BOOTSTRAP_MANIFEST in dynamic_context"

# --- Test 2: PROMPT_plan.md has BOOTSTRAP_MANIFEST placeholder ---
dynamic_section=$(sed -n '/<dynamic_context>/,/<\/dynamic_context>/p' "$PROJECT_ROOT/PROMPT_plan.md")
echo "$dynamic_section" | grep -q 'BOOTSTRAP_MANIFEST'
assert_exit_code 0 $? "PROMPT_plan.md has BOOTSTRAP_MANIFEST in dynamic_context"

# --- Test 3: PROMPT_research.md has BOOTSTRAP_MANIFEST placeholder ---
dynamic_section=$(sed -n '/<dynamic_context>/,/<\/dynamic_context>/p' "$PROJECT_ROOT/PROMPT_research.md")
echo "$dynamic_section" | grep -q 'BOOTSTRAP_MANIFEST'
assert_exit_code 0 $? "PROMPT_research.md has BOOTSTRAP_MANIFEST in dynamic_context"

# --- Test 4: PROMPT_review.md has BOOTSTRAP_MANIFEST placeholder ---
dynamic_section=$(sed -n '/<dynamic_context>/,/<\/dynamic_context>/p' "$PROJECT_ROOT/PROMPT_review.md")
echo "$dynamic_section" | grep -q 'BOOTSTRAP_MANIFEST'
assert_exit_code 0 $? "PROMPT_review.md has BOOTSTRAP_MANIFEST in dynamic_context"

# --- Test 5: PROMPT_self_research.md has BOOTSTRAP_MANIFEST placeholder ---
dynamic_section=$(sed -n '/<dynamic_context>/,/<\/dynamic_context>/p' "$PROJECT_ROOT/PROMPT_self_research.md")
echo "$dynamic_section" | grep -q 'BOOTSTRAP_MANIFEST'
assert_exit_code 0 $? "PROMPT_self_research.md has BOOTSTRAP_MANIFEST in dynamic_context"

# --- Test 6: No Phase 0 Load Context in agent PROMPT files (replaced by bootstrap) ---
for file in PROMPT_build.md PROMPT_plan.md PROMPT_research.md PROMPT_review.md; do
    if grep -q "Phase 0.*Load Context" "$PROJECT_ROOT/$file"; then
        echo "FAIL: $file still has Phase 0 Load Context instructions" >&2
        ((_TEST_FAIL_COUNT++))
    else
        echo "PASS: $file has no Phase 0 Load Context"
        ((_TEST_PASS_COUNT++))
    fi
done

# --- Test 7: PROMPT_self_research.md Phase 0 replaced ---
if grep -q "Phase 0.*Load Context" "$PROJECT_ROOT/PROMPT_self_research.md"; then
    echo "FAIL: PROMPT_self_research.md still has Phase 0 Load Context" >&2
    ((_TEST_FAIL_COUNT++))
else
    echo "PASS: PROMPT_self_research.md Phase 0 Load Context replaced"
    ((_TEST_PASS_COUNT++))
fi

# --- Test 8: Context sections note agents don't need to read state files ---
for file in PROMPT_build.md PROMPT_plan.md PROMPT_research.md PROMPT_review.md; do
    if grep -qi "do NOT need to read\|pre-assembled by\|bootstrap" "$PROJECT_ROOT/$file"; then
        echo "PASS: $file references bootstrap/pre-assembled context"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: $file should reference bootstrap/pre-assembled context" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Test 9: PROMPT_converse.md Phase 0 is preserved (it's interactive, not context loading) ---
if grep -q "Phase 0.*Greet and Orient" "$PROJECT_ROOT/PROMPT_converse.md"; then
    echo "PASS: PROMPT_converse.md preserves Phase 0 Greet and Orient"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: PROMPT_converse.md should keep Phase 0 Greet and Orient" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Template files match root PROMPT files ---
for file in PROMPT_build.md PROMPT_plan.md PROMPT_research.md PROMPT_review.md PROMPT_self_research.md; do
    if [ -f "$PROJECT_ROOT/templates/$file" ]; then
        if diff -q "$PROJECT_ROOT/$file" "$PROJECT_ROOT/templates/$file" > /dev/null 2>&1; then
            echo "PASS: templates/$file matches root $file"
            ((_TEST_PASS_COUNT++))
        else
            echo "FAIL: templates/$file differs from root $file" >&2
            ((_TEST_FAIL_COUNT++))
        fi
    fi
done

test_summary
