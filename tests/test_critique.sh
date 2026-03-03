#!/usr/bin/env bash
# tests/test_critique.sh — Tests for spec-47 pre-flight spec critique
# Verifies that phase_critique() gathers spec files, estimates tokens,
# truncates at ceiling, generates SPEC_CRITIQUE.md, and handles config.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_critique_$$"
mkdir -p "$test_dir" "$test_dir/.automaton" "$test_dir/specs"
trap 'rm -rf "$test_dir"' EXIT

# Create test spec files
cat > "$test_dir/specs/spec-01-example.md" <<'SPEC'
# Spec 01: Example Feature
## Requirements
1. The system should be fast.
2. Users can log in.
## Acceptance Criteria
- [ ] Login works
SPEC

cat > "$test_dir/specs/spec-02-another.md" <<'SPEC'
# Spec 02: Another Feature
## Requirements
1. Depends on spec-01 features.
2. Data must be scalable.
## Acceptance Criteria
- [ ] Feature works correctly
SPEC

# Extract phase_critique and its helpers from automaton.sh
_extract_critique() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail

# Minimal stubs
log() { :; }
AUTOMATON_DIR="$TEST_DIR/.automaton"
PROJECT_ROOT="$TEST_DIR"
CRITIQUE_AUTO_PREFLIGHT="false"
CRITIQUE_BLOCK_ON_ERROR="true"
CRITIQUE_MAX_TOKEN_ESTIMATE=80000

# Stub claude command to return test JSON
claude() {
    cat <<'MOCK_OUTPUT'
{
  "findings": [
    {
      "severity": "ERROR",
      "spec": "spec-01",
      "dimension": "ambiguity",
      "description": "Requirement 1 uses \"should be fast\" without defining a latency target.",
      "suggestion": "Add a measurable threshold (e.g., \"responds within 200ms\")."
    },
    {
      "severity": "WARNING",
      "spec": "spec-02",
      "dimension": "missing_dependency",
      "description": "References spec-01 features but does not declare dependency.",
      "suggestion": "Add explicit dependency declaration."
    },
    {
      "severity": "INFO",
      "spec": "spec-02",
      "dimension": "ambiguity",
      "description": "\"scalable\" is vague without quantitative bounds.",
      "suggestion": "Define expected data volume and growth rate."
    }
  ]
}
MOCK_OUTPUT
}
export -f claude
HARNESS
    # Extract the phase_critique function and _critique_generate_report helper
    sed -n '/^phase_critique()/,/^[^ ]/{ /^[^ ]/!p; /^phase_critique()/p; }' "$script_file" >> "$test_dir/harness.sh"
    sed -n '/^_critique_generate_report()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_generate_report()/p; }' "$script_file" >> "$test_dir/harness.sh"
    sed -n '/^_critique_collect_specs()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_collect_specs()/p; }' "$script_file" >> "$test_dir/harness.sh"
}
_extract_critique

