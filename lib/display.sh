#!/usr/bin/env bash
# lib/display.sh — Display functions and CLI subcommand handlers for garden, signals, and governance.
# Spec references: spec-44 (CLI display commands), spec-41 (garden/signal/constitution display)

_display_garden() {
    local garden_dir="$AUTOMATON_DIR/garden"

    if [ ! -d "$garden_dir" ]; then
        echo "No garden found. Use --plant \"idea\" to plant the first seed."
        return 0
    fi

    # Collect all idea files and extract relevant fields in a single pass
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

    if [ -z "$idea_files" ]; then
        echo "AUTOMATON GARDEN — 0 ideas"
        echo ""
        echo "The garden is empty. Use --plant \"idea\" to plant the first seed."
        return 0
    fi

    # Build a JSON array of non-wilted, non-harvested ideas with display fields
    local ideas_json="[]"
    local seed_count=0 sprout_count=0 bloom_count=0 total_active=0
    local now_epoch
    now_epoch=$(date +%s)

    while IFS= read -r f; do
        [ -f "$f" ] || continue
        local stage
        stage=$(jq -r '.stage' "$f")

        # Skip wilted and harvested ideas
        [ "$stage" = "wilt" ] && continue
        [ "$stage" = "harvest" ] && continue

        total_active=$((total_active + 1))
        case "$stage" in
            seed)   seed_count=$((seed_count + 1)) ;;
            sprout) sprout_count=$((sprout_count + 1)) ;;
            bloom)  bloom_count=$((bloom_count + 1)) ;;
        esac

        # Extract fields for display
        local id title priority created_at
        id=$(jq -r '.id' "$f")
        title=$(jq -r '.title' "$f")
        priority=$(jq -r '.priority // 0' "$f")
        created_at=$(jq -r '.stage_history[0].entered_at // .updated_at' "$f")

        # Calculate age in days
        local age_days="?"
        if [ -n "$created_at" ] && [ "$created_at" != "null" ]; then
            local created_epoch
            created_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo "")
            if [ -n "$created_epoch" ]; then
                age_days=$(( (now_epoch - created_epoch) / 86400 ))
            fi
        fi

        # Stage sort order: bloom=0, sprout=1, seed=2
        local sort_order=2
        case "$stage" in
            bloom)  sort_order=0 ;;
            sprout) sort_order=1 ;;
            seed)   sort_order=2 ;;
        esac

        ideas_json=$(echo "$ideas_json" | jq \
            --arg id "$id" \
            --arg stage "$stage" \
            --argjson priority "$priority" \
            --arg title "$title" \
            --arg age "${age_days}d" \
            --argjson sort_order "$sort_order" \
            '. + [{"id": $id, "stage": $stage, "priority": $priority, "title": $title, "age": $age, "sort_order": $sort_order}]')
    done <<< "$idea_files"

    if [ "$total_active" -eq 0 ]; then
        echo "AUTOMATON GARDEN — 0 ideas"
        echo ""
        echo "The garden is empty. Use --plant \"idea\" to plant the first seed."
        return 0
    fi

    # Sort by stage order (bloom first) then priority descending
    ideas_json=$(echo "$ideas_json" | jq 'sort_by(.sort_order, -.priority)')

    # Print header
    local stage_summary=""
    [ "$seed_count" -gt 0 ] && stage_summary="${seed_count} seed"
    [ "$sprout_count" -gt 0 ] && { [ -n "$stage_summary" ] && stage_summary="$stage_summary, "; stage_summary="${stage_summary}${sprout_count} sprout"; }
    [ "$bloom_count" -gt 0 ] && { [ -n "$stage_summary" ] && stage_summary="$stage_summary, "; stage_summary="${stage_summary}${bloom_count} bloom"; }

    echo "AUTOMATON GARDEN — ${total_active} ideas (${stage_summary})"
    echo ""

    # Print table header
    printf " %-10s %-8s %4s  %-40s %s\n" "ID" "STAGE" "PRI" "TITLE" "AGE"

    # Print each idea row
    local row_count
    row_count=$(echo "$ideas_json" | jq 'length')
    local i=0
    while [ "$i" -lt "$row_count" ]; do
        local row_id row_stage row_pri row_title row_age
        row_id=$(echo "$ideas_json" | jq -r ".[$i].id")
        row_stage=$(echo "$ideas_json" | jq -r ".[$i].stage")
        row_pri=$(echo "$ideas_json" | jq -r ".[$i].priority")
        row_title=$(echo "$ideas_json" | jq -r ".[$i].title")
        row_age=$(echo "$ideas_json" | jq -r ".[$i].age")

        # Truncate title to 40 chars
        if [ "${#row_title}" -gt 40 ]; then
            row_title="${row_title:0:37}..."
        fi

        printf " %-10s %-8s %4s  %-40s %s\n" "$row_id" "$row_stage" "$row_pri" "$row_title" "$row_age"
        i=$((i + 1))
    done

    echo ""
    echo "Bloom candidates ready for quorum: ${bloom_count}"
    echo "Use --garden-detail ID for full details. Use --plant \"idea\" to add new seeds."
}

