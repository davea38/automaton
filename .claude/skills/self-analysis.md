---
name: self-analysis
description: Analyze automaton.sh for self-build mode — extract function index, identify modification targets, check dependencies
tools: Read, Grep, Glob
---

## Instructions

Analyze `automaton.sh` to produce a structured overview for self-build mode. This skill provides the codebase context that build agents need when modifying the orchestrator itself.

### Step 1: Extract Function Index

Use Grep to find all function definitions in `automaton.sh` matching the pattern `^[a-z_]+() {`. For each function, record:
- **name**: The function name
- **line**: The line number where it is defined
- **scope**: Whether it is public (no `_` prefix) or internal (`_` prefix)

### Step 2: Map Function Sections

Group functions by the section they belong to, using comment headers in `automaton.sh` (lines matching `^# ---` or `^## `). Common sections include: configuration, logging, state management, budget tracking, phase execution, parallel builds, self-build safety, and utilities.

### Step 3: Identify Protected Functions

Read the `self_build.protected_functions` config value from `automaton.config.json`. List these functions separately — they must not be modified unless the task explicitly targets them.

### Step 4: Identify Modification Targets

Given a task description (provided in the invocation context), identify:
- **target_functions**: Functions that need modification to implement the task
- **callers**: Functions that call the target functions (found via Grep for the function name followed by a space or parenthesis)
- **callees**: Functions called by the target functions

### Step 5: Check Orchestrator File Inventory

Use Glob to list all orchestrator files that are protected by self-build safety rules:
- `automaton.sh`
- `PROMPT_*.md`
- `automaton.config.json`
- `bin/cli.js`

Report their sizes (line counts) so the build agent understands the scope of each file.

### Step 6: Output Structured Analysis

Output a single JSON object:

```json
{
  "function_index": [
    {
      "name": "load_config",
      "line": 17,
      "scope": "public",
      "section": "configuration"
    }
  ],
  "total_functions": 99,
  "total_lines": 5249,
  "protected_functions": ["run_orchestration", "_handle_shutdown"],
  "modification_targets": {
    "task": "Add bootstrap integration to run_agent",
    "target_functions": ["run_agent"],
    "callers": ["run_phase_build", "run_phase_research"],
    "callees": ["write_state", "log"]
  },
  "orchestrator_files": [
    {
      "path": "automaton.sh",
      "lines": 5249
    },
    {
      "path": "automaton.config.json",
      "lines": 85
    }
  ]
}
```

## Constraints

- This skill is read-only. Do not modify any files.
- Output must be valid JSON. Do not include markdown formatting around the JSON output.
- If `automaton.sh` does not exist, output `{"error": "automaton.sh not found"}`.
- If `automaton.config.json` does not exist, set `protected_functions` to the defaults: `["run_orchestration", "_handle_shutdown"]`.
- If no task description is provided in the invocation context, omit the `modification_targets` field from the output.
- Keep the function index concise — include only name, line, scope, and section. Do not include function bodies.
- Use only Read, Grep, and Glob tools. Do not run any shell commands.
