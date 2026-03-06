#!/usr/bin/env bash
# lib/signals.sh — Stigmergic signal system: emission, decay, reinforcement, and garden linking.
# Spec references: spec-41 (stigmergic signals), spec-44 (signal CLI)

_signal_enabled() {
    [ "${STIGMERGY_ENABLED:-true}" = "true" ]
}

# Returns the default decay_rate for a given signal type.
# See spec-42 §3 for type-specific decay rates.
_signal_default_decay_rate() {
    local type="$1"
    case "$type" in
        attention_needed)    echo "0.10" ;;
        promising_approach)  echo "0.05" ;;
        recurring_pattern)   echo "0.05" ;;
        efficiency_opportunity) echo "0.08" ;;
        quality_concern)     echo "0.07" ;;
        complexity_warning)  echo "0.06" ;;
        *)                   echo "0.05" ;;
    esac
}

# Lazily initializes .automaton/signals.json with an empty structure.
# Called on first signal emission, not during initialize_state().
_signal_init_file() {
    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        cat > "$signals_file" << 'SIGEOF'
{"version":1,"signals":[],"next_id":1,"updated_at":"1970-01-01T00:00:00Z"}
SIGEOF
    fi
}

# Emits a new signal or reinforces an existing one if a match is found.
# Creates .automaton/signals.json lazily on first call.
#
# Args: type title description agent cycle detail
# Returns: 0 on success, outputs signal ID (SIG-NNN)
_signal_emit() {
    if ! _signal_enabled; then return 1; fi
    local type="${1:?_signal_emit requires type}"
    local title="${2:?_signal_emit requires title}"
    local description="${3:?_signal_emit requires description}"
    local agent="${4:-unknown}"
    local cycle="${5:-0}"
    local detail="${6:-}"

    local signals_file="$AUTOMATON_DIR/signals.json"

    # Lazy initialization — create signals.json on first emission
    _signal_init_file

    # Check for existing matching signal to reinforce instead of duplicate
    local match_id
    match_id=$(_signal_find_match "$type" "$title" "$description")

    if [ -n "$match_id" ]; then
        # Reinforce the existing signal with a new observation
        _signal_reinforce "$match_id" "$agent" "$cycle" "$detail"
        log "SIGNAL" "Reinforced: $match_id - $title"
        echo "$match_id"
        return 0
    fi

    # No match — create a new signal
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local next_id
    next_id=$(jq -r '.next_id // 1' "$signals_file")
    local signal_id
    signal_id=$(printf "SIG-%03d" "$next_id")

    local decay_rate
    decay_rate=$(_signal_default_decay_rate "$type")

    local initial_strength="${STIGMERGY_INITIAL_STRENGTH:-0.3}"

    # Append the new signal and update next_id
    local tmp_file="${signals_file}.tmp"
    jq --arg id "$signal_id" \
       --arg type "$type" \
       --arg title "$title" \
       --arg desc "$description" \
       --argjson strength "$initial_strength" \
       --argjson decay_rate "$decay_rate" \
       --arg agent "$agent" \
       --argjson cycle "$cycle" \
       --arg now "$now" \
       --arg detail "$detail" \
       '.signals += [{
            id: $id,
            type: $type,
            title: $title,
            description: $desc,
            strength: $strength,
            decay_rate: $decay_rate,
            observations: [{
                agent: $agent,
                cycle: $cycle,
                timestamp: $now,
                detail: $detail
            }],
            related_ideas: [],
            created_at: $now,
            last_reinforced_at: $now,
            last_decayed_at: $now
        }] | .next_id = (.next_id + 1) | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    log "SIGNAL" "Emitted: $signal_id - $title (type=$type, strength=$initial_strength)"
    echo "$signal_id"
}

# Reinforces an existing signal by adding an observation and increasing strength.
# Strength increases by STIGMERGY_REINFORCE_INCREMENT, capped at 1.0.
#
# Args: signal_id agent cycle detail
# Returns: 0 on success
_signal_reinforce() {
    if ! _signal_enabled; then return 1; fi
    local signal_id="${1:?_signal_reinforce requires signal_id}"
    local agent="${2:-unknown}"
    local cycle="${3:-0}"
    local detail="${4:-}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 1

    local reinforce_increment="${STIGMERGY_REINFORCE_INCREMENT:-0.15}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${signals_file}.tmp"
    jq --arg id "$signal_id" \
       --argjson inc "$reinforce_increment" \
       --arg agent "$agent" \
       --argjson cycle "$cycle" \
       --arg now "$now" \
       --arg detail "$detail" \
       '(.signals[] | select(.id == $id)) |=
            (.observations += [{agent: $agent, cycle: $cycle, timestamp: $now, detail: $detail}]
            | .strength = ([.strength + $inc, 1.0] | min)
            | .last_reinforced_at = $now)
        | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"
}

