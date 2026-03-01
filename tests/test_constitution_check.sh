#!/usr/bin/env bash
# tests/test_constitution_check.sh — Tests for _constitution_check() (spec-40 §2)
# Verifies that _constitution_check() validates proposed diffs against the constitution:
#   - Safety preservation (Article I)
#   - Human control preservation (Article II)
#   - Measurability (Article III — idea has metric target)
#   - Scope limits (Article VI)
#   - Test coverage (Article VII)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

script_file="$SCRIPT_DIR/../automaton.sh"

# --- Test 1: _constitution_check function exists ---
grep_result=$(grep -c '^_constitution_check()' "$script_file" || true)
assert_equals "1" "$grep_result" "_constitution_check() function exists in automaton.sh"

# --- Setup: create temp directory and harness ---
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create config file with self_build settings
cat > "$TMPDIR_TEST/automaton.config.json" << 'CFGEOF'
{
  "self_build": {
    "enabled": true,
    "max_files_per_iteration": 3,
    "max_lines_changed_per_iteration": 200,
    "protected_functions": ["run_orchestration", "_handle_shutdown"]
  }
}
CFGEOF

# Create constitution
mkdir -p "$TMPDIR_TEST"
cat > "$TMPDIR_TEST/constitution.md" << 'CONSTEOF'
# Automaton Constitution
## Ratified: 2026-03-01

### Article I: Safety First
**Protection: unanimous**

All autonomous modifications must preserve existing safety mechanisms.

### Article II: Human Sovereignty
**Protection: unanimous**

The human operator retains ultimate authority.

### Article III: Measurable Progress
**Protection: supermajority**

Every implemented change must target a measurable improvement.

### Article VI: Incremental Growth
**Protection: majority**

Evolution proceeds through small, reversible steps.

### Article VII: Test Coverage
**Protection: majority**

The test suite must not degrade through evolution.

### Article VIII: Amendment Protocol
**Protection: unanimous**
CONSTEOF

# Create garden directory with a test idea
mkdir -p "$TMPDIR_TEST/garden"
cat > "$TMPDIR_TEST/garden/idea-001.json" << 'IDEAEOF'
{
  "id": "idea-001",
  "title": "Improve token efficiency",
  "description": "Reduce tokens per task by optimizing prompt caching. Target metric: tokens_per_task reduced by 10%.",
  "stage": "bloom",
  "tags": []
}
IDEAEOF

# Create a harness that sources the function
cat > "$TMPDIR_TEST/_test_harness.sh" << 'HARNESS'
#!/usr/bin/env bash
set -uo pipefail
AUTOMATON_DIR="$1"
script_file="$2"
diff_file="$3"
idea_id="${4:-idea-001}"
cycle_id="${5:-1}"

CONFIG_FILE="$AUTOMATON_DIR/automaton.config.json"
SELF_BUILD_MAX_FILES=$(jq -r '.self_build.max_files_per_iteration // 3' "$CONFIG_FILE")
SELF_BUILD_MAX_LINES=$(jq -r '.self_build.max_lines_changed_per_iteration // 200' "$CONFIG_FILE")
SELF_BUILD_PROTECTED_FUNCTIONS=$(jq -r '.self_build.protected_functions // ["run_orchestration","_handle_shutdown"] | join(",")' "$CONFIG_FILE")

log() { :; }

eval "$(sed -n '/^_constitution_check()/,/^}/p' "$script_file")"

_constitution_check "$diff_file" "$idea_id" "$cycle_id"
HARNESS
chmod +x "$TMPDIR_TEST/_test_harness.sh"

# --- Test 2: Clean diff passes ---
cat > "$TMPDIR_TEST/clean.diff" << 'DIFFEOF'
diff --git a/automaton.sh b/automaton.sh
--- a/automaton.sh
+++ b/automaton.sh
@@ -100,3 +100,5 @@ some_function() {
     echo "hello"
+    echo "world"
+    echo "extra"
 }
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/clean.diff" "idea-001" "1" 2>/dev/null)
assert_equals "pass" "$result" "Clean diff returns pass"

# --- Test 3: Diff removing protected function triggers fail ---
cat > "$TMPDIR_TEST/safety.diff" << 'DIFFEOF'
diff --git a/automaton.sh b/automaton.sh
--- a/automaton.sh
+++ b/automaton.sh
@@ -100,5 +100,0 @@
-run_orchestration() {
-    echo "orchestrating"
-    do_stuff
-}
-
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/safety.diff" "idea-001" "1" 2>/dev/null)
assert_equals "fail" "$result" "Removing protected function run_orchestration returns fail"

