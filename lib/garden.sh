#!/usr/bin/env bash
# lib/garden.sh — Idea garden: planting, watering, wilting, pruning, and bloom management.
# Spec references: spec-41 (evolution garden), spec-44 (garden CLI)

_garden_plant_seed() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local title="${1:?_garden_plant_seed requires title}"
    local description="${2:?_garden_plant_seed requires description}"
    local origin_type="${3:?_garden_plant_seed requires origin_type}"
    local origin_source="${4:?_garden_plant_seed requires origin_source}"
    local created_by="${5:?_garden_plant_seed requires created_by}"
    local estimated_complexity="${6:-medium}"
    local tags_csv="${7:-}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local index_file="$garden_dir/_index.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Ensure garden directory exists
    mkdir -p "$garden_dir"

    # Initialize index if it doesn't exist
    if [ ! -f "$index_file" ]; then
        cat > "$index_file" << 'IDXEOF'
{"total":0,"by_stage":{"seed":0,"sprout":0,"bloom":0,"harvest":0,"wilt":0},"bloom_candidates":[],"recent_activity":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
IDXEOF
    fi

    # Read and increment next_id
    local next_id
    next_id=$(jq -r '.next_id // 1' "$index_file")
    local idea_id
    idea_id=$(printf "idea-%03d" "$next_id")
    local idea_file="$garden_dir/${idea_id}.json"

    # Build tags JSON array from CSV
    local tags_json="[]"
    if [ -n "$tags_csv" ]; then
        tags_json=$(echo "$tags_csv" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Create the idea JSON file with complete schema
    jq -n \
        --arg id "$idea_id" \
        --arg title "$title" \
        --arg description "$description" \
        --arg stage "seed" \
        --arg origin_type "$origin_type" \
        --arg origin_source "$origin_source" \
        --arg created_by "$created_by" \
        --arg created_at "$now" \
        --argjson tags "$tags_json" \
        --arg complexity "$estimated_complexity" \
        --arg updated_at "$now" \
        '{
            id: $id,
            title: $title,
            description: $description,
            stage: $stage,
            origin: {
                type: $origin_type,
                source: $origin_source,
                created_by: $created_by,
                created_at: $created_at
            },
            evidence: [],
            tags: $tags,
            priority: 0,
            estimated_complexity: $complexity,
            related_specs: [],
            related_signals: [],
            related_ideas: [],
            stage_history: [
                {
                    stage: "seed",
                    entered_at: $created_at,
                    reason: "Planted as new seed"
                }
            ],
            vote_id: null,
            implementation: null,
            updated_at: $updated_at
        }' > "$idea_file"

    log "GARDEN" "Planted seed: $idea_id - $title"

    # Rebuild the garden index
    _garden_rebuild_index

    echo "$idea_id"
}

# Adds an evidence item to an existing idea, updates updated_at,
# and calls _garden_advance_stage() if thresholds are met.
#
# Args: idea_id evidence_type observation added_by
# Returns: 0 on success, 1 if idea not found
_garden_water() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_water requires idea_id}"
    local evidence_type="${2:?_garden_water requires evidence_type}"
    local observation="${3:?_garden_water requires observation}"
    local added_by="${4:?_garden_water requires added_by}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "GARDEN" "Idea $idea_id not found"
        return 1
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Add evidence item and update timestamp
    local tmp_file="${idea_file}.tmp"
    jq --arg type "$evidence_type" \
       --arg obs "$observation" \
       --arg by "$added_by" \
       --arg now "$now" \
       '.evidence += [{type: $type, observation: $obs, added_by: $by, added_at: $now}] | .updated_at = $now' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Watered $idea_id with $evidence_type evidence"

    # Check if stage advancement is warranted
    local stage evidence_count
    stage=$(jq -r '.stage' "$idea_file")
    evidence_count=$(jq '.evidence | length' "$idea_file")

    if [ "$stage" = "seed" ] && [ "$evidence_count" -ge "$GARDEN_SPROUT_THRESHOLD" ]; then
        _garden_advance_stage "$idea_id" "sprout" "Evidence count ($evidence_count) reached sprout threshold ($GARDEN_SPROUT_THRESHOLD)"
    elif [ "$stage" = "sprout" ]; then
        local priority
        priority=$(jq -r '.priority // 0' "$idea_file")
        if [ "$evidence_count" -ge "$GARDEN_BLOOM_THRESHOLD" ] && [ "$priority" -ge "$GARDEN_BLOOM_PRIORITY_THRESHOLD" ]; then
            _garden_advance_stage "$idea_id" "bloom" "Evidence count ($evidence_count) and priority ($priority) met bloom thresholds"
        fi
    fi

    _garden_rebuild_index
}

