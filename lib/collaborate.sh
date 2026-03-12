#!/usr/bin/env bash
# lib/collaborate.sh — spec-61: Collaboration Mode and Checkpoints
# Provides checkpoint() for pausing at phase transitions in collaborative mode,
# and run_deep_research() for standalone deep research (spec-63).

# ---------------------------------------------------------------------------
# checkpoint(name)
# ---------------------------------------------------------------------------
# Pauses execution at a phase transition point when collaboration mode is
# "collaborative" or "supervised" and stdin is a TTY.
#
# Args:
#   name — one of: after_research, after_plan, after_review
#
# Returns:
#   0 — execution continues if user chooses [c]ontinue; exits for [p]ause/[a]bort
checkpoint() {
    local name="$1"

    # Silent no-op in autonomous mode
    [[ "${COLLABORATION_MODE:-autonomous}" == "autonomous" ]] && return 0

    # Silent no-op when stdin is not a TTY (CI, piped, background)
    [[ ! -t 0 ]] && return 0

    local _checkpoint_dir="${AUTOMATON_DIR:-.automaton}/checkpoints"
    mkdir -p "$_checkpoint_dir"

    # Loop to allow re-display after [m]odify or [r]esearch
    while true; do
        local _summary
        _summary=$(generate_checkpoint_summary "$name")

        # Write checkpoint audit file
        local _timestamp
        _timestamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "unknown")
        local _audit_file="$_checkpoint_dir/checkpoint-${name}-${_timestamp}.md"
        printf '%s\n' "$_summary" > "$_audit_file"

        # Display summary to user
        printf '\n%s\n' "$_summary"

        # Build choices line based on checkpoint type
        local _choices_display="[c]ontinue  [m]odify  [p]ause  [a]bort"
        if [[ "$name" == "after_research" ]]; then
            _choices_display="[c]ontinue  [m]odify  [p]ause  [a]bort  [r]esearch"
        fi

        printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
        printf ' %s\n' "$_choices_display"
        printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
        printf 'Choice [c]: '

        local _choice
        read -r _choice
        _choice=$(echo "${_choice:-c}" | tr '[:upper:]' '[:lower:]')

        case "$_choice" in
            c|continue)
                # Clear checkpoint_paused_at if set
                local _state_file="${AUTOMATON_DIR:-.automaton}/state.json"
                if [ -f "$_state_file" ]; then
                    local _tmp
                    _tmp=$(mktemp) && \
                        jq 'del(.checkpoint_paused_at)' "$_state_file" > "$_tmp" && \
                        mv "$_tmp" "$_state_file" 2>/dev/null || true
                fi
                printf '\n**User choice:** continue\n**Timestamp:** %s\n' \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_audit_file"
                return 0
                ;;
            m|modify)
                printf '\n**User choice:** modify\n**Timestamp:** %s\n' \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_audit_file"
                handle_modify "$name"
                # Loop back to re-display updated summary
                continue
                ;;
            p|pause)
                printf '\n**User choice:** pause\n**Timestamp:** %s\n' \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_audit_file"
                handle_pause "$name"
                exit 0
                ;;
            a|abort)
                printf '\n**User choice:** abort\n**Timestamp:** %s\n' \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_audit_file"
                handle_abort "$name"
                exit 1
                ;;
            r|research)
                if [[ "$name" == "after_research" ]]; then
                    printf '\n**User choice:** research\n**Timestamp:** %s\n' \
                        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_audit_file"
                    printf '\nWhat topic would you like to research? '
                    local _research_topic
                    read -r _research_topic
                    if [ -n "$_research_topic" ]; then
                        run_deep_research "$_research_topic"
                    else
                        printf 'No topic provided. Returning to checkpoint.\n'
                    fi
                    # Loop back to re-display checkpoint
                    continue
                else
                    printf 'Invalid choice. Enter c, m, p, or a.\n'
                fi
                ;;
            *)
                printf 'Invalid choice. Enter c, m, p, or a.\n'
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# generate_checkpoint_summary(name)
# ---------------------------------------------------------------------------
# Produces a structured phase summary for display to the user.
generate_checkpoint_summary() {
    local name="$1"
    local _title _what_happened _whats_next
    local _plan_file="${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md"

    case "$name" in
        after_research)
            _title="Research → Plan"
            _what_happened=$(
                local _specs_count
                _specs_count=$(ls "${PROJECT_ROOT:-.}/specs"/spec-*.md 2>/dev/null | wc -l || echo 0)
                printf '- Analyzed %s spec file(s)\n' "$_specs_count"
                local _tbds_remaining
                _tbds_remaining=$(grep -ri '\bTBD\b' "${PROJECT_ROOT:-.}/specs/" 2>/dev/null | grep -v 'RESOLVED\|resolved' | wc -l || echo 0)
                if [ "${_tbds_remaining:-0}" -gt 0 ]; then
                    printf '- %s TBDs remain (may be non-blocking)\n' "$_tbds_remaining"
                else
                    printf '- No unresolved TBDs\n'
                fi
            )
            _whats_next="Plan phase will decompose specs into an ordered implementation task list."
            ;;
        after_plan)
            _title="Plan → Build"
            _what_happened=$(
                if [ -f "$_plan_file" ]; then
                    local _total _pending
                    _total=$(grep -c '\- \[' "$_plan_file" 2>/dev/null || echo 0)
                    _pending=$(grep -c '\- \[ \]' "$_plan_file" 2>/dev/null || echo 0)
                    printf '- %s implementation tasks created\n' "$_total"
                    printf '- %s tasks pending build\n' "$_pending"
                else
                    printf '- Implementation plan not yet available\n'
                fi
            )
            _whats_next="Build phase will implement each task in dependency order."
            ;;
        after_review)
            _title="Review → Complete"
            _what_happened=$(
                local _traceability="${AUTOMATON_DIR:-.automaton}/traceability.json"
                if [ -f "$_traceability" ]; then
                    local _passing _failing
                    _passing=$(jq '[.[] | select(.status == "pass")] | length' "$_traceability" 2>/dev/null || echo 0)
                    _failing=$(jq '[.[] | select(.status == "fail")] | length' "$_traceability" 2>/dev/null || echo 0)
                    printf '- Acceptance criteria: %s passing, %s failing\n' "$_passing" "$_failing"
                else
                    printf '- Review complete\n'
                fi
            )
            _whats_next="Marking run COMPLETE. All phases finished successfully."
            ;;
        *)
            _title="Checkpoint: $name"
            _what_happened="Phase completed."
            _whats_next="Continuing to next phase."
            ;;
    esac

    cat <<SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CHECKPOINT: ${_title}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## What Just Happened
