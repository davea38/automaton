# Spec 62: Project Idea Garden

## Purpose

Reuse the garden infrastructure (seed/sprout/bloom lifecycle from spec-38) to suggest features, improvements, and best practices for the *user's project* — not automaton itself. The existing garden in `.automaton/garden/` is automaton's self-improvement garden. This spec creates a parallel garden in `.automaton/project-garden/` that thinks about the user's software.

## Requirements

### 1. Configuration

New config section `project_garden`:

```json
{
  "project_garden": {
    "enabled": true,
    "suggest_after_research": true,
    "suggest_after_review": true,
    "max_suggestions_per_cycle": 5
  }
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `project_garden.enabled` | `true` when `collaboration.mode` is `"collaborative"`, `false` when `"autonomous"` | Master toggle |
| `project_garden.suggest_after_research` | `true` | Generate stack-specific suggestions after research |
| `project_garden.suggest_after_review` | `true` | Generate implementation-informed suggestions after review |
| `project_garden.max_suggestions_per_cycle` | `5` | Cap on suggestions per generation cycle |

### 2. Suggestion Prompt

New file `PROMPT_suggest.md` (~80 lines) that instructs Claude to:

1. Read the project's PRD, specs, and any existing source code.
2. Analyze for gaps across these categories:
   - **Missing features** — functionality implied by specs but not explicitly specified
   - **Security improvements** — authentication, authorization, input validation, secrets management
   - **UX enhancements** — error messages, loading states, accessibility, responsive design
   - **Performance optimizations** — caching, query optimization, lazy loading, pagination
   - **Accessibility considerations** — ARIA labels, keyboard navigation, screen reader support
   - **Testing gaps** — untested edge cases, missing integration tests, error path coverage
3. Produce up to `max_suggestions_per_cycle` suggestions.
4. Each suggestion includes: title, category, rationale, estimated complexity (low/medium/high), and which spec it relates to.
5. Output as JSON array matching the garden seed format.

### 3. Core Function

New function `run_project_suggestions()` in `lib/garden.sh`:

```bash
run_project_suggestions() {
    local trigger="$1"  # "after_research" or "after_review"

    # Check if enabled
    local enabled
    enabled=$(config_get "project_garden.enabled" "true")
    [[ "$enabled" != "true" ]] && return 0

    # Check trigger-specific toggle
    local trigger_key="project_garden.suggest_${trigger}"
    local trigger_enabled
    trigger_enabled=$(config_get "$trigger_key" "true")
    [[ "$trigger_enabled" != "true" ]] && return 0

    # Build context and call claude with PROMPT_suggest.md
    # Store results in .automaton/project-garden/
}
```

### 4. Storage

Suggestions stored in `.automaton/project-garden/` using the existing garden data format:

```
.automaton/project-garden/
├── seeds.json          # Raw suggestions (seed stage)
├── sprouts.json        # User-acknowledged suggestions (sprout stage)
├── blooms.json         # User-approved suggestions ready for implementation (bloom stage)
└── history.json        # Archived/dismissed suggestions
```

Each suggestion entry follows the garden schema:

```json
{
  "id": "pg-20260312-001",
  "title": "Add rate limiting to public API endpoints",
  "category": "security",
  "rationale": "Specs define public API endpoints but no rate limiting. Without it, the API is vulnerable to abuse.",
  "complexity": "medium",
  "related_spec": "spec-03-api-endpoints.md",
  "stage": "seed",
  "source_trigger": "after_research",
  "created_at": "2026-03-12T14:30:22Z",
  "support_count": 0
}
```

### 5. Suggestion Seeding Points

| Trigger | When | Context Available | Suggestion Focus |
|---------|------|-------------------|------------------|
| `after_research` | Research phase complete | PRD, specs with resolved TBDs, technology choices | Stack-specific: library features, framework patterns, known pitfalls |
| `after_review` | Review phase complete | All of the above + built code + test results + review report | Implementation-informed: code quality, test gaps, architectural concerns |

### 6. Display Integration

**Collaborative mode:** Suggestions presented at the relevant checkpoint (spec-61). Added as a "Suggestions" section in the checkpoint summary:

```
## Project Suggestions (3 new)
  1. [security] Add rate limiting to public API endpoints (medium)
  2. [testing] Add integration tests for database error paths (low)
  3. [ux] Add loading states to async operations (low)

