# Spec 17: Builder Agent

## Purpose

Define how each builder window operates during a wave. A builder is an ephemeral Claude agent that runs in a git worktree, implements a single assigned task, commits the result, and writes a result file. Builders are created per-wave and destroyed after merge. This spec covers the builder wrapper script, prompt override mechanism, worktree isolation, file ownership constraints, and commit protocol.

## Builder Wrapper Script

The conductor generates `.automaton/wave/builder-wrapper.sh` before each wave. Each builder tmux window runs this script:

```bash
#!/usr/bin/env bash
set -euo pipefail

BUILDER_NUM="$1"
WAVE_NUM="$2"
PROJECT_ROOT="$3"
ASSIGNMENTS_FILE="$PROJECT_ROOT/.automaton/wave/assignments.json"
RESULT_FILE="$PROJECT_ROOT/.automaton/wave/results/builder-${BUILDER_NUM}.json"

# Read assignment
assignment=$(jq ".assignments[$((BUILDER_NUM - 1))]" "$ASSIGNMENTS_FILE")
task=$(echo "$assignment" | jq -r '.task')
task_line=$(echo "$assignment" | jq -r '.task_line')
files_owned=$(echo "$assignment" | jq -r '.files_owned | join(", ")')

# Generate task-specific prompt header
HEADER=$(cat <<EOF
# Builder $BUILDER_NUM — Wave $WAVE_NUM

## Your Assignment
You are builder $BUILDER_NUM in a parallel build wave. You have ONE task:

**Task:** $task

## File Ownership
You may ONLY create or modify these files (and their test files):
$files_owned

Do NOT modify any other files. If your task requires changes to files outside your ownership, note this in your commit message with the prefix "NEEDS:" and complete what you can.

## Rules
- Complete this ONE task fully. No placeholders, no TODOs, no stubs.
- Only modify files in your ownership list.
- Run tests for the files you changed.
- Mark the task as [x] in IMPLEMENTATION_PLAN.md.
- Commit all changes with a descriptive message.
- Output <promise>COMPLETE</promise> when done.

---

EOF
)

# Prepend header to the standard build prompt
PROMPT_FILE=$(mktemp)
echo "$HEADER" > "$PROMPT_FILE"
cat "$PROJECT_ROOT/PROMPT_build.md" >> "$PROMPT_FILE"

# Record start time
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Run Claude agent
result=$(cat "$PROMPT_FILE" | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model "$MODEL_BUILDING" \
    --verbose 2>&1) || true

exit_code=${PIPESTATUS[1]:-$?}
completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Extract token usage
usage=$(echo "$result" | grep '"type":"result"' | tail -1)
input_tokens=$(echo "$usage" | jq -r '.usage.input_tokens // 0')
output_tokens=$(echo "$usage" | jq -r '.usage.output_tokens // 0')
cache_create=$(echo "$usage" | jq -r '.usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$usage" | jq -r '.usage.cache_read_input_tokens // 0')

# Determine status
status="success"
if [ "$exit_code" -ne 0 ]; then
    if echo "$result" | grep -qi 'rate_limit\|429\|overloaded'; then
        status="rate_limited"
    else
        status="error"
    fi
elif ! echo "$result" | grep -q '<promise>COMPLETE</promise>'; then
    status="partial"
fi

# Get git info
git_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")
files_changed=$(git diff --name-only HEAD~1 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')

# Calculate duration
start_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || echo 0)
end_epoch=$(date -d "$completed_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$completed_at" +%s 2>/dev/null || echo 0)
duration=$((end_epoch - start_epoch))

# Calculate cost (simplified — conductor recalculates with correct model pricing)
estimated_cost=$(echo "scale=2; ($input_tokens * 3 + $output_tokens * 15) / 1000000" | bc 2>/dev/null || echo "0")

# Write result file (this signals completion to the conductor)
cat > "$RESULT_FILE" <<RESULT
{
  "builder": $BUILDER_NUM,
  "wave": $WAVE_NUM,
  "status": "$status",
  "task": $(echo "$task" | jq -R .),
  "task_line": $task_line,
  "started_at": "$started_at",
  "completed_at": "$completed_at",
  "duration_seconds": $duration,
  "exit_code": $exit_code,
  "tokens": {
    "input": $input_tokens,
    "output": $output_tokens,
    "cache_create": $cache_create,
    "cache_read": $cache_read
  },
  "estimated_cost": $estimated_cost,
  "git_commit": "$git_commit",
  "files_changed": $files_changed,
  "promise_complete": $(echo "$result" | grep -q '<promise>COMPLETE</promise>' && echo "true" || echo "false")
}
RESULT

# Clean up temp prompt file
rm -f "$PROMPT_FILE"
```

## Prompt Override Mechanism

The builder's prompt is constructed by prepending a task-specific header to the standard `PROMPT_build.md`. This preserves all existing RALPH build prompt behavior while adding:

