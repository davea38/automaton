#!/usr/bin/env bash
# tests/test_qa_gates.sh — Tests for gate functions in lib/qa.sh
# Verifies gate_research_completeness, gate_plan_validity, gate_build_completion,
# gate_review_pass, check_phase_timeout, and the gate_check wrapper.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_qa_gates_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Extract gate functions from combined source ---
extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
emit_event() { :; }
run_started_at="1970-01-01"
current_phase="build"
HARNESS
    for fn in gate_check gate_research_completeness gate_plan_validity \
              gate_build_completion gate_review_pass check_phase_timeout; do
        sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/harness.sh" 2>/dev/null || true
    done
}
extract_functions

# ===================================================================
# gate_research_completeness
# ===================================================================

# --- Test 1: gate_research_completeness PASS — no TBDs, AGENTS.md grown ---
mkdir -p "$test_dir/research_pass/specs"
# AGENTS.md with more than 22 lines
for i in $(seq 1 30); do echo "Agent line $i" >> "$test_dir/research_pass/AGENTS.md"; done
# Spec file with no TBD/TODO
echo "# Spec 01 - Feature" > "$test_dir/research_pass/specs/spec-01.md"
(cd "$test_dir/research_pass" && source "$test_dir/harness.sh" && gate_research_completeness)
rc=$?
assert_exit_code 0 "$rc" "gate_research_completeness PASS when specs clean and AGENTS.md grown"

# --- Test 2: gate_research_completeness FAIL — TBD in specs ---
mkdir -p "$test_dir/research_tbd/specs"
for i in $(seq 1 30); do echo "Agent line $i" >> "$test_dir/research_tbd/AGENTS.md"; done
echo "# Spec - TBD details" > "$test_dir/research_tbd/specs/spec-01.md"
(cd "$test_dir/research_tbd" && source "$test_dir/harness.sh" && gate_research_completeness)
rc=$?
assert_exit_code 1 "$rc" "gate_research_completeness FAIL when TBD in specs"

# --- Test 3: gate_research_completeness FAIL — TODO in specs ---
mkdir -p "$test_dir/research_todo/specs"
for i in $(seq 1 30); do echo "Agent line $i" >> "$test_dir/research_todo/AGENTS.md"; done
echo "# Spec - TODO: fill in" > "$test_dir/research_todo/specs/spec-01.md"
(cd "$test_dir/research_todo" && source "$test_dir/harness.sh" && gate_research_completeness)
rc=$?
assert_exit_code 1 "$rc" "gate_research_completeness FAIL when TODO in specs"

# --- Test 4: gate_research_completeness PASS — small AGENTS.md is only a warning ---
mkdir -p "$test_dir/research_small_agents/specs"
echo "Short agents" > "$test_dir/research_small_agents/AGENTS.md"
echo "# Clean spec" > "$test_dir/research_small_agents/specs/spec-01.md"
(cd "$test_dir/research_small_agents" && source "$test_dir/harness.sh" && gate_research_completeness)
rc=$?
assert_exit_code 0 "$rc" "gate_research_completeness PASS with small AGENTS.md (warning only)"

# ===================================================================
# gate_plan_validity
# ===================================================================

# --- Test 5: gate_plan_validity PASS — 5+ unchecked tasks, >10 lines ---
mkdir -p "$test_dir/plan_pass"
cat > "$test_dir/plan_pass/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
## Phase 1
Refer to spec-01 for details.
### Tasks
- [ ] Task 1 (spec-01)
- [ ] Task 2 (spec-02)
- [ ] Task 3 (spec-03)
- [ ] Task 4 (spec-04)
- [ ] Task 5 (spec-05)
## Notes
Additional context here.
PLAN
(cd "$test_dir/plan_pass" && source "$test_dir/harness.sh" && gate_plan_validity)
rc=$?
assert_exit_code 0 "$rc" "gate_plan_validity PASS with 5 unchecked tasks and >10 lines"

# --- Test 6: gate_plan_validity FAIL — fewer than 5 unchecked tasks ---
mkdir -p "$test_dir/plan_few"
cat > "$test_dir/plan_few/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
## Phase 1
Refer to spec-01 for details.
### Tasks
- [ ] Task 1 (spec-01)
- [ ] Task 2 (spec-02)
- [x] Task 3 done
## Notes
Additional context here.
Some more text.
PLAN
(cd "$test_dir/plan_few" && source "$test_dir/harness.sh" && gate_plan_validity)
rc=$?
assert_exit_code 1 "$rc" "gate_plan_validity FAIL with fewer than 5 unchecked tasks"

# --- Test 7: gate_plan_validity FAIL — plan too short (<=10 lines) ---
mkdir -p "$test_dir/plan_short"
cat > "$test_dir/plan_short/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Plan
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
- [ ] Task 4
- [ ] Task 5
PLAN
(cd "$test_dir/plan_short" && source "$test_dir/harness.sh" && gate_plan_validity)
rc=$?
assert_exit_code 1 "$rc" "gate_plan_validity FAIL when plan is too short"

