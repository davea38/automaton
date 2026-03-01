---
name: constitutional-review
description: Guided workflow for reviewing the constitution and proposing amendments
tools: Read, Grep
---

## Instructions

Guide the human through reviewing the current constitution and understanding the amendment process. This skill provides a higher-level workflow than the `--constitution` and `--amend` commands.

### Step 1: Load Constitution

Read `.automaton/constitution.md` and extract:
- The list of articles with their titles and protection levels (unanimous, supermajority, majority)
- The full text of each article

If `.automaton/constitution.md` does not exist, report that no constitution exists and suggest running `--evolve` which will create the default constitution automatically.

### Step 2: Load Amendment History

Read `.automaton/constitution-history.json` and extract:
- Total number of amendments
- Recent amendments with article, type, description, and approval date
- Any pending amendments (garden ideas tagged `constitutional`)

If `.automaton/constitution-history.json` does not exist or has no amendments, report that no amendments have been made.

### Step 3: Analyze Protection Levels

Present each article with its protection level and explain the quorum threshold required to amend it:

- **unanimous** (Articles I, II, VIII): Cannot be weakened or removed. These articles are code-enforced immutable. Amendment requires unanimous quorum approval.
- **supermajority** (Articles III, IV, V): Requires supermajority quorum approval (typically 4/5 voters).
- **majority** (Articles VI, VII): Requires simple majority quorum approval (typically 3/5 voters).

Highlight which articles are immutable (protection cannot be reduced) and which can be amended.

### Step 4: Check for Compliance Issues

If `.automaton/evolution-metrics.json` exists, check for patterns that might indicate constitutional concerns:
- Article III (Measurable Progress): Are ideas being implemented without metric targets?
- Article VI (Incremental Growth): Are implementations exceeding scope limits?
- Article VII (Test Coverage): Is test pass rate declining?

Report any potential compliance concerns found.

### Step 5: Guide Amendment Process

If the human wants to propose an amendment, explain the process:

1. Use `--amend` to start the interactive amendment workflow
2. Select the article to amend (or propose a new article)
3. The amendment is planted as a garden idea with the `constitutional` tag
4. The idea progresses through normal garden lifecycle (seed → sprout → bloom)
5. At bloom stage, the quorum evaluates with the `constitutional_amendment` threshold
6. If approved, the amendment is applied to `constitution.md` and recorded in history

Remind the human:
- Articles with `unanimous` protection cannot have their protection level reduced
- Article VIII (Amendment Protocol) cannot be removed or weakened
- Use `--promote ID` to fast-track a constitutional amendment if urgent

### Step 6: Output Summary

Output a structured summary:

```json
{
  "constitution_version": 1,
  "total_articles": 8,
  "amendments": 0,
  "articles": [
    {"number": "I", "title": "Safety First", "protection": "unanimous", "immutable": true},
    {"number": "II", "title": "Human Sovereignty", "protection": "unanimous", "immutable": true},
    {"number": "III", "title": "Measurable Progress", "protection": "supermajority", "immutable": false},
    {"number": "IV", "title": "Transparency", "protection": "supermajority", "immutable": false},
    {"number": "V", "title": "Budget Discipline", "protection": "supermajority", "immutable": false},
    {"number": "VI", "title": "Incremental Growth", "protection": "majority", "immutable": false},
    {"number": "VII", "title": "Test Coverage", "protection": "majority", "immutable": false},
    {"number": "VIII", "title": "Amendment Protocol", "protection": "unanimous", "immutable": true}
  ],
  "pending_amendments": [],
  "compliance_concerns": []
}
```

## Constraints

- This skill is read-only. Do not modify the constitution or history files — only recommend actions via CLI commands.
- Output must be valid JSON in the final summary.
- If `.automaton/constitution.md` does not exist, output `{"constitution_version": 0, "total_articles": 0, "recommended_action": "Run --evolve to create default constitution"}`.
- Do not propose specific amendment text — only identify potential concerns and explain the process.
- Always emphasize the immutability of Articles I, II, and VIII — these are safety-critical.
- Use only Read and Grep tools. Do not run shell commands.
