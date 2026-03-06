# Audit Finding 03: Evolution Subsystem Over-Investment

## Problem

The evolution subsystem (specs 38-45) comprises:
- 6 lib modules: garden.sh, signals.sh, quorum.sh, metrics.sh, constitution.sh, evolution.sh
- ~4,228 lines of code (25% of total codebase)
- 5 voter agent definitions
- 3 evolution agent definitions + prompts
- Constitutional governance framework
- Stigmergic signal coordination
- Idea garden lifecycle management

This is a self-improvement loop for automaton to evolve itself. It is intellectually interesting but:

1. **The core pipeline hasn't been battle-tested.** The basic converse->research->plan->build->review flow needs hardening before self-modification makes sense.
2. **No evidence it works.** The IMPLEMENTATION_PLAN.md shows all evolution specs marked [x] but there's no record of a successful evolution cycle producing a meaningful improvement.
3. **Complexity cost is real.** 5 voter agents, constitutional amendments, stigmergic signals — this is governance machinery for a system that hasn't yet proven it can reliably build a TODO app.
4. **Token cost is high.** Each evolution cycle invokes 5 voter agents + 3 evolution agents + build + review. That's ~$5-10 per cycle for self-improvement that may not be needed.

## What VSDD's Critique Section Says

The VSDD gist's own critical commentary warns: "the 'airtight spec before building' assumption is the same original sin that killed traditional waterfall development." Applied here: building an airtight self-evolution framework before the core pipeline is proven is the same pattern.

## Recommendation

**Do not remove the evolution code.** It's already built and may be valuable later. Instead:

### A. Freeze Evolution Features
No new evolution specs until the core pipeline has been validated on 5+ real projects with documented outcomes.

### B. Focus Investment on Core Pipeline
All new work should target: traceability (audit/01), incremental verification (audit/02), acceptance test generation (audit/06), and token optimization (audit/05).

### C. Simplify Evolution Entry Point
Currently `--evolve` activates a complex 5-phase loop. Consider a simpler "suggest improvements" mode that runs REFLECT only and writes suggestions to a file, without the full IDEATE->EVALUATE->IMPLEMENT->OBSERVE machinery.

## Complexity
Low — this is a prioritization decision, not a code change.

## Dependencies
None.