# Renders full details for a single garden idea including description, evidence
# list with timestamps, related specs/signals, stage history, and vote status.
# Accepts an idea ID (with or without "idea-" prefix).
#
# Usage: _display_garden_detail <idea_id>
_display_garden_detail() {
    local idea_id="$1"
    local garden_dir="$AUTOMATON_DIR/garden"

    # Normalize ID: add "idea-" prefix if not present
    if [[ "$idea_id" != idea-* ]]; then
        idea_id="idea-$(printf '%03d' "$idea_id" 2>/dev/null || echo "$idea_id")"
    fi

    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        echo "Idea '$idea_id' not found in the garden."
        return 1
    fi

    # Read all fields from the idea file
    local title stage priority complexity description vote_id
    title=$(jq -r '.title // "Untitled"' "$idea_file")
    stage=$(jq -r '.stage // "unknown"' "$idea_file")
    priority=$(jq -r '.priority // 0' "$idea_file")
    complexity=$(jq -r '.estimated_complexity // "unknown"' "$idea_file")
    description=$(jq -r '.description // ""' "$idea_file")
    vote_id=$(jq -r '.vote_id // empty' "$idea_file" 2>/dev/null || echo "")

    # Get the date for the current stage
    local stage_date=""
    stage_date=$(jq -r --arg s "$stage" '.stage_history[] | select(.stage == $s) | .entered_at' "$idea_file" | tail -1)
    if [ -n "$stage_date" ] && [ "$stage_date" != "null" ]; then
        stage_date=$(echo "$stage_date" | cut -dT -f1)
    else
        stage_date="unknown"
    fi

    # Tags
    local tags
    tags=$(jq -r '.tags // [] | join(", ")' "$idea_file")
    local tag_suffix=""
    if [ -n "$tags" ]; then
        tag_suffix=" ($tags)"
    fi

    # Header
    echo "IDEA: ${idea_id} — ${title}${tag_suffix}"
    echo "Stage: ${stage} (since ${stage_date})  |  Priority: ${priority}  |  Complexity: ${complexity}"
    echo ""

    # Description
    echo "Description:"
    if [ -n "$description" ]; then
        echo "$description" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo "  (no description)"
    fi
    echo ""

    # Evidence
    local evidence_count
    evidence_count=$(jq '.evidence | length' "$idea_file")
    echo "Evidence (${evidence_count} items):"
    if [ "$evidence_count" -gt 0 ]; then
        local i=0
        while [ "$i" -lt "$evidence_count" ]; do
            local ev_type ev_content ev_source ev_date
            ev_type=$(jq -r ".evidence[$i].type // \"unknown\"" "$idea_file")
            ev_content=$(jq -r ".evidence[$i].content // \"\"" "$idea_file")
            ev_source=$(jq -r ".evidence[$i].source // \"\"" "$idea_file")
            ev_date=$(jq -r ".evidence[$i].added_at // \"\"" "$idea_file")
            if [ -n "$ev_date" ] && [ "$ev_date" != "null" ]; then
                ev_date=$(echo "$ev_date" | cut -dT -f1)
            else
                ev_date=""
            fi
            local ev_suffix=""
            if [ -n "$ev_source" ] || [ -n "$ev_date" ]; then
                ev_suffix=" (${ev_source}${ev_date:+, $ev_date})"
            fi
            echo "  $((i + 1)). [${ev_type}] ${ev_content}${ev_suffix}"
            i=$((i + 1))
        done
    else
        echo "  (no evidence yet)"
    fi
    echo ""

    # Related items
    local specs signals
    specs=$(jq -r '.related_specs // [] | if length > 0 then "specs " + (map(tostring) | join(", ")) else "" end' "$idea_file" 2>/dev/null || echo "")
    signals=$(jq -r '.related_signals // [] | if length > 0 then "signals " + join(", ") else "" end' "$idea_file" 2>/dev/null || echo "")
    local related_parts=""
    [ -n "$specs" ] && related_parts="$specs"
    if [ -n "$signals" ]; then
        [ -n "$related_parts" ] && related_parts="$related_parts  |  "
        related_parts="${related_parts}${signals}"
    fi
    if [ -n "$related_parts" ]; then
        echo "Related: ${related_parts}"
    else
        echo "Related: (none)"
    fi
    echo ""

    # Stage history
    local history_count
    history_count=$(jq '.stage_history | length' "$idea_file")
    echo "Stage History:"
    if [ "$history_count" -gt 0 ]; then
        local i=0
        while [ "$i" -lt "$history_count" ]; do
            local h_stage h_date h_reason
            h_stage=$(jq -r ".stage_history[$i].stage // \"\"" "$idea_file")
            h_date=$(jq -r ".stage_history[$i].entered_at // \"\"" "$idea_file")
            h_reason=$(jq -r ".stage_history[$i].reason // \"\"" "$idea_file")
            if [ -n "$h_date" ] && [ "$h_date" != "null" ]; then
                h_date=$(echo "$h_date" | cut -dT -f1)
            fi
            printf "  %-8s → %s  %s\n" "$h_stage" "$h_date" "$h_reason"
            i=$((i + 1))
        done
    else
        echo "  (no history)"
    fi
    echo ""

    # Vote status
    if [ -n "$vote_id" ] && [ "$vote_id" != "null" ]; then
        echo "Vote: ${vote_id}"
    else
        echo "Vote: not yet evaluated"
    fi
}

