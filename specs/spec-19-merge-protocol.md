# Spec 19: Merge Protocol

## Purpose

Define how builder worktree branches are merged back to the main branch after a wave completes. Merging parallel work is the highest-risk operation in the multi-window system. This spec defines a three-tier conflict resolution strategy, the git worktree lifecycle, branch naming conventions, and post-wave verification.

## Three-Tier Merge Strategy

### Tier 1: Clean Merge (Auto-Proceed)

The merge applies cleanly with no conflicts. This is the expected case when task partitioning (spec-18) works correctly — builders modified disjoint file sets.

```bash
# Attempt clean merge
git merge --no-ff "$builder_branch" -m "automaton: merge wave $wave builder $builder"
if [ $? -eq 0 ]; then
    log "CONDUCTOR" "Wave $wave: builder-$builder merged cleanly"
    return 0  # Tier 1 success
fi
```

### Tier 2: Trivial Conflict in Coordination Files (Auto-Resolve)

Conflicts in known coordination files are expected and auto-resolvable. These files are updated by every builder (e.g., marking their task as `[x]` in the plan).

**Coordination files:**
- `IMPLEMENTATION_PLAN.md` — multiple builders mark different tasks as `[x]`
- `AGENTS.md` — multiple builders may append operational learnings

For these files, the conductor uses a merge strategy that accepts all checkbox changes:

```bash
handle_coordination_conflict() {
    local file="$1"
    local wave=$2
    local builder=$3

    case "$file" in
        IMPLEMENTATION_PLAN.md)
            # Accept all [x] changes from both sides
            # Strategy: take ours, then apply their checkbox changes
            git checkout --ours "$file"

            # Extract tasks marked [x] by this builder (from their branch)
            local their_completed=$(git show "$builder_branch:$file" | grep '\[x\]')
            # For each task they completed, mark it in ours
            while IFS= read -r line; do
                local task_text=$(echo "$line" | sed 's/- \[x\] //')
                sed -i "s/- \[ \] $(echo "$task_text" | sed 's/[\/&]/\\&/g')/- [x] $task_text/" "$file"
            done <<< "$their_completed"

            git add "$file"
            log "CONDUCTOR" "Wave $wave: auto-resolved IMPLEMENTATION_PLAN.md conflict (builder-$builder)"
            return 0
            ;;
        AGENTS.md)
            # Accept both additions — append their new content
            git checkout --ours "$file"
            local their_additions=$(git diff "$builder_branch"..."ours" -- "$file" | grep '^+' | grep -v '^+++')
            if [ -n "$their_additions" ]; then
                echo "$their_additions" | sed 's/^+//' >> "$file"
                git add "$file"
            fi
            log "CONDUCTOR" "Wave $wave: auto-resolved AGENTS.md conflict (builder-$builder)"
            return 0
            ;;
    esac
    return 1  # not a coordination file
}
```

### Tier 3: Real Source Conflict (Re-Queue)

A conflict in actual source files means the task partitioning failed to identify a file overlap. This should be rare if annotations are accurate.

```bash
handle_source_conflict() {
    local wave=$1
    local builder=$2
    local conflicting_files="$3"

    log "CONDUCTOR" "Wave $wave: builder-$builder has source conflicts: $conflicting_files"

    # Abort this builder's merge
    git merge --abort

    # Mark this builder's task for re-queue
    jq ".assignments[$((builder - 1))].requeue = true" \
        ".automaton/wave/assignments.json" > ".automaton/wave/assignments.json.tmp"
    mv ".automaton/wave/assignments.json.tmp" ".automaton/wave/assignments.json"

    # The re-queued task will run as a single-builder in the next wave
    log "CONDUCTOR" "Wave $wave: builder-$builder task re-queued for single-builder execution"
    return 0
}
```

Re-queued tasks run as single-builder waves in the next iteration — they get the full codebase and can resolve the conflict themselves.

## Merge Sequence

Builders are merged in order (builder-1 first, then builder-2, etc.). Only builders with `"status": "success"` or `"status": "partial"` are merged.