# Transitions an idea to the next lifecycle stage.
# Validates threshold requirements for automatic transitions.
# Supports a force parameter for human promotion (bypasses thresholds).
#
# Args: idea_id target_stage reason [force]
# Returns: 0 on success, 1 on failure
_garden_advance_stage() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_advance_stage requires idea_id}"
    local target_stage="${2:?_garden_advance_stage requires target_stage}"
    local reason="${3:?_garden_advance_stage requires reason}"
    local force="${4:-false}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "GARDEN" "Idea $idea_id not found"
        return 1
    fi

    local current_stage
    current_stage=$(jq -r '.stage' "$idea_file")

    # Validate stage transition order (unless forced)
    if [ "$force" != "true" ]; then
        local transition="${current_stage}_to_${target_stage}"
        case "$transition" in
            seed_to_sprout|sprout_to_bloom|bloom_to_harvest) ;;
            *)
                log "GARDEN" "Invalid transition: $current_stage -> $target_stage for $idea_id"
                return 1
                ;;
        esac

        # Validate thresholds for non-forced transitions
        local evidence_count
        evidence_count=$(jq '.evidence | length' "$idea_file")

        if [ "$target_stage" = "sprout" ] && [ "$evidence_count" -lt "$GARDEN_SPROUT_THRESHOLD" ]; then
            log "GARDEN" "Cannot advance $idea_id to sprout: need $GARDEN_SPROUT_THRESHOLD evidence, have $evidence_count"
            return 1
        fi

        if [ "$target_stage" = "bloom" ]; then
            local priority
            priority=$(jq -r '.priority // 0' "$idea_file")
            if [ "$evidence_count" -lt "$GARDEN_BLOOM_THRESHOLD" ]; then
                log "GARDEN" "Cannot advance $idea_id to bloom: need $GARDEN_BLOOM_THRESHOLD evidence, have $evidence_count"
                return 1
            fi
            if [ "$priority" -lt "$GARDEN_BLOOM_PRIORITY_THRESHOLD" ]; then
                log "GARDEN" "Cannot advance $idea_id to bloom: need priority >= $GARDEN_BLOOM_PRIORITY_THRESHOLD, have $priority"
                return 1
            fi
        fi
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update stage and record history
    local tmp_file="${idea_file}.tmp"
    jq --arg stage "$target_stage" \
       --arg now "$now" \
       --arg reason "$reason" \
       '.stage = $stage | .updated_at = $now | .stage_history += [{stage: $stage, entered_at: $now, reason: $reason}]' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Advanced $idea_id: $current_stage -> $target_stage"
}

# Moves an idea to the wilt stage with a reason.
# Records a stage_history entry and rebuilds the index.
# Wilting preserves the idea record for audit while removing it from active consideration.
#
# Args: idea_id reason
# Returns: 0 on success, 1 on failure
_garden_wilt() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_wilt requires idea_id}"
    local reason="${2:?_garden_wilt requires reason}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_file="$garden_dir/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "GARDEN" "Idea $idea_id not found"
        return 1
    fi

    local current_stage
    current_stage=$(jq -r '.stage' "$idea_file")

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update stage to wilt, record reason in stage_history, update timestamp
    local tmp_file="${idea_file}.tmp"
    jq --arg now "$now" \
       --arg reason "$reason" \
       '.stage = "wilt" | .updated_at = $now | .stage_history += [{stage: "wilt", entered_at: $now, reason: $reason}]' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Wilted $idea_id ($current_stage -> wilt): $reason"

    _garden_rebuild_index
}

