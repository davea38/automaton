# Spec 27: Native Subagent Definitions

## Purpose

Automaton currently spawns agents via bare `claude -p` with piped prompt files. Claude Code now provides first-class subagent definitions in `.claude/agents/` — markdown files with YAML frontmatter supporting model selection, tool restrictions, permission modes, hooks, persistent memory, worktree isolation, and background execution. This spec migrates automaton's agent spawning to native subagent definitions, replacing manual prompt piping with structured agent files.

## Requirements

### 1. Agent Definition Files

Create `.claude/agents/` with one definition file per automaton phase agent, plus a self-research agent:

| File | Agent | Phase |
|------|-------|-------|
| `.claude/agents/research.md` | Research agent | Phase 1 |
| `.claude/agents/plan.md` | Plan agent | Phase 2 |
| `.claude/agents/build.md` | Build agent | Phase 3 |
| `.claude/agents/review.md` | Review agent | Phase 4 |
| `.claude/agents/self-research.md` | Self-research agent | Self-targeting (spec-25) |

### 2. Agent Definition Format

Each agent file uses YAML frontmatter with the body serving as the system prompt (replacing the corresponding `PROMPT_*.md` static content):

```markdown
---
name: automaton-research
description: Researches project requirements by analyzing specs, PRD, and codebase
model: sonnet
tools: Read, Glob, Grep, Bash, Agent
permissionMode: bypassPermissions
maxTurns: 50
memory: project
---

<context>
[Static context from PROMPT_research.md]
</context>

<identity>
You are the research agent for the automaton orchestrator...
</identity>

<rules>
[Rules from PROMPT_research.md]
</rules>

<instructions>
[Phase workflow from PROMPT_research.md]
</instructions>

<output_format>
[Expected deliverables]
</output_format>
```

### 3. Frontmatter Field Specifications

Each agent definition must include:

| Field | research | plan | build | review | self-research |
|-------|----------|------|-------|--------|---------------|
| `model` | sonnet | opus | sonnet | opus | opus |
| `tools` | Read, Glob, Grep, Bash, Agent | Read, Glob, Grep, Bash, Write, Edit, Agent | Read, Glob, Grep, Bash, Write, Edit, Agent | Read, Glob, Grep, Bash, Agent | Read, Glob, Grep, Bash, WebSearch, WebFetch, Agent |
| `permissionMode` | bypassPermissions | bypassPermissions | bypassPermissions | bypassPermissions | bypassPermissions |
| `maxTurns` | 50 | 30 | 100 | 50 | 80 |
| `memory` | project | project | project | project | project |
| `background` | false | false | false | false | false |

The `tools` field scopes each agent to only the tools it needs. Research and review agents do not get Write/Edit (they analyze, not modify). Self-research gets web tools for documentation lookup.

### 4. Build Agent Worktree Isolation

In parallel mode (`parallel.enabled: true`), the build agent definition uses worktree isolation:

```yaml
---
name: automaton-builder
isolation: worktree
---
```

This replaces the manual git worktree management in spec-17's builder wrapper script. When `isolation: worktree` is set, Claude Code automatically creates a temporary git worktree, runs the agent in it, and cleans up the worktree if no changes were made.

In single-builder mode (`parallel.enabled: false`), the build agent runs without worktree isolation (writes directly to the working tree), preserving v1 behavior.

### 5. Persistent Memory Replaces AGENTS.md Learnings

Native subagent memory (`memory: project`) stores learnings in `.claude/agent-memory/<name>/MEMORY.md` instead of appending to `AGENTS.md`. This provides:

- Per-agent memory scoping (research learnings separate from build learnings)
- Automatic 200-line inclusion in system prompt
- Self-curating memory with instructions to prune when exceeding limits

The first 200 lines of each agent's `MEMORY.md` are automatically included in the agent's system prompt on each invocation. This replaces the "read AGENTS.md learnings" Phase 0 instructions in current prompts.

