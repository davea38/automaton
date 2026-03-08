#!/usr/bin/env bash
# lib/context.sh — Bootstrap execution, dynamic context injection, and prompt management.
# Spec references: spec-13 (bootstrap scripts), spec-30 (dynamic context),
#                  spec-31 (cache prefix optimization)

_run_bootstrap() {
    local phase="${1:-$current_phase}"
    local iteration="${2:-$phase_iteration}"

    # Initialize metrics globals
    BOOTSTRAP_TIME_MS=0
    BOOTSTRAP_TOKENS_SAVED=0

    if [ "$EXEC_BOOTSTRAP_ENABLED" != "true" ]; then
        return 0
    fi

    local script_path="$EXEC_BOOTSTRAP_SCRIPT"
    if [ ! -x "$script_path" ]; then
        log "ORCHESTRATOR" "Bootstrap script not found or not executable: $script_path" >&2
        return 1
    fi

    local timeout_seconds=$(( EXEC_BOOTSTRAP_TIMEOUT_MS / 1000 ))
    [ "$timeout_seconds" -lt 1 ] && timeout_seconds=1

    # Millisecond-precision timing (fall back to seconds * 1000)
    local start_ms
    if date +%s%N &>/dev/null && [ "$(date +%s%N)" != "%N" ]; then
        start_ms=$(( $(date +%s%N) / 1000000 ))
    else
        start_ms=$(( $(date +%s) * 1000 ))
    fi

    local manifest="" stderr_file
    stderr_file=$(mktemp) || { log "ORCHESTRATOR" "Failed to create temp file for bootstrap" >&2; return 1; }
    # NOTE: _run_bootstrap runs inside $() in run_agent, so anything on stdout
    # becomes BOOTSTRAP_MANIFEST. Use >&2 for log calls to avoid polluting it.
    if command -v timeout &>/dev/null; then
        manifest=$(timeout "${timeout_seconds}s" "$script_path" "." "$phase" "$iteration" 2>"$stderr_file") || {
            local stderr_output
            stderr_output=$(cat "$stderr_file")
            rm -f "$stderr_file"
            _bootstrap_record_time "$start_ms"
            log "ORCHESTRATOR" "Bootstrap failed. Falling back to agent-driven context loading." >&2
            [ -n "$stderr_output" ] && log "ORCHESTRATOR" "Bootstrap stderr: $stderr_output" >&2
            return 1
        }
    else
        manifest=$("$script_path" "." "$phase" "$iteration" 2>"$stderr_file") || {
            local stderr_output
            stderr_output=$(cat "$stderr_file")
            rm -f "$stderr_file"
            _bootstrap_record_time "$start_ms"
            log "ORCHESTRATOR" "Bootstrap failed. Falling back to agent-driven context loading." >&2
            [ -n "$stderr_output" ] && log "ORCHESTRATOR" "Bootstrap stderr: $stderr_output" >&2
            return 1
        }
    fi
    rm -f "$stderr_file"

    # Validate JSON
    if ! echo "$manifest" | jq empty 2>/dev/null; then
        _bootstrap_record_time "$start_ms"
        log "ORCHESTRATOR" "Bootstrap produced invalid JSON. Falling back to agent-driven context loading." >&2
        return 1
    fi

    # Check for error field in manifest
    if echo "$manifest" | jq -e '.error' &>/dev/null; then
        _bootstrap_record_time "$start_ms"
        log "ORCHESTRATOR" "Bootstrap error: $(echo "$manifest" | jq -r '.error')" >&2
        return 1
    fi

    # Record timing and estimate token savings
    _bootstrap_record_time "$start_ms"
    _bootstrap_estimate_tokens_saved "$manifest"

    # Performance check: warn if bootstrap exceeds 2-second target
    local target_ms="$EXEC_BOOTSTRAP_TIMEOUT_MS"
    if [ "$BOOTSTRAP_TIME_MS" -gt "$target_ms" ]; then
        local elapsed_s
        elapsed_s=$(awk -v ms="$BOOTSTRAP_TIME_MS" 'BEGIN { printf "%.1f", ms / 1000 }')
        local target_s
        target_s=$(awk -v ms="$target_ms" 'BEGIN { printf "%.1f", ms / 1000 }')
        log "ORCHESTRATOR" "WARNING: Bootstrap took ${elapsed_s}s (target: <${target_s}s). Consider optimizing init.sh." >&2
    fi

    # Persist metrics to file so they survive the $() subshell boundary.
    # The caller (run_agent) reads these back into globals after the call.
    echo "{\"time_ms\":${BOOTSTRAP_TIME_MS},\"tokens_saved\":${BOOTSTRAP_TOKENS_SAVED}}" \
        > "${AUTOMATON_DIR}/bootstrap_metrics.json"

    echo "$manifest"
}

