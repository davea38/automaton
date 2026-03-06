# Spec 59: Requirements Wizard

## Priority

P1 -- The single biggest onboarding friction point. Users currently must know
to run `claude` manually before `./automaton.sh` will work. Gate 1 fails with
a cryptic message. This wizard eliminates the gap entirely: run
`./automaton.sh` and it just works.

## Purpose

When `./automaton.sh` detects no specs (Gate 1 failure), launch a structured
multi-stage wizard that wraps interactive `claude` sessions to interview the
user, generate spec files, PRD.md, and AGENTS.md, then seamlessly continue
into autonomous execution. The user's entire journey becomes a single command.

## Requirements

### 1. Trigger Behavior

The wizard auto-launches when ALL of the following are true:
- Gate 1 (`spec_completeness`) fails (no spec files, or PRD.md missing/empty)
- stdin is a TTY (`[ -t 0 ]`)
- `--no-wizard` was not passed

When stdin is NOT a TTY and Gate 1 fails, print an actionable error and
exit 1:
```
Error: No spec files found and stdin is not a TTY.
Run './automaton.sh' in an interactive terminal to start the requirements wizard,
or run 'claude' manually to complete the conversation phase.
```

### 2. CLI Flags

| Flag           | Behavior                                                    |
|----------------|-------------------------------------------------------------|
| `--wizard`     | Force-run the wizard even if specs already exist.           |
| `--no-wizard`  | Skip the wizard; fail at Gate 1 as before (exit 1).        |

Mutually exclusive. Passing both exits 1 with an error message.

When `--wizard` is used and specs already exist, display a confirmation
prompt before proceeding:
```
Existing specs found in specs/. The wizard will overwrite them.
Continue? (yes/no) [no]:
```
Accepting proceeds. Declining exits with a message.

### 3. Wizard Structure: 6 Stages

The wizard is a bash function (`requirements_wizard()`) that orchestrates a
single interactive `claude` session. Claude is launched with a wizard-specific
system prompt (`PROMPT_wizard.md`) that structures the conversation into 6
stages.

At each stage, Claude asks probing questions about the stage's topic. The
conversation within each stage continues until either:
- Claude determines it has enough information and proposes moving on
- The user says "next", "ready", "move on", "done with this", or similar

Claude manages stage transitions internally, printing clear visual headers:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 STAGE 1 OF 6: PROJECT OVERVIEW
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Stage 1 — Project Overview**
Claude asks about: what the project does, what problem it solves, who has the
problem, what the minimum viable version (v1) looks like. Claude challenges
vague answers ("make it good" → "what does good mean for this use case?").

**Stage 2 — Users & Workflows**
Claude asks about: target users, how technical they are, the primary
step-by-step workflow, secondary workflows if any.

**Stage 3 — Core Features**
Claude asks the user to list key features, then digs into each one for
specifics. Challenges vague features until requirements are testable. This is
typically the longest stage.

**Stage 4 — Constraints & Preferences**
Claude asks about: technology preferences (language, framework, hosting),
performance targets, security requirements, scale expectations. Accepts "no
preference" / "standard" / "none" as valid answers and moves on quickly.

**Stage 5 — Boundaries**
Claude asks about: what is explicitly out of scope for v1, anything else the
system should know. Brief stage.

**Stage 6 — Review & Generate**
Claude summarizes everything gathered across stages 1-5, asks for final
confirmation, then generates all artifacts:
- Spec files in `specs/` (one per feature/subsystem, numbered)
- `PRD.md` with project vision, problem, users, architecture, stories
- Updated `AGENTS.md` with project name, language/framework preferences

Claude writes files incrementally and reports each one created. When
complete, Claude tells the user the wizard is done and they can exit.

### 4. New Prompt File: PROMPT_wizard.md

A new prompt file that replaces PROMPT_converse.md for the wizard flow. It
MUST instruct Claude to:

