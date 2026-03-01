# Spec 44: Human Interface

## Purpose

The evolution loop (spec-41) runs autonomously, but humans must remain in control (Article II of the constitution, spec-40). This spec defines 15 new CLI commands that let the human observe, guide, and intervene in automaton's evolution. Commands fall into four categories: observation (inspect what's happening), guidance (plant ideas, water evidence, prune bad ideas), governance (constitution, amendments, overrides), and control (pause, resume, set cycle limits). The interface makes automaton's internal state legible and manipulable without requiring the human to read JSON files directly.

## Requirements

### 1. CLI Command Summary

| Command | Category | Description |
|---------|----------|-------------|
| `--evolve` | Control | Start autonomous evolution loop (spec-41) |
| `--plant "idea"` | Guidance | Plant a new seed in the garden |
| `--garden` | Observation | Display garden summary |
| `--garden-detail ID` | Observation | Show full details of a garden idea |
| `--water ID "evidence"` | Guidance | Add evidence to an existing idea |
| `--prune ID "reason"` | Guidance | Wilt an idea with a reason |
| `--promote ID` | Guidance | Force-promote an idea to bloom stage |
| `--health` | Observation | Display health dashboard (spec-43) |
| `--inspect ID` | Observation | Show vote record details |
| `--constitution` | Governance | Display the current constitution |
| `--amend` | Governance | Propose a constitutional amendment |
| `--override` | Governance | Override a quorum decision |
| `--pause-evolution` | Control | Pause the running evolution loop |
| `--signals` | Observation | Display active stigmergic signals |
| `--cycles N` | Control | Set maximum evolution cycles (used with --evolve) |

### 2. Argument Parsing

New argument variables added to the CLI parser (extending the block at lines 2210-2294 of `automaton.sh`):

```bash
ARG_EVOLVE=false
ARG_PLANT=""
ARG_GARDEN=false
ARG_GARDEN_DETAIL=""
ARG_WATER_ID=""
ARG_WATER_EVIDENCE=""
ARG_PRUNE_ID=""
ARG_PRUNE_REASON=""
ARG_PROMOTE=""
ARG_HEALTH=false
ARG_INSPECT=""
ARG_CONSTITUTION=false
ARG_AMEND=false
ARG_OVERRIDE=false
ARG_PAUSE_EVOLUTION=false
ARG_SIGNALS=false
ARG_CYCLES=0
```

Commands that accept arguments use the following patterns:

```bash
--plant)       ARG_PLANT="$2"; shift ;;
--water)       ARG_WATER_ID="$2"; ARG_WATER_EVIDENCE="$3"; shift 2 ;;
--prune)       ARG_PRUNE_ID="$2"; ARG_PRUNE_REASON="$3"; shift 2 ;;
--promote)     ARG_PROMOTE="$2"; shift ;;
--inspect)     ARG_INSPECT="$2"; shift ;;
--garden-detail) ARG_GARDEN_DETAIL="$2"; shift ;;
--cycles)      ARG_CYCLES="$2"; shift ;;
```

### 3. Observation Commands

#### 3.1 `--garden` — Garden Summary

Displays a table of all non-wilted garden ideas:

```
AUTOMATON GARDEN — 9 ideas (4 seed, 3 sprout, 2 bloom)

 ID        STAGE    PRI  TITLE                                    AGE
 idea-001  seed      25  Add parallel review support               2d
 idea-002  seed      18  Improve error message clarity             1d
 idea-003  sprout    52  Reduce prompt overhead in build phase     5d
 idea-004  sprout    45  Cache static prompt sections              4d
 idea-005  sprout    38  Add rate limit retry backoff              3d
 idea-006  bloom     72  Reduce prompt overhead (combined)         8d
 idea-007  bloom     65  Add parallel review capability            7d
 idea-008  seed      12  Investigate token regression              0d
 idea-009  seed      10  Update outdated spec references           1d

Bloom candidates ready for quorum: 2
Use --garden-detail ID for full details. Use --plant "idea" to add new seeds.
```

Implementation: Reads `_index.json` and all non-wilted idea files. Sorts by stage (bloom first) then priority.

#### 3.2 `--garden-detail ID` — Idea Details

Displays full details of a single idea:

