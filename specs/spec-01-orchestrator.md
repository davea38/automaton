# Spec 01: Orchestrator (`automaton.sh`)

## Purpose

The orchestrator is the master bash script that drives the entire automaton lifecycle. It is NOT an LLM agent. It manages phase transitions, spawns and monitors Claude agents, enforces budgets, handles errors, and persists state. It is the only process that survives across phases.

## Responsibilities

1. Parse CLI arguments (`--resume`, `--skip-research`, `--skip-review`, `--config`)
2. Initialize `.automaton/` directory and state files on first run
3. Drive the phase sequence: research -> plan -> build -> review
4. Spawn Claude agents via `claude -p` with appropriate prompts and models
5. Parse `--output-format stream-json` output to extract token usage
6. Run quality gate checks between phases (delegates to gate functions)
7. Enforce budget limits (delegates to budget module)
8. Handle rate limiting (delegates to rate limit module)
9. Detect and handle errors per the error taxonomy
10. Write state to `.automaton/state.json` after every iteration
11. Log all events to `.automaton/session.log`
12. Handle SIGINT/SIGTERM gracefully (save state, log, exit)

## Phase Sequence

```
[start]
  |
  v
RESEARCH (max 3 iterations)
  |-- Gate 2: Research Completeness
  v
PLAN (max 2 iterations)
  |-- Gate 3: Plan Validity
  v
BUILD (configurable iterations, default unlimited)
  |-- Gate 4: Build Completion
  v
REVIEW (max 2 iterations)
  |-- Gate 5: Review Pass --> COMPLETE
  |-- Gate 5: Review Fail --> back to BUILD with new tasks
```

Phase 0 (converse) is interactive and runs separately before `automaton.sh`.

## Agent Spawning

Each agent is invoked as:

```bash
result=$(cat "$PROMPT_FILE" | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model "$MODEL" \
    --verbose)
```

The orchestrator selects the prompt file and model based on current phase:

| Phase | Prompt File | Model |
|-------|------------|-------|
| research | `PROMPT_research.md` | config.models.research (default: sonnet) |
| plan | `PROMPT_plan.md` | config.models.planning (default: opus) |
| build | `PROMPT_build.md` | config.models.building (default: sonnet) |
| review | `PROMPT_review.md` | config.models.review (default: opus) |

## CLI Interface

```bash
./automaton.sh                  # Start from beginning (Phase 1 if specs exist)
./automaton.sh --resume         # Resume from .automaton/state.json
./automaton.sh --skip-research  # Skip Phase 1, start at Phase 2
./automaton.sh --skip-review    # Skip Phase 4, COMPLETE after build
./automaton.sh --config FILE    # Use alternate config file
./automaton.sh --dry-run        # Show what would happen without running agents
```

## Startup Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 automaton v0.1.0
 Phase:   research
 Budget:  $50.00 max | 10M tokens max
 Config:  automaton.config.json
 Branch:  main
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Inter-Iteration Output

After each iteration, emit a one-line status to stdout:

```
[RESEARCH 1/3] Enriched 3 specs | 45K input / 8K output (~$0.82) | budget: $49.18 remaining
[BUILD 7/~20] Task: Add auth middleware | 112K input / 24K output (~$2.04) | budget: $31.40 remaining
```

## Communication Protocol

Agents do not communicate directly. All coordination happens through shared files:

| Channel | Written By | Read By | Purpose |
|---------|-----------|---------|---------|
| `IMPLEMENTATION_PLAN.md` | Plan, Build, Review | All | Task coordination |
| `AGENTS.md` | Any agent | All | Operational learnings |
| `specs/*.md` | Converse, Research | Plan, Build, Review | Requirements |
| `PRD.md` | Converse | Research, Plan | High-level vision |
| Git history | Build | Review | Implementation details |

## Signal Handling

- `SIGINT` (Ctrl+C): Save state, log `[ORCHESTRATOR] Interrupted by user`, exit 130
- `SIGTERM`: Same as SIGINT
- `SIGHUP`: Ignored (allow running in background)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All phases complete, review passed |
| 1 | General error |
| 2 | Budget exhausted (resumable) |
| 3 | Escalation required (human intervention needed) |
| 130 | Interrupted by user (resumable) |

## Dependencies on Other Specs

- Reads config from: spec-12-configuration
- Uses budget system from: spec-07-token-tracking
- Uses rate limiting from: spec-08-rate-limiting
- Uses error handling from: spec-09-error-handling
- Uses state management from: spec-10-state-management
- Runs quality gates from: spec-11-quality-gates
