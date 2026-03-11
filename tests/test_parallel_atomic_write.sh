#!/usr/bin/env bash
# tests/test_parallel_atomic_write.sh — Verify build_conflict_graph uses atomic writes
# Ensures tasks.json is written via .tmp + mv pattern to prevent corruption.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"
setup_test_dir

# Check that the source code uses atomic write pattern for tasks.json
# parallel.sh is now a compat shim; the implementation lives in parallel_core.sh
tasks_write=$(grep -A5 'tasks_file' "$_PROJECT_DIR/lib/parallel_core.sh" | grep -c '\.tmp' || echo "0")
assert_matches "$tasks_write" "[1-9]" "parallel.sh uses .tmp pattern for tasks.json"

# Also verify build_conflict_graph specifically
conflict_fn=$(sed -n '/^build_conflict_graph/,/^[^ ]/p' "$_PROJECT_DIR/lib/parallel_core.sh")
assert_contains "$conflict_fn" '.tmp' "build_conflict_graph uses temp file"
assert_contains "$conflict_fn" 'mv ' "build_conflict_graph uses mv for atomic rename"

test_summary
