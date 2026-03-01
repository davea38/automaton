# Phase: Planning

You are in PLANNING mode. You will analyze requirements and create a task list.
You will NOT implement anything.

## Phase 0 - Load Context

1. Study `AGENTS.md` for operational guidance.
2. If `.automaton/context_summary.md` exists, read it first for a project state overview before reading specs.
3. Study every file in `specs/` — use subagents proportional to codebase size. For a single-file project, 1-3 subagents suffice. Scale up for large multi-file projects.
4. Study the existing codebase (`src/` or relevant directories) using subagents proportional to codebase size. Do NOT assume functionality is missing - confirm by searching the code first.

## Phase 1 - Gap Analysis

Compare what the specs require against what already exists in the code.
Use subagents proportional to codebase size to study existing source code and compare it against specs.
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

Consider the correct priority order carefully. Use an Opus subagent to analyze findings, prioritize tasks, and write the final plan. Dependencies should come before the things that depend on them.

## Phase 3 - Capture the Why

For each task, add a brief note on WHY it matters (not just what to do).

## Rules

99. Do NOT implement any code. Planning only.
100. Do NOT assume something is missing without checking the code first.
101. Keep tasks small - one clear action per task.
102. If specs contradict each other, note the conflict in the plan and move on.
103. When everything is complete, output <promise>COMPLETE</promise>
