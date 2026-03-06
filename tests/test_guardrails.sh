#!/usr/bin/env bash
# tests/test_guardrails.sh — Tests for spec-58 design principles & anti-pattern guard rails
# Verifies DESIGN_PRINCIPLES.md, 6 guardrail_check_* functions, and run_guardrails() dispatcher.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

config_file="$SCRIPT_DIR/../automaton.config.json"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_guardrails_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: DESIGN_PRINCIPLES.md exists ---
principles_file="$SCRIPT_DIR/../.automaton/DESIGN_PRINCIPLES.md"
assert_file_exists "$principles_file" "DESIGN_PRINCIPLES.md exists"

# --- Test 2: DESIGN_PRINCIPLES.md documents all 7 principles ---
if [ -f "$principles_file" ]; then
    principles_content=$(cat "$principles_file")
    assert_contains "$principles_content" "Size Ceiling" "Principle 1: Size Ceiling documented"
    assert_contains "$principles_content" "Zero External Dependencies" "Principle 2: Zero External Dependencies documented"
    assert_contains "$principles_content" "Plain Text State" "Principle 3: Plain Text State documented"
    assert_contains "$principles_content" "Loud Failure" "Principle 4: Loud Failure documented"
    assert_contains "$principles_content" "stdout is the UI" "Principle 5: stdout is the UI documented"
    assert_contains "$principles_content" "Claude for Creativity Only" "Principle 6: Claude for Creativity Only documented"
    assert_contains "$principles_content" "No Feature Without Tests" "Principle 7: No Feature Without Tests documented"
fi

# --- Test 3: All 6 guardrail_check_* functions exist ---
grep -q '^guardrail_check_size()' "$script_file"
assert_exit_code 0 $? "guardrail_check_size() exists"

grep -q '^guardrail_check_dependencies()' "$script_file"
assert_exit_code 0 $? "guardrail_check_dependencies() exists"

grep -q '^guardrail_check_silent_errors()' "$script_file"
assert_exit_code 0 $? "guardrail_check_silent_errors() exists"

grep -q '^guardrail_check_state_location()' "$script_file"
assert_exit_code 0 $? "guardrail_check_state_location() exists"

grep -q '^guardrail_check_tui_deps()' "$script_file"
assert_exit_code 0 $? "guardrail_check_tui_deps() exists"

grep -q '^guardrail_check_prompt_logic()' "$script_file"
assert_exit_code 0 $? "guardrail_check_prompt_logic() exists"

# --- Test 4: run_guardrails() dispatcher exists ---
grep -q '^run_guardrails()' "$script_file"
assert_exit_code 0 $? "run_guardrails() exists"

# --- Test 5: guardrails_mode config ---
if [ -f "$config_file" ]; then
    mode_val=$(jq -r '.guardrails_mode // empty' "$config_file")
    if [ -n "$mode_val" ]; then
        echo "PASS: guardrails_mode exists in config (value: $mode_val)"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: guardrails_mode not found in config" >&2
        ((_TEST_FAIL_COUNT++))
    fi
fi

# --- Test 6: Config loading for GUARDRAILS_MODE ---
grep -q 'GUARDRAILS_MODE' "$script_file"
assert_exit_code 0 $? "GUARDRAILS_MODE variable loaded in config"

# --- Test 7: guardrail_check_size detects oversized files ---
# Build a harness that extracts guardrail_check_size and tests it
cat > "$test_dir/harness_size.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
GUARDRAIL_VIOLATIONS=()
GUARDRAILS_SIZE_CEILING=100
PROJECT_ROOT="TESTDIR"

log() { :; }
HARNESS
sed -i "s|TESTDIR|$test_dir|" "$test_dir/harness_size.sh"

# Extract guardrail_check_size from automaton.sh
sed -n '/^guardrail_check_size()/,/^}/p' "$script_file" >> "$test_dir/harness_size.sh"

# Create a test file that exceeds the limit
python3 -c "
for i in range(150):
    print(f'echo line{i}')
" > "$test_dir/automaton.sh"

cat >> "$test_dir/harness_size.sh" <<'TESTCODE'
guardrail_check_size
rc=$?
echo "EXIT=$rc"
echo "VIOLATIONS=${#GUARDRAIL_VIOLATIONS[@]}"
for v in "${GUARDRAIL_VIOLATIONS[@]}"; do
    echo "V=$v"
done
TESTCODE

output=$(bash "$test_dir/harness_size.sh" 2>&1)
assert_contains "$output" "EXIT=1" "guardrail_check_size fails when file exceeds ceiling"
assert_contains "$output" "VIOLATIONS=1" "guardrail_check_size adds a violation"

# --- Test 8: guardrail_check_dependencies detects package managers ---
cat > "$test_dir/harness_deps.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS

sed -n '/^guardrail_check_dependencies()/,/^}/p' "$script_file" >> "$test_dir/harness_deps.sh"