# Renders a formatted table of active stigmergic signals with ID, type,
# strength, title, observation count, and linked idea status. Includes
# summary counts of unlinked and strong signals.
#
# Usage: _display_signals
_display_signals() {
    local signals_file="$AUTOMATON_DIR/signals.json"

    if [ ! -f "$signals_file" ]; then
        echo "No active signals. Signals are emitted during evolution cycles."
        return 0
    fi

    local signal_count
    signal_count=$(jq '.signals | length' "$signals_file")

    if [ "$signal_count" -eq 0 ]; then
        echo "ACTIVE SIGNALS — 0 signals"
        echo ""
        echo "No active signals. Signals are emitted during evolution cycles."
        return 0
    fi

    # Count strong signals (strength >= 0.5)
    local strong_count
    strong_count=$(jq '[.signals[] | select(.strength >= 0.5)] | length' "$signals_file")

    # Print header
    echo "ACTIVE SIGNALS — ${signal_count} signals (${strong_count} strong)"
    echo ""

    # Print column headers
    printf " %-8s %-20s %5s  %-35s %4s  %s\n" "ID" "TYPE" "STR" "TITLE" "OBS" "LINKED"

    # Sort signals by strength descending and print each row
    local sorted_signals
    sorted_signals=$(jq '[.signals | sort_by(-.strength)[]]' "$signals_file")

    local i=0
    while [ "$i" -lt "$signal_count" ]; do
        local sig_id sig_type sig_strength sig_title obs_count linked
        sig_id=$(echo "$sorted_signals" | jq -r ".[$i].id")
        sig_type=$(echo "$sorted_signals" | jq -r ".[$i].type")
        sig_strength=$(echo "$sorted_signals" | jq -r ".[$i].strength")
        sig_title=$(echo "$sorted_signals" | jq -r ".[$i].title")
        obs_count=$(echo "$sorted_signals" | jq -r ".[$i].observations | length")

        # Get linked idea (first related idea or dash)
        local related_count
        related_count=$(echo "$sorted_signals" | jq ".[$i].related_ideas | length")
        if [ "$related_count" -gt 0 ]; then
            linked=$(echo "$sorted_signals" | jq -r ".[$i].related_ideas[0]")
        else
            linked="—"
        fi

        # Truncate title to 35 chars
        if [ "${#sig_title}" -gt 35 ]; then
            sig_title="${sig_title:0:32}..."
        fi

        # Format strength as 2-decimal
        sig_strength=$(printf "%.2f" "$sig_strength")

        printf " %-8s %-20s %5s  %-35s %4s  %s\n" "$sig_id" "$sig_type" "$sig_strength" "$sig_title" "$obs_count" "$linked"
        i=$((i + 1))
    done

    # Summary lines
    local unlinked_count
    unlinked_count=$(jq '[.signals[] | select(.related_ideas | length == 0)] | length' "$signals_file")

    echo ""
    echo "Unlinked signals (no garden idea): ${unlinked_count}"
    echo "Strong signals (>= 0.5): ${strong_count}"
}