# Recomputes priority scores for all active (non-wilted, non-harvested) ideas
# using the 5-component formula from spec-38 §4:
#   priority = (evidence_weight*30) + (signal_strength*25) + (metric_severity*25) + (age_bonus*10) + (human_boost*10)
#
# Components:
#   evidence_weight: min(evidence_count / bloom_threshold, 1.0)
#   signal_strength: max strength of related signals (0 if none or no signals file)
#   metric_severity: normalized severity of originating metric breach (0-1.0)
#   age_bonus:       min(days_since_creation / 30, 1.0)
#   human_boost:     1.0 if origin.type == "human", else 0
#
# Updates each idea's priority field in-place. Skips wilted and harvested ideas.
_garden_recompute_priorities() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 0; fi
    local garden_dir="$AUTOMATON_DIR/garden"
    local signals_file="$AUTOMATON_DIR/signals.json"

    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

    local now_epoch
    now_epoch=$(date -u +%s)

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")

        # Skip wilted and harvested ideas
        if [ "$stage" = "wilt" ] || [ "$stage" = "harvest" ]; then
            continue
        fi

        # 1. evidence_weight: min(evidence_count / bloom_threshold, 1.0)
        local evidence_count
        evidence_count=$(jq '.evidence | length' "$f")
        local evidence_weight
        evidence_weight=$(awk "BEGIN { v = $evidence_count / $GARDEN_BLOOM_THRESHOLD; print (v > 1.0 ? 1.0 : v) }")

        # 2. signal_strength: max strength of related signals
        local signal_strength=0
        if [ -f "$signals_file" ]; then
            local related_signals
            related_signals=$(jq -r '.related_signals // [] | .[]' "$f" 2>/dev/null)
            if [ -n "$related_signals" ]; then
                local max_str
                max_str=$(echo "$related_signals" | while IFS= read -r sig_id; do
                    jq -r --arg id "$sig_id" '.signals[]? | select(.id == $id) | .strength // 0' "$signals_file" 2>/dev/null
                done | sort -rn | head -1)
                if [ -n "$max_str" ]; then
                    signal_strength="$max_str"
                fi
            fi
        fi

        # 3. metric_severity: based on origin type and source
        local metric_severity=0
        local origin_type
        origin_type=$(jq -r '.origin.type' "$f")
        if [ "$origin_type" = "metric" ]; then
            # Extract numeric value from origin.source if it contains a threshold breach
            local origin_source
            origin_source=$(jq -r '.origin.source // ""' "$f")
            local extracted_val
            extracted_val=$(echo "$origin_source" | grep -oE '[0-9]+\.?[0-9]*' | tail -1 || true)
            if [ -n "$extracted_val" ]; then
                # Normalize: cap at 1.0 (values like 0.25 become 0.25, values > 1 become 1.0)
                metric_severity=$(awk "BEGIN { v = $extracted_val; print (v > 1.0 ? 1.0 : v) }")
            else
                # Metric origin but no extractable value — assign a moderate default
                metric_severity="0.5"
            fi
        fi

        # 4. age_bonus: min(days_since_creation / 30, 1.0)
        local created_at
        created_at=$(jq -r '.origin.created_at' "$f")
        local created_epoch
        created_epoch=$(date -u -d "$created_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || echo "$now_epoch")
        local days_old
        days_old=$(( (now_epoch - created_epoch) / 86400 ))
        local age_bonus
        age_bonus=$(awk "BEGIN { v = $days_old / 30.0; print (v > 1.0 ? 1.0 : v) }")

        # 5. human_boost: 1.0 if origin.type == "human", else 0
        local human_boost=0
        if [ "$origin_type" = "human" ]; then
            human_boost=1
        fi

        # Compute final priority: integer 0-100
        local priority
        priority=$(awk "BEGIN {
            p = ($evidence_weight * 30) + ($signal_strength * 25) + ($metric_severity * 25) + ($age_bonus * 10) + ($human_boost * 10);
            p = int(p + 0.5);
            if (p > 100) p = 100;
            if (p < 0) p = 0;
            print p
        }")

        # Update the idea file
        local tmp_file="${f}.tmp"
        jq --argjson priority "$priority" '.priority = $priority' "$f" > "$tmp_file" && mv "$tmp_file" "$f"
    done

    log "GARDEN" "Recomputed priorities for all active ideas"
}

