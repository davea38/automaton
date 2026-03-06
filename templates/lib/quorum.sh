#!/usr/bin/env bash
# lib/quorum.sh — Quorum voting system: vote parsing, tallying, cooldowns, and bloom evaluation.
# Spec references: spec-41 (quorum governance), spec-44 (quorum CLI)

_quorum_parse_vote() {
    local raw_output="$1"
    local voter_name="${2:-unknown}"

    # Try to extract JSON from the raw output — the voter may emit
    # explanation text before/after the JSON object.
    local json_candidate
    json_candidate=$(echo "$raw_output" | sed -n '/{/,/}/p' | head -50)

    # Validate it's parseable JSON with required fields
    if [ -n "$json_candidate" ] && echo "$json_candidate" | jq -e '.vote' >/dev/null 2>&1; then
        local vote confidence reasoning risk_assessment conditions
        vote=$(echo "$json_candidate" | jq -r '.vote // "abstain"')
        confidence=$(echo "$json_candidate" | jq -r '.confidence // 0.5')
        reasoning=$(echo "$json_candidate" | jq -r '.reasoning // "No reasoning provided"')
        risk_assessment=$(echo "$json_candidate" | jq -r '.risk_assessment // "medium"')
        conditions=$(echo "$json_candidate" | jq -c '.conditions // []')

        # Validate vote value
        case "$vote" in
            approve|reject|abstain) ;;
            *) vote="abstain"; reasoning="Invalid vote value: $vote" ;;
        esac

        jq -n \
            --arg vote "$vote" \
            --arg confidence "$confidence" \
            --arg reasoning "$reasoning" \
            --arg risk "$risk_assessment" \
            --argjson conditions "$conditions" \
            '{
                vote: $vote,
                confidence: ($confidence | tonumber),
                reasoning: $reasoning,
                conditions: $conditions,
                risk_assessment: $risk
            }'
    else
        # Invalid output — return abstain (spec-39 §4)
        log "QUORUM" "WARN: voter=$voter_name produced invalid output, recording as abstain"
        jq -n \
            --arg voter "$voter_name" \
            '{
                vote: "abstain",
                confidence: 0.0,
                reasoning: "Vote parsing failed",
                conditions: [],
                risk_assessment: "medium"
            }'
    fi
}

# Invoke a single voter agent with a proposal and return the parsed vote.
# Uses the Claude CLI with the voter's agent definition file, Sonnet model,
# --print for text output, and --max-tokens limit. The voter is read-only
# (no tools) and produces a JSON vote.
#
# Args: voter_name proposal_json
# Outputs: parsed JSON vote object to stdout
# Returns: 0 on success (even if vote is abstain due to parse failure)
_quorum_invoke_voter() {
    local voter_name="${1:?_quorum_invoke_voter requires voter_name}"
    local proposal_json="${2:?_quorum_invoke_voter requires proposal_json}"

    local agent_file=".claude/agents/voter-${voter_name}.md"
    local model="${QUORUM_MODEL:-sonnet}"
    local max_tokens="${QUORUM_MAX_TOKENS_PER_VOTER:-500}"

    if [ ! -f "$agent_file" ]; then
        log "QUORUM" "ERROR: voter agent file not found: $agent_file"
        _quorum_parse_vote "" "$voter_name"
        return 0
    fi

    log "QUORUM" "Invoking voter: name=$voter_name model=$model max-tokens=$max_tokens"

    local raw_output=""
    local exit_code=0

    # Invoke claude CLI with:
    #   --agent: voter agent definition (contains perspective + output format)
    #   --model: cost-efficient model (default sonnet)
    #   --max-tokens: limit output length
    #   --print: simple text output (not stream-json)
    #   Proposal is piped via stdin
    local prompt
    printf -v prompt 'Evaluate this proposal:\n\n%s' "$proposal_json"
    raw_output=$(printf '%s' "$prompt" | claude --agent "$agent_file" \
        --model "$model" \
        --max-tokens "$max_tokens" \
        --print 2>&1) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        log "QUORUM" "WARN: voter=$voter_name exited with code $exit_code"
    fi

    log "QUORUM" "Voter $voter_name responded (${#raw_output} bytes)"

    # Parse and validate the vote output — expects JSON with "vote" field.
    # Invalid output is treated as abstain (spec-39 §4).
    local parsed_vote
    parsed_vote=$(_quorum_parse_vote "$raw_output" "$voter_name")
    echo "$parsed_vote"
}

