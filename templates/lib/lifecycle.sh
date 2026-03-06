#!/usr/bin/env bash
# lib/lifecycle.sh — Self-build, learnings, run summaries, budget history, and lifecycle management.
# Spec references: spec-22 (self-build checkpoints), spec-25 (self-build mode),
#                  spec-26 (run history/stats), spec-34 (persistent state),
#                  spec-42 (learnings system)

self_build_checkpoint() {
    if [ "$SELF_BUILD_ENABLED" != "true" ]; then
        return 0
    fi

    local checksums_file="$AUTOMATON_DIR/self_checksums.json"
    local tmp="$AUTOMATON_DIR/self_checksums.json.tmp"
    local backup_dir="$AUTOMATON_DIR/self_backup"
    mkdir -p "$backup_dir"

    # Build checksums JSON and backup files
    local checksums_json="{}"
    for f in $SELF_BUILD_FILES; do
        if [ -f "$f" ]; then
            local hash
            hash=$(sha256sum "$f" | awk '{print $1}')
            # Backup the file for potential restore
            cp "$f" "$backup_dir/$(echo "$f" | tr '/' '_')"
            checksums_json=$(echo "$checksums_json" | jq --arg k "$f" --arg v "$hash" '. + {($k): $v}')
        fi
    done

    echo "$checksums_json" > "$tmp" && mv "$tmp" "$checksums_file"

    log "ORCHESTRATOR" "Self-build checkpoint: checksums saved for orchestrator files"
}

# After a build iteration, compares current file checksums against the
# pre-iteration checkpoint. If any orchestrator file changed, validates the
# change (syntax check + smoke test) and logs to the audit trail.
#
# Usage: self_build_validate
# Returns: 0 = all clear, 1 = file was restored from checkpoint
self_build_validate() {
    if [ "$SELF_BUILD_ENABLED" != "true" ]; then
        return 0
    fi

    local checksums_file="$AUTOMATON_DIR/self_checksums.json"
    local backup_dir="$AUTOMATON_DIR/self_backup"
    local audit_file="$AUTOMATON_DIR/self_modifications.json"
    local changed_files=""
    local any_changed=false

    # Initialize audit log if it doesn't exist
    if [ ! -f "$audit_file" ]; then
        echo '[]' > "$audit_file"
    fi

    if [ ! -f "$checksums_file" ]; then
        return 0
    fi

    # Compare current checksums against checkpoint
    local new_checksums=""
    for f in $SELF_BUILD_FILES; do
        if [ -f "$f" ]; then
            local old_hash new_hash
            old_hash=$(jq -r --arg f "$f" '.[$f] // ""' "$checksums_file")
            new_hash=$(sha256sum "$f" | awk '{print $1}')

            if [ -n "$old_hash" ] && [ "$old_hash" != "$new_hash" ]; then
                any_changed=true
                changed_files="${changed_files} $f"
                log "ORCHESTRATOR" "Self-build: $f was modified during iteration $iteration"
                new_checksums="${new_checksums}{\"file\":\"$f\",\"before\":\"$old_hash\",\"after\":\"$new_hash\"},"
            fi
        fi
    done

    if [ "$any_changed" != "true" ]; then
        return 0
    fi

    # --- Syntax validation for automaton.sh ---
    local syntax_ok="skipped"
    local smoke_ok="skipped"

    if echo "$changed_files" | grep -q "automaton.sh"; then
        # Syntax check
        if bash -n automaton.sh 2>/dev/null; then
            syntax_ok="pass"
            log "ORCHESTRATOR" "Self-build: automaton.sh syntax check PASSED"

            # Smoke test (dry-run in subshell)
            if [ "$SELF_BUILD_REQUIRE_SMOKE" = "true" ]; then
                if (./automaton.sh --dry-run) >/dev/null 2>&1; then
                    smoke_ok="pass"
                    log "ORCHESTRATOR" "Self-build: automaton.sh smoke test PASSED"
                else
                    smoke_ok="fail"
                    log "ORCHESTRATOR" "Self-build: automaton.sh smoke test FAILED — restoring from checkpoint"
                    _self_build_restore "$backup_dir"
                    _self_build_add_fix_task "automaton.sh smoke test (--dry-run) failed after iteration $iteration"
                    _self_build_audit_entry "$changed_files" "$new_checksums" "$syntax_ok" "$smoke_ok"
                    return 1
                fi
            fi
        else
            syntax_ok="fail"
            log "ORCHESTRATOR" "Self-build: automaton.sh syntax check FAILED — restoring from checkpoint"
            _self_build_restore "$backup_dir"
            _self_build_add_fix_task "automaton.sh syntax error introduced in iteration $iteration"
            _self_build_audit_entry "$changed_files" "$new_checksums" "$syntax_ok" "$smoke_ok"
            return 1
        fi
    fi

    # Log audit entry for successful modifications
    _self_build_audit_entry "$changed_files" "$new_checksums" "$syntax_ok" "$smoke_ok"

    log "ORCHESTRATOR" "Self-build: modifications validated. Changes take effect on next --resume or fresh run."
    return 0
}

# Restores orchestrator files from the pre-iteration backup.
_self_build_restore() {
    local backup_dir="$1"

    for f in $SELF_BUILD_FILES; do
        local backup_name
        backup_name="$backup_dir/$(echo "$f" | tr '/' '_')"
        if [ -f "$backup_name" ]; then
            cp "$backup_name" "$f"
        fi
    done

    # Commit the restoration
    git add automaton.sh PROMPT_*.md automaton.config.json bin/cli.js 2>/dev/null || true
    git commit -m "automaton: self-build restore from checkpoint (iteration $iteration)" 2>/dev/null || true

    log "ORCHESTRATOR" "Self-build: files restored from pre-iteration checkpoint"
}

# Adds a fix task to the appropriate plan file for self-build failures.
_self_build_add_fix_task() {
    local description="$1"
    local plan_file="IMPLEMENTATION_PLAN.md"

    # In self-build mode, prefer the backlog
    if [ -f "$AUTOMATON_DIR/backlog.md" ] && [ "${ARG_SELF:-false}" = "true" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    if [ -f "$plan_file" ]; then
        echo "- [ ] Fix: $description" >> "$plan_file"
    fi

    log "ORCHESTRATOR" "Self-build: added fix task to $plan_file: $description"
}

# Appends an entry to the self-modification audit log.
_self_build_audit_entry() {
    local changed_files="$1" checksums_json="$2" syntax_result="$3" smoke_result="$4"
    local audit_file="$AUTOMATON_DIR/self_modifications.json"
    local tmp="$AUTOMATON_DIR/self_modifications.json.tmp"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build files array as JSON
    local files_json
    files_json=$(echo "$changed_files" | tr ' ' '\n' | grep -v '^$' | jq -R -s 'split("\n") | map(select(. != ""))')

    jq --arg ts "$timestamp" \
       --argjson iter "$iteration" \
       --arg phase "$current_phase" \
       --argjson files "$files_json" \
       --arg syntax "$syntax_result" \
       --arg smoke "$smoke_result" \
       '. + [{
           timestamp: $ts,
           iteration: $iter,
           phase: $phase,
           files_changed: $files,
           syntax_check: $syntax,
           smoke_test: $smoke
       }]' "$audit_file" > "$tmp"
    mv "$tmp" "$audit_file"
}

