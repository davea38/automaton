# Spec 39: Agent Quorum

## Purpose

Self-modification decisions should not rest on a single agent's judgment. A code change that looks brilliant to one perspective may be reckless from another. This spec introduces collective decision-making through a quorum of 5 voter agents, each with a distinct evaluation perspective. Voters are read-only Sonnet agents that receive a proposal (a bloom-stage garden idea) and emit a structured vote. The quorum tallies votes against configurable thresholds — simple majority for low-risk seeds, 3/5 for bloom implementations, 4/5 supermajority for constitutional amendments. This mirrors multi-agent debate research showing that voting improves reasoning task accuracy, while keeping costs controlled through lightweight read-only agents and strict budget tracking.

## Requirements

### 1. Voter Agent Definitions

Five voter agents defined as Claude agent definition files in `.claude/agents/`:

| Agent File | Perspective | Focus |
|------------|-------------|-------|
| `voter-conservative.md` | Conservative | Risk, stability, rollback probability. Skeptical of changes that touch core orchestration. |
| `voter-ambitious.md` | Ambitious | Growth potential, new capabilities, strategic value. Favors changes that expand what automaton can do. |
| `voter-efficiency.md` | Efficiency | Token cost, runtime performance, cache hit ratio. Evaluates whether the idea saves more than it costs. |
| `voter-quality.md` | Quality | Test coverage, code clarity, spec compliance. Ensures changes maintain or improve quality standards. |
| `voter-advocate.md` | User Advocate | Human experience, CLI usability, transparency. Considers whether the change helps or hinders the human operator. |

Each agent file follows the native subagent definition format (spec-27):

```markdown
# Voter: [Perspective Name]

## Role
You are a [perspective] voter in automaton's evolution quorum.

## Context
You will receive a proposal (a garden idea at bloom stage) with:
- The idea's title, description, and evidence
- Related metrics and signals
- Estimated complexity and affected specs
- The current state of automaton (from bootstrap manifest)

## Instructions
1. Evaluate the proposal ONLY from your perspective
2. Consider the evidence provided
3. Assess risks and benefits through your lens
4. Produce a structured vote

## Output Format
Respond with ONLY a JSON object:
{
  "vote": "approve" | "reject" | "abstain",
  "confidence": 0.0-1.0,
  "reasoning": "One paragraph explaining your vote from your perspective",
  "conditions": ["Optional conditions that must be met for your approval"],
  "risk_assessment": "low" | "medium" | "high"
}

## Constraints
- You are READ-ONLY. Do not modify any files.
- You must vote. Abstain only if the proposal is entirely outside your perspective.
- Base your vote on evidence, not speculation.
- Keep reasoning under 200 words.
```

### 2. Vote Schema

Each vote is recorded as a JSON file in `.automaton/votes/`:

```json
{
  "vote_id": "vote-001",
  "idea_id": "idea-003",
  "cycle_id": 5,
  "type": "bloom_implementation",
  "proposal": {
    "title": "Reduce prompt overhead in build phase",
    "description": "Extract static rules to a cached preamble",
    "evidence_count": 4,
    "priority": 72,
    "complexity": "medium"
  },
  "votes": {
    "conservative": {
      "vote": "approve",
      "confidence": 0.7,
      "reasoning": "Medium risk but evidence is strong...",
      "conditions": ["Must pass syntax check", "Rollback plan required"],
      "risk_assessment": "medium"
    },
    "ambitious": {
      "vote": "approve",
      "confidence": 0.9,
      "reasoning": "Opens the door to further prompt optimizations...",
      "conditions": [],
      "risk_assessment": "low"
    },
    "efficiency": {
      "vote": "approve",
      "confidence": 0.95,
      "reasoning": "Estimated 20K token savings per iteration...",
      "conditions": [],
      "risk_assessment": "low"
    },
    "quality": {
      "vote": "approve",
      "confidence": 0.6,
      "reasoning": "Acceptable if tests are maintained...",
      "conditions": ["Update PROMPT_build.md tests"],
      "risk_assessment": "medium"
    },
    "advocate": {
      "vote": "reject",
      "confidence": 0.5,
      "reasoning": "Prompt changes are invisible to users, low priority...",
      "conditions": [],
      "risk_assessment": "low"
    }
  },
  "tally": {
    "approve": 4,
    "reject": 1,
    "abstain": 0,
    "threshold": 3,
    "result": "approved",
    "conditions_merged": ["Must pass syntax check", "Rollback plan required", "Update PROMPT_build.md tests"]
  },
  "budget": {
    "tokens_used": 15200,
    "estimated_cost_usd": 0.12
  },
  "created_at": "2026-03-02T14:30:00Z"
}
```

