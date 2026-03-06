# Spec 37: Session Bootstrap

## Purpose

Each agent invocation starts from a blank context window and must re-discover project state by reading files — the "Phase 0: Load Context" pattern in every prompt. This wastes the first portion of every iteration on file reads that produce identical results. Best practice is to prepare dynamic context BEFORE the agent runs via a bootstrap script, so the agent receives pre-assembled context instead of instructions to go read files.

## Requirements

### 1. Bootstrap Script

Create `.automaton/init.sh` — a bash script that runs before each agent invocation as an orchestrator step (not inside the agent). It assembles all dynamic context into a structured manifest that the agent receives as part of its prompt.

```bash
#!/usr/bin/env bash
# .automaton/init.sh — Session Bootstrap
# Runs BEFORE each agent invocation. Outputs JSON manifest to stdout.
set -euo pipefail

PROJECT_ROOT="${1:-.}"
PHASE="${2:-build}"
ITERATION="${3:-1}"

# Dependency check
check_dependencies() {
    local missing=""
    for cmd in jq git claude; do
        command -v "$cmd" &>/dev/null || missing="$missing $cmd"
    done
    if [ -n "$missing" ]; then
        echo "{\"error\": \"Missing dependencies:$missing\"}"
        exit 1
    fi
}

# State validation
validate_state() {
    local state_file="$PROJECT_ROOT/.automaton/state.json"
    if [ -f "$state_file" ]; then
        jq empty "$state_file" 2>/dev/null || {
            echo "{\"error\": \"state.json is invalid JSON\"}"
            exit 1
        }
    fi
}

# Context summary generation
generate_context() {
    local manifest="{}"

    # Project state
    manifest=$(echo "$manifest" | jq --arg phase "$PHASE" --argjson iter "$ITERATION" \
        '. + {project_state: {phase: $phase, iteration: $iter}}')

    # Current task (from IMPLEMENTATION_PLAN.md)
    if [ -f "$PROJECT_ROOT/IMPLEMENTATION_PLAN.md" ]; then
        local next_task=$(grep -m1 '^\- \[ \]' "$PROJECT_ROOT/IMPLEMENTATION_PLAN.md" | sed 's/^- \[ \] //')
        local total_tasks=$(grep -c '^\- \[' "$PROJECT_ROOT/IMPLEMENTATION_PLAN.md" || echo 0)
        local done_tasks=$(grep -c '^\- \[x\]' "$PROJECT_ROOT/IMPLEMENTATION_PLAN.md" || echo 0)
        manifest=$(echo "$manifest" | jq \
            --arg next "$next_task" \
            --argjson total "$total_tasks" \
            --argjson done "$done_tasks" \
            '.project_state += {next_task: $next, tasks_total: $total, tasks_done: $done}')
    fi

    # Recent changes (last 5 commits)
    local recent_commits=$(git log --oneline -5 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')
    manifest=$(echo "$manifest" | jq --argjson commits "$recent_commits" \
        '. + {recent_changes: $commits}')

    # Budget remaining
    if [ -f "$PROJECT_ROOT/.automaton/budget.json" ]; then
        local budget_remaining=$(jq '.used.estimated_cost_usd' "$PROJECT_ROOT/.automaton/budget.json" 2>/dev/null || echo 0)
        local budget_limit=$(jq '.limits.max_cost_usd' "$PROJECT_ROOT/.automaton/budget.json" 2>/dev/null || echo 50)
        manifest=$(echo "$manifest" | jq \
            --argjson used "$budget_remaining" \
            --argjson limit "$budget_limit" \
            '. + {budget: {used_usd: $used, limit_usd: $limit, remaining_usd: ($limit - $used)}}')
    fi

    # Modified files since last iteration
    local modified_files=$(git diff --name-only HEAD~1 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' || echo '[]')
    manifest=$(echo "$manifest" | jq --argjson files "$modified_files" \
        '. + {modified_files: $files}')

    # Learnings (high-confidence, active)
    if [ -f "$PROJECT_ROOT/.automaton/learnings.json" ]; then
        local learnings=$(jq '[.entries[] | select(.active == true and .confidence == "high") | .summary]' \
            "$PROJECT_ROOT/.automaton/learnings.json" 2>/dev/null || echo '[]')
        manifest=$(echo "$manifest" | jq --argjson learn "$learnings" \
            '. + {learnings: $learn}')
    fi

    echo "$manifest" | jq .
}

check_dependencies
validate_state
generate_context
```

### 2. Bootstrap Integration Point

The orchestrator calls `init.sh` before each `run_agent()` invocation:

```bash
run_agent() {
    local phase="$1"
    local iteration="$2"

    # Bootstrap: generate context manifest
    local manifest
    manifest=$(.automaton/init.sh "$PROJECT_ROOT" "$phase" "$iteration")

    if echo "$manifest" | jq -e '.error' &>/dev/null; then
        log "ORCHESTRATOR" "Bootstrap failed: $(echo "$manifest" | jq -r '.error')"
        return 1
    fi

    # Inject manifest into dynamic context section of prompt
    local dynamic_context="<dynamic_context>
$(echo "$manifest" | jq -r '.')
</dynamic_context>"

    # Assemble prompt: static (from PROMPT_*.md) + dynamic (from bootstrap)
    # ... existing run_agent logic with dynamic_context appended
}
```

### 3. Manifest Schema

The bootstrap outputs a JSON manifest with this schema:

