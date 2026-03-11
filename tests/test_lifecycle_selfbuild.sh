#!/usr/bin/env bash
# tests/test_lifecycle_selfbuild.sh — Tests for self-build lifecycle functions in lib/lifecycle.sh
# Covers: self_build_checkpoint, self_build_validate, _self_build_restore,
#         _self_build_add_fix_task, _self_build_audit_entry, self_build_check_scope,
#         calculate_test_coverage

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_lifecycle_selfbuild_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Helper: build a harness with required globals and extracted functions ---
_build_harness() {
    local harness_file="$1"
    cat > "$harness_file" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail

# Minimal stubs
log() { :; }

# Required globals
SELF_BUILD_ENABLED="${SELF_BUILD_ENABLED:-true}"
AUTOMATON_DIR="$test_dir/.automaton"
SELF_BUILD_FILES="${SELF_BUILD_FILES:-}"
SELF_BUILD_REQUIRE_SMOKE="${SELF_BUILD_REQUIRE_SMOKE:-false}"
SELF_BUILD_MAX_FILES="${SELF_BUILD_MAX_FILES:-5}"
SELF_BUILD_MAX_LINES="${SELF_BUILD_MAX_LINES:-200}"
SELF_BUILD_PROTECTED_FUNCTIONS="${SELF_BUILD_PROTECTED_FUNCTIONS:-run_orchestration,_handle_shutdown}"
iteration="${iteration:-1}"
current_phase="${current_phase:-build}"
ARG_SELF="${ARG_SELF:-false}"
PLAN_FILE="${PLAN_FILE:-}"

rm -rf "\$AUTOMATON_DIR"
mkdir -p "\$AUTOMATON_DIR"
HARNESS

    # Extract all self-build functions from the combined source
    for fn in self_build_checkpoint self_build_validate _self_build_restore \
              _self_build_add_fix_task _self_build_audit_entry self_build_check_scope \
              calculate_test_coverage; do
        sed -n "/^${fn}()/,/^}/p" "$script_file" >> "$harness_file"
    done
}

# =====================================================================
# Section 1: self_build_checkpoint
# =====================================================================

# --- Test 1: checkpoint is no-op when SELF_BUILD_ENABLED=false ---
SELF_BUILD_ENABLED="false"
_build_harness "$test_dir/harness_cp_disabled.sh"

cat >> "$test_dir/harness_cp_disabled.sh" <<'EOF'
self_build_checkpoint
rc=$?
echo "EXIT=$rc"
if [ -f "$AUTOMATON_DIR/self_checksums.json" ]; then
    echo "CHECKSUMS_EXIST"
else
    echo "NO_CHECKSUMS"
fi
EOF

output=$(bash "$test_dir/harness_cp_disabled.sh" 2>&1)
assert_contains "$output" "EXIT=0" "checkpoint disabled: returns 0"
assert_contains "$output" "NO_CHECKSUMS" "checkpoint disabled: no checksums file created"

# --- Test 2: checkpoint creates checksums and backup ---
SELF_BUILD_ENABLED="true"
# Create test files to checkpoint
echo '#!/usr/bin/env bash' > "$test_dir/file_a.sh"
echo 'echo hello' >> "$test_dir/file_a.sh"
echo '{"key":"value"}' > "$test_dir/file_b.json"
SELF_BUILD_FILES="$test_dir/file_a.sh $test_dir/file_b.json"
_build_harness "$test_dir/harness_cp_happy.sh"

cat >> "$test_dir/harness_cp_happy.sh" <<'EOF'
self_build_checkpoint
rc=$?
echo "EXIT=$rc"
if [ -f "$AUTOMATON_DIR/self_checksums.json" ]; then
    echo "CHECKSUMS_EXIST"
    # Verify it's valid JSON with the right keys
    jq -e 'keys | length > 0' "$AUTOMATON_DIR/self_checksums.json" >/dev/null 2>&1 && echo "VALID_JSON"
else
    echo "NO_CHECKSUMS"
fi
if [ -d "$AUTOMATON_DIR/self_backup" ]; then
    backup_count=$(ls "$AUTOMATON_DIR/self_backup" | wc -l)
    echo "BACKUP_COUNT=$backup_count"
else
    echo "NO_BACKUP_DIR"
fi
EOF

