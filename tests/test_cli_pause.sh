#!/usr/bin/env bash
# tests/test_cli_pause.sh — Tests for spec-44 §44.3 _cli_pause()
# Verifies that _cli_pause() writes the pause flag file with correct content,
# displays confirmation, and handles edge cases.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# ============================================================
# Function existence
# ============================================================

# --- Test 1: _cli_pause function is defined ---
grep_result=$(grep -c '^_cli_pause()' "$script_file" || true)
assert_equals "1" "$grep_result" "_cli_pause() function is defined"

# ============================================================
# Integration tests with temp directory
# ============================================================

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

EVOL_DIR="$TEST_DIR/evolution"
mkdir -p "$EVOL_DIR"

# Build a wrapper that sources the _cli_pause function
cat > "$TEST_DIR/run_pause.sh" << WRAPPER
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$TEST_DIR"

# Minimal log function
log() { echo "[\$1] \$2"; }

# Extract _cli_pause from automaton.sh
eval "\$(sed -n '/^_cli_pause()/,/^}/p' '$script_file')"

_cli_pause "\$@"
WRAPPER
chmod +x "$TEST_DIR/run_pause.sh"

# --- Test 2: _cli_pause creates the pause flag file ---
output=$(bash "$TEST_DIR/run_pause.sh" 2>&1) || true
assert_file_exists "$EVOL_DIR/pause" "Pause flag file created"

# --- Test 3: Pause flag file contains paused_at ---
pause_content=$(cat "$EVOL_DIR/pause")
assert_contains "$pause_content" "paused_at=" "Pause file contains paused_at"

# --- Test 4: Pause flag file contains paused_by=human ---
assert_contains "$pause_content" "paused_by=human" "Pause file contains paused_by=human"

# --- Test 5: Output shows confirmation message ---
assert_contains "$output" "pause" "Output mentions pause"

# --- Test 6: Output mentions resume instructions ---
assert_contains "$output" "resume" "Output mentions resume"

# --- Test 7: Running pause again overwrites the file (idempotent) ---
rm -f "$EVOL_DIR/pause"
mkdir -p "$EVOL_DIR"
output2=$(bash "$TEST_DIR/run_pause.sh" 2>&1) || true
assert_file_exists "$EVOL_DIR/pause" "Pause flag file created on second run"

# --- Test 8: Evolution directory is created if missing ---
rm -rf "$EVOL_DIR"
output3=$(bash "$TEST_DIR/run_pause.sh" 2>&1) || true
assert_file_exists "$EVOL_DIR/pause" "Pause flag file created even when evolution dir missing"

# --- Test 9: paused_at has ISO 8601 format ---
paused_at=$(grep 'paused_at=' "$EVOL_DIR/pause" | cut -d= -f2)
assert_contains "$paused_at" "T" "paused_at is in ISO 8601 format"
assert_contains "$paused_at" "Z" "paused_at ends with Z (UTC)"

# ============================================================
# Summary
# ============================================================
test_summary
