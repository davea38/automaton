#!/usr/bin/env bash
# lib/utilities.sh — Agent execution, guardrails, debt tracking, and phase helper utilities.
# Spec references: spec-14 (agent execution), spec-30 (dynamic context),
#                  spec-36 (guardrails), spec-55 (status line)

# Atomically writes content to a file using write-to-temp + rename.
# This prevents readers from seeing partial writes. Uses the target's
# directory for the temp file so mv is a same-filesystem rename (atomic).
# Usage: atomic_write <target_file> < content   OR
#        echo "data" | atomic_write <target_file>
atomic_write() {
    local target="$1"
    local dir
    dir=$(dirname "$target")
    mkdir -p "$dir"
    local tmp
    tmp=$(mktemp "$dir/.tmp.XXXXXX") || { echo "atomic_write: mktemp failed for $target" >&2; return 1; }
    if cat > "$tmp"; then
        mv -f "$tmp" "$target"
    else
        rm -f "$tmp"
        echo "atomic_write: write failed for $target" >&2
        return 1
    fi
}

_prompt_to_agent_name() {
    local prompt_file="$1"
    local basename
    basename=$(basename "$prompt_file")

    case "$basename" in
        PROMPT_research.md)       echo "automaton-research" ;;
        PROMPT_plan.md)           echo "automaton-planner" ;;
        PROMPT_build.md)          echo "automaton-builder" ;;
        PROMPT_review.md)         echo "automaton-reviewer" ;;
        PROMPT_self_research.md)  echo "automaton-self-researcher" ;;
        PROMPT_self_plan.md)      echo "automaton-self-planner" ;;
        *)                        echo "" ;;
    esac
}