# Tally votes from all voters and determine the quorum result.
# Counts approve/reject/abstain, reduces denominator for abstentions,
# compares approve count against threshold for the decision_type,
# and merges conditions from approving voters into the result.
#
# Args: votes_json decision_type
#   votes_json: JSON object mapping voter names to vote objects
#               e.g. {"conservative":{"vote":"approve","conditions":[...]}, ...}
#   decision_type: one of seed_promotion, bloom_implementation,
#                  constitutional_amendment, emergency_override
# Outputs: JSON tally result to stdout with approve, reject, abstain counts,
#          threshold, result (approved/rejected), and conditions_merged
_quorum_tally() {
    local votes_json="${1:?_quorum_tally requires votes_json}"
    local decision_type="${2:?_quorum_tally requires decision_type}"

    # Count votes by category
    local approve_count reject_count abstain_count total
    approve_count=$(echo "$votes_json" | jq '[.[] | select(.vote == "approve")] | length')
    reject_count=$(echo "$votes_json" | jq '[.[] | select(.vote == "reject")] | length')
    abstain_count=$(echo "$votes_json" | jq '[.[] | select(.vote == "abstain")] | length')
    total=$(echo "$votes_json" | jq 'length')

    # Reduce denominator for abstentions (spec-39 §3)
    local denominator=$(( total - abstain_count ))

    # Look up threshold for the decision type from config
    local threshold
    threshold=$(jq -r ".quorum.thresholds.${decision_type} // 3" "$CONFIG_FILE" 2>/dev/null || echo "3")

    # Determine result: approved if approve_count >= threshold,
    # but also handle edge case where denominator is 0 (all abstain)
    local result
    if [ "$denominator" -le 0 ]; then
        # All voters abstained — cannot reach any threshold
        result="rejected"
        log "QUORUM" "WARN: all voters abstained, decision_type=$decision_type — rejecting"
    elif [ "$approve_count" -ge "$threshold" ]; then
        result="approved"
    else
        result="rejected"
    fi

    # Merge conditions from all approving voters into a flat array
    local conditions_merged
    conditions_merged=$(echo "$votes_json" | jq '[.[] | select(.vote == "approve") | .conditions[]? // empty] | unique')

    log "QUORUM" "Tally: approve=$approve_count reject=$reject_count abstain=$abstain_count denominator=$denominator threshold=$threshold result=$result"

    # Return structured tally result
    jq -n \
        --argjson approve "$approve_count" \
        --argjson reject "$reject_count" \
        --argjson abstain "$abstain_count" \
        --argjson threshold "$threshold" \
        --arg result "$result" \
        --argjson conditions_merged "$conditions_merged" \
        '{
            approve: $approve,
            reject: $reject,
            abstain: $abstain,
            threshold: $threshold,
            result: $result,
            conditions_merged: $conditions_merged
        }'
}

# Check whether a bloom candidate idea is on rejection cooldown.
# Scans vote history in .automaton/votes/ for rejected votes matching the idea_id.
# If a rejection is found and fewer than rejection_cooldown_cycles votes have been
# recorded since then, the idea is considered on cooldown and should be skipped.
#
# Args:
#   $1 — idea_id: the garden idea ID to check
# Returns: 0 if idea is not on cooldown (can be evaluated), 1 if on cooldown (skip)
_quorum_check_cooldown() {
    local idea_id="${1:?_quorum_check_cooldown requires idea_id}"
    local cooldown_cycles="${QUORUM_REJECTION_COOLDOWN:-5}"
    local votes_dir="$AUTOMATON_DIR/votes"

    if [ ! -d "$votes_dir" ]; then
        return 0
    fi

    # Find the most recent rejection vote for this idea
    local rejection_vote_id=""
    local vote_files
    vote_files=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | sort -r)

    for vote_file in $vote_files; do
        local matched_idea matched_result
        matched_idea=$(jq -r '.idea_id // empty' "$vote_file" 2>/dev/null) || continue
        matched_result=$(jq -r '.tally.result // empty' "$vote_file" 2>/dev/null) || continue

        if [ "$matched_idea" = "$idea_id" ] && [ "$matched_result" = "rejected" ]; then
            rejection_vote_id=$(jq -r '.vote_id // empty' "$vote_file" 2>/dev/null) || true
            break
        fi
    done

    if [ -z "$rejection_vote_id" ]; then
        return 0
    fi

    # Count how many votes have been recorded after the rejection vote
    # Each vote roughly corresponds to one evaluation cycle
    local votes_since=0
    local past_rejection=false
    local all_vote_files
    all_vote_files=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | sort)

    for vote_file in $all_vote_files; do
        local vid
        vid=$(jq -r '.vote_id // empty' "$vote_file" 2>/dev/null) || continue
        if [ "$past_rejection" = "true" ]; then
            votes_since=$(( votes_since + 1 ))
        elif [ "$vid" = "$rejection_vote_id" ]; then
            past_rejection=true
        fi
    done

    if [ "$votes_since" -lt "$cooldown_cycles" ]; then
        log "QUORUM" "Idea $idea_id on cooldown: $votes_since cycles since rejection ($rejection_vote_id), need $cooldown_cycles"
        return 1
    fi

    return 0
}

