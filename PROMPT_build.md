# Phase: Building

You are in BUILDING mode. You will implement exactly ONE task, then stop.

## Phase 0 - Load Context

1. Study `AGENTS.md` for operational guidance.
2. Study `IMPLEMENTATION_PLAN.md` to see all tasks.
3. If `.automaton/context_summary.md` exists, read it for project state overview.
4. If `.automaton/iteration_memory.md` exists, read the last 10 lines for recent build history.
5. Study relevant files in `specs/` — use subagents proportional to codebase size. For a single-file project, 1-3 subagents suffice. Scale up for large multi-file projects.

## Phase 1 - Pick One Task

From `IMPLEMENTATION_PLAN.md` (or `.automaton/backlog.md` in self-build mode), select the most important incomplete task.
Consider which task should come next based on dependencies and priority.

## Phase 2 - Investigate Before Building

Before writing any code, study the existing codebase related to this task.
Do NOT assume functionality is missing - search the code first.
Use subagents proportional to codebase size for research, but only 1 Sonnet subagent for building and testing.
Use Opus subagents when complex reasoning is needed (debugging, architectural decisions).

## Phase 3 - Implement

Implement the task completely. No placeholders. No "TODO" comments. No partial work.
If the task is too large, implement the most critical part and note the remainder in the plan.

## Phase 4 - Validate

Run all relevant validation:
- Tests (if they exist)
- Type checking (if applicable)
- Linting (if applicable)
- Build (if applicable)

Use only 1 Sonnet subagent for running tests and builds (this creates helpful backpressure).
Fix any failures before proceeding.

## Phase 5 - Update and Commit

1. Update `IMPLEMENTATION_PLAN.md`:
   - Mark the completed task with [x]
   - Add any new tasks discovered during implementation
   - Note any bugs found (even unrelated ones)
2. Update `AGENTS.md` if you learned something operationally important (keep it brief).
3. Git commit with a descriptive message explaining WHAT changed and WHY.

## Self-Modification Safety (spec-22)

When the target project IS automaton itself (self-build mode):

108. **NEVER** modify orchestrator files (`automaton.sh`, `PROMPT_*.md`, `automaton.config.json`, `bin/cli.js`) as a side effect of another task. Only modify them when the task explicitly targets orchestrator code.
109. When modifying `automaton.sh`, change only the specific function targeted by the task. Do not refactor surrounding code.
110. Do not modify protected functions (`run_orchestration`, `_handle_shutdown`) unless the task explicitly requires it.
111. Keep changes under 200 lines per iteration. If a task requires more, split it into sub-tasks.
112. After modifying `automaton.sh`, verify your changes don't break the syntax: think about whether `bash -n automaton.sh` would pass.

## Self-Build Mode Context

When `.automaton/backlog.md` exists and you are in self-build mode:
- Read `.automaton/backlog.md` instead of `IMPLEMENTATION_PLAN.md` for task selection
- Prioritize tasks that reduce token usage or improve reliability
- The orchestrator will validate `automaton.sh` after your changes — if syntax fails, your changes will be rolled back

## Rules

99. Implement only ONE task per iteration. Then stop.
100. Capture the why when writing documentation or commit messages.
101. No migrations or adapters - use single sources of truth.
102. If you find spec inconsistencies, note them in the plan but don't block on them.
103. Implement completely. No placeholders, no stubs, no "coming soon".
104. Periodically clean completed items from the plan, but always keep at least 5 recent `[x]` checkboxes visible (the loop script counts them to verify completion).
105. Update `AGENTS.md` with operational learnings - but keep it under 60 lines.
106. If you find spec inconsistencies, use an Opus subagent to resolve them and update the specs.
107. When every task in `IMPLEMENTATION_PLAN.md` has an [x] and no `[ ]` remain, output <promise>COMPLETE</promise>.