# Regenerates .automaton/garden/_index.json from all idea files.
# Provides total counts, by_stage breakdown, bloom_candidates sorted by priority,
# recent_activity, next_id, and updated_at.
_garden_rebuild_index() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 0; fi
    local garden_dir="$AUTOMATON_DIR/garden"
    local index_file="$garden_dir/_index.json"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Collect all idea files
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)

    local total=0
    local seed_count=0 sprout_count=0 bloom_count=0 harvest_count=0 wilt_count=0
    local max_id=0
    local bloom_candidates="[]"
    local recent_activity="[]"

    for f in $idea_files; do
        [ -f "$f" ] || continue
        total=$((total + 1))

        local stage id priority title updated_at_idea
        stage=$(jq -r '.stage' "$f")
        id=$(jq -r '.id' "$f")
        priority=$(jq -r '.priority // 0' "$f")
        title=$(jq -r '.title' "$f")
        updated_at_idea=$(jq -r '.updated_at' "$f")

        # Extract numeric ID for next_id calculation
        local num
        num=$(echo "$id" | sed 's/idea-0*//')
        if [ "$num" -gt "$max_id" ] 2>/dev/null; then
            max_id=$num
        fi

        # Count by stage
        case "$stage" in
            seed)    seed_count=$((seed_count + 1)) ;;
            sprout)  sprout_count=$((sprout_count + 1)) ;;
            bloom)   bloom_count=$((bloom_count + 1))
                     bloom_candidates=$(echo "$bloom_candidates" | jq --arg id "$id" --arg title "$title" --argjson priority "$priority" '. + [{"id": $id, "title": $title, "priority": $priority}]')
                     ;;
            harvest) harvest_count=$((harvest_count + 1)) ;;
            wilt)    wilt_count=$((wilt_count + 1)) ;;
        esac

        # Track recent activity (last stage_history entry)
        local last_action last_at
        last_action=$(jq -r '.stage_history[-1].stage // "unknown"' "$f")
        last_at=$(jq -r '.stage_history[-1].entered_at // ""' "$f")
        if [ -n "$last_at" ]; then
            recent_activity=$(echo "$recent_activity" | jq --arg id "$id" --arg action "$last_action" --arg at "$last_at" '. + [{"id": $id, "action": $action, "at": $at}]')
        fi
    done

    # Sort bloom candidates by priority descending
    bloom_candidates=$(echo "$bloom_candidates" | jq 'sort_by(-.priority)')

    # Keep only most recent 10 activity entries, sorted by time descending
    recent_activity=$(echo "$recent_activity" | jq 'sort_by(.at) | reverse | .[0:10]')

    local next_id=$((max_id + 1))

    # Write the index
    jq -n \
        --argjson total "$total" \
        --argjson seed "$seed_count" \
        --argjson sprout "$sprout_count" \
        --argjson bloom "$bloom_count" \
        --argjson harvest "$harvest_count" \
        --argjson wilt "$wilt_count" \
        --argjson bloom_candidates "$bloom_candidates" \
        --argjson recent_activity "$recent_activity" \
        --argjson next_id "$next_id" \
        --arg updated_at "$now" \
        '{
            total: $total,
            by_stage: {
                seed: $seed,
                sprout: $sprout,
                bloom: $bloom,
                harvest: $harvest,
                wilt: $wilt
            },
            bloom_candidates: $bloom_candidates,
            recent_activity: $recent_activity,
            next_id: $next_id,
            updated_at: $updated_at
        }' > "$index_file"
}

