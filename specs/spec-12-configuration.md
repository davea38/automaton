# Spec 12: Configuration

## Purpose

Define the configuration schema for automaton. All settings have sensible defaults. The config file is optional - automaton runs with defaults if absent.

## Config File

`automaton.config.json` in the project root.

## Precedence

```
CLI flags > automaton.config.json > built-in defaults
```

If `automaton.config.json` doesn't exist, all defaults apply.
If a config key is missing from the file, its default applies.

## Full Schema

```json
{
  "models": {
    "primary": "opus",
    "research": "sonnet",
    "planning": "opus",
    "building": "sonnet",
    "review": "opus",
    "subagent_default": "sonnet"
  },
  "budget": {
    "max_total_tokens": 10000000,
    "max_cost_usd": 50.00,
    "per_phase": {
      "research": 500000,
      "plan": 1000000,
      "build": 7000000,
      "review": 1500000
    },
    "per_iteration": 500000
  },
  "rate_limits": {
    "tokens_per_minute": 80000,
    "requests_per_minute": 50,
    "cooldown_seconds": 60,
    "backoff_multiplier": 2,
    "max_backoff_seconds": 300
  },
  "execution": {
    "max_iterations": {
      "research": 3,
      "plan": 2,
      "build": 0,
      "review": 2
    },
    "parallel_builders": 1,
    "stall_threshold": 3,
    "max_consecutive_failures": 3,
    "retry_delay_seconds": 10,
    "phase_timeout_seconds": {
      "research": 0,
      "plan": 0,
      "build": 0,
      "review": 0
    }
  },
  "git": {
    "auto_push": true,
    "auto_commit": true,
    "branch_prefix": "automaton/"
  },
  "flags": {
    "dangerously_skip_permissions": true,
    "verbose": true,
    "skip_research": false,
    "skip_review": false
  }
}
```

## Field Definitions

### models

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| primary | string | "opus" | Default model when no phase-specific model is set |
| research | string | "sonnet" | Model for Phase 1 research agent |
| planning | string | "opus" | Model for Phase 2 planning agent |
| building | string | "sonnet" | Model for Phase 3 build agent |
| review | string | "opus" | Model for Phase 4 review agent |
| subagent_default | string | "sonnet" | Model for subagents spawned within agents |

Valid values: "opus", "sonnet", "haiku"

### budget

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| max_total_tokens | number | 10000000 | Hard limit on total tokens (all types combined) |
| max_cost_usd | number | 50.00 | Hard limit on estimated USD cost |
| per_phase.research | number | 500000 | Token budget for research phase |
| per_phase.plan | number | 1000000 | Token budget for planning phase |
| per_phase.build | number | 7000000 | Token budget for build phase |
| per_phase.review | number | 1500000 | Token budget for review phase |
| per_iteration | number | 500000 | Soft limit per iteration (warning only) |

### rate_limits

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| tokens_per_minute | number | 80000 | Target TPM to stay under |
| requests_per_minute | number | 50 | Target RPM to stay under |
| cooldown_seconds | number | 60 | Initial backoff delay on rate limit |
| backoff_multiplier | number | 2 | Exponential backoff multiplier |
| max_backoff_seconds | number | 300 | Maximum backoff delay (5 minutes) |

### execution

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| max_iterations.research | number | 3 | Max iterations for research phase |
| max_iterations.plan | number | 2 | Max iterations for planning phase |
| max_iterations.build | number | 0 | Max iterations for build phase (0 = unlimited) |
| max_iterations.review | number | 2 | Max iterations for review phase |
| parallel_builders | number | 1 | Number of concurrent build agents |
| stall_threshold | number | 3 | Consecutive stalls before re-plan |
| max_consecutive_failures | number | 3 | Consecutive CLI failures before giving up |
| retry_delay_seconds | number | 10 | Delay between retries |
| phase_timeout_seconds.* | number | 0 | Wallclock timeout per phase (0 = none) |

### git

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| auto_push | boolean | true | Push after each build iteration |
| auto_commit | boolean | true | Commit after each build iteration (agents do this) |
| branch_prefix | string | "automaton/" | Prefix for worktree branches |

### flags

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| dangerously_skip_permissions | boolean | true | Pass --dangerously-skip-permissions to claude |
| verbose | boolean | true | Pass --verbose to claude |
| skip_research | boolean | false | Skip Phase 1 entirely |
| skip_review | boolean | false | Skip Phase 4 entirely |

## Config Loading

```bash
load_config() {
    local config_file="${1:-automaton.config.json}"

    if [ -f "$config_file" ]; then
        # Load each value with fallback to default
        MODEL_RESEARCH=$(jq -r '.models.research // "sonnet"' "$config_file")
        MODEL_PLANNING=$(jq -r '.models.planning // "opus"' "$config_file")
        MODEL_BUILDING=$(jq -r '.models.building // "sonnet"' "$config_file")
        MODEL_REVIEW=$(jq -r '.models.review // "opus"' "$config_file")
        BUDGET_MAX_TOKENS=$(jq -r '.budget.max_total_tokens // 10000000' "$config_file")
        BUDGET_MAX_USD=$(jq -r '.budget.max_cost_usd // 50' "$config_file")
        # ... etc for all fields
    else
        # All defaults
        MODEL_RESEARCH="sonnet"
        MODEL_PLANNING="opus"
        # ... etc
    fi
}
```

## CLI Override Examples

```bash
./automaton.sh --skip-research          # flags.skip_research = true
./automaton.sh --skip-review            # flags.skip_review = true
./automaton.sh --config custom.json     # Use alternate config file
./automaton.sh --resume                 # Resume from state
./automaton.sh --dry-run                # Show config and exit
```

CLI flags override config file values. This is standard convention.

## Dependencies

Requires `jq` for JSON parsing. The CLI entry point checks for jq availability on startup.
