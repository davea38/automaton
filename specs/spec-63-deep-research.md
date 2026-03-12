# Spec 63: Deep Research Mode

## Purpose

Add open-ended comparative research capability beyond the mechanical TBD resolution of the standard research phase. While the existing research phase (spec-03) resolves specific unknowns in specs (library versions, API choices), deep research explores a problem domain holistically: comparing architectures, evaluating trade-offs, and producing a recommendation document that informs planning.

## Requirements

### 1. Deep Research Prompt

New file `PROMPT_deep_research.md` (~100 lines) that instructs Claude to:

1. **Understand the domain** — Read the topic string, PRD (if exists), and specs (if exist) to understand the project context.
2. **Research 3-5 approaches** — For the given topic, identify 3-5 distinct approaches, architectures, or solutions. Use web search to gather current information.
3. **Produce comparative matrix** — For each approach, evaluate:
   - Pros and cons
   - Complexity (low/medium/high)
   - Ecosystem maturity
   - Learning curve
   - Real-world examples / who uses it
   - Fit with the current project (if PRD/specs exist)
4. **Make a recommendation** — Choose one approach and explain WHY, including what trade-offs are accepted.
5. **Output format** — Structured markdown document with clear sections.

### 2. CLI Interface

```bash
./automaton.sh --research "topic string"
```

| Flag | Argument | Description |
|------|----------|-------------|
| `--research` | Topic string (quoted) | Run standalone deep research on the given topic |

The topic string is injected into the prompt via dynamic context injection (same pattern as bootstrap manifest injection in `lib/context.sh`).

### 3. Output

Research output written to:

```
.automaton/research/RESEARCH-{sanitized-topic}-{timestamp}.md
```

Topic sanitization: lowercase, spaces to hyphens, strip non-alphanumeric except hyphens, truncate to 50 chars.

Example: `--research "state management approaches for React"` → `.automaton/research/RESEARCH-state-management-approaches-for-react-20260312T143022.md`

Multiple research documents can coexist (different topics, different timestamps).

### 4. Document Format

```markdown
# Deep Research: {topic}

**Generated:** {timestamp}
**Project context:** {PRD title or "standalone research"}
**Budget used:** {tokens consumed}

## Executive Summary
[2-3 sentence summary of findings and recommendation]

## Approaches Analyzed

### 1. {Approach Name}
**Overview:** [Brief description]
**Pros:**
- ...
**Cons:**
- ...
**Complexity:** {low|medium|high}
**Ecosystem:** {mature|growing|emerging}
**Used by:** [Notable projects/companies]

### 2. {Approach Name}
[Same structure]

[... up to 5 approaches]

## Comparative Matrix

| Criterion | Approach 1 | Approach 2 | Approach 3 |
|-----------|-----------|-----------|-----------|
| Complexity | ... | ... | ... |
| Performance | ... | ... | ... |
| Ecosystem | ... | ... | ... |
| Learning Curve | ... | ... | ... |
| Project Fit | ... | ... | ... |

## Recommendation

**Recommended:** {Approach Name}

**Rationale:** [Why this approach, what trade-offs are accepted]

**Migration path:** [If the project already has related code, how to adopt]
```

### 5. Configuration

```json
{
  "research": {
    "deep_research_budget": 200000,
    "deep_research_model": "sonnet"
  }
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `research.deep_research_budget` | `200000` | Max tokens for a single deep research run |
| `research.deep_research_model` | `"sonnet"` | Model to use for deep research |

### 6. Budget Enforcement

Deep research tracks tokens against `research.deep_research_budget`. If the budget is exhausted mid-research:
- Gracefully stop the Claude session
- Save partial results with a note: "Research truncated: budget limit reached. Partial results below."
- Exit with code 0 (not a failure, just incomplete)

### 7. Collaborative Mode Integration

In collaborative mode (spec-61), the `after_research` checkpoint offers an additional option:

```
 [c]ontinue  [m]odify  [p]ause  [a]bort  [r]esearch
```

`[r]esearch` prompts: "What topic would you like to research?" and then runs `run_deep_research()` with the user's input. After research completes, the checkpoint re-displays.

### 8. Plan Phase Context

When deep research documents exist in `.automaton/research/`, they are automatically included in the plan phase context. The planning agent reads them alongside specs to make informed architectural decisions.

Implementation: `lib/context.sh` checks for `.automaton/research/RESEARCH-*.md` files and includes them in the plan phase bootstrap.

### 9. Standalone Mode

`--research` works without a PRD or specs. In standalone mode:
- No project context is injected
- Research is purely topic-driven
- Output is still written to `.automaton/research/`
- Useful for pre-project exploration

## Acceptance Criteria

- AC-63-1: `--research "topic"` produces a comparative analysis document in `.automaton/research/`
- AC-63-2: Document contains 3-5 approaches with pros/cons for each
- AC-63-3: Document contains a comparative matrix
- AC-63-4: Document contains a recommendation with reasoning
- AC-63-5: Budget enforced — research stops gracefully if token limit exceeded, partial results saved
- AC-63-6: Research documents persist across runs and multiple documents can coexist
- AC-63-7: Plan phase context includes research documents when they exist
- AC-63-8: `--research` works standalone without PRD or specs
- AC-63-9: In collaborative mode, `after_research` checkpoint offers `[r]esearch` option

## Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Very broad topic ("everything about databases") | Prompt instructs Claude to narrow scope to 3-5 most relevant approaches |
| No PRD/specs exist | Research works in standalone mode, no project context injected |
| Budget exhausted mid-research | Graceful exit with partial results saved and noted |
| Topic string contains special characters | Sanitization strips non-alphanumeric except hyphens |
| Empty topic string | Error: "--research requires a topic string" |
| Multiple `--research` runs same topic | Both coexist (different timestamps in filename) |
| Research document referenced by plan but later deleted | Plan phase handles missing files gracefully (warning, not error) |

## Implementation Touchpoints

| File | Change Type | Summary |
|------|-------------|---------|
| `PROMPT_deep_research.md` | Create | Deep research prompt (~100 lines) |
| `templates/PROMPT_deep_research.md` | Create | Template copy |
| `tests/test_deep_research.sh` | Create | Unit and integration tests |
| `automaton.sh` | Edit | Add `--research` CLI flag and dispatch |
| `lib/config.sh` | Edit | Add `research.deep_research_budget` and `research.deep_research_model` config keys |
| `lib/context.sh` | Edit | Include research documents in plan phase context |
| `lib/collaborate.sh` | Edit | Add `[r]esearch` option to `after_research` checkpoint |
| `lib/display.sh` | Edit | Add `--research` to help text |
| `automaton.config.json` | Edit | Add `research` config section |
| `templates/automaton.config.json` | Edit | Same |

## Dependencies

- **Spec 03** (Research Phase): Parallel capability, does not replace standard research
- **Spec 61** (Collaboration Mode): Integration with collaborative checkpoints
