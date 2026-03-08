# Spec 60: Scope Flag (`--scope PATH`)

## Purpose

Allow users to constrain all automaton agent operations to a specific directory
and its subdirectories. This is essential for monorepos, scoped refactors, and
running automaton against a subdirectory of a larger project without agents
wandering into unrelated code.

## Requirements

### 1. CLI Flag

| Flag | Argument | Default |
|------|----------|---------|
| `--scope` | Directory path (absolute or relative to cwd) | None (operates on cwd) |

When omitted, behavior is identical to today: `PROJECT_ROOT` defaults to the
current working directory.

### 2. Path Resolution

At parse time (before any phase dispatch), the orchestrator resolves the path:

1. If the path is absolute, use it directly.
2. If the path is relative, resolve it to an absolute path via the invocation
   cwd (`cd "$path" && pwd`).
3. Validate the resolved path is an existing directory. If not, exit 1 with a
   clear error message.

```bash
# Examples:
./automaton.sh --scope ./services/api     # relative — resolved to $(pwd)/services/api
./automaton.sh --scope /home/user/project  # absolute — used as-is
./automaton.sh --scope .                   # no-op — resolves to cwd
```

### 3. Variable Separation

The flag introduces a clean separation of three directory concerns:

| Variable | Value | Scope |
|---|---|---|
| `PROJECT_ROOT` | Resolved `--scope` path (or cwd if omitted) | Where agents discover and modify files |
| `AUTOMATON_DIR` | `$(pwd)/.automaton` (always cwd-anchored, absolute) | Orchestrator state, logs, budget, wave data |
| `AUTOMATON_INSTALL_DIR` | Directory containing `automaton.sh` | Prompt files (PROMPT_*.md), lib/, templates/ |

`AUTOMATON_DIR` must **never** follow `--scope`. State files remain at the
invocation directory so that `--resume` works regardless of scope, and so that
scoping to a subdirectory does not pollute it with `.automaton/` state.

### 4. Agent Working Directory

When `--scope` is active, the orchestrator changes the agent's working directory
to `PROJECT_ROOT` before invocation. This applies to:

- Single-agent mode (both native `--agent` and legacy `-p` invocations)
- Parallel mode (builder wrapper scripts)

The orchestrator itself remains at its invocation cwd. Agent cwd changes happen
in subshells to avoid side effects:

```bash
(cd "$PROJECT_ROOT" && claude "${cmd_args[@]}")
```

### 5. Prompt File Resolution

Phase prompt files (`PROMPT_research.md`, `PROMPT_plan.md`, etc.) live alongside
`automaton.sh`, not in the scoped directory. `get_phase_prompt()` must return
absolute paths using `AUTOMATON_INSTALL_DIR` so prompts resolve correctly
regardless of the agent's cwd.

### 6. Startup Banner

When scope differs from cwd, display it in the banner:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 automaton v0.1.0
 Phase:   research
 Mode:    single-builder
 Scope:   /home/user/monorepo/services/api
 Budget:  $50.00 max | 10M tokens max
 Config:  automaton.config.json
 Branch:  main
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

When scope equals cwd (including `--scope .`), the `Scope:` line is omitted.

### 7. Mutual Exclusions

| Combination | Behavior |
|---|---|
| `--scope` + `--self` | Error: self-build targets automaton's own directory |
| `--scope` + `--resume` | Allowed: state is cwd-anchored, independent of scope |
| `--scope` + `--config` | Allowed: config is resolved independently |

### 8. Hook Integration

No hook changes required. Hooks already read the project root from the
environment:

```bash
project_root="${AUTOMATON_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
```

The orchestrator exports `AUTOMATON_PROJECT_ROOT="$PROJECT_ROOT"` before agent
invocation, so hooks automatically receive the scoped path.

### 9. Error Messages

```
Error: --scope requires a directory path argument.
Error: --scope path does not exist or is not accessible: ./nonexistent
Error: --scope path is not a directory: /etc/passwd
Error: --scope and --self are mutually exclusive.
```

### 10. Parallel Mode (`lib/parallel.sh`)

In `spawn_builders()`, the `project_root` local variable currently uses `$(pwd)`.
With `--scope`, it must use `${PROJECT_ROOT:-$(pwd)}` so builders inherit the
scoped directory.

In `generate_builder_wrapper()`, the builder wrapper template derives paths from
`$PROJECT_ROOT` (its third argument). Two values must be baked in at generation
time so the standalone wrapper script can locate them without inheriting shell
state:

- `AUTOMATON_INSTALL_DIR` — so the wrapper finds `PROMPT_build.md` at
  `$AUTOMATON_INSTALL_DIR/PROMPT_build.md` instead of `$PROJECT_ROOT/PROMPT_build.md`
- `AUTOMATON_DIR` — absolute path, so the wrapper finds `assignments.json` and
  writes results correctly

