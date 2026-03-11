#!/usr/bin/env bash
# tests/test_scaffolder_files.sh — Verify scaffolder TEMPLATE_FILES covers all templates
cd "$(dirname "$0")/.." || exit 1
source tests/test_helpers.sh

# ---------------------------------------------------------------------------
# Verify every file in templates/ is either in TEMPLATE_FILES or handled separately
# ---------------------------------------------------------------------------

echo "=== scaffolder: all PROMPT files listed ==="
for prompt in PROMPT_converse.md PROMPT_research.md PROMPT_plan.md PROMPT_build.md \
              PROMPT_review.md PROMPT_self_research.md PROMPT_self_plan.md PROMPT_wizard.md PROMPT_qa.md \
              PROMPT_evolve_reflect.md PROMPT_evolve_ideate.md PROMPT_evolve_observe.md; do
    assert_contains "$(cat bin/cli.js)" "'$prompt'" "TEMPLATE_FILES includes $prompt"
done

echo "=== scaffolder: core files listed ==="
for f in automaton.sh automaton.config.json AGENTS.md IMPLEMENTATION_PLAN.md CLAUDE.md PRD.md; do
    assert_contains "$(cat bin/cli.js)" "'$f'" "TEMPLATE_FILES includes $f"
done

echo "=== scaffolder: template files exist for all TEMPLATE_FILES entries ==="
# Extract filenames from the TEMPLATE_FILES array only (between the array brackets)
template_files=$(sed -n '/^const TEMPLATE_FILES/,/^];/p' bin/cli.js | grep -oP "'[^']+'" | tr -d "'")
for f in $template_files; do
    assert_file_exists "templates/$f" "Template exists for $f"
done

echo "=== scaffolder: lib/ directory copy function exists ==="
assert_contains "$(cat bin/cli.js)" "copyLibDirectory" "copyLibDirectory function present"

echo "=== scaffolder: all lib modules have templates ==="
for mod in lib/*.sh; do
    mod_name=$(basename "$mod")
    assert_file_exists "templates/lib/$mod_name" "Template exists for lib/$mod_name"
done

echo "=== scaffolder: template lib files match root lib files ==="
mismatch_count=0
for mod in lib/*.sh; do
    mod_name=$(basename "$mod")
    if ! diff -q "$mod" "templates/lib/$mod_name" > /dev/null 2>&1; then
        echo "FAIL: templates/lib/$mod_name differs from lib/$mod_name" >&2
        mismatch_count=$((mismatch_count + 1))
    fi
done
assert_equals "0" "$mismatch_count" "All template lib files in sync with root"


echo "=== 28.4 scaffolder: template jq-optimized lib files in sync ==="
for mod in lib/budget.sh lib/qa.sh lib/evolution.sh; do
    mod_name=$(basename "$mod")
    if [ -f "templates/lib/$mod_name" ]; then
        if ! diff -q "$mod" "templates/lib/$mod_name" > /dev/null 2>&1; then
            echo "FAIL: 28.4: templates/lib/$mod_name not synced after jq batching optimization" >&2
            ((_TEST_FAIL_COUNT++))
        else
            echo "PASS: 28.4: templates/lib/$mod_name in sync with lib/$mod_name"
            ((_TEST_PASS_COUNT++))
        fi
    fi
done

echo "=== 29.3 scaffolder: template parallel split modules exist ==="
assert_file_exists "templates/lib/parallel_core.sh" \
    "29.3: templates/lib/parallel_core.sh exists after split"
assert_file_exists "templates/lib/parallel_teams.sh" \
    "29.3: templates/lib/parallel_teams.sh exists after split"

test_summary
