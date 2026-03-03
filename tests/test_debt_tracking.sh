#!/usr/bin/env bash
# tests/test_debt_tracking.sh — Tests for spec-56 typed technical debt tracking
# Verifies _scan_technical_debt() and _generate_debt_summary() functions.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"
config_file="$SCRIPT_DIR/../automaton.config.json"
TMPDIR="${TMPDIR:-/tmp}"
test_dir="$TMPDIR/test_debt_tracking_$$"
mkdir -p "$test_dir"
trap 'rm -rf "$test_dir"' EXIT

# --- Test 1: _scan_technical_debt function exists ---
grep -q '^_scan_technical_debt()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_scan_technical_debt() function exists in automaton.sh"

# --- Test 2: _generate_debt_summary function exists ---
grep -q '^_generate_debt_summary()' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "_generate_debt_summary() function exists in automaton.sh"

# --- Test 3: debt_tracking config section exists ---
if [ -f "$config_file" ]; then
    jq -e '.debt_tracking' "$config_file" >/dev/null 2>&1
    rc=$?
    assert_exit_code 0 "$rc" "debt_tracking section exists in config"

    enabled_val=$(jq -r '.debt_tracking.enabled' "$config_file")
    assert_equals "true" "$enabled_val" "debt_tracking.enabled defaults to true"

    threshold_val=$(jq -r '.debt_tracking.threshold' "$config_file")
    assert_equals "20" "$threshold_val" "debt_tracking.threshold defaults to 20"

    markers_count=$(jq '.debt_tracking.markers | length' "$config_file")
    assert_equals "6" "$markers_count" "debt_tracking.markers has 6 entries"
else
    echo "FAIL: automaton.config.json not found" >&2
    ((_TEST_FAIL_COUNT++))
fi

# --- Test 4: Config loading variables exist ---
grep -q 'DEBT_TRACKING_ENABLED' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "DEBT_TRACKING_ENABLED config variable exists"

grep -q 'DEBT_TRACKING_THRESHOLD' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "DEBT_TRACKING_THRESHOLD config variable exists"

grep -q 'DEBT_TRACKING_MARKERS' "$script_file"
rc=$?
assert_exit_code 0 "$rc" "DEBT_TRACKING_MARKERS config variable exists"

# --- Test 5: Extract and test _scan_technical_debt ---
# Set up a fake git repo with files containing debt markers
mkdir -p "$test_dir/repo/.automaton"
cd "$test_dir/repo"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create initial commit
echo "# project" > README.md
git add README.md
git commit -q -m "init"

# Save starting SHA
start_sha=$(git rev-parse HEAD)

# Create files with various debt markers
cat > src_file.sh <<'EOF'
#!/usr/bin/env bash
# TODO: hardcoded timeout, should read from config
TIMEOUT=30

# FIXME: error handling missing for network failures
fetch_data() {
    curl -s http://example.com
}

# HACK: slow O(n^2) lookup, optimize later
for i in "${arr[@]}"; do
    for j in "${arr[@]}"; do
        echo "$i $j"
    done
done

# WORKAROUND: test coverage missing for edge cases
validate_input() {
    echo "ok"
}

# TEMPORARY: cleanup this function later
do_thing() {
    echo "temporary"
}

# DEBT: retry logic needed for error handling
connect() {
    echo "connect"
}
EOF

git add src_file.sh
git commit -q -m "add source with debt markers"

# Build harness that extracts _scan_technical_debt
cat > "$test_dir/harness_scan.sh" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
cd "$test_dir/repo"
AUTOMATON_DIR="$test_dir/repo/.automaton"
phase_iteration=3

# Debt tracking config
DEBT_TRACKING_ENABLED="true"
DEBT_TRACKING_THRESHOLD=20
DEBT_TRACKING_MARKERS="TODO FIXME HACK DEBT WORKAROUND TEMPORARY"

log() { :; }
HARNESS

# Extract _scan_technical_debt and its helper from automaton.sh
sed -n '/^_classify_debt_type()/,/^}/p' "$script_file" >> "$test_dir/harness_scan.sh"
sed -n '/^_scan_technical_debt()/,/^}/p' "$script_file" >> "$test_dir/harness_scan.sh"

cat >> "$test_dir/harness_scan.sh" <<TESTCODE
_scan_technical_debt "$start_sha"

# Check results
if [ -f "$test_dir/repo/.automaton/debt-ledger.jsonl" ]; then
    echo "LEDGER_EXISTS"
    line_count=\$(wc -l < "$test_dir/repo/.automaton/debt-ledger.jsonl")
    echo "ENTRIES=\$line_count"
    # Check first line is valid JSON
    head -1 "$test_dir/repo/.automaton/debt-ledger.jsonl" | jq -e '.type' >/dev/null 2>&1 && echo "VALID_JSON"
    # Check all required fields exist in first entry
    head -1 "$test_dir/repo/.automaton/debt-ledger.jsonl" | jq -e '.file, .line, .marker, .marker_text, .iteration, .timestamp, .type' >/dev/null 2>&1 && echo "ALL_FIELDS"
    # Check classifications
    grep -c '"error_handling"' "$test_dir/repo/.automaton/debt-ledger.jsonl" | xargs -I{} echo "ERROR_HANDLING={}"
    grep -c '"hardcoded"' "$test_dir/repo/.automaton/debt-ledger.jsonl" | xargs -I{} echo "HARDCODED={}"
    grep -c '"performance"' "$test_dir/repo/.automaton/debt-ledger.jsonl" | xargs -I{} echo "PERFORMANCE={}"
    grep -c '"test_coverage"' "$test_dir/repo/.automaton/debt-ledger.jsonl" | xargs -I{} echo "TEST_COVERAGE={}"
    grep -c '"cleanup"' "$test_dir/repo/.automaton/debt-ledger.jsonl" | xargs -I{} echo "CLEANUP={}"