# --- Test 8: gate_plan_validity PASS — no spec refs is warning only ---
mkdir -p "$test_dir/plan_nospec"
cat > "$test_dir/plan_nospec/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
## Phase 1
Some context about the project.
### Tasks
- [ ] Task 1 - build the thing
- [ ] Task 2 - add feature
- [ ] Task 3 - fix bug
- [ ] Task 4 - write tests
- [ ] Task 5 - deploy
## Notes
Additional notes and context.
PLAN
(cd "$test_dir/plan_nospec" && source "$test_dir/harness.sh" && gate_plan_validity)
rc=$?
assert_exit_code 0 "$rc" "gate_plan_validity PASS when no spec references (warning only)"

# --- Test 9: gate_plan_validity FAIL — both conditions violated ---
mkdir -p "$test_dir/plan_both_fail"
cat > "$test_dir/plan_both_fail/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Plan
- [ ] Task 1
PLAN
(cd "$test_dir/plan_both_fail" && source "$test_dir/harness.sh" && gate_plan_validity)
rc=$?
assert_exit_code 1 "$rc" "gate_plan_validity FAIL when both too few tasks and too short"

# ===================================================================
# gate_build_completion
# ===================================================================

# --- Test 10: gate_build_completion PASS — all tasks checked ---
mkdir -p "$test_dir/build_pass"
cat > "$test_dir/build_pass/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [x] Task 2
- [x] Task 3
PLAN
# Initialize a git repo so git log works
(cd "$test_dir/build_pass" && git init -q && git commit --allow-empty -m "init" -q)
(cd "$test_dir/build_pass" && source "$test_dir/harness.sh" && gate_build_completion)
rc=$?
assert_exit_code 0 "$rc" "gate_build_completion PASS when all tasks complete"

# --- Test 11: gate_build_completion FAIL — unchecked tasks remain ---
mkdir -p "$test_dir/build_fail"
cat > "$test_dir/build_fail/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [ ] Task 2 incomplete
- [x] Task 3
PLAN
(cd "$test_dir/build_fail" && git init -q && git commit --allow-empty -m "init" -q)
(cd "$test_dir/build_fail" && source "$test_dir/harness.sh" && gate_build_completion)
rc=$?
assert_exit_code 1 "$rc" "gate_build_completion FAIL when unchecked tasks remain"

# --- Test 12: gate_build_completion FAIL — multiple unchecked tasks ---
mkdir -p "$test_dir/build_multi_fail"
cat > "$test_dir/build_multi_fail/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
PLAN
(cd "$test_dir/build_multi_fail" && git init -q && git commit --allow-empty -m "init" -q)
(cd "$test_dir/build_multi_fail" && source "$test_dir/harness.sh" && gate_build_completion)
rc=$?
assert_exit_code 1 "$rc" "gate_build_completion FAIL with multiple unchecked tasks"

# ===================================================================
# gate_review_pass
# ===================================================================

# --- Test 13: gate_review_pass PASS — no unchecked tasks, no escalation ---
mkdir -p "$test_dir/review_pass"
cat > "$test_dir/review_pass/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [x] Task 2
PLAN
(cd "$test_dir/review_pass" && source "$test_dir/harness.sh" && gate_review_pass)
rc=$?
assert_exit_code 0 "$rc" "gate_review_pass PASS when all tasks done and no escalation"

# --- Test 14: gate_review_pass FAIL — unchecked tasks added by reviewer ---
mkdir -p "$test_dir/review_unchecked"
cat > "$test_dir/review_unchecked/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [ ] New task from reviewer
PLAN
(cd "$test_dir/review_unchecked" && source "$test_dir/harness.sh" && gate_review_pass)
rc=$?
assert_exit_code 1 "$rc" "gate_review_pass FAIL when reviewer added unchecked tasks"

# --- Test 15: gate_review_pass FAIL — ESCALATION marker present ---
mkdir -p "$test_dir/review_escalation"
cat > "$test_dir/review_escalation/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [x] Task 2
ESCALATION: Critical issue found during review
PLAN
(cd "$test_dir/review_escalation" && source "$test_dir/harness.sh" && gate_review_pass)
rc=$?
assert_exit_code 1 "$rc" "gate_review_pass FAIL when ESCALATION marker present"

# --- Test 16: gate_review_pass FAIL — both unchecked tasks and escalation ---
mkdir -p "$test_dir/review_both"
cat > "$test_dir/review_both/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [ ] New task
ESCALATION: Something wrong
PLAN
(cd "$test_dir/review_both" && source "$test_dir/harness.sh" && gate_review_pass)
rc=$?
assert_exit_code 1 "$rc" "gate_review_pass FAIL when both unchecked tasks and escalation"

# ===================================================================
# check_phase_timeout
# ===================================================================

# --- Test 17: check_phase_timeout PASS — no timeout configured (0) ---
mkdir -p "$test_dir/timeout_none"
(cd "$test_dir/timeout_none" && source "$test_dir/harness.sh" && \
    EXEC_PHASE_TIMEOUT_BUILD=0 current_phase="build" PHASE_START_TIME=1 check_phase_timeout)