Migration: on first run with `agents.use_native_definitions: true`, copy existing `AGENTS.md` learnings section into `.claude/agent-memory/automaton-build/MEMORY.md` (build agent gets the bulk of operational learnings).

### 6. Hooks in Agent Frontmatter

Agent definitions can include scoped hooks (active only while the agent runs):

```yaml
hooks:
  Stop:
    - type: command
      command: ".claude/hooks/write-result-file.sh"
      timeout: 10
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: ".claude/hooks/capture-test-results.sh"
          timeout: 30
```

See spec-31 for full hook definitions. Hooks in agent frontmatter are scoped to the agent's lifecycle and cleaned up when the agent finishes.

### 7. Migration Flag

Add `agents.use_native_definitions` to `automaton.config.json`:

```json
{
  "agents": {
    "use_native_definitions": false
  }
}
```

- `false` (default): current behavior — `claude -p` with piped `PROMPT_*.md` files
- `true`: use `.claude/agents/*.md` definitions, invoke via `claude --agent automaton-research` (or equivalent)

This allows gradual migration. When `use_native_definitions` is `true`, the orchestrator invokes agents via:

```bash
result=$(claude --agent automaton-research \
    --output-format=stream-json \
    --verbose \
    <<< "$DYNAMIC_CONTEXT")
```

The static prompt is in the agent definition file. Only dynamic context (iteration state, task assignment) is piped via stdin.

### 8. Subagent Nesting Constraint

Claude Code subagents cannot spawn other subagents — the `Agent` tool is not available inside subagent definitions (it has no effect). This impacts specs 03-06 which instruct phase agents to "use subagents" for parallel file reading.

When `use_native_definitions` is `true`:
- Phase agents run as the main session (not as subagents), so they CAN use the Agent tool to spawn built-in subagents (Explore, Plan, general-purpose)
- If a phase agent is itself invoked as a subagent (future nested orchestrator scenario), it cannot spawn further subagents — instructions to "use subagents" are ignored silently
- Document this constraint in each agent definition's `<rules>` section

### 9. Skills Reference in Agent Definitions

Agent definitions can reference skills (spec-32) via the `skills` frontmatter field:

```yaml
skills:
  - spec-reader
  - validation-suite
```

Skills are loaded into the agent's context at startup, reducing prompt size by extracting reusable workflow patterns.

## Acceptance Criteria

- [ ] `.claude/agents/` directory exists with 5 agent definition files
- [ ] Each agent definition has valid YAML frontmatter with name, description, model, tools, permissionMode, maxTurns, memory
- [ ] Agent body contains XML-structured prompt content per spec-29 format
- [ ] Build agent uses `isolation: worktree` when parallel mode is active
- [ ] `memory: project` configured for all agents; `.claude/agent-memory/` used for learnings
- [ ] `agents.use_native_definitions` config flag controls migration
- [ ] When flag is true, orchestrator invokes `claude --agent` instead of `claude -p`
- [ ] Subagent nesting constraint documented in agent rules sections

## Dependencies

- Depends on: spec-29 (prompt format with XML sections)
- Depends on: spec-12 (configuration for migration flag)
- Extends: spec-01 (agent spawning mechanism)
- Extends: spec-03, spec-04, spec-05, spec-06 (phase execution via agent definitions)
- Replaces: spec-17 worktree management (when using `isolation: worktree`)
- Extends: spec-24 (persistent memory replaces AGENTS.md learnings append)
- Depended on by: spec-28 (Agent Teams references agent definitions), spec-31 (hooks in agent frontmatter), spec-32 (skills referenced from agent definitions)

## Files to Modify

- `.claude/agents/research.md` — new file: research agent definition
- `.claude/agents/plan.md` — new file: plan agent definition
- `.claude/agents/build.md` — new file: build agent definition
- `.claude/agents/review.md` — new file: review agent definition
- `.claude/agents/self-research.md` — new file: self-research agent definition
- `automaton.sh` — `run_agent()` to support `--agent` invocation when migration flag is true
- `automaton.config.json` — add `agents.use_native_definitions` field
- `AGENTS.md` — document memory migration path