# --- Test 4: Diff removing _handle_shutdown triggers fail ---
cat > "$TMPDIR_TEST/safety2.diff" << 'DIFFEOF'
diff --git a/automaton.sh b/automaton.sh
--- a/automaton.sh
+++ b/automaton.sh
@@ -200,4 +200,0 @@
-_handle_shutdown() {
-    cleanup
-    exit 0
-}
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/safety2.diff" "idea-001" "1" 2>/dev/null)
assert_equals "fail" "$result" "Removing _handle_shutdown returns fail"

# --- Test 5: Diff removing --pause-evolution triggers fail ---
cat > "$TMPDIR_TEST/human.diff" << 'DIFFEOF'
diff --git a/automaton.sh b/automaton.sh
--- a/automaton.sh
+++ b/automaton.sh
@@ -50,3 +50,2 @@
-        --pause-evolution)
-            ARG_PAUSE=true;;
         --other-flag)
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/human.diff" "idea-001" "1" 2>/dev/null)
assert_equals "fail" "$result" "Removing --pause-evolution returns fail"

# --- Test 6: Diff removing --override triggers fail ---
cat > "$TMPDIR_TEST/human2.diff" << 'DIFFEOF'
diff --git a/automaton.sh b/automaton.sh
--- a/automaton.sh
+++ b/automaton.sh
@@ -50,3 +50,2 @@
-        --override)
-            ARG_OVERRIDE=true;;
         --other-flag)
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/human2.diff" "idea-001" "1" 2>/dev/null)
assert_equals "fail" "$result" "Removing --override returns fail"

# --- Test 7: Diff removing --amend triggers fail ---
cat > "$TMPDIR_TEST/human3.diff" << 'DIFFEOF'
diff --git a/automaton.sh b/automaton.sh
--- a/automaton.sh
+++ b/automaton.sh
@@ -50,3 +50,2 @@
-        --amend)
-            ARG_AMEND=true;;
         --other-flag)
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/human3.diff" "idea-001" "1" 2>/dev/null)
assert_equals "fail" "$result" "Removing --amend returns fail"

# --- Test 8: Idea without metric target triggers warn ---
cat > "$TMPDIR_TEST/garden/idea-002.json" << 'IDEAEOF'
{
  "id": "idea-002",
  "title": "Refactor code",
  "description": "Clean up the codebase for readability.",
  "stage": "bloom",
  "tags": []
}
IDEAEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/clean.diff" "idea-002" "1" 2>/dev/null)
assert_equals "warn" "$result" "Idea without metric target returns warn"

# --- Test 9: Too many files changed triggers warn ---
# Generate a diff with 5 files changed (limit is 3)
cat > "$TMPDIR_TEST/scope.diff" << 'DIFFEOF'
diff --git a/file1.sh b/file1.sh
--- a/file1.sh
+++ b/file1.sh
@@ -1,1 +1,2 @@
 echo "a"
+echo "b"
diff --git a/file2.sh b/file2.sh
--- a/file2.sh
+++ b/file2.sh
@@ -1,1 +1,2 @@
 echo "a"
+echo "b"
diff --git a/file3.sh b/file3.sh
--- a/file3.sh
+++ b/file3.sh
@@ -1,1 +1,2 @@
 echo "a"
+echo "b"
diff --git a/file4.sh b/file4.sh
--- a/file4.sh
+++ b/file4.sh
@@ -1,1 +1,2 @@
 echo "a"
+echo "b"
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/scope.diff" "idea-001" "1" 2>/dev/null)
assert_equals "warn" "$result" "Too many files changed returns warn"

# --- Test 10: Test removal triggers warn ---
cat > "$TMPDIR_TEST/testremoval.diff" << 'DIFFEOF'
diff --git a/tests/test_something.sh b/tests/test_something.sh
--- a/tests/test_something.sh
+++ b/tests/test_something.sh
@@ -10,5 +10,0 @@
-assert_equals "1" "1" "basic test"
-assert_equals "2" "2" "another test"
-assert_contains "hello world" "hello" "contains test"
-
-test_summary
DIFFEOF

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/testremoval.diff" "idea-001" "1" 2>/dev/null)
assert_equals "warn" "$result" "Test removal returns warn"

# --- Test 11: Empty diff passes ---
touch "$TMPDIR_TEST/empty.diff"

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/empty.diff" "idea-001" "1" 2>/dev/null)
assert_equals "pass" "$result" "Empty diff returns pass"

# --- Test 12: Missing constitution file returns warn ---
mv "$TMPDIR_TEST/constitution.md" "$TMPDIR_TEST/constitution.md.bak"

result=$(bash "$TMPDIR_TEST/_test_harness.sh" "$TMPDIR_TEST" "$script_file" "$TMPDIR_TEST/clean.diff" "idea-001" "1" 2>/dev/null)
assert_equals "warn" "$result" "Missing constitution returns warn"

mv "$TMPDIR_TEST/constitution.md.bak" "$TMPDIR_TEST/constitution.md"

test_summary