### 3. Decision Types and Thresholds

| Decision Type | Threshold | When Used |
|---------------|-----------|-----------|
| `seed_promotion` | Simple majority (3/5) | Advancing a seed to sprout when evidence is borderline |
| `bloom_implementation` | 3/5 | Standard approval for implementing a bloom-stage idea |
| `constitutional_amendment` | Supermajority (4/5) | Modifying a constitutional principle (spec-40) |
| `emergency_override` | Unanimous (5/5) | Overriding a safety circuit breaker (spec-45) |

Thresholds are configurable in the `quorum` config section. Abstentions reduce the denominator — a vote of 3 approve, 1 reject, 1 abstain counts as 3/4 (75%), meeting the 3/5 (60%) threshold.

### 4. Quorum Execution Flow

The quorum is invoked during the EVALUATE phase of the evolution loop (spec-41):

1. **Select bloom candidates** — `_garden_get_bloom_candidates()` returns ideas at bloom stage, sorted by priority
2. **Prepare proposal** — For each bloom candidate, assemble the proposal context: idea details, related metrics, signals, affected specs, bootstrap manifest
3. **Invoke voters** — Run all 5 voter agents sequentially (not parallel, to control costs). Each voter receives the proposal and produces a JSON vote
4. **Parse votes** — Extract structured votes from agent output. If a voter's output is not valid JSON, record as abstain with `"reasoning": "Vote parsing failed"`
5. **Tally** — Count approve/reject/abstain, compare against threshold for the decision type
6. **Record** — Write vote record to `.automaton/votes/vote-{NNN}.json`
7. **Act** — If approved, advance idea to harvest stage and queue for IMPLEMENT phase. If rejected, wilt the idea with merged rejection reasoning

### 5. Voter Invocation

Voters are invoked as lightweight Claude subagents using the Sonnet model (cost-efficient):

```bash
_quorum_invoke_voter() {
    local voter_name="$1"    # e.g., "conservative"
    local proposal_json="$2"  # JSON string of proposal context

    local agent_file=".claude/agents/voter-${voter_name}.md"
    local prompt="Evaluate this proposal:\n\n${proposal_json}"

    # Use claude CLI with agent definition, Sonnet model, no tools
    claude --agent "$agent_file" \
           --model sonnet \
           --max-tokens 500 \
           --no-tools \
           --print \
           "$prompt"
}
```

Voters are explicitly `--no-tools` — they cannot read files, execute commands, or modify anything. They receive all context in the prompt and produce only a JSON vote.

### 6. Budget Tracking

Each quorum vote consumes tokens. Track per-vote costs in the vote record and aggregate in the evolution cycle budget. Quorum budget rules:

- Maximum tokens per voter invocation: `quorum.max_tokens_per_voter` (default: 500)
- Maximum total quorum cost per cycle: `quorum.max_cost_per_cycle_usd` (default: 1.00)
- If quorum budget is exhausted mid-cycle, skip remaining bloom candidates and log warning

The quorum cost is deducted from the evolution cycle's budget allocation, not the main build budget.

### 7. Quorum Conditions

When voters approve with conditions, those conditions are merged into the vote tally's `conditions_merged` array. The IMPLEMENT phase (spec-41) must satisfy all merged conditions or the implementation is considered failed. Conditions are free-text strings interpreted by the build agent — they are not machine-enforced.

### 8. Vote History