```json
{
  "project_state": {
    "phase": "build",
    "iteration": 7,
    "next_task": "Add budget pacing logic",
    "tasks_total": 25,
    "tasks_done": 12
  },
  "recent_changes": [
    "abc1234 automaton: add rate limit presets",
    "def5678 automaton: implement allowance tracking"
  ],
  "budget": {
    "used_usd": 18.60,
    "limit_usd": 50.00,
    "remaining_usd": 31.40
  },
  "modified_files": [
    "automaton.sh",
    "automaton.config.json"
  ],
  "learnings": [
    "Use kebab-case for all spec filenames",
    "Budget checks run after each iteration, not before"
  ],
  "test_status": {
    "last_run": "2026-03-01T10:30:00Z",
    "passed": 7,
    "failed": 1,
    "failing_tests": ["tests/test_rate_presets.sh"]
  }
}
```

### 4. Replace Phase 0 in All Prompts

With bootstrap providing pre-assembled context, the "Phase 0: Load Context" instructions in all PROMPT_*.md files become unnecessary. Replace them with:

```xml
<dynamic_context>
## Pre-assembled Context
The following context was generated by the bootstrap script. You do NOT need to read these files yourself — the data is already here.

{{BOOTSTRAP_MANIFEST}}

If you need additional context beyond what's provided, read specific files as needed.
</dynamic_context>
```

This eliminates the first N tool calls of every iteration that were spent reading AGENTS.md, IMPLEMENTATION_PLAN.md, specs, and project state files.

### 5. Cold Start Cost Reduction

Measure the cold start cost reduction by comparing:
- **Before bootstrap:** Agent reads 5-10 files in first 3-5 tool calls (~20-50K input tokens for file content)
- **After bootstrap:** Agent receives manifest (~2K tokens) and skips file reads

Expected savings per iteration: 18-48K input tokens (the file content that's now pre-assembled).

Track in budget history:
```json
{
  "bootstrap_tokens_saved": 35000,
  "bootstrap_time_ms": 450
}
```

### 6. Bootstrap Performance Target

The bootstrap script must complete in under 2 seconds. It runs synchronous shell commands (git, jq, file reads) — no network calls, no Claude invocations. If it exceeds 2 seconds, log a warning:

```
[ORCHESTRATOR] WARNING: Bootstrap took 3.2s (target: <2s). Consider optimizing init.sh.
```

### 7. Bootstrap Failure Handling

If `init.sh` fails (missing dependencies, invalid state, script error):

1. Log the error with full stderr output
2. Fall back to legacy behavior: inject empty `<dynamic_context>` and let the agent read files itself
3. Do NOT abort the iteration — bootstrap is an optimization, not a requirement
4. Log: `[ORCHESTRATOR] Bootstrap failed. Falling back to agent-driven context loading.`

### 8. Extensible Bootstrap

The bootstrap script is designed to be extended. Additional context generators can be added as functions within `init.sh` or as separate scripts called by it:

```bash
# Future extensions (not implemented in this spec)
# generate_test_status     → test results summary
# generate_dependency_graph → task dependency visualization
# generate_codebase_stats   → lines of code, file count, complexity
```

The manifest schema is forward-compatible — new fields can be added without breaking existing agents (they ignore unknown fields).

### 9. Configuration

```json
{
  "execution": {
    "bootstrap_enabled": true,
    "bootstrap_script": ".automaton/init.sh",
    "bootstrap_timeout_ms": 2000
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `bootstrap_enabled` | boolean | true | Enable pre-invocation bootstrap |
| `bootstrap_script` | string | ".automaton/init.sh" | Path to bootstrap script |
| `bootstrap_timeout_ms` | number | 2000 | Max time for bootstrap execution |

When `bootstrap_enabled` is `false`, the orchestrator skips bootstrap and uses legacy Phase 0 behavior.

## Acceptance Criteria

- [ ] `.automaton/init.sh` exists and produces valid JSON manifest
- [ ] Bootstrap runs before every agent invocation in the orchestrator
- [ ] Manifest includes: project state, recent changes, budget, modified files, learnings
- [ ] Phase 0 "Load Context" instructions replaced by bootstrap manifest injection
- [ ] Bootstrap completes in under 2 seconds
- [ ] Bootstrap failure falls back gracefully to agent-driven context loading
- [ ] Cold start token savings tracked in budget history
- [ ] `execution.bootstrap_enabled` config flag controls the feature

## Dependencies

- Depends on: spec-33 (context handoff protocol defines what data goes in the manifest)
- Depends on: spec-29 (prompt structure with `<dynamic_context>` section for manifest injection)
- Depends on: spec-34 (learnings.json provides structured learnings for manifest)
- Extends: spec-24 (context summary generation moves from inline to bootstrap)
- Extends: spec-03, spec-04, spec-05, spec-06 (Phase 0 replaced by bootstrap manifest)
- Extends: spec-12 (bootstrap configuration)

## Files to Modify

- `.automaton/init.sh` — new file: bootstrap script
- `automaton.sh` — call `init.sh` before `run_agent()`, inject manifest into dynamic context
- `automaton.config.json` — add `execution.bootstrap_enabled`, `bootstrap_script`, `bootstrap_timeout_ms`
- `PROMPT_research.md` — remove Phase 0, add bootstrap manifest placeholder
- `PROMPT_plan.md` — remove Phase 0, add bootstrap manifest placeholder
- `PROMPT_build.md` — remove Phase 0, add bootstrap manifest placeholder
- `PROMPT_review.md` — remove Phase 0, add bootstrap manifest placeholder