output=$(bash "$test_dir/harness_cp_happy.sh" 2>&1)
assert_contains "$output" "EXIT=0" "checkpoint happy: returns 0"
assert_contains "$output" "CHECKSUMS_EXIST" "checkpoint happy: checksums file created"
assert_contains "$output" "VALID_JSON" "checkpoint happy: checksums file is valid JSON"
assert_contains "$output" "BACKUP_COUNT=2" "checkpoint happy: 2 backup files created"

# --- Test 3: checkpoint ignores nonexistent files ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES="$test_dir/file_a.sh $test_dir/nonexistent_file.sh"
_build_harness "$test_dir/harness_cp_missing.sh"

cat >> "$test_dir/harness_cp_missing.sh" <<'EOF'
self_build_checkpoint
rc=$?
echo "EXIT=$rc"
# Should only have checksum for file_a.sh
count=$(jq 'keys | length' "$AUTOMATON_DIR/self_checksums.json" 2>/dev/null)
echo "KEY_COUNT=$count"
EOF

output=$(bash "$test_dir/harness_cp_missing.sh" 2>&1)
assert_contains "$output" "EXIT=0" "checkpoint missing file: returns 0"
assert_contains "$output" "KEY_COUNT=1" "checkpoint missing file: only existing file checksummed"

# =====================================================================
# Section 2: self_build_validate
# =====================================================================

# --- Test 4: validate is no-op when disabled ---
SELF_BUILD_ENABLED="false"
_build_harness "$test_dir/harness_val_disabled.sh"

cat >> "$test_dir/harness_val_disabled.sh" <<'EOF'
self_build_validate
rc=$?
echo "EXIT=$rc"
EOF

output=$(bash "$test_dir/harness_val_disabled.sh" 2>&1)
assert_contains "$output" "EXIT=0" "validate disabled: returns 0"

# --- Test 5: validate happy path (no changes) ---
SELF_BUILD_ENABLED="true"
echo '#!/usr/bin/env bash' > "$test_dir/stable.sh"
SELF_BUILD_FILES="$test_dir/stable.sh"
_build_harness "$test_dir/harness_val_happy.sh"

cat >> "$test_dir/harness_val_happy.sh" <<'EOF'
# First checkpoint, then validate without changing anything
self_build_checkpoint
self_build_validate
rc=$?
echo "EXIT=$rc"
EOF

output=$(bash "$test_dir/harness_val_happy.sh" 2>&1)
assert_contains "$output" "EXIT=0" "validate no-change: returns 0"

# --- Test 6: validate detects changes (non-automaton.sh file) ---
SELF_BUILD_ENABLED="true"
echo 'original content' > "$test_dir/tracked.txt"
SELF_BUILD_FILES="$test_dir/tracked.txt"
_build_harness "$test_dir/harness_val_changed.sh"

cat >> "$test_dir/harness_val_changed.sh" <<'EOF'
self_build_checkpoint

# Modify the file after checkpoint
echo 'modified content' > "$AUTOMATON_DIR/../tracked.txt"

self_build_validate
rc=$?
echo "EXIT=$rc"
# Check that audit file was created
if [ -f "$AUTOMATON_DIR/self_modifications.json" ]; then
    entry_count=$(jq 'length' "$AUTOMATON_DIR/self_modifications.json" 2>/dev/null)
    echo "AUDIT_ENTRIES=$entry_count"
else
    echo "NO_AUDIT"
fi
EOF

# Fix: tracked.txt path must match between checkpoint and validate
echo 'original content' > "$test_dir/tracked.txt"
SELF_BUILD_FILES="$test_dir/tracked.txt"
_build_harness "$test_dir/harness_val_changed2.sh"

cat >> "$test_dir/harness_val_changed2.sh" <<TESTEOF
self_build_checkpoint

# Modify the tracked file after checkpoint
echo 'modified content' > "$test_dir/tracked.txt"

self_build_validate
rc=\$?
echo "EXIT=\$rc"
# Check that audit file was created
if [ -f "\$AUTOMATON_DIR/self_modifications.json" ]; then
    entry_count=\$(jq 'length' "\$AUTOMATON_DIR/self_modifications.json" 2>/dev/null)
    echo "AUDIT_ENTRIES=\$entry_count"
else
    echo "NO_AUDIT"
fi
TESTEOF