The wrapper template's `BUILD_PROMPT` variable changes from
`"$PROJECT_ROOT/PROMPT_build.md"` to `"__AUTOMATON_INSTALL_DIR__/PROMPT_build.md"`,
with `__AUTOMATON_INSTALL_DIR__` replaced by sed alongside the existing
`__CLAUDE_MODEL__` placeholder pattern.

### 11. Bootstrap Script (`lib/state.sh`)

The `generate_bootstrap_script()` template currently derives `AUTOMATON_DIR` as
`"$PROJECT_ROOT/.automaton"`. With scope, these are decoupled. The template must
accept `AUTOMATON_DIR` from the environment (or as a fourth argument) rather than
computing it from `PROJECT_ROOT`:

```bash
# Before:
AUTOMATON_DIR="$PROJECT_ROOT/.automaton"

# After:
AUTOMATON_DIR="${AUTOMATON_DIR:-$PROJECT_ROOT/.automaton}"
```

This is backward-compatible: when `AUTOMATON_DIR` is not exported, the old
derivation still works.

## Implementation Touchpoints

| File | Change Type | Summary |
|---|---|---|
| `specs/spec-60-scope-flag.md` | Already exists | This file |
| `automaton.sh` | Edit | `AUTOMATON_DIR` → absolute; add `AUTOMATON_INSTALL_DIR`; add `ARG_SCOPE`; add `--scope` case; add resolution + mutual-exclusion blocks; add banner `Scope:` line; export `AUTOMATON_PROJECT_ROOT` |
| `lib/display.sh` | Edit | Add `--scope PATH` to help text |
| `lib/utilities.sh` | Edit | `get_phase_prompt()` prefixes with `$AUTOMATON_INSTALL_DIR/`; `run_agent()` wraps `claude` in `(cd "$PROJECT_ROOT" && ...)` subshell |
| `lib/parallel.sh` | Edit | `spawn_builders()` uses `${PROJECT_ROOT:-$(pwd)}`; `generate_builder_wrapper()` bakes in `AUTOMATON_INSTALL_DIR` and absolute `AUTOMATON_DIR` |
| `lib/state.sh` | Edit | `generate_bootstrap_script()` template reads `AUTOMATON_DIR` from env |
| `tests/test_cli_args.sh` | Edit | Add `ARG_SCOPE=""` default, `--scope` case, and test cases |
| `tests/test_scope.sh` | Create | Integration tests for path resolution and error cases |

## Edge Cases

| Input | Expected Behavior |
|---|---|
| `--scope .` | Resolves to `$(pwd)`, effectively a no-op; no `Scope:` banner line |
| `--scope ../sibling` | Resolved to absolute via `cd + pwd` |
| `--scope /nonexistent` | Error: path does not exist, exit 1 |
| `--scope /etc/passwd` (file, not dir) | Error: path is not a directory, exit 1 |
| `--scope` with no argument | Error: requires a directory path argument, exit 1 |
| `--scope` + `--self` | Mutual exclusion error, exit 1 |
| `--scope` + `--resume` | Works: `.automaton/` is cwd-anchored, independent of scope |
| `--scope` + `--config` | Both work independently; config resolved before scope |

## Test Plan

### Unit tests (`tests/test_cli_args.sh`)

Add to the existing `_test_parse_args()` function:

- `ARG_SCOPE=""` in defaults
- `--scope` case branch in the while/case
- Test: `--scope /tmp` sets `ARG_SCOPE="/tmp"`
- Test: `--scope` with no argument returns error
- Test: `--scope /tmp --dry-run` works as combined flags

### Integration tests (`tests/test_scope.sh`, new file)

- Relative path `--scope ./subdir` resolves to absolute
- Non-existent path exits 1 with error message
- File path (not directory) exits 1 with error message
- `--scope .` resolves to `$(pwd)` (no-op)
- `AUTOMATON_DIR` stays at `$(pwd)/.automaton` regardless of scope
- `--scope` + `--self` exits 1 with mutual exclusion error

### Manual smoke tests

1. `./automaton.sh --scope ./some-subfolder --dry-run` — banner shows `Scope:` line
2. `./automaton.sh --scope ./subfolder --complexity complex --dry-run` — parallel mode wrapper has correct paths
3. Run existing `bash tests/test_cli_args.sh` to confirm no regressions

## Dependencies on Other Specs

- **spec-01** (orchestrator): CLI parsing, phase dispatch, banner
- **spec-14** (agent execution): `run_agent()` invocation in `lib/utilities.sh`
- **spec-16** (wave execution): `spawn_builders()` and builder wrapper in `lib/parallel.sh`
- **spec-17** (builder agent): Builder receives `PROJECT_ROOT` as argument
- **spec-37** (session bootstrap): `init.sh` template uses `AUTOMATON_DIR`
- **spec-44** (CLI args): Argument parsing tests in `tests/test_cli_args.sh`
