# Spec 31: Hooks Integration

## Purpose

Claude Code hooks are guaranteed to run — unlike CLAUDE.md instructions which are advisory, hooks execute as shell commands or HTTP handlers before/after tool calls. Critical automaton behaviors currently rely on advisory prompt instructions: file ownership enforcement (spec-17), self-modification safety (spec-22), and plan corruption prevention (spec-09). Converting these to hooks improves reliability from "the agent should do this" to "the system enforces this."

## Requirements

### 1. File Ownership Enforcement Hook

Replace prompt-based file ownership with a `PreToolUse` hook that blocks writes to files outside a builder's ownership list.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/enforce-file-ownership.sh",
            "timeout": 5,
            "statusMessage": "Checking file ownership..."
          }
        ]
      }
    ]
  }
}
```

The hook script (`.claude/hooks/enforce-file-ownership.sh`):
- Reads the builder's assignment from `$CLAUDE_PROJECT_DIR/.automaton/wave/assignments.json`
- Extracts the target file path from the hook's stdin JSON (`tool_input.file_path`)
- Compares against `files_owned` list
- Exit 0 if file is in ownership list (allow write)
- Exit 2 if file is NOT in ownership list (block write, stderr message fed back to agent)

This hook is only active during parallel build waves. The orchestrator configures it in `.claude/settings.local.json` when entering parallel build mode and removes it when exiting.

### 2. Self-Build Safety Hook

Replace prompt-based self-modification rules with a `PreToolUse` hook that validates writes to orchestrator files.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/self-build-guard.sh",
            "timeout": 5,
            "statusMessage": "Validating self-modification..."
          }
        ]
      }
    ]
  }
}
```

The hook script (`.claude/hooks/self-build-guard.sh`):
- Checks if target file is an orchestrator file (`automaton.sh`, `PROMPT_*.md`, `automaton.config.json`, `bin/cli.js`)
- If `self_build.enabled` is false: exit 2 (block all writes to orchestrator files)
- If `self_build.enabled` is true: check if the current task explicitly targets orchestrator code (read from assignment or task context). Exit 0 if targeted, exit 2 if side-effect modification
- When blocking, stderr contains: "Cannot modify orchestrator file [filename] — not the assigned task target"

### 3. Test/Lint Result Capture Hook

Capture structured test and lint results from Bash tool calls via a `PostToolUse` hook.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/capture-test-results.sh",
            "timeout": 30,
            "statusMessage": "Processing test results..."
          }
        ]
      }
    ]
  }
}
```

The hook script (`.claude/hooks/capture-test-results.sh`):
- Reads the Bash command from stdin JSON (`tool_input.command`)
- Detects test/lint patterns (commands containing `test`, `jest`, `pytest`, `bats`, `eslint`, `shellcheck`, etc.)
- For detected test commands: parse exit code and output, append structured result to `.automaton/test_results.json`
- For non-test commands: exit 0 immediately (no-op)
- Structured result format:

```json
{
  "command": "bats tests/test_budget.sh",
  "exit_code": 0,
  "passed": true,
  "timestamp": "2026-03-01T10:30:00Z",
  "iteration": 7,
  "phase": "build"
}
```

### 4. Builder Stop Hook

Replace builder wrapper cleanup logic with a `Stop` hook that writes result files and commits automatically when an agent finishes.

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": ".claude/hooks/builder-on-stop.sh",
        "timeout": 30,
        "statusMessage": "Finalizing builder results..."
      }
    ]
  }
}
```

When defined in an agent's frontmatter (spec-27), `Stop` hooks are automatically converted to `SubagentStop` at runtime. The hook:
- Extracts token usage from the session transcript (`transcript_path` from stdin)
- Writes the builder result JSON to `.automaton/wave/results/builder-{N}.json`
- Stages and commits all changes if any files were modified
- Signals completion to the conductor

### 5. Subagent Token Tracking Hooks

Track per-subagent token usage for budget attribution using `SubagentStart` and `SubagentStop` hooks.

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "automaton-*",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/track-subagent-start.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "automaton-*",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/track-subagent-stop.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

`SubagentStart` records the start timestamp and agent name. `SubagentStop` extracts token usage from the session data and appends to `.automaton/subagent_usage.json` for budget reconciliation.

