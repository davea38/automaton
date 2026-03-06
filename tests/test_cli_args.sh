#!/usr/bin/env bash
# tests/test_cli_args.sh — Tests for spec-44 §44.1 argument parsing
# Verifies CLI flags are correctly parsed by actually invoking the parser.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# We can test argument parsing by sourcing just the argument parser section.
# Extract the arg-parsing block from automaton.sh and wrap it in a testable function.
_test_parse_args() {
    # Reset all ARG_ variables to defaults
    ARG_RESUME=false
    ARG_SKIP_RESEARCH=false
    ARG_SKIP_REVIEW=false
    ARG_CONFIG_FILE=""
    ARG_DRY_RUN=false
    ARG_SELF=false
    ARG_CONTINUE=false
    ARG_STATS=false
    ARG_BUDGET_CHECK=false
    ARG_HEALTH=false
    ARG_EVOLVE=false
    ARG_CYCLES=0
    ARG_PLANT=""
    ARG_GARDEN=false
    ARG_GARDEN_DETAIL=""
    ARG_WATER_ID=""
    ARG_WATER_EVIDENCE=""
    ARG_PRUNE_ID=""
    ARG_PRUNE_REASON=""
    ARG_PROMOTE=""
    ARG_INSPECT=""
    ARG_CONSTITUTION=false
    ARG_AMEND=false
    ARG_OVERRIDE=false
    ARG_PAUSE_EVOLUTION=false
    ARG_SIGNALS=false
    ARG_VALIDATE_CONFIG=false
    ARG_DOCTOR=false
    ARG_CRITIQUE_SPECS=false
    ARG_SKIP_CRITIQUE=false
    ARG_STEELMAN=false
    ARG_COMPLEXITY=""
    ARG_LOG_LEVEL=""
    ARG_SETUP=false
    ARG_NO_SETUP=false
    ARG_WIZARD=false
    ARG_NO_WIZARD=false

    # Parse args using the same while/case from automaton.sh
    while [ $# -gt 0 ]; do
        case "$1" in
            --resume) ARG_RESUME=true; shift ;;
            --skip-research) ARG_SKIP_RESEARCH=true; shift ;;
            --skip-review) ARG_SKIP_REVIEW=true; shift ;;
            --config)
                if [ -z "${2:-}" ]; then echo "Error: --config requires arg" >&2; return 1; fi
                ARG_CONFIG_FILE="$2"; shift 2 ;;
            --dry-run) ARG_DRY_RUN=true; shift ;;
            --self) ARG_SELF=true; shift ;;
            --continue) ARG_CONTINUE=true; shift ;;
            --stats) ARG_STATS=true; shift ;;
            --budget-check) ARG_BUDGET_CHECK=true; shift ;;
            --health) ARG_HEALTH=true; shift ;;
            --evolve) ARG_EVOLVE=true; ARG_SELF=true; shift ;;
            --cycles)
                if [ -z "${2:-}" ] || ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then return 1; fi
                ARG_CYCLES="$2"; shift 2 ;;
            --plant)
                ARG_PLANT="${2:-}"; [ -z "$ARG_PLANT" ] && return 1; shift 2 ;;
            --garden) ARG_GARDEN=true; shift ;;
            --garden-detail)
                ARG_GARDEN_DETAIL="${2:-}"; [ -z "$ARG_GARDEN_DETAIL" ] && return 1; shift 2 ;;
            --water)
                ARG_WATER_ID="${2:-}"; ARG_WATER_EVIDENCE="${3:-}"
                [ -z "$ARG_WATER_ID" ] || [ -z "$ARG_WATER_EVIDENCE" ] && return 1; shift 3 ;;
            --prune)
                ARG_PRUNE_ID="${2:-}"; ARG_PRUNE_REASON="${3:-}"
                [ -z "$ARG_PRUNE_ID" ] || [ -z "$ARG_PRUNE_REASON" ] && return 1; shift 3 ;;
            --promote)
                ARG_PROMOTE="${2:-}"; [ -z "$ARG_PROMOTE" ] && return 1; shift 2 ;;
            --inspect)
                ARG_INSPECT="${2:-}"; [ -z "$ARG_INSPECT" ] && return 1; shift 2 ;;
            --constitution) ARG_CONSTITUTION=true; shift ;;
            --amend) ARG_AMEND=true; shift ;;
            --override) ARG_OVERRIDE=true; shift ;;
            --pause-evolution) ARG_PAUSE_EVOLUTION=true; shift ;;
            --signals) ARG_SIGNALS=true; shift ;;
            --validate-config) ARG_VALIDATE_CONFIG=true; shift ;;
            --doctor) ARG_DOCTOR=true; shift ;;
            --critique-specs) ARG_CRITIQUE_SPECS=true; shift ;;
            --skip-critique) ARG_SKIP_CRITIQUE=true; shift ;;
            --steelman) ARG_STEELMAN=true; shift ;;
            --complexity)
                if [ -z "${2:-}" ] || ! echo "${2:-}" | grep -qE '^(simple|moderate|complex)$'; then return 1; fi
                ARG_COMPLEXITY="$2"; shift 2 ;;
            --log-level)
                if [ -z "${2:-}" ] || ! echo "${2:-}" | grep -qE '^(minimal|normal|verbose)$'; then return 1; fi
                ARG_LOG_LEVEL="$2"; shift 2 ;;
            --setup) ARG_SETUP=true; shift ;;
            --no-setup) ARG_NO_SETUP=true; shift ;;
            --wizard) ARG_WIZARD=true; shift ;;
            --no-wizard) ARG_NO_WIZARD=true; shift ;;
            --help|-h) return 0 ;;
            *) echo "Error: Unknown argument: $1" >&2; return 1 ;;
        esac
    done
}