```
IDEA: idea-006 — Reduce prompt overhead (combined)
Stage: bloom (since 2026-03-01)  |  Priority: 72  |  Complexity: medium

Description:
  Build prompts contain 4K tokens of static rules identical every iteration.
  Extract static rules to a cached preamble, reducing per-iteration overhead.

Evidence (4 items):
  1. [metric] Prompt overhead ratio >50% for 5 consecutive runs (evolve-reflect, 2026-02-25)
  2. [signal] SIG-007 strength 0.8: recurring high prompt overhead (evolve-ideate, 2026-02-26)
  3. [metric] Cache hit ratio could increase 15% with static preamble (evolve-reflect, 2026-02-27)
  4. [human] "This is the most impactful optimization available" (human, 2026-02-28)

Related: specs [29, 30, 37]  |  signals [SIG-007]

Stage History:
  seed    → 2026-02-25  Auto-seeded from metric threshold
  sprout  → 2026-02-26  2 evidence items accumulated
  bloom   → 2026-02-28  Priority 72, 4 evidence items, human promoted

Vote: not yet evaluated
```

#### 3.3 `--signals` — Active Signals

Displays active stigmergic signals:

```
ACTIVE SIGNALS — 5 signals (2 strong)

 ID       TYPE                 STR   TITLE                              OBS  LINKED
 SIG-001  recurring_pattern    0.80  High prompt overhead               4    idea-006
 SIG-003  efficiency_opp       0.65  Review reads entire codebase       2    idea-007
 SIG-005  attention_needed     0.42  Test flakiness in budget tests     3    —
 SIG-006  promising_approach   0.35  Caching reduced token usage 20%    1    idea-004
 SIG-007  complexity_warning   0.28  automaton.sh approaching 9K lines  1    —

Unlinked signals (no garden idea): 2
Strong signals (>= 0.5): 2
```

#### 3.4 `--inspect ID` — Vote Record

Displays a vote record by vote ID or idea ID:

```
VOTE: vote-005 — Evaluating idea-003 "Reduce prompt overhead"
Type: bloom_implementation  |  Threshold: 3/5  |  Result: APPROVED

 VOTER          VOTE     CONF  RISK    REASONING
 conservative   approve  0.70  medium  Evidence is strong, medium risk acceptable...
 ambitious      approve  0.90  low     Opens door to further optimizations...
 efficiency     approve  0.95  low     Estimated 20K tokens saved per iteration...
 quality        approve  0.60  medium  Acceptable if tests maintained...
 advocate       reject   0.50  low     Low user-visible impact, low priority...

Tally: 4 approve, 1 reject, 0 abstain → APPROVED (4/5 >= 3/5)
Conditions: Must pass syntax check, Rollback plan required, Update tests
Cost: 15,200 tokens ($0.12)
```

#### 3.5 `--constitution` — View Constitution

Displays the current constitution with version and article count:

```
AUTOMATON CONSTITUTION (v1, ratified 2026-03-01)
8 articles, 0 amendments

  Art. I   Safety First                [unanimous]
  Art. II  Human Sovereignty           [unanimous]
  Art. III Measurable Progress         [supermajority]
  Art. IV  Transparency                [supermajority]
  Art. V   Budget Discipline           [supermajority]
  Art. VI  Incremental Growth          [majority]
  Art. VII Test Coverage               [majority]
  Art. VIII Amendment Protocol         [unanimous]

Use --amend to propose changes. Full text: .automaton/constitution.md
```

#### 3.6 `--health` — Health Dashboard

Displays the growth metrics dashboard (spec-43). See spec-43, Requirement 6 for full output format.

### 4. Guidance Commands

#### 4.1 `--plant "idea"` — Plant a Seed

Creates a new seed in the garden with human origin:

```bash
./automaton.sh --plant "Add support for parallel review agents"
```

Output:
```
Planted seed idea-010: "Add support for parallel review agents"
Origin: human  |  Stage: seed  |  Priority: 10 (+10 human boost)
Water with evidence using: --water idea-010 "your evidence here"
```

Implementation: Calls `_garden_plant_seed()` (spec-38) with `origin.type = "human"`.

#### 4.2 `--water ID "evidence"` — Add Evidence

Adds evidence to an existing idea:

```bash
./automaton.sh --water idea-003 "Measured 4.2K tokens of static rules in PROMPT_build.md"
```

Output:
```
Watered idea-003: "Reduce prompt overhead in build phase"
Evidence added (5 total). Priority: 72 → 78.
Stage: sprout → bloom (threshold met: 5 evidence items, priority 78 >= 40)
```

