# Spec 03: Phase 1 - Research

## Purpose

The research phase reads all specs produced by the conversation phase, identifies gaps and unknowns, performs web searches to resolve them, and enriches the specs with concrete technology decisions. It produces enriched specs, not code.

## How It Runs

```bash
result=$(cat PROMPT_research.md | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model sonnet \
    --verbose)
```

Runs as a single RALPH-style loop iteration. The orchestrator runs up to 3 iterations.

## Prompt Behavior (`PROMPT_research.md`)

The research prompt instructs Claude to:

### Phase 0 - Load Context
1. Read `AGENTS.md` for operational guidance
2. Read `PRD.md` for the high-level vision
3. Read all files in `specs/` to understand requirements

### Phase 1 - Identify Unknowns
For each spec, identify:
- Technology choices marked as TBD or unresolved
- Libraries or frameworks that need evaluation
- Patterns or prior art worth investigating
- Security considerations not yet addressed
- Performance constraints that affect technology selection

### Phase 2 - Research
- Use web search to investigate each unknown
- Compare library options (popularity, maintenance, license, size)
- Look for established patterns for the problem domain
- Check for known gotchas or anti-patterns

### Phase 3 - Enrich Specs
- Update spec files with concrete technology decisions
- Replace TBD/TODO markers with specific choices and rationale
- Add "Technology Decisions" sections to specs that needed research
- Note alternatives that were considered and why they were rejected

### Phase 4 - Update Operational Guide
- Update `AGENTS.md` with:
  - Language and framework choices
  - Key library selections with versions
  - Build/test/lint commands if determinable
  - Any operational notes for builders

### Rules
1. Do NOT write any code. Research and spec enrichment only.
2. Do NOT modify `IMPLEMENTATION_PLAN.md` (that's the planning phase's job).
3. Be specific: "Use Express 4.x for HTTP server" not "use a web framework".
4. Include rationale: WHY this library over alternatives.
5. When everything is enriched, output `<promise>COMPLETE</promise>`.

## Iteration Limits

| Setting | Default | Config Key |
|---------|---------|-----------|
| Max iterations | 3 | execution.max_iterations.research |
| Per-iteration token limit | 500K | budget.per_iteration |
| Phase token budget | 500K | budget.per_phase.research |

## Quality Gate (Gate 2) Checks

After research completes or hits max iterations:

| Check | Method | On Fail |
|-------|--------|---------|
| Research agent signaled COMPLETE | grep output for `COMPLETE</promise>` | Retry (up to max) |
| AGENTS.md grew in content | `wc -l` before vs after | Warning, continue |
| No TBD/TODO remaining in specs | `grep -ri "TBD\|TODO" specs/` | Retry (up to max) |

## Skipping Research

If `--skip-research` flag is passed or `flags.skip_research` is true in config, the orchestrator skips directly to Phase 2 (plan). This is useful when the human has already made all technology decisions during the conversation phase.

## What This Phase Does NOT Do

- Does not write code
- Does not create the implementation plan
- Does not modify the build/review prompts
- Does not install dependencies