# Extracts only the dynamic context portion for native agent invocation.
# Unlike inject_dynamic_context() which augments the full prompt file,
# this returns just the dynamic content that gets piped to `claude --agent`
# since the static prompt is already in the agent definition file.
_build_dynamic_context_stdin() {
    local prompt_file="$1"
    local dynamic_content=""

    # Bootstrap manifest (spec-37): pre-assembled context from init.sh
    # When bootstrap fails, _format_bootstrap_for_context emits a fallback
    # notice telling the agent to read files manually.
    if [ -n "${BOOTSTRAP_MANIFEST:-}" ] || [ "${BOOTSTRAP_FAILED:-false}" = "true" ]; then
        dynamic_content+=$(_format_bootstrap_for_context "${BOOTSTRAP_MANIFEST:-}")$'\n'
    fi

    dynamic_content+="## Current State"$'\n'
    dynamic_content+=""$'\n'
    dynamic_content+="- Phase: $current_phase"$'\n'
    dynamic_content+="- Iteration: $phase_iteration"$'\n'

    # Build sub-phase context (spec-36)
    if [ "$current_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
        if [ "${build_sub_phase:-implementation}" = "scaffold" ]; then
            dynamic_content+="- Build sub-phase: TEST SCAFFOLD (3a) — iteration $((scaffold_iterations_done + 1))/$EXEC_TEST_SCAFFOLD_ITERATIONS"$'\n'
            dynamic_content+=""$'\n'
            dynamic_content+="**TEST SCAFFOLD MODE**: Write test files ONLY for plan tasks with \`<!-- test: path -->\` annotations. Do NOT implement any features. Tests should fail initially (no implementation exists yet). Commit test files when done."$'\n'
            dynamic_content+="- Test framework: $EXEC_TEST_FRAMEWORK"$'\n'
        else
            dynamic_content+="- Build sub-phase: IMPLEMENTATION (3b)"$'\n'
        fi
    fi

    if [ -f "$AUTOMATON_DIR/budget.json" ]; then
        local remaining
        remaining=$(jq '.tokens_remaining // "unknown"' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "unknown")
        dynamic_content+="- Budget remaining: $remaining tokens"$'\n'
    fi
    dynamic_content+=""$'\n'

    if [ -f "$AUTOMATON_DIR/context_summary.md" ]; then
        dynamic_content+=$(cat "$AUTOMATON_DIR/context_summary.md")$'\n'
        dynamic_content+=""$'\n'
    fi

    if [ "$current_phase" = "build" ] && [ "$phase_iteration" -gt 1 ]; then
        local plan_file="IMPLEMENTATION_PLAN.md"
        if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
            plan_file="$AUTOMATON_DIR/backlog.md"
        fi

        dynamic_content+="## Recent Changes"$'\n'
        dynamic_content+='```'$'\n'
        dynamic_content+=$(git diff --stat HEAD~3 2>/dev/null || echo "No recent changes.")$'\n'
        dynamic_content+='```'$'\n'
        dynamic_content+=""$'\n'

        dynamic_content+="## Current Focus"$'\n'
        if [ -f "$plan_file" ]; then
            dynamic_content+=$(grep '\[ \]' "$plan_file" | head -5 || echo "All tasks complete.")$'\n'
        fi
        dynamic_content+=""$'\n'

        if [ -f "$AUTOMATON_DIR/iteration_memory.md" ]; then
            dynamic_content+="## Recent Iteration History"$'\n'
            dynamic_content+=$(tail -5 "$AUTOMATON_DIR/iteration_memory.md")$'\n'
            dynamic_content+=""$'\n'
        fi

    fi

    # Review-specific context: inject QA failure report when available (spec-46.4)
    if [ "$current_phase" = "review" ] && [ -f "$AUTOMATON_DIR/qa/failure-report.md" ]; then
        dynamic_content+="## QA Failure Report"$'\n'
        dynamic_content+=""$'\n'
        dynamic_content+="The QA loop exhausted its iterations with unresolved failures. Review the report below:"$'\n'
        dynamic_content+=""$'\n'
        dynamic_content+=$(cat "$AUTOMATON_DIR/qa/failure-report.md")$'\n'
        dynamic_content+=""$'\n'
    fi

    echo "$dynamic_content"
}

# ---------------------------------------------------------------------------
# Output Truncation (spec-49)
# ---------------------------------------------------------------------------
# Applies head+tail truncation to long output, preserving both the start
# context and error messages at the end. Archives full output for debugging.
#
# Usage: truncate_output <input_file> [phase] [iteration]
#   Prints truncated (or unmodified) output to stdout.
#   When output exceeds OUTPUT_MAX_LINES, archives the full file to
#   .automaton/logs/ before truncating.
truncate_output() {
    local input_file="$1"
    local phase="${2:-}"
    local iteration="${3:-}"

    local total_lines
    total_lines=$(wc -l < "$input_file" 2>/dev/null || echo 0)
    total_lines=$((total_lines + 0))  # ensure numeric

    # Below or at threshold: pass through unmodified, no archive
    if [ "$total_lines" -le "$OUTPUT_MAX_LINES" ]; then
        cat "$input_file"
        return 0
    fi

    # Archive full output before truncating
    local logs_dir="${AUTOMATON_DIR}/logs"
    mkdir -p "$logs_dir"
    local archive_name="output_${phase}_${iteration}_$(date +%s).log"
    cp "$input_file" "$logs_dir/$archive_name"

    # Head + tail with truncation marker
    local truncated_count=$((total_lines - OUTPUT_HEAD_LINES - OUTPUT_TAIL_LINES))
    head -n "$OUTPUT_HEAD_LINES" "$input_file"
    echo "... [$truncated_count lines truncated] ..."
    tail -n "$OUTPUT_TAIL_LINES" "$input_file"
}

_classify_debt_type() {
    local text="$1"
    local lower
    lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    if echo "$lower" | grep -qE 'error|catch|exception|fail|retry'; then
        echo "error_handling"
    elif echo "$lower" | grep -qE 'hardcode|magic|config|constant|literal'; then
        echo "hardcoded"
    elif echo "$lower" | grep -qE 'slow|o\(n|performance|optimize|cache'; then
        echo "performance"
    elif echo "$lower" | grep -qE 'test|coverage|assert|spec|verify'; then
        echo "test_coverage"
    else
        echo "cleanup"
    fi
}

# Scans files changed since $1 (commit SHA) for debt markers.
# Appends findings as JSONL to .automaton/debt-ledger.jsonl.
# Reads globals: DEBT_TRACKING_ENABLED, DEBT_TRACKING_MARKERS, phase_iteration, AUTOMATON_DIR
_scan_technical_debt() {
    [ "${DEBT_TRACKING_ENABLED:-false}" = "true" ] || return 0
    local start_sha="${1:-HEAD~1}"
    local ledger="$AUTOMATON_DIR/debt-ledger.jsonl"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Get files changed since start_sha
    local changed_files
    changed_files=$(git diff --name-only "$start_sha" HEAD 2>/dev/null) || return 0
    [ -n "$changed_files" ] || return 0

    # Build grep pattern from markers
    local pattern=""
    for marker in $DEBT_TRACKING_MARKERS; do
        [ -n "$pattern" ] && pattern="$pattern|"
        pattern="${pattern}${marker}"
    done

    while IFS= read -r file; do
        [ -f "$file" ] || continue
        # Grep for debt markers with line numbers
        grep -n -E "($pattern)" "$file" 2>/dev/null | while IFS=: read -r lineno line_text; do
            # Determine which marker matched
            local matched_marker="UNKNOWN"
            for m in $DEBT_TRACKING_MARKERS; do
                if echo "$line_text" | grep -q "$m"; then
                    matched_marker="$m"
                    break
                fi
            done
            local debt_type
            debt_type=$(_classify_debt_type "$line_text")
            # Append JSONL entry
            jq -nc \
                --arg type "$debt_type" \
                --arg file "$file" \
                --argjson line "$lineno" \
                --arg marker "$matched_marker" \
                --arg marker_text "$line_text" \
                --argjson iteration "${phase_iteration:-0}" \
                --arg timestamp "$ts" \
                '{type:$type,file:$file,line:$line,marker:$marker,marker_text:$marker_text,iteration:$iteration,timestamp:$timestamp}' \
                >> "$ledger"
        done
    done <<< "$changed_files"
}

# Generates .automaton/debt-summary.md from the debt ledger.
# Reads globals: DEBT_TRACKING_ENABLED, DEBT_TRACKING_THRESHOLD, AUTOMATON_DIR
_generate_debt_summary() {
    [ "${DEBT_TRACKING_ENABLED:-false}" = "true" ] || return 0
    local ledger="$AUTOMATON_DIR/debt-ledger.jsonl"
    local summary="$AUTOMATON_DIR/debt-summary.md"
    [ -f "$ledger" ] || return 0

    local total
    total=$(wc -l < "$ledger")
    [ "$total" -gt 0 ] 2>/dev/null || return 0

    local run_ts
    run_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    {
        echo "# Technical Debt Summary"
        echo "Run: $run_ts | Total: $total items"
        echo ""
        echo "## By Type"
        echo "| Type | Count |"
        echo "|------|-------|"
        jq -rs 'group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count)[] | "| \(.type) | \(.count) |"' "$ledger"
        echo ""
        echo "## Top Files"
        echo "| File | Items |"
        echo "|------|-------|"
        jq -rs 'group_by(.file) | map({file: .[0].file, count: length}) | sort_by(-.count)[:10][] | "| \(.file) | \(.count) |"' "$ledger"
    } > "$summary"

    # Emit threshold warning
    if [ "${DEBT_TRACKING_THRESHOLD:-0}" -gt 0 ] && [ "$total" -gt "${DEBT_TRACKING_THRESHOLD:-20}" ]; then
        log "ORCHESTRATOR" "WARNING: Technical debt ($total items) exceeds threshold (${DEBT_TRACKING_THRESHOLD}). Review $summary"
    fi

    # Return summary line for run output
    local type_breakdown
    type_breakdown=$(jq -rs 'group_by(.type) | map("\(.[0].type):\(length)") | join(" ")' "$ledger")
    echo "Technical debt: $total items ($type_breakdown)"
}

# === Design Principles Guard Rails (spec-58) ===
# Zero-API-call checks that enforce the 7 design principles from DESIGN_PRINCIPLES.md.
# Each check returns 0 on pass, 1 on violation, and appends to GUARDRAIL_VIOLATIONS array.

guardrail_check_size() {
    local target="${PROJECT_ROOT:-.}/automaton.sh"
    [ -f "$target" ] || return 0
    local ceiling="${GUARDRAILS_SIZE_CEILING:-18000}"
    local lines
    lines=$(wc -l < "$target")
    # Include lib/ modules in the total line count
    local lib_dir
    lib_dir="$(dirname "$target")/lib"
    if [ -d "$lib_dir" ]; then
        local lib_lines
        lib_lines=$(cat "$lib_dir"/*.sh 2>/dev/null | wc -l)
        lines=$((lines + lib_lines))
    fi
    if [ "$lines" -ge "$ceiling" ]; then
        local delta=$((lines - ceiling))
        GUARDRAIL_VIOLATIONS+=("Size Ceiling: automaton.sh + lib/ is $lines lines ($delta over the $ceiling limit)")
        return 1
    fi
    return 0
}

guardrail_check_dependencies() {
    local found=0
    local matches
    matches=$(grep -rnE '(apt-get|npm install|pip3? install|brew install|cargo install|gem install|go get|curl\s.*\|\s*sh|wget\s.*\|\s*sh)' ./*.sh ./**/*.sh 2>/dev/null || true)
    if [ -n "$matches" ]; then
        while IFS= read -r line; do
            GUARDRAIL_VIOLATIONS+=("External Dependency: $line")
            found=1
        done <<< "$matches"
    fi
    return $found
}

guardrail_check_silent_errors() {
    local found=0
    # Check for 2>/dev/null without || fallback on the same line
    local silent
    silent=$(grep -rnE '2>/dev/null' ./*.sh 2>/dev/null | grep -vE '\|\||# ' || true)
    if [ -n "$silent" ]; then
        while IFS= read -r line; do
            GUARDRAIL_VIOLATIONS+=("Silent Error: $line")
            found=1
        done <<< "$silent"
    fi
    # Check for set +e without restoration within 20 lines
    local files
    files=$(grep -rlE 'set \+e' ./*.sh 2>/dev/null || true)
    for f in $files; do
        [ -n "$f" ] || continue
        grep -n 'set +e' "$f" 2>/dev/null | while IFS=: read -r lineno _rest; do
            local end=$((lineno + 20))
            if ! sed -n "$((lineno+1)),${end}p" "$f" 2>/dev/null | grep -q 'set -e'; then
                GUARDRAIL_VIOLATIONS+=("Unrestored set +e: $f:$lineno")
                found=1
            fi
        done
    done
    return $found
}

guardrail_check_state_location() {
    local found=0
    # Find file writes (redirects) to absolute or home-relative paths outside .automaton/
    local writes
    writes=$(grep -rnE '>>?\s*(\/[^d]|~\/)' ./*.sh 2>/dev/null | grep -vE '\.automaton|\$AUTOMATON_DIR|/dev/' || true)
    if [ -n "$writes" ]; then
        while IFS= read -r line; do
            GUARDRAIL_VIOLATIONS+=("State Outside .automaton/: $line")
            found=1
        done <<< "$writes"
    fi
    return $found
}

guardrail_check_tui_deps() {
    local found=0
    local matches
    matches=$(grep -rnE '(curses|tput cup|dialog|whiptail|electron|react|textual)' ./*.sh ./**/*.sh 2>/dev/null || true)
    if [ -n "$matches" ]; then
        while IFS= read -r line; do
            GUARDRAIL_VIOLATIONS+=("TUI/GUI Dependency: $line")
            found=1
        done <<< "$matches"
    fi
    return $found
}

guardrail_check_prompt_logic() {
    local found=0
    # Look for control-flow keywords inside heredoc blocks (between <<EOF/<<'EOF' and EOF)
    local files
    files=$(grep -rlE '<<.*EOF' ./*.sh 2>/dev/null || true)
    for f in $files; do
        [ -n "$f" ] || continue
        # Extract heredoc contents and check for control-flow patterns
        local in_heredoc=0
        local lineno=0
        while IFS= read -r line; do
            lineno=$((lineno + 1))
            if echo "$line" | grep -qE '<<-?\s*'\''?EOF'; then
                in_heredoc=1
                continue
            fi
            if [ "$in_heredoc" -eq 1 ]; then
                if echo "$line" | grep -qE '^EOF$'; then
                    in_heredoc=0
                    continue
                fi
                if echo "$line" | grep -qE '\bif\b.*\bthen\b|\bfor\b.*\bdo\b|\bwhile\b.*\bdo\b'; then
                    GUARDRAIL_VIOLATIONS+=("Prompt Logic: $f:$lineno: $line")
                    found=1
                fi
            fi
        done < "$f"
    done
    return $found
}

run_guardrails() {
    GUARDRAIL_VIOLATIONS=()
    local had_failure=0 checks="size dependencies silent_errors state_location tui_deps prompt_logic"
    local -A results=()
    for check in $checks; do
        if "guardrail_check_$check"; then results[$check]="PASS"
        else results[$check]="FAIL"; had_failure=1; fi
    done
    local report="${AUTOMATON_DIR:-.automaton}/principle-violations.md"
    {
        echo "# Principle Violations Report"
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        for check in $checks; do
            if [ "${results[$check]}" = "FAIL" ]; then
                echo "## FAIL: $check"
                for v in "${GUARDRAIL_VIOLATIONS[@]}"; do
                    echo "$v" | grep -qi "${check%%_*}" && echo "- $v"
                done
            else echo "## PASS: $check"; fi
        done
    } > "$report"
    if [ "$had_failure" -eq 1 ]; then
        if [ "${GUARDRAILS_MODE:-warn}" = "block" ]; then
            log "ORCHESTRATOR" "GUARDRAILS BLOCKED: ${#GUARDRAIL_VIOLATIONS[@]} violations. See $report"
            return 1
        fi
        log "ORCHESTRATOR" "GUARDRAILS WARNING: ${#GUARDRAIL_VIOLATIONS[@]} violations. See $report"
    fi
    return 0
}

_start_progress_spinner() {
    local phase="$1" iteration="$2" model="$3"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0 elapsed=0
    while true; do
        local c="${spin_chars:$((i % ${#spin_chars})):1}"
        printf "\r  %s  [%s] %s iter %s  (%s)  %ds elapsed..." "$c" "$model" "$phase" "$iteration" "agent running" "$elapsed" >&2
        sleep 1
        elapsed=$((elapsed + 1))
        i=$((i + 1))
    done
}

_stop_progress_spinner() {
    local pid="$1"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null || true
    fi
    printf "\r\033[K" >&2
}

_save_agent_log() {
    local output_file="$1" phase="$2" iteration="$3"
    local logs_dir="${AUTOMATON_DIR}/logs"
    mkdir -p "$logs_dir"
    local log_name="agent_${phase}_iter${iteration}_$(date +%s).log"
    cp "$output_file" "$logs_dir/$log_name"
    log "ORCHESTRATOR" "Agent output saved to $logs_dir/$log_name"
}

run_agent() {
    local prompt_file="$1"
    local model="$2"

    # Bootstrap (spec-37): pre-assemble context before agent invocation.
    # _run_bootstrap returns exit 1 on failure; || catches it for set -e safety.
    # Metrics are written to bootstrap_metrics.json inside the $() subshell
    # and read back here since globals don't survive subshell boundaries.
    BOOTSTRAP_MANIFEST=""
    BOOTSTRAP_FAILED="false"
    BOOTSTRAP_TIME_MS=0
    BOOTSTRAP_TOKENS_SAVED=0
    BOOTSTRAP_MANIFEST=$(_run_bootstrap) || BOOTSTRAP_FAILED="true"
    # Read metrics persisted by _run_bootstrap (survives subshell)
    if [ -f "$AUTOMATON_DIR/bootstrap_metrics.json" ]; then
        BOOTSTRAP_TIME_MS=$(jq -r '.time_ms // 0' "$AUTOMATON_DIR/bootstrap_metrics.json" 2>/dev/null || echo 0)
        BOOTSTRAP_TOKENS_SAVED=$(jq -r '.tokens_saved // 0' "$AUTOMATON_DIR/bootstrap_metrics.json" 2>/dev/null || echo 0)
        rm -f "$AUTOMATON_DIR/bootstrap_metrics.json"
    fi
    if [ -n "$BOOTSTRAP_MANIFEST" ]; then
        log "ORCHESTRATOR" "Bootstrap manifest assembled ($(echo "$BOOTSTRAP_MANIFEST" | wc -c | tr -d ' ') bytes, ${BOOTSTRAP_TIME_MS}ms, ~${BOOTSTRAP_TOKENS_SAVED} tokens saved)"
    fi

    # Native agent definitions (spec-27): invoke claude --agent with dynamic
    # context piped via stdin. The static prompt lives in the agent definition
    # file under .claude/agents/.
    if [ "$AGENTS_USE_NATIVE_DEFINITIONS" = "true" ]; then
        local agent_name
        agent_name=$(_prompt_to_agent_name "$prompt_file")

        if [ -z "$agent_name" ]; then
            log "ORCHESTRATOR" "ERROR: No native agent mapping for: $prompt_file"
            AGENT_RESULT=""
            AGENT_EXIT_CODE=1
            return 0
        fi

        local dynamic_context
        dynamic_context=$(_build_dynamic_context_stdin "$prompt_file")

        local cmd_args=("--agent" "$agent_name" "--output-format" "stream-json" "--model" "$model" "--betas" "token-efficient-tool-use-2025-02-19")

        if [ "$FLAG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
            cmd_args+=("--dangerously-skip-permissions")
        fi

        if [ "$FLAG_VERBOSE" = "true" ]; then
            cmd_args+=("--verbose")
        fi

        log "ORCHESTRATOR" "Invoking native agent: name=$agent_name model=$model"

        # Scope support (spec-60): export PROJECT_ROOT so hooks can determine
        # which directory the agent is operating in.
        export AUTOMATON_PROJECT_ROOT="${PROJECT_ROOT:-.}"

        AGENT_RESULT=""
        AGENT_EXIT_CODE=0

        # Start progress spinner so the terminal shows activity
        _start_progress_spinner "$current_phase" "$phase_iteration" "$model" &
        local _spinner_pid=$!

        local _tmp_output
        _tmp_output=$(mktemp) || { _stop_progress_spinner "$_spinner_pid"; log "ORCHESTRATOR" "Failed to create temp file"; AGENT_EXIT_CODE=1; return 0; }
        # Scope support (spec-60): run agent in PROJECT_ROOT so it operates on
        # the scoped directory while the orchestrator stays at invocation cwd.
        echo "$dynamic_context" | (cd "${PROJECT_ROOT:-.}" && unset CLAUDECODE && claude "${cmd_args[@]}") > "$_tmp_output" 2>&1 || AGENT_EXIT_CODE=$?

        _stop_progress_spinner "$_spinner_pid"

        local _phase_hint="${prompt_file##*/PROMPT_}"
        _phase_hint="${_phase_hint%.md}"

        # Always save agent output to logs for debugging
        _save_agent_log "$_tmp_output" "$_phase_hint" "${phase_iteration:-0}"

        AGENT_RESULT=$(truncate_output "$_tmp_output" "$_phase_hint" "${CURRENT_ITERATION:-0}")
        rm -f "$_tmp_output"

        log "ORCHESTRATOR" "Agent finished: exit_code=$AGENT_EXIT_CODE"
        return 0
    fi

    # Legacy mode: pipe full prompt to claude -p
    if [ ! -f "$prompt_file" ]; then
        log "ORCHESTRATOR" "ERROR: Prompt file not found: $prompt_file"
        AGENT_RESULT=""
        AGENT_EXIT_CODE=1
        return 0
    fi

    # Inject dynamic context (iteration, budget, diffs) into <dynamic_context>
    # section at the end of the prompt, preserving the static prefix for
    # prompt caching (spec-29, spec-30)
    local effective_prompt="$prompt_file"
    local augmented
    augmented=$(inject_dynamic_context "$prompt_file")
    if [ -n "$augmented" ] && [ -f "$augmented" ]; then
        effective_prompt="$augmented"
    fi

    # Log prompt size for token efficiency tracking (spec-24)
    log_prompt_size "$effective_prompt"

    # Check if static prefix meets minimum cacheable threshold (spec-30)
    check_cache_prefix_threshold "$effective_prompt" "$model"

    local cmd_args=("-p" "--output-format" "stream-json" "--model" "$model" "--betas" "token-efficient-tool-use-2025-02-19")

    if [ "$FLAG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
        cmd_args+=("--dangerously-skip-permissions")
    fi

    if [ "$FLAG_VERBOSE" = "true" ]; then
        cmd_args+=("--verbose")
    fi

    log "ORCHESTRATOR" "Invoking agent: model=$model prompt=$effective_prompt"

    # Scope support (spec-60): export PROJECT_ROOT so hooks can determine
    # which directory the agent is operating in.
    export AUTOMATON_PROJECT_ROOT="${PROJECT_ROOT:-.}"

    AGENT_RESULT=""
    AGENT_EXIT_CODE=0

    # Start progress spinner so the terminal shows activity
    _start_progress_spinner "$current_phase" "$phase_iteration" "$model" &
    local _spinner_pid=$!

    # Capture stdout (stream-json) and stderr (errors, verbose logs) together.
    # extract_tokens() greps for "type":"result" lines so stderr noise is harmless.
    # Error classifiers (is_rate_limit, is_network_error) need stderr to detect failures.
    local _tmp_output
    _tmp_output=$(mktemp) || { _stop_progress_spinner "$_spinner_pid"; log "ORCHESTRATOR" "Failed to create temp file"; AGENT_EXIT_CODE=1; return 0; }
    # Scope support (spec-60): run agent in PROJECT_ROOT so it operates on
    # the scoped directory while the orchestrator stays at invocation cwd.
    cat "$effective_prompt" | (cd "${PROJECT_ROOT:-.}" && unset CLAUDECODE && claude "${cmd_args[@]}") > "$_tmp_output" 2>&1 || AGENT_EXIT_CODE=$?

    _stop_progress_spinner "$_spinner_pid"

    local _phase_hint="${prompt_file##*/PROMPT_}"
    _phase_hint="${_phase_hint%.md}"

    # Always save agent output to logs for debugging
    _save_agent_log "$_tmp_output" "$_phase_hint" "${phase_iteration:-0}"

    AGENT_RESULT=$(truncate_output "$_tmp_output" "$_phase_hint" "${CURRENT_ITERATION:-0}")
    rm -f "$_tmp_output"

    log "ORCHESTRATOR" "Agent finished: exit_code=$AGENT_EXIT_CODE"

    return 0
}

get_phase_prompt() {
    local _install_dir="${AUTOMATON_INSTALL_DIR:-.}"
    case "$1" in
        research)
            # Self-build mode uses specialized research prompt (spec-25)
            if [ "${ARG_SELF:-false}" = "true" ] && [ -f "${_install_dir}/PROMPT_self_research.md" ]; then
                echo "${_install_dir}/PROMPT_self_research.md"
            else
                echo "${_install_dir}/PROMPT_research.md"
            fi
            ;;
        plan)
            if [ "${ARG_SELF:-false}" = "true" ] && [ -f "${_install_dir}/PROMPT_self_plan.md" ]; then
                echo "${_install_dir}/PROMPT_self_plan.md"
            else
                echo "${_install_dir}/PROMPT_plan.md"
            fi
            ;;
        build)    echo "${_install_dir}/PROMPT_build.md" ;;
        review)   echo "${_install_dir}/PROMPT_review.md" ;;
    esac
}