Implementation: Calls `_garden_water()` (spec-38), then `_garden_advance_stage()` if thresholds are met.

#### 4.3 `--prune ID "reason"` — Wilt an Idea

Manually wilts an idea:

```bash
./automaton.sh --prune idea-002 "No longer relevant after spec-37 changes"
```

Output:
```
Pruned idea-002: "Improve error message clarity" → wilted
Reason: No longer relevant after spec-37 changes
```

Implementation: Calls `_garden_wilt()` (spec-38).

#### 4.4 `--promote ID` — Force Promote to Bloom

Promotes an idea directly to bloom stage, bypassing normal thresholds:

```bash
./automaton.sh --promote idea-005
```

Output:
```
Promoted idea-005: "Add rate limit retry backoff" → bloom
Bypassed threshold check (human promotion). Ready for quorum evaluation.
```

Implementation: Calls `_garden_advance_stage()` with `force=true` (spec-38).

### 5. Governance Commands

#### 5.1 `--amend` — Propose Constitutional Amendment

Interactive command that guides the human through proposing an amendment:

```
$ ./automaton.sh --amend

CONSTITUTIONAL AMENDMENT PROCESS

Which article to amend? (I-VIII or 'new' for new article): VI
Current text of Article VI: "Incremental Growth" [majority]

  Evolution proceeds through small, reversible steps:
  - Each cycle implements at most one idea
  - Each implementation modifies at most 3 files
  ...

Enter the proposed change (one line):
> Increase max_files_per_iteration reference from 3 to 5

This amendment will:
  - Modify Article VI (protection: majority)
  - Require quorum vote: 3/5 majority
  - Be planted as a garden idea with tag 'constitutional'

Proceed? (y/n): y

Planted idea-011: "Constitutional amendment: Article VI — increase file limit"
Tags: [constitutional]  |  Stage: seed
The idea will progress through normal garden lifecycle.
For immediate evaluation, use: --promote idea-011
```

Implementation: Creates a garden idea with `tags: ["constitutional"]`. The idea progresses through normal lifecycle. When it reaches bloom, the quorum evaluates with `constitutional_amendment` threshold.

#### 5.2 `--override` — Override Quorum Decision

Allows the human to override a quorum rejection (Article II: Human Sovereignty):

```
$ ./automaton.sh --override

Recent rejected ideas:
  idea-008  "Investigate token regression"   rejected vote-007 (2/5)
  idea-009  "Update outdated spec refs"       rejected vote-008 (1/5)

Override which idea? Enter ID: idea-008

WARNING: Overriding quorum rejection of idea-008.
This bypasses collective decision-making (Article II).
The override will be recorded in the audit trail.

Confirm override? (y/n): y

Override recorded. idea-008 → bloom (re-promoted for implementation)
Override logged in vote-007 with reason: "Human override — Article II sovereignty"
```

Implementation: Re-promotes the wilted idea to bloom stage, adds an override record to the vote, and logs the override in `constitution-history.json`.

### 6. Control Commands

#### 6.1 `--pause-evolution` — Pause Evolution

Sets a pause flag that the evolution loop checks between phases:

```bash
./automaton.sh --pause-evolution
```

This writes a flag file `.automaton/evolution/pause`:
```
paused_at=2026-03-02T15:00:00Z
paused_by=human
```

The evolution loop checks for this file between phases and halts cleanly if found:
```
[EVOLUTION] Pause requested. Completing current phase and stopping.
[EVOLUTION] Paused after cycle 5, phase EVALUATE. Resume with --evolve --resume.
```

To unpause: `rm .automaton/evolution/pause` and `./automaton.sh --evolve --resume`.

#### 6.2 `--cycles N` — Set Cycle Limit

Used with `--evolve` to limit the number of evolution cycles:

```bash
./automaton.sh --evolve --cycles 3   # Run exactly 3 cycles then stop
```

Implementation: Sets `ARG_CYCLES=N` which the evolution loop checks after each cycle.

### 7. No-Conflict Verification

New flags do not conflict with existing flags:

| Existing Flag | New Flag | Conflict? |
|--------------|----------|-----------|
| `--resume` | `--evolve --resume` | No — `--resume` works with `--evolve` |
| `--self` | `--evolve` | No — `--evolve` implies `--self` |
| `--self --continue` | `--evolve` | No — separate modes |
| `--stats` | `--health` | No — `--stats` shows run history, `--health` shows metrics |
| `--dry-run` | `--evolve --dry-run` | No — `--dry-run` works with `--evolve` |
| `--skip-research` | N/A | Not applicable to evolution |
| `--skip-review` | N/A | Not applicable to evolution |
| `--config FILE` | N/A | Works with all modes |
| `--help` | N/A | Updated to include new flags |

