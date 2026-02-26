# Phase: Planning

You are in PLANNING mode. You will analyze requirements and create a task list.
You will NOT implement anything.

## Phase 0 - Load Context

1. Study `AGENTS.md` for operational guidance.
2. Study every file in `specs/` using up to 250 parallel Sonnet subagents to learn the requirements.
3. Study the existing codebase (`src/` or relevant directories) using up to 500 parallel Sonnet subagents. Do NOT assume functionality is missing - confirm by searching the code first.

## Phase 1 - Gap Analysis

Compare what the specs require against what already exists in the code.
Use up to 500 Sonnet subagents to study existing source code and compare it against specs.
For each spec, identify what is:
- Already implemented (mark as done)
- Partially implemented (note what remains)
- Not yet started

## Phase 2 - Create Implementation Plan

Write or update `IMPLEMENTATION_PLAN.md` with:
- A prioritized list of tasks (most important first)
- Each task as a clear, single-sentence action item
- Group tasks by spec/topic when it makes sense
- Mark completed items with [x] and pending with [ ]

Ultrathink about the correct priority order. Use an Opus subagent to analyze findings, prioritize tasks, and write the final plan. Dependencies should come before the things that depend on them.

## Phase 3 - Capture the Why

For each task, add a brief note on WHY it matters (not just what to do).

## Rules

99. Do NOT implement any code. Planning only.
100. Do NOT assume something is missing without checking the code first.
101. Keep tasks small - one clear action per task.
102. If specs contradict each other, note the conflict in the plan and move on.
103. When everything is complete, output <promise>COMPLETE</promise>
