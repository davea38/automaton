#!/usr/bin/env bash
# tests/test_complexity.sh — Tests for spec-51 complexity-based execution routing
# Verifies assess_complexity(), apply_complexity_routing(), CLI override,
# fallback on failure, and state file creation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_complexity_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# Extract assess_complexity and apply_complexity_routing from automaton.sh
_extract_functions() {
    cat > "$test_dir/harness.sh" <<'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
log() { :; }
AUTOMATON_DIR="$TEST_AUTOMATON_DIR"
FLAG_SKIP_RESEARCH="false"
FLAG_SKIP_REVIEW="false"
FLAG_BLIND_VALIDATION="false"
FLAG_STEELMAN_CRITIQUE="false"
MODEL_BUILDING="sonnet"
EXEC_MAX_ITER_REVIEW=2
QA_MAX_ITERATIONS=5
ARG_COMPLEXITY=""
# Stub claude CLI — controlled by TEST_CLAUDE_RESPONSE
claude() {
    if [ "${TEST_CLAUDE_FAIL:-false}" = "true" ]; then
        return 1
    fi
    echo "${TEST_CLAUDE_RESPONSE:-{\"tier\":\"MODERATE\",\"rationale\":\"Standard task\"}}"
}
export -f claude
HARNESS
    sed -n '/^assess_complexity()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
    sed -n '/^apply_complexity_routing()/,/^}/p' "$script_file" >> "$test_dir/harness.sh"
}
_extract_functions

# Helper to set up test environment
_setup_env() {
    local env_dir
    env_dir=$(mktemp -d "$test_dir/env_XXXXXX")
    mkdir -p "$env_dir"
    echo "$env_dir"
}