Note: `SubagentStart` only supports command hooks (not http, prompt, or agent hook types).

### 6. TaskCompleted Quality Gate Hook (Agent Teams Mode)

When using Agent Teams mode (spec-28), use the `TaskCompleted` hook to enforce per-task quality checks:

```json
{
  "hooks": {
    "TaskCompleted": [
      {
        "type": "command",
        "command": ".claude/hooks/task-quality-gate.sh",
        "timeout": 60,
        "statusMessage": "Running quality gate..."
      }
    ]
  }
}
```

The hook:
- Reads `task_id`, `task_subject`, `task_description` from stdin
- Runs task-specific validation (syntax check, test execution)
- Exit 0: task marked complete
- Exit 2: task NOT marked complete, stderr feedback sent to teammate ("Tests failing — fix before marking complete")

`TaskCompleted` only supports command hooks.

### 7. Hook Configuration Location

Hooks are configured in `.claude/settings.local.json` (project-specific, gitignored) for runtime-dynamic hooks (file ownership, which changes per wave) and `.claude/settings.json` (project-specific, committable) for stable hooks (self-build guard, test capture).

Agent-scoped hooks are defined in agent frontmatter (spec-27) and are active only during that agent's lifecycle.

| Hook | Location | Reason |
|------|----------|--------|
| File ownership | `.claude/settings.local.json` | Changes per wave (dynamic) |
| Self-build guard | `.claude/settings.json` | Stable safety rule |
| Test capture | `.claude/settings.json` | Stable behavior |
| Builder stop | Agent frontmatter | Scoped to agent lifecycle |
| Subagent tracking | `.claude/settings.json` | Stable tracking |
| TaskCompleted gate | `.claude/settings.json` | Stable quality gate |

### 8. Hook Performance Requirement

All hooks must be idempotent and complete within their timeout. Target execution time is under 2 seconds for `PreToolUse` hooks (they block agent progress) and under 30 seconds for `PostToolUse`/`Stop` hooks. Hook scripts must:

- Use efficient file reads (jq streaming, not full parse)
- Avoid network calls
- Handle missing files gracefully (exit 0 if context files don't exist yet)
- Be idempotent — safe to run multiple times with same input

## Acceptance Criteria

- [ ] File ownership enforced by `PreToolUse` hook — writes to unowned files blocked with exit 2
- [ ] Self-build guard blocks writes to orchestrator files unless task explicitly targets them
- [ ] Test/lint results captured as structured JSON by `PostToolUse` hook on Bash
- [ ] Builder `Stop` hook writes result file and commits changes
- [ ] Subagent token usage tracked via `SubagentStart`/`SubagentStop` hooks
- [ ] `TaskCompleted` hook prevents task completion when quality gate fails
- [ ] All `PreToolUse` hooks complete in under 2 seconds
- [ ] All hooks are idempotent — repeated execution produces same result
- [ ] Hook configuration split correctly between `.claude/settings.json` and `.claude/settings.local.json`

## Dependencies

- Depends on: spec-27 (agent definitions with frontmatter hooks)
- Extends: spec-17 (file ownership moves from prompt instruction to hook enforcement)
- Extends: spec-22 (self-build safety moves from prompt instruction to hook enforcement)
- Extends: spec-09 (test result capture provides structured gate data)
- Extends: spec-11 (quality gate data from hooks)
- Depended on by: spec-28 (TaskCompleted hook for Agent Teams mode)

## Files to Modify

- `.claude/hooks/enforce-file-ownership.sh` — new file: file ownership enforcement script
- `.claude/hooks/self-build-guard.sh` — new file: self-modification guard script
- `.claude/hooks/capture-test-results.sh` — new file: test result capture script
- `.claude/hooks/builder-on-stop.sh` — new file: builder completion handler
- `.claude/hooks/track-subagent-start.sh` — new file: subagent start tracker
- `.claude/hooks/track-subagent-stop.sh` — new file: subagent stop tracker
- `.claude/hooks/task-quality-gate.sh` — new file: task completion quality gate
- `.claude/settings.json` — add stable hook definitions
- `automaton.sh` — configure dynamic hooks in `.claude/settings.local.json` during parallel build setup