# Checks self-build scope limits (spec-25): max files per iteration,
# max lines changed per iteration, protected function modification.
# Returns: 0 = within limits, logs warnings for violations
self_build_check_scope() {
    if [ "$SELF_BUILD_ENABLED" != "true" ]; then
        return 0
    fi

    # Count files changed in this iteration
    local files_changed_count
    files_changed_count=$(git diff --name-only HEAD~1 2>/dev/null | wc -l || echo 0)

    if [ "$files_changed_count" -gt "$SELF_BUILD_MAX_FILES" ]; then
        log "ORCHESTRATOR" "WARNING: Self-build scope: $files_changed_count files changed (limit: $SELF_BUILD_MAX_FILES)"
    fi

    # Count lines changed
    local lines_changed
    lines_changed=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)

    if [ "$lines_changed" -gt "$SELF_BUILD_MAX_LINES" ]; then
        log "ORCHESTRATOR" "WARNING: Self-build scope: $lines_changed lines changed (limit: $SELF_BUILD_MAX_LINES)"
    fi

    # Check protected functions
    if git diff HEAD~1 -- automaton.sh 2>/dev/null | grep -qE '^\+.*(run_orchestration|_handle_shutdown)\(' 2>/dev/null; then
        local protected
        IFS=',' read -ra protected <<< "$SELF_BUILD_PROTECTED_FUNCTIONS"
        for func in "${protected[@]}"; do
            if git diff HEAD~1 -- automaton.sh 2>/dev/null | grep -qE "^\+.*${func}\s*\(" 2>/dev/null; then
                log "ORCHESTRATOR" "WARNING: Self-build scope: protected function '$func' was modified"
            fi
        done
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Structured Learnings (spec-34)
# ---------------------------------------------------------------------------

# Initializes .automaton/learnings.json if it does not exist.
# Called from initialize() to ensure the file is present before any phase runs.
init_learnings() {
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ -f "$learnings_file" ]; then
        return 0
    fi

    mkdir -p "$AUTOMATON_DIR"
    cat > "$learnings_file" <<'LEARN'
{
  "version": 1,
  "entries": []
}
LEARN
    log "ORCHESTRATOR" "Initialized structured learnings at $learnings_file"
}

# Adds a new learning entry to learnings.json.
# Args: category summary [detail] [confidence] [source_phase] [tags_csv]
# category: one of convention, architecture, debugging, tooling, performance, safety
# confidence: high, medium, low (default: medium)
# tags_csv: comma-separated tags (default: empty)
# Returns: 0 on success, 1 on error
add_learning() {
    local category="$1"
    local summary="$2"
    local detail="${3:-}"
    local confidence="${4:-medium}"
    local source_phase="${5:-${current_phase:-unknown}}"
    local tags_csv="${6:-}"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    local tmp="$AUTOMATON_DIR/learnings.json.tmp"

    if [ ! -f "$learnings_file" ]; then
        init_learnings
    fi

    # Validate category
    case "$category" in
        convention|architecture|debugging|tooling|performance|safety) ;;
        *)
            log "ORCHESTRATOR" "WARN: Invalid learning category '$category'"
            return 1
            ;;
    esac

    # Validate confidence
    case "$confidence" in
        high|medium|low) ;;
        *)
            log "ORCHESTRATOR" "WARN: Invalid learning confidence '$confidence'"
            return 1
            ;;
    esac

    # Generate next ID
    local next_id
    next_id=$(jq -r '
        .entries | map(.id) | map(ltrimstr("learn-") | tonumber) |
        (if length == 0 then 0 else max end) + 1 |
        "learn-" + (. | tostring | if length < 3 then ("000" + .)[-3:] else . end)
    ' "$learnings_file")

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Convert tags CSV to JSON array
    local tags_json
    if [ -z "$tags_csv" ]; then
        tags_json="[]"
    else
        tags_json=$(echo "$tags_csv" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R -s 'split("\n") | map(select(. != ""))')
    fi

    jq --arg id "$next_id" \
       --arg cat "$category" \
       --arg sum "$summary" \
       --arg det "$detail" \
       --arg conf "$confidence" \
       --arg phase "$source_phase" \
       --argjson iter "${iteration:-0}" \
       --arg ts "$timestamp" \
       --argjson tags "$tags_json" \
       '.entries += [{
           id: $id,
           category: $cat,
           summary: $sum,
           detail: $det,
           confidence: $conf,
           source_phase: $phase,
           source_iteration: $iter,
           created_at: $ts,
           updated_at: $ts,
           tags: $tags,
           active: true
       }]' "$learnings_file" > "$tmp"
    mv "$tmp" "$learnings_file"

    log "ORCHESTRATOR" "Learning added: $next_id ($category) — $summary"
}

# Queries learnings from learnings.json with optional filters.
# Args: [--category CAT] [--confidence CONF] [--tag TAG] [--active-only] [--ids-only]
# Outputs: JSON array of matching entries (or IDs if --ids-only).
query_learnings() {
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ ! -f "$learnings_file" ]; then
        echo "[]"
        return 0
    fi

    local filter_cat="" filter_conf="" filter_tag="" active_only="false" ids_only="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --category)   filter_cat="$2"; shift 2 ;;
            --confidence) filter_conf="$2"; shift 2 ;;
            --tag)        filter_tag="$2"; shift 2 ;;
            --active-only) active_only="true"; shift ;;
            --ids-only)   ids_only="true"; shift ;;
            *) shift ;;
        esac
    done

    jq --arg cat "$filter_cat" \
       --arg conf "$filter_conf" \
       --arg tag "$filter_tag" \
       --arg active "$active_only" \
       --arg ids "$ids_only" \
       '.entries |
        (if $active == "true" then map(select(.active == true)) else . end) |
        (if $cat != "" then map(select(.category == $cat)) else . end) |
        (if $conf != "" then map(select(.confidence == $conf)) else . end) |
        (if $tag != "" then map(select(.tags | index($tag) != null)) else . end) |
        (if $ids == "true" then map(.id) else . end)
       ' "$learnings_file"
}

# Deactivates a learning by ID (sets active to false).
# Args: id [reason]
# Returns: 0 on success, 1 if not found
deactivate_learning() {
    local target_id="$1"
    local reason="${2:-superseded}"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    local tmp="$AUTOMATON_DIR/learnings.json.tmp"

    if [ ! -f "$learnings_file" ]; then
        return 1
    fi

    local found
    found=$(jq --arg id "$target_id" '.entries | map(select(.id == $id)) | length' "$learnings_file")
    if [ "$found" -eq 0 ]; then
        log "ORCHESTRATOR" "WARN: Learning '$target_id' not found"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq --arg id "$target_id" \
       --arg ts "$timestamp" \
       --arg reason "$reason" \
       '.entries |= map(
           if .id == $id then
               .active = false | .updated_at = $ts | .detail = (.detail + " [deactivated: " + $reason + "]")
           else . end
       )' "$learnings_file" > "$tmp"
    mv "$tmp" "$learnings_file"

    log "ORCHESTRATOR" "Learning deactivated: $target_id ($reason)"
}

# Updates a learning's summary, detail, or confidence by ID.
# Args: id field value
# field: one of summary, detail, confidence
# Returns: 0 on success, 1 if not found or invalid field
update_learning() {
    local target_id="$1"
    local field="$2"
    local value="$3"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    local tmp="$AUTOMATON_DIR/learnings.json.tmp"

    if [ ! -f "$learnings_file" ]; then
        return 1
    fi

    # Validate field
    case "$field" in
        summary|detail|confidence) ;;
        *)
            log "ORCHESTRATOR" "WARN: Invalid learning field '$field'"
            return 1
            ;;
    esac

    # Validate confidence value if updating confidence
    if [ "$field" = "confidence" ]; then
        case "$value" in
            high|medium|low) ;;
            *)
                log "ORCHESTRATOR" "WARN: Invalid confidence value '$value'"
                return 1
                ;;
        esac
    fi

    local found
    found=$(jq --arg id "$target_id" '.entries | map(select(.id == $id)) | length' "$learnings_file")
    if [ "$found" -eq 0 ]; then
        log "ORCHESTRATOR" "WARN: Learning '$target_id' not found"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq --arg id "$target_id" \
       --arg field "$field" \
       --arg val "$value" \
       --arg ts "$timestamp" \
       '.entries |= map(
           if .id == $id then
               .[$field] = $val | .updated_at = $ts
           else . end
       )' "$learnings_file" > "$tmp"
    mv "$tmp" "$learnings_file"

    log "ORCHESTRATOR" "Learning updated: $target_id.$field"
}