# Record elapsed bootstrap time in BOOTSTRAP_TIME_MS and persist metrics to file.
# Called on both success and failure paths so metrics survive the $() subshell.
# Args: $1 — start time in milliseconds
_bootstrap_record_time() {
    local start_ms="$1"
    local end_ms
    if date +%s%N &>/dev/null && [ "$(date +%s%N)" != "%N" ]; then
        end_ms=$(( $(date +%s%N) / 1000000 ))
    else
        end_ms=$(( $(date +%s) * 1000 ))
    fi
    BOOTSTRAP_TIME_MS=$(( end_ms - start_ms ))
    [ "$BOOTSTRAP_TIME_MS" -lt 0 ] && BOOTSTRAP_TIME_MS=0
    # Persist to file (tokens_saved may be updated later on success path)
    echo "{\"time_ms\":${BOOTSTRAP_TIME_MS},\"tokens_saved\":${BOOTSTRAP_TOKENS_SAVED}}" \
        > "${AUTOMATON_DIR}/bootstrap_metrics.json" 2>/dev/null || true
}

# Estimate input tokens saved by bootstrap vs agent-driven file reads.
# Without bootstrap, agents spend 3-5 tool calls reading AGENTS.md,
# IMPLEMENTATION_PLAN.md, state.json, budget.json, and specs (~20-50K tokens).
# Bootstrap provides the same data in a compact manifest (~2K tokens).
# Baseline: 30000 tokens (midpoint of 20-50K range from spec-37).
# Args: $1 — manifest JSON string
_bootstrap_estimate_tokens_saved() {
    local manifest="$1"
    local baseline_tokens=30000
    local manifest_bytes manifest_tokens
    manifest_bytes=$(printf '%s' "$manifest" | wc -c | tr -d ' ')
    manifest_tokens=$(( manifest_bytes / 4 ))
    BOOTSTRAP_TOKENS_SAVED=$(( baseline_tokens - manifest_tokens ))
    [ "$BOOTSTRAP_TOKENS_SAVED" -lt 0 ] && BOOTSTRAP_TOKENS_SAVED=0
}

# Format bootstrap manifest for inclusion in dynamic context.
# Returns formatted markdown block or empty string if manifest is empty.
#
# Args:
#   $1 — manifest JSON string
_format_bootstrap_for_context() {
    local manifest="$1"
    if [ -z "$manifest" ]; then
        # When bootstrap failed, tell the agent to read files manually
        if [ "${BOOTSTRAP_FAILED:-false}" = "true" ]; then
            echo "## Bootstrap Failed"
            echo ""
            echo "Bootstrap context assembly failed. You should read AGENTS.md, IMPLEMENTATION_PLAN.md, state files, and budget files manually to understand the project state."
            echo ""
        fi
        return 0
    fi
    echo "## Bootstrap Manifest"
    echo "<!-- Pre-assembled by init.sh — do NOT re-read these files -->"
    echo '```json'
    if echo "$manifest" | jq empty 2>/dev/null; then
        echo "$manifest" | jq .
    else
        echo "$manifest"
    fi
    echo '```'
    echo ""
}