# Check whether the quorum budget for the current cycle has been exceeded.
# Tracks cumulative quorum token usage and compares estimated cost against
# QUORUM_MAX_COST_PER_CYCLE. Uses a simple token-to-cost estimate based on
# Sonnet pricing (~$3/M input + $15/M output tokens, approximated as $0.01/1K tokens).
#
# Args:
#   $1 — tokens_used: cumulative tokens consumed by quorum voters this cycle
# Returns: 0 if budget remains, 1 if budget exceeded
_quorum_check_budget() {
    local tokens_used="${1:?_quorum_check_budget requires tokens_used}"
    local max_cost="${QUORUM_MAX_COST_PER_CYCLE:-1.00}"

    # Estimate cost: ~$0.01 per 1000 tokens (conservative Sonnet estimate)
    local estimated_cost
    estimated_cost=$(echo "$tokens_used $max_cost" | awk '{
        cost = $1 / 1000 * 0.01
        printf "%.4f", cost
    }')

    local exceeded
    exceeded=$(echo "$estimated_cost $max_cost" | awk '{print ($1 >= $2) ? "true" : "false"}')

    if [ "$exceeded" = "true" ]; then
        log "QUORUM" "Budget exceeded: ~\$${estimated_cost} used of \$${max_cost} max — skipping remaining candidates"
        return 1
    fi

    return 0
}

