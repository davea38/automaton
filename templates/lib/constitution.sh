#!/usr/bin/env bash
# lib/constitution.sh — Constitutional governance: creation, validation, checking, and amendments.
# Spec references: spec-41 (constitution system), spec-44 (constitution CLI)

_constitution_create_default() {
    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    # Do not overwrite existing constitution
    if [ -f "$const_file" ]; then
        log "CONSTITUTION" "Constitution already exists at $const_file"
        return 0
    fi

    local ratified_date
    ratified_date=$(date -u +%Y-%m-%d)

    cat > "$const_file" << CONSTEOF
# Automaton Constitution
## Ratified: ${ratified_date}

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.
No evolution cycle may disable, weaken, or bypass:
- Self-build safety protocol (spec-22)
- Syntax validation gates
- Smoke test requirements
- Circuit breakers (spec-45)
- Budget enforcement (spec-23)

A modification that degrades safety must be rejected regardless of other benefits.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority over automaton's evolution.
- All evolution can be paused via \`--pause-evolution\` (spec-44)
- The human can override any quorum decision via \`--override\` (spec-44)
- The human can amend the constitution via \`--amend\` (spec-44)
- No autonomous action may remove or restrict human control mechanisms
- The evolution loop must halt if it cannot reach the human operator

### Article III: Measurable Progress
**Protection: supermajority**

Every implemented change must target a measurable improvement:
- Token efficiency (tokens per completed task)
- Quality (test pass rate, rollback rate)
- Capability (new specs, functions, or test coverage)
- Reliability (stall rate, error rate)

Changes that cannot be measured against at least one metric must not be implemented.
The OBSERVE phase (spec-41) must compare before/after metrics for every implementation.

### Article IV: Transparency
**Protection: supermajority**

All autonomous decisions must be fully auditable:
- Every quorum vote is recorded with reasoning (spec-39)
- Every garden idea has a traceable origin (spec-38)
- Every signal has observation history (spec-42)
- Every implementation records its branch, commits, and metric deltas
- The human can inspect any decision via \`--inspect\` (spec-44)

Hidden or obfuscated decision-making is a constitutional violation.

### Article V: Budget Discipline
**Protection: supermajority**

Evolution must operate within defined resource constraints:
- Each evolution cycle has a budget ceiling (spec-45)
- Quorum voting has per-cycle cost limits (spec-39)
- The evolution loop must halt when budget is exhausted, not proceed on debt
- Budget overruns in one cycle reduce the next cycle's allocation
- Weekly allowance limits (spec-23) apply to evolution cycles

### Article VI: Incremental Growth
**Protection: majority**

Evolution proceeds through small, reversible steps:
- Each cycle implements at most one idea
- Each implementation modifies at most \`self_build.max_files_per_iteration\` files (spec-22)
- Each implementation changes at most \`self_build.max_lines_changed_per_iteration\` lines (spec-22)
- Complex ideas must be decomposed into smaller sub-ideas before implementation
- The system prefers many small improvements over few large changes

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution:
- Test pass rate must remain >= the pre-evolution baseline
- New functionality must include corresponding tests
- Removing a test requires quorum approval as a separate decision
- The OBSERVE phase must run the full test suite after every implementation
- Test count may increase but must never decrease without explicit justification

### Article VIII: Amendment Protocol
**Protection: unanimous**

This constitution may be amended through the following process:
1. An amendment idea is planted in the garden (spec-38) with \`tags: ["constitutional"]\`
2. The idea progresses through normal lifecycle stages (seed -> sprout -> bloom)
3. At bloom, the quorum evaluates with \`constitutional_amendment\` threshold (4/5 supermajority)
4. If approved, the amendment is applied to constitution.md
5. The amendment is recorded in constitution-history.json with before/after text
6. Articles with \`unanimous\` protection cannot have their protection level reduced
7. This article (Article VIII) cannot be removed or modified to reduce amendment requirements
CONSTEOF

    log "CONSTITUTION" "Constitution ratified with 8 articles. Use --constitution to view, --amend to modify."

    # Initialize amendment history if it doesn't exist
    if [ ! -f "$hist_file" ]; then
        jq -n '{
            version: 1,
            amendments: [],
            current_version: 1
        }' > "$hist_file"
    fi
}

# Returns a JSON summary of the constitution for the bootstrap manifest.
# Output: { articles: N, version: N, key_constraints: [...] }
_constitution_get_summary() {
    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    if [ ! -f "$const_file" ]; then
        jq -n '{ articles: 0, version: 0, key_constraints: [] }'
        return 0
    fi

    local article_count
    article_count=$(grep -c '^### Article' "$const_file" || echo "0")

    local version=1
    if [ -f "$hist_file" ]; then
        version=$(jq -r '.current_version // 1' "$hist_file")
    fi

    jq -n \
        --argjson articles "$article_count" \
        --argjson version "$version" \
        '{
            articles: $articles,
            version: $version,
            key_constraints: [
                "Safety mechanisms must be preserved (Art. I)",
                "Human retains override authority (Art. II)",
                "Changes must target measurable metrics (Art. III)",
                "Each cycle implements at most 1 idea (Art. VI)"
            ]
        }'
}

# Validates a proposed diff against the constitution articles.
# Returns: "pass" (no violations), "warn" (non-blocking concerns), "fail" (blocks commit).
#
# Checks:
#   Article I  (Safety) — diff must not remove protected functions
#   Article II (Human Sovereignty) — diff must not remove human control CLI flags
#   Article III (Measurable Progress) — idea must have a metric target
#   Article VI (Incremental Growth) — files/lines within self_build limits
#   Article VII (Test Coverage) — diff must not remove tests
#
# Usage: result=$(_constitution_check "$diff_file" "$idea_id" "$cycle_id")
_constitution_check() {
    local diff_file="$1"
    local idea_id="$2"
    local cycle_id="$3"

    local const_file="$AUTOMATON_DIR/constitution.md"
    local result="pass"

    # If constitution doesn't exist, warn but don't block
    if [ ! -f "$const_file" ]; then
        log "CONSTITUTION" "WARNING: Constitution file not found, skipping compliance check"
        echo "warn"
        return 0
    fi

    local diff_content=""
    if [ -f "$diff_file" ] && [ -s "$diff_file" ]; then
        diff_content=$(cat "$diff_file")
    else
        # Empty diff — nothing to violate
        echo "pass"
        return 0
    fi

    # Extract removed lines (lines starting with -)
    local removed_lines
    removed_lines=$(echo "$diff_content" | grep '^-' | grep -v '^---' || true)

    # --- Check 1: Safety preservation (Article I) ---
    # Diff must not remove or modify protected functions
    IFS=',' read -ra protected_fns <<< "$SELF_BUILD_PROTECTED_FUNCTIONS"
    for fn in "${protected_fns[@]}"; do
        fn=$(echo "$fn" | xargs)  # trim whitespace
        if echo "$removed_lines" | grep -q "${fn}()"; then
            log "CONSTITUTION" "FAIL: Article I violation — protected function '$fn' removed"
            echo "fail"
            return 0
        fi
    done

    # --- Check 2: Human control preservation (Article II) ---
    # Diff must not remove CLI flags: --pause-evolution, --override, --amend
    local human_flags=("--pause-evolution" "--override" "--amend")
    for flag in "${human_flags[@]}"; do
        if echo "$removed_lines" | grep -q -- "$flag"; then
            log "CONSTITUTION" "FAIL: Article II violation — human control flag '$flag' removed"
            echo "fail"
            return 0
        fi
    done

    # --- Check 3: Measurability (Article III) ---
    # Idea must have at least one metric target in its description
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    if [ -f "$idea_file" ]; then
        local description
        description=$(jq -r '.description // ""' "$idea_file")
        # Look for metric-related keywords
        local metric_keywords="metric|token|efficiency|pass rate|coverage|rollback|error rate|stall|reliability|capability|quality|performance|latency|speed|reduce|increase|improve"
        if ! echo "$description" | grep -qiE "$metric_keywords"; then
            log "CONSTITUTION" "WARN: Article III concern — idea '$idea_id' has no measurable metric target"
            result="warn"
        fi
    fi

    # --- Check 4: Scope limits (Article VI) ---
    # Count files changed
    local files_changed
    files_changed=$(echo "$diff_content" | grep -c '^diff --git' || echo "0")
    if [ "$files_changed" -gt "$SELF_BUILD_MAX_FILES" ]; then
        log "CONSTITUTION" "WARN: Article VI concern — $files_changed files changed (limit: $SELF_BUILD_MAX_FILES)"
        result="warn"
    fi

    # Count lines changed (additions + deletions)
    local lines_added lines_removed lines_changed
    lines_added=$(echo "$diff_content" | grep -c '^+' | grep -v '^+++' || echo "0")
    lines_removed=$(echo "$diff_content" | grep -c '^-' | grep -v '^---' || echo "0")
    lines_changed=$((lines_added + lines_removed))
    if [ "$lines_changed" -gt "$SELF_BUILD_MAX_LINES" ]; then
        log "CONSTITUTION" "WARN: Article VI concern — $lines_changed lines changed (limit: $SELF_BUILD_MAX_LINES)"
        result="warn"
    fi

    # --- Check 5: Test coverage (Article VII) ---
    # If tests were removed, flag as warning
    if echo "$removed_lines" | grep -qE 'assert_equals|assert_contains|assert_file_exists|assert_exit_code|test_summary'; then
        log "CONSTITUTION" "WARN: Article VII concern — test assertions appear to be removed"
        result="warn"
    fi

    echo "$result"
}

# Validates that a proposed amendment does not violate immutable constraints.
# These constraints are enforced in code independently of the constitution text:
#   1. unanimous articles cannot have their protection level reduced
#   2. Article VIII cannot be removed or weakened
#
# Usage: _constitution_validate_amendment "VIII" "protection_change" "supermajority" ""
#   article:         Article number (I, II, III, IV, V, VI, VII, VIII)
#   amendment_type:  "modify", "remove", or "protection_change"
#   new_protection:  New protection level (only for protection_change)
#   new_text:        New article text (only for modify)
# Returns: 0 if allowed, 1 if blocked by immutable constraints
_constitution_validate_amendment() {
    local article="$1"
    local amendment_type="$2"
    local new_protection="${3:-}"
    local new_text="${4:-}"

    # Hardcoded immutable articles and their protection levels.
    # These are the articles that have "unanimous" protection and thus
    # cannot have their protection level reduced per spec-40 §2.
    local -A IMMUTABLE_ARTICLES=(
        ["I"]="unanimous"
        ["II"]="unanimous"
        ["VIII"]="unanimous"
    )

    # Protection level hierarchy for comparison (higher = stricter)
    local -A PROTECTION_RANK=(
        ["majority"]=1
        ["supermajority"]=2
        ["unanimous"]=3
    )

    # --- Constraint 1: Article VIII cannot be removed ---
    if [ "$article" = "VIII" ] && [ "$amendment_type" = "remove" ]; then
        log "CONSTITUTION" "BLOCKED: Article VIII cannot be removed (immutable constraint)"
        return 1
    fi

    # --- Constraint 2: Article VIII cannot be weakened ---
    if [ "$article" = "VIII" ] && [ "$amendment_type" = "modify" ] && [ -n "$new_text" ]; then
        # Check for weakening: text that reduces amendment threshold requirements
        # Weakening indicators: removing supermajority/4\/5 requirement, adding "simple majority", etc.
        local lower_text
        lower_text=$(echo "$new_text" | tr '[:upper:]' '[:lower:]')
        # If the new text mentions "simple majority" or "majority vote" without
        # "supermajority" or "4/5", it is weakening the amendment protocol
        if echo "$lower_text" | grep -qE 'simple majority|majority vote'; then
            if ! echo "$lower_text" | grep -qE 'supermajority|4/5|constitutional_amendment'; then
                log "CONSTITUTION" "BLOCKED: Article VIII cannot be weakened (immutable constraint)"
                return 1
            fi
        fi
    fi

    # --- Constraint 3: unanimous articles cannot have protection reduced ---
    if [ "$amendment_type" = "protection_change" ] && [ -n "$new_protection" ]; then
        local current_protection="${IMMUTABLE_ARTICLES[$article]:-}"
        if [ -n "$current_protection" ]; then
            local current_rank="${PROTECTION_RANK[$current_protection]:-0}"
            local new_rank="${PROTECTION_RANK[$new_protection]:-0}"
            if [ "$new_rank" -lt "$current_rank" ]; then
                log "CONSTITUTION" "BLOCKED: Article $article has '$current_protection' protection which cannot be reduced (immutable constraint)"
                return 1
            fi
        fi
    fi

    return 0
}

# Applies an approved amendment to constitution.md and records the change
# in constitution-history.json with a full audit trail.
#
# Usage: _constitution_amend "VI" "modify" "description" "new_text" "vote-001" "human"
#   article:         Article number (I, II, III, IV, V, VI, VII, VIII)
#   amendment_type:  "modify", "remove", or "protection_change"
#   description:     Human-readable description of the amendment
#   new_text:        New article body text (for modify) or new protection level (for protection_change)
#   vote_id:         ID of the quorum vote that approved this amendment
#   proposed_by:     Who proposed: "human" or "agent"
# Returns: 0 on success, 1 if blocked by immutable constraints
_constitution_amend() {
    local article="$1"
    local amendment_type="$2"
    local description="$3"
    local new_text="${4:-}"
    local vote_id="${5:-}"
    local proposed_by="${6:-agent}"

    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    if [ ! -f "$const_file" ]; then
        log "CONSTITUTION" "ERROR: Constitution file not found at $const_file"
        return 1
    fi

    # Validate against immutable constraints before proceeding
    local validate_protection=""
    local validate_text=""
    if [ "$amendment_type" = "protection_change" ]; then
        validate_protection="$new_text"
    elif [ "$amendment_type" = "modify" ]; then
        validate_text="$new_text"
    fi

    if ! _constitution_validate_amendment "$article" "$amendment_type" "$validate_protection" "$validate_text"; then
        return 1
    fi

    # Extract before-text for the article (everything between this article header and the next)
    local before_text
    before_text=$(awk -v art="### Article ${article}:" '
        $0 ~ art { found=1; next }
        found && /^### Article / { exit }
        found { print }
    ' "$const_file")

    # Apply the amendment to constitution.md
    case "$amendment_type" in
        modify)
            # Replace article body text (between this article header+protection line and the next article)
            local tmpfile
            tmpfile=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file"; return 1; }
            awk -v art="### Article ${article}:" -v newtext="$new_text" '
                $0 ~ art { print; in_article=1; next }
                in_article && /^\*\*Protection:/ { print; in_article=2; next }
                in_article == 2 && /^### Article / { print newtext; print ""; in_article=0; print; next }
                in_article == 2 && /^$/ && !printed_new { next }
                in_article == 2 { next }
                { print }
                END { if (in_article == 2) print newtext }
            ' "$const_file" > "$tmpfile"
            mv "$tmpfile" "$const_file"
            ;;
        protection_change)
            # Update the **Protection: level** line for the article
            local tmpfile
            tmpfile=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file"; return 1; }
            awk -v art="### Article ${article}:" -v newprot="$new_text" '
                $0 ~ art { print; in_article=1; next }
                in_article && /^\*\*Protection:/ { print "**Protection: " newprot "**"; in_article=0; next }
                { print }
            ' "$const_file" > "$tmpfile"
            mv "$tmpfile" "$const_file"
            ;;
        remove)
            # Remove the entire article section
            local tmpfile
            tmpfile=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file"; return 1; }
            awk -v art="### Article ${article}:" '
                $0 ~ art { skip=1; next }
                skip && /^### Article / { skip=0; print; next }
                skip { next }
                { print }
            ' "$const_file" > "$tmpfile"
            mv "$tmpfile" "$const_file"
            ;;
    esac

    # Initialize history file if missing
    if [ ! -f "$hist_file" ]; then
        jq -n '{version: 1, amendments: [], current_version: 1}' > "$hist_file"
    fi

    # Compute amendment_id from current amendment count
    local amendment_count
    amendment_count=$(jq '.amendments | length' "$hist_file")
    local amendment_id
    amendment_id=$(printf "amend-%03d" $((amendment_count + 1)))

    local approved_at
    approved_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Record in history
    local after_text="$new_text"
    jq --arg aid "$amendment_id" \
       --arg art "$article" \
       --arg atype "$amendment_type" \
       --arg desc "$description" \
       --arg before "$before_text" \
       --arg after "$after_text" \
       --arg vid "$vote_id" \
       --arg pby "$proposed_by" \
       --arg aat "$approved_at" \
       '.amendments += [{
           amendment_id: $aid,
           article: $art,
           type: $atype,
           description: $desc,
           before_text: $before,
           after_text: $after,
           vote_id: $vid,
           proposed_by: $pby,
           approved_at: $aat
       }] | .current_version += 1' "$hist_file" > "${hist_file}.tmp"
    mv "${hist_file}.tmp" "$hist_file"

    log "CONSTITUTION" "Amendment $amendment_id applied to Article $article ($amendment_type)"
}
