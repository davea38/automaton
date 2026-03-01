---
name: rollback-executor
description: Guided manual rollback of a specific evolution cycle's merged changes
tools: Bash, Read, Grep
---

## Instructions

Execute a manual rollback of a specific evolution cycle when automatic rollback is insufficient — e.g., a merged change that was later found to be problematic. This skill guides you through identifying, reverting, and recording the rollback.

### Step 1: Identify the Target Cycle

List recent evolution cycles by examining the audit trail and git history:

1. Read `.automaton/self_modifications.json` to find recent evolution entries (harvest, rollback, implement actions)
2. List evolution branches: `git branch --list 'automaton/evolve-*'`
3. Check `.automaton/votes/` for vote records linked to evolution ideas
4. Read `.automaton/garden/_index.json` for harvested ideas

Present the user with a summary of recent cycles: cycle ID, idea ID, idea title, outcome (harvested/rolled back), and the merge commit hash if applicable.

If the user has already specified a cycle ID or idea ID, skip the listing and proceed directly.

### Step 2: Locate the Merge Commit

Find the merge commit that brought the evolution branch into the working branch:

```bash
# Find the merge commit for the evolution branch
git log --oneline --merges --grep="automaton/evolve-{cycle_id}-{idea_id}" | head -5
```

If no merge commit is found, check for fast-forward merges by searching for commits from the evolution branch:

```bash
git log --oneline --all --ancestry-path automaton/evolve-{cycle_id}-{idea_id}..HEAD | head -10
```

Report the merge commit hash and the files changed.

### Step 3: Verify the Rollback Target

Before proceeding, display:
- The merge commit message and date
- The list of files modified by the evolution cycle
- The current test pass rate (run `bash -n automaton.sh` as a quick syntax check)
- Whether the evolution branch still exists for reference

Ask the user to confirm they want to proceed with the rollback.

### Step 4: Revert the Merge

Execute `git revert` to undo the merge commit:

```bash
# For a merge commit (two parents), revert keeping the mainline
git revert -m 1 <merge_commit_hash> --no-edit
```

If the evolution was fast-forwarded (no merge commit), identify the range of commits from the evolution branch and revert them in reverse order:

```bash
# Revert commits in reverse chronological order
git revert --no-edit <newest_commit>..<oldest_commit>
```

If there are conflicts during the revert, stop and report the conflicts to the user with guidance on resolution.

### Step 5: Wilt the Garden Idea

Mark the responsible idea as wilted in the garden:

```bash
# Source automaton.sh functions and wilt the idea
source automaton.sh
_garden_wilt "<idea_id>" "Manual rollback: <reason provided by user>"
```

If `automaton.sh` cannot be sourced, manually update the idea JSON file in `.automaton/garden/` to set `stage: "wilt"` and append a stage_history entry.

### Step 6: Emit Quality Concern Signal

Record a signal about the rollback:

```bash
source automaton.sh
_signal_emit "quality_concern" \
    "Manual rollback of idea-<idea_id> (cycle <cycle_id>)" \
    "Post-merge rollback: <reason>" \
    "safety" "<cycle_id>" ""
```

If `automaton.sh` cannot be sourced, manually append the signal to `.automaton/signals.json`.

### Step 7: Update Audit Trail

Record the manual rollback in `.automaton/self_modifications.json`:

```bash
jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg cid "<cycle_id>" --arg iid "<idea_id>" \
   --arg reason "<reason>" --arg rev "<revert_commit_hash>" \
   '. + [{timestamp:$ts, action:"manual_rollback", cycle_id:$cid, idea_id:$iid, reason:$reason, revert_commit:$rev}]' \
   .automaton/self_modifications.json > .automaton/self_modifications.json.tmp \
   && mv .automaton/self_modifications.json.tmp .automaton/self_modifications.json
```

### Step 8: Verify Rollback Success

Run validation to confirm the rollback restored a healthy state:

1. Syntax check: `bash -n automaton.sh`
2. Run the test suite if available
3. Compare the current test pass rate against the pre-evolution baseline
4. Confirm the revert commit exists in git log

### Step 9: Output Summary

Output a JSON summary of the rollback:

```json
{
  "action": "manual_rollback",
  "cycle_id": "<cycle_id>",
  "idea_id": "<idea_id>",
  "merge_commit": "<original merge hash>",
  "revert_commit": "<revert commit hash>",
  "files_restored": ["list of files reverted"],
  "idea_wilted": true,
  "signal_emitted": true,
  "audit_recorded": true,
  "validation": {
    "syntax_check": "pass",
    "test_suite": "pass"
  }
}
```

## Constraints

- This skill modifies files only through `git revert` and state file updates. It never uses `git reset --hard` or other destructive operations.
- Always use `git revert` to create a new commit that undoes changes — never rewrite history.
- If the evolution branch still exists, do not delete it — preserve it for debugging reference.
- If `.automaton/self_modifications.json` does not exist, create it with an empty array `[]` before appending.
- If `.automaton/garden/` or `.automaton/signals.json` do not exist, skip the wilt and signal steps and note this in the output.
- If `automaton.sh` cannot be sourced (syntax errors, missing dependencies), fall back to direct JSON file manipulation with `jq`.
- Do not proceed with the revert if the user has not confirmed the target. Always verify before reverting.
- Check `.automaton/votes/` for the vote record associated with the idea to include in the output context.
- Output must be valid JSON. Do not include markdown formatting around the JSON output.
