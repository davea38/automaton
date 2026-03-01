---
name: context-loader
description: Load and assemble context from AGENTS.md, IMPLEMENTATION_PLAN.md, and recent git history
tools: Read, Bash
---

## Instructions

Load project context and output a structured JSON summary of the current state.

### Step 1: Read Project Metadata

Read `AGENTS.md` and extract:
- **project**: The project name
- **language**: Primary language/framework
- **commands**: Build, test, and lint commands

### Step 2: Read Implementation Plan

Read `IMPLEMENTATION_PLAN.md` and extract:
- **completed_tasks**: Count of `[x]` checkboxes
- **pending_tasks**: Count of `[ ]` checkboxes
- **next_task**: The first unchecked `[ ]` task description
- **current_tier**: The tier/section heading containing the next task

### Step 3: Read Recent Git History

Run `git log --oneline -10` to get the 10 most recent commits.

Run `git diff --stat HEAD~3..HEAD` to summarize recent file changes (last 3 commits). If fewer than 3 commits exist, use `git diff --stat` against the first commit.

### Step 4: Read Learnings

If `.automaton/learnings.json` exists, read it and extract active learnings (where `active` is true) with confidence >= 0.7. Include only the `category`, `summary`, and `confidence` fields.

### Step 5: Output Structured Context

Output a single JSON object:

```json
{
  "project": {
    "name": "my-project",
    "language": "TypeScript",
    "commands": {
      "build": "npm run build",
      "test": "npm test",
      "lint": "npm run lint"
    }
  },
  "plan": {
    "completed_tasks": 15,
    "pending_tasks": 8,
    "next_task": "Implement user authentication",
    "current_tier": "Tier 2: Core Features"
  },
  "recent_commits": [
    "abc1234 Add login endpoint",
    "def5678 Create user model"
  ],
  "recent_changes": "5 files changed, 120 insertions(+), 30 deletions(-)",
  "learnings": [
    {
      "category": "architecture",
      "summary": "Use Express middleware for auth",
      "confidence": 0.9
    }
  ]
}
```

## Constraints

- This skill is read-only. Do not modify any files.
- Output must be valid JSON. Do not include markdown formatting around the JSON output.
- If `AGENTS.md` does not exist, set project fields to `"unknown"`.
- If `IMPLEMENTATION_PLAN.md` does not exist, set plan fields to `null` and counts to 0.
- If `.automaton/learnings.json` does not exist, set learnings to an empty array.
- Use only `git log` and `git diff` for Bash commands. Do not run any other shell commands.
- Keep the output concise. Do not include full file contents — only extracted summaries.
