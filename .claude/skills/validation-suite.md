---
name: validation-suite
description: Run the complete validation suite for the project
tools: Bash, Read
---

## Instructions

Detect the project type and run all applicable validation commands. Report results as structured JSON.

### Step 1: Detect Project Type

Check for configuration files in the project root to determine which validation commands apply:

| File Present | Validation Commands |
|---|---|
| `package.json` | `npm test`, `npm run lint` (if `lint` script exists), `npm run typecheck` (if `typecheck` script exists) |
| `Makefile` | `make test` (if `test` target exists) |
| `pytest.ini` or `setup.py` or `pyproject.toml` | `pytest` |
| `automaton.sh` | `bash -n automaton.sh` |
| `Cargo.toml` | `cargo test`, `cargo clippy` |
| `go.mod` | `go test ./...`, `go vet ./...` |

For `package.json`, read the file to check which scripts are defined before running them. Only run scripts that exist.

For `Makefile`, check for the target before running it (e.g., `make -n test` or grep for `^test:` in the Makefile).

### Step 2: Run Each Validation Command

Run each detected command sequentially. For each command:
- Record the command name
- Record pass (exit code 0) or fail (non-zero exit code)
- Capture the first 50 lines of output on failure (for diagnostics)

Do not stop on the first failure. Run all detected commands to provide a complete report.

### Step 3: Output Structured Results

Output a single JSON object with the validation results:

```json
{
  "project_type": "node",
  "validations": [
    {
      "command": "npm test",
      "status": "pass",
      "exit_code": 0
    },
    {
      "command": "npm run lint",
      "status": "fail",
      "exit_code": 1,
      "output_excerpt": "first 50 lines of failure output..."
    }
  ],
  "summary": {
    "total": 2,
    "passed": 1,
    "failed": 1
  }
}
```

## Constraints

- This skill is idempotent. Running it multiple times produces the same results for the same code state.
- Output must be valid JSON. Do not include markdown formatting around the JSON output.
- Do not modify any project files. This skill is read-only except for running test/lint commands.
- If no project type is detected, output `{"project_type": "unknown", "validations": [], "summary": {"total": 0, "passed": 0, "failed": 0}}`.
- If a command is not found (e.g., `shellcheck` not installed), skip it and do not report it as a failure.
- Capture at most 50 lines of output per failed command to avoid excessive output.