output=$(bash "$test_dir/harness_val_changed2.sh" 2>&1)
assert_contains "$output" "EXIT=0" "validate changed non-script: returns 0 (no syntax check needed)"
assert_contains "$output" "AUDIT_ENTRIES=1" "validate changed: audit entry created"

# --- Test 7: validate detects syntax failure in automaton.sh and restores ---
# We need a file named literally "automaton.sh" in the tracked list
mkdir -p "$test_dir/proj7"
cat > "$test_dir/proj7/automaton.sh" <<'GOODSCRIPT'
#!/usr/bin/env bash
echo "valid script"
GOODSCRIPT

SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES="$test_dir/proj7/automaton.sh"
SELF_BUILD_REQUIRE_SMOKE="false"
_build_harness "$test_dir/harness_val_syntax.sh"

# Override git to no-op for restore
cat >> "$test_dir/harness_val_syntax.sh" <<'EOF'
git() { :; }
EOF

cat >> "$test_dir/harness_val_syntax.sh" <<TESTEOF
cd "$test_dir/proj7"
self_build_checkpoint

# Break syntax in automaton.sh
echo 'if [[ broken' > "$test_dir/proj7/automaton.sh"

self_build_validate
rc=\$?
echo "EXIT=\$rc"

# Check that the file was restored
restored_content=\$(cat "$test_dir/proj7/automaton.sh")
echo "RESTORED=\$restored_content"
TESTEOF

output=$(bash "$test_dir/harness_val_syntax.sh" 2>&1)
assert_contains "$output" "EXIT=1" "validate syntax fail: returns 1"
assert_contains "$output" "RESTORED=#!/usr/bin/env bash" "validate syntax fail: file restored from backup"

# --- Test 8: validate with smoke test failure ---
mkdir -p "$test_dir/proj8"
cat > "$test_dir/proj8/automaton.sh" <<'GOODSCRIPT'
#!/usr/bin/env bash
echo "valid script"
GOODSCRIPT

SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES="$test_dir/proj8/automaton.sh"
SELF_BUILD_REQUIRE_SMOKE="true"
_build_harness "$test_dir/harness_val_smoke.sh"

# Override git to no-op
cat >> "$test_dir/harness_val_smoke.sh" <<'EOF'
git() { :; }
EOF

cat >> "$test_dir/harness_val_smoke.sh" <<TESTEOF
cd "$test_dir/proj8"
self_build_checkpoint

# Replace automaton.sh with syntactically valid but smoke-test-failing script
# (it will have valid syntax but --dry-run won't work since the file will exit 1)
cat > "$test_dir/proj8/automaton.sh" <<'NEWSCRIPT'
#!/usr/bin/env bash
exit 1
NEWSCRIPT
chmod +x "$test_dir/proj8/automaton.sh"

self_build_validate
rc=\$?
echo "EXIT=\$rc"

# Verify restoration
if grep -q "valid script" "$test_dir/proj8/automaton.sh"; then
    echo "FILE_RESTORED"
else
    echo "FILE_NOT_RESTORED"
fi
TESTEOF

output=$(bash "$test_dir/harness_val_smoke.sh" 2>&1)
assert_contains "$output" "EXIT=1" "validate smoke fail: returns 1"
assert_contains "$output" "FILE_RESTORED" "validate smoke fail: file restored from backup"

# --- Test 9: validate returns 0 when no checksums file exists ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES="$test_dir/file_a.sh"
_build_harness "$test_dir/harness_val_nochk.sh"

cat >> "$test_dir/harness_val_nochk.sh" <<'EOF'
# Do NOT call checkpoint first — no checksums file
rm -f "$AUTOMATON_DIR/self_checksums.json"
self_build_validate
rc=$?
echo "EXIT=$rc"
EOF

output=$(bash "$test_dir/harness_val_nochk.sh" 2>&1)
assert_contains "$output" "EXIT=0" "validate no-checksums: returns 0"

# =====================================================================
# Section 3: _self_build_restore
# =====================================================================

# --- Test 10: restore copies backup files back to original locations ---
mkdir -p "$test_dir/proj10"
echo 'original A' > "$test_dir/proj10/fileA.sh"
echo 'original B' > "$test_dir/proj10/fileB.sh"

SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES="$test_dir/proj10/fileA.sh $test_dir/proj10/fileB.sh"
_build_harness "$test_dir/harness_restore.sh"

# Override git
cat >> "$test_dir/harness_restore.sh" <<'EOF'
git() { :; }
EOF

cat >> "$test_dir/harness_restore.sh" <<TESTEOF
# Create checkpoint (makes backups)
self_build_checkpoint

# Modify files
echo 'corrupted A' > "$test_dir/proj10/fileA.sh"
echo 'corrupted B' > "$test_dir/proj10/fileB.sh"

# Restore
_self_build_restore "\$AUTOMATON_DIR/self_backup"

contentA=\$(cat "$test_dir/proj10/fileA.sh")
contentB=\$(cat "$test_dir/proj10/fileB.sh")
echo "A=\$contentA"
echo "B=\$contentB"
TESTEOF

output=$(bash "$test_dir/harness_restore.sh" 2>&1)
assert_contains "$output" "A=original A" "restore: fileA restored to original content"
assert_contains "$output" "B=original B" "restore: fileB restored to original content"

# =====================================================================
# Section 4: _self_build_add_fix_task
# =====================================================================

# --- Test 11: add_fix_task appends to IMPLEMENTATION_PLAN.md ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_fix_plan.sh"

cat >> "$test_dir/harness_fix_plan.sh" <<TESTEOF
# Create a plan file
echo "# Plan" > "$test_dir/IMPLEMENTATION_PLAN.md"

# Override PLAN_FILE to look in the right spot
cd "$test_dir"
_self_build_add_fix_task "syntax error in iteration 3"

content=\$(cat "$test_dir/IMPLEMENTATION_PLAN.md")
echo "CONTENT=\$content"
TESTEOF

output=$(bash "$test_dir/harness_fix_plan.sh" 2>&1)
assert_contains "$output" "Fix: syntax error in iteration 3" "add_fix_task: appends fix task to plan"

# --- Test 12: add_fix_task uses backlog in self-build mode ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_fix_backlog.sh"

# Override ARG_SELF
sed -i 's/ARG_SELF="false"/ARG_SELF="true"/' "$test_dir/harness_fix_backlog.sh"

cat >> "$test_dir/harness_fix_backlog.sh" <<TESTEOF
# Create both plan and backlog
echo "# Plan" > "$test_dir/IMPLEMENTATION_PLAN.md"
echo "# Backlog" > "\$AUTOMATON_DIR/backlog.md"

cd "$test_dir"
_self_build_add_fix_task "smoke test failed"

plan_content=\$(cat "$test_dir/IMPLEMENTATION_PLAN.md")
backlog_content=\$(cat "\$AUTOMATON_DIR/backlog.md")
echo "PLAN=\$plan_content"
echo "BACKLOG=\$backlog_content"
TESTEOF

output=$(bash "$test_dir/harness_fix_backlog.sh" 2>&1)
assert_contains "$output" "BACKLOG=# Backlog" "add_fix_task backlog: appends to backlog"
assert_contains "$output" "Fix: smoke test failed" "add_fix_task backlog: fix task in backlog"

# --- Test 13: add_fix_task no-op when plan file missing ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_fix_noplan.sh"

cat >> "$test_dir/harness_fix_noplan.sh" <<TESTEOF
cd "$test_dir"
rm -f "$test_dir/IMPLEMENTATION_PLAN.md"
_self_build_add_fix_task "should not crash"
echo "EXIT=\$?"
TESTEOF

output=$(bash "$test_dir/harness_fix_noplan.sh" 2>&1)
# Should not crash — just silently skip
assert_not_contains "$output" "FAIL" "add_fix_task no plan: no crash"

# =====================================================================
# Section 5: _self_build_audit_entry
# =====================================================================

# --- Test 14: audit entry writes valid JSON with correct fields ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_audit.sh"

cat >> "$test_dir/harness_audit.sh" <<'EOF'
# Initialize audit log
echo '[]' > "$AUTOMATON_DIR/self_modifications.json"

_self_build_audit_entry "file_a.sh file_b.sh" '{"file":"a","before":"x","after":"y"},' "pass" "skipped"

content=$(cat "$AUTOMATON_DIR/self_modifications.json")
echo "$content"