# Injects dynamic runtime context into the <dynamic_context> section of a prompt
# file. Replaces placeholder content between <dynamic_context> and </dynamic_context>
# with iteration number, budget remaining, recent diffs, and phase-specific data.
# The static prefix (everything before <dynamic_context>) is preserved byte-for-byte,
# enabling prompt caching (spec-30).
#
# Args: prompt_file
# Outputs: path to augmented prompt file (or empty string if no injection needed)
inject_dynamic_context() {
    local prompt_file="$1"
    local augmented="$AUTOMATON_DIR/prompt_augmented.md"

    # If no <dynamic_context> tag found, skip injection
    if ! grep -q '<dynamic_context>' "$prompt_file"; then
        echo ""
        return 0
    fi

    {
        # Static prefix: everything up to and including <dynamic_context>
        sed -n '1,/<dynamic_context>/p' "$prompt_file"

        # --- Dynamic content injected by orchestrator ---

        # Bootstrap manifest (spec-37): pre-assembled context from init.sh
        # When bootstrap fails, _format_bootstrap_for_context emits a fallback
        # notice telling the agent to read files manually.
        if [ -n "${BOOTSTRAP_MANIFEST:-}" ] || [ "${BOOTSTRAP_FAILED:-false}" = "true" ]; then
            _format_bootstrap_for_context "${BOOTSTRAP_MANIFEST:-}"
        fi

        echo "## Current State"
        echo ""
        echo "- Phase: $current_phase"
        echo "- Iteration: $phase_iteration"

        # Build sub-phase context (spec-36)
        if [ "$current_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
            if [ "${build_sub_phase:-implementation}" = "scaffold" ]; then
                echo "- Build sub-phase: TEST SCAFFOLD (3a) — iteration $((scaffold_iterations_done + 1))/$EXEC_TEST_SCAFFOLD_ITERATIONS"
                echo ""
                echo "**TEST SCAFFOLD MODE**: Write test files ONLY for plan tasks with \`<!-- test: path -->\` annotations. Do NOT implement any features. Tests should fail initially (no implementation exists yet). Commit test files when done."
            else
                echo "- Build sub-phase: IMPLEMENTATION (3b)"
            fi
        fi

        # Budget remaining
        if [ -f "$AUTOMATON_DIR/budget.json" ]; then
            local remaining
            remaining=$(jq '.tokens_remaining // "unknown"' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "unknown")
            echo "- Budget remaining: $remaining tokens"
        fi
        echo ""

        # Context summary if available
        if [ -f "$AUTOMATON_DIR/context_summary.md" ]; then
            cat "$AUTOMATON_DIR/context_summary.md"
            echo ""
        fi

        # Build-specific context for iterations after the first.
        # When COMPACTION_REDUCE_CONTEXT is set (post-compaction mitigation),
        # emit only essential context (current focus) and skip verbose sections
        # (git diffs, iteration memory, codebase overview) to keep the prompt lean.
        if [ "$current_phase" = "build" ] && [ "$phase_iteration" -gt 1 ]; then
            local plan_file="IMPLEMENTATION_PLAN.md"
            if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
                plan_file="$AUTOMATON_DIR/backlog.md"
            fi

            if [ "${COMPACTION_REDUCE_CONTEXT:-false}" = "true" ]; then
                echo "## Post-Compaction Recovery"
                echo "Auto-compaction was detected. Context has been reduced. Read progress.txt for full state."
                echo ""
                echo "## Current Focus"
                if [ -f "$plan_file" ]; then
                    grep '\[ \]' "$plan_file" | head -3 || echo "All tasks complete."
                fi
                echo ""
                # Clear the flag after one reduced-context iteration
                COMPACTION_REDUCE_CONTEXT=false
            else
                echo "## Recent Changes"
                echo '```'
                git diff --stat HEAD~3 2>/dev/null || echo "No recent changes."
                echo '```'
                echo ""

                echo "## Current Focus"
                if [ -f "$plan_file" ]; then
                    grep '\[ \]' "$plan_file" | head -5 || echo "All tasks complete."
                fi
                echo ""

                if [ -f "$AUTOMATON_DIR/iteration_memory.md" ]; then
                    echo "## Recent Iteration History"
                    tail -5 "$AUTOMATON_DIR/iteration_memory.md"
                    echo ""
                fi

                if [ "$SELF_BUILD_ENABLED" = "true" ] && [ -f "automaton.sh" ]; then
                    echo "## Codebase Overview (automaton.sh)"
                    echo '```'
                    grep -n '^[a-z_]*()' automaton.sh | head -40 || true
                    echo '```'
                    echo ""
                fi
            fi
        fi

        # Review-specific context: delta-only review with changed files and related specs (audit wave 5)
        if [ "$current_phase" = "review" ]; then
            _inject_delta_review_context
        fi

        # Review-specific context: inject pending spec amendment proposals for evaluation
        if [ "$current_phase" = "review" ]; then
            local _amendments_ctx
            _amendments_ctx=$(get_pending_amendments_context)
            if [ -n "$_amendments_ctx" ]; then
                echo "$_amendments_ctx"
                echo ""
            fi
        fi

        # Review-specific context: inject QA failure report when available (spec-46.4)
        if [ "$current_phase" = "review" ] && [ -f "$AUTOMATON_DIR/qa/failure-report.md" ]; then
            echo "## QA Failure Report"
            echo ""
            echo "The QA loop exhausted its iterations with unresolved failures. Review the report below:"
            echo ""
            cat "$AUTOMATON_DIR/qa/failure-report.md"
            echo ""
        fi

        # Suffix: </dynamic_context> and everything after
        sed -n '/<\/dynamic_context>/,$p' "$prompt_file"
    } > "$augmented"

    echo "$augmented"
}

# Tracks prompt size and logs it. Called before each agent invocation.
# Args: prompt_file
log_prompt_size() {
    local prompt_file="$1"
    if [ ! -f "$prompt_file" ]; then
        return 0
    fi

    local char_count est_tokens
    char_count=$(wc -c < "$prompt_file")
    est_tokens=$((char_count / 4))

    log "ORCHESTRATOR" "Prompt size: ${char_count} chars (~${est_tokens} tokens) from $prompt_file"
}

# Checks whether the static prefix of a prompt file meets the minimum token
# threshold required for prompt caching. Logs an informational message when
# the prefix is too small to be cached.
# WHY: Users need to know when caching is inactive so they can decide whether
# to expand the static prefix (spec-30).
#
# Minimum cacheable thresholds per model:
#   Opus/Haiku: 4096 tokens
#   Sonnet: 2048 tokens
#
# Args: prompt_file model
check_cache_prefix_threshold() {
    local prompt_file="$1"
    local model="$2"
    [ -f "$prompt_file" ] || return 0

    # Extract static prefix (everything before <dynamic_context>)
    local static_chars
    if grep -q '<dynamic_context>' "$prompt_file"; then
        static_chars=$(sed -n '1,/<dynamic_context>/p' "$prompt_file" | wc -c)
    else
        # No dynamic_context marker — entire prompt is static
        static_chars=$(wc -c < "$prompt_file")
    fi

    local est_tokens=$((static_chars / 4))

    # Determine threshold for model
    local threshold
    case "$model" in
        sonnet) threshold=2048 ;;
        *)      threshold=4096 ;;
    esac

    if [ "$est_tokens" -lt "$threshold" ]; then
        log "ORCHESTRATOR" "INFO: Static prompt prefix is ~${est_tokens} tokens, below the ${threshold}-token minimum for caching with model '${model}'. Prompt caching will be inactive. Consider expanding the static prefix to enable cache hits."
    fi
}

