#!/usr/bin/env bash
# tests/test_template_sync.sh — Verify templates/ match lib/ and root files
# Ensures scaffolded projects get the same code as the source of truth.
set -uo pipefail
source "$(dirname "$0")/test_helpers.sh"

# --- Test lib/ files match templates/lib/ ---
mismatch_count=0
for lib_file in "$_PROJECT_DIR"/lib/*.sh; do
    basename=$(basename "$lib_file")
    template_file="$_PROJECT_DIR/templates/lib/$basename"
    if [ ! -f "$template_file" ]; then
        echo "FAIL: templates/lib/$basename missing" >&2
        ((_TEST_FAIL_COUNT++))
        continue
    fi
    if ! diff -q "$lib_file" "$template_file" >/dev/null 2>&1; then
        echo "FAIL: lib/$basename differs from templates/lib/$basename" >&2
        diff --brief "$lib_file" "$template_file" >&2
        ((_TEST_FAIL_COUNT++))
        ((mismatch_count++))
    else
        ((_TEST_PASS_COUNT++))
        echo "PASS: lib/$basename matches template"
    fi
done

# --- Test key root files match templates/ ---
for root_file in automaton.sh automaton.config.json; do
    src="$_PROJECT_DIR/$root_file"
    tmpl="$_PROJECT_DIR/templates/$root_file"
    [ ! -f "$src" ] && continue
    if [ ! -f "$tmpl" ]; then
        echo "FAIL: templates/$root_file missing" >&2
        ((_TEST_FAIL_COUNT++))
        continue
    fi
    if ! diff -q "$src" "$tmpl" >/dev/null 2>&1; then
        echo "FAIL: $root_file differs from templates/$root_file" >&2
        ((_TEST_FAIL_COUNT++))
    else
        ((_TEST_PASS_COUNT++))
        echo "PASS: $root_file matches template"
    fi
done

test_summary