# --- Test 1: _critique_collect_specs gathers spec files ---
output=$(TEST_DIR="$test_dir" bash -c "
    source '$test_dir/harness.sh'
    _critique_collect_specs '$test_dir/specs'
" 2>&1) || true
rc=$?
# Should contain both specs with headers
assert_contains "$output" "spec-01-example.md" "collect_specs includes spec-01"
assert_contains "$output" "spec-02-another.md" "collect_specs includes spec-02"

# --- Test 2: phase_critique creates SPEC_CRITIQUE.md ---
TEST_DIR="$test_dir" bash -c "
    source '$test_dir/harness.sh'
    phase_critique '$test_dir/specs'
" 2>&1 || true
assert_file_exists "$test_dir/.automaton/SPEC_CRITIQUE.md" "SPEC_CRITIQUE.md is created"

# --- Test 3: Report contains severity tags ---
if [ -f "$test_dir/.automaton/SPEC_CRITIQUE.md" ]; then
    report=$(cat "$test_dir/.automaton/SPEC_CRITIQUE.md")
    assert_contains "$report" "[ERROR]" "report contains ERROR tag"
    assert_contains "$report" "[WARNING]" "report contains WARNING tag"
    assert_contains "$report" "[INFO]" "report contains INFO tag"
    assert_contains "$report" "Spec Critique Report" "report has title"
    assert_contains "$report" "Summary" "report has summary section"
fi

# --- Test 4: phase_critique returns exit 1 when errors found ---
exit_code=0
TEST_DIR="$test_dir" bash -c "
    source '$test_dir/harness.sh'
    phase_critique '$test_dir/specs'
" 2>&1 || exit_code=$?
assert_equals "1" "$exit_code" "phase_critique exits 1 when errors found"

# --- Test 5: phase_critique returns exit 0 when only warnings ---
# Override claude stub to return only warnings
cat > "$test_dir/harness_warn.sh" <<'WARN_HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_DIR/.automaton"
PROJECT_ROOT="$TEST_DIR"
CRITIQUE_AUTO_PREFLIGHT="false"
CRITIQUE_BLOCK_ON_ERROR="true"
CRITIQUE_MAX_TOKEN_ESTIMATE=80000
claude() {
    cat <<'MOCK_OUTPUT'
{
  "findings": [
    {
      "severity": "WARNING",
      "spec": "spec-02",
      "dimension": "missing_dependency",
      "description": "References spec-01 features but does not declare dependency.",
      "suggestion": "Add explicit dependency declaration."
    }
  ]
}
MOCK_OUTPUT
}
export -f claude
WARN_HARNESS
sed -n '/^phase_critique()/,/^[^ ]/{ /^[^ ]/!p; /^phase_critique()/p; }' "$script_file" >> "$test_dir/harness_warn.sh"
sed -n '/^_critique_generate_report()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_generate_report()/p; }' "$script_file" >> "$test_dir/harness_warn.sh"
sed -n '/^_critique_collect_specs()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_collect_specs()/p; }' "$script_file" >> "$test_dir/harness_warn.sh"

rm -f "$test_dir/.automaton/SPEC_CRITIQUE.md"
exit_code=0
TEST_DIR="$test_dir" bash -c "
    source '$test_dir/harness_warn.sh'
    phase_critique '$test_dir/specs'
" 2>&1 || exit_code=$?
assert_equals "0" "$exit_code" "phase_critique exits 0 when only warnings"

# --- Test 6: Token estimation and truncation ---
# Create a spec file that's oversized relative to a low ceiling
cat > "$test_dir/harness_trunc.sh" <<'TRUNC_HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { echo "$@" >&2; }
AUTOMATON_DIR="$TEST_DIR/.automaton"
PROJECT_ROOT="$TEST_DIR"
CRITIQUE_AUTO_PREFLIGHT="false"
CRITIQUE_BLOCK_ON_ERROR="true"
CRITIQUE_MAX_TOKEN_ESTIMATE=10  # Very low ceiling for testing
claude() {
    echo '{"findings": []}'
}
export -f claude
TRUNC_HARNESS
sed -n '/^phase_critique()/,/^[^ ]/{ /^[^ ]/!p; /^phase_critique()/p; }' "$script_file" >> "$test_dir/harness_trunc.sh"
sed -n '/^_critique_generate_report()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_generate_report()/p; }' "$script_file" >> "$test_dir/harness_trunc.sh"
sed -n '/^_critique_collect_specs()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_collect_specs()/p; }' "$script_file" >> "$test_dir/harness_trunc.sh"

rm -f "$test_dir/.automaton/SPEC_CRITIQUE.md"
output=$(TEST_DIR="$test_dir" bash -c "
    source '$test_dir/harness_trunc.sh'
    phase_critique '$test_dir/specs'
" 2>&1) || true
assert_contains "$output" "truncat" "truncation warning emitted when specs exceed ceiling"

# --- Test 7: No spec files produces appropriate message ---
empty_dir="$test_dir/empty_specs"
mkdir -p "$empty_dir"
cat > "$test_dir/harness_empty.sh" <<'EMPTY_HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { echo "$@" >&2; }
AUTOMATON_DIR="$TEST_DIR/.automaton"
PROJECT_ROOT="$TEST_DIR"
CRITIQUE_AUTO_PREFLIGHT="false"
CRITIQUE_BLOCK_ON_ERROR="true"
CRITIQUE_MAX_TOKEN_ESTIMATE=80000
claude() { echo '{"findings": []}'; }
export -f claude
EMPTY_HARNESS
sed -n '/^phase_critique()/,/^[^ ]/{ /^[^ ]/!p; /^phase_critique()/p; }' "$script_file" >> "$test_dir/harness_empty.sh"
sed -n '/^_critique_generate_report()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_generate_report()/p; }' "$script_file" >> "$test_dir/harness_empty.sh"
sed -n '/^_critique_collect_specs()/,/^[^ ]/{ /^[^ ]/!p; /^_critique_collect_specs()/p; }' "$script_file" >> "$test_dir/harness_empty.sh"

output=$(TEST_DIR="$test_dir" bash -c "
    source '$test_dir/harness_empty.sh'
    phase_critique '$empty_dir'
" 2>&1) || true
assert_contains "$output" "No spec files" "no spec files produces warning"

test_summary
