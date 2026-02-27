# Spec 18: Task Partitioning

## Purpose

Define how the planning agent annotates tasks with file ownership hints, how the conductor builds a conflict graph from those hints, and how it selects non-conflicting tasks for each wave. This is the bridge between the planning phase (spec-04) and wave execution (spec-16). Good partitioning means more tasks per wave; bad partitioning means more single-builder fallbacks.

## Extended IMPLEMENTATION_PLAN.md Format

When `parallel.enabled` is `true`, the planning agent (Phase 2) adds file ownership annotations to each task using HTML comments. This is backward-compatible — the annotations are invisible in rendered markdown and ignored by the v1 single-builder.

### Annotated Task Format

```markdown
## Authentication

- [ ] Implement JWT token generation and validation (WHY: core auth primitive)
  <!-- files: src/auth/jwt.ts, src/auth/jwt.test.ts -->
- [ ] Add login endpoint with password hashing (WHY: user-facing auth entry point)
  <!-- files: src/routes/auth.ts, src/routes/auth.test.ts, src/auth/password.ts -->
- [ ] Create auth middleware for protected routes (WHY: enforce auth on API)
  <!-- files: src/middleware/auth.ts, src/middleware/auth.test.ts -->

## Database

- [ ] Set up database connection pool (WHY: required before any DB operations)
  <!-- files: src/db/connection.ts, src/db/connection.test.ts -->
- [ ] Create users table migration (WHY: auth depends on user storage)
  <!-- files: src/db/migrations/001-users.ts, src/db/schema.ts -->
```

### Annotation Rules

1. The `<!-- files: ... -->` comment must appear on the line immediately after the task checkbox line.
2. File paths are comma-separated, relative to project root.
3. Include both source files and their test files.
4. If a task's file ownership is uncertain, omit the annotation. The conductor treats unannotated tasks as conflicting with everything (see "Missing Annotations" below).
5. Shared files (like `src/db/schema.ts`) that multiple tasks need should be listed in only the task that creates/primarily modifies them. Dependent tasks should list it too — the conflict graph will serialize them.

## Planning Prompt Extension

When `parallel.enabled` is `true`, the conductor appends the following to `PROMPT_plan.md` before running the planning agent:

```markdown
---

## File Ownership Annotations (for parallel builds)

For each task in the implementation plan, add a file ownership annotation on the
line immediately below the task. Use this format:

  - [ ] Task description (WHY: rationale)
    <!-- files: path/to/file1.ts, path/to/file2.ts -->

List all files that this task will create or modify, including test files. Be
specific — use actual file paths, not directories. If you're unsure which files
a task will touch, omit the annotation.

These annotations enable parallel builders to work on non-conflicting tasks
simultaneously. Better annotations = more parallelism = faster builds.
```

This extension is appended only when `parallel.enabled` is `true`. It does not modify the base `PROMPT_plan.md` file.

## Conflict Graph Construction

The conductor builds an in-memory conflict graph from the annotated plan. Two tasks conflict if they share any file in their `files` annotations.

```bash
build_conflict_graph() {
    local plan="IMPLEMENTATION_PLAN.md"
    local tasks_file=".automaton/wave/tasks.json"

    # Extract tasks with their file annotations
    # Output: JSON array of {line, task, files[]}
    awk '
    /^- \[ \]/ {
        task_line = NR
        task_text = $0
        sub(/^- \[ \] /, "", task_text)
        # Read next line for annotation
        getline
        if ($0 ~ /<!-- files:/) {
            files = $0
            gsub(/.*<!-- files: /, "", files)
            gsub(/ -->.*/, "", files)
        } else {
            files = ""
        }
        print task_line "\t" task_text "\t" files
    }
    ' "$plan" | jq -R -s '
        split("\n") | map(select(. != "")) | map(
            split("\t") | {
                line: (.[0] | tonumber),
                task: .[1],
                files: (.[2] | split(", ") | map(select(. != "")))
            }
        )
    ' > "$tasks_file"
}
```

### Conflict Detection

Two tasks T1 and T2 conflict if:
- `T1.files ∩ T2.files ≠ ∅` (they share at least one file)
- Either T1 or T2 has no file annotation (unannotated tasks conflict with everything)

