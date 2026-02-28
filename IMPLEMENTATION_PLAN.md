# Implementation Plan

Automaton is a mature multi-phase orchestrator (specs 01-26) with comprehensive functionality in `automaton.sh` (5249 lines, 98 functions). This plan covers the small number of remaining gaps identified through gap analysis.

## 1. Template Sync — automaton.sh (spec-13)

The root `automaton.sh` (5249 lines) has diverged significantly from `templates/automaton.sh` (4146 lines). Features from specs 22-26 were added to the root but never synced back to the template.

- [x] Copy the root `automaton.sh` to `templates/automaton.sh` to bring the template up to date with specs 22-26 (WHY: the template is 1103 lines behind the root and is missing self-build, journal, weekly allowance, context efficiency, self-targeting, and improvement loop functionality)

## 2. Template Sync — Config (spec-13)

The root `automaton.config.json` has `self_build`, `journal`, `weekly_allowance_tokens`, `allowance_reset_day`, `reserve_percentage`, and `mode` fields that the template lacks.

- [x] Copy the root `automaton.config.json` to `templates/automaton.config.json` to include `self_build`, `journal`, and extended budget fields (WHY: new projects scaffolded from templates would be missing self-build safety, journal, and dual-mode budget configuration)

## 3. Template Sync — Prompt Files (spec-13)

Root prompt files have diverged from their template copies. Specific diffs:

**PROMPT_build.md** — template is missing context_summary/iteration_memory reads, self-modification safety rules (spec-22), self-build mode context section, proportional subagent scaling, and backlog.md references.

**PROMPT_review.md** — template is missing context_summary read, self-build review section (syntax check, dry-run, token usage comparison, protected function audit, self_modifications.json check), and backlog.md task-append path.

**PROMPT_research.md** — template is missing context_summary read and proportional subagent scaling language.

**PROMPT_plan.md** — template is missing context_summary read, proportional subagent scaling language, and updated codebase study instructions.

- [x] Copy the root `PROMPT_build.md` to `templates/PROMPT_build.md` (WHY: template is missing self-build safety rules from spec-22 and context efficiency reads from spec-24)
- [ ] Copy the root `PROMPT_review.md` to `templates/PROMPT_review.md` (WHY: template is missing the entire self-build review section including token usage comparison from spec-25)
- [ ] Copy the root `PROMPT_research.md` to `templates/PROMPT_research.md` (WHY: template is missing context_summary read from spec-24)
- [ ] Copy the root `PROMPT_plan.md` to `templates/PROMPT_plan.md` (WHY: template is missing context_summary read from spec-24 and proportional subagent scaling)

## 4. Housekeeping

- [ ] Stage and commit the `.gitignore` file (WHY: it is untracked per git status and should be part of the repository to ensure `.automaton/` runtime state is excluded from version control)

## Summary

All 26 specs are functionally implemented in the root orchestrator. The remaining work is entirely template synchronization (spec-13) to ensure `automaton.sh --init` scaffolds new projects with the full feature set, plus one housekeeping commit. No new logic or features need to be written.