# Validate fields
echo "VALID_JSON=$(echo "$content" | jq empty 2>&1 && echo 'yes' || echo 'no')"
echo "LENGTH=$(echo "$content" | jq 'length')"
echo "HAS_TIMESTAMP=$(echo "$content" | jq '.[0] | has("timestamp")')"
echo "HAS_ITERATION=$(echo "$content" | jq '.[0] | has("iteration")')"
echo "HAS_PHASE=$(echo "$content" | jq '.[0] | has("phase")')"
echo "HAS_FILES=$(echo "$content" | jq '.[0] | has("files_changed")')"
echo "HAS_SYNTAX=$(echo "$content" | jq '.[0] | has("syntax_check")')"
echo "HAS_SMOKE=$(echo "$content" | jq '.[0] | has("smoke_test")')"
echo "SYNTAX_VAL=$(echo "$content" | jq -r '.[0].syntax_check')"
echo "SMOKE_VAL=$(echo "$content" | jq -r '.[0].smoke_test')"
echo "PHASE_VAL=$(echo "$content" | jq -r '.[0].phase')"
echo "ITER_VAL=$(echo "$content" | jq '.[0].iteration')"
EOF

output=$(bash "$test_dir/harness_audit.sh" 2>&1)
assert_contains "$output" "LENGTH=1" "audit entry: one entry created"
assert_contains "$output" "HAS_TIMESTAMP=true" "audit entry: has timestamp field"
assert_contains "$output" "HAS_ITERATION=true" "audit entry: has iteration field"
assert_contains "$output" "HAS_PHASE=true" "audit entry: has phase field"
assert_contains "$output" "HAS_FILES=true" "audit entry: has files_changed field"
assert_contains "$output" "HAS_SYNTAX=true" "audit entry: has syntax_check field"
assert_contains "$output" "HAS_SMOKE=true" "audit entry: has smoke_test field"
assert_contains "$output" "SYNTAX_VAL=pass" "audit entry: syntax_check = pass"
assert_contains "$output" "SMOKE_VAL=skipped" "audit entry: smoke_test = skipped"
assert_contains "$output" "PHASE_VAL=build" "audit entry: phase = build"
assert_contains "$output" "ITER_VAL=1" "audit entry: iteration = 1"

# --- Test 15: audit appends (does not overwrite) ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_audit_append.sh"

cat >> "$test_dir/harness_audit_append.sh" <<'EOF'
echo '[]' > "$AUTOMATON_DIR/self_modifications.json"

_self_build_audit_entry "first.sh" "" "pass" "pass"
_self_build_audit_entry "second.sh" "" "fail" "skipped"

count=$(jq 'length' "$AUTOMATON_DIR/self_modifications.json")
echo "COUNT=$count"
EOF

output=$(bash "$test_dir/harness_audit_append.sh" 2>&1)
assert_contains "$output" "COUNT=2" "audit append: two entries accumulated"

# =====================================================================
# Section 6: self_build_check_scope
# =====================================================================

# --- Test 16: check_scope is no-op when disabled ---
SELF_BUILD_ENABLED="false"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_scope_disabled.sh"

cat >> "$test_dir/harness_scope_disabled.sh" <<'EOF'
self_build_check_scope
rc=$?
echo "EXIT=$rc"
EOF

output=$(bash "$test_dir/harness_scope_disabled.sh" 2>&1)
assert_contains "$output" "EXIT=0" "check_scope disabled: returns 0"

# --- Test 17: check_scope returns 0 even with warnings (non-blocking) ---
# This function calls git, so we stub git to return controlled output
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
SELF_BUILD_MAX_FILES="2"
SELF_BUILD_MAX_LINES="50"
_build_harness "$test_dir/harness_scope_warn.sh"

# Override git to simulate many files changed
cat >> "$test_dir/harness_scope_warn.sh" <<'GITEOF'
git() {
    if [[ "$1" == "diff" && "$2" == "--name-only" ]]; then
        # Simulate 5 files changed
        printf "a.sh\nb.sh\nc.sh\nd.sh\ne.sh\n"
    elif [[ "$1" == "diff" && "$2" == "--stat" ]]; then
        echo " 5 files changed, 300 insertions(+), 100 deletions(-)"
    else
        return 0
    fi
}
log() {
    echo "LOG: $*"
}
GITEOF

