# Design Principles

Seven inviolable rules for automaton development, derived from analysis of 17 competitor projects.
Referenced by the constitution (spec-40) as an operational annex.

## 1. Size Ceiling

`automaton.sh` must stay under 18,000 lines. Complexity spirals (ruflo 393K LOC, Auto-Claude 451K LOC) are the #1 anti-pattern in competitor projects. When approaching the ceiling, extract functionality into separate scripts or refactor before adding new features.

**Threshold**: `wc -l automaton.sh` < 18,000

## 2. Zero External Dependencies

Only `bash` (>=4.0), `git`, `claude` CLI, and `jq` are permitted runtime dependencies. Dependency hell (sparc 9/13 issues are install bugs, crewAI 75+ deps) is the #3 anti-pattern. No `apt-get`, `npm`, `pip`, `brew`, `cargo`, or `gem` commands in generated or orchestrator code.

**Threshold**: Zero package manager invocations in codebase.

## 3. Plain Text State

All persistent state lives in `.automaton/` as cat-able text files (JSON, JSONL, Markdown). No databases, no binary formats, no scattered dotfiles. This avoids the #8 anti-pattern (oh-my-claudecode, ruflo spread state across multiple locations).

**Threshold**: All state writes target `.automaton/` or `$AUTOMATON_DIR`.

## 4. Loud Failure

Every script uses `set -euo pipefail`. No silent error swallowing (`2>/dev/null` without fallback handling). No unrestored `set +e`. This combats the #2 anti-pattern (gastown, claude-octopus swallow errors silently).

**Threshold**: Zero instances of `2>/dev/null` without `||` fallback; zero unrestored `set +e`.

## 5. stdout is the UI

No TUI frameworks, no dashboards, no GUIs, no Electron apps. Terminal output is the interface. This avoids the #5 and #9 anti-patterns (Auto-Claude 250K LOC Electron, zeroshot Rust TUI).

**Threshold**: Zero references to `curses`, `dialog`, `whiptail`, `electron`, `react`, `textual`, `tput cup`.

## 6. Claude for Creativity Only

Bash handles all deterministic logic (file I/O, branching, iteration, parsing). Claude handles ambiguous/creative tasks (planning, coding, reviewing). No prompt-as-code patterns where prompts contain if/then/else or loop constructs for deterministic control flow. This avoids the #4 anti-pattern (claude-octopus, wshobson/agents).

**Threshold**: Zero control-flow keywords (`if.*then`, `for.*do`, `while.*do`) inside heredoc prompt blocks.

## 7. No Feature Without Tests

Every new function must have a corresponding test in the test suite. Feature claims without implementation are the #7 anti-pattern (ruflo, sparc advertise features that do not exist). Tests are the proof that features work.

**Threshold**: Every function added in a commit has a test that exercises it.
