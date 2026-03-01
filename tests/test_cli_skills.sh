#!/usr/bin/env bash
# tests/test_cli_skills.sh — Tests for spec-44 §44.4 CLI skill files
# Verifies that all 4 skill files exist with correct structure and content.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

skills_dir="$SCRIPT_DIR/../.claude/skills"

# ============================================================
# garden-tender.md
# ============================================================

skill_file="$skills_dir/garden-tender.md"

# --- Test 1: garden-tender.md exists ---
assert_file_exists "$skill_file" "garden-tender.md skill file exists"

# --- Test 2: Has name in frontmatter ---
if head -5 "$skill_file" | grep -q 'name: garden-tender'; then
    echo "PASS: garden-tender has name in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should have name in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Has description ---
if head -5 "$skill_file" | grep -q 'description:'; then
    echo "PASS: garden-tender has description"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should have description" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Has tools field ---
if head -5 "$skill_file" | grep -q 'tools:'; then
    echo "PASS: garden-tender has tools field"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should have tools field" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Has Instructions section ---
grep_result=$(grep -c '## Instructions' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: garden-tender has Instructions section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should have Instructions section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Has Constraints section ---
grep_result=$(grep -c '## Constraints' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: garden-tender has Constraints section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should have Constraints section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: References garden index ---
grep_result=$(grep -c '_index.json' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: garden-tender references _index.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should reference _index.json for garden state" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: References watering/evidence ---
grep_result=$(grep -ci 'water\|evidence' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: garden-tender references watering/evidence"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should reference watering or evidence" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: References pruning/wilting ---
grep_result=$(grep -ci 'prune\|wilt' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: garden-tender references pruning/wilting"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: garden-tender should reference pruning or wilting" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# constitutional-review.md
# ============================================================

skill_file="$skills_dir/constitutional-review.md"

# --- Test 10: constitutional-review.md exists ---
assert_file_exists "$skill_file" "constitutional-review.md skill file exists"

# --- Test 11: Has name in frontmatter ---
if head -5 "$skill_file" | grep -q 'name: constitutional-review'; then
    echo "PASS: constitutional-review has name in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should have name in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Has Instructions section ---
grep_result=$(grep -c '## Instructions' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: constitutional-review has Instructions section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should have Instructions section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: References constitution.md ---
grep_result=$(grep -c 'constitution.md' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: constitutional-review references constitution.md"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should reference constitution.md" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: References articles and protection levels ---
grep_result=$(grep -ci 'article\|protection' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: constitutional-review references articles/protection"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should reference articles and protection levels" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: References amendment process ---
grep_result=$(grep -ci 'amend' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: constitutional-review references amendments"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should reference amendment process" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: References constitution-history.json ---
grep_result=$(grep -c 'constitution-history.json' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: constitutional-review references constitution-history.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should reference constitution-history.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 17: Has Constraints section ---
grep_result=$(grep -c '## Constraints' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: constitutional-review has Constraints section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: constitutional-review should have Constraints section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# signal-reader.md
# ============================================================

skill_file="$skills_dir/signal-reader.md"

# --- Test 18: signal-reader.md exists ---
assert_file_exists "$skill_file" "signal-reader.md skill file exists"

# --- Test 19: Has name in frontmatter ---
if head -5 "$skill_file" | grep -q 'name: signal-reader'; then
    echo "PASS: signal-reader has name in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should have name in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 20: Has Instructions section ---
grep_result=$(grep -c '## Instructions' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: signal-reader has Instructions section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should have Instructions section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 21: References signals.json ---
grep_result=$(grep -c 'signals.json' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: signal-reader references signals.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should reference signals.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 22: References signal strength ---
grep_result=$(grep -ci 'strength' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: signal-reader references signal strength"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should reference signal strength" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 23: References unlinked signals ---
grep_result=$(grep -ci 'unlinked' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: signal-reader references unlinked signals"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should reference unlinked signals" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 24: References signal types ---
grep_result=$(grep -ci 'type\|recurring_pattern\|efficiency_opp\|quality_concern' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: signal-reader references signal types"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should reference signal types" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 25: Has Constraints section ---
grep_result=$(grep -c '## Constraints' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: signal-reader has Constraints section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: signal-reader should have Constraints section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# ============================================================
# metrics-analyzer.md
# ============================================================

skill_file="$skills_dir/metrics-analyzer.md"

# --- Test 26: metrics-analyzer.md exists ---
assert_file_exists "$skill_file" "metrics-analyzer.md skill file exists"

# --- Test 27: Has name in frontmatter ---
if head -5 "$skill_file" | grep -q 'name: metrics-analyzer'; then
    echo "PASS: metrics-analyzer has name in frontmatter"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should have name in frontmatter" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 28: Has Instructions section ---
grep_result=$(grep -c '## Instructions' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: metrics-analyzer has Instructions section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should have Instructions section" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 29: References evolution-metrics.json ---
grep_result=$(grep -c 'evolution-metrics.json' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: metrics-analyzer references evolution-metrics.json"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should reference evolution-metrics.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 30: References trend analysis ---
grep_result=$(grep -ci 'trend' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: metrics-analyzer references trends"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should reference trend analysis" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 31: References 5 metric categories ---
grep_result=$(grep -ci 'capability\|efficiency\|quality\|innovation\|health' "$skill_file" || true)
if [ "$grep_result" -ge 3 ]; then
    echo "PASS: metrics-analyzer references metric categories"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should reference metric categories (capability, efficiency, quality, innovation, health)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 32: References baselines ---
grep_result=$(grep -ci 'baseline' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: metrics-analyzer references baselines"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should reference baselines for comparison" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 33: Has Constraints section ---
grep_result=$(grep -c '## Constraints' "$skill_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: metrics-analyzer has Constraints section"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: metrics-analyzer should have Constraints section" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
