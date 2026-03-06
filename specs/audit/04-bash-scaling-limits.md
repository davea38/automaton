# Audit Finding 04: Bash at 17K Lines — Structural Risk

## Problem

The orchestrator is 17,187 lines of bash across 18 files. The PRD says "you can read the entire system in 30 minutes." That was true at 1,000 lines. At 17K lines, bash becomes a liability:

1. **No type system.** Variables are strings. A typo in a variable name silently creates a new empty variable. `set -u` catches undefined reads but not misspellings of defined variables.
2. **Testing is manual.** The test files in `tests/` use a custom assertion framework (`test_helpers.sh`). There's no way to run the full test suite and get a pass/fail count without custom scripting.
3. **Refactoring is dangerous.** Renaming a function requires grep across 18 files. No IDE support for bash refactoring at this scale.
4. **Error propagation is fragile.** Bash error handling via `$?` checks and `set -e` with exceptions (`|| true`) is correct but brittle. A missing `|| true` on a non-critical command crashes the orchestrator.
5. **JSON manipulation via jq.** Every state operation shells out to jq. This works but is slow for complex operations and error messages from jq are opaque.

The PRD explicitly chose bash for "zero dependencies, instant start." This was the right call at 1K lines. At 17K lines, the cost-benefit has shifted.

## What This Means for the Factory

When automaton builds OTHER projects, bash is fine — it just shells out to `claude -p`. But when automaton needs to evolve itself (the evolution subsystem), bugs in bash are harder to catch and fix autonomously. An agent modifying a 17K-line bash codebase is more likely to introduce subtle bugs than an agent modifying structured TypeScript/Python.

## Recommendation

### NOT a rewrite. Instead:

### A. Harden the Test Suite
Create a `make test` or `./run_tests.sh` that executes all `tests/test_*.sh` files, counts pass/fail, and exits non-zero on any failure. This is prerequisite for safe changes.

### B. Add ShellCheck as a Gate
ShellCheck catches the exact class of bugs bash is vulnerable to (undefined variables, word splitting, quoting). Add `shellcheck automaton.sh lib/*.sh` to the review phase.

### C. Extract Configuration to Declarative Format
The 1,108-line `config.sh` is mostly `jq` reads. Consider generating bash variable assignments from `automaton.config.json` once at startup, eliminating repeated jq calls.

### D. Consider a Thin TypeScript Wrapper (Future)
If the codebase grows past 25K lines, consider a TypeScript orchestrator that calls the same `claude -p` commands. This gives type safety, better testing, and IDE support while keeping the "shell out to claude" architecture. This is a future consideration, not an immediate action.

## Complexity
A: Low (new script, ~50 lines)
B: Low (one shellcheck call in review)
C: Moderate (config loader refactor)
D: High (future — only if needed)

## Dependencies
A is prerequisite for everything else.