# Renders a vote record with per-voter breakdown (vote, confidence, risk,
# reasoning), tally result, merged conditions, and cost. Accepts either a
# vote ID (e.g. "vote-005") or an idea ID (e.g. "idea-003" or bare "3").
#
# Usage: _display_vote <id>
_display_vote() {
    local input_id="$1"
    local votes_dir="$AUTOMATON_DIR/votes"
    local vote_file=""

    # Try direct vote ID lookup first
    if [[ "$input_id" == vote-* ]]; then
        vote_file="$votes_dir/${input_id}.json"
    elif [ -f "$votes_dir/${input_id}.json" ]; then
        vote_file="$votes_dir/${input_id}.json"
    fi

    # If not found as vote ID, try as idea ID
    if [ -z "$vote_file" ] || [ ! -f "$vote_file" ]; then
        local idea_id="$input_id"
        # Normalize bare number to idea-NNN format
        if [[ "$idea_id" =~ ^[0-9]+$ ]]; then
            idea_id=$(printf "idea-%03d" "$idea_id")
        fi

        # Look up vote_id from the garden idea file
        local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
        if [ -f "$idea_file" ]; then
            local linked_vote_id
            linked_vote_id=$(jq -r '.vote_id // empty' "$idea_file" 2>/dev/null || echo "")
            if [ -n "$linked_vote_id" ] && [ "$linked_vote_id" != "null" ]; then
                vote_file="$votes_dir/${linked_vote_id}.json"
            fi
        fi

        # If still not found, scan vote files for matching idea_id
        if [ -z "$vote_file" ] || [ ! -f "$vote_file" ]; then
            local f
            for f in "$votes_dir"/vote-*.json; do
                [ -f "$f" ] || continue
                local vid
                vid=$(jq -r '.idea_id // ""' "$f" 2>/dev/null)
                if [ "$vid" = "$idea_id" ]; then
                    vote_file="$f"
                    break
                fi
            done
        fi
    fi

    if [ -z "$vote_file" ] || [ ! -f "$vote_file" ]; then
        echo "Vote '$input_id' not found. Use --garden to see ideas with vote references."
        return 1
    fi

    # Read vote record fields
    local vote_id idea_id vote_type result threshold
    local approve_count reject_count abstain_count
    vote_id=$(jq -r '.vote_id' "$vote_file")
    idea_id=$(jq -r '.idea_id' "$vote_file")
    vote_type=$(jq -r '.type // "unknown"' "$vote_file")
    result=$(jq -r '.tally.result // "unknown"' "$vote_file")
    threshold=$(jq -r '.tally.threshold // 0' "$vote_file")
    approve_count=$(jq -r '.tally.approve // 0' "$vote_file")
    reject_count=$(jq -r '.tally.reject // 0' "$vote_file")
    abstain_count=$(jq -r '.tally.abstain // 0' "$vote_file")

    # Get idea title from proposal or garden
    local idea_title=""
    idea_title=$(jq -r '.proposal.idea.title // empty' "$vote_file" 2>/dev/null || echo "")
    if [ -z "$idea_title" ] || [ "$idea_title" = "null" ]; then
        local idea_garden_file="$AUTOMATON_DIR/garden/${idea_id}.json"
        if [ -f "$idea_garden_file" ]; then
            idea_title=$(jq -r '.title // "Unknown"' "$idea_garden_file")
        else
            idea_title="Unknown"
        fi
    fi

    local total_voters=$(( approve_count + reject_count + abstain_count ))
    local result_upper
    result_upper=$(echo "$result" | tr '[:lower:]' '[:upper:]')

    # Header
    echo "VOTE: ${vote_id} — Evaluating ${idea_id} \"${idea_title}\""
    echo "Type: ${vote_type}  |  Threshold: ${threshold}/${total_voters}  |  Result: ${result_upper}"
    echo ""

    # Per-voter breakdown table
    printf " %-14s %-8s %4s  %-6s  %s\n" "VOTER" "VOTE" "CONF" "RISK" "REASONING"

    # Iterate over voter names in the votes object
    local voter_names
    voter_names=$(jq -r '.votes | keys[]' "$vote_file" 2>/dev/null)

    for voter in $voter_names; do
        local v_vote v_conf v_risk v_reasoning
        v_vote=$(jq -r ".votes[\"$voter\"].vote // \"abstain\"" "$vote_file")
        v_conf=$(jq -r ".votes[\"$voter\"].confidence // 0" "$vote_file")
        v_risk=$(jq -r ".votes[\"$voter\"].risk_assessment // \"medium\"" "$vote_file")
        v_reasoning=$(jq -r ".votes[\"$voter\"].reasoning // \"\"" "$vote_file")

        # Truncate reasoning to fit display
        if [ "${#v_reasoning}" -gt 50 ]; then
            v_reasoning="${v_reasoning:0:47}..."
        fi

        printf " %-14s %-8s %4s  %-6s  %s\n" "$voter" "$v_vote" "$v_conf" "$v_risk" "$v_reasoning"
    done
    echo ""

    # Tally line
    echo "Tally: ${approve_count} approve, ${reject_count} reject, ${abstain_count} abstain → ${result_upper} (${approve_count}/${total_voters} >= ${threshold}/${total_voters})"

    # Conditions (only if non-empty)
    local conditions_count
    conditions_count=$(jq '.tally.conditions_merged | length' "$vote_file" 2>/dev/null || echo "0")
    if [ "$conditions_count" -gt 0 ]; then
        local conditions_str
        conditions_str=$(jq -r '.tally.conditions_merged | join(", ")' "$vote_file")
        echo "Conditions: ${conditions_str}"
    fi
}

# Renders the constitution article summary with version, amendment count, and
# per-article protection levels. Matches the spec-44 §3.5 output format.
#
# Usage: _display_constitution
_display_constitution() {
    local const_file="$AUTOMATON_DIR/constitution.md"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    if [ ! -f "$const_file" ]; then
        echo "No constitution found. Constitution is created on first --evolve run."
        return 0
    fi

    # Extract ratification date from "## Ratified: YYYY-MM-DD" line
    local ratified_date
    ratified_date=$(grep -m1 '## Ratified:' "$const_file" | sed 's/.*Ratified: *//' || echo "unknown")

    # Count articles
    local article_count
    article_count=$(grep -c '^### Article' "$const_file" || echo "0")

    # Get version and amendment count from history
    local version=1
    local amendment_count=0
    if [ -f "$hist_file" ]; then
        version=$(jq -r '.current_version // 1' "$hist_file")
        amendment_count=$(jq '.amendments | length' "$hist_file" 2>/dev/null || echo "0")
    fi

    # Header
    echo "AUTOMATON CONSTITUTION (v${version}, ratified ${ratified_date})"
    echo "${article_count} articles, ${amendment_count} amendments"
    echo ""

    # Extract and display each article with its protection level
    while IFS= read -r line; do
        # Parse "### Article N: Title"
        local art_num art_title
        art_num=$(echo "$line" | sed 's/### Article \([^:]*\):.*/\1/')
        art_title=$(echo "$line" | sed 's/### Article [^:]*: *//')

        # Read the next non-empty line to get the protection level
        local protection="unknown"
        local prot_line
        # Search for the Protection line after this article heading
        prot_line=$(sed -n "/^### Article ${art_num}:/,/^### Article/{/\*\*Protection:/p;}" "$const_file" | head -1)
        if [ -n "$prot_line" ]; then
            protection=$(echo "$prot_line" | sed 's/.*Protection: *//;s/\*\*//g')
        fi

        printf "  Art. %-4s %-28s [%s]\n" "$art_num" "$art_title" "$protection"
    done < <(grep '^### Article' "$const_file")

    # Footer
    echo ""
    echo "Use --amend to propose changes. Full text: .automaton/constitution.md"
}