Type 's' to explore suggestions, or choose an action:
 [c]ontinue  [m]odify  [p]ause  [a]bort  [s]uggestions
```

**Autonomous mode:** Suggestions written silently to `.automaton/project-suggestions.md` (human-readable summary) and to `.automaton/project-garden/seeds.json` (machine-readable).

### 7. CLI Commands

| Command | Description |
|---------|-------------|
| `--suggest` | Run a one-shot suggestion cycle: analyze current specs/code and display results |
| `--project-garden` | Display current project suggestions across all stages (seeds, sprouts, blooms) |

`--suggest` works standalone (outside of a full automaton run). It reads whatever specs/code exist and generates suggestions.

### 8. Garden Separation

The project garden (`project-garden/`) and the evolution garden (`garden/`) must be completely separate:

- Different directories under `.automaton/`
- Different JSON files
- Different ID prefixes (`pg-` for project garden, existing prefixes for evolution garden)
- Garden functions in `lib/garden.sh` accept a `garden_dir` parameter to operate on either
- No cross-contamination: evolution suggestions never appear in project garden and vice versa

## Acceptance Criteria

- AC-62-1: `--suggest` produces relevant suggestions for a project with specs and/or code
- AC-62-2: Suggestions stored in `.automaton/project-garden/seeds.json` as valid JSON
- AC-62-3: Project garden directory (`.automaton/project-garden/`) is separate from evolution garden (`.automaton/garden/`)
- AC-62-4: Collaborative mode shows suggestions at checkpoints with `[s]uggestions` option
- AC-62-5: Autonomous mode writes suggestions to `.automaton/project-suggestions.md` silently
- AC-62-6: `--project-garden` displays current suggestions across all stages
- AC-62-7: `max_suggestions_per_cycle` config is respected
- AC-62-8: Garden functions work with both garden directories without cross-contamination

## Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| No specs exist yet | `--suggest` fails gracefully: "No specs found. Run the converse phase first to generate specs." |
| Empty PRD, specs exist | Use specs only for suggestion context |
| No code exists (pre-build) | Suggestions focus on spec-level gaps only, skip code quality suggestions |
| Garden functions called with wrong directory | `garden_dir` parameter prevents cross-contamination |
| `--suggest` with no config file | Uses defaults (enabled, max 5 suggestions) |
| Suggestion duplicates across cycles | De-duplicate by title similarity before storing |

## Implementation Touchpoints

| File | Change Type | Summary |
|------|-------------|---------|
| `PROMPT_suggest.md` | Create | Suggestion generation prompt (~80 lines) |
| `templates/PROMPT_suggest.md` | Create | Template copy |
| `tests/test_project_garden.sh` | Create | Unit and integration tests |
| `lib/garden.sh` | Edit | Add `run_project_suggestions()`, parameterize garden functions with `garden_dir` |
| `lib/collaborate.sh` | Edit | Add suggestion display to checkpoint summaries |
| `automaton.sh` | Edit | Add `--suggest` and `--project-garden` CLI flags |
| `lib/config.sh` | Edit | Add `project_garden` config section |
| `lib/display.sh` | Edit | Add `--suggest` and `--project-garden` to help text |
| `automaton.config.json` | Edit | Add `project_garden` section |
| `templates/automaton.config.json` | Edit | Same |

## Dependencies

- **Spec 38** (Idea Garden): Reuses garden data format and lifecycle concepts
- **Spec 61** (Collaboration Mode): Suggestions display at checkpoints in collaborative mode
