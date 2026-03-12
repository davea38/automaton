# Spec 61: Collaboration Mode and Checkpoints

## Purpose

Transform automaton from a "walk away" autonomous factory into a system that can pause at phase transitions, explain what happened and what's coming, and let the user approve, modify, pause, or abort. This is the foundation for automaton's mentor/collaborative persona.

## Requirements

### 1. Configuration

New config key `collaboration` with the following schema:

```json
{
  "collaboration": {
    "mode": "collaborative",
    "checkpoint_dir": ".automaton/checkpoints"
  }
}
```

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `collaboration.mode` | `"collaborative"`, `"supervised"`, `"autonomous"` | `"collaborative"` | Controls checkpoint behavior |

- `"collaborative"` — Default for new projects. Pauses at all phase transitions with educational annotations.
- `"supervised"` — Pauses at phase transitions only (identical to collaborative for now since build checkpoints are phase-transition-only). Reserved for future differentiation.
- `"autonomous"` — Current behavior. Zero pauses, zero prompts, zero educational annotations.

### 2. CLI Flag

| Flag | Argument | Default |
|------|----------|---------|
| `--mode` | `collaborative\|supervised\|autonomous` | None (uses config) |

CLI flag overrides the config file value. If neither is set, default is `"collaborative"`.

### 3. Core Module: `lib/collaborate.sh`

New module (~250 lines) providing the checkpoint system.

**Core function:** `checkpoint(name)`

```bash
# checkpoint "after_research"
# checkpoint "after_plan"
# checkpoint "after_review"
```

The function:
1. Checks if collaboration mode is `"autonomous"` — if so, returns immediately (no-op).
2. Checks if stdin is a TTY (`[[ -t 0 ]]`) — if not a TTY (CI, piped, background), returns immediately (no-op).
3. Generates a structured summary of what just happened (phase-specific).
4. Writes the summary to `.automaton/checkpoints/checkpoint-{name}-{timestamp}.md`.
5. Displays the summary to the user.
6. Presents choices: `[c]ontinue / [m]odify / [p]ause / [a]bort`
7. Waits for user input (no timeout — user may walk away and come back).
8. Dispatches based on choice.

### 4. Checkpoint Locations

Checkpoints fire at exactly 3 phase-transition points:

| Checkpoint Name | When | Summary Contents |
|-----------------|------|------------------|
| `after_research` | After research phase completes, before plan phase begins | Technology decisions, library choices, alternatives considered, specs modified, TBDs resolved |
| `after_plan` | After plan phase completes, before build phase begins | Task breakdown, dependency order, estimated complexity, files to be created/modified |
| `after_review` | After review phase completes, before complete/loop-back decision | Test results, spec coverage, review confidence score, what the system plans to do next (complete vs. loop back) |

### 5. Checkpoint Summary Format

Each checkpoint displays a structured summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CHECKPOINT: Research → Plan
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## What Just Happened
- Researched 12 TBDs across 5 specs
- Resolved 10 technology decisions
- 2 TBDs remain (non-blocking)

## Key Decisions
- Database: PostgreSQL 16 (chosen over MySQL for JSON support)
- Auth: JWT with refresh tokens (chosen over sessions for API-first architecture)
- Framework: Express.js 5 (chosen over Fastify for ecosystem maturity)

## Why These Choices
[Brief rationale for the most impactful decisions]

## What's Next
Plan phase will decompose specs into implementation tasks,
ordered by dependency. Estimated 15-20 tasks.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [c]ontinue  [m]odify  [p]ause  [a]bort
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 6. Choice Actions

| Choice | Behavior |
|--------|----------|
| `[c]ontinue` | Returns from `checkpoint()`, execution resumes immediately |
| `[m]odify` | Launches an interactive `claude` session with relevant context files loaded (specs, plan, review report). User makes changes interactively. After the session exits, checkpoint re-displays the updated summary and re-prompts. |
| `[p]ause` | Writes current state to `.automaton/state.json` (including `checkpoint_paused_at` field), exits with code 0. Resumable via `--resume`. |
| `[a]bort` | Writes current state (preserving work done so far), exits with code 1. |

**`[m]odify` context by checkpoint:**

| Checkpoint | Files loaded into interactive session |
|------------|--------------------------------------|
| `after_research` | All specs in `specs/`, `AGENTS.md` |
| `after_plan` | `IMPLEMENTATION_PLAN.md`, all specs, `AGENTS.md` |
| `after_review` | `.automaton/traceability.json`, review report, `IMPLEMENTATION_PLAN.md` |

### 7. Pause and Resume

When `[p]ause` is selected:
- `state.json` updated with `"checkpoint_paused_at": "after_research"` (or whichever checkpoint)
- Process exits with code 0 (clean exit, not failure)
- User can resume with `./automaton.sh --resume`