# Evaluate the highest-priority bloom candidate through the quorum.
# Selects the top bloom candidate from the garden, assembles proposal context
# (idea details, metrics, signals), invokes all configured voters sequentially,
# tallies votes, writes a vote record to .automaton/votes/vote-{NNN}.json,
# and advances (harvest) or wilts the idea based on the result.
#
# Args: none (reads bloom candidates from garden, voters from config)
# Returns: 0 on success (even if no candidates), 1 on error
# Outputs: vote record path to stdout if a vote was held
_quorum_evaluate_bloom() {
    if [ "${QUORUM_ENABLED:-true}" != "true" ]; then
        log "EVOLUTION" "Quorum disabled — bloom ideas auto-approved without voting"
        # Auto-approve all bloom candidates without voting (spec-39 §10)
        local disabled_candidates
        disabled_candidates=$(_garden_get_bloom_candidates 2>/dev/null) || true
        if [ -n "$disabled_candidates" ]; then
            while IFS= read -r auto_id; do
                [ -n "$auto_id" ] || continue
                log "QUORUM" "Auto-approving $auto_id (quorum disabled)"
                _garden_advance_stage "$auto_id" "harvest" "Auto-approved (quorum disabled)" "true"
            done <<< "$disabled_candidates"
        fi
        return 0
    fi

    # Get bloom candidates sorted by priority descending
    local candidates
    candidates=$(_garden_get_bloom_candidates 2>/dev/null) || true
    if [ -z "$candidates" ]; then
        log "QUORUM" "No bloom candidates to evaluate"
        return 0
    fi

    # Select highest-priority candidate (first line)
    local idea_id
    idea_id=$(echo "$candidates" | head -1)
    local idea_file="$AUTOMATON_DIR/garden/${idea_id}.json"

    if [ ! -f "$idea_file" ]; then
        log "QUORUM" "ERROR: idea file not found: $idea_file"
        return 1
    fi

    # Check rejection cooldown — skip ideas recently rejected by quorum
    if ! _quorum_check_cooldown "$idea_id"; then
        return 0
    fi

    # Check if quorum budget for this cycle has been exceeded
    if ! _quorum_check_budget "${_QUORUM_CYCLE_TOKENS:-0}"; then
        log "QUORUM" "Skipping bloom candidate $idea_id — quorum budget exceeded"
        return 0
    fi

    log "QUORUM" "Evaluating bloom candidate: $idea_id"

    # Assemble proposal context from idea details
    local proposal_json
    proposal_json=$(jq '{
        title: .title,
        description: .description,
        evidence_count: (.evidence | length),
        priority: (.priority // 0),
        complexity: (.estimated_complexity // "medium"),
        tags: (.tags // []),
        related_specs: (.related_specs // []),
        related_signals: (.related_signals // []),
        evidence: [.evidence[] | {type, observation, added_at}]
    }' "$idea_file")

    # Invoke all voters sequentially (spec-39: not parallel, to control costs)
    local all_votes="{}"
    local voter_list
    IFS=',' read -ra voter_list <<< "$QUORUM_VOTERS"

    local voter_tokens=0
    for voter_name in "${voter_list[@]}"; do
        voter_name=$(echo "$voter_name" | tr -d ' ')
        log "QUORUM" "Invoking voter: $voter_name for $idea_id"
        local vote_result
        vote_result=$(_quorum_invoke_voter "$voter_name" "$proposal_json")
        all_votes=$(echo "$all_votes" | jq --arg name "$voter_name" --argjson vote "$vote_result" '. + {($name): $vote}')
        # Estimate tokens per voter (input prompt + output tokens)
        voter_tokens=$(( voter_tokens + ${QUORUM_MAX_TOKENS_PER_VOTER:-500} ))
    done

    # Accumulate cycle-level quorum token usage
    _QUORUM_CYCLE_TOKENS=$(( ${_QUORUM_CYCLE_TOKENS:-0} + voter_tokens ))

    # Tally the votes using bloom_implementation threshold
    local tally_result
    tally_result=$(_quorum_tally "$all_votes" "bloom_implementation")

    local result
    result=$(echo "$tally_result" | jq -r '.result')

    # Determine next vote ID from existing vote files
    local votes_dir="$AUTOMATON_DIR/votes"
    mkdir -p "$votes_dir"
    local next_vote_id=1
    local latest_vote
    latest_vote=$(find "$votes_dir" -name 'vote-*.json' -type f 2>/dev/null | sort | tail -1)
    if [ -n "$latest_vote" ]; then
        next_vote_id=$(basename "$latest_vote" .json | sed 's/vote-//' | sed 's/^0*//' )
        next_vote_id=$(( next_vote_id + 1 ))
    fi
    local vote_id
    vote_id=$(printf "vote-%03d" "$next_vote_id")
    local vote_file="$votes_dir/${vote_id}.json"

    # Build the vote record
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg vote_id "$vote_id" \
        --arg idea_id "$idea_id" \
        --arg type "bloom_implementation" \
        --argjson proposal "$proposal_json" \
        --argjson votes "$all_votes" \
        --argjson tally "$tally_result" \
        --arg created_at "$now" \
        '{
            vote_id: $vote_id,
            idea_id: $idea_id,
            type: $type,
            proposal: $proposal,
            votes: $votes,
            tally: $tally,
            created_at: $created_at
        }' > "$vote_file"

    log "QUORUM" "Vote recorded: $vote_id result=$result for $idea_id"

    # Update idea with vote reference
    local tmp_file="${idea_file}.tmp"
    jq --arg vid "$vote_id" '.vote_id = $vid' "$idea_file" > "$tmp_file" && mv "$tmp_file" "$idea_file"

    # Act on the result
    if [ "$result" = "approved" ]; then
        log "QUORUM" "APPROVED: $idea_id — advancing to harvest"
        _garden_advance_stage "$idea_id" "harvest" "Quorum approved ($vote_id)" "true"
    else
        log "QUORUM" "REJECTED: $idea_id — wilting"
        _garden_wilt "$idea_id" "Quorum rejected ($vote_id)"
    fi

    echo "$vote_file"
    return 0
}