1. **Task assignment** — Tells the builder exactly which task to work on (instead of the default "pick the most important task" behavior).
2. **File ownership** — Constrains which files the builder may modify.
3. **Wave context** — Identifies the builder number and wave for logging.

The standard `PROMPT_build.md` follows after the header, providing all the usual RALPH build rules (load context, investigate, implement, validate, commit). The header overrides only the task selection step.

## Worktree Isolation

Each builder works in a dedicated git worktree:

```
.automaton/worktrees/
  builder-1/    ← full working copy, branch automaton/wave-N-builder-1
  builder-2/    ← full working copy, branch automaton/wave-N-builder-2
  builder-3/    ← full working copy, branch automaton/wave-N-builder-3
```

### Worktree Properties

- Created from `HEAD` of the main branch at wave start.
- Each worktree has its own branch (`automaton/wave-{N}-builder-{M}`).
- The builder has full read/write access within its worktree.
- The builder commits to its worktree branch. These commits are later merged by the conductor.
- The worktree is removed after merge (spec-16 cleanup step).

### What Builders Can See

Builders can read all project files (they're in a full worktree). They can see:
- `AGENTS.md`, `PRD.md`, `specs/*.md` — for context.
- `IMPLEMENTATION_PLAN.md` — to see the full plan and mark their task done.
- All source code — to understand the codebase.

### What Builders Cannot Do

- Modify files outside their `files_owned` list (enforced by prompt instruction, not filesystem).
- Read or write `.automaton/state.json` or `.automaton/budget.json` (conductor-only files).
- Communicate with other builders (no shared inbox, no inter-builder coordination).
- Spawn additional Claude agents beyond standard RALPH subagent usage.

## File Ownership Enforcement

File ownership is enforced via the prompt header instruction, not filesystem permissions. This is a soft constraint — the builder agent is instructed not to modify files outside its list, but the system must handle violations gracefully.

### Post-Build Ownership Check

After a builder completes, the conductor checks the `files_changed` list in the result file against `files_owned` in the assignment:

```bash
check_ownership() {
    local builder=$1
    local assignment=$(jq ".assignments[$((builder - 1))]" ".automaton/wave/assignments.json")
    local owned=$(echo "$assignment" | jq -r '.files_owned[]')
    local changed=$(jq -r '.files_changed[]' ".automaton/wave/results/builder-${builder}.json")

    local violations=""
    for file in $changed; do
        if ! echo "$owned" | grep -qF "$file"; then
            violations="$violations $file"
        fi
    done

    if [ -n "$violations" ]; then
        log "CONDUCTOR" "Builder $builder ownership violation: $violations"
        return 1
    fi
    return 0
}
```

### Handling Ownership Violations

If a builder modifies files outside its ownership:

1. Log the violation.
2. Check if the violated files were also modified by another builder in the same wave.
3. If no conflict: allow the change (the builder needed a file not in the initial estimate).
4. If conflict: drop the violating builder's changes to the conflicting files, keep the assigned owner's changes. Re-queue the violating builder's task.

## Commit Protocol

Each builder follows this commit protocol:

1. Stage all changed files: `git add -A`
2. Commit with a structured message:

```
automaton: wave N builder M — [task summary]

Task: [full task description]
Files: [list of files changed]
Builder: M/N
Wave: N
```

3. Only one commit per builder per wave (the builder completes one task then exits).

If the builder needs multiple commits (e.g., fixing a test failure), they are squashed by the merge protocol (spec-19).

## Builder Environment

The builder wrapper sets these environment variables:

| Variable | Value | Purpose |
|----------|-------|---------|
| `BUILDER_NUM` | 1, 2, 3... | Identifies this builder |
| `WAVE_NUM` | 1, 2, 3... | Current wave number |
| `PROJECT_ROOT` | Absolute path | Path to the main project root |
| `MODEL_BUILDING` | From config | Model to use (default: sonnet) |

## Builder Lifecycle Summary

```
tmux window created
  │
  ├── Read assignment from assignments.json
  ├── Generate task-specific prompt (header + PROMPT_build.md)
  ├── Run claude -p in worktree
  ├── Extract token usage from stream-json
  ├── Determine status (success/error/rate_limited/partial)
  ├── Write result file (signals completion to conductor)
  └── Exit (tmux window destroyed by conductor)
```

## Dependencies on Other Specs

- Used by: spec-15-conductor (spawns builders), spec-16-wave-execution (builder lifecycle)
- Extends: spec-05-phase-build (prompt override mechanism)
- Uses: spec-08-rate-limiting (rate limit detection in result status)
- Uses: spec-07-token-tracking (token extraction from stream-json)
- Constrained by: spec-18-task-partitioning (file ownership lists)
- Followed by: spec-19-merge-protocol (merges builder commits)