When `--resume` detects a `checkpoint_paused_at` field:
- Regenerate the checkpoint summary from current state (do NOT cache stale summaries)
- Re-display the checkpoint and re-prompt the user
- If the user `[c]ontinue`s, clear `checkpoint_paused_at` and proceed to the next phase

### 8. TTY Detection

```bash
checkpoint() {
    local name="$1"

    # Silent no-op in autonomous mode
    [[ "$COLLABORATION_MODE" == "autonomous" ]] && return 0

    # Silent no-op when stdin is not a TTY (CI, piped, background)
    [[ ! -t 0 ]] && return 0

    # ... checkpoint logic ...
}
```

This ensures:
- CI pipelines don't hang waiting for input
- Piped input (`echo "specs" | ./automaton.sh`) doesn't break
- Background execution (`./automaton.sh &`) doesn't block

### 9. Checkpoint Audit Trail

Every checkpoint writes a markdown file to `.automaton/checkpoints/`:

```
.automaton/checkpoints/
├── checkpoint-after_research-20260312T143022.md
├── checkpoint-after_plan-20260312T144511.md
└── checkpoint-after_review-20260312T150833.md
```

Each file contains the full summary that was displayed, plus the user's choice and timestamp.

### 10. Educational Annotations

When `collaboration.mode` is `"collaborative"`, inject educational context into phase prompts via dynamic context injection in `lib/context.sh`:

| Prompt | Injection | Purpose |
|--------|-----------|---------|
| `PROMPT_research.md` | "Why This Matters" block explaining the research phase's role | Help user understand why automated research matters |
| `PROMPT_plan.md` | "Rationale" instructions asking the planning agent to explain WHY each task matters, not just WHAT | Help user learn task decomposition reasoning |
| `PROMPT_review.md` | "Learning Opportunity" section asking the review agent to highlight patterns, anti-patterns, and teaching moments | Help user learn from the review process |

These are injected dynamically — the prompt files themselves are NOT modified. Instead, `lib/context.sh` appends educational blocks when building the prompt context, gated on `COLLABORATION_MODE != "autonomous"`.

### 11. Setup Wizard Integration

Update the setup wizard in `lib/config.sh` (`run_setup_wizard()`) to ask:

```
How would you like automaton to work?

  1. Collaborative (recommended) — Pauses at key milestones to explain
     decisions and get your approval. Best for learning and oversight.

  2. Autonomous — Runs end-to-end without stopping. Best for experienced
     users who want to walk away and come back to results.

Choice [1]:
```

Default: 1 (collaborative). Sets `collaboration.mode` in config.

## Acceptance Criteria

- AC-61-1: `./automaton.sh --mode collaborative` pauses at all 3 phase transitions
- AC-61-2: `./automaton.sh --mode autonomous` has zero pauses (regression test against current behavior)
- AC-61-3: Each checkpoint displays an accurate summary of what the just-completed phase produced
- AC-61-4: `[c]ontinue` resumes execution immediately with no delay
- AC-61-5: `[m]odify` opens an interactive Claude session with the correct context files for that checkpoint
- AC-61-6: `[p]ause` writes state and exits with code 0; `--resume` regenerates and re-displays the checkpoint
- AC-61-7: `[a]bort` exits with code 1, state preserved
- AC-61-8: Non-TTY execution (piped stdin, CI, background) skips all checkpoints silently
- AC-61-9: Checkpoint audit files written to `.automaton/checkpoints/` with correct content
- AC-61-10: `--mode` CLI flag overrides config file setting
- AC-61-11: Educational annotations injected in collaborative mode, absent in autonomous mode

## Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Non-TTY stdin (CI/piped) | Checkpoints are silent no-ops, execution continues |
| `--resume` after `[p]ause` | Regenerates checkpoint summary from current state, re-prompts |
| `--mode` flag + config file conflict | CLI flag wins |
| No timeout on checkpoint input | User may walk away and come back; no timeout |
| Invalid `--mode` value | Error: "Invalid mode 'xyz'. Valid values: collaborative, supervised, autonomous" |
| `--mode` + `--self` | Allowed: self-build can run in any mode |
| Checkpoint after empty research (nothing changed) | Summary says "No changes made" but still pauses for approval |

## Implementation Touchpoints

| File | Change Type | Summary |
|------|-------------|---------|
| `lib/collaborate.sh` | Create | Core checkpoint system (~250 lines) |
| `tests/test_collaborate.sh` | Create | Unit and integration tests |
| `automaton.sh` | Edit | Source `lib/collaborate.sh`; add `--mode` flag parsing; call `checkpoint()` at phase transitions |
| `lib/config.sh` | Edit | Add `collaboration` config section; update `run_setup_wizard()` |
| `lib/context.sh` | Edit | Add educational annotation injection gated on collaboration mode |
| `lib/display.sh` | Edit | Add `--mode` to help text |
| `automaton.config.json` | Edit | Add `collaboration` section with defaults |
| `templates/automaton.config.json` | Edit | Same |

## Dependencies

None — this is the foundation the other specs (62, 63, 64) build on.
