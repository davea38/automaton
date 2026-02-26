#!/bin/bash
# Usage: ./loop.sh [plan] [max_iterations]
# Examples:
#   ./loop.sh              # Build mode, unlimited tasks
#   ./loop.sh 20           # Build mode, max 20 tasks
#   ./loop.sh plan         # Plan mode, unlimited tasks
#   ./loop.sh plan 5       # Plan mode, max 5 tasks

MAX_RETRIES=3
RETRY_DELAY=10

# Parse arguments
if [ "$1" = "plan" ]; then
    # Plan mode
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    # Build mode with max tasks
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=$1
else
    # Build mode, unlimited
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=0
fi

ITERATION=0
CONSECUTIVE_FAILURES=0
CURRENT_BRANCH=$(git branch --show-current)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Mode:   $MODE"
echo "Prompt: $PROMPT_FILE"
echo "Branch: $CURRENT_BRANCH"
[ $MAX_ITERATIONS -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: $PROMPT_FILE not found"
    exit 1
fi

# Check IMPLEMENTATION_PLAN.md for remaining incomplete tasks
# Returns 0 if incomplete tasks exist, 1 if all done (or file missing)
check_remaining_tasks() {
    if [ -f "IMPLEMENTATION_PLAN.md" ]; then
        incomplete=$(grep -c '\[ \]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo "0")
        completed=$(grep -c '\[x\]' IMPLEMENTATION_PLAN.md 2>/dev/null || echo "0")
        echo "Tasks: $completed done, $incomplete remaining"
        if [ "$incomplete" -gt 0 ]; then
            return 0
        elif [ "$completed" -eq 0 ]; then
            echo "WARNING: No checkboxes found — plan may have been reformatted. Not trusting COMPLETE."
            return 0
        else
            return 1
        fi
    else
        echo "Warning: IMPLEMENTATION_PLAN.md not found, skipping verification"
        return 1
    fi
}

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Run Ralph iteration with selected prompt
    # -p: Headless mode (non-interactive, reads from stdin)
    # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
    # --output-format=stream-json: Structured output for logging/monitoring
    # --model opus: Primary agent uses Opus for complex reasoning (task selection, prioritization)
    #               Can use 'sonnet' in build mode for speed if plan is clear and tasks well-defined
    # --verbose: Detailed execution logging
    result=$(cat "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose)

    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        echo "Error: claude command failed with exit code $exit_code (attempt $CONSECUTIVE_FAILURES/$MAX_RETRIES)"
        if [ $CONSECUTIVE_FAILURES -ge $MAX_RETRIES ]; then
            echo "Giving up after $MAX_RETRIES consecutive failures"
            break
        fi
        echo "Retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
        continue
    fi

    # Reset failure counter on success
    CONSECUTIVE_FAILURES=0

    echo "$result"

    ITERATION=$((ITERATION + 1))
    echo -e "\n\n======================== LOOP $ITERATION ========================\n"

    # Check for COMPLETE signal from Claude
    # Use grep to handle stream-json chunking — the promise tag might be split
    # across JSON delta objects, so we strip JSON framing and check the raw text
    if echo "$result" | grep -q 'COMPLETE</promise>'; then
        if [ "$MODE" = "plan" ]; then
            # In plan mode, trust the COMPLETE signal directly — the plan will
            # have unchecked [ ] items by design (they haven't been built yet)
            echo "Plan complete after $ITERATION iterations."
            git push origin "$CURRENT_BRANCH" 2>/dev/null
            exit 0
        fi
        # Verify against the actual plan file before trusting Claude's claim
        if check_remaining_tasks; then
            echo "WARNING: Claude reported COMPLETE but incomplete tasks remain. Continuing..."
        else
            echo "All tasks complete after $ITERATION iterations."
            git push origin "$CURRENT_BRANCH" 2>/dev/null
            exit 0
        fi
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" 2>/dev/null || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH" || {
            echo "Warning: Failed to push to remote (continuing loop)"
        }
    }
done
