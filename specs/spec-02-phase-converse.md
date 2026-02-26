# Spec 02: Phase 0 - Converse

## Purpose

Phase 0 is the interactive requirements gathering phase. The human talks to Claude using the standard `claude` command (NOT `claude -p`). Claude interviews the human, challenges vague requirements, and produces structured spec files and a PRD.

This is the only phase that requires human interaction. It runs before `automaton.sh`.

## How It Runs

```bash
claude                          # Standard interactive mode
# Claude loads PROMPT_converse.md as system context via CLAUDE.md reference
```

Unlike all other phases, this is NOT driven by the orchestrator. The human runs `claude` directly in the project directory where automaton was scaffolded.

## Prompt Behavior (`PROMPT_converse.md`)

The converse prompt instructs Claude to:

1. **Greet and orient.** Acknowledge the project, explain that this is the requirements phase.
2. **Interview.** Ask probing questions about what the human wants to build. Focus on:
   - Core functionality (what does it DO?)
   - Users (who is it FOR?)
   - Constraints (what technology, what timeline, what budget?)
   - Non-functional requirements (performance, security, scale)
3. **Challenge vagueness.** If the human says "make it fast" or "good UX", push for specifics.
4. **Write specs.** As requirements crystallize, write numbered spec files:
   - `specs/spec-01-[topic].md` through `specs/spec-NN-[topic].md`
   - Each spec covers one coherent feature or subsystem
   - Each spec has: Purpose, Requirements (numbered), Acceptance Criteria, Dependencies
5. **Write PRD.md.** Summarize the full vision, problem statement, and high-level architecture.
6. **Update AGENTS.md.** Set the project name, language, and framework fields.
7. **Signal completion.** When the human says something like "specs are complete" or "that's everything", confirm the handoff:
   ```
   Specs are written. Run ./automaton.sh to begin autonomous execution.
   ```

## Spec File Format

Each spec file follows this template:

```markdown
# Spec NN: [Topic Name]

## Purpose
[One paragraph explaining what this spec covers and why it matters]

## Requirements
1. [Specific, testable requirement]
2. [Another requirement]
...

## Acceptance Criteria
- [ ] [Verifiable criterion]
- [ ] [Another criterion]

## Dependencies
- Depends on: [other spec numbers, if any]
- Depended on by: [other spec numbers, if any]
```

## Quality Gate (Gate 1) Preconditions

Before `automaton.sh` will start, these must be true:
- At least one `specs/*.md` file exists
- `PRD.md` exists and has > 0 lines
- `AGENTS.md` has a non-placeholder project name (not "thesis-map" or "(to be determined)")

If these fail, `automaton.sh` refuses to start and tells the human to run the conversation phase first.

## What This Phase Does NOT Do

- Does not run autonomously (requires human in the loop)
- Does not write any code
- Does not make technology choices (that's the research phase)
- Does not create the implementation plan (that's the planning phase)

## Open Question

The exact handoff mechanism is TBD. Options:
1. Human manually runs `./automaton.sh` after conversation (simplest)
2. Claude outputs `<promise>SPECS_COMPLETE</promise>` and a wrapper script detects it
3. A marker file `.automaton/specs_ready` is created

Option 1 is recommended for v1.