# ---------------------------------------------------------------------------
# CLI Action Functions (spec-44 §44.3)
# ---------------------------------------------------------------------------

# Plants a new seed in the garden with human origin and displays the result
# including assigned ID, priority (with human boost), and watering guidance.
#
# Usage: _cli_plant "idea description"
# Outputs: formatted plant confirmation to stdout
# Returns: 0 on success, 1 on failure
_cli_plant() {
    local description="${1:?_cli_plant requires an idea description}"

    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then
        echo "Error: Garden is not enabled. Set garden.enabled=true in automaton.config.json." >&2
        return 1
    fi

    # Plant the seed with human origin
    local idea_id
    idea_id=$(_garden_plant_seed \
        "$description" \
        "$description" \
        "human" \
        "cli" \
        "human" \
        "medium" \
        "")

    if [ -z "$idea_id" ]; then
        echo "Error: Failed to plant seed." >&2
        return 1
    fi

    # Recompute priorities so the human boost is reflected
    _garden_recompute_priorities 2>/dev/null || true

    # Read back the idea to get the computed priority
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    local priority=10
    if [ -f "$idea_file" ]; then
        priority=$(jq -r '.priority // 10' "$idea_file")
    fi

    # Display the result
    echo "Planted seed ${idea_id}: \"${description}\""
    echo "Origin: human  |  Stage: seed  |  Priority: ${priority} (+10 human boost)"
    echo "Water with evidence using: --water ${idea_id} \"your evidence here\""
}

# Adds evidence to an existing garden idea and displays the result.
# Shows updated evidence count, priority change, and any stage advancement.
# Called by --water ID "evidence" CLI command.
#
# Args: idea_id evidence_text
# Returns: 0 on success, 1 on failure
_cli_water() {
    local idea_id="${1:?_cli_water requires an idea ID}"
    local evidence="${2:?_cli_water requires evidence text}"

    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then
        echo "Error: Garden is not enabled. Set garden.enabled=true in automaton.config.json." >&2
        return 1
    fi

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        echo "Error: Idea $idea_id not found." >&2
        return 1
    fi

    # Capture pre-water state
    local old_title old_stage old_priority old_evidence_count
    old_title=$(jq -r '.title' "$idea_file")
    old_stage=$(jq -r '.stage' "$idea_file")
    old_priority=$(jq -r '.priority // 0' "$idea_file")
    old_evidence_count=$(jq '.evidence | length' "$idea_file")

    # Water the idea with human evidence
    _garden_water "$idea_id" "observation" "$evidence" "human"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to water idea $idea_id." >&2
        return 1
    fi

    # Recompute priorities so changes are reflected
    _garden_recompute_priorities 2>/dev/null || true

    # Read back updated state
    local new_stage new_priority new_evidence_count
    new_stage=$(jq -r '.stage' "$idea_file")
    new_priority=$(jq -r '.priority // 0' "$idea_file")
    new_evidence_count=$(jq '.evidence | length' "$idea_file")

    # Display result
    echo "Watered ${idea_id}: \"${old_title}\""
    echo "Evidence added (${new_evidence_count} total). Priority: ${old_priority} → ${new_priority}."

    # Report stage advancement if it occurred
    if [ "$old_stage" != "$new_stage" ]; then
        echo "Stage: ${old_stage} → ${new_stage} (threshold met: ${new_evidence_count} evidence items, priority ${new_priority} >= ${GARDEN_BLOOM_PRIORITY_THRESHOLD:-40})"
    fi
}

# Wilts a garden idea with a reason and displays confirmation.
# Called by --prune ID "reason" CLI command.
#
# Args: idea_id reason
# Returns: 0 on success, 1 on failure
_cli_prune() {
    local idea_id="${1:?_cli_prune requires an idea ID}"
    local reason="${2:?_cli_prune requires a reason}"

    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then
        echo "Error: Garden is not enabled. Set garden.enabled=true in automaton.config.json." >&2
        return 1
    fi

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        echo "Error: Idea $idea_id not found." >&2
        return 1
    fi

    # Read title before wilting
    local title
    title=$(jq -r '.title' "$idea_file")

    # Wilt the idea
    _garden_wilt "$idea_id" "$reason"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to prune idea $idea_id." >&2
        return 1
    fi

    # Display confirmation
    echo "Pruned ${idea_id}: \"${title}\" → wilted"
    echo "Reason: ${reason}"
}

# Force-promotes a garden idea to bloom stage, bypassing normal thresholds.
# Implements Article II human sovereignty — the human can override maturation.
# Called by --promote ID CLI command.
#
# Args: idea_id
# Returns: 0 on success, 1 on failure
_cli_promote() {
    local idea_id="${1:?_cli_promote requires an idea ID}"

    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then
        echo "Error: Garden is not enabled. Set garden.enabled=true in automaton.config.json." >&2
        return 1
    fi

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        echo "Error: Idea $idea_id not found." >&2
        return 1
    fi

    # Read current state
    local title current_stage
    title=$(jq -r '.title' "$idea_file")
    current_stage=$(jq -r '.stage' "$idea_file")

    # Prevent promoting already-bloom, harvested, or wilted ideas
    case "$current_stage" in
        bloom)
            echo "Idea $idea_id is already at bloom stage."
            return 0
            ;;
        harvest)
            echo "Error: Idea $idea_id is already harvested and cannot be promoted." >&2
            return 1
            ;;
        wilt)
            echo "Error: Idea $idea_id is wilted. Use --override to re-promote rejected ideas." >&2
            return 1
            ;;
    esac

    # Force-advance to bloom, bypassing thresholds
    _garden_advance_stage "$idea_id" "bloom" "Human promotion (bypassed thresholds)" "true"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to promote idea $idea_id." >&2
        return 1
    fi

    # Recompute priorities so the change is reflected
    _garden_recompute_priorities 2>/dev/null || true

    # Display result
    echo "Promoted ${idea_id}: \"${title}\" → bloom"
    echo "Bypassed threshold check (human promotion). Ready for quorum evaluation."
}

