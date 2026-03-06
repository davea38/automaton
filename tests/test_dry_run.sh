#!/usr/bin/env bash
# tests/test_dry_run.sh — Integration test for --dry-run smoke test
# Validates that automaton.sh --dry-run loads config, runs gates, and exits 0.
# This was previously broken due to ((_i++)) returning falsy under set -e.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_dry_run_$$"
mkdir -p "$test_dir/.automaton" "$test_dir/specs"
trap 'rm -rf "$test_dir"' EXIT

# Use the project's own config as a complete, valid reference
cp "$_PROJECT_DIR/automaton.config.json" "$test_dir/automaton.config.json"

cat > "$test_dir/PRD.md" << 'EOF'
# Test PRD
This is a test product requirements document.
EOF

cat > "$test_dir/AGENTS.md" << 'EOF'
# Test Project Agents
Agent definitions for testing.
EOF

cat > "$test_dir/specs/spec-01-test.md" << 'EOF'
# Spec 01: Test Spec
Test specification.
EOF

# Initialize git repo for dry-run (it reads git branch)
cd "$test_dir"
git init -q
git add -A
git commit -q -m "init" 2>/dev/null || true

# --- Test 1: dry-run exits 0 ---
output=$(bash "$_PROJECT_DIR/automaton.sh" --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "dry-run exits 0"

# --- Test 2: dry-run shows banner ---
echo "$output" | grep -q 'automaton'
assert_exit_code 0 $? "dry-run shows automaton banner"

# --- Test 3: dry-run shows Gate 1 ---
echo "$output" | grep -q 'Gate 1'
assert_exit_code 0 $? "dry-run runs Gate 1"

# --- Test 4: dry-run shows resolved settings ---
echo "$output" | grep -q 'Resolved settings'
assert_exit_code 0 $? "dry-run shows resolved settings"

# --- Test 5: dry-run shows model config ---
echo "$output" | grep -q 'research:'
assert_exit_code 0 $? "dry-run shows model configuration"

# --- Test 6: dry-run shows budget config ---
echo "$output" | grep -q 'Budget\|budget\|max tokens'
assert_exit_code 0 $? "dry-run shows budget configuration"

# --- Test 7: dry-run shows phase sequence ---
echo "$output" | grep -q 'Phase sequence'
assert_exit_code 0 $? "dry-run shows phase sequence"

# --- Test 8: dry-run shows completion message ---
echo "$output" | grep -q 'Dry run complete'
assert_exit_code 0 $? "dry-run shows completion message"

# --- Test 9: dry-run shows no agents invoked ---
echo "$output" | grep -q 'No agents were invoked'
assert_exit_code 0 $? "dry-run confirms no agents invoked"

# --- Test 10: dry-run with --skip-research ---
output=$(bash "$_PROJECT_DIR/automaton.sh" --dry-run --skip-research 2>&1)
rc=$?
assert_exit_code 0 "$rc" "dry-run with --skip-research exits 0"
echo "$output" | grep -q 'research skipped'
assert_exit_code 0 $? "dry-run shows research skipped"

# --- Test 11: dry-run without PRD fails Gate 1 gracefully ---
rm "$test_dir/PRD.md"
output=$(bash "$_PROJECT_DIR/automaton.sh" --dry-run 2>&1)
rc=$?
assert_exit_code 0 "$rc" "dry-run exits 0 even when Gate 1 fails"
echo "$output" | grep -q 'FAIL'
assert_exit_code 0 $? "dry-run reports Gate 1 failure"

test_summary