```bash
merge_wave() {
    local wave=$1
    local builder_count=$(jq '.assignments | length' ".automaton/wave/assignments.json")
    local merged=0
    local failed=0
    local skipped=0

    for i in $(seq 1 "$builder_count"); do
        local status=$(jq -r '.status' ".automaton/wave/results/builder-${i}.json")
        local branch="automaton/wave-${wave}-builder-${i}"

        # Skip failed/timed-out builders
        if [ "$status" != "success" ] && [ "$status" != "partial" ]; then
            log "CONDUCTOR" "Wave $wave: skipping builder-$i (status: $status)"
            skipped=$((skipped + 1))
            continue
        fi

        # Attempt merge
        if git merge --no-ff "$branch" -m "automaton: merge wave $wave builder $i" 2>/dev/null; then
            merged=$((merged + 1))
            log "CONDUCTOR" "Wave $wave: builder-$i merged (tier 1: clean)"
            continue
        fi

        # Merge had conflicts — check which files
        local conflicting=$(git diff --name-only --diff-filter=U)
        local tier2_resolved=true

        for file in $conflicting; do
            if handle_coordination_conflict "$file" "$wave" "$i"; then
                continue  # tier 2 handled it
            else
                tier2_resolved=false
                break
            fi
        done

        if $tier2_resolved; then
            # All conflicts were coordination files — complete the merge
            git commit --no-edit
            merged=$((merged + 1))
            log "CONDUCTOR" "Wave $wave: builder-$i merged (tier 2: coordination files)"
        else
            # Real source conflict — tier 3
            handle_source_conflict "$wave" "$i" "$conflicting"
            failed=$((failed + 1))
        fi
    done

    log "CONDUCTOR" "Wave $wave: merge complete ($merged merged, $failed conflicts, $skipped skipped)"
}
```

## Git Worktree Lifecycle

### Creation (Before Wave)

```bash
create_worktree() {
    local builder=$1
    local wave=$2
    local worktree_path=".automaton/worktrees/builder-$builder"
    local branch="automaton/wave-${wave}-builder-${builder}"

    # Remove stale worktree if exists
    if [ -d "$worktree_path" ]; then
        git worktree remove "$worktree_path" --force 2>/dev/null
    fi

    # Remove stale branch if exists
    git branch -D "$branch" 2>/dev/null

    # Create worktree from current HEAD
    git worktree add "$worktree_path" -b "$branch" HEAD

    log "CONDUCTOR" "Created worktree: $worktree_path (branch: $branch)"
}
```

### Cleanup (After Wave)

```bash
cleanup_worktree() {
    local builder=$1
    local wave=$2
    local worktree_path=".automaton/worktrees/builder-$builder"
    local branch="automaton/wave-${wave}-builder-${builder}"

    # Remove worktree
    git worktree remove "$worktree_path" --force 2>/dev/null

    # Delete the builder branch (it's been merged or abandoned)
    git branch -D "$branch" 2>/dev/null

    # Prune stale worktree references
    git worktree prune
}
```

## Branch Naming Convention

```
automaton/wave-{wave_number}-builder-{builder_number}
```

Examples:
- `automaton/wave-1-builder-1`
- `automaton/wave-1-builder-2`
- `automaton/wave-3-builder-1`

These branches are ephemeral — created at wave start, deleted after merge or abandonment. They use the `automaton/` prefix from `git.branch_prefix` (spec-12).

## Post-Wave Verification

After all merges complete, the conductor runs verification (defined in spec-16):

1. **No conflict markers** — grep for `<<<<<<<` in source files.
2. **Build check** — run the project build command if configured.
3. **Plan integrity** — completed task count didn't decrease.
4. **Test check** — optionally run tests (if `parallel.post_wave_test_command` is configured).

If verification fails:
1. `git reset --hard` to the pre-wave commit.
2. Log the failure.
3. Re-queue all wave tasks.
4. Fall back to single-builder for 1 iteration.
5. Retry wave dispatch.

## Merge Failure Recovery

| Failure | Tier | Recovery |
|---------|------|----------|
| Clean merge succeeds | 1 | Continue |
| Conflict in IMPLEMENTATION_PLAN.md | 2 | Auto-resolve: merge checkbox changes |
| Conflict in AGENTS.md | 2 | Auto-resolve: append additions from both |
| Conflict in source files | 3 | Abort merge, re-queue task as single-builder |
| All builders conflict | 3 | All re-queued, fall back to single-builder mode |
| Post-merge verification fails | — | Revert all, re-queue all, single-builder fallback |

## Squash vs Merge Commits

The conductor uses merge commits (`--no-ff`) rather than squash merges. This preserves the builder's commit history for debugging. Each builder makes one commit, so the merge history is clean:

```
* merge wave 1 builder 3
|\
| * automaton: wave 1 builder 3 — Create API error utils
|/
* merge wave 1 builder 2
|\
| * automaton: wave 1 builder 2 — Add database migration
|/
* merge wave 1 builder 1
|\
| * automaton: wave 1 builder 1 — Implement JWT auth
|/
* pre-wave state
```

## Dependencies on Other Specs

- Used by: spec-15-conductor (post-wave merge), spec-16-wave-execution (merge step)
- Depends on: spec-17-builder-agent (builder commit protocol)
- Depends on: spec-18-task-partitioning (file ownership prevents most conflicts)
- Extends: spec-09-error-handling (merge failure recovery)
- Uses: spec-12-configuration (`git.branch_prefix`)