else
    echo "NO_LEDGER"
fi
TESTCODE

output=$(bash "$test_dir/harness_scan.sh" 2>&1)
assert_contains "$output" "LEDGER_EXISTS" "debt-ledger.jsonl is created"
assert_contains "$output" "VALID_JSON" "ledger entries are valid JSON"
assert_contains "$output" "ALL_FIELDS" "ledger entries have all required fields"
# We should find at least 7 markers: TODO, FIXME, HACK, WORKAROUND, TEMPORARY, DEBT, plus the second DEBT line
# Exact counts depend on classification logic
assert_contains "$output" "ENTRIES=6" "6 debt markers found in test file"

# --- Test 6: _generate_debt_summary ---
cat > "$test_dir/harness_summary.sh" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$test_dir/repo/.automaton"
DEBT_TRACKING_ENABLED="true"
DEBT_TRACKING_THRESHOLD=20
log() { :; }
HARNESS

sed -n '/^_generate_debt_summary()/,/^}/p' "$script_file" >> "$test_dir/harness_summary.sh"

cat >> "$test_dir/harness_summary.sh" <<'TESTCODE'
_generate_debt_summary
if [ -f "$AUTOMATON_DIR/debt-summary.md" ]; then
    echo "SUMMARY_EXISTS"
    grep -q "Technical Debt Summary" "$AUTOMATON_DIR/debt-summary.md" && echo "HAS_TITLE"
    grep -q "By Type" "$AUTOMATON_DIR/debt-summary.md" && echo "HAS_TYPE_TABLE"
    grep -q "Top Files" "$AUTOMATON_DIR/debt-summary.md" && echo "HAS_FILE_TABLE"
else
    echo "NO_SUMMARY"
fi
TESTCODE

output=$(bash "$test_dir/harness_summary.sh" 2>&1)
assert_contains "$output" "SUMMARY_EXISTS" "debt-summary.md is generated"
assert_contains "$output" "HAS_TITLE" "summary has title"
assert_contains "$output" "HAS_TYPE_TABLE" "summary has by-type table"
assert_contains "$output" "HAS_FILE_TABLE" "summary has top-files table"

# --- Test 7: Disabled debt tracking is a no-op ---
cat > "$test_dir/harness_disabled.sh" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
cd "$test_dir/repo"
AUTOMATON_DIR="$test_dir/repo/.automaton_disabled"
mkdir -p "\$AUTOMATON_DIR"
phase_iteration=1
DEBT_TRACKING_ENABLED="false"
DEBT_TRACKING_THRESHOLD=20
DEBT_TRACKING_MARKERS="TODO FIXME HACK DEBT WORKAROUND TEMPORARY"
log() { :; }
HARNESS

sed -n '/^_classify_debt_type()/,/^}/p' "$script_file" >> "$test_dir/harness_disabled.sh"
sed -n '/^_scan_technical_debt()/,/^}/p' "$script_file" >> "$test_dir/harness_disabled.sh"

cat >> "$test_dir/harness_disabled.sh" <<TESTCODE
_scan_technical_debt "$start_sha"
if [ -f "\$AUTOMATON_DIR/debt-ledger.jsonl" ]; then
    echo "LEDGER_CREATED"
else
    echo "NO_LEDGER"
fi
TESTCODE

output=$(bash "$test_dir/harness_disabled.sh" 2>&1)
assert_contains "$output" "NO_LEDGER" "_scan_technical_debt is no-op when disabled"

# --- Test 8: Line count checks ---
func_lines=$(sed -n '/^_scan_technical_debt()/,/^}/p' "$script_file" | wc -l)
if [ "$func_lines" -le 70 ]; then
    echo "PASS: _scan_technical_debt is $func_lines lines (within 70-line limit)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _scan_technical_debt is $func_lines lines (exceeds 70-line limit)" >&2
    ((_TEST_FAIL_COUNT++))
fi

func_lines=$(sed -n '/^_generate_debt_summary()/,/^}/p' "$script_file" | wc -l)
if [ "$func_lines" -le 40 ]; then
    echo "PASS: _generate_debt_summary is $func_lines lines (within 40-line limit)"
    ((_TEST_PASS_COUNT++))
else
    echo "FAIL: _generate_debt_summary is $func_lines lines (exceeds 40-line limit)" >&2
    ((_TEST_FAIL_COUNT++))
fi

test_summary
exit $?