# Returns the configured model for a given phase.
get_phase_model() {
    case "$1" in
        research) echo "$MODEL_RESEARCH" ;;
        plan)     echo "$MODEL_PLANNING" ;;
        build)    echo "$MODEL_BUILDING" ;;
        review)   echo "$MODEL_REVIEW" ;;
    esac
}

# Returns max iterations for a given phase (0 = unlimited).
get_phase_max_iterations() {
    case "$1" in
        research) echo "$EXEC_MAX_ITER_RESEARCH" ;;
        plan)     echo "$EXEC_MAX_ITER_PLAN" ;;
        build)    echo "$EXEC_MAX_ITER_BUILD" ;;
        review)   echo "$EXEC_MAX_ITER_REVIEW" ;;
    esac
}

# Checks whether the agent output contains the COMPLETE signal.
agent_signaled_complete() {
    # Check for both legacy (<promise>COMPLETE</promise>) and spec-29
    # (<result status="complete">) completion signals for backward compatibility
    echo "$AGENT_RESULT" | grep -qE 'COMPLETE</promise>|<result status="complete">'
}

# Emits a one-line inter-iteration status per spec-01 format.
# Includes cache hit ratio for the current iteration (spec-30).
emit_status_line() {
    local model="$1" iter_cost="$2"
    local phase_upper max_iter iter_display remaining_budget

    phase_upper=$(echo "$current_phase" | tr '[:lower:]' '[:upper:]')
    max_iter=$(get_phase_max_iterations "$current_phase")

    if [ "$max_iter" -eq 0 ]; then
        iter_display="${phase_iteration}"
    else
        iter_display="${phase_iteration}/${max_iter}"
    fi

    # Calculate per-iteration cache hit ratio from last token extraction (spec-30)
    local cache_pct="n/a"
    local cr=${LAST_CACHE_READ:-0} inp=${LAST_INPUT_TOKENS:-0} cc=${LAST_CACHE_CREATE:-0}
    local cache_denom=$((cr + inp + cc))
    if [ "$cache_denom" -gt 0 ] 2>/dev/null; then
        cache_pct="$(awk -v cr="$cr" -v d="$cache_denom" 'BEGIN{printf "%d%%", (cr/d)*100}')"
    fi

    if [ "$BUDGET_MODE" = "allowance" ]; then
        # Allowance mode: show input/output tokens and remaining allowance (spec-30 §7)
        # Note: cache reduces USD cost but NOT allowance consumption (token-based)
        local tokens_remaining tokens_display
        tokens_remaining=$(jq '.tokens_remaining' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
        if [ "$tokens_remaining" != "?" ] && [ "$tokens_remaining" -ge 1000000 ] 2>/dev/null; then
            tokens_display="$((tokens_remaining / 1000000))M"
        elif [ "$tokens_remaining" != "?" ] && [ "$tokens_remaining" -ge 1000 ] 2>/dev/null; then
            tokens_display="$((tokens_remaining / 1000))K"
        else
            tokens_display="$tokens_remaining"
        fi

        local inp_display out_display
        if [ "${LAST_INPUT_TOKENS:-0}" -ge 1000 ] 2>/dev/null; then
            inp_display="$(awk -v t="${LAST_INPUT_TOKENS:-0}" 'BEGIN{printf "%dK", t/1000}')"
        else
            inp_display="${LAST_INPUT_TOKENS:-0}"
        fi
        if [ "${LAST_OUTPUT_TOKENS:-0}" -ge 1000 ] 2>/dev/null; then
            out_display="$(awk -v t="${LAST_OUTPUT_TOKENS:-0}" 'BEGIN{printf "%dK", t/1000}')"
        else
            out_display="${LAST_OUTPUT_TOKENS:-0}"
        fi

        echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ${inp_display}/${out_display} tokens | cache: ${cache_pct} | allowance: ${tokens_display} remaining (cache saves cost, not tokens)"
    else
        remaining_budget=$(jq -r '(.limits.max_cost_usd - .used.estimated_cost_usd) * 100 | floor / 100' \
            "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
        echo "[${phase_upper} ${iter_display}] ${current_phase} iteration ${phase_iteration} | ~\$${iter_cost} | cache: ${cache_pct} | budget: \$${remaining_budget} remaining"
    fi
}