${_what_happened}
## What's Next
${_whats_next}
SUMMARY
}

# ---------------------------------------------------------------------------
# handle_modify(checkpoint_name)
# ---------------------------------------------------------------------------
# Launches an interactive claude session with context files for the checkpoint.
handle_modify() {
    local name="$1"
    local -a _context_files=()

    case "$name" in
        after_research)
            while IFS= read -r _f; do
                _context_files+=("$_f")
            done < <(ls "${PROJECT_ROOT:-.}/specs"/spec-*.md 2>/dev/null || true)
            [ -f "${PROJECT_ROOT:-.}/AGENTS.md" ] && _context_files+=("${PROJECT_ROOT:-.}/AGENTS.md")
            ;;
        after_plan)
            [ -f "${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md" ] && _context_files+=("${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md")
            while IFS= read -r _f; do
                _context_files+=("$_f")
            done < <(ls "${PROJECT_ROOT:-.}/specs"/spec-*.md 2>/dev/null || true)
            [ -f "${PROJECT_ROOT:-.}/AGENTS.md" ] && _context_files+=("${PROJECT_ROOT:-.}/AGENTS.md")
            ;;
        after_review)
            [ -f "${AUTOMATON_DIR:-.automaton}/traceability.json" ] && \
                _context_files+=("${AUTOMATON_DIR:-.automaton}/traceability.json")
            local _review_report
            _review_report=$(ls -t "${AUTOMATON_DIR:-.automaton}"/agents/review-*.json 2>/dev/null | head -1 || true)
            [ -n "$_review_report" ] && _context_files+=("$_review_report")
            [ -f "${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md" ] && _context_files+=("${PROJECT_ROOT:-.}/IMPLEMENTATION_PLAN.md")
            ;;
    esac

    printf '\nLaunching interactive Claude session. Exit with /exit when done.\n'
    [ "${#_context_files[@]}" -gt 0 ] && printf 'Context files: %s\n\n' "${_context_files[*]}"

    local -a _claude_args=("claude")
    for _f in "${_context_files[@]}"; do
        [ -f "$_f" ] && _claude_args+=("--file" "$_f")
    done

    "${_claude_args[@]}" 2>/dev/null || true
    printf '\nInteractive session ended.\n'
}