# Returns count of active learnings, useful for status/dashboard.
count_active_learnings() {
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ ! -f "$learnings_file" ]; then
        echo "0"
        return 0
    fi
    jq '.entries | map(select(.active == true)) | length' "$learnings_file"
}

# ---------------------------------------------------------------------------
# Agent Memory Migration (spec-27)
# ---------------------------------------------------------------------------

# Migrates existing AGENTS.md learnings into per-agent memory files under
# .claude/agent-memory/<name>/MEMORY.md. Called once on first run with
# agents.use_native_definitions enabled. The build agent receives the bulk
# of operational learnings since they are most relevant to implementation.
# Also migrates structured learnings from learnings.json if available.
migrate_learnings_to_agent_memory() {
    local memory_base=".claude/agent-memory"
    local builder_memory="$memory_base/automaton-builder/MEMORY.md"
    local marker="$AUTOMATON_DIR/.learnings_migrated"

    # Only migrate once — idempotent via marker file
    if [ -f "$marker" ]; then
        return 0
    fi

    # Ensure directories exist
    local agents=("automaton-research" "automaton-planner" "automaton-builder" "automaton-reviewer" "automaton-self-researcher")
    for agent in "${agents[@]}"; do
        mkdir -p "$memory_base/$agent"
    done

    log "ORCHESTRATOR" "Migrating learnings to per-agent memory (spec-27)"

    # Extract learnings from AGENTS.md (everything under ## Learnings)
    local agents_learnings=""
    if [ -f "AGENTS.md" ]; then
        agents_learnings=$(sed -n '/^## Learnings/,/^## /{ /^## Learnings/d; /^## /d; p; }' "AGENTS.md" | sed '/^$/d' || true)
    fi

    # Extract structured learnings from learnings.json if available
    local structured_learnings=""
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ -f "$learnings_file" ]; then
        structured_learnings=$(jq -r '
            .entries
            | map(select(.active == true))
            | sort_by(if .confidence == "high" then 0
                      elif .confidence == "medium" then 1
                      else 2 end)
            | .[]
            | "- " + .summary + (if .detail != "" then " (" + .detail + ")" else "" end)
        ' "$learnings_file" 2>/dev/null || true)
    fi

    # Build the migrated content for the builder agent
    local migrated=""
    if [ -n "$agents_learnings" ]; then
        migrated="${migrated}${agents_learnings}"$'\n'
    fi
    if [ -n "$structured_learnings" ]; then
        if [ -n "$migrated" ]; then
            migrated="${migrated}"$'\n'
        fi
        migrated="${migrated}${structured_learnings}"$'\n'
    fi

    # Append migrated learnings to builder's MEMORY.md (it gets the bulk)
    if [ -n "$migrated" ] && [ -f "$builder_memory" ]; then
        printf '%s' "$migrated" >> "$builder_memory"
        log "ORCHESTRATOR" "Migrated learnings to $builder_memory"
    fi

    # Seed other agents with relevant subset headers (no content duplication)
    for agent in "${agents[@]}"; do
        local mem_file="$memory_base/$agent/MEMORY.md"
        if [ ! -f "$mem_file" ]; then
            cat > "$mem_file" <<EOF
# ${agent} Memory

## Guidelines
- Keep this file under 200 lines (first 200 lines auto-included in system prompt)
- Remove outdated entries when adding new ones

## Learnings
EOF
        fi
    done

    # Write marker to prevent re-migration
    echo "migrated=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker"
    log "ORCHESTRATOR" "Learnings migration complete — marker written to $marker"
}

