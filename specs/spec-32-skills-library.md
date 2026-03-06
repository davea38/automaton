# Spec 32: Skills Library

## Purpose

Automaton has recurring workflow patterns embedded as prose in prompts: "read all specs and summarize", "run the validation suite", "load context from AGENTS.md and IMPLEMENTATION_PLAN.md". Claude Code skills (`.claude/skills/`) provide reusable, testable, versioned workflow definitions that reduce prompt size and improve consistency. This spec defines a skills library for automaton's common patterns.

## Requirements

### 1. Skills Directory

Create `.claude/skills/` with skill definition files. Each skill is a markdown file with YAML frontmatter:

```markdown
---
name: spec-reader
description: Read and summarize all spec files in the specs/ directory
tools: Read, Glob, Grep
---

## Instructions

1. Use Glob to find all `specs/spec-*.md` files
2. Read each spec file
3. For each spec, extract: Purpose (first paragraph), Dependencies, Files to Modify
4. Output a structured summary as JSON:

```json
{
  "specs": [
    {
      "id": "spec-01",
      "name": "Orchestrator",
      "purpose": "...",
      "dependencies": [...],
      "files": [...]
    }
  ],
  "total": 26
}
```
```

### 2. Skill Definitions

Define the following skills:

#### spec-reader
**Purpose:** Read and summarize all project specs.
**Tools:** Read, Glob, Grep
**Used by:** Research agent, Plan agent, Review agent
**Replaces:** "Phase 0: Read all specs" instructions in PROMPT_research.md, PROMPT_plan.md, PROMPT_review.md

#### validation-suite
**Purpose:** Run the project's full validation suite (tests, linting, type checking, syntax validation).
**Tools:** Bash, Read
**Used by:** Build agent, Review agent
**Replaces:** Inline validation instructions in PROMPT_build.md and PROMPT_review.md

```markdown
---
name: validation-suite
description: Run the complete validation suite for the project
tools: Bash, Read
---

## Instructions

1. Detect the project type by checking for configuration files:
   - `package.json` → npm test, npm run lint
   - `Makefile` → make test
   - `pytest.ini` / `setup.py` → pytest
   - `automaton.sh` → bash -n automaton.sh, shellcheck automaton.sh (if available)
2. Run each detected validation command
3. Collect results as structured JSON
4. Report pass/fail summary
```

#### context-loader
**Purpose:** Load and assemble context from AGENTS.md, IMPLEMENTATION_PLAN.md, and recent git history.
**Tools:** Read, Bash (git commands only)
**Used by:** All agents at start of each iteration
**Replaces:** "Phase 0: Load Context" instructions in all PROMPT_*.md files

#### plan-updater
**Purpose:** Update IMPLEMENTATION_PLAN.md task checkboxes and add new tasks.
**Tools:** Read, Edit
**Used by:** Build agent (mark tasks complete), Review agent (add fix tasks)
**Replaces:** Inline plan update instructions in PROMPT_build.md

#### self-analysis
**Purpose:** Analyze automaton.sh for self-build: extract function index, identify modification targets, check dependencies between functions.
**Tools:** Read, Grep, Glob
**Used by:** Build agent in self-build mode (spec-22/25)
**Replaces:** Self-build codebase overview generation from spec-24

### 3. Skill Registration in Agent Definitions

Skills are referenced in agent definitions (spec-27) via the `skills` frontmatter field:

```yaml
---
name: automaton-research
skills:
  - spec-reader
  - context-loader
---
```

When an agent starts, referenced skills are loaded into the agent's context at startup. Skills execute as part of the agent's session — they do not spawn separate contexts.

### 4. Prompt Size Reduction

Skills reduce prompt size by extracting reusable patterns from inline instructions. Estimated savings:

| Prompt | Current Pattern | Skill Replacement | Estimated Reduction |
|--------|----------------|-------------------|-------------------|
| PROMPT_research.md | "Read all specs" (15 lines) | `spec-reader` skill | ~15 lines |
| PROMPT_build.md | "Run tests and lint" (20 lines) | `validation-suite` skill | ~20 lines |
| All PROMPT_*.md | "Phase 0: Load Context" (25 lines each) | `context-loader` skill | ~100 lines total |
| PROMPT_build.md | "Update plan checkboxes" (10 lines) | `plan-updater` skill | ~10 lines |
| PROMPT_build.md (self) | "Analyze automaton.sh" (15 lines) | `self-analysis` skill | ~15 lines |

Total estimated prompt reduction: ~160 lines of prose replaced by 5 skill references.

### 5. Skill Versioning

Skills are tracked in git alongside the rest of the project. Version changes are visible in git history. When automaton modifies its own skills (self-build mode), the self-build safety protocol (spec-22) applies — skills are treated as orchestrator files.

### 6. Skill Idempotency

All skills must be idempotent — running a skill multiple times produces the same result. This is critical because skills may re-execute after auto-compaction (spec-33) or on resumed sessions.

- `spec-reader`: always reads current state of specs (idempotent by nature)
- `validation-suite`: runs tests against current code state (idempotent)
- `context-loader`: reads current files (idempotent)
- `plan-updater`: edits are based on current file content (idempotent)
- `self-analysis`: reads current automaton.sh (idempotent)

### 7. Skill Testing

Each skill should have a corresponding test that validates its behavior. Tests live in `tests/skills/`:

```
tests/skills/
  test-spec-reader.sh
  test-validation-suite.sh
  test-context-loader.sh
  test-plan-updater.sh
  test-self-analysis.sh
```

Tests verify that the skill produces expected output format and handles edge cases (empty specs directory, no tests configured, missing AGENTS.md, etc.).

## Acceptance Criteria

- [ ] `.claude/skills/` directory exists with 5 skill definition files
- [ ] Each skill has valid YAML frontmatter with name, description, tools
- [ ] Skills are referenced from agent definitions (spec-27) via `skills` field
- [ ] All PROMPT_*.md "Phase 0" context loading instructions replaced by `context-loader` skill reference
- [ ] Validation instructions in PROMPT_build.md and PROMPT_review.md replaced by `validation-suite` skill reference
- [ ] All skills are idempotent
- [ ] Skills are version-controlled in git

## Dependencies

- Depends on: spec-27 (agent definitions reference skills via frontmatter)
- Extends: spec-03 (research prompt — spec-reader and context-loader replace inline instructions)
- Extends: spec-04 (plan prompt — spec-reader and context-loader replace inline instructions)
- Extends: spec-05 (build prompt — validation-suite, context-loader, plan-updater replace inline instructions)
- Extends: spec-06 (review prompt — validation-suite, spec-reader, context-loader replace inline instructions)
- Extends: spec-24 (self-analysis skill replaces codebase overview generation)

## Files to Modify

- `.claude/skills/spec-reader.md` — new file: spec reading skill
- `.claude/skills/validation-suite.md` — new file: validation skill
- `.claude/skills/context-loader.md` — new file: context loading skill
- `.claude/skills/plan-updater.md` — new file: plan update skill
- `.claude/skills/self-analysis.md` — new file: self-build analysis skill
- `PROMPT_research.md` — replace Phase 0 with skill references
- `PROMPT_plan.md` — replace Phase 0 with skill references
- `PROMPT_build.md` — replace Phase 0 and validation with skill references
- `PROMPT_review.md` — replace Phase 0 and validation with skill references
