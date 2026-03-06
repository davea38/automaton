# Spec 29: Prompt Engineering for Claude 4.6

## Purpose

Restructure all automaton prompts (`PROMPT_*.md`) to follow Claude 4.6 best practices: adaptive thinking (no manual "Ultrathink"), outcome-oriented instructions (no subagent cardinality), XML-tagged sections, static-first ordering, and guardrails against over-exploration and over-engineering.

## Requirements

### 1. Remove "Ultrathink" Instructions

Claude 4.6 uses adaptive thinking that dynamically decides when and how much to reason. All prompts must remove explicit thinking instructions such as "Ultrathink", "think step by step", or `budget_tokens` directives. The model calibrates thinking depth based on query complexity and the `effort` parameter.

Remove from all `PROMPT_*.md`:
- "Ultrathink" or "think deeply" directives
- Explicit `budget_tokens` values passed to subagent calls
- Instructions to "reason through every possibility"

### 2. Remove Subagent Cardinality Instructions

Claude 4.6 has native parallel tool calling and decides subagent count adaptively. Replace prescriptive cardinality ("use up to 500 parallel Sonnet subagents") with outcome-oriented instructions.

Replace patterns like:
```
Use up to 500 parallel Sonnet subagents to read all specs.
```

With:
```
Read all specs in the specs/ directory. Use subagents proportional to codebase size — for a single-file project, 1-3 subagents suffice; scale up for large multi-file projects. Use subagents when tasks can run in parallel; for simple tasks, work directly.
```

### 3. XML Section Structure for All Prompts

Every `PROMPT_*.md` must use a consistent XML-tagged structure. Tags provide clear semantic boundaries that Claude 4.6 is highly responsive to.

Standard template:

```markdown
<context>
## Project Context
[Specs, PRD, AGENTS.md content or references — STATIC across iterations]
</context>

<identity>
## Agent Identity
[Role definition, phase assignment, model expectations]
</identity>

<rules>
## Rules
[Constraints, file ownership, safety rules, output requirements]
</rules>

<instructions>
## Instructions
[Phase-specific workflow steps — what to do]
</instructions>

<output_format>
## Output Format
[Expected deliverables, commit protocol, result signaling]
</output_format>

<dynamic_context>
## Current State
[Iteration number, recent changes, task assignment, budget remaining — DYNAMIC per iteration]
</dynamic_context>
```

### 4. Static-First Prompt Ordering

All static content (agent identity, rules, project context, specs) must appear BEFORE dynamic content (current task, diffs, iteration state, budget). This ordering is critical for prompt caching (spec-30) — the static prefix must remain identical across iterations to achieve cache hits.

Ordering within `PROMPT_*.md`:
1. `<context>` — project specs, PRD, AGENTS.md (static)
2. `<identity>` — agent role and model expectations (static)
3. `<rules>` — constraints and safety rules (static)
4. `<instructions>` — phase workflow (static)
5. `<output_format>` — deliverable format (static)
6. `<dynamic_context>` — iteration state, diffs, budget (dynamic, injected by orchestrator)

The orchestrator must NOT inject timestamps, iteration numbers, or budget figures into the static prefix sections.

### 5. Replace `<promise>COMPLETE</promise>` Signal

The `<promise>COMPLETE</promise>` pattern is non-standard. Replace with structured result signaling that integrates with file-state verification:

```xml
<result status="complete">
Task: [task description]
Files modified: [list]
Tests passed: [yes/no]
</result>
```

Alternatively, for phases where file-state is the ground truth (build, review), the orchestrator can verify completion by checking git status and task checkboxes rather than relying on agent self-reporting.

### 6. Tone Calibration Per Phase

Claude 4.6 is more responsive to system prompts and may overtrigger on aggressive language. Calibrate prompt tone per phase:

| Phase | Calibration |
|-------|-------------|
| Research | Add "do NOT over-explore" guardrail — 4.6 explores aggressively by default. Scope investigations narrowly. |
| Plan | Remove "be exhaustive" — replace with "cover all tasks needed, no more" |
| Build | Keep direct action language — "Implement completely, no placeholders" is correct tone |
| Review | Remove "be thorough" — Opus 4.6 is already thorough. Add "focus on correctness, not style" |

### 7. Anti-Pattern Guardrails

Add explicit guardrails to all prompts addressing known Claude 4.6 anti-patterns:

```xml
<rules>
- Avoid over-engineering. Only make changes that are directly requested.
- Do not create helper files, utilities, or abstractions for one-time operations.
- Do not add error handling for scenarios that cannot happen.
- Implement solutions that work for all valid inputs, not just test cases.
- For simple file lookups, use Grep/Glob directly instead of spawning subagents.
- Clean up any temporary files created during the task.
- Choose an approach and commit to it. Avoid revisiting decisions.
</rules>
```

### 8. Parallel Tool Calling Directive

Add to all prompts to ensure maximum parallelism for independent tool calls:

```xml
<use_parallel_tool_calls>
If you intend to call multiple tools and there are no dependencies between the calls, make all independent tool calls in parallel in a single message.
</use_parallel_tool_calls>
```

### 9. Prompt Template Standard

Define a canonical template that all `PROMPT_*.md` files must follow. This template is used by the orchestrator to assemble the final prompt:

```
PROMPT_*.md structure:
  Lines 1-N:    Static content (XML-tagged sections: context, identity, rules, instructions, output_format)
  Separator:    <!-- DYNAMIC CONTEXT BELOW — injected by orchestrator -->
  Lines N+1-M:  Dynamic content template (placeholders for orchestrator injection)
```

The orchestrator replaces placeholders in the dynamic section with current iteration state. The static section is never modified between iterations.

## Acceptance Criteria

- [ ] No `PROMPT_*.md` contains "Ultrathink", "think deeply", or explicit `budget_tokens`
- [ ] No `PROMPT_*.md` contains "500 parallel Sonnet subagents" or fixed subagent counts
- [ ] All `PROMPT_*.md` use XML-tagged sections: `<context>`, `<identity>`, `<rules>`, `<instructions>`, `<output_format>`, `<dynamic_context>`
- [ ] Static content precedes dynamic content in all prompts with a clear separator
- [ ] `<promise>COMPLETE</promise>` replaced with `<result status="complete">` or file-state verification
- [ ] Research prompt contains "do NOT over-explore" guardrail
- [ ] Review prompt does not contain "be thorough" or "be exhaustive"
- [ ] All prompts include anti-overengineering guardrails
- [ ] All prompts include parallel tool calling directive

## Dependencies

- Depends on: none (this is the prompt foundation)
- Depended on by: spec-30 (caching requires static-first ordering), spec-27 (native agents reference prompt format), spec-32 (skills extract from prompt patterns), spec-36 (test-first adds to build prompt), spec-37 (bootstrap replaces dynamic context injection)

## Files to Modify

- `PROMPT_research.md` — restructure with XML tags, add over-exploration guardrail, remove cardinality instructions
- `PROMPT_plan.md` — restructure with XML tags, remove "500 subagents", add outcome-oriented instructions
- `PROMPT_build.md` — restructure with XML tags, replace `<promise>COMPLETE</promise>`, add anti-overengineering rules
- `PROMPT_review.md` — restructure with XML tags, remove "be thorough", add focus-on-correctness tone
- `automaton.sh` — update `run_agent()` to inject dynamic context after the static separator instead of prepending
