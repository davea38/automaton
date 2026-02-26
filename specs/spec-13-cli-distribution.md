# Spec 13: CLI & Distribution

## Purpose

Define how automaton is distributed (npm package), installed (`npx automaton`), and what it scaffolds into the user's project directory.

## Distribution

- **Package name:** `automaton` (npm)
- **Entry point:** `bin/cli.js`
- **Install:** `npx automaton` (no global install needed)
- **License:** MIT
- **Runtime deps:** None (jq is a system dependency, checked at runtime)

## CLI Entry Point (`bin/cli.js`)

The CLI is a Node.js script (following the ralph-init pattern) that:

1. Checks for existing automaton files (warn if overwriting)
2. Copies template files to the current directory
3. Makes `automaton.sh` executable
4. Creates `specs/` directory
5. Creates `.automaton/` directory
6. Adds `.automaton/` to `.gitignore` (if .gitignore exists)
7. Prints a getting-started message

```javascript
#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const templates = [
    'automaton.sh',
    'automaton.config.json',
    'PROMPT_converse.md',
    'PROMPT_research.md',
    'PROMPT_plan.md',
    'PROMPT_build.md',
    'PROMPT_review.md',
    'AGENTS.md',
    'IMPLEMENTATION_PLAN.md',
    'CLAUDE.md',
    'PRD.md',
];

// Copy each template
// Create directories
// Set permissions
// Print instructions
```

## Scaffolded File List

After running `npx automaton`, the project directory contains:

```
project/
  automaton.sh               # Master orchestrator (executable)
  automaton.config.json      # Configuration with defaults
  PROMPT_converse.md         # Phase 0: conversation prompt
  PROMPT_research.md         # Phase 1: research prompt
  PROMPT_plan.md             # Phase 2: planning prompt (from RALPH)
  PROMPT_build.md            # Phase 3: build prompt (from RALPH)
  PROMPT_review.md           # Phase 4: review prompt
  AGENTS.md                  # Operational guide (from RALPH)
  IMPLEMENTATION_PLAN.md     # Task list (from RALPH)
  CLAUDE.md                  # Points to AGENTS.md
  PRD.md                     # Empty template for conversation phase to fill
  specs/                     # Empty directory for spec files
  .automaton/                # Runtime state directory (gitignored)
    state.json               # (created on first run)
    budget.json              # (created on first run)
    session.log              # (created on first run)
    agents/                  # (created on first run)
```

## Getting Started Message

After scaffolding:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 automaton scaffolded successfully

 Next steps:
   1. Run 'claude' to start the conversation phase
      (Claude will interview you and write specs)
   2. When specs are complete, run './automaton.sh'
      (Research, plan, build, and review run autonomously)

 Files created:
   automaton.sh          - Master orchestrator
   PROMPT_*.md           - Agent prompts (5 phases)
   automaton.config.json - Configuration
   AGENTS.md             - Operational guide
   specs/                - Your specs go here

 To resume an interrupted run:
   ./automaton.sh --resume
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## package.json

```json
{
  "name": "automaton",
  "version": "0.1.0",
  "description": "Multi-agent orchestration for autonomous software delivery",
  "bin": {
    "automaton": "bin/cli.js"
  },
  "files": [
    "bin/",
    "templates/"
  ],
  "keywords": [
    "claude",
    "claude-code",
    "multi-agent",
    "orchestration",
    "autonomous",
    "ai",
    "coding"
  ],
  "license": "MIT"
}
```

## System Dependencies

The orchestrator requires:

| Dependency | Purpose | Check |
|-----------|---------|-------|
| `claude` | Claude Code CLI | `which claude` |
| `jq` | JSON parsing | `which jq` |
| `git` | Version control | `which git` |

On first run, `automaton.sh` checks for these and exits with a clear error if missing:
```
Error: 'jq' is required but not installed.
  Install: sudo apt install jq  (Debian/Ubuntu)
           brew install jq      (macOS)
```

## What Gets Committed to Git

Everything except `.automaton/`:

| File | Committed | Why |
|------|-----------|-----|
| automaton.sh | Yes | Reproducible setup |
| automaton.config.json | Yes | Team shares settings |
| PROMPT_*.md | Yes | Prompts are reviewable |
| AGENTS.md | Yes | Operational learnings persist |
| IMPLEMENTATION_PLAN.md | Yes | Task tracking is visible |
| PRD.md | Yes | Requirements are documented |
| CLAUDE.md | Yes | Tiny reference file |
| specs/*.md | Yes | Requirements are documented |
| .automaton/ | No | Runtime state is ephemeral |

## Overwrite Protection

If files already exist when running `npx automaton`:
- Warn for each existing file
- Ask for confirmation before overwriting
- Never overwrite `specs/`, `PRD.md`, or `AGENTS.md` if they have content (these contain user work)
- Always overwrite `automaton.sh` and prompt files (these are templates)