# Guides the human through proposing a constitutional amendment.
# Interactive: reads article selection, proposed change, and confirmation from stdin.
# Creates a garden idea tagged 'constitutional' so the amendment follows normal lifecycle.
# Called by --amend CLI command.
#
# Flow:
#   1. Show header
#   2. Read article number (I-VIII or 'new')
#   3. Show current article text and protection level
#   4. Read proposed change
#   5. Show what will happen (quorum threshold)
#   6. Read confirmation (y/n)
#   7. Plant garden idea with constitutional tag
#   8. Display next steps
#
# Returns: 0 on success, 1 on error or user abort
_cli_amend() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then
        echo "Error: Garden is not enabled. Set garden.enabled=true in automaton.config.json." >&2
        return 1
    fi

    local const_file="$AUTOMATON_DIR/constitution.md"
    if [ ! -f "$const_file" ]; then
        echo "Error: Constitution not found at $const_file. Run --evolve first to initialize." >&2
        return 1
    fi

    echo ""
    echo "CONSTITUTIONAL AMENDMENT PROCESS"
    echo ""

    # Read article selection
    printf "Which article to amend? (I-VIII or 'new' for new article): "
    local article_input
    read -r article_input

    if [ "$article_input" = "new" ]; then
        # New article proposal
        printf "Enter the proposed new article (one line):\n"
        local proposed_change
        read -r proposed_change

        echo ""
        echo "This amendment will:"
        echo "  - Add a new article to the constitution"
        echo "  - Require quorum vote: 4/5 supermajority (constitutional_amendment threshold)"
        echo "  - Be planted as a garden idea with tag 'constitutional'"
        echo ""
        printf "Proceed? (y/n): "
        local confirm
        read -r confirm

        if [ "$confirm" != "y" ]; then
            echo "Amendment cancelled."
            return 0
        fi

        local idea_title="Constitutional amendment: New article — ${proposed_change:0:60}"
        local idea_desc="Propose adding a new article to the constitution: $proposed_change"

        local idea_id
        idea_id=$(_garden_plant_seed \
            "$idea_title" \
            "$idea_desc" \
            "human" \
            "cli" \
            "human" \
            "medium" \
            "constitutional")

        if [ -z "$idea_id" ]; then
            echo "Error: Failed to plant amendment idea." >&2
            return 1
        fi

        _garden_recompute_priorities 2>/dev/null || true

        echo ""
        echo "Planted ${idea_id}: \"${idea_title}\""
        echo "Tags: [constitutional]  |  Stage: seed"
        echo "The idea will progress through normal garden lifecycle."
        echo "For immediate evaluation, use: --promote ${idea_id}"
        return 0
    fi

    # Validate article input (must be a roman numeral I-VIII)
    local article_upper
    article_upper=$(echo "$article_input" | tr '[:lower:]' '[:upper:]')
    local valid_articles="I II III IV V VI VII VIII"
    local found=false
    for art in $valid_articles; do
        if [ "$art" = "$article_upper" ]; then
            found=true
            break
        fi
    done

    if [ "$found" != "true" ]; then
        echo "Error: Invalid article '$article_input'. Use I-VIII or 'new'." >&2
        return 1
    fi

    # Extract article title and protection level
    local article_header
    article_header=$(grep "^### Article ${article_upper}:" "$const_file" || true)
    if [ -z "$article_header" ]; then
        echo "Error: Article ${article_upper} not found in constitution." >&2
        return 1
    fi

    local article_title
    article_title=$(echo "$article_header" | sed "s/^### Article ${article_upper}: //")

    # Extract protection level
    local protection
    protection=$(awk -v art="### Article ${article_upper}:" '
        $0 ~ art { found=1; next }
        found && /^\*\*Protection:/ { gsub(/\*\*Protection: /, ""); gsub(/\*\*/, ""); print; exit }
    ' "$const_file")

    # Extract article body text
    local article_text
    article_text=$(awk -v art="### Article ${article_upper}:" '
        $0 ~ art { found=1; next }
        found && /^\*\*Protection:/ { next }
        found && /^$/ && !started { started=1; next }
        found && /^### Article / { exit }
        found && /^#/ { exit }
        found { print }
    ' "$const_file")

    echo "Current text of Article ${article_upper}: \"${article_title}\" [${protection}]"
    echo ""
    echo "$article_text"
    echo ""

    printf "Enter the proposed change (one line):\n"
    local proposed_change
    read -r proposed_change

    # Determine required quorum threshold based on protection level
    local threshold_desc="3/5 majority"
    case "$protection" in
        unanimous) threshold_desc="4/5 supermajority" ;;
        supermajority) threshold_desc="4/5 supermajority" ;;
        majority) threshold_desc="3/5 majority" ;;
    esac

    echo ""
    echo "This amendment will:"
    echo "  - Modify Article ${article_upper} (protection: ${protection})"
    echo "  - Require quorum vote: ${threshold_desc}"
    echo "  - Be planted as a garden idea with tag 'constitutional'"
    echo ""
    printf "Proceed? (y/n): "
    local confirm
    read -r confirm

    if [ "$confirm" != "y" ]; then
        echo "Amendment cancelled."
        return 0
    fi

    local idea_title="Constitutional amendment: Article ${article_upper} — ${proposed_change:0:60}"
    local idea_desc="Propose modifying Article ${article_upper} (${article_title}): ${proposed_change}"

    local idea_id
    idea_id=$(_garden_plant_seed \
        "$idea_title" \
        "$idea_desc" \
        "human" \
        "cli" \
        "human" \
        "medium" \
        "constitutional")

    if [ -z "$idea_id" ]; then
        echo "Error: Failed to plant amendment idea." >&2
        return 1
    fi

    _garden_recompute_priorities 2>/dev/null || true

    echo ""
    echo "Planted ${idea_id}: \"${idea_title}\""
    echo "Tags: [constitutional]  |  Stage: seed"
    echo "The idea will progress through normal garden lifecycle."
    echo "For immediate evaluation, use: --promote ${idea_id}"
}

