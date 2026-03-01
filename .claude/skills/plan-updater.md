---
name: plan-updater
description: Update IMPLEMENTATION_PLAN.md task checkboxes and add new tasks
tools: Read, Edit
---

## Instructions

Update the implementation plan to reflect completed work, new tasks, and discovered bugs.

### Step 1: Determine Plan File

Check if `.automaton/backlog.md` exists (self-build mode). If it does, use it as the plan file. Otherwise, use `IMPLEMENTATION_PLAN.md`.

### Step 2: Read Current Plan

Read the plan file and identify:
- All task lines matching `- [ ]` (pending) and `- [x]` (completed)
- The section/tier structure (headings)
- The count of recent `[x]` checkboxes (at least 5 must remain visible)

### Step 3: Mark Completed Task

Find the specific task line that was just completed and change `- [ ]` to `- [x]`. Match the task by its description text — do not use line numbers, as the file may have changed since it was last read.

Only mark ONE task per invocation. If multiple tasks were completed, invoke this skill once per task.

### Step 4: Add New Tasks (if any)

If new tasks were discovered during implementation, add them as `- [ ]` lines under the appropriate section/tier heading. Place new tasks after existing tasks in the same section.

Each new task should include:
- A clear description of what needs to be done
- A `(WHY: ...)` explanation in parentheses
- A `<!-- test: path -->` or `<!-- test: none -->` annotation if applicable

### Step 5: Note Discovered Bugs (if any)

If bugs were found (even unrelated to the current task), add them as new `- [ ]` tasks with a `(BUG:)` prefix in the description, placed under the most relevant section.

### Step 6: Clean Old Completed Items

If the plan has more than 20 completed `[x]` items, move the oldest completed items (beyond the most recent 5) into a `## Previously Completed` section at the top of the plan. This keeps the active sections readable while preserving history.

Always keep at least 5 recent `[x]` checkboxes visible in their original sections — the orchestrator counts them to verify completion.

### Step 7: Output Confirmation

Output a JSON summary of changes made:

```json
{
  "plan_file": "IMPLEMENTATION_PLAN.md",
  "marked_complete": "Task description that was marked [x]",
  "tasks_added": [
    "New task description 1"
  ],
  "bugs_noted": [],
  "completed_visible": 6,
  "total_pending": 12
}
```

## Constraints

- This skill modifies only the plan file. Do not modify any other files.
- This skill is idempotent. Marking an already-completed task has no effect.
- If the task description is not found in the plan, output an error in the JSON: `{"error": "Task not found", "searched": "task description"}`.
- Do not reorder existing tasks. Preserve the original order within each section.
- Do not change task descriptions when marking them complete — only change `[ ]` to `[x]`.
- Preserve all existing formatting, headings, and whitespace in the plan file.