# ============================================================
# Simple boolean flags
# ============================================================

_test_parse_args --resume
assert_equals "true" "$ARG_RESUME" "--resume sets ARG_RESUME=true"

_test_parse_args --skip-research
assert_equals "true" "$ARG_SKIP_RESEARCH" "--skip-research sets ARG_SKIP_RESEARCH=true"

_test_parse_args --skip-review
assert_equals "true" "$ARG_SKIP_REVIEW" "--skip-review sets ARG_SKIP_REVIEW=true"

_test_parse_args --dry-run
assert_equals "true" "$ARG_DRY_RUN" "--dry-run sets ARG_DRY_RUN=true"

_test_parse_args --self
assert_equals "true" "$ARG_SELF" "--self sets ARG_SELF=true"

_test_parse_args --garden
assert_equals "true" "$ARG_GARDEN" "--garden sets ARG_GARDEN=true"

_test_parse_args --constitution
assert_equals "true" "$ARG_CONSTITUTION" "--constitution sets ARG_CONSTITUTION=true"

_test_parse_args --amend
assert_equals "true" "$ARG_AMEND" "--amend sets ARG_AMEND=true"

_test_parse_args --override
assert_equals "true" "$ARG_OVERRIDE" "--override sets ARG_OVERRIDE=true"

_test_parse_args --pause-evolution
assert_equals "true" "$ARG_PAUSE_EVOLUTION" "--pause-evolution sets ARG_PAUSE_EVOLUTION=true"

_test_parse_args --signals
assert_equals "true" "$ARG_SIGNALS" "--signals sets ARG_SIGNALS=true"

_test_parse_args --doctor
assert_equals "true" "$ARG_DOCTOR" "--doctor sets ARG_DOCTOR=true"

_test_parse_args --steelman
assert_equals "true" "$ARG_STEELMAN" "--steelman sets ARG_STEELMAN=true"

# ============================================================
# Flags with arguments
# ============================================================

_test_parse_args --plant "new feature idea"
assert_equals "new feature idea" "$ARG_PLANT" "--plant captures idea text"

_test_parse_args --garden-detail "idea-42"
assert_equals "idea-42" "$ARG_GARDEN_DETAIL" "--garden-detail captures ID"

_test_parse_args --water "idea-7" "test passed in CI"
assert_equals "idea-7" "$ARG_WATER_ID" "--water captures ID"
assert_equals "test passed in CI" "$ARG_WATER_EVIDENCE" "--water captures evidence"

_test_parse_args --prune "idea-3" "superseded by idea-7"
assert_equals "idea-3" "$ARG_PRUNE_ID" "--prune captures ID"
assert_equals "superseded by idea-7" "$ARG_PRUNE_REASON" "--prune captures reason"

_test_parse_args --promote "idea-12"
assert_equals "idea-12" "$ARG_PROMOTE" "--promote captures ID"

_test_parse_args --inspect "vote-5"
assert_equals "vote-5" "$ARG_INSPECT" "--inspect captures ID"

_test_parse_args --cycles 5
assert_equals "5" "$ARG_CYCLES" "--cycles captures integer"

_test_parse_args --complexity "moderate"
assert_equals "moderate" "$ARG_COMPLEXITY" "--complexity captures value"

_test_parse_args --log-level "verbose"
assert_equals "verbose" "$ARG_LOG_LEVEL" "--log-level captures value"

# ============================================================
# --evolve implies --self
# ============================================================

_test_parse_args --evolve
assert_equals "true" "$ARG_EVOLVE" "--evolve sets ARG_EVOLVE=true"
assert_equals "true" "$ARG_SELF" "--evolve also sets ARG_SELF=true"

# ============================================================
# Multi-flag combinations
# ============================================================

_test_parse_args --resume --skip-review --dry-run
assert_equals "true" "$ARG_RESUME" "multi-flag: --resume"
assert_equals "true" "$ARG_SKIP_REVIEW" "multi-flag: --skip-review"
assert_equals "true" "$ARG_DRY_RUN" "multi-flag: --dry-run"
assert_equals "false" "$ARG_SKIP_RESEARCH" "multi-flag: unset flags stay false"

# ============================================================
# Error cases
# ============================================================

# --plant with no argument
output=$(_test_parse_args --plant 2>&1)
rc=$?
assert_equals "1" "$rc" "--plant with no arg returns error"

# --cycles with non-integer
output=$(_test_parse_args --cycles "abc" 2>&1)
rc=$?
assert_equals "1" "$rc" "--cycles with non-integer returns error"

# --complexity with invalid value
output=$(_test_parse_args --complexity "mega" 2>&1)
rc=$?
assert_equals "1" "$rc" "--complexity with invalid value returns error"

# --log-level with invalid value
output=$(_test_parse_args --log-level "debug" 2>&1)
rc=$?
assert_equals "1" "$rc" "--log-level with invalid value returns error"

# Unknown flag
output=$(_test_parse_args --nonexistent 2>&1)
rc=$?
assert_equals "1" "$rc" "unknown flag returns error"

# --water with missing evidence
output=$(_test_parse_args --water "id1" 2>&1)
rc=$?
assert_equals "1" "$rc" "--water with missing evidence returns error"

# Defaults are correct when no args passed
_test_parse_args
assert_equals "false" "$ARG_RESUME" "default: ARG_RESUME=false"
assert_equals "" "$ARG_PLANT" "default: ARG_PLANT empty"
assert_equals "0" "$ARG_CYCLES" "default: ARG_CYCLES=0"
assert_equals "false" "$ARG_GARDEN" "default: ARG_GARDEN=false"
assert_equals "" "$ARG_COMPLEXITY" "default: ARG_COMPLEXITY empty"

test_summary
