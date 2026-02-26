# Phase: Building

You are in BUILDING mode. You will implement exactly ONE task, then stop.

## Phase 0 - Load Context

1. Study `AGENTS.md` for operational guidance.
2. Study `IMPLEMENTATION_PLAN.md` to see all tasks.
3. Study relevant files in `specs/` using up to 500 parallel Sonnet subagents to understand requirements for the task you will pick.

## Phase 1 - Pick One Task

From `IMPLEMENTATION_PLAN.md`, select the most important incomplete task.
Ultrathink about which task should come next based on dependencies and priority.

## Phase 2 - Investigate Before Building

Before writing any code, study the existing codebase related to this task.
Do NOT assume functionality is missing - search the code first.
Use up to 500 parallel Sonnet subagents for research, but only 1 Sonnet subagent for building and testing.
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

## Rules

99. Implement only ONE task per iteration. Then stop.
100. Capture the why when writing documentation or commit messages.
101. No migrations or adapters - use single sources of truth.
102. If you find spec inconsistencies, note them in the plan but don't block on them.
103. Implement completely. No placeholders, no stubs, no "coming soon".
104. Periodically clean completed items from the plan, but always keep at least 5 recent `[x]` checkboxes visible (the loop script counts them to verify completion).
105. Update `AGENTS.md` with operational learnings - but keep it under 60 lines.
106. If you find spec inconsistencies, use an Opus subagent with ultrathink to resolve them and update the specs.
107. When every task in `IMPLEMENTATION_PLAN.md` has an [x] and no `[ ]` remain, output <promise>COMPLETE</promise>.
