#!/usr/bin/env bash
# tests/test_safety_guard_hook.sh — Tests for spec-45 §5 evolution safety guard hook
# Verifies that .claude/hooks/evolution-safety-guard.sh exists with the correct
# structure: branch isolation, constitutional compliance, and scope limits.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

hook_file="$SCRIPT_DIR/../.claude/hooks/evolution-safety-guard.sh"

# --- Test 1: Hook file exists ---
assert_file_exists "$hook_file" "evolution-safety-guard.sh hook file exists"

# --- Test 2: Hook file is executable ---
if [ -x "$hook_file" ]; then
    echo "PASS: evolution-safety-guard.sh is executable"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: evolution-safety-guard.sh should be executable" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 3: Has proper shebang ---
head_line=$(head -1 "$hook_file")
if [[ "$head_line" == "#!/usr/bin/env bash" ]]; then
    echo "PASS: Has proper bash shebang"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should have #!/usr/bin/env bash shebang (got: $head_line)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Checks AUTOMATON_EVOLVE environment variable ---
grep_result=$(grep -c 'AUTOMATON_EVOLVE' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Checks AUTOMATON_EVOLVE environment variable"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should check AUTOMATON_EVOLVE environment variable" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 5: Exits cleanly when not in evolution mode ---
grep_result=$(grep -c 'exit 0' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Has exit 0 for non-evolution mode bypass"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should exit 0 when not in evolution mode" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 6: Checks branch isolation with automaton/evolve- pattern ---
grep_result=$(grep -c 'automaton/evolve-' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Checks for automaton/evolve- branch pattern"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should check for automaton/evolve- branch pattern" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 7: Uses git rev-parse for branch detection ---
grep_result=$(grep -c 'git rev-parse --abbrev-ref HEAD' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Uses git rev-parse --abbrev-ref HEAD for branch detection"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should use git rev-parse --abbrev-ref HEAD" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 8: Reads protected_functions from automaton.config.json ---
grep_result=$(grep -c 'protected_functions' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Reads protected_functions from config"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should read protected_functions from automaton.config.json" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: Checks staged diff for protected function modifications ---
grep_result=$(grep -c 'git diff --cached' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Checks git diff --cached for staged changes"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should check git diff --cached for staged changes" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 10: Protected function check is warning-only (no exit on match) ---
# The protected function block should emit a warning but NOT exit 1/2
grep_result=$(grep -c 'SAFETY WARNING.*[Pp]rotected function' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Protected function check emits SAFETY WARNING"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should emit SAFETY WARNING for protected function modifications" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 11: Checks scope limits (file count) ---
grep_result=$(grep -c 'max_files_per_iteration' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Checks max_files_per_iteration scope limit"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should check max_files_per_iteration for scope limits" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 12: Blocks when scope limit exceeded ---
grep_result=$(grep -c 'SAFETY VIOLATION.*files changed' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Emits SAFETY VIOLATION when file count exceeds limit"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should emit SAFETY VIOLATION when file count exceeds limit" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 13: Blocks when on non-evolution branch ---
grep_result=$(grep -c 'SAFETY VIOLATION.*non-evolution branch' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Emits SAFETY VIOLATION for non-evolution branch commits"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should emit SAFETY VIOLATION for non-evolution branch" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 14: Reads JSON from stdin (Claude Code PreToolUse input) ---
grep_result=$(grep -c 'tool_input' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Reads tool_input from stdin JSON"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should read tool_input from stdin JSON" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 15: Only intercepts git commit commands ---
grep_result=$(grep -c 'git.*commit' "$hook_file" || true)
if [ "$grep_result" -ge 1 ]; then
    echo "PASS: Specifically targets git commit commands"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should specifically target git commit commands" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: Uses exit 2 for blocking (Claude Code PreToolUse convention) ---
grep_result=$(grep -c 'exit 2' "$hook_file" || true)
if [ "$grep_result" -ge 2 ]; then
    echo "PASS: Uses exit 2 for blocking violations (PreToolUse convention)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: Should use exit 2 for blocking violations (need at least 2: branch + scope)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