cat >> "$test_dir/harness_scope_warn.sh" <<'EOF'
self_build_check_scope
rc=$?
echo "EXIT=$rc"
EOF

output=$(bash "$test_dir/harness_scope_warn.sh" 2>&1)
assert_contains "$output" "EXIT=0" "check_scope warnings: still returns 0"

# --- Test 18: check_scope function exists in source ---
grep -q '^self_build_check_scope()' "$script_file"
assert_exit_code 0 $? "self_build_check_scope() exists in source"

# =====================================================================
# Section 7: calculate_test_coverage
# =====================================================================

# --- Test 19: coverage with no plan file returns all zeros ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_cov_empty.sh"

cat >> "$test_dir/harness_cov_empty.sh" <<TESTEOF
PLAN_FILE="$test_dir/nonexistent_plan.md"
output=\$(calculate_test_coverage)
echo "\$output"
echo "COVERAGE=\$(echo "\$output" | jq '.coverage_ratio')"
echo "WITH_TESTS=\$(echo "\$output" | jq '.tasks_with_tests')"
echo "WITHOUT_TESTS=\$(echo "\$output" | jq '.tasks_without_tests')"
TESTEOF

output=$(bash "$test_dir/harness_cov_empty.sh" 2>&1)
assert_contains "$output" "COVERAGE=0" "coverage empty: ratio is 0"
assert_contains "$output" "WITH_TESTS=0" "coverage empty: tasks_with_tests is 0"
assert_contains "$output" "WITHOUT_TESTS=0" "coverage empty: tasks_without_tests is 0"

# --- Test 20: coverage counts tasks with and without test annotations ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_cov_plan.sh"

# Create a plan file with mixed annotations
cat > "$test_dir/test_plan.md" <<PLANEOF
# Implementation Plan
- [x] Implement feature A <!-- test: $test_dir/test_a.sh -->
- [ ] Implement feature B <!-- test: $test_dir/test_b_missing.sh -->
- [x] Implement feature C <!-- test: none -->
- [ ] Implement feature D
- [x] Implement feature E <!-- test: $test_dir/test_e.sh -->
PLANEOF

# Create test files that exist
echo '#!/usr/bin/env bash' > "$test_dir/test_a.sh"
echo '#!/usr/bin/env bash' > "$test_dir/test_e.sh"

cat >> "$test_dir/harness_cov_plan.sh" <<TESTEOF
PLAN_FILE="$test_dir/test_plan.md"
output=\$(calculate_test_coverage)
echo "\$output"
echo "WITH=\$(echo "\$output" | jq '.tasks_with_tests')"
echo "WITHOUT=\$(echo "\$output" | jq '.tasks_without_tests')"
echo "EXEMPT=\$(echo "\$output" | jq '.tasks_exempt')"
echo "UNANNOTATED=\$(echo "\$output" | jq '.tasks_unannotated')"
echo "RATIO=\$(echo "\$output" | jq '.coverage_ratio')"
TESTEOF

output=$(bash "$test_dir/harness_cov_plan.sh" 2>&1)
assert_contains "$output" "WITH=2" "coverage plan: 2 tasks with existing test files"
assert_contains "$output" "WITHOUT=1" "coverage plan: 1 task with missing test file"
assert_contains "$output" "EXEMPT=1" "coverage plan: 1 exempt task"
assert_contains "$output" "UNANNOTATED=1" "coverage plan: 1 unannotated task"

# --- Test 21: coverage reads test_results.json ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_cov_results.sh"

cat >> "$test_dir/harness_cov_results.sh" <<TESTEOF
PLAN_FILE="$test_dir/nonexistent_plan.md"
mkdir -p "\$AUTOMATON_DIR"
cat > "\$AUTOMATON_DIR/test_results.json" <<'RESULTSEOF'
[
    {"test": "test_a", "result": "pass"},
    {"test": "test_b", "result": "pass"},
    {"test": "test_c", "result": "fail"},
    {"test": "test_d", "result": "pass"}
]
RESULTSEOF

output=\$(calculate_test_coverage)
echo "\$output"
echo "PASSING=\$(echo "\$output" | jq '.tests_passing')"
echo "FAILING=\$(echo "\$output" | jq '.tests_failing')"
TESTEOF