```bash
tasks_conflict() {
    local task1_files="$1"  # comma-separated
    local task2_files="$2"  # comma-separated

    # Empty files list = unannotated = conflicts with everything
    if [ -z "$task1_files" ] || [ -z "$task2_files" ]; then
        return 0  # conflict
    fi

    # Check for any shared file
    for f1 in $(echo "$task1_files" | tr ',' ' '); do
        for f2 in $(echo "$task2_files" | tr ',' ' '); do
            if [ "$f1" = "$f2" ]; then
                return 0  # conflict
            fi
        done
    done

    return 1  # no conflict
}
```

## Task Selection Algorithm

The conductor uses a greedy algorithm to select the maximum number of non-conflicting tasks for each wave, up to `max_builders`:

```
function select_wave_tasks(max_builders):
    incomplete = [t for t in tasks if t.status == "[ ]"]
    if len(incomplete) == 0:
        return []

    selected = []
    used_files = set()

    for task in incomplete (in plan order):
        if len(selected) >= max_builders:
            break

        if task.files is empty:
            # Unannotated — can only run alone
            if len(selected) == 0:
                return [task]  # single-builder wave
            else:
                continue  # skip, run in a later wave

        task_files = set(task.files)
        if task_files ∩ used_files == ∅:
            selected.append(task)
            used_files = used_files ∪ task_files
        # else: skip (conflicts with already-selected task)

    return selected
```

### Algorithm Properties

- **Greedy, plan-order.** Tasks are considered in the order they appear in `IMPLEMENTATION_PLAN.md`. This respects the planner's dependency ordering.
- **Maximum parallelism within constraints.** Selects up to `max_builders` tasks per wave.
- **Safe fallback.** Unannotated tasks are treated as "conflicts with everything" and run alone in single-builder waves.
- **Deterministic.** Same plan always produces the same wave assignments.

## Missing Annotations

When file annotations are missing (the planning agent didn't add them, or they were removed):

| Scenario | Behavior |
|----------|----------|
| All tasks annotated | Full parallelism — greedy selection |
| Some tasks annotated | Annotated tasks parallelized; unannotated tasks run alone |
| No tasks annotated | Every task runs alone — effectively single-builder mode |

This ensures graceful degradation. Even with no annotations, the system still works — it just doesn't parallelize.

## Annotation Quality Heuristics

The conductor logs annotation coverage to help humans assess partition quality:

```bash
log_partition_quality() {
    local total=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    local annotated=$(grep -c '<!-- files:' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
    local coverage=$((annotated * 100 / total))

    log "CONDUCTOR" "Task annotations: $annotated/$total ($coverage% coverage)"

    if [ "$coverage" -lt 50 ]; then
        log "CONDUCTOR" "WARN: Low annotation coverage. Parallelism will be limited."
    fi
}
```

## Dependency-Aware Selection (Future Enhancement)

The current algorithm relies on file-level conflict detection. A future enhancement could use explicit task dependencies (e.g., `<!-- depends: line 14 -->`) to prevent scheduling dependent tasks in the same wave even when they don't share files. For v2, file-level conflict detection is sufficient.

## Example Wave Selection

Given this plan:
```markdown
- [ ] Set up database connection pool
  <!-- files: src/db/connection.ts, src/db/connection.test.ts -->
- [ ] Create users table migration
  <!-- files: src/db/migrations/001-users.ts, src/db/schema.ts -->
- [ ] Implement JWT token generation
  <!-- files: src/auth/jwt.ts, src/auth/jwt.test.ts -->
- [ ] Add login endpoint
  <!-- files: src/routes/auth.ts, src/auth/password.ts -->
- [ ] Create auth middleware
  <!-- files: src/middleware/auth.ts, src/middleware/auth.test.ts -->
```

With `max_builders: 3`:

**Wave 1:** Tasks 1, 3, 5 (connection pool, JWT, auth middleware — no file overlap)
**Wave 2:** Tasks 2, 4 (users migration, login endpoint — no file overlap)

All 5 tasks completed in 2 waves instead of 5 sequential iterations.

## Dependencies on Other Specs

- Extends: spec-04-phase-plan (annotated task format, planning prompt extension)
- Used by: spec-15-conductor (task selection), spec-16-wave-execution (assignment generation)
- Used by: spec-17-builder-agent (file ownership constraints)
- Informs: spec-19-merge-protocol (conflict likelihood based on ownership)