# Finds an existing signal of the same type with sufficient word overlap.
# Uses Jaccard similarity on key terms from title+description.
# Returns the matching signal ID if overlap >= match_threshold, empty otherwise.
#
# Args: type title description
# Outputs: matching signal ID (e.g. SIG-001) or empty string
_signal_find_match() {
    local type="${1:?_signal_find_match requires type}"
    local title="${2:?_signal_find_match requires title}"
    local description="${3:-}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 0

    local threshold="${STIGMERGY_MATCH_THRESHOLD:-0.6}"

    # Extract same-type signal IDs, titles, and descriptions via jq
    local candidates
    candidates=$(jq -r --arg t "$type" \
        '.signals[] | select(.type == $t) | "\(.id)\t\(.title) \(.description)"' \
        "$signals_file" 2>/dev/null) || return 0

    [ -n "$candidates" ] || return 0

    # Build the new signal's word set (lowercase, unique, stop words removed)
    local new_text
    new_text=$(printf '%s %s' "$title" "$description" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | grep -vxE '(a|an|the|in|on|at|of|to|is|it|and|or|for|by|with|from|that|this|was|are|has|been|but|not|its)' || true)

    [ -n "$new_text" ] || return 0

    local best_id=""
    local best_score=0

    while IFS=$'\t' read -r sig_id sig_text; do
        # Build the existing signal's word set
        local existing_text
        existing_text=$(printf '%s' "$sig_text" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | grep -vxE '(a|an|the|in|on|at|of|to|is|it|and|or|for|by|with|from|that|this|was|are|has|been|but|not|its)' || true)

        [ -n "$existing_text" ] || continue

        # Compute Jaccard similarity: |intersection| / |union|
        local intersection union
        intersection=$(comm -12 <(echo "$new_text") <(echo "$existing_text") | wc -l)
        union=$(comm <(echo "$new_text") <(echo "$existing_text") | sed 's/^\t*//' | sort -u | wc -l)

        [ "$union" -gt 0 ] || continue

        # Compare using integer arithmetic (multiply by 100 to avoid floats)
        local score_100=$(( intersection * 100 / union ))
        local threshold_100
        threshold_100=$(printf '%.0f' "$(echo "$threshold * 100" | bc 2>/dev/null || echo "60")")

        if [ "$score_100" -ge "$threshold_100" ] && [ "$score_100" -gt "$best_score" ]; then
            best_score=$score_100
            best_id=$sig_id
        fi
    done <<< "$candidates"

    echo "$best_id"
}

# Decays all signal strengths by their individual decay_rate.
# Removes signals whose strength drops below decay_floor.
# Called at the start of each evolution cycle (spec-42 §4).
#
# Returns: 0 on success, 1 if disabled or no signals file
_signal_decay_all() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 1

    local decay_floor="${STIGMERGY_DECAY_FLOOR:-0.05}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${signals_file}.tmp"
    jq --argjson floor "$decay_floor" \
       --arg now "$now" \
       '.signals = [.signals[] |
            .strength = (.strength - .decay_rate) |
            .last_decayed_at = $now
        ] | .signals = [.signals[] | select(.strength >= $floor)] | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    local remaining
    remaining=$(jq '.signals | length' "$signals_file")
    log "SIGNAL" "Decay applied: $remaining signals remaining (floor=$decay_floor)"
}

_signal_prune() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 0

    local max_signals="${STIGMERGY_MAX_SIGNALS:-100}"
    local current_count
    current_count=$(jq '.signals | length' "$signals_file")

    if [ "$current_count" -le "$max_signals" ]; then
        return 0
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local pruned=$(( current_count - max_signals ))

    local tmp_file="${signals_file}.tmp"
    jq --argjson keep "$max_signals" \
       --arg now "$now" \
       '.signals = (.signals | sort_by(-.strength) | .[0:$keep]) | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    log "SIGNAL" "Pruned $pruned weakest signals (max=$max_signals, kept strongest $max_signals)"
}

