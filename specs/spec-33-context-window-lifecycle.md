# Spec 33: Context Window Lifecycle Management

## Purpose

The context window fills up fast and performance degrades as it fills — this is the critical constraint per Claude Code best practices. Spec-24 partially addresses context efficiency but lacks compaction strategy, auto-compaction behavior, fresh-vs-resumed context trade-offs, and multi-context-window patterns. This spec defines comprehensive context window lifecycle management across all phases.

## Requirements

### 1. Context Utilization Ceilings Per Phase

Define target context utilization ceilings to prevent performance degradation:

| Phase | Target Ceiling | Rationale |
|-------|---------------|-----------|
| Research | 60% | Leaves headroom for unexpected codebase exploration |
| Plan | 70% | Plan generation is output-heavy; needs room for full plan |
| Build | 80% | Highest utilization — agents need maximum context for implementation |
| Review | 70% | Must hold full diff context plus review analysis |

These are advisory targets. The orchestrator does not enforce them directly — they inform prompt size budgets and compaction trigger points.

### 2. Fresh Context Per Iteration (Validated Default)

Each iteration spawns a fresh agent invocation with a clean context window. This is the correct baseline for automaton because:

- No context leakage between iterations (stale data from iteration 3 does not confuse iteration 7)
- Prompt caching (spec-30) provides the efficiency benefit of context reuse without the degradation
- Budget tracking is precise (each invocation's tokens are independently measured)
- Error isolation — a context-corrupted iteration does not propagate

Session resumption (`claude --continue`) is NOT used between iterations. Each iteration is a stateless invocation that receives all needed context via the prompt.

Exception: within a single iteration, if the agent hits auto-compaction (see requirement 3), the iteration continues with compacted context. This is unavoidable and acceptable.

### 3. Auto-Compaction Behavior

Claude Code auto-compaction triggers at ~95% context capacity by default. When this happens mid-iteration:

- The agent's context is automatically summarized, preserving important code and decisions
- Uncommitted work is at risk if the agent was mid-edit
- The iteration continues with reduced context

Mitigation requirements:
- Build agents must commit frequently (after each logical unit of work, not just at task completion)
- The build prompt (spec-29) must include: "Commit after each logical change. Do not accumulate uncommitted work — auto-compaction at 95% context may lose uncommitted state."
- The orchestrator tracks whether auto-compaction occurred (detectable via token count drops in stream-json output) and logs it

### 4. Compaction Triggers for Long-Running Iterations

For phases that may hit context limits (build, research on large codebases), define manual compaction guidance in prompts:

```xml
<rules>
If your context is growing large from file reads and tool results:
- Use /compact to summarize investigation results before continuing
- When compacting, preserve: modified file list, test commands, current task status
- Prefer targeted file reads (specific line ranges) over full-file reads
- Scope investigations narrowly — use Grep to find relevant sections instead of reading entire files
</rules>
```

### 5. Context Handoff Protocol

Between iterations and phases, context is handed off through structured artifacts, not conversation history:

| Channel | Format | Content |
|---------|--------|---------|
| Code changes | Git commits | Implementation work — the ground truth |
| Task status | IMPLEMENTATION_PLAN.md | Checkbox state — what's done, what's remaining |
| Operational learnings | `.claude/agent-memory/` (spec-27) or AGENTS.md | Patterns, gotchas, conventions discovered |
| Phase summary | `.automaton/context_summary.md` (spec-24) | Structured JSON + prose summary of phase outcomes |
| Iteration log | `.automaton/iteration_memory.md` (spec-24) | One-line summaries of each iteration's work |
| Test results | `.automaton/test_results.json` (spec-31) | Structured test/lint pass/fail data |

The protocol: data that must survive compaction goes in files. Data that is nice-to-have goes in prompts. No critical state lives only in context.

### 6. Multi-Context-Window Patterns

Define patterns for effective multi-window usage following best practices:

**Pattern 1: Test Scaffolding First**
In the first 1-3 build iterations, write test scaffolding and infrastructure scripts. Subsequent iterations implement against existing tests. This pattern works because:
- Tests are committed to git (survive context boundaries)
- Build agents in later iterations discover tests via file reads
- Review agent can run pre-written tests

**Pattern 2: Writer/Reviewer Separation**
Research and Plan run in their own context windows (separate iterations). Build runs in its context window. Review runs in a fresh context window. Each phase has no conversation bias from previous phases — only file-based artifacts.

**Pattern 3: Fan-Out for Batch Operations**
When a single iteration needs to process many files (e.g., research reading 20+ specs), use subagents (Agent tool) to fan out reads into separate context windows. The main agent context only receives summaries.

**Pattern 4: Progress File for Cross-Window Coordination**
Maintain `.automaton/progress.txt` as a human-readable status file that any agent can read to understand project state without loading full history:

```
# Automaton Progress
Phase: build (iteration 7/~20)
Completed: 12/25 tasks
Last completed: Add authentication middleware
Currently blocked: Database migration (depends on schema task)
Key decisions: Using JWT for auth, PostgreSQL for storage
```

### 7. Context Utilization Tracking

Track context utilization per iteration as a metric. After each agent invocation:

```json
{
  "iteration": 7,
  "phase": "build",
  "context_tokens_in": 112000,
  "context_tokens_out": 24000,
  "auto_compaction_detected": false,
  "estimated_utilization": 0.68
}
```

Estimated utilization = `(input_tokens + output_tokens) / model_context_window_size`

Model context window sizes:
| Model | Context Window |
|-------|---------------|
| Opus 4.6 | 200,000 tokens |
| Sonnet 4.6 | 200,000 tokens |
| Haiku 4.5 | 200,000 tokens |

Log a warning when utilization exceeds the phase ceiling:

```
[ORCHESTRATOR] WARNING: Build iteration 7 context utilization 85% exceeds ceiling 80%. Consider smaller tasks or more frequent commits.
```

### 8. Commit Frequency Rule

Build agents must commit after each logical change, not just at task completion. This is a defense against auto-compaction data loss and provides better git history for review.

Rule: "Commit after completing each function, test, or logical unit of work. If you have more than 50 lines of uncommitted changes, commit now."

This rule goes in the build prompt (`<rules>` section per spec-29) and can optionally be enforced by a periodic `PostToolUse` hook that counts uncommitted lines.

## Acceptance Criteria

- [ ] Context utilization ceilings defined per phase and logged when exceeded
- [ ] Fresh-context-per-iteration validated as default with documented rationale
- [ ] Build prompt includes frequent-commit rule to mitigate auto-compaction risk
- [ ] Context handoff protocol defines which data goes in files vs. prompts
- [ ] Multi-context-window patterns documented: test scaffolding, writer/reviewer, fan-out, progress file
- [ ] Context utilization tracked per iteration in budget history
- [ ] Auto-compaction detection logged when it occurs
- [ ] `.automaton/progress.txt` maintained for cross-window state awareness

## Dependencies

- Supersedes: spec-24 (context efficiency becomes a subset of this spec)
- Depends on: spec-29 (prompt structure for compaction guidance)
- Depends on: spec-07 (token data for utilization calculation)
- Extends: spec-05 (commit frequency rule in build phase)
- Extends: spec-10 (progress.txt as new state file)
- Depended on by: spec-37 (session bootstrap uses context handoff protocol)

## Files to Modify

- `automaton.sh` — context utilization tracking in `post_iteration()`, auto-compaction detection, progress.txt generation
- `PROMPT_build.md` — frequent-commit rule, compaction guidance in `<rules>` section
- `PROMPT_research.md` — narrow-scope investigation guidance
- `.automaton/progress.txt` — new file: cross-window progress status