# Create test files with dependency commands
mkdir -p "$test_dir/deps_test"
cat > "$test_dir/deps_test/bad_script.sh" <<'EOF'
#!/usr/bin/env bash
apt-get install -y curl
npm install express
pip install requests
brew install jq
EOF

cat >> "$test_dir/harness_deps.sh" <<TESTCODE
cd "$test_dir/deps_test"
guardrail_check_dependencies
rc=\$?
echo "EXIT=\$rc"
echo "VIOLATIONS=\${#GUARDRAIL_VIOLATIONS[@]}"
TESTCODE

output=$(bash "$test_dir/harness_deps.sh" 2>&1)
assert_contains "$output" "EXIT=1" "guardrail_check_dependencies detects package manager commands"

# --- Test 9: guardrail_check_silent_errors detects suppressed errors ---
cat > "$test_dir/harness_silent.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS

sed -n '/^guardrail_check_silent_errors()/,/^}/p' "$script_file" >> "$test_dir/harness_silent.sh"

mkdir -p "$test_dir/silent_test"
cat > "$test_dir/silent_test/bad_errors.sh" <<'EOF'
#!/usr/bin/env bash
command_that_fails 2>/dev/null
set +e
echo "many lines here"
echo "no restoration"
echo "of set -e"
echo "within 20 lines"
EOF

cat >> "$test_dir/harness_silent.sh" <<TESTCODE
cd "$test_dir/silent_test"
guardrail_check_silent_errors
rc=\$?
echo "EXIT=\$rc"
echo "VIOLATIONS=\${#GUARDRAIL_VIOLATIONS[@]}"
TESTCODE

output=$(bash "$test_dir/harness_silent.sh" 2>&1)
assert_contains "$output" "EXIT=1" "guardrail_check_silent_errors detects suppressed errors"

# --- Test 10: guardrail_check_state_location detects writes outside .automaton ---
cat > "$test_dir/harness_state.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS

sed -n '/^guardrail_check_state_location()/,/^}/p' "$script_file" >> "$test_dir/harness_state.sh"

mkdir -p "$test_dir/state_test"
cat > "$test_dir/state_test/bad_state.sh" <<'EOF'
#!/usr/bin/env bash
echo "data" > /tmp/state.json
echo "more" >> ~/my_state.log
echo "ok" > .automaton/valid.json
echo "ok" > /dev/stdout
EOF

cat >> "$test_dir/harness_state.sh" <<TESTCODE
cd "$test_dir/state_test"
guardrail_check_state_location
rc=\$?
echo "EXIT=\$rc"
echo "VIOLATIONS=\${#GUARDRAIL_VIOLATIONS[@]}"
TESTCODE

output=$(bash "$test_dir/harness_state.sh" 2>&1)
assert_contains "$output" "EXIT=1" "guardrail_check_state_location flags writes outside .automaton"

# --- Test 11: guardrail_check_tui_deps detects TUI libraries ---
cat > "$test_dir/harness_tui.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS

sed -n '/^guardrail_check_tui_deps()/,/^}/p' "$script_file" >> "$test_dir/harness_tui.sh"

mkdir -p "$test_dir/tui_test"
cat > "$test_dir/tui_test/bad_tui.sh" <<'EOF'
#!/usr/bin/env bash
dialog --yesno "Proceed?" 10 40
whiptail --msgbox "Hello" 10 40
EOF

cat >> "$test_dir/harness_tui.sh" <<TESTCODE
cd "$test_dir/tui_test"
guardrail_check_tui_deps
rc=\$?
echo "EXIT=\$rc"
echo "VIOLATIONS=\${#GUARDRAIL_VIOLATIONS[@]}"
TESTCODE

output=$(bash "$test_dir/harness_tui.sh" 2>&1)
assert_contains "$output" "EXIT=1" "guardrail_check_tui_deps detects TUI/GUI libraries"

# --- Test 12: guardrail_check_prompt_logic detects control flow in prompts ---
cat > "$test_dir/harness_prompt.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS

sed -n '/^guardrail_check_prompt_logic()/,/^}/p' "$script_file" >> "$test_dir/harness_prompt.sh"

mkdir -p "$test_dir/prompt_test"
cat > "$test_dir/prompt_test/bad_prompt.sh" <<'PROMPTEOF'
#!/usr/bin/env bash
prompt=$(cat <<'EOF'
You are an assistant.
if the user asks about X then respond with Y
for each item in the list do the following
while there are remaining items loop through them
EOF
)
PROMPTEOF

cat >> "$test_dir/harness_prompt.sh" <<TESTCODE
cd "$test_dir/prompt_test"
guardrail_check_prompt_logic
rc=\$?
echo "EXIT=\$rc"
echo "VIOLATIONS=\${#GUARDRAIL_VIOLATIONS[@]}"
TESTCODE

output=$(bash "$test_dir/harness_prompt.sh" 2>&1)
assert_contains "$output" "EXIT=1" "guardrail_check_prompt_logic flags control flow in heredoc prompts"