1. Act as a structured interviewer, not a free-form conversationalist
2. Move through exactly 6 stages in order with clear visual headers
3. Ask probing questions at each stage — same depth as PROMPT_converse.md
4. Challenge vague requirements until they are specific and testable
5. Allow the user to say "next" or "ready" to advance at any point
6. Propose moving on when satisfied (don't interrogate endlessly)
7. Write spec files using the standard template (Purpose, Requirements,
   Acceptance Criteria, Dependencies) as requirements crystallize
8. At Stage 6, generate all remaining artifacts and signal completion
9. NEVER write code or make technology decisions (same as PROMPT_converse.md)
10. Keep the tone friendly and encouraging, not interrogative

The prompt should include the spec file template (same as PROMPT_converse.md
Phase 2) and the PRD template (same as PROMPT_converse.md Phase 3).

### 5. Bash Integration

#### requirements_wizard() Function

```
requirements_wizard()
├── Non-TTY guard (return 1 if not interactive)
├── Overwrite check (if --wizard and specs exist, confirm)
├── Print wizard banner with instructions
├── Launch claude interactively with PROMPT_wizard.md context
├── On claude exit:
│   ├── Re-check Gate 1 (spec_completeness)
│   ├── PASS → return 0 (orchestrator continues)
│   └── FAIL → print what's missing, return 1
└── return code
```

The function lives in `automaton.sh`, called from the modified Gate 1 failure
path in `run_orchestration()`.

#### Gate 1 Modification

Replace the current Gate 1 failure behavior (lines ~16502-16506):
```
# Current:
echo "Gate 1 (spec completeness) failed. Run the conversation phase first."
exit 1

# New:
if [ -t 0 ] && [ "$ARG_NO_WIZARD" != "true" ]; then
    requirements_wizard || exit 1
    # Re-check Gate 1 after wizard
    gate_check "spec_completeness" || {
        echo "Wizard completed but specs are incomplete. Check specs/ and PRD.md."
        exit 1
    }
else
    echo "Gate 1 failed. Run './automaton.sh' interactively for the requirements wizard."
    exit 1
fi
```

#### Claude Invocation

The wizard launches `claude` with the wizard prompt injected as system
context. The exact mechanism depends on Claude CLI capabilities:

- **Preferred**: `claude --system-prompt "$(cat PROMPT_wizard.md)"` if
  supported in interactive mode
- **Alternative**: Temporarily prepend PROMPT_wizard.md content to CLAUDE.md,
  launch `claude`, restore CLAUDE.md on exit (trap for cleanup)
- **Alternative**: Use `claude -p` with an initial message that includes the
  wizard prompt, then `--resume` for interactive continuation

The implementation should use whichever mechanism the Claude CLI supports for
injecting a system prompt into an interactive session.

### 6. Claude as Prerequisite

`claude` CLI is already checked as a required dependency at startup
(automaton.sh lines 13154-13156). The wizard adds no new dependencies. The
wizard REQUIRES interactive `claude` (not just `claude -p`), which is
guaranteed by the TTY check.

### 7. Post-Wizard Flow

After `requirements_wizard()` returns 0:
1. Gate 1 passes (re-checked inside the function)
2. `run_orchestration()` continues normally
3. Research → Plan → Build → Review proceeds autonomously
4. The user sees no interruption — wizard flows into autonomous execution

### 8. PROMPT_converse.md Preservation

The existing `PROMPT_converse.md` is NOT modified or removed. It remains
available for power users who prefer the free-form interview by running
`claude` manually. The wizard is a structured alternative, not a replacement.

## Acceptance Criteria

- [ ] Running `./automaton.sh` with no specs launches the wizard automatically
- [ ] The wizard guides through 6 stages with clear visual stage headers
- [ ] At each stage, Claude asks probing questions about the stage's topic
- [ ] User can say "next" / "ready" to advance stages at any point
- [ ] Claude proposes advancing when it has enough information
- [ ] Vague requirements are challenged (not accepted as-is)
- [ ] Spec files are generated in `specs/` following the standard template
- [ ] PRD.md is generated with vision, problem, users, architecture, stories
- [ ] AGENTS.md is updated with project name and preferences
- [ ] After wizard completion, autonomous execution continues seamlessly
- [ ] `--wizard` re-runs the wizard with overwrite confirmation
- [ ] `--no-wizard` skips the wizard and fails at Gate 1 as before
- [ ] `--wizard` + `--no-wizard` together exits with error code 1
- [ ] Non-TTY stdin prints actionable error and exits 1
- [ ] Ctrl+C during wizard does not corrupt state (re-runnable)
- [ ] PROMPT_converse.md is unchanged (preserved for manual use)
- [ ] New PROMPT_wizard.md is created with stage-structured instructions

## Design Considerations

- **Single claude session**: One interactive `claude` session for the entire
  wizard (not one per stage). Claude self-manages stage transitions within the
  session. This preserves full context across stages and avoids the overhead of
  launching multiple `claude` processes.
- **No wizard state persistence**: If interrupted, the user re-runs from
  scratch. The wizard is designed to take 5-15 minutes — fast enough that
  re-entering answers is not burdensome. No `.automaton/wizard-state.json`.
- **Spec quality**: The wizard prompt must reproduce the same quality bar as
  PROMPT_converse.md. Requirements must be specific and testable. Each spec
  covers one coherent feature. Dependencies are tracked.
- **Budget awareness**: The wizard uses interactive Claude (included in Claude
  Code subscription or API billing). It does NOT consume the automaton budget
  configured in `automaton.config.json` — that budget is for autonomous phases.

## Dependencies

- **Depends on**: spec-01 (Orchestrator) — argument parser, `run_orchestration()`
- **Depends on**: spec-11 (Quality Gates) — Gate 1 `spec_completeness` check
- **Depends on**: spec-02 (Converse Phase) — spec template, PRD template, quality bar
- **Related**: spec-57 (Setup Wizard) — structural pattern for bash wizard functions
- **Related**: spec-12 (Configuration) — wizard runs before config matters

## Files to Modify

- `automaton.sh` — Add `requirements_wizard()` function (~50-80 lines), modify
  Gate 1 failure path in `run_orchestration()`, add `--wizard`/`--no-wizard`
  flags to arg parser and `_show_help()`.
- New `PROMPT_wizard.md` — Stage-structured interview prompt for Claude
  (~100-150 lines, similar scope to PROMPT_converse.md).
- `bin/cli.js` — Update scaffolder banner to mention that `./automaton.sh`
  handles everything (remove "Run 'claude' first" step).
