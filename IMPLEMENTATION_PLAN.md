# Implementation Plan

All 26 specs are functionally implemented in `automaton.sh` (5249 lines, 99 functions). Root and template copies of `automaton.sh`, `automaton.config.json`, `PROMPT_build.md`, `PROMPT_review.md`, `PROMPT_research.md`, `PROMPT_converse.md`, and `PROMPT_plan.md` are verified identical. Two gaps remain: a missing template file and an untracked `.gitignore`.

## Previously Completed

- [x] Sync `templates/automaton.sh` with root (WHY: template was 1103 lines behind, missing specs 22-26 functionality)
- [x] Sync `templates/automaton.config.json` with root (WHY: template was missing self_build, journal, and budget fields)
- [x] Sync `templates/PROMPT_build.md` with root (WHY: template was missing self-build safety rules from spec-22)
- [x] Sync `templates/PROMPT_review.md` with root (WHY: template was missing self-build review section from spec-25)
- [x] Sync `templates/PROMPT_research.md` with root (WHY: template was missing context_summary read from spec-24)
- [x] Sync `templates/PROMPT_plan.md` with root (WHY: template was missing context_summary read and proportional subagent scaling)

## 1. Missing Template — PROMPT_self_research.md (spec-13, spec-25)

Root `PROMPT_self_research.md` exists and is referenced by `automaton.sh` at line 4632 for `--self` mode, but has no template counterpart. Projects scaffolded via `npx automaton` will be missing this file, causing `--self` mode research phase to silently skip it.

- [x] Copy root `PROMPT_self_research.md` to `templates/PROMPT_self_research.md` (WHY: without the template, scaffolded projects cannot use `--self` mode's research phase)
- [x] Add `'PROMPT_self_research.md'` to the `TEMPLATE_FILES` array in `bin/cli.js` (WHY: the scaffolder must know about the file to copy it during `npx automaton`)

## 2. Housekeeping

- [x] Stage and commit `.gitignore` (WHY: it is untracked and should be in version control to ensure `.automaton/` runtime state is excluded; committed in af3cdd5)
