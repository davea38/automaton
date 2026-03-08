# Operational Guide

<!-- This file starts nearly empty ON PURPOSE. -->
<!-- As you run RALPH loops, Claude will add learnings here. -->
<!-- You can also add notes here yourself when you spot patterns. -->

## Project

- Project: automaton
- Language: Bash (orchestrator), Node.js (CLI scaffolder)
- Framework: None (pure bash + jq for orchestrator)

## Commands

- Build: N/A (bash scripts, no compilation)
- Test: `bash -n automaton.sh` (syntax check)
- Lint: `shellcheck automaton.sh lib/*.sh` (if available)

## Learnings

- System deps: claude CLI, jq, git (checked at startup)
- Existing templates: PROMPT_plan.md, PROMPT_build.md, AGENTS.md, IMPLEMENTATION_PLAN.md, CLAUDE.md
- automaton.sh is the main orchestrator for multi-phase runs
