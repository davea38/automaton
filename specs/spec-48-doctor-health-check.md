# Spec 48: Doctor / Health Check Command

## Priority

P1 -- Prevent User Frustration. Users encounter cryptic failures mid-execution
when dependencies are missing, versions are wrong, or the environment is
misconfigured. A pre-flight check eliminates this entire class of errors and
reduces support burden. This should ship before any feature that makes the
dependency surface area larger.

## Competitive Sources

- **openclaw** (`doctor-config-flow.ts`) -- Validates environment setup before
  first run, checks for required config files and tool availability.
- **ruflo** (`doctor` command) -- Validates the full toolchain and prints a
  status table with pass/fail per component.
- **claude-octopus** (Doctor diagnostics) -- Validates environment and
  configuration, reports actionable remediation steps.

All three competitors treat doctor/health-check as a blocking prerequisite for
first-time users. Automaton should match this pattern.

## Purpose

Provide a `--doctor` CLI flag that validates the runtime environment, tool
versions, authentication state, repository health, and project configuration
before any real work begins. The command prints a human-readable report of
pass/warn/fail results with actionable fix instructions for every non-passing
check. It requires zero network calls and zero Claude API usage so it runs
in under two seconds on any machine.

## Requirements

### 1. CLI Interface

- Invoked as `automaton.sh --doctor` with no other required arguments.
- Can be run from any directory; if not inside a git repo, the git-related
  checks report warnings rather than failures.
- Prints results to stdout. Errors and warnings go to stderr.
- Exit code 0 if all checks pass or only warnings exist. Exit code 1 if any
  check fails.

### 2. Required Tool Checks

Each tool check verifies both presence on `$PATH` and minimum version.

| Tool      | Minimum Version | Check Method                        |
|-----------|-----------------|-------------------------------------|
| `bash`    | 4.0             | `${BASH_VERSINFO[0]}` introspection |
| `git`     | 2.20            | `git --version` parse               |
| `claude`  | any             | `command -v claude`                  |
| `jq`      | 1.5             | `jq --version` parse                |

- A missing tool is a **fail**.
- A tool present but below minimum version is a **fail** with the detected
  version printed alongside the required version.

### 3. Claude CLI Authentication Check

- Run `claude --version` (or equivalent non-API command) to confirm the binary
  executes without error.
- Do NOT make an actual API call. The doctor command must work offline and
  must not consume tokens.
- If the claude CLI exits with a non-zero status, report a **warn** with a
  message suggesting `claude login` or checking `ANTHROPIC_API_KEY`.

### 4. Disk Space Check

- Read available space in the current working directory (or project root)
  using `df` output parsed with standard coreutils.
- Below 100 MB free: **warn** with the actual free space reported.
- Below 10 MB free: **fail**.
- This check must work on both Linux and macOS `df` output formats.

### 5. Git Repository State

- **Is a git repo**: `git rev-parse --is-inside-work-tree`. Not being in a
  repo is a **warn** (automaton can still run in limited modes).
- **Has at least one commit**: `git log -1` succeeds. Empty repo is a **warn**.
- **Has a remote configured**: `git remote -v` returns output. No remote is
  a **warn**.
- **Working tree status**: Report whether the tree is clean or dirty. A dirty
  tree is informational only (no warn/fail) since in-progress work is normal.

### 6. Project File Checks

Check for the presence of expected project files relative to the repository
root (or current directory if not in a repo).

| File / Directory          | Missing Status | Note                              |
|---------------------------|----------------|-----------------------------------|
| `automaton.config.json`   | warn           | Automaton runs with defaults      |
| `AGENTS.md`               | warn           | Needed for agent role definitions  |
| `specs/` directory        | warn           | Needed for spec-driven workflow    |
| `PRD.md`                  | warn           | Needed for product context         |

- If `automaton.config.json` exists, validate it is parseable JSON using
  `jq empty < automaton.config.json`. A parse failure is a **fail**.

### 7. State Directory Check

- If `.automaton/` exists, confirm it is a directory (not a file) and is
  writable. Not writable is a **fail**.
- If `.automaton/` does not exist, report **pass** with a note that it will
  be created on first run.

### 8. Output Format

Results are printed as a plain-text table to stdout:

```
automaton --doctor

  bash .................. PASS  (5.2.15, requires >=4.0)
  git ................... PASS  (2.39.2, requires >=2.20)
  claude ................ PASS
  jq .................... PASS  (1.6, requires >=1.5)
  claude auth ........... WARN  (could not verify; run 'claude login')
  disk space ............ PASS  (12.4 GB free)
  git repo .............. PASS
  git remote ............ PASS  (origin -> git@github.com:user/repo.git)
  working tree .......... INFO  (3 uncommitted changes)
  automaton.config.json . PASS  (valid JSON)
  AGENTS.md ............. WARN  (not found; create to define agent roles)
  specs/ ................ PASS
  PRD.md ................ WARN  (not found; create for product context)
  .automaton/ ........... PASS

  Result: 10 passed, 3 warnings, 0 failures
```

- PASS lines in green (ANSI), WARN in yellow, FAIL in red, INFO in blue.
- Color output disabled when stdout is not a TTY or when `NO_COLOR` env var
  is set (respect the no-color.org convention).
- The final summary line counts each category.

### 9. Actionable Fix Messages

Every WARN or FAIL must include a one-line remediation hint. Examples:

- `jq` missing: `Install jq: https://jqlang.github.io/jq/download/`
- `bash` too old: `Upgrade bash: brew install bash (macOS) or apt install bash`
- Config parse error: `Fix JSON syntax in automaton.config.json`
- No remote: `Add a git remote: git remote add origin <url>`

## Acceptance Criteria

- [ ] `automaton.sh --doctor` runs and exits 0 on a correctly configured machine.
- [ ] Missing `jq` causes exit code 1 with a FAIL line and install instructions.
- [ ] Bash version below 4.0 causes exit code 1.
- [ ] Invalid `automaton.config.json` causes exit code 1.
- [ ] Missing `AGENTS.md` causes a WARN (not a fail) and exits 0.
- [ ] Disk space below 100 MB triggers a WARN; below 10 MB triggers a FAIL.
- [ ] Output respects `NO_COLOR` and non-TTY detection.
- [ ] No network calls or Claude API calls are made during the check.
- [ ] The entire doctor implementation fits within 100 lines of bash.
- [ ] Runs in under 2 seconds on typical hardware.

## Design Considerations

- **Single bash file**: All doctor logic lives inside `automaton.sh` as a
  function (e.g., `doctor_check()`) called when `--doctor` is the first
  argument. No external scripts.
- **Zero dependencies**: The doctor checks only the four allowed tools plus
  standard POSIX utilities (`df`, `test`, `command`). No curl, no python.
- **File-based state**: The doctor reads `.automaton/` but never writes to it.
  It is purely diagnostic.
- **Composability**: The doctor function should use a small helper like
  `report_check "name" "status" "detail"` to keep output consistent and the
  line count low.
- **Fast execution**: Every check uses local-only commands. The claude auth
  check uses `claude --version`, not an API call.
- **Idempotent**: Running `--doctor` multiple times has no side effects.

## Dependencies

- Depends on: spec-01 (CLI argument parsing framework in `automaton.sh`)
- Related: spec-03 (configuration file format for `automaton.config.json`)
- Related: spec-12 (project scaffolding; `--doctor` checks what scaffolding
  would create)

## Files to Modify

- `automaton.sh` -- Add `doctor_check()` function and `--doctor` flag handler
  in the argument parsing block. Estimated ~80-100 lines of bash.