# Lists recently rejected (quorum-wilted) ideas and allows the human to
# override a rejection by re-promoting the idea to bloom stage.
# Records the override in the vote record and constitution history.
# Implements Article II: Human Sovereignty.
#
# Interactive: reads idea selection and confirmation from stdin.
# Returns: 0 on success, 1 on error or user abort
_cli_override() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then
        echo "Error: Garden is not enabled. Set garden.enabled=true in automaton.config.json." >&2
        return 1
    fi

    local garden_dir="$AUTOMATON_DIR/garden"
    local votes_dir="$AUTOMATON_DIR/votes"
    local hist_file="$AUTOMATON_DIR/constitution-history.json"

    # Find wilted ideas that were rejected by quorum (have vote_id and wilt reason mentions "rejected")
    local rejected_ideas=()
    local rejected_display=()
    local idea_file
    for idea_file in "$garden_dir"/idea-*.json; do
        [ -f "$idea_file" ] || continue
        local stage vote_id title wilt_reason
        stage=$(jq -r '.stage' "$idea_file")
        [ "$stage" = "wilt" ] || continue
        vote_id=$(jq -r '.vote_id // ""' "$idea_file")
        [ -n "$vote_id" ] && [ "$vote_id" != "null" ] || continue
        # Check that the wilt reason references quorum rejection
        wilt_reason=$(jq -r '.stage_history[-1].reason // ""' "$idea_file")
        echo "$wilt_reason" | grep -qi "rejected" || continue
        title=$(jq -r '.title' "$idea_file")
        local idea_id
        idea_id=$(jq -r '.id' "$idea_file")
        rejected_ideas+=("$idea_id")
        # Get vote tally for display
        local approve_count=0 total_count=0
        if [ -f "$votes_dir/${vote_id}.json" ]; then
            approve_count=$(jq '.tally.approve // 0' "$votes_dir/${vote_id}.json")
            total_count=$(jq '(.tally.approve // 0) + (.tally.reject // 0) + (.tally.abstain // 0)' "$votes_dir/${vote_id}.json")
        fi
        rejected_display+=("  ${idea_id}  \"${title}\"   rejected ${vote_id} (${approve_count}/${total_count})")
    done

    if [ ${#rejected_ideas[@]} -eq 0 ]; then
        echo "No rejected ideas found to override."
        return 0
    fi

    echo ""
    echo "Recent rejected ideas:"
    for line in "${rejected_display[@]}"; do
        echo "$line"
    done
    echo ""

    printf "Override which idea? Enter ID: "
    local selected_id
    read -r selected_id

    # Validate the selected idea exists and is in the rejected list
    local found=false
    for rid in "${rejected_ideas[@]}"; do
        if [ "$rid" = "$selected_id" ]; then
            found=true
            break
        fi
    done

    if [ "$found" != "true" ]; then
        echo "Error: Idea $selected_id not found in rejected ideas list." >&2
        return 1
    fi

    local selected_file="$garden_dir/${selected_id}.json"
    local selected_title selected_vote_id
    selected_title=$(jq -r '.title' "$selected_file")
    selected_vote_id=$(jq -r '.vote_id // ""' "$selected_file")

    echo ""
    echo "WARNING: Overriding quorum rejection of ${selected_id}."
    echo "This bypasses collective decision-making (Article II)."
    echo "The override will be recorded in the audit trail."
    echo ""
    printf "Confirm override? (y/n): "
    local confirm
    read -r confirm

    if [ "$confirm" != "y" ]; then
        echo "Override cancelled."
        return 0
    fi

    # Re-promote idea to bloom stage with force
    _garden_advance_stage "$selected_id" "bloom" "Human override — Article II sovereignty" "true"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to re-promote idea ${selected_id}." >&2
        return 1
    fi

    _garden_recompute_priorities 2>/dev/null || true

    # Update vote record with override information
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [ -n "$selected_vote_id" ] && [ "$selected_vote_id" != "null" ] && [ -f "$votes_dir/${selected_vote_id}.json" ]; then
        local vote_file="$votes_dir/${selected_vote_id}.json"
        local tmp_file="${vote_file}.tmp"
        jq --arg now "$now" \
           --arg reason "Human override — Article II sovereignty" \
           '. + {override: {overridden_at: $now, reason: $reason, by: "human"}}' \
           "$vote_file" > "$tmp_file" && mv "$tmp_file" "$vote_file"
    fi

    # Log override in constitution history
    if [ -f "$hist_file" ]; then
        local tmp_hist="${hist_file}.tmp"
        jq --arg idea_id "$selected_id" \
           --arg vote_id "$selected_vote_id" \
           --arg now "$now" \
           --arg reason "Human override — Article II sovereignty" \
           '.overrides = (.overrides // []) + [{idea_id: $idea_id, vote_id: $vote_id, overridden_at: $now, reason: $reason}]' \
           "$hist_file" > "$tmp_hist" && mv "$tmp_hist" "$hist_file"
    fi

    echo ""
    echo "Override recorded. ${selected_id} → bloom (re-promoted for implementation)"
    echo "Override logged in ${selected_vote_id} with reason: \"Human override — Article II sovereignty\""
}

# Writes .automaton/evolution/pause flag file to halt the evolution loop
# between phases. The evolution loop checks for this file between cycles
# and stops cleanly when found. To unpause, delete the file and resume
# with --evolve --resume.
_cli_pause() {
    local evol_dir="$AUTOMATON_DIR/evolution"
    mkdir -p "$evol_dir"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "$evol_dir/pause" << EOF
paused_at=$now
paused_by=human
EOF

    log "EVOLVE" "Pause flag written to $evol_dir/pause"
    echo ""
    echo "Evolution paused."
    echo "The evolution loop will complete its current phase and stop."
    echo ""
    echo "To resume: rm .automaton/evolution/pause && ./automaton.sh --evolve --resume"
}

# ---------------------------------------------------------------------------
# Help Display
# ---------------------------------------------------------------------------

_show_help() {
    cat <<'HELPTEXT'
Usage: automaton.sh [OPTIONS]

Multi-phase orchestrator for autonomous Claude agent workflows.

Standard Mode:
  --resume              Resume from saved state (.automaton/state.json)
  --skip-research       Skip Phase 1 (research), start at Phase 2 (plan)
  --skip-review         Skip Phase 4 (review), mark COMPLETE after build
  --config FILE         Use an alternate config file (default: automaton.config.json)
  --scope PATH          Scope agent operations to a directory (monorepo support) (spec-60)
  --mode MODE           Set collaboration mode: collaborative|supervised|autonomous (spec-61)
  --research "topic"    Run standalone deep research on a topic, write report, and exit (spec-63)
  --dry-run             Load config, run Gate 1, show settings, then exit
  --self                Self-build mode: improve automaton itself (spec-25)
  --self --continue     Auto-pick highest-priority backlog item and run (spec-26)
  --stats               Display run history and performance trends (spec-26)
  --budget-check        Show weekly allowance status without starting a run (spec-35)
  --setup               Run interactive setup wizard (re-generates config) (spec-57)
  --no-setup            Skip setup wizard; use built-in defaults (spec-57)
  --wizard              Force-run requirements wizard even if specs exist (spec-59)
  --no-wizard           Skip requirements wizard; fail at Gate 1 if no specs (spec-59)
  --validate-config     Validate config file and exit (spec-50)
  --doctor              Check environment, tools, and project health (spec-48)
  --critique-specs      Run spec critique, produce report, and exit (spec-47)
  --skip-critique       Skip pre-flight spec critique even when auto_preflight is on
  --steelman            Run adversarial plan critique, produce STEELMAN.md, and exit (spec-53)
  --complexity TIER     Override complexity assessment (simple|moderate|complex) (spec-51)
  --log-level LEVEL     Set work log verbosity (minimal|normal|verbose) (spec-55)
  --help, -h            Show this help message

Evolution Mode:
  --evolve              Start autonomous evolution loop (implies --self)
  --evolve --cycles N   Run exactly N evolution cycles
  --evolve --dry-run    Show REFLECT analysis without acting
  --evolve --resume     Resume interrupted evolution

Garden:
  --plant "idea"        Plant a new seed in the garden
  --garden              Display garden summary
  --garden-detail ID    Show full idea details
  --water ID "evidence" Add evidence to an idea
  --prune ID "reason"   Wilt an idea with a reason
  --promote ID          Force-promote idea to bloom

Project Garden:
  --suggest             Generate project improvement suggestions (one-shot)
  --project-garden      Display current project suggestions

Observation:
  --health              Display health metrics dashboard
  --signals             Display active stigmergic signals
  --inspect ID          Show vote record details

Governance:
  --constitution        Display the current constitution
  --amend               Propose a constitutional amendment
  --override            Override a quorum decision
  --pause-evolution     Pause running evolution loop

Exit codes:
  0   All phases complete, review passed
  1   General error or max consecutive failures
  2   Budget exhausted (resumable with --resume)
  3   Escalation required (human intervention needed)
  130 Interrupted by user (resumable with --resume)
HELPTEXT
}
