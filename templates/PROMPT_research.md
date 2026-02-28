# Phase: Research

You are in RESEARCH mode. You will read all specs, identify unknowns, perform web searches to resolve them, and enrich the specs with concrete technology decisions. You will NOT write any code.

## Phase 0 - Load Context

1. Study `AGENTS.md` for operational guidance (project name, any existing tech preferences).
2. Read `PRD.md` for the high-level vision and architecture overview.
3. If `.automaton/context_summary.md` exists, read it for project state overview.
4. Read every file in `specs/` to understand the full set of requirements.

## Phase 1 - Identify Unknowns

For each spec, identify:
- Technology choices marked as TBD, TODO, or left unresolved
- Libraries or frameworks that need evaluation (e.g., "use a web framework" without specifying which one)
- Patterns or prior art worth investigating for the problem domain
- Security considerations not yet addressed
- Performance constraints that affect technology selection

Compile a list of all unknowns before starting research. This prevents redundant searches and reveals cross-cutting concerns (e.g., one library choice may resolve multiple unknowns).

## Phase 2 - Research

For each unknown, use web search to investigate:
- Compare library options by popularity, maintenance activity, license compatibility, bundle size, and ecosystem fit
- Look for established patterns and best practices in the problem domain
- Check for known gotchas, breaking changes, or anti-patterns
- Verify compatibility between selected technologies (e.g., framework X works with database Y)

Prefer mature, well-maintained libraries over cutting-edge alternatives unless the specs explicitly require otherwise. Favor libraries with permissive licenses (MIT, Apache 2.0, BSD).

## Phase 3 - Enrich Specs

Update spec files with your research findings:
- Replace every TBD/TODO marker with a specific technology choice and rationale
- Add a `## Technology Decisions` section to any spec that required research, listing:
  - The decision made (e.g., "Use Express 4.x for HTTP server")
  - Why this choice over alternatives (e.g., "Mature ecosystem, extensive middleware, team familiarity")
  - Alternatives considered and why they were rejected
- Update version constraints where relevant (e.g., "Node.js >= 18" not just "Node.js")

Be specific. "Use Express 4.x for HTTP server" not "use a web framework". Every decision should be concrete enough that a builder can `npm install` or `pip install` without further research.

## Phase 4 - Update Operational Guide

Update `AGENTS.md` with:
- **Language:** The primary language and version (e.g., "TypeScript 5.x targeting Node.js 20")
- **Framework:** The main framework(s) chosen (e.g., "Next.js 14 (App Router)")
- **Key libraries:** Important library selections with versions
- **Commands:** Build, test, and lint commands if determinable from the technology choices
- **Learnings:** Any operational notes that will help builders (e.g., "Database migrations must run before tests")

## Rules

99. Do NOT write any code. Research and spec enrichment only.
100. Do NOT modify `IMPLEMENTATION_PLAN.md`. That is the planning phase's job.
101. Be specific in every technology decision. Name the library, the version range, and the rationale.
102. Include rationale for every decision: WHY this choice over alternatives.
103. If a spec has no unknowns and needs no research, leave it unchanged.
104. If two specs have conflicting technology needs, note the conflict and propose a resolution.
105. Do NOT modify `CLAUDE.md`. It already points to AGENTS.md.
106. When all unknowns are resolved and all specs are enriched, output <promise>COMPLETE</promise>.