### 8. Help Text Update

Update the `--help` output to include the new commands:

```
./automaton.sh [OPTIONS]

Standard Mode:
  --resume          Resume from saved state
  --skip-research   Skip research phase
  --skip-review     Skip review phase
  --config FILE     Use alternate config file
  --dry-run         Show settings, then exit
  --self            Self-build mode
  --self --continue Auto-pick backlog item and run
  --stats           Display run history and trends
  --help, -h        Show this help message

Evolution Mode:
  --evolve              Start autonomous evolution loop
  --evolve --cycles N   Run exactly N evolution cycles
  --evolve --dry-run    Show REFLECT analysis without acting
  --evolve --resume     Resume interrupted evolution

Garden:
  --plant "idea"        Plant a new seed in the garden
  --garden              Display garden summary
  --garden-detail ID    Show full idea details
  --water ID "evidence" Add evidence to an idea
  --prune ID "reason"   Wilt an idea with a reason
  --promote ID          Force-promote idea to bloom

Observation:
  --health              Display health metrics dashboard
  --signals             Display active stigmergic signals
  --inspect ID          Show vote record details

Governance:
  --constitution        Display the current constitution
  --amend               Propose a constitutional amendment
  --override            Override a quorum decision
  --pause-evolution     Pause running evolution loop
```

### 9. Skills for Human Interaction

New skill definitions in `.claude/skills/`:

| Skill File | Description |
|------------|-------------|
| `garden-tender.md` | Guided workflow for reviewing and tending the garden |
| `constitutional-review.md` | Guided workflow for reviewing constitution and proposing amendments |
| `signal-reader.md` | Guided workflow for interpreting signals and their implications |
| `metrics-analyzer.md` | Guided workflow for analyzing health metrics and trends |

These skills provide higher-level guided interactions beyond what individual CLI commands offer.

## Acceptance Criteria

- [ ] All 15 CLI commands parse correctly and produce expected output
- [ ] `--plant` creates a seed with human origin and priority boost
- [ ] `--water` adds evidence and triggers stage advancement if thresholds met
- [ ] `--prune` wilts ideas with recorded reason
- [ ] `--promote` force-advances ideas to bloom regardless of threshold
- [ ] `--garden` displays sorted table of all non-wilted ideas
- [ ] `--garden-detail` shows full idea information including evidence and stage history
- [ ] `--signals` displays active signals with strength and linking status
- [ ] `--inspect` shows vote records with per-voter breakdown
- [ ] `--constitution` displays article summary with protection levels
- [ ] `--amend` creates constitutional amendment idea through guided interaction
- [ ] `--override` re-promotes rejected ideas with audit trail
- [ ] `--pause-evolution` halts the evolution loop cleanly between phases
- [ ] `--health` displays the metrics dashboard (spec-43)
- [ ] `--cycles N` limits evolution to N cycles
- [ ] No flag conflicts with existing CLI commands
- [ ] `--help` output updated with all new commands

## Dependencies

- Depends on: spec-38 (garden — plant, water, prune, promote operations)
- Depends on: spec-39 (quorum — inspect vote records, override)
- Depends on: spec-40 (constitution — display, amend)
- Depends on: spec-41 (evolution loop — evolve, pause, cycles, resume)
- Depends on: spec-42 (signals — display active signals)
- Depends on: spec-43 (metrics — health dashboard)
- Depends on: spec-45 (safety — pause triggers clean halt)

## Files to Modify

- `automaton.sh` — add argument parsing for 15 new flags, add display functions (`_display_garden()`, `_display_garden_detail()`, `_display_signals()`, `_display_vote()`, `_display_constitution()`, `_display_health()`), add action functions (`_cli_plant()`, `_cli_water()`, `_cli_prune()`, `_cli_promote()`, `_cli_amend()`, `_cli_override()`, `_cli_pause()`), update `_show_help()`
- `.claude/skills/garden-tender.md` — new file: garden tending skill
- `.claude/skills/constitutional-review.md` — new file: constitution review skill
- `.claude/skills/signal-reader.md` — new file: signal reader skill
- `.claude/skills/metrics-analyzer.md` — new file: metrics analyzer skill
