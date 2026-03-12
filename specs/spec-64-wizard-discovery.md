# Spec 64: Enhanced Wizard with Discovery Stage

## Purpose

Transform the converse phase from a structured interrogation into guided exploration, especially for users who arrive with vague ideas. Currently, the wizard (spec-59) and converse prompt (spec-02) assume the user knows what they want to build. Many users don't — they have a rough problem space but need help converging on a concrete concept.

## Requirements

### 1. Discovery Stage (Stage 0)

Add a new Stage 0 (Discovery) to `PROMPT_wizard.md` that activates when the user's initial description is vague.

**Vagueness detection heuristics** (handled entirely within the prompt — Claude detects these patterns):
- Fewer than 2 complete sentences
- Hedging language: "something like", "maybe", "not sure", "I think", "kind of", "sort of"
- Abstract nouns without specifics: "a tool for tasks", "an app for productivity", "something for tracking"
- Questions instead of statements: "could I build...?", "is it possible to...?"

**Discovery flow:**

1. **Acknowledge the starting point** — Validate the user's idea without judgment. "That's a great starting area. Let me help you narrow it down."

2. **Ask 2-3 open-ended questions** about the problem space:
   - "Who would use this? What's their day look like?"
   - "What's the most frustrating part of how this is done today?"
   - "If this existed and worked perfectly, what would change?"

3. **Suggest 3 concrete project directions** based on the user's answers:
   - Each direction: name, one-sentence description, key differentiator, estimated complexity (small/medium/large)
   - Directions should be meaningfully different from each other, not variations on a theme

4. **Explore the user's reaction:**
   - If the user picks one: transition to Stage 1 (Project Overview) with that direction as the seed
   - If the user rejects all three: ask "What's missing from these? What element would make it feel right?" and suggest 3 more
   - If the user wants to combine elements: help them articulate the hybrid, then transition to Stage 1

5. **Transition signal** — When transitioning from Discovery to Stage 1, the prompt explicitly says: "Great, now I have a clear picture. Let me interview you properly about [concrete concept]."

### 2. Specific Input Bypass

When the user provides a specific, detailed initial description, Discovery is skipped entirely:

**Specificity indicators** (any 2+ of these skip Discovery):
- Named technologies ("React", "PostgreSQL", "REST API")
- Concrete domain ("inventory management", "recipe sharing", "employee onboarding")
- Architectural hints ("microservices", "monolith", "serverless")
- User role specification ("admin dashboard for warehouse managers")
- More than 3 complete sentences with technical content

Example that skips Discovery: "Build a REST API for inventory management with PostgreSQL backend and JWT auth"
Example that triggers Discovery: "I want to build something for managing tasks"

### 3. Converse Prompt Update

`PROMPT_converse.md` updated with the same discovery capability. The converse prompt is the non-wizard equivalent — it should also detect vagueness and enter discovery mode.

### 4. Educational Framing (Collaborative Mode)

When `collaboration.mode` is `"collaborative"` (spec-61), the converse/wizard prompts include educational framing:

- **Why each question is asked:** "I'm asking about users because the best software is designed around specific people, not abstract 'users'."
- **What good requirements look like:** "A testable requirement says 'users can filter by date range' not 'users can find what they need'."
- **What makes specs testable:** "Each acceptance criterion should be verifiable by a human or automated test without ambiguity."

These annotations are present throughout the conversation, not just in Discovery. They help the user learn requirements engineering while going through the process.

In non-collaborative modes, the wizard/converse prompts work exactly as before — no educational framing, just efficient requirements gathering.

### 5. Implementation Approach

This spec is **entirely prompt-driven**. No bash orchestrator changes are needed for the core discovery functionality. Claude detects vagueness, enters discovery mode, and transitions to the standard interview — all within the same conversation.

Changes are limited to:
- Editing `PROMPT_wizard.md` to add Discovery stage instructions
- Editing `PROMPT_converse.md` to add Discovery capability
- Educational framing gated on a context variable (`COLLABORATION_MODE`) injected by `lib/context.sh` (already handled by spec-61's educational annotation system)

## Acceptance Criteria

- AC-64-1: Vague input ("I want to build something for tasks") triggers discovery mode with open-ended questions
- AC-64-2: Discovery suggests 3 concrete, meaningfully different project directions
- AC-64-3: User can pick a direction and transition smoothly to Stage 1 interview
- AC-64-4: User can reject all directions and get 3 new ones
- AC-64-5: User can combine elements from multiple suggestions
- AC-64-6: Specific input ("Build a REST API for inventory management with PostgreSQL") skips discovery, goes straight to interview
- AC-64-7: Educational annotations present in collaborative mode throughout the conversation
- AC-64-8: Non-collaborative mode works exactly as before (no discovery changes to behavior, no educational framing)
- AC-64-9: Discovery works in both wizard (`--wizard`) and converse (Phase 0) modes

## Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Extremely long but still vague description | Discovery activates (length alone doesn't indicate specificity) |
| User rejects all 3 directions | Ask clarifying questions, suggest 3 more. After 2 rounds of rejection, ask "Would you like to describe your ideal project from scratch?" |
| User wants to combine 2+ suggestions | Help articulate the hybrid concept, confirm understanding, transition to Stage 1 |
| User provides single word ("chat") | Discovery activates with broad exploration of chat-related applications |
| User pastes a full requirements document | Specificity detection skips discovery, wizard enters Stage 1 or later |
| Non-English input | Discovery works in whatever language the user writes in |
| User explicitly says "I don't know what to build" | Discovery activates with even broader questions about interests and problems they face |

## Implementation Touchpoints

| File | Change Type | Summary |
|------|-------------|---------|
| `PROMPT_wizard.md` | Edit | Add Stage 0 (Discovery) with vagueness detection, 3-direction suggestion, exploration flow |
| `PROMPT_converse.md` | Edit | Add same discovery capability |
| `templates/PROMPT_wizard.md` | Edit | Template copy of wizard changes |
| `templates/PROMPT_converse.md` | Edit | Template copy of converse changes |
| `tests/test_wizard_discovery.sh` | Create | Tests for discovery activation and bypass |

No changes to `automaton.sh`, `lib/config.sh`, or other bash modules. Educational framing injection is handled by spec-61's context injection system.

## Dependencies

- **Spec 59** (Requirements Wizard): Discovery is Stage 0 of the existing wizard flow
- **Spec 02** (Converse Phase): Discovery applies to the converse prompt as well
- **Spec 61** (Collaboration Mode): Educational annotations config and context injection