rc=$?
assert_exit_code 0 "$rc" "check_phase_timeout PASS when timeout is 0 (disabled)"

# --- Test 18: check_phase_timeout PASS — PHASE_START_TIME not set ---
mkdir -p "$test_dir/timeout_nostart"
(cd "$test_dir/timeout_nostart" && source "$test_dir/harness.sh" && \
    EXEC_PHASE_TIMEOUT_BUILD=60 current_phase="build" unset PHASE_START_TIME && check_phase_timeout)
rc=$?
assert_exit_code 0 "$rc" "check_phase_timeout PASS when PHASE_START_TIME not set"

# --- Test 19: check_phase_timeout PASS — within time limit ---
now=$(date +%s)
start=$((now - 10))
mkdir -p "$test_dir/timeout_ok"
(cd "$test_dir/timeout_ok" && source "$test_dir/harness.sh" && \
    EXEC_PHASE_TIMEOUT_BUILD=3600 current_phase="build" PHASE_START_TIME=$start check_phase_timeout)
rc=$?
assert_exit_code 0 "$rc" "check_phase_timeout PASS when within time limit"

# --- Test 20: check_phase_timeout FAIL — timeout exceeded ---
now=$(date +%s)
start=$((now - 7200))
mkdir -p "$test_dir/timeout_exceeded"
(cd "$test_dir/timeout_exceeded" && source "$test_dir/harness.sh" && \
    EXEC_PHASE_TIMEOUT_BUILD=3600 current_phase="build" PHASE_START_TIME=$start check_phase_timeout)
rc=$?
assert_exit_code 1 "$rc" "check_phase_timeout FAIL when timeout exceeded"

# --- Test 21: check_phase_timeout uses correct phase variable ---
now=$(date +%s)
start=$((now - 100))
mkdir -p "$test_dir/timeout_phase"
(cd "$test_dir/timeout_phase" && source "$test_dir/harness.sh" && \
    EXEC_PHASE_TIMEOUT_RESEARCH=50 current_phase="research" PHASE_START_TIME=$start check_phase_timeout)
rc=$?
assert_exit_code 1 "$rc" "check_phase_timeout uses phase-specific timeout variable"

# --- Test 22: check_phase_timeout PASS — exactly at boundary ---
now=$(date +%s)
start=$((now - 59))
mkdir -p "$test_dir/timeout_boundary"
(cd "$test_dir/timeout_boundary" && source "$test_dir/harness.sh" && \
    EXEC_PHASE_TIMEOUT_BUILD=60 current_phase="build" PHASE_START_TIME=$start check_phase_timeout)
rc=$?
assert_exit_code 0 "$rc" "check_phase_timeout PASS when just under timeout boundary"

# ===================================================================
# gate_check wrapper
# ===================================================================

# --- Test 23: gate_check returns 0 when gate passes ---
mkdir -p "$test_dir/gatecheck_pass"
cat > "$test_dir/gatecheck_pass/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Task 1
- [x] Task 2
PLAN
(cd "$test_dir/gatecheck_pass" && source "$test_dir/harness.sh" && gate_check review_pass)
rc=$?
assert_exit_code 0 "$rc" "gate_check returns 0 when gate function passes"

# --- Test 24: gate_check returns 1 when gate fails ---
mkdir -p "$test_dir/gatecheck_fail"
cat > "$test_dir/gatecheck_fail/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [ ] Incomplete task
PLAN
(cd "$test_dir/gatecheck_fail" && source "$test_dir/harness.sh" && gate_check review_pass)
rc=$?
assert_exit_code 1 "$rc" "gate_check returns 1 when gate function fails"

# --- Test 25: gate_check logs PASS for passing gate ---
mkdir -p "$test_dir/gatecheck_log_pass"
cat > "$test_dir/gatecheck_log_pass/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [x] Done
PLAN
# Override log to capture output
cat > "$test_dir/gatecheck_log_harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
_log_output=""
log() { _log_output="$_log_output $*"; }
emit_event() { :; }
HARNESS
for fn in gate_check gate_review_pass; do
    sed -n "/^${fn}() {/,/^}/p" "$script_file" >> "$test_dir/gatecheck_log_harness.sh" 2>/dev/null || true
done
output=$(cd "$test_dir/gatecheck_log_pass" && source "$test_dir/gatecheck_log_harness.sh" && \
    gate_check review_pass && echo "$_log_output")
assert_contains "$output" "PASS" "gate_check logs PASS for passing gate"

# --- Test 26: gate_check logs FAIL for failing gate ---
mkdir -p "$test_dir/gatecheck_log_fail"
cat > "$test_dir/gatecheck_log_fail/IMPLEMENTATION_PLAN.md" <<'PLAN'
# Implementation Plan
- [ ] Incomplete
PLAN
output=$(cd "$test_dir/gatecheck_log_fail" && source "$test_dir/gatecheck_log_harness.sh" && \
    gate_check review_pass; echo "$_log_output")
assert_contains "$output" "FAIL" "gate_check logs FAIL for failing gate"

echo ""
echo "=== test_qa_gates.sh complete ==="
test_summary
