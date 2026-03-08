#!/usr/bin/env bash
# run_tests.sh — Discovers and runs all tests/test_*.sh files.
# Exits non-zero if any test file fails.
# Usage: ./run_tests.sh [pattern]
#   pattern: optional glob filter, e.g. "budget" runs only test_*budget*.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"

filter="${1:-}"

passed=0
failed=0
failed_files=()
skipped=0

total_files=0
for f in "$TEST_DIR"/test_*.sh; do
    [ -f "$f" ] || continue
    total_files=$((total_files + 1))
done

current=0
for test_file in "$TEST_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue

    base=$(basename "$test_file")

    # Apply filter if provided
    if [ -n "$filter" ] && [[ "$base" != *"$filter"* ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    current=$((current + 1))
    printf "\r[%d/%d] Running %s..." "$current" "$total_files" "$base" >&2

    # Run test, capture output and exit code
    rc=0
    output=$(bash "$test_file" 2>&1) || rc=$?

    # Check exit code: test_summary returns 1 on failure
    # Also check output for FAIL lines as a fallback
    if [ "$rc" -ne 0 ] || echo "$output" | grep -q '^FAIL:'; then
        failed=$((failed + 1))
        failed_files+=("$base")
        printf "\r%-60s %s\n" "$base" "FAIL" >&2
        # Show failure details indented
        echo "$output" | grep '^FAIL:' | sed 's/^/  /' >&2
    else
        passed=$((passed + 1))
    fi
done

# Clear progress line
printf "\r%-60s\n" "" >&2

echo "========================================"
echo "Test Results"
echo "========================================"
echo "Passed:  $passed"
echo "Failed:  $failed"
[ "$skipped" -gt 0 ] && echo "Skipped: $skipped (filter: *${filter}*)"
echo "Total:   $((passed + failed))"
echo "========================================"

if [ "$failed" -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for f in "${failed_files[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

echo "All tests passed."
exit 0