# --- Test 13: run_guardrails produces violations report ---
cat > "$test_dir/harness_dispatcher.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="TESTDIR/.automaton_disp"
mkdir -p "$AUTOMATON_DIR"
GUARDRAILS_MODE="warn"
GUARDRAILS_SIZE_CEILING=100
PROJECT_ROOT="TESTDIR"
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS
sed -i "s|TESTDIR|$test_dir|" "$test_dir/harness_dispatcher.sh"

# Create a tiny automaton.sh in project root to pass size check
python3 -c "
for i in range(50):
    print(f'echo line{i}')
" > "$test_dir/automaton.sh"

# Create clean project files (no violations)
mkdir -p "$test_dir/clean_project"
cat > "$test_dir/clean_project/script.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "clean code"
EOF

# Extract all guardrail functions and dispatcher
for fn in guardrail_check_size guardrail_check_dependencies guardrail_check_silent_errors guardrail_check_state_location guardrail_check_tui_deps guardrail_check_prompt_logic run_guardrails; do
    sed -n "/^${fn}()/,/^}/p" "$script_file" >> "$test_dir/harness_dispatcher.sh"
done

cat >> "$test_dir/harness_dispatcher.sh" <<TESTCODE
cd "$test_dir/clean_project"
run_guardrails
rc=\$?
echo "EXIT=\$rc"
if [ -f "\$AUTOMATON_DIR/principle-violations.md" ]; then
    echo "REPORT_EXISTS"
    grep -q "Principle Violations Report" "\$AUTOMATON_DIR/principle-violations.md" && echo "HAS_TITLE"
else
    echo "NO_REPORT"
fi
TESTCODE

output=$(bash "$test_dir/harness_dispatcher.sh" 2>&1)
# Clean project should pass
assert_contains "$output" "EXIT=0" "run_guardrails passes on clean project"
# Report should still be generated (with all PASS entries)
assert_contains "$output" "REPORT_EXISTS" "violations report is generated"
assert_contains "$output" "HAS_TITLE" "violations report has title"

# --- Test 14: Each guardrail function is under 30 lines ---
for fn in guardrail_check_size guardrail_check_dependencies guardrail_check_silent_errors guardrail_check_state_location guardrail_check_tui_deps guardrail_check_prompt_logic; do
    func_lines=$(sed -n "/^${fn}()/,/^}/p" "$script_file" | wc -l)
    if [ "$func_lines" -le 30 ]; then
        echo "PASS: $fn is $func_lines lines (within 30-line limit)"
        ((_TEST_PASS_COUNT++))
    else
        echo "FAIL: $fn is $func_lines lines (exceeds 30-line limit)" >&2
        ((_TEST_FAIL_COUNT++))
    fi
done

# --- Test 15: run_guardrails dispatcher is under 40 lines ---
func_lines=$(sed -n '/^run_guardrails()/,/^}/p' "$script_file" | wc -l)
if [ "$func_lines" -le 40 ]; then
    echo "PASS: run_guardrails is $func_lines lines (within 40-line limit)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: run_guardrails is $func_lines lines (exceeds 40-line limit)" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 16: Zero API calls (no claude invocations) ---
for fn in guardrail_check_size guardrail_check_dependencies guardrail_check_silent_errors guardrail_check_state_location guardrail_check_tui_deps guardrail_check_prompt_logic run_guardrails; do
    func_body=$(sed -n "/^${fn}()/,/^}/p" "$script_file")
    if echo "$func_body" | grep -qE 'claude\s+-p|claude\s+--agent|run_agent'; then
        echo "FAIL: $fn contains API calls (must be zero-API-call)" >&2
        ((_TEST_FAIL_COUNT++))
    else
        echo "PASS: $fn has zero API calls"
        ((_TEST_PASS_COUNT++))
    fi
done

# --- Test 17: guardrails_mode block mode exits non-zero on violation ---
cat > "$test_dir/harness_block.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="TESTDIR/.automaton_block"
mkdir -p "$AUTOMATON_DIR"
GUARDRAILS_MODE="block"
GUARDRAILS_SIZE_CEILING=10
PROJECT_ROOT="TESTDIR"
GUARDRAIL_VIOLATIONS=()

log() { :; }
HARNESS
sed -i "s|TESTDIR|$test_dir|" "$test_dir/harness_block.sh"

for fn in guardrail_check_size guardrail_check_dependencies guardrail_check_silent_errors guardrail_check_state_location guardrail_check_tui_deps guardrail_check_prompt_logic run_guardrails; do
    sed -n "/^${fn}()/,/^}/p" "$script_file" >> "$test_dir/harness_block.sh"
done

cat >> "$test_dir/harness_block.sh" <<TESTCODE
cd "$test_dir/clean_project"
run_guardrails
rc=\$?
echo "EXIT=\$rc"
TESTCODE

output=$(bash "$test_dir/harness_block.sh" 2>&1)
# The automaton.sh in test_dir is 50 lines, ceiling is 10 — should fail
assert_contains "$output" "EXIT=1" "run_guardrails in block mode returns 1 on violation"

test_summary
exit $?