# Auto-wilts seeds older than GARDEN_SEED_TTL_DAYS and sprouts older than
# GARDEN_SPROUT_TTL_DAYS that have received no new evidence. TTL for seeds
# is measured from creation date; TTL for sprouts is measured from the most
# recent evidence timestamp (or creation date if no evidence).
_garden_prune_expired() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 0; fi
    local garden_dir="$AUTOMATON_DIR/garden"

    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)
    [ -n "$idea_files" ] || return 0

    local now_epoch
    now_epoch=$(date -u +%s)
    local seed_ttl_secs=$((GARDEN_SEED_TTL_DAYS * 86400))
    local sprout_ttl_secs=$((GARDEN_SPROUT_TTL_DAYS * 86400))
    local pruned=0

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")

        if [ "$stage" = "seed" ]; then
            # Seeds: TTL from creation date
            local created_at
            created_at=$(jq -r '.origin.created_at' "$f")
            local created_epoch
            created_epoch=$(date -u -d "$created_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || echo "$now_epoch")
            local age_secs=$((now_epoch - created_epoch))
            if [ "$age_secs" -ge "$seed_ttl_secs" ]; then
                local idea_id
                idea_id=$(jq -r '.id' "$f")
                _garden_wilt "$idea_id" "TTL expired: seed received no evidence after ${GARDEN_SEED_TTL_DAYS} days"
                pruned=$((pruned + 1))
            fi
        elif [ "$stage" = "sprout" ]; then
            # Sprouts: TTL from most recent evidence timestamp
            local last_evidence_at
            last_evidence_at=$(jq -r '(.evidence | last | .added_at) // .origin.created_at' "$f")
            local last_evidence_epoch
            last_evidence_epoch=$(date -u -d "$last_evidence_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_evidence_at" +%s 2>/dev/null || echo "$now_epoch")
            local stale_secs=$((now_epoch - last_evidence_epoch))
            if [ "$stale_secs" -ge "$sprout_ttl_secs" ]; then
                local idea_id
                idea_id=$(jq -r '.id' "$f")
                _garden_wilt "$idea_id" "TTL expired: sprout received no new evidence after ${GARDEN_SPROUT_TTL_DAYS} days"
                pruned=$((pruned + 1))
            fi
        fi
        # bloom, harvest, wilt stages are immune to TTL pruning
    done

    if [ "$pruned" -gt 0 ]; then
        log "GARDEN" "Pruned $pruned expired ideas"
    fi
}

# Checks for existing non-wilted ideas with matching tags before creating a
# new seed. Returns the existing idea ID (on stdout) if a match is found.
# A match requires at least one overlapping tag between the search tags and
# the candidate idea's tags. Wilted and harvested ideas are excluded.
#
# Args: tags_csv (comma-separated tags to match against)
# Returns: 0 and prints idea ID if duplicate found, 1 if no match
_garden_find_duplicates() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local tags_csv="${1:?_garden_find_duplicates requires tags_csv}"

    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)
    [ -n "$idea_files" ] || return 1

    # Convert search tags CSV to newline-separated list for comparison
    local search_tags
    search_tags=$(echo "$tags_csv" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")

        # Skip wilted and harvested ideas
        [ "$stage" = "wilt" ] && continue
        [ "$stage" = "harvest" ] && continue

        # Get idea's tags as newline-separated list
        local idea_tags
        idea_tags=$(jq -r '.tags[]' "$f" 2>/dev/null)
        [ -n "$idea_tags" ] || continue

        # Check for any overlapping tag
        local tag
        while IFS= read -r tag; do
            [ -n "$tag" ] || continue
            if echo "$idea_tags" | grep -qxF "$tag"; then
                local idea_id
                idea_id=$(jq -r '.id' "$f")
                log "GARDEN" "Duplicate detected: $idea_id matches tags [$tags_csv]"
                echo "$idea_id"
                return 0
            fi
        done <<< "$search_tags"
    done

    return 1
}

# Returns sprout-stage ideas eligible for bloom transition, sorted by priority
# descending. An idea is eligible when its evidence count >= bloom_threshold
# and its priority >= bloom_priority_threshold.
# Outputs one idea ID per line (highest priority first).
#
# Returns: 0 if candidates found, 1 if none
_garden_get_bloom_candidates() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local garden_dir="$AUTOMATON_DIR/garden"
    local idea_files
    idea_files=$(find "$garden_dir" -name 'idea-*.json' -type f 2>/dev/null | sort)
    [ -n "$idea_files" ] || return 1

    local candidates=""

    for f in $idea_files; do
        [ -f "$f" ] || continue

        local stage
        stage=$(jq -r '.stage' "$f")
        [ "$stage" = "sprout" ] || continue

        local evidence_count priority
        evidence_count=$(jq '.evidence | length' "$f")
        priority=$(jq -r '.priority // 0' "$f")

        if [ "$evidence_count" -ge "$GARDEN_BLOOM_THRESHOLD" ] && [ "$priority" -ge "$GARDEN_BLOOM_PRIORITY_THRESHOLD" ]; then
            local idea_id
            idea_id=$(jq -r '.id' "$f")
            candidates="${candidates}${priority} ${idea_id}"$'\n'
        fi
    done

    [ -n "$candidates" ] || return 1

    # Sort by priority descending, output only idea IDs
    echo "$candidates" | sort -t' ' -k1 -nr | awk '{print $2}'
    return 0
}