output=$(bash "$test_dir/harness_cov_results.sh" 2>&1)
assert_contains "$output" "PASSING=3" "coverage results: 3 tests passing"
assert_contains "$output" "FAILING=1" "coverage results: 1 test failing"

# --- Test 22: coverage output is valid JSON ---
SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES=""
_build_harness "$test_dir/harness_cov_json.sh"

cat >> "$test_dir/harness_cov_json.sh" <<TESTEOF
PLAN_FILE="$test_dir/nonexistent.md"
output=\$(calculate_test_coverage)
echo "\$output" | jq empty 2>&1 && echo "VALID_JSON" || echo "INVALID_JSON"
TESTEOF

output=$(bash "$test_dir/harness_cov_json.sh" 2>&1)
assert_contains "$output" "VALID_JSON" "coverage: output is valid JSON"

# =====================================================================
# Section 8: All functions exist in source
# =====================================================================

# --- Test 23: all target functions exist in lifecycle.sh ---
for fn in self_build_checkpoint self_build_validate _self_build_restore \
          _self_build_add_fix_task _self_build_audit_entry self_build_check_scope \
          calculate_test_coverage; do
    grep -q "^${fn}()" "$script_file"
    assert_exit_code 0 $? "$fn() exists in source"
done

# =====================================================================
# Section 9: Integration — checkpoint then validate with syntax failure triggers audit + restore
# =====================================================================

# --- Test 24: end-to-end: checkpoint, break syntax, validate restores and logs audit ---
mkdir -p "$test_dir/proj24"
cat > "$test_dir/proj24/automaton.sh" <<'GOODSCRIPT'
#!/usr/bin/env bash
echo "healthy"
GOODSCRIPT

echo "# Plan" > "$test_dir/proj24/IMPLEMENTATION_PLAN.md"

SELF_BUILD_ENABLED="true"
SELF_BUILD_FILES="$test_dir/proj24/automaton.sh"
SELF_BUILD_REQUIRE_SMOKE="false"
_build_harness "$test_dir/harness_e2e.sh"

# Stub git
cat >> "$test_dir/harness_e2e.sh" <<'EOF'
git() { :; }
EOF

cat >> "$test_dir/harness_e2e.sh" <<TESTEOF
cd "$test_dir/proj24"

# 1. Checkpoint
self_build_checkpoint
echo "CHECKPOINT_OK"

# 2. Break the file
echo 'if [[ bad syntax' > "$test_dir/proj24/automaton.sh"

# 3. Validate — should fail, restore, add fix task, and audit
self_build_validate
rc=\$?
echo "VALIDATE_EXIT=\$rc"

# 4. Verify restoration
if grep -q "healthy" "$test_dir/proj24/automaton.sh"; then
    echo "RESTORED_OK"
else
    echo "NOT_RESTORED"
fi

# 5. Verify audit
if [ -f "\$AUTOMATON_DIR/self_modifications.json" ]; then
    entries=\$(jq 'length' "\$AUTOMATON_DIR/self_modifications.json")
    syntax_result=\$(jq -r '.[0].syntax_check' "\$AUTOMATON_DIR/self_modifications.json")
    echo "AUDIT_ENTRIES=\$entries"
    echo "AUDIT_SYNTAX=\$syntax_result"
else
    echo "AUDIT_FILE_MISSING"
fi

# 6. Verify fix task
if [ -f "$test_dir/proj24/IMPLEMENTATION_PLAN.md" ]; then
    if grep -q "Fix:" "$test_dir/proj24/IMPLEMENTATION_PLAN.md"; then
        echo "FIX_TASK_ADDED"
    else
        echo "NO_FIX_TASK"
    fi
fi
TESTEOF

output=$(bash "$test_dir/harness_e2e.sh" 2>&1)
assert_contains "$output" "CHECKPOINT_OK" "e2e: checkpoint succeeded"
assert_contains "$output" "VALIDATE_EXIT=1" "e2e: validate returns 1 on syntax error"
assert_contains "$output" "RESTORED_OK" "e2e: file restored after syntax failure"
assert_contains "$output" "AUDIT_ENTRIES=1" "e2e: audit entry created"
assert_contains "$output" "AUDIT_SYNTAX=fail" "e2e: audit records syntax_check=fail"
assert_contains "$output" "FIX_TASK_ADDED" "e2e: fix task appended to plan"

test_summary
exit $?