All vote records are preserved in `.automaton/votes/` as persistent state (spec-34). This provides an audit trail of every decision the quorum has made. The evolution loop can query vote history to avoid re-evaluating recently-rejected ideas:

- Ideas wilted by quorum rejection have a cooldown of `quorum.rejection_cooldown_cycles` (default: 5) before they can be re-promoted to bloom

### 9. Configuration

New `quorum` section in `automaton.config.json`:

```json
{
  "quorum": {
    "enabled": true,
    "voters": ["conservative", "ambitious", "efficiency", "quality", "advocate"],
    "thresholds": {
      "seed_promotion": 3,
      "bloom_implementation": 3,
      "constitutional_amendment": 4,
      "emergency_override": 5
    },
    "max_tokens_per_voter": 500,
    "max_cost_per_cycle_usd": 1.00,
    "rejection_cooldown_cycles": 5,
    "model": "sonnet"
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable quorum voting |
| `voters` | array | 5 voter names | Active voter perspectives |
| `thresholds.seed_promotion` | number | 3 | Votes needed for seed promotion |
| `thresholds.bloom_implementation` | number | 3 | Votes needed for implementation |
| `thresholds.constitutional_amendment` | number | 4 | Votes needed for constitution changes |
| `thresholds.emergency_override` | number | 5 | Votes needed for safety overrides |
| `max_tokens_per_voter` | number | 500 | Max output tokens per voter invocation |
| `max_cost_per_cycle_usd` | number | 1.00 | Max quorum cost per evolution cycle |
| `rejection_cooldown_cycles` | number | 5 | Cycles before rejected idea can be re-evaluated |
| `model` | string | "sonnet" | Model used for voter agents |

### 10. Fallback: Quorum Disabled

When `quorum.enabled` is false, bloom-stage ideas are automatically approved for implementation (bypass voting). This enables faster iteration at the cost of reduced safety. A warning is logged: `[EVOLUTION] Quorum disabled — bloom ideas auto-approved without voting`.

## Acceptance Criteria

- [ ] 5 voter agent definition files created in `.claude/agents/`
- [ ] Voters produce valid JSON votes with vote, confidence, reasoning, conditions, risk_assessment
- [ ] Vote tallying respects configurable thresholds per decision type
- [ ] Abstentions reduce the denominator correctly
- [ ] Approved ideas advance to harvest stage; rejected ideas wilt with merged reasoning
- [ ] Vote records written to `.automaton/votes/` with complete audit trail
- [ ] Per-voter token budget enforced
- [ ] Per-cycle quorum cost budget enforced
- [ ] Rejection cooldown prevents re-evaluation of recently-rejected ideas
- [ ] Invalid voter output treated as abstain (graceful degradation)
- [ ] `quorum.enabled: false` auto-approves with warning

## Dependencies

- Depends on: spec-27 (native subagent definitions — voter agent files)
- Depends on: spec-38 (garden — bloom candidates as quorum input)
- Depends on: spec-37 (bootstrap manifest — proposal context)
- Integrates with: spec-40 (constitution — supermajority threshold for amendments)
- Depended on by: spec-40 (constitution — supermajority threshold for amendments)
- Depended on by: spec-41 (evolution loop EVALUATE phase invokes quorum)
- Depended on by: spec-44 (CLI commands to inspect vote records)

## Files to Modify

- `automaton.sh` — add quorum functions (`_quorum_invoke_voter()`, `_quorum_tally()`, `_quorum_evaluate_bloom()`, `_quorum_check_budget()`), integrate into evolution EVALUATE phase
- `automaton.config.json` — add `quorum` configuration section
- `.claude/agents/voter-conservative.md` — new file: conservative voter definition
- `.claude/agents/voter-ambitious.md` — new file: ambitious voter definition
- `.claude/agents/voter-efficiency.md` — new file: efficiency voter definition
- `.claude/agents/voter-quality.md` — new file: quality voter definition
- `.claude/agents/voter-advocate.md` — new file: user advocate voter definition
- `.gitignore` — add `.automaton/votes/` as persistent (git-tracked) state
