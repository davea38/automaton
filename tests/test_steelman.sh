#!/usr/bin/env bash
# tests/test_steelman.sh — Tests for spec-53 steelman self-critique
# Verifies run_steelman_critique() reads plan+specs, invokes claude, writes
# STEELMAN.md, handles failures gracefully, and avoids side effects.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_steelman_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# Extract run_steelman_critique from automaton.sh into a test harness
_extract_function() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
HARNESS
    sed -n '/^run_steelman_critique()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
}
_extract_function

# Helper: create a minimal project dir with plan and specs
_setup_project() {
    local project_dir
    project_dir=$(mktemp -d "$test_dir/project_XXXXXX")
    mkdir -p "$project_dir/specs" "$project_dir/.automaton"

    cat > "$project_dir/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [ ] Task one: implement feature X
- [ ] Task two: add tests for feature X
PLAN

    cat > "$project_dir/specs/spec-01-example.md" <<'SPEC'
# Spec 01: Example Feature
## Requirements
- Must implement feature X
## Acceptance Criteria
- [ ] Feature X works correctly
SPEC

    echo "$project_dir"
}

# --- Test 1: run_steelman_critique aborts with exit 1 when no plan exists ---
project_dir=$(mktemp -d "$test_dir/project_XXXXXX")
mkdir -p "$project_dir/.automaton"
# No IMPLEMENTATION_PLAN.md

rc=0
(
    export PROJECT_ROOT="$project_dir"
    export AUTOMATON_DIR="$project_dir/.automaton"
    source "$test_dir/harness.sh"
    run_steelman_critique
) 2>/dev/null || rc=$?
assert_equals "1" "$rc" "Exit 1 when no IMPLEMENTATION_PLAN.md exists"

# --- Test 2: run_steelman_critique produces STEELMAN.md ---
project_dir=$(_setup_project)

# Mock claude to return a valid critique
cat > "$test_dir/mock_claude.sh" <<'MOCK'
#!/usr/bin/env bash
cat <<'RESPONSE'
# STEELMAN Self-Critique

## Risks and Failure Modes
- The plan assumes network availability.

## Rejected Alternatives
- Could have used a database instead of files.

## Questionable Assumptions
- Assumes bash 4.0+ is available everywhere.

## Fragile Dependencies
- Relies on claude CLI being installed.

## Complexity Hotspots
- Task two interacts with task one in unclear ways.
RESPONSE
MOCK
chmod +x "$test_dir/mock_claude.sh"

rc=0
(
    export PROJECT_ROOT="$project_dir"
    export AUTOMATON_DIR="$project_dir/.automaton"
    export PATH="$test_dir:$PATH"
    # Create a 'claude' wrapper that calls our mock
    cat > "$test_dir/claude" <<WRAPPER
#!/usr/bin/env bash
exec "$test_dir/mock_claude.sh"
WRAPPER
    chmod +x "$test_dir/claude"
    source "$test_dir/harness.sh"
    run_steelman_critique
) 2>/dev/null || rc=$?
assert_equals "0" "$rc" "Exit 0 on successful steelman critique"
assert_file_exists "$project_dir/STEELMAN.md" "STEELMAN.md should be created"

# Check all 5 required sections
output=$(cat "$project_dir/STEELMAN.md")
assert_contains "$output" "Risks and Failure Modes" "Contains Risks section"
assert_contains "$output" "Rejected Alternatives" "Contains Alternatives section"
assert_contains "$output" "Questionable Assumptions" "Contains Assumptions section"
assert_contains "$output" "Fragile Dependencies" "Contains Dependencies section"
assert_contains "$output" "Complexity Hotspots" "Contains Hotspots section"

# --- Test 3: STEELMAN.md contains a timestamp header ---
assert_contains "$output" "Generated:" "Contains generation timestamp"

# --- Test 4: Non-blocking on claude failure ---
project_dir=$(_setup_project)
rc=0
(
    export PROJECT_ROOT="$project_dir"
    export AUTOMATON_DIR="$project_dir/.automaton"
    # Mock claude that fails
    claude() { return 1; }
    export -f claude
    source "$test_dir/harness.sh"
    run_steelman_critique
) 2>/dev/null || rc=$?
assert_equals "0" "$rc" "Return 0 even when claude fails (non-blocking)"

# --- Test 5: Does not modify .automaton/ or specs/ ---
project_dir=$(_setup_project)
spec_checksum=$(md5sum "$project_dir/specs/spec-01-example.md" | awk '{print $1}')
automaton_files_before=$(ls "$project_dir/.automaton/" 2>/dev/null | sort)

(
    export PROJECT_ROOT="$project_dir"
    export AUTOMATON_DIR="$project_dir/.automaton"
    export PATH="$test_dir:$PATH"
    source "$test_dir/harness.sh"
    run_steelman_critique
) 2>/dev/null || true

spec_checksum_after=$(md5sum "$project_dir/specs/spec-01-example.md" | awk '{print $1}')
automaton_files_after=$(ls "$project_dir/.automaton/" 2>/dev/null | sort)

assert_equals "$spec_checksum" "$spec_checksum_after" "specs/ files unchanged"
assert_equals "$automaton_files_before" "$automaton_files_after" ".automaton/ directory unchanged"

# --- Test 6: FLAG_STEELMAN_CRITIQUE config key can be read ---
cfg_file=$(mktemp "$test_dir/config_XXXXXX.json")
echo '{"flags": {"steelman_critique": true}}' > "$cfg_file"
val=$(jq -r '.flags.steelman_critique // false' "$cfg_file")
assert_equals "true" "$val" "Config loads steelman_critique=true"

echo '{"flags": {"steelman_critique": false}}' > "$cfg_file"
val=$(jq -r '.flags.steelman_critique // false' "$cfg_file")
assert_equals "false" "$val" "Config loads steelman_critique=false"

# --- Test 7: function exists in automaton.sh ---
rc=0
grep -q '^run_steelman_critique()' "$script_file" || rc=1
assert_equals "0" "$rc" "run_steelman_critique() function exists in automaton.sh"

# --- Test 8: --steelman flag is parsed in automaton.sh ---
rc=0
grep -q '\-\-steelman)' "$script_file" || rc=1
assert_equals "0" "$rc" "--steelman flag is parsed in argument loop"

# --- Summary ---
test_summary
