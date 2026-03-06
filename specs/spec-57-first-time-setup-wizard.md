# Spec 57: First-Time Setup Wizard

## Priority

P3 -- When P0-P2 are Battle-Tested. New users must manually edit JSON to
configure automaton. High-value but low-urgency since automaton runs on
defaults. Ship after doctor and config validation are stable.

## Competitive Sources

- **mini-swe-agent** (clean setup wizard) -- Prompts for essential config on
  first run. Minimal questions, fast completion.
- **openclaw** (onboarding wizard) -- Step-by-step guided setup with validation.
- **MassGen** (quickstart wizard) -- Interactive config with sensible defaults.

## Purpose

Detect an unconfigured environment on first run, walk the user through
essential settings via interactive `read` prompts, generate a valid
`automaton.config.json`, and run the doctor check. Eliminates the most common
onboarding failure: malformed or missing config JSON.

## Requirements

### 1. First-Run Detection

The wizard triggers automatically when no `automaton.config.json` exists in
the project root AND `--no-setup` was not passed. The `.automaton/` directory
alone does not constitute a configured environment.

### 2. CLI Flags

| Flag          | Behavior                                              |
|---------------|-------------------------------------------------------|
| `--setup`     | Force-run the wizard even if config already exists.   |
| `--no-setup`  | Skip the wizard entirely; use all built-in defaults.  |

Mutually exclusive. Passing both exits 1 with an error message.

### 3. Interactive Prompts

Four questions via bash `read -p`. Each shows the default in brackets.
Pressing Enter accepts the default.

**Prompt 1 -- Model Tier** (default: `sonnet`, maps to `models.primary`)
```
Select model tier [sonnet]:
  1) opus   -- highest quality, ~$15/M input tokens
  2) sonnet -- balanced quality/cost, ~$3/M input tokens
Choice (1 or 2):
```
Planning and review always use `opus` regardless of this choice.

**Prompt 2 -- Budget Limit** (default: `50`, maps to `budget.max_cost_usd`)
```
Maximum spend limit in USD [50]:
```
Must be a positive number. Invalid input re-prompts once, then uses default.

**Prompt 3 -- Auto-Push** (default: `yes`, maps to `git.auto_push`)
```
Auto-push commits to git remote? (yes/no) [yes]:
```
Accepts `y`/`yes`/`n`/`no` case-insensitive. Other input re-prompts once.

**Prompt 4 -- Skip Research** (default: `no`, maps to `flags.skip_research`)
```
Skip research phase? (yes/no) [no]:
  (Choose 'yes' for existing codebases where research is unnecessary)
```

### 4. Config Generation

Construct `automaton.config.json` via `jq -n` template merging answers with
spec-12 defaults. Generated file includes ALL schema fields, not just the
four prompted.

### 5. Confirmation Summary

Before writing, display chosen values and ask for confirmation:
```
--- Setup Summary ---
  Model tier:      sonnet
  Budget limit:    $50.00
  Auto-push:       yes
  Skip research:   no
  Config file:     automaton.config.json

Write this configuration? (yes/no) [yes]:
```
Declining returns to Prompt 1. After two declines, exit with a message
suggesting manual editing.

### 6. Post-Setup Doctor Check

After writing config, automatically invoke `doctor_check()` (spec-48). If the
doctor reports failures, print them but do not delete the generated config.

### 7. State Directory Initialization

Create `.automaton/` if it does not exist after wizard completion. Required by
spec-10 and prevents "directory not found" on first real run.

### 8. Non-Interactive Fallback

When stdin is not a TTY (`[ -t 0 ]` is false):
- `--setup` explicitly passed: exit 1 ("requires interactive terminal").
- Otherwise: silently use all defaults (equivalent to `--no-setup`).

Ensures CI/CD pipelines never hang on a prompt.

## Acceptance Criteria

- [ ] Missing config triggers the wizard; `--setup` re-runs; `--no-setup` skips.
- [ ] `--setup` + `--no-setup` together exits with error code 1.
- [ ] Enter at each prompt accepts the displayed default.
- [ ] Invalid budget input re-prompts once, then falls back to default.
- [ ] Generated config passes `jq empty` and contains all spec-12 fields.
- [ ] Confirmation summary displays before writing the file.
- [ ] Declining confirmation twice exits with a manual-edit suggestion.
- [ ] Doctor check runs automatically after config is written.
- [ ] Non-TTY stdin falls back to defaults without hanging.
- [ ] `.automaton/` is created if absent after wizard completes.
- [ ] No Claude API calls or network requests during setup.
- [ ] Total interaction under 60 seconds; implementation under 100 lines.

## Design Considerations

- **Single bash file**: `setup_wizard()` in `automaton.sh`, called from
  `main()` after arg parsing and before `load_config()`.
- **Zero dependencies**: `read`, `printf`, `jq`, bash builtins only.
- **File-based state**: Only artifacts are `automaton.config.json` and
  `.automaton/`. No wizard state files or "setup complete" markers.
- **Re-entrancy**: `--setup` overwrites existing config. Git history is backup.
- **Input sanitization**: All input validated before reaching jq. Budget checked
  with bash arithmetic. Strings constrained to known enums.
- **Color output**: Same ANSI conventions as spec-48. Disabled when `NO_COLOR`
  is set or stdout is not a TTY.

## Dependencies

- **Depends on**: spec-12 (Configuration) -- generated config conforms to schema.
- **Depends on**: spec-48 (Doctor) -- wizard calls `doctor_check()` post-setup.
- **Related**: spec-50 (Config Validation) -- generated config passes validation.
- **Related**: spec-01 (Orchestrator) -- argument parser handles new flags.

## Files to Modify

- `automaton.sh` -- Add `setup_wizard()` function (~80-100 lines), first-run
  detection in `main()`, `--setup`/`--no-setup` flag handling in arg parser.
