#!/usr/bin/env bash
# tests/test_qa_behavioral.sh — Behavioral tests for lib/qa.sh gate functions.
# Actually executes gate checks against real file structures.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
setup_test_dir

# Minimal stubs
AUTOMATON_DIR="$TEST_DIR/.automaton"
mkdir -p "$AUTOMATON_DIR"
log() { :; }
emit_event() { :; }

# Source the QA module
source "$_PROJECT_DIR/lib/qa.sh"

cd "$TEST_DIR"

# --- Test 1: gate_spec_completeness fails with no specs ---
mkdir -p specs
gate_spec_completeness && rc=0 || rc=1
assert_exit_code 1 "$rc" "gate_spec_completeness fails with no specs"

# --- Test 2: gate_spec_completeness fails with missing PRD ---
echo "# Spec 1" > specs/spec-01-auth.md
gate_spec_completeness && rc=0 || rc=1
assert_exit_code 1 "$rc" "gate_spec_completeness fails without PRD.md"

# --- Test 3: gate_spec_completeness fails with template AGENTS.md ---
echo "# PRD" > PRD.md
echo 'Project: (to be determined)' > AGENTS.md
gate_spec_completeness && rc=0 || rc=1
assert_exit_code 1 "$rc" "gate_spec_completeness fails with template placeholder"

# --- Test 4: gate_spec_completeness passes with all files ---
echo "Project: MyApp" > AGENTS.md
gate_spec_completeness
assert_exit_code 0 $? "gate_spec_completeness passes with specs, PRD, and AGENTS.md"

# --- Test 5: gate_research_completeness fails with TBD in specs ---
echo "# Spec with TBD items" > specs/spec-01-auth.md
echo "Database: TBD" >> specs/spec-01-auth.md
gate_research_completeness && rc=0 || rc=1
assert_exit_code 1 "$rc" "gate_research_completeness fails with TBD in specs"

# --- Test 6: gate_research_completeness passes with no TBD ---
echo "# Spec fully resolved" > specs/spec-01-auth.md
echo "Database: PostgreSQL 16" >> specs/spec-01-auth.md
gate_research_completeness
assert_exit_code 0 $? "gate_research_completeness passes with no TBD"

# --- Test 7: gate_plan_validity fails with too few tasks ---
cat > IMPLEMENTATION_PLAN.md <<'EOF'
- [ ] Task 1
- [ ] Task 2
EOF
gate_plan_validity && rc=0 || rc=1
assert_exit_code 1 "$rc" "gate_plan_validity fails with fewer than 5 tasks"

# --- Test 8: gate_plan_validity passes with 5+ tasks and >10 lines ---
cat > IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Phase 1: Core Features (spec-01)

- [ ] Task 1: Set up project structure (spec-01)
- [ ] Task 2: Add database schema (spec-01)
- [ ] Task 3: Implement auth layer (spec-01)
- [ ] Task 4: Build API routes (spec-01)
- [ ] Task 5: Add input validation (spec-01)

## Notes
Spec references checked above.
EOF
gate_plan_validity
assert_exit_code 0 $? "gate_plan_validity passes with 5 tasks, spec refs, and >10 lines"

# --- Test 9: gate_build_completion fails with unchecked tasks ---
cat > IMPLEMENTATION_PLAN.md <<'EOF'
- [x] Task 1
- [ ] Task 2
- [x] Task 3
EOF
git init . >/dev/null 2>&1
echo "change" > src.txt
git add -A >/dev/null 2>&1 && git commit -m "init" >/dev/null 2>&1
gate_build_completion && rc=0 || rc=1
assert_exit_code 1 "$rc" "gate_build_completion fails with unchecked tasks"

# --- Test 10: gate_build_completion passes with all tasks checked ---
cat > IMPLEMENTATION_PLAN.md <<'EOF'
- [x] Task 1
- [x] Task 2
- [x] Task 3
EOF
git add -A >/dev/null 2>&1 && git commit -m "complete" >/dev/null 2>&1
gate_build_completion
assert_exit_code 0 $? "gate_build_completion passes with all tasks checked"

cd "$SCRIPT_DIR/.."
test_summary