# --- Test 1: assess_complexity writes complexity.json ---
env_dir=$(_setup_env)
output=$(TEST_AUTOMATON_DIR="$env_dir" TEST_CLAUDE_RESPONSE='{"tier":"SIMPLE","rationale":"Typo fix in README"}' \
    bash -c "source '$test_dir/harness.sh'; assess_complexity 'Fix typo in README'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "assess_complexity exits 0 on success"
assert_file_exists "$env_dir/complexity.json" "complexity.json is created"
tier=$(jq -r '.tier' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "SIMPLE" "$tier" "tier is SIMPLE from claude response"
rationale=$(jq -r '.rationale' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "Typo fix in README" "$rationale" "rationale captured from response"
override=$(jq -r '.override' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "false" "$override" "override is false for assessed complexity"

# --- Test 2: assess_complexity defaults to MODERATE on failure ---
env_dir=$(_setup_env)
output=$(TEST_AUTOMATON_DIR="$env_dir" TEST_CLAUDE_FAIL="true" \
    bash -c "source '$test_dir/harness.sh'; assess_complexity 'Some task'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "assess_complexity exits 0 even on failure (fallback)"
tier=$(jq -r '.tier' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "MODERATE" "$tier" "tier defaults to MODERATE on failure"

# --- Test 3: assess_complexity defaults to MODERATE on invalid JSON ---
env_dir=$(_setup_env)
output=$(TEST_AUTOMATON_DIR="$env_dir" TEST_CLAUDE_RESPONSE="not valid json" \
    bash -c "source '$test_dir/harness.sh'; assess_complexity 'Some task'" 2>&1)
rc=$?
tier=$(jq -r '.tier' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "MODERATE" "$tier" "tier defaults to MODERATE on invalid JSON"

# --- Test 4: apply_complexity_routing for SIMPLE ---
env_dir=$(_setup_env)
cat > "$env_dir/complexity.json" <<'EOF'
{"tier":"SIMPLE","rationale":"Simple change","assessed_at":"2026-03-03T00:00:00Z","override":false}
EOF
output=$(TEST_AUTOMATON_DIR="$env_dir" \
    bash -c "source '$test_dir/harness.sh'; apply_complexity_routing; echo \"SKIP_RESEARCH=\$FLAG_SKIP_RESEARCH MODEL=\$MODEL_BUILDING REVIEW=\$EXEC_MAX_ITER_REVIEW BLIND=\$FLAG_BLIND_VALIDATION STEELMAN=\$FLAG_STEELMAN_CRITIQUE QA=\$QA_MAX_ITERATIONS\"" 2>&1)
assert_contains "$output" "SKIP_RESEARCH=true" "SIMPLE skips research"
assert_contains "$output" "MODEL=sonnet" "SIMPLE uses sonnet for build"
assert_contains "$output" "REVIEW=1" "SIMPLE caps review at 1"
assert_contains "$output" "BLIND=false" "SIMPLE disables blind validation"
assert_contains "$output" "STEELMAN=false" "SIMPLE disables steelman"

# --- Test 5: apply_complexity_routing for MODERATE ---
env_dir=$(_setup_env)
cat > "$env_dir/complexity.json" <<'EOF'
{"tier":"MODERATE","rationale":"Standard task","assessed_at":"2026-03-03T00:00:00Z","override":false}
EOF
output=$(TEST_AUTOMATON_DIR="$env_dir" \
    bash -c "source '$test_dir/harness.sh'; apply_complexity_routing; echo \"SKIP_RESEARCH=\$FLAG_SKIP_RESEARCH MODEL=\$MODEL_BUILDING REVIEW=\$EXEC_MAX_ITER_REVIEW BLIND=\$FLAG_BLIND_VALIDATION QA=\$QA_MAX_ITERATIONS\"" 2>&1)
assert_contains "$output" "SKIP_RESEARCH=false" "MODERATE runs research"
assert_contains "$output" "MODEL=sonnet" "MODERATE uses sonnet for build"
assert_contains "$output" "REVIEW=2" "MODERATE allows 2 review iterations"
assert_contains "$output" "BLIND=false" "MODERATE skips blind validation"

# --- Test 6: apply_complexity_routing for COMPLEX ---
env_dir=$(_setup_env)
cat > "$env_dir/complexity.json" <<'EOF'
{"tier":"COMPLEX","rationale":"Multi-file architecture change","assessed_at":"2026-03-03T00:00:00Z","override":false}
EOF
output=$(TEST_AUTOMATON_DIR="$env_dir" \
    bash -c "source '$test_dir/harness.sh'; apply_complexity_routing; echo \"SKIP_RESEARCH=\$FLAG_SKIP_RESEARCH MODEL=\$MODEL_BUILDING REVIEW=\$EXEC_MAX_ITER_REVIEW BLIND=\$FLAG_BLIND_VALIDATION STEELMAN=\$FLAG_STEELMAN_CRITIQUE QA=\$QA_MAX_ITERATIONS\"" 2>&1)
assert_contains "$output" "SKIP_RESEARCH=false" "COMPLEX runs research"
assert_contains "$output" "MODEL=opus" "COMPLEX uses opus for build"
assert_contains "$output" "REVIEW=4" "COMPLEX allows 4 review iterations"
assert_contains "$output" "BLIND=true" "COMPLEX enables blind validation"
assert_contains "$output" "STEELMAN=true" "COMPLEX enables steelman"

# --- Test 7: CLI override writes complexity.json with override=true ---
env_dir=$(_setup_env)
output=$(TEST_AUTOMATON_DIR="$env_dir" ARG_COMPLEXITY="simple" \
    bash -c "source '$test_dir/harness.sh'; ARG_COMPLEXITY='simple'; assess_complexity 'Anything'" 2>&1)
rc=$?
assert_exit_code 0 "$rc" "CLI override exits 0"
tier=$(jq -r '.tier' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "SIMPLE" "$tier" "CLI override sets tier to SIMPLE"
override=$(jq -r '.override' "$env_dir/complexity.json" 2>/dev/null)
assert_equals "true" "$override" "CLI override sets override=true"

# --- Test 8: complexity.json has assessed_at timestamp ---
env_dir=$(_setup_env)
output=$(TEST_AUTOMATON_DIR="$env_dir" TEST_CLAUDE_RESPONSE='{"tier":"COMPLEX","rationale":"Big change"}' \
    bash -c "source '$test_dir/harness.sh'; assess_complexity 'Redesign the auth system'" 2>&1)
ts=$(jq -r '.assessed_at' "$env_dir/complexity.json" 2>/dev/null)
# Timestamp should match ISO 8601 format
if echo "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    echo "PASS: assessed_at has ISO 8601 format"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: assessed_at is not ISO 8601 (got '$ts')" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 9: apply_complexity_routing with missing complexity.json is no-op ---
env_dir=$(_setup_env)
output=$(TEST_AUTOMATON_DIR="$env_dir" \
    bash -c "source '$test_dir/harness.sh'; apply_complexity_routing; echo \"MODEL=\$MODEL_BUILDING REVIEW=\$EXEC_MAX_ITER_REVIEW\"" 2>&1)
assert_contains "$output" "MODEL=sonnet" "missing complexity.json keeps default model"
assert_contains "$output" "REVIEW=2" "missing complexity.json keeps default review iterations"

test_summary