# ---------------------------------------------------------------------------
# handle_pause(checkpoint_name)
# ---------------------------------------------------------------------------
# Writes checkpoint_paused_at to state.json and exits 0.
handle_pause() {
    local name="$1"
    local _state_file="${AUTOMATON_DIR:-.automaton}/state.json"

    if [ -f "$_state_file" ]; then
        local _tmp
        _tmp=$(mktemp) && \
            jq --arg cp "$name" '. + {checkpoint_paused_at: $cp}' "$_state_file" > "$_tmp" && \
            mv "$_tmp" "$_state_file" 2>/dev/null || true
    else
        mkdir -p "$(dirname "$_state_file")"
        printf '{"checkpoint_paused_at":"%s"}\n' "$name" > "$_state_file"
    fi

    printf '\nRun paused at checkpoint: %s\n' "$name"
    printf 'Resume with: ./automaton.sh --resume\n'
}

# ---------------------------------------------------------------------------
# handle_abort(checkpoint_name)
# ---------------------------------------------------------------------------
# Saves state and exits 1.
handle_abort() {
    local name="$1"
    printf '\nRun aborted at checkpoint: %s\n' "$name"
    printf 'Work done so far has been preserved.\n'
    write_state 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# run_deep_research(topic)
# ---------------------------------------------------------------------------
# Runs standalone deep research on the given topic (spec-63).
# Writes output to .automaton/research/RESEARCH-{sanitized-topic}-{timestamp}.md
run_deep_research() {
    local topic="$1"

    if [ -z "$topic" ]; then
        echo "Error: run_deep_research requires a topic string" >&2
        return 1
    fi

    # Sanitize topic for filename: lowercase, spaces to hyphens, strip non-alphanumeric, truncate
    local _sanitized
    _sanitized=$(printf '%s' "$topic" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9-]//g' | cut -c1-50)

    local _timestamp
    _timestamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "unknown")

    local _output_dir="${AUTOMATON_DIR:-.automaton}/research"
    local _output_file="$_output_dir/RESEARCH-${_sanitized}-${_timestamp}.md"

    mkdir -p "$_output_dir"

    local _deep_research_budget="${DEEP_RESEARCH_BUDGET:-200000}"
    local _deep_research_model="${DEEP_RESEARCH_MODEL:-sonnet}"

    # Locate prompt file relative to automaton install dir
    local _install_dir
    _install_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local _prompt_file="${_install_dir}/PROMPT_deep_research.md"

    if [ ! -f "$_prompt_file" ]; then
        echo "Error: PROMPT_deep_research.md not found at $_prompt_file" >&2
        return 1
    fi

    printf '\nRunning deep research on: %s\n' "$topic"
    printf 'Output will be written to: %s\n' "$_output_file"
    printf 'Budget: %s tokens | Model: %s\n\n' "$_deep_research_budget" "$_deep_research_model"

    # Build augmented prompt with dynamic context
    local _augmented_prompt
    _augmented_prompt=$(mktemp --suffix=.md) || {
        echo "Error: Could not create temp file" >&2
        return 1
    }

    local _project_context="standalone research (no PRD)"
    [ -f "${PROJECT_ROOT:-.}/PRD.md" ] && _project_context="project PRD available"

    if grep -q '<dynamic_context>' "$_prompt_file"; then
        {
            sed -n '1,/<dynamic_context>/p' "$_prompt_file"
            printf '\n## Research Topic\n%s\n\n' "$topic"
            printf '## Project Context\n%s\n\n' "$_project_context"
            printf '## Budget\nToken limit: %s\n' "$_deep_research_budget"
            sed -n '/<\/dynamic_context>/,$p' "$_prompt_file"
        } > "$_augmented_prompt"
    else
        cp "$_prompt_file" "$_augmented_prompt"
        printf '\n## Research Topic\n%s\n\n## Project Context\n%s\n\n## Budget\nToken limit: %s\n' \
            "$topic" "$_project_context" "$_deep_research_budget" >> "$_augmented_prompt"
    fi

    local _cmd_args=("--print" "--model" "$_deep_research_model" "--output-format" "text")
    [ "${FLAG_DANGEROUSLY_SKIP_PERMISSIONS:-true}" = "true" ] && _cmd_args+=("--dangerously-skip-permissions")

    local _result _exit_code=0
    _result=$(claude "${_cmd_args[@]}" --file "$_augmented_prompt" 2>&1) || _exit_code=$?

    rm -f "$_augmented_prompt"

    # Write output file (preserving partial results on failure)
    {
        printf '# Deep Research: %s\n\n' "$topic"
        printf '**Generated:** %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '**Project context:** %s\n' "$_project_context"
        printf '**Budget used:** up to %s tokens\n\n' "$_deep_research_budget"
        if [ "$_exit_code" -ne 0 ]; then
            printf '> **Note:** Research truncated: budget limit reached or interrupted. Partial results below.\n\n'
        fi
        printf '%s\n' "$_result"
    } > "$_output_file"

    printf 'Deep research complete. Report saved to:\n  %s\n' "$_output_file"
    return 0
}