# Generates AGENTS.md from learnings.json and project metadata (spec-34).
# Called at phase transitions so AGENTS.md is a generated view rather than
# a manually-appended file. Preserves project metadata (name, language,
# framework, commands) from the existing AGENTS.md and replaces the learnings
# section with structured data from learnings.json.
# Enforces the 60-line AGENTS.md limit by truncating learnings if needed.
generate_agents_md() {
    local agents_file="AGENTS.md"
    local learnings_file="$AUTOMATON_DIR/learnings.json"

    # Extract project metadata from existing AGENTS.md before overwriting
    local project_name="" language="" framework=""
    local cmd_build="" cmd_test="" cmd_lint=""

    if [ -f "$agents_file" ]; then
        project_name=$(grep -m1 '^- Project:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        language=$(grep -m1 '^- Language:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        framework=$(grep -m1 '^- Framework:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        cmd_build=$(grep -m1 '^- Build:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        cmd_test=$(grep -m1 '^- Test:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
        cmd_lint=$(grep -m1 '^- Lint:' "$agents_file" | cut -d: -f2- | sed 's/^ *//' || true)
    fi

    # Fall back to directory name if project name not set or still placeholder
    if [ -z "$project_name" ] || [ "$project_name" = "your-project" ]; then
        project_name=$(basename "$(pwd)")
    fi

    # Count completed runs from run-summaries/ (may not exist yet)
    local run_count=0
    if [ -d "$AUTOMATON_DIR/run-summaries" ]; then
        run_count=$(find "$AUTOMATON_DIR/run-summaries" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
        run_count=$(echo "$run_count" | tr -d ' ')
    fi

    # Build learnings lines from learnings.json (active, high confidence first)
    local learnings_lines=""
    if [ -f "$learnings_file" ]; then
        learnings_lines=$(jq -r '
            .entries
            | map(select(.active == true))
            | sort_by(if .confidence == "high" then 0
                      elif .confidence == "medium" then 1
                      else 2 end)
            | .[]
            | "- " + .summary
        ' "$learnings_file" 2>/dev/null | head -40 || true)
    fi

    # Build recent activity from run-summaries/ (last 3 runs)
    local activity_lines=""
    if [ -d "$AUTOMATON_DIR/run-summaries" ]; then
        # shellcheck disable=SC2012
        activity_lines=$(ls -t "$AUTOMATON_DIR/run-summaries/"*.json 2>/dev/null \
            | head -3 \
            | while IFS= read -r f; do
                jq -r '"- " + .run_id + ": " +
                    (.phases_completed | join(" → ")) +
                    " (" + (.tasks_completed | tostring) + " tasks)"' "$f" 2>/dev/null || true
            done || true)
    fi

    # Assemble AGENTS.md into a temp file
    {
        echo "# Operational Guide"
        echo ""
        echo "## Project"
        echo ""
        echo "- Project: $project_name"
        [ -n "$language" ] && echo "- Language: $language"
        [ -n "$framework" ] && echo "- Framework: $framework"
        [ -n "${current_phase:-}" ] && echo "- Current Phase: $current_phase"
        [ "$run_count" -gt 0 ] && echo "- Total Runs: $run_count"
        echo ""
        echo "## Commands"
        echo ""
        echo "- Build: ${cmd_build:-(not configured)}"
        echo "- Test: ${cmd_test:-(not configured)}"
        echo "- Lint: ${cmd_lint:-(not configured)}"
        echo ""
        echo "## Learnings"
        echo ""
        if [ -n "$learnings_lines" ]; then
            echo "$learnings_lines"
        else
            echo "(none yet — learnings accumulate in .automaton/learnings.json)"
        fi
        if [ -n "$activity_lines" ]; then
            echo ""
            echo "## Recent Activity"
            echo ""
            echo "$activity_lines"
        fi
    } > "${agents_file}.tmp"

    # Enforce 60-line limit
    local line_count
    line_count=$(wc -l < "${agents_file}.tmp")
    line_count=$(echo "$line_count" | tr -d ' ')

    if [ "$line_count" -gt 60 ]; then
        head -59 "${agents_file}.tmp" > "${agents_file}.tmp2"
        echo "(truncated — full data in .automaton/learnings.json)" >> "${agents_file}.tmp2"
        mv "${agents_file}.tmp2" "$agents_file"
    else
        mv "${agents_file}.tmp" "$agents_file"
    fi

    log "ORCHESTRATOR" "AGENTS.md regenerated from learnings.json (${line_count} lines)"
}

# ---------------------------------------------------------------------------
# Self-Targeting Mode (spec-25)
# ---------------------------------------------------------------------------

# Initializes the improvement backlog if it doesn't exist.
_self_init_backlog() {
    local backlog="$AUTOMATON_DIR/backlog.md"
    if [ -f "$backlog" ]; then
        return 0
    fi

    mkdir -p "$AUTOMATON_DIR"
    cat > "$backlog" <<'BACKLOG'
# Improvement Backlog

## Prompt Improvements
- [ ] Reduce prompt sizes across all phases for token efficiency

## Architecture Improvements
- [ ] Extract budget functions into sourced module
- [ ] Extract self-build functions into sourced module

## Configuration Improvements
- [ ] Add validation for all config fields at load time

## Performance Improvements
- [ ] Reduce jq invocations by batching reads

## Auto-generated
BACKLOG

    log "ORCHESTRATOR" "Self-build: initialized improvement backlog at $backlog"
}

# Shows --self --continue recommendation: estimates token cost for the
# highest-priority backlog item and shows whether it's safe to run.
_self_continue_recommendation() {
    local backlog="$AUTOMATON_DIR/backlog.md"
    if [ ! -f "$backlog" ]; then
        echo "No backlog found. Run --self first to initialize."
        exit 0
    fi

    local next_task
    next_task=$(grep '^\- \[ \]' "$backlog" | head -1 | sed 's/^- \[ \] //')

    if [ -z "$next_task" ]; then
        echo "Backlog is empty. No improvement tasks remain."
        exit 0
    fi

    echo "Next backlog item: $next_task"
    echo ""

    # Check remaining allowance
    if [ "$BUDGET_MODE" = "allowance" ] && [ -f "$AUTOMATON_DIR/budget.json" ]; then
        local remaining effective pct daily_pace
        remaining=$(jq '.tokens_remaining // 0' "$AUTOMATON_DIR/budget.json")
        effective=$(jq '.limits.effective_allowance // 1' "$AUTOMATON_DIR/budget.json")
        pct=$(awk -v r="$remaining" -v e="$effective" 'BEGIN { printf "%d", (r/e)*100 }')
        daily_pace=$(_calculate_daily_budget)
        echo "Remaining weekly allowance: $remaining tokens ($pct%)"
        echo "Daily pace: $daily_pace tokens/day"

        if [ "$daily_pace" -lt 500000 ]; then
            echo "Recommendation: Low daily budget (${daily_pace} tokens). Consider waiting for reset."
        elif [ "$pct" -gt 30 ]; then
            echo "Recommendation: Safe to run - $pct% of remaining allowance"
        elif [ "$pct" -gt 10 ]; then
            echo "Recommendation: Proceed with caution - only $pct% remaining"
        else
            echo "Recommendation: Low allowance ($pct%). Consider waiting for reset."
        fi
    else
        echo "Budget mode: api (cost-based). Run at your discretion."
    fi
}

# ---------------------------------------------------------------------------
# Run Summaries (spec-34)
# ---------------------------------------------------------------------------

# Calculates test coverage metrics from IMPLEMENTATION_PLAN.md annotations.
# Parses <!-- test: path --> and <!-- test: none --> markers to count:
# - tasks_with_tests: tasks annotated with a test file that exists on disk
# - tasks_without_tests: tasks annotated with a test file that does NOT exist
# - tasks_exempt: tasks annotated with <!-- test: none -->
# - tasks_unannotated: tasks with no test annotation at all
# Also checks test_results.json for passing/failing counts.
# WHY: coverage tracking ensures test discipline is maintained across runs
# and reveals testing gaps (spec-36 §6).
# Outputs: JSON object to stdout
calculate_test_coverage() {
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    local tasks_with_tests=0
    local tasks_without_tests=0
    local tasks_exempt=0
    local tasks_unannotated=0
    local tests_passing=0
    local tests_failing=0

    if [ -f "$plan_file" ]; then
        # Process each incomplete and completed task line
        while IFS= read -r line; do
            if echo "$line" | grep -q '<!-- test: none -->'; then
                tasks_exempt=$((tasks_exempt + 1))
            elif echo "$line" | grep -q '<!-- test:'; then
                # Extract test file path
                local test_path
                test_path=$(echo "$line" | sed -n 's/.*<!-- test: \([^ ]*\) -->.*/\1/p')
                if [ -n "$test_path" ] && [ -f "$test_path" ]; then
                    tasks_with_tests=$((tasks_with_tests + 1))
                else
                    tasks_without_tests=$((tasks_without_tests + 1))
                fi
            else
                tasks_unannotated=$((tasks_unannotated + 1))
            fi
        done < <(grep -E '^\- \[(x| )\]' "$plan_file" 2>/dev/null || true)
    fi

    # Check test results from test_results.json if it exists
    local results_file="$AUTOMATON_DIR/test_results.json"
    if [ -f "$results_file" ]; then
        tests_passing=$(jq '[.[] | select(.result == "pass")] | length' "$results_file" 2>/dev/null || echo 0)
        tests_failing=$(jq '[.[] | select(.result == "fail")] | length' "$results_file" 2>/dev/null || echo 0)
    fi

    # Calculate coverage ratio: tasks_with_tests / (tasks_with_tests + tasks_without_tests)
    local testable_tasks=$((tasks_with_tests + tasks_without_tests))
    local coverage_ratio="0.00"
    if [ "$testable_tasks" -gt 0 ]; then
        coverage_ratio=$(awk -v tw="$tasks_with_tests" -v tt="$testable_tasks" 'BEGIN { printf "%.2f", tw / tt }')
    fi

    jq -n \
        --argjson tasks_with_tests "$tasks_with_tests" \
        --argjson tasks_without_tests "$tasks_without_tests" \
        --argjson tasks_exempt "$tasks_exempt" \
        --argjson tasks_unannotated "$tasks_unannotated" \
        --argjson coverage_ratio "$coverage_ratio" \
        --argjson tests_passing "$tests_passing" \
        --argjson tests_failing "$tests_failing" \
        '{
            tasks_with_tests: $tasks_with_tests,
            tasks_without_tests: $tasks_without_tests,
            tasks_exempt: $tasks_exempt,
            tasks_unannotated: $tasks_unannotated,
            coverage_ratio: $coverage_ratio,
            tests_passing: $tests_passing,
            tests_failing: $tests_failing
        }'
}

# Writes a per-run summary JSON to .automaton/run-summaries/.
# Captures: phases completed, iterations, tokens, cost, learnings, git commits,
# and test coverage metrics (spec-36 §6).
# Called at the end of run_orchestration() and from _handle_shutdown().
# Args: [exit_code] (default: 0)
write_run_summary() {
    local run_exit_code="${1:-0}"
    local summaries_dir="$AUTOMATON_DIR/run-summaries"
    mkdir -p "$summaries_dir"

    # Build run_id from started_at timestamp (colons → hyphens for filename safety)
    local run_ts="${started_at:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local run_id
    run_id="run-$(echo "$run_ts" | tr ':' '-')"
    local summary_file="$summaries_dir/${run_id}.json"

    local completed_at
    completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Phases completed from phase_history variable
    local phases_json="[]"
    if [ -n "${phase_history:-}" ] && [ "$phase_history" != "[]" ]; then
        phases_json=$(echo "$phase_history" | jq -c '[.[].phase]')
    fi

    # Task counts from IMPLEMENTATION_PLAN.md
    local tasks_completed=0 tasks_remaining=0
    local plan_file="${PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
    if [ -f "$plan_file" ]; then
        tasks_completed=$(grep -c '^\- \[x\]' "$plan_file" 2>/dev/null) || tasks_completed=0
        tasks_remaining=$(grep -c '^\- \[ \]' "$plan_file" 2>/dev/null) || tasks_remaining=0
    fi

    # Token usage from budget.json
    local input_tokens=0 output_tokens=0 cache_create=0 cache_read=0 cost_usd="0.00"
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ -f "$budget_file" ]; then
        input_tokens=$(jq '.used.total_input // 0' "$budget_file")
        output_tokens=$(jq '.used.total_output // 0' "$budget_file")
        cache_create=$(jq '.used.total_cache_create // 0' "$budget_file")
        cache_read=$(jq '.used.total_cache_read // 0' "$budget_file")
        cost_usd=$(jq '.used.estimated_cost_usd // 0' "$budget_file")
    fi

    # Learnings added during this run (created_at >= started_at)
    local learnings_added=0 new_learnings_json="[]"
    local learnings_file="$AUTOMATON_DIR/learnings.json"
    if [ -f "$learnings_file" ]; then
        new_learnings_json=$(jq -c --arg since "$run_ts" '
            [.entries[] | select(.created_at >= $since) | .id]
        ' "$learnings_file" 2>/dev/null || echo "[]")
        learnings_added=$(echo "$new_learnings_json" | jq 'length')
    fi

    # Git commits since run started
    local commits_json="[]"
    if [ -n "${run_ts:-}" ]; then
        local raw_commits
        raw_commits=$(git log --oneline --since="$run_ts" --format="%h" 2>/dev/null || true)
        if [ -n "$raw_commits" ]; then
            commits_json=$(echo "$raw_commits" | jq -R -s -c 'split("\n") | map(select(. != ""))')
        fi
    fi

    # Calculate test coverage metrics (spec-36 §6)
    local test_coverage_json
    test_coverage_json=$(calculate_test_coverage 2>/dev/null || echo '{}')

    # Write the summary JSON
    jq -n \
        --arg run_id "$run_id" \
        --arg started_at "$run_ts" \
        --arg completed_at "$completed_at" \
        --argjson exit_code "$run_exit_code" \
        --argjson phases_completed "$phases_json" \
        --argjson iterations_total "${iteration:-0}" \
        --argjson tasks_completed "$tasks_completed" \
        --argjson tasks_remaining "$tasks_remaining" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --argjson cache_create "$cache_create" \
        --argjson cache_read "$cache_read" \
        --argjson cost_usd "$cost_usd" \
        --argjson learnings_added "$learnings_added" \
        --argjson new_learnings "$new_learnings_json" \
        --argjson git_commits "$commits_json" \
        --argjson test_coverage "$test_coverage_json" \
        '{
            run_id: $run_id,
            started_at: $started_at,
            completed_at: $completed_at,
            exit_code: $exit_code,
            phases_completed: $phases_completed,
            iterations_total: $iterations_total,
            tasks_completed: $tasks_completed,
            tasks_remaining: $tasks_remaining,
            tokens_used: {
                input: $input_tokens,
                output: $output_tokens,
                cache_read: $cache_read,
                cache_create: $cache_create
            },
            estimated_cost_usd: $cost_usd,
            learnings_added: $learnings_added,
            new_learnings: $new_learnings,
            git_commits: $git_commits,
            test_coverage: $test_coverage
        }' > "$summary_file"

    log "ORCHESTRATOR" "Run summary written to $summary_file"

    # Accumulate into persistent budget history (spec-34)
    update_budget_history "$run_id" "$input_tokens" "$output_tokens" \
        "$cache_create" "$cache_read" "$cost_usd"

    # Increment run count in cross-project allowance tracking (spec-35 §5)
    _increment_cross_project_run_count
}

# Accumulates per-run token and cost data into .automaton/budget-history.json.
# Appends a run entry and updates/creates the weekly total for the current week.
# WHY: budget.json is ephemeral and reset each run; budget-history.json persists
# across runs for cost analysis and weekly allowance tracking.
# Args: run_id input_tokens output_tokens cache_create cache_read cost_usd
update_budget_history() {
    local run_id="$1" input_tokens="$2" output_tokens="$3"
    local cache_create="$4" cache_read="$5" cost_usd="$6"

    local history_file="$AUTOMATON_DIR/budget-history.json"
    local tmp="$AUTOMATON_DIR/budget-history.json.tmp"

    # Initialize file if missing or empty
    if [ ! -f "$history_file" ] || [ ! -s "$history_file" ]; then
        echo '{"runs":[],"weekly_totals":[]}' > "$history_file"
    fi

    local total_tokens=$((input_tokens + output_tokens))

    # Calculate cache hit ratio: cache_read / (cache_read + input + cache_create)
    local cache_hit_ratio="0.00"
    local cache_denominator=$((cache_read + input_tokens + cache_create))
    if [ "$cache_denominator" -gt 0 ]; then
        cache_hit_ratio=$(awk -v cr="$cache_read" -v denom="$cache_denominator" \
            'BEGIN { printf "%.2f", cr / denom }')
    fi

    # Build per-phase breakdown and utilization stats from budget.json history
    local phases_json="{}"
    local peak_utilization="0" avg_utilization="0"
    local total_bootstrap_saved="0" avg_bootstrap_ms="0"
    local budget_file="$AUTOMATON_DIR/budget.json"
    if [ -f "$budget_file" ]; then
        phases_json=$(jq -c '
            .history // [] | group_by(.phase) |
            map({
                key: .[0].phase,
                value: {
                    tokens: ([.[].input_tokens] | add) + ([.[].output_tokens] | add),
                    iterations: length
                }
            }) | from_entries
        ' "$budget_file" 2>/dev/null || echo "{}")

        # Extract peak and average context utilization from per-iteration history (spec-33)
        peak_utilization=$(jq '
            [.history // [] | .[].estimated_utilization // 0] |
            if length > 0 then max else 0 end
        ' "$budget_file" 2>/dev/null || echo "0")
        avg_utilization=$(jq '
            [.history // [] | .[].estimated_utilization // 0] |
            if length > 0 then (add / length * 10 | round / 10) else 0 end
        ' "$budget_file" 2>/dev/null || echo "0")

        # Aggregate bootstrap metrics from per-iteration history (spec-37)
        total_bootstrap_saved=$(jq '
            [.history // [] | .[].bootstrap_tokens_saved // 0] | add // 0
        ' "$budget_file" 2>/dev/null || echo "0")
        avg_bootstrap_ms=$(jq '
            [.history // [] | .[].bootstrap_time_ms // 0] |
            if length > 0 then (add / length | round) else 0 end
        ' "$budget_file" 2>/dev/null || echo "0")
    fi

    # Determine current week boundaries
    local week_start week_end
    if [ "$BUDGET_MODE" = "allowance" ]; then
        week_start=$(_allowance_week_start)
        week_end=$(_allowance_week_end "$week_start")
    else
        # For API mode, use ISO week (Monday-based)
        week_start=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
        week_end=$(date -d "$week_start + 6 days" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
    fi

    # Append run entry and update weekly total atomically
    jq \
        --arg run_id "$run_id" \
        --arg mode "${BUDGET_MODE:-api}" \
        --argjson tokens_used "$total_tokens" \
        --argjson cost "$cost_usd" \
        --arg cache_hit_ratio "$cache_hit_ratio" \
        --argjson phases "$phases_json" \
        --argjson peak_util "$peak_utilization" \
        --argjson avg_util "$avg_utilization" \
        --arg week_start "$week_start" \
        --arg week_end "$week_end" \
        --argjson bootstrap_saved "$total_bootstrap_saved" \
        --argjson bootstrap_avg_ms "$avg_bootstrap_ms" \
        '
        # Append run entry
        .runs += [{
            run_id: $run_id,
            mode: $mode,
            tokens_used: $tokens_used,
            estimated_cost_usd: ($cost | tonumber),
            cache_hit_ratio: ($cache_hit_ratio | tonumber),
            peak_utilization: $peak_util,
            avg_utilization: $avg_util,
            phases: $phases,
            bootstrap_tokens_saved: $bootstrap_saved,
            bootstrap_avg_time_ms: $bootstrap_avg_ms
        }] |

        # Update or create weekly total
        if (.weekly_totals | map(.week_start) | index($week_start)) then
            .weekly_totals |= map(
                if .week_start == $week_start then
                    .tokens_used += $tokens_used |
                    .runs += 1
                else . end
            )
        else
            .weekly_totals += [{
                week_start: $week_start,
                week_end: $week_end,
                tokens_used: $tokens_used,
                runs: 1
            }]
        end
    ' "$history_file" > "$tmp" && mv "$tmp" "$history_file"

    log "ORCHESTRATOR" "Budget history updated: ${total_tokens} tokens, \$${cost_usd} cost"
}

# Commits persistent state files (.automaton/ tracked files) to git.
# Called at phase transitions, run completion, shutdown, and every 5 build
# iterations to ensure persistent state survives interruptions (spec-34).
commit_persistent_state() {
    local phase="${1:-$current_phase}" iter="${2:-$iteration}"

    # Persistent files that should be tracked in git
    local -a persistent_files=(
        "$AUTOMATON_DIR/budget-history.json"
        "$AUTOMATON_DIR/learnings.json"
        "$AUTOMATON_DIR/run-summaries"
        "$AUTOMATON_DIR/test_results.json"
        "$AUTOMATON_DIR/self_modifications.json"
    )

    # Stage only files that exist
    local staged=false
    for f in "${persistent_files[@]}"; do
        if [ -e "$f" ]; then
            git add "$f" 2>/dev/null && staged=true
        fi
    done

    # Also stage AGENTS.md since it is generated from learnings.json
    if [ -f "AGENTS.md" ]; then
        git add "AGENTS.md" 2>/dev/null && staged=true
    fi

    if [ "$staged" != "true" ]; then
        return 0
    fi

    # Only commit if there are staged changes
    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "automaton: state checkpoint — ${phase} iteration ${iter}" 2>/dev/null || true
        log "ORCHESTRATOR" "Persistent state committed (${phase} iter ${iter})"
    fi
}

# ---------------------------------------------------------------------------
# Run Journal & Performance Tracking (spec-26)
# ---------------------------------------------------------------------------

# Archives the current run data to .automaton/journal/run-{NNN}/.
# Called at the end of run_orchestration().
archive_run_journal() {
    local journal_dir="$AUTOMATON_DIR/journal"
    mkdir -p "$journal_dir"

    # Determine next run number
    local run_num=1
    if [ -d "$journal_dir" ]; then
        local latest
        latest=$(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | tail -1 || true)
        if [ -n "$latest" ]; then
            run_num=$(( $(basename "$latest" | sed 's/run-//') + 1 ))
        fi
    fi

    local run_dir
    run_dir=$(printf "%s/run-%03d" "$journal_dir" "$run_num")
    mkdir -p "$run_dir"

    # Copy run artifacts
    cp "$AUTOMATON_DIR/budget.json" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/state.json" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/session.log" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/context_summary.md" "$run_dir/" 2>/dev/null || true
    cp "$AUTOMATON_DIR/self_modifications.json" "$run_dir/" 2>/dev/null || true

    # Generate performance metrics
    _generate_run_metadata "$run_dir"

    # Auto-generate backlog entries from performance data (spec-26)
    if [ "${ARG_SELF:-false}" = "true" ]; then
        _auto_generate_backlog "$run_dir"
        _check_convergence "$journal_dir"
    fi

    # Enforce journal retention limit
    local max_runs="${JOURNAL_MAX_RUNS:-50}"
    local run_count
    run_count=$(ls -1d "$journal_dir"/run-* 2>/dev/null | wc -l)
    if [ "$run_count" -gt "$max_runs" ]; then
        local to_remove=$((run_count - max_runs))
        ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | head -"$to_remove" | while read -r old_run; do
            rm -rf "$old_run"
        done
        log "ORCHESTRATOR" "Journal: pruned $to_remove old runs (max: $max_runs)"
    fi

    log "ORCHESTRATOR" "Run archived to $run_dir"
}

# Generates run_metadata.json with performance metrics.
_generate_run_metadata() {
    local run_dir="$1"
    local budget_file="$run_dir/budget.json"
    local state_file="$run_dir/state.json"

    if [ ! -f "$budget_file" ]; then
        echo '{}' > "$run_dir/run_metadata.json"
        return
    fi

    local total_input total_output total_tokens history_count
    total_input=$(jq '.used.total_input // 0' "$budget_file")
    total_output=$(jq '.used.total_output // 0' "$budget_file")
    total_tokens=$((total_input + total_output))
    history_count=$(jq '.history | length' "$budget_file")

    # Tasks completed: count successful build iterations
    local tasks_completed
    tasks_completed=$(jq '[.history[] | select(.phase == "build" and .status == "success")] | length' "$budget_file")

    # Tokens per completed task
    local tokens_per_task=0
    if [ "$tasks_completed" -gt 0 ]; then
        tokens_per_task=$((total_tokens / tasks_completed))
    fi

    # Stall rate
    local stall_count total_build_iters stall_rate
    stall_count=$(jq '.stall_count // 0' "$state_file" 2>/dev/null || echo 0)
    total_build_iters=$(jq '[.history[] | select(.phase == "build")] | length' "$budget_file")
    if [ "$total_build_iters" -gt 0 ]; then
        stall_rate=$(awk -v s="$stall_count" -v t="$total_build_iters" 'BEGIN { printf "%.2f", s/t }')
    else
        stall_rate="0.00"
    fi

    # Average iteration duration
    local avg_duration
    if [ "$history_count" -gt 0 ]; then
        avg_duration=$(jq '[.history[].duration_seconds] | add / length | floor' "$budget_file")
    else
        avg_duration=0
    fi

    # Prompt overhead ratio (estimated: prompt tokens are a portion of input)
    local prompt_overhead="0.00"

    # First-pass success rate
    local review_rework_count first_pass_rate
    review_rework_count=$(jq '.replan_count // 0' "$state_file" 2>/dev/null || echo 0)
    if [ "$tasks_completed" -gt 0 ]; then
        local successful=$((tasks_completed - review_rework_count))
        if [ "$successful" -lt 0 ]; then successful=0; fi
        first_pass_rate=$(awk -v s="$successful" -v t="$tasks_completed" 'BEGIN { printf "%.2f", s/t }')
    else
        first_pass_rate="0.00"
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg ts "$timestamp" \
        --argjson total_tokens "$total_tokens" \
        --argjson tasks_completed "$tasks_completed" \
        --argjson tokens_per_task "$tokens_per_task" \
        --arg stall_rate "$stall_rate" \
        --arg first_pass_rate "$first_pass_rate" \
        --argjson avg_duration "$avg_duration" \
        --arg prompt_overhead "$prompt_overhead" \
        --argjson history_count "$history_count" \
        '{
            timestamp: $ts,
            total_tokens: $total_tokens,
            tasks_completed: $tasks_completed,
            tokens_per_task: $tokens_per_task,
            stall_rate: ($stall_rate | tonumber),
            first_pass_success_rate: ($first_pass_rate | tonumber),
            avg_iteration_duration_seconds: $avg_duration,
            prompt_overhead_ratio: ($prompt_overhead | tonumber),
            total_iterations: $history_count
        }' > "$run_dir/run_metadata.json"
}

# Auto-generates backlog entries from performance analysis.
_auto_generate_backlog() {
    local run_dir="$1"
    local metadata="$run_dir/run_metadata.json"
    local backlog="$AUTOMATON_DIR/backlog.md"

    if [ ! -f "$metadata" ] || [ ! -f "$backlog" ]; then
        return
    fi

    local stall_rate tokens_per_task
    stall_rate=$(jq '.stall_rate // 0' "$metadata")
    tokens_per_task=$(jq '.tokens_per_task // 0' "$metadata")

    local new_items=""

    # Stall rate > 20% → improve prompt task
    local stall_high
    stall_high=$(awk -v s="$stall_rate" 'BEGIN { print (s > 0.20) ? "yes" : "no" }')
    if [ "$stall_high" = "yes" ]; then
        new_items="${new_items}\n- [ ] Investigate: stall rate ${stall_rate} exceeds 20% — review build prompt clarity"
    fi

    # Check if previous run exists for regression comparison
    local prev_run
    prev_run=$(ls -1d "$AUTOMATON_DIR/journal"/run-* 2>/dev/null | sort -t- -k2 -n | tail -2 | head -1 || true)
    if [ -n "$prev_run" ] && [ -f "$prev_run/run_metadata.json" ]; then
        local prev_tpt
        prev_tpt=$(jq '.tokens_per_task // 0' "$prev_run/run_metadata.json")
        if [ "$tokens_per_task" -gt 0 ] && [ "$prev_tpt" -gt 0 ]; then
            local regression
            regression=$(awk -v curr="$tokens_per_task" -v prev="$prev_tpt" \
                'BEGIN { print (curr > prev * 1.1) ? "yes" : "no" }')
            if [ "$regression" = "yes" ]; then
                new_items="${new_items}\n- [ ] Investigate: token efficiency regression — ${tokens_per_task} tokens/task vs previous ${prev_tpt}"
            fi
        fi
    fi

    if [ -n "$new_items" ]; then
        echo -e "$new_items" >> "$backlog"
        log "ORCHESTRATOR" "Auto-generated backlog entries from performance analysis"
    fi
}

# Convergence detection: warns if last 3 runs show no improvement.
_check_convergence() {
    local journal_dir="$1"

    local recent_runs
    recent_runs=$(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | tail -3)
    local run_count
    run_count=$(echo "$recent_runs" | grep -c .) || run_count=0

    if [ "$run_count" -lt 3 ]; then
        return 0
    fi

    # Compare tokens_per_task across last 3 runs
    local improving=false
    local prev_tpt=0
    while IFS= read -r run; do
        if [ -f "$run/run_metadata.json" ]; then
            local tpt
            tpt=$(jq '.tokens_per_task // 0' "$run/run_metadata.json")
            if [ "$prev_tpt" -gt 0 ] && [ "$tpt" -lt "$prev_tpt" ]; then
                improving=true
            fi
            prev_tpt="$tpt"
        fi
    done <<< "$recent_runs"

    if [ "$improving" = "false" ]; then
        log "ORCHESTRATOR" "WARNING: Self-improvement may have converged. Last 3 runs show no measurable improvement. Consider manual review of backlog priorities."
    fi
}

# Displays run history table and performance trends.
# Called by --stats CLI command.
display_stats() {
    local journal_dir="$AUTOMATON_DIR/journal"

    if [ ! -d "$journal_dir" ] || [ -z "$(ls -d "$journal_dir"/run-* 2>/dev/null)" ]; then
        echo "No run history found. Complete at least one run first."
        exit 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " automaton — Run History"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-8s %-22s %-8s %-12s %-10s %-10s %-8s\n" \
        "Run" "Timestamp" "Tasks" "Tokens/Task" "Stall%" "1stPass%" "AvgSec"
    echo "-------  --------------------  ------  ----------  --------  --------  ------"

    for run_dir in $(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n); do
        local meta="$run_dir/run_metadata.json"
        if [ ! -f "$meta" ]; then
            continue
        fi

        local run_name ts tasks tpt stall fp avg_dur
        run_name=$(basename "$run_dir")
        ts=$(jq -r '.timestamp // "?"' "$meta" | cut -c1-19)
        tasks=$(jq '.tasks_completed // 0' "$meta")
        tpt=$(jq '.tokens_per_task // 0' "$meta")
        stall=$(jq '.stall_rate // 0' "$meta" | awk '{printf "%.0f", $1*100}')
        fp=$(jq '.first_pass_success_rate // 0' "$meta" | awk '{printf "%.0f", $1*100}')
        avg_dur=$(jq '.avg_iteration_duration_seconds // 0' "$meta")

        printf "%-8s %-22s %-8s %-12s %-10s %-10s %-8s\n" \
            "$run_name" "$ts" "$tasks" "$tpt" "${stall}%" "${fp}%" "${avg_dur}s"
    done

    echo ""

    # Trend analysis
    echo "Trends (last 5 runs):"
    local recent_tpts=()
    local recent_stalls=()
    for run_dir in $(ls -1d "$journal_dir"/run-* 2>/dev/null | sort -t- -k2 -n | tail -5); do
        local meta="$run_dir/run_metadata.json"
        if [ -f "$meta" ]; then
            recent_tpts+=($(jq '.tokens_per_task // 0' "$meta"))
            recent_stalls+=($(jq '.stall_rate // 0' "$meta"))
        fi
    done

    if [ "${#recent_tpts[@]}" -ge 2 ]; then
        local first_tpt="${recent_tpts[0]}"
        local last_tpt="${recent_tpts[${#recent_tpts[@]}-1]}"
        if [ "$first_tpt" -gt "$last_tpt" ] 2>/dev/null; then
            echo "  Tokens/task: improving (${first_tpt} -> ${last_tpt})"
        elif [ "$first_tpt" -lt "$last_tpt" ] 2>/dev/null; then
            echo "  Tokens/task: regressing (${first_tpt} -> ${last_tpt})"
        else
            echo "  Tokens/task: stable (${last_tpt})"
        fi
    fi

    echo ""
    exit 0
}

# Escalation: when automated recovery fails, stop cleanly and hand off to human.
# Logs the escalation, marks it in IMPLEMENTATION_PLAN.md for visibility,
# saves state, commits everything, and exits with code 3.
#
# Usage: escalate "description of what went wrong"
# Exits: always exits with code 3 (human intervention required)
escalate() {
    local description="$1"
    log "ORCHESTRATOR" "ESCALATION: $description"

    # Structured work log: escalation (spec-55)
    emit_event "escalation" "{\"reason\":\"${description}\",\"target\":\"user\"}"

    # Notify: escalation and run_failed (spec-52)
    send_notification "escalation" "${current_phase:-unknown}" "failure" "Escalation: $description"
    send_notification "run_failed" "${current_phase:-unknown}" "failure" "$description"

    # Mark the escalation in the plan file for human visibility
    local plan_file="IMPLEMENTATION_PLAN.md"
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi
    {
        echo ""
        echo "## ESCALATION"
        echo ""
        echo "ESCALATION: $description"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Phase: $current_phase, Iteration: $iteration"
    } >> "$plan_file"

    # Persist current state for --resume
    write_state

    # Commit state and plan so no work is lost on exit
    git add IMPLEMENTATION_PLAN.md "$AUTOMATON_DIR/state.json" "$AUTOMATON_DIR/session.log" "$AUTOMATON_DIR/budget.json" 2>/dev/null || true
    git commit -m "automaton: escalation - $description" 2>/dev/null || true

    exit 3
}

# Focused fix strategy: when the review→build loop has failed twice, instead
# of immediately escalating, extract only the specific failing issues and create
# a minimal, targeted task list for one more build cycle. This gives the system
# one last chance to self-heal before requiring human intervention.
#
# Strategy:
# 1. Extract failing test names and unchecked review tasks from the plan
# 2. Create a focused task list with ONLY those specific fixes
# 3. Clear iteration memory to give the builder fresh context
# 4. Set max iterations for this focused build to 3 (tight scope)
attempt_focused_fix() {
    local plan_file="IMPLEMENTATION_PLAN.md"
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    # Extract only unchecked tasks (these are the review-identified issues)
    local unchecked_tasks
    unchecked_tasks=$(grep '^\- \[ \]' "$plan_file" 2>/dev/null || true)

    # Extract failing test names from test_results.json
    local failing_tests=""
    if [ -f "$AUTOMATON_DIR/test_results.json" ]; then
        failing_tests=$(jq -r '.[]? | select(.status == "failed") | .test // empty' \
            "$AUTOMATON_DIR/test_results.json" 2>/dev/null || true)
    fi

    # Create a focused fix section in the plan
    {
        echo ""
        echo "## Focused Fix (Auto-Generated)"
        echo ""
        echo "The following issues were identified after 2 review cycles."
        echo "This is a targeted fix attempt. Fix ONLY these specific issues:"
        echo ""
        if [ -n "$failing_tests" ]; then
            echo "### Failing Tests"
            echo "$failing_tests" | while IFS= read -r test; do
                [ -z "$test" ] && continue
                echo "- [ ] Fix failing test: $test"
            done
            echo ""
        fi
        if [ -n "$unchecked_tasks" ]; then
            echo "### Remaining Review Issues"
            echo "$unchecked_tasks"
            echo ""
        fi
        echo "**IMPORTANT**: Do NOT refactor or improve unrelated code. Fix ONLY the items listed above."
    } >> "$plan_file"

    # Clear iteration memory to give fresh context
    : > "$AUTOMATON_DIR/iteration_memory.md" 2>/dev/null || true

    # Override max iterations for the focused build to keep it tight
    EXEC_MAX_ITER_BUILD=3

    local _review_issues _failing_count
    _review_issues=$(echo "$unchecked_tasks" | grep -c '\[ \]' 2>/dev/null) || _review_issues=0
    _failing_count=$(echo "$failing_tests" | grep -c . 2>/dev/null) || _failing_count=0
    log "ORCHESTRATOR" "Focused fix: created targeted task list with $_review_issues review issues and $_failing_count failing tests. Max 3 build iterations."

    # Commit the focused fix plan
    git add "$plan_file" 2>/dev/null || true
    git commit -m "automaton: focused fix attempt after 2 failed reviews" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Context Efficiency (spec-24)
# ---------------------------------------------------------------------------

# Generates .automaton/context_summary.md at each phase transition.
# Contains: project state, completed tasks, remaining tasks, key decisions,
# recently modified files.
generate_context_summary() {
    local summary_file="$AUTOMATON_DIR/context_summary.md"
    local plan_file="IMPLEMENTATION_PLAN.md"

    # In self-build mode, use backlog
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    {
        echo "# Context Summary"
        echo ""
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Phase: $current_phase | Iteration: $iteration"
        echo ""

        # Completed tasks
        echo "## Completed Tasks"
        if [ -f "$plan_file" ]; then
            grep '\[x\]' "$plan_file" | tail -10 || echo "None yet."
        else
            echo "No plan file found."
        fi
        echo ""

        # Remaining tasks
        echo "## Remaining Tasks"
        if [ -f "$plan_file" ]; then
            grep '\[ \]' "$plan_file" | head -10 || echo "All tasks complete."
        else
            echo "No plan file found."
        fi
        echo ""

        # Recently modified files
        echo "## Recently Modified Files"
        git log --oneline --name-only -5 2>/dev/null | grep -v '^[a-f0-9]' | sort -u | head -15 || echo "No git history."
        echo ""

        # Budget status
        echo "## Budget Status"
        if [ -f "$AUTOMATON_DIR/budget.json" ]; then
            if [ "$BUDGET_MODE" = "allowance" ]; then
                local used remaining daily_pace
                used=$(jq '.tokens_used_this_week' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                remaining=$(jq '.tokens_remaining' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                daily_pace=$(jq '.limits.daily_budget // 0' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                echo "Mode: allowance | Used this week: $used | Remaining: $remaining | Daily pace: $daily_pace"
            else
                local cost
                cost=$(jq '.used.estimated_cost_usd' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "?")
                echo "Mode: api | Cost so far: \$$cost / \$$BUDGET_MAX_USD"
            fi
        fi
    } > "$summary_file"

    log "ORCHESTRATOR" "Context summary generated: $summary_file"
}

# Generates .automaton/progress.txt at each iteration (spec-33).
# A human-readable status file that any agent in any context window can read
# to understand full project state without loading history.
generate_progress_txt() {
    local progress_file="$AUTOMATON_DIR/progress.txt"
    local plan_file="IMPLEMENTATION_PLAN.md"

    # In self-build mode, use backlog
    if [ "${ARG_SELF:-false}" = "true" ] && [ -f "$AUTOMATON_DIR/backlog.md" ]; then
        plan_file="$AUTOMATON_DIR/backlog.md"
    fi

    # Task counts
    local tasks_completed=0 tasks_remaining=0 tasks_total=0
    if [ -f "$plan_file" ]; then
        tasks_completed=$(grep -c '\[x\]' "$plan_file" 2>/dev/null) || tasks_completed=0
        tasks_remaining=$(grep -c '\[ \]' "$plan_file" 2>/dev/null) || tasks_remaining=0
        tasks_total=$((tasks_completed + tasks_remaining))
    fi

    # Last completed task (most recent [x] line, stripped of markdown)
    local last_completed="None yet"
    if [ -f "$plan_file" ]; then
        local raw
        raw=$(grep '\[x\]' "$plan_file" | tail -1 | sed 's/^- \[x\] //' | sed 's/ (WHY:.*//' 2>/dev/null || true)
        if [ -n "$raw" ]; then
            last_completed="$raw"
        fi
    fi

    # Next pending task (first [ ] line, stripped of markdown)
    local next_pending="None"
    if [ -f "$plan_file" ]; then
        local raw_next
        raw_next=$(grep '\[ \]' "$plan_file" | head -1 | sed 's/^- \[ \] //' | sed 's/ (WHY:.*//' 2>/dev/null || true)
        if [ -n "$raw_next" ]; then
            next_pending="$raw_next"
        fi
    fi

    # Blocked info from stall/failure state
    local blocked_info="None"
    if [ "${stall_count:-0}" -ge 2 ]; then
        blocked_info="Stall detected ($stall_count consecutive iterations with no changes)"
    elif [ "${consecutive_failures:-0}" -ge 2 ]; then
        blocked_info="Consecutive failures ($consecutive_failures)"
    fi

    # Key decisions from recent git commits
    local key_decisions=""
    key_decisions=$(git log --oneline -5 --format="%s" 2>/dev/null | head -5 || true)

    # Budget info
    local budget_info="unknown"
    if [ -f "$AUTOMATON_DIR/budget.json" ]; then
        if [ "$BUDGET_MODE" = "allowance" ]; then
            local remaining
            remaining=$(jq '.tokens_remaining // "unknown"' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "unknown")
            budget_info="allowance, $remaining tokens remaining"
        else
            local cost_used
            cost_used=$(jq '.used.estimated_cost_usd // 0' "$AUTOMATON_DIR/budget.json" 2>/dev/null || echo "0")
            budget_info="api, \$$cost_used / \$$BUDGET_MAX_USD spent"
        fi
    fi

    {
        echo "# Automaton Progress"
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Phase: $current_phase (iteration $phase_iteration)"
        if [ "$current_phase" = "build" ] && [ "$EXEC_TEST_FIRST_ENABLED" = "true" ]; then
            echo "Build sub-phase: ${build_sub_phase:-implementation} (scaffold: $scaffold_iterations_done/$EXEC_TEST_SCAFFOLD_ITERATIONS done)"
        fi
        echo "Total iterations: $iteration"
        echo "Completed: $tasks_completed/$tasks_total tasks"
        echo "Last completed: $last_completed"
        echo "Next pending: $next_pending"
        echo "Currently blocked: $blocked_info"
        echo "Budget: $budget_info"
        echo ""
        echo "## Recent Commits"
        if [ -n "$key_decisions" ]; then
            echo "$key_decisions"
        else
            echo "No commits yet"
        fi
    } > "$progress_file"
}