# Appends a one-line summary to .automaton/iteration_memory.md after each
# build iteration. Included in context for subsequent iterations.
append_iteration_memory() {
    local memory_file="$AUTOMATON_DIR/iteration_memory.md"

    # Get files changed and a short summary
    local files_summary
    files_summary=$(git diff --name-only HEAD~1 2>/dev/null | head -3 | tr '\n' ', ' || echo "none")
    files_summary="${files_summary%, }"

    local line_info
    line_info=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | sed 's/^ *//' || echo "no changes")

    echo "[BUILD $phase_iteration] $files_summary: $line_info" >> "$memory_file"
}

# Injects delta-only review context: per-task diffs, changed file contents,
# and related specs via traceability map. Replaces full-codebase review with
# focused context containing only what changed during the build cycle.
# WHY: Estimated 30-50% input token reduction — review previously had to read
# the entire codebase; now it receives only changed files and their related specs.
_inject_delta_review_context() {
    local build_files
    build_files=$(ls "$AUTOMATON_DIR/agents/build-"*.json 2>/dev/null || true)

    # --- Per-task build diffs (preserved from audit wave 4) ---
    if [ -n "$build_files" ]; then
        echo "## Per-Task Build Diffs"
        echo ""
        echo "Each build iteration's changes (task, commit, diff stat):"
        echo ""
        local bfile
        for bfile in $build_files; do
            local b_task b_commit b_diff b_iter
            b_iter=$(jq -r '.iteration // "?"' "$bfile" 2>/dev/null || echo "?")
            b_task=$(jq -r '.task // "unknown"' "$bfile" 2>/dev/null || echo "unknown")
            b_commit=$(jq -r '.git_commit // "none"' "$bfile" 2>/dev/null || echo "none")
            b_diff=$(jq -r '.diff_stat // ""' "$bfile" 2>/dev/null || echo "")
            echo "### Iteration ${b_iter}: ${b_task}"
            echo "Commit: ${b_commit}"
            if [ -n "$b_diff" ]; then
                echo '```'
                echo "$b_diff"
                echo '```'
            else
                echo "_No diff recorded_"
            fi
            echo ""
        done
    fi

    # --- Delta-only: collect all changed files across build iterations ---
    local all_changed_files=""
    if [ -n "$build_files" ]; then
        for bfile in $build_files; do
            local iter_files
            iter_files=$(jq -r '.files_changed[]? // empty' "$bfile" 2>/dev/null || true)
            if [ -n "$iter_files" ]; then
                all_changed_files="${all_changed_files}${iter_files}"$'\n'
            fi
        done
    fi

    # Deduplicate and filter to existing files
    local unique_files=""
    if [ -n "$all_changed_files" ]; then
        unique_files=$(echo "$all_changed_files" | sort -u | while read -r f; do
            [ -n "$f" ] && [ -f "$f" ] && echo "$f"
        done)
    fi

    # --- Emit changed file contents (truncated for large files) ---
    if [ -n "$unique_files" ]; then
        local file_count
        file_count=$(echo "$unique_files" | wc -l | tr -d ' ')
        echo "## Changed Files (${file_count} files)"
        echo ""
        echo "Contents of files modified during the build cycle. Review these for correctness."
        echo "You do NOT need to read these files separately — they are included below."
        echo ""
        local max_lines=200
        echo "$unique_files" | while read -r filepath; do
            [ -z "$filepath" ] && continue
            local line_count
            line_count=$(wc -l < "$filepath" 2>/dev/null || echo "0")
            line_count=$(echo "$line_count" | tr -d ' ')
            echo "### \`${filepath}\` (${line_count} lines)"
            echo '```'
            if [ "$line_count" -le "$max_lines" ]; then
                cat "$filepath"
            else
                head -n "$max_lines" "$filepath"
                echo ""
                echo "... [truncated — ${line_count} total lines, showing first ${max_lines}]"
            fi
            echo '```'
            echo ""
        done
    fi

    # --- Related specs via traceability map ---
    local traceability_file="$AUTOMATON_DIR/traceability.json"
    local related_specs=""
    if [ -f "$traceability_file" ] && [ -n "$unique_files" ]; then
        # Extract spec references from traceability evidence fields that mention changed files
        related_specs=$(echo "$unique_files" | while read -r filepath; do
            [ -z "$filepath" ] && continue
            jq -r --arg f "$filepath" \
                '.criteria[]? | select(.evidence | test($f)) | .id | split("-")[1]' \
                "$traceability_file" 2>/dev/null || true
        done | sort -u)
    fi

    # Also extract spec numbers from changed file paths (e.g., test_scope.sh → spec-60)
    # and from plan task annotations
    if [ -n "$unique_files" ] && [ -d "specs" ]; then
        local spec_from_files
        spec_from_files=$(echo "$unique_files" | while read -r filepath; do
            [ -z "$filepath" ] && continue
            # Match spec numbers referenced in the file's first few lines
            head -n 5 "$filepath" 2>/dev/null | grep -oP 'spec-\d+' | grep -oP '\d+' || true
        done | sort -u)
        if [ -n "$spec_from_files" ]; then
            related_specs=$(printf '%s\n%s' "$related_specs" "$spec_from_files" | sort -u | grep -v '^$')
        fi
    fi

    # Emit related spec contents
    if [ -n "$related_specs" ]; then
        echo "## Related Specs"
        echo ""
        echo "Specs linked to changed files via traceability map or file references."
        echo "You do NOT need to read these spec files separately — they are included below."
        echo ""
        echo "$related_specs" | while read -r spec_num; do
            [ -z "$spec_num" ] && continue
            local spec_file
            # Find spec file matching the number
            spec_file=$(ls "specs/spec-${spec_num}"*.md 2>/dev/null | head -1)
            if [ -n "$spec_file" ] && [ -f "$spec_file" ]; then
                local spec_lines
                spec_lines=$(wc -l < "$spec_file" | tr -d ' ')
                echo "### \`${spec_file}\`"
                echo '```'
                if [ "$spec_lines" -le 150 ]; then
                    cat "$spec_file"
                else
                    head -n 150 "$spec_file"
                    echo ""
                    echo "... [truncated — ${spec_lines} total lines, showing first 150]"
                fi
                echo '```'
                echo ""
            fi
        done
    fi

    # --- Traceability summary if available ---
    if [ -f "$traceability_file" ]; then
        echo "## Previous Traceability Results"
        echo ""
        local t_pass t_partial t_fail
        t_pass=$(jq -r '.summary.pass // 0' "$traceability_file" 2>/dev/null || echo "0")
        t_partial=$(jq -r '.summary.partial // 0' "$traceability_file" 2>/dev/null || echo "0")
        t_fail=$(jq -r '.summary.fail // 0' "$traceability_file" 2>/dev/null || echo "0")
        echo "Last traceability check: ${t_pass} pass, ${t_partial} partial, ${t_fail} fail"
        echo ""
        # Show failed/partial criteria for focused re-verification
        local issues
        issues=$(jq -r '.criteria[]? | select(.status != "pass") | "- **\(.id)** [\(.status)]: \(.evidence)"' \
            "$traceability_file" 2>/dev/null || true)
        if [ -n "$issues" ]; then
            echo "### Items needing re-verification"
            echo "$issues"
            echo ""
        fi
    fi
}