# Returns signals with strength >= threshold as a JSON array.
# Args: threshold (float, e.g. 0.6)
# Outputs: JSON array of matching signal objects
_signal_get_strong() {
    if ! _signal_enabled; then return 1; fi
    local threshold="${1:?_signal_get_strong requires threshold}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    jq --argjson thr "$threshold" \
        '[.signals[] | select(.strength >= $thr)]' \
        "$signals_file"
}

# Returns signals matching the given type as a JSON array.
# Args: type (string, e.g. "attention_needed")
# Outputs: JSON array of matching signal objects
_signal_get_by_type() {
    if ! _signal_enabled; then return 1; fi
    local type="${1:?_signal_get_by_type requires type}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    jq --arg t "$type" \
        '[.signals[] | select(.type == $t)]' \
        "$signals_file"
}

# Returns all signals with strength > decay_floor as a JSON array.
# Outputs: JSON array of active signal objects
_signal_get_active() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    local decay_floor="${STIGMERGY_DECAY_FLOOR:-0.05}"

    jq --argjson floor "$decay_floor" \
        '[.signals[] | select(.strength >= $floor)]' \
        "$signals_file"
}

# Returns signals with no related garden ideas as a JSON array.
# Outputs: JSON array of unlinked signal objects
_signal_get_unlinked() {
    if ! _signal_enabled; then return 1; fi

    local signals_file="$AUTOMATON_DIR/signals.json"
    if [ ! -f "$signals_file" ]; then
        echo "[]"
        return 0
    fi

    jq '[.signals[] | select(.related_ideas | length == 0)]' \
        "$signals_file"
}

# Adds a garden idea ID to a signal's related_ideas array (dedup-safe).
# This is one half of the bidirectional link between signals and garden ideas.
#
# Args: signal_id idea_id
# Returns: 0 on success, 1 if signal not found or stigmergy disabled
_signal_link_idea() {
    if ! _signal_enabled; then return 1; fi
    local signal_id="${1:?_signal_link_idea requires signal_id}"
    local idea_id="${2:?_signal_link_idea requires idea_id}"

    local signals_file="$AUTOMATON_DIR/signals.json"
    [ -f "$signals_file" ] || return 1

    # Check signal exists
    local exists
    exists=$(jq --arg id "$signal_id" '[.signals[] | select(.id == $id)] | length' "$signals_file")
    [ "$exists" -gt 0 ] || return 1

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Add idea_id to related_ideas if not already present (deduplicate)
    local tmp_file="${signals_file}.tmp"
    jq --arg sid "$signal_id" \
       --arg iid "$idea_id" \
       --arg now "$now" \
       '(.signals[] | select(.id == $sid)) |=
            (if (.related_ideas | index($iid)) then .
             else .related_ideas += [$iid]
             end)
        | .updated_at = $now' \
       "$signals_file" > "$tmp_file" && mv "$tmp_file" "$signals_file"

    log "SIGNAL" "Linked signal $signal_id -> idea $idea_id"
}

# Adds a signal ID to a garden idea's related_signals array (dedup-safe).
# This is one half of the bidirectional link between signals and garden ideas.
#
# Args: idea_id signal_id
# Returns: 0 on success, 1 if idea not found or garden disabled
_garden_link_signal() {
    if [ "${GARDEN_ENABLED:-true}" != "true" ]; then return 1; fi
    local idea_id="${1:?_garden_link_signal requires idea_id}"
    local signal_id="${2:?_garden_link_signal requires signal_id}"

    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"
    [ -f "$idea_file" ] || return 1

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Add signal_id to related_signals if not already present (deduplicate)
    local tmp_file="${idea_file}.tmp"
    jq --arg sid "$signal_id" \
       --arg now "$now" \
       'if (.related_signals | index($sid)) then .
        else .related_signals += [$sid] | .updated_at = $now
        end' \
       "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    log "GARDEN" "Linked idea $idea_id -> signal $signal_id"
}

# Creates a bidirectional link between a signal and a garden idea.
# Updates both the signal's related_ideas and the idea's related_signals.
#
# Args: signal_id idea_id
# Returns: 0 on success
_signal_garden_link() {
    local signal_id="${1:?_signal_garden_link requires signal_id}"
    local idea_id="${2:?_signal_garden_link requires idea_id}"

    _signal_link_idea "$signal_id" "$idea_id"
    _garden_link_signal "$idea_id" "$signal_id"
}
