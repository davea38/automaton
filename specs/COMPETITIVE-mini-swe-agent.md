# Competitive Analysis: mini-swe-agent (SWE-agent/mini-swe-agent)

## Overview

**mini-swe-agent** is a radically minimal AI software engineering agent built in Python. Its core thesis is that modern LLMs are capable enough that a ~100-line agent class, armed with nothing but bash, can match the performance of far more complex agent scaffolds.

| Metric | Value |
|---|---|
| **Primary Language** | Python (105 `.py` files) |
| **Source LOC (non-test)** | ~4,650 lines of Python |
| **Test LOC** | ~8,250 lines of Python |
| **Total project LOC** | ~20,270 lines (all file types including docs, YAML, CSS, JS) |
| **Stars** | 3,076 |
| **Forks** | 408 |
| **License** | MIT |
| **Last Updated** | 2026-03-03 (active daily) |
| **Current Version** | 2.2.6 |
| **PyPI Package** | `mini-swe-agent` |
| **CLI Entry Points** | `mini` (main agent), `mini-extra` (benchmarks, inspector, config) |
| **Maintainer** | Kilian Lieret (Princeton/Stanford, SWE-bench team) |

The project scores >74% on SWE-bench Verified -- a strong result for any coding agent, let alone one this small. It is used by Meta, NVIDIA, IBM, Essential AI, Nebius, Anyscale, Princeton, and Stanford.

---

## Architecture & Structure

### Directory Layout

```
src/minisweagent/
  __init__.py              # Version, protocols (Model, Environment, Agent), global config paths
  __main__.py              # Package entry point
  exceptions.py            # Custom exceptions (Submitted, LimitsExceeded, FormatError, etc.)

  agents/
    default.py             # Core agent loop (~156 LOC) -- THE key file
    interactive.py          # Human-in-the-loop extension (~183 LOC)
    utils/prompt_user.py    # User input helpers

  environments/
    local.py               # subprocess.run on host (~80 LOC)
    docker.py              # docker exec in container (~162 LOC)
    singularity.py          # Apptainer/Singularity for HPC
    extra/
      bubblewrap.py         # bwrap sandbox (Linux)
      swerex_docker.py      # SWE-ReX remote execution via Docker
      swerex_modal.py       # SWE-ReX remote execution via Modal
      contree.py            # Contree SDK cloud sandboxing

  models/
    litellm_model.py        # Primary model class via LiteLLM (tool-calling) (~148 LOC)
    litellm_textbased_model.py  # Text/regex-based action parsing (for models without tool use)
    litellm_response_model.py   # OpenAI /response endpoint support
    openrouter_model.py     # Direct OpenRouter HTTP
    openrouter_textbased_model.py
    openrouter_response_model.py
    portkey_model.py        # Portkey AI gateway
    portkey_response_model.py
    requesty_model.py       # Requesty gateway
    test_models.py          # Deterministic model for testing
    extra/
      roulette.py           # Random model selection & interleaving (~65 LOC)
    utils/
      actions_toolcall.py   # Tool-call action parsing
      actions_text.py       # Regex-based action parsing
      anthropic_utils.py    # Thinking block reordering
      cache_control.py      # Anthropic prompt caching
      retry.py              # Tenacity-based retry logic
      content_string.py     # Content extraction helpers
      openai_multimodal.py  # Multimodal content expansion

  config/
    default.yaml            # Base config (system prompt, observation template)
    mini.yaml               # Interactive CLI config
    mini_textbased.yaml     # Text-based (non-tool-call) config
    benchmarks/
      swebench.yaml         # SWE-bench batch config (tool-call based)
      swebench_xml.yaml     # SWE-bench XML variant
      swebench_backticks.yaml  # SWE-bench backtick variant
      swebench_modal.yaml   # SWE-bench on Modal
    inspector.tcss          # TUI stylesheet

  run/
    mini.py                 # CLI entry point (typer app, ~110 LOC)
    hello_world.py          # Minimal Python binding example (~43 LOC)
    utilities/
      mini_extra.py         # Subcommand router for extra tools
      config.py             # First-time setup wizard, config management
      inspector.py          # Trajectory browser TUI (textual app, ~290 LOC)
    benchmarks/
      swebench.py           # Batch SWE-bench runner with ThreadPoolExecutor (~290 LOC)
      swebench_single.py    # Single-instance SWE-bench runner
      utils/batch_progress.py  # Rich live progress display

  utils/
    serialize.py            # recursive_merge, UNSET sentinel
    log.py                  # Logging setup
```

### Core Architectural Decisions

1. **Bash-only tool**: The agent has exactly one tool -- bash. No file editors, no search tools, no custom interfaces. The LLM uses shell commands for everything (`sed`, `grep`, `find`, `cat`, etc.).

2. **Stateless execution**: Every command runs via `subprocess.run` in a fresh subshell. No persistent shell session. This is a deliberate choice documented extensively in their FAQ as critical for stability and sandboxing portability. Swapping local execution for Docker is literally replacing `subprocess.run` with `docker exec`.

3. **Linear message history**: The agent's trajectory is the exact message history sent to the LLM. No history compression, no summarization, no windowing. Each step appends assistant message + observation. Great for debugging and fine-tuning data.

4. **Protocol-based abstractions**: `Model`, `Environment`, and `Agent` are defined as Python `Protocol` classes in `__init__.py`. Implementations use duck typing -- no inheritance required.

5. **YAML-driven configuration**: System prompts, observation templates, model parameters, and environment settings are all in YAML config files that get recursively merged. CLI arguments override YAML.

6. **Jinja2 templates everywhere**: System prompts, instance prompts, observation formatting, and error messages all use Jinja2 templates with `StrictUndefined`. Templates have access to environment variables, platform info, model config, and agent state.

### Tech Stack

- **Python 3.10+**, setuptools build
- **LiteLLM** for model abstraction (supports 100+ providers)
- **Pydantic v2** for config validation
- **Typer** for CLI
- **Rich** for terminal output formatting
- **Textual** for the trajectory inspector TUI
- **Jinja2** for prompt templating
- **Tenacity** for retry logic
- **python-dotenv** for environment config
- **datasets** (HuggingFace) for SWE-bench data loading

---

## Features

### Core Agent Features

- **Single-tool bash agent**: ~100-line agent class (`agents/default.py`) with run/step/query/execute_actions loop
- **Interactive mode**: Human-in-the-loop with three modes -- `human` (user types commands), `confirm` (LLM proposes, user approves), `yolo` (fully autonomous). Switchable mid-session via `/y`, `/c`, `/u` commands.
- **Cost tracking and limits**: Per-agent and global cost/step limits. Configurable via `cost_limit` and `step_limit`. Global limits via `MSWEA_GLOBAL_COST_LIMIT` env var with thread-safe tracking.
- **Trajectory serialization**: Full agent state saved as JSON including messages, model stats, config, exit status, and submission. Compatible with SWE-bench evaluation.
- **First-time setup wizard**: `configure_if_first_time()` prompts for model name and API key on first run, saves to global `.env` file.

### Environment Support (7 environments)

- **Local** (`local.py`): Direct `subprocess.run` on host machine
- **Docker** (`docker.py`): Runs commands via `docker exec` in a container. Supports podman via `MSWEA_DOCKER_EXECUTABLE` env var. Configurable interpreter, env forwarding, container timeout.
- **Singularity/Apptainer** (`singularity.py`): For HPC clusters
- **Bubblewrap** (`bubblewrap.py`): Lightweight Linux sandboxing without root
- **SWE-ReX Docker** (`swerex_docker.py`): Remote execution via SWE-ReX framework
- **SWE-ReX Modal** (`swerex_modal.py`): Serverless cloud execution via Modal
- **Contree** (`contree.py`): Cloud sandboxing via Contree SDK

### Model Support (9+ model classes)

- **LiteLLM tool-calling** (`litellm_model.py`): Primary model class using LiteLLM's `completion()` with tool-calling interface
- **LiteLLM text-based** (`litellm_textbased_model.py`): Regex-based action extraction for models without tool-calling support. Uses ` ```mswea_bash_command ``` ` fenced blocks.
- **LiteLLM response** (`litellm_response_model.py`): OpenAI `/response` endpoint
- **OpenRouter** variants (tool-call, text-based, response): Direct HTTP to OpenRouter API
- **Portkey** variants: Via Portkey AI gateway
- **Requesty**: Via Requesty gateway
- **Roulette model** (`extra/roulette.py`): Randomly selects between multiple models per call. Blog post claims randomly switching GPT-5 and Sonnet 4 boosts performance.
- **Interleaving model** (`extra/roulette.py`): Deterministic alternation between models in a configurable sequence

### Benchmarking

- **Batch SWE-bench runner** (`run/benchmarks/swebench.py`): ThreadPoolExecutor-based parallel processing with configurable worker count. Rich live progress display. Supports SWE-bench Full, Verified, Lite, Multimodal, Multilingual, SWE-smith, and SWE-rebench datasets.
- **Single-instance runner** for debugging individual SWE-bench cases
- **preds.json output**: Standard SWE-bench prediction format for evaluation
- **Instance filtering**: Regex filter and slice specification for subset selection. Resume support (skips completed instances).

### Developer/User Tools

- **Trajectory inspector** (`run/utilities/inspector.py`): Textual-based TUI for browsing agent conversation trajectories. Vim-like navigation (h/j/k/l), multi-trajectory support, jless integration.
- **Config management CLI** (`mini-extra config`): `setup`, `set`, `unset`, `edit` subcommands for global `.env` config file
- **Python bindings**: Simple programmatic API -- `DefaultAgent(model, env).run("task")`
- **Multimodal support**: Regex-based extraction and expansion of multimodal content in messages
- **Anthropic-specific optimizations**: Prompt caching via `set_cache_control`, thinking block reordering

### Prompt Engineering

- **Output truncation**: Observation template clips output >10,000 chars, showing first/last 5,000 chars with a warning message
- **Format error recovery**: When the LLM doesn't produce valid tool calls or bash blocks, a configurable error template guides it back
- **Platform-aware prompts**: System information (OS, arch) injected into instance template. MacOS-specific sed instructions.
- **Submission protocol**: `echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT` as the completion signal. Detected by environment's `_check_finished()`.

---

## What Users Like

### Simplicity and Hackability
Users consistently praise the radical simplicity. The ~100-line agent class is genuinely understandable at a glance. Several issues and comments reference forking and modifying the agent with minimal effort (e.g., issue #583 where a user forked and removed problematic cost-checking code to fix OpenRouter compatibility).

### Strong Benchmark Performance
The >74% on SWE-bench Verified is a headline feature. Issue #756 shows users trying to replicate these scores, indicating trust in the claimed results. The project provides downloadable trajectories for verification.

### Broad Model Compatibility
Users run it with everything from Claude and GPT-5 to local models via Ollama and llama-server. The LiteLLM abstraction makes swapping models trivial. Issues #630, #707, #759 show active usage with local models.

### Active Maintenance
3,076 stars with frequent PRs (multiple per week as of March 2026). The maintainer (`klieret`) responds to issues quickly, often within hours. The v2 migration shows active evolution.

### Academic Credibility
Built by the Princeton/Stanford SWE-bench team. The NeurIPS 2024 paper backing gives academic weight. Users from Meta, NVIDIA, IBM, etc. adopt it partly for this provenance.

### Easy Installation
`uvx mini-swe-agent` or `pip install mini-swe-agent` with no complex setup. First-time wizard guides API key configuration.

---

## What Users Dislike / Struggle With

### Local Model Support is Fragile
Issues #759, #630, #707 show users struggling with local models (Ollama, llama-server). Cost tracking breaks for unregistered models, LiteLLM compatibility layers have edge cases, and hanging/timeout issues occur. The `cost_tracking: 'ignore_errors'` workaround is not discoverable.

### Cost Tracking Errors Block Execution (Fixed but Recurring Pattern)
Multiple issues (#583, #577, #707) report that cost calculation failures crash the agent rather than gracefully degrading. Even after fixes, the pattern recurs with new model providers.

### SWE-bench Reproducibility Confusion
Issue #756 (8 comments) shows users struggling to replicate benchmark scores. Dataset versioning, config differences (text-based vs tool-call), and environment setup all create friction.

### Environment Configuration Complexity
Issue #699 (6 comments) -- environment settings from config files not propagating correctly. Issue #710 (10 comments) -- read-only filesystem errors with Singularity that required extensive debugging of HPC-specific mount policies.

### No MCP/External Tool Support
Issue #563 (5 comments, still open) -- users want MCP integration or a way to define custom tools. The maintainer's response is "just tell the LLM to use CLI tools," which is philosophically consistent but limits extensibility.

### FormatError Handling Gaps
Issues #737 (7 comments) and #727 (open) report that when the LLM produces invalid output (no tool call, malformed JSON), the error recovery can break trajectory serialization and the inspector. Step counting becomes incorrect.

### Agent Hallucination with Weak Models
Issue #581 (4 comments) -- the agent hallucinates conversing with a user instead of executing commands. This happens with weaker models that don't follow the system prompt reliably.

### Stateless Execution is a Double-Edged Sword
While the FAQ extensively justifies why stateless subshells are better, users find it unintuitive that `cd` and environment variable changes don't persist. The workaround (`cd /path && command`) is documented but adds friction.

---

## Good Ideas to Poach

### 1. Output Truncation with Head/Tail Preservation
File: `src/minisweagent/config/default.yaml` (observation_template, lines 119-141)

When command output exceeds 10,000 characters, the template shows the first 5,000 and last 5,000 chars with a warning and elided character count. This is strictly better than simple truncation -- the tail often contains error messages and summaries. Automaton should adopt this pattern for long command output.

### 2. Roulette/Interleaving Model Selection
File: `src/minisweagent/models/extra/roulette.py`

Randomly switching between models per-call or interleaving them in a sequence reportedly boosts performance. This is a zero-cost architectural trick. For Automaton's pipeline, alternating between a planning-strong model and a code-strong model could improve results.

### 3. First-Time Setup Wizard
File: `src/minisweagent/run/utilities/config.py` (lines 62-93)

The `configure_if_first_time()` pattern -- check for `MSWEA_CONFIGURED` flag, run interactive setup, persist to `.env` -- is a smooth onboarding experience. Automaton could use a similar pattern for first-run configuration.

### 4. Recursive Config Merging from Multiple Sources
File: `src/minisweagent/config/__init__.py` and `src/minisweagent/utils/serialize.py`

The `-c` flag accepts multiple config specs (YAML files, `key.path=value` overrides) that get recursively deep-merged. This is more flexible than a single config file. For Automaton, allowing `--config base.yaml --config overrides.yaml --config model.temperature=0.5` would be powerful.

### 5. Trajectory Inspector TUI
File: `src/minisweagent/run/utilities/inspector.py`

A Textual-based TUI for browsing agent conversations with vim-like navigation. This is invaluable for debugging. Automaton could benefit from a similar post-run inspection tool, even if simpler (e.g., `less`-based with structured output).

### 6. Interactive Mode with Switchable Autonomy
File: `src/minisweagent/agents/interactive.py`

Three modes (`human`, `confirm`, `yolo`) switchable mid-session via `/y`, `/c`, `/u` slash commands. The `confirm` mode where the LLM proposes and the user approves is a great trust-building pattern. The action whitelist regex for auto-approving safe commands is clever.

### 7. COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT Sentinel
File: `src/minisweagent/environments/local.py` (lines 55-66)

Using a deterministic stdout sentinel (`echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT`) to signal task completion is robust and works across all environments. No special API needed. The submission content follows on subsequent lines.

### 8. Anthropic Prompt Caching
File: `src/minisweagent/models/utils/cache_control.py`

Automatic `cache_control` markers for Anthropic models, auto-detected by model name. Reduces cost significantly for long conversations. Automaton should implement this if using Anthropic models.

### 9. Platform-Aware Prompt Templates
File: `src/minisweagent/config/default.yaml` (lines 72-76)

Jinja2 conditionals in the system prompt that adapt to the OS (e.g., `sed -i ''` on macOS vs `sed -i` on Linux). Small but prevents common user errors.

### 10. Global Cost Limits with Thread Safety
File: `src/minisweagent/models/__init__.py` (GlobalModelStats class, lines 14-41)

Thread-safe global cost tracking across all model instances via `MSWEA_GLOBAL_COST_LIMIT`. Essential for batch runs where you want a hard spending cap.

---

## Ideas to Improve On

### 1. No Persistent State Between Commands
mini-swe-agent deliberately uses stateless subshells (`subprocess.run` per command). While this simplifies sandboxing, it means every command must re-establish working directory and environment. Users in issue #581 and elsewhere stumble on this. Automaton, as a bash-file pipeline, naturally has persistent shell state -- this is an inherent advantage. Lean into it.

### 2. No Spec-Driven Architecture
mini-swe-agent is purely task-driven: give it a problem statement, it tries to solve it. There is no concept of a specification, acceptance criteria, or phased workflow. Automaton's spec-to-code pipeline is fundamentally more structured and can produce more predictable outputs for defined work.

### 3. Weak Error Recovery
FormatError handling (issues #737, #727) shows that when the LLM produces malformed output, recovery is fragile. The agent sends an error message back and hopes the LLM corrects itself. Automaton could implement structured retry with progressive simplification (retry with simpler prompt, fall back to different model, split the task).

### 4. No Built-in Testing/Validation Phase
mini-swe-agent's prompt suggests a workflow (analyze, reproduce, fix, verify), but there's no structural enforcement. The agent can skip verification entirely. Automaton could enforce test-before-submit as a pipeline stage, not just a suggestion in the prompt.

### 5. No Progress Persistence / Checkpointing
If mini-swe-agent crashes mid-run, all progress is lost (for that instance). The trajectory is saved after each step, but there's no mechanism to resume from the last step. Automaton could implement checkpointing that allows resumption from the last successful state.

### 6. Bloated Dependency Chain for a "Minimal" Agent
Despite the "100 lines" marketing, the actual dependency list is substantial: litellm, pydantic, jinja2, rich, textual, datasets, openai, tenacity, typer, prompt_toolkit, platformdirs, python-dotenv. A single-bash-file approach (Automaton) has zero dependencies beyond curl/jq, which is genuinely minimal.

### 7. No Multi-File Awareness / Codebase Indexing
mini-swe-agent relies entirely on the LLM to navigate codebases using `find`, `grep`, and `cat`. There's no pre-indexing, no AST analysis, no file relevance ranking. Automaton could pre-index the codebase (e.g., tree output, file size ranking, symbol extraction) and feed a compressed map to the LLM upfront.

### 8. Observation Template is Static
The 10,000-character output limit is hardcoded in the YAML template. There's no adaptive truncation based on context window remaining, output relevance, or content type. Automaton could dynamically adjust output windows based on remaining token budget.

### 9. No Parallel Command Execution in Interactive Mode
While SWE-bench batch mode uses ThreadPoolExecutor for parallelism across instances, individual agent runs execute commands sequentially. The agent cannot run independent commands in parallel within a single step. Automaton could support `cmd1 & cmd2 & wait` patterns natively.

### 10. Single-Agent, No Orchestration
mini-swe-agent is a single agent with a single loop. There's no planner/executor split, no agent delegation, no task decomposition. For complex multi-step specifications, Automaton's pipeline approach (spec parsing -> task decomposition -> implementation -> testing) provides structural advantages that a flat agent loop cannot match.

### 11. No Git Integration
mini-swe-agent creates patches via `git diff` in the prompt instructions, but has no built-in git awareness. It doesn't know what branch it's on, what files have changed, or how to create commits. Automaton, running in a real git environment, could integrate git status/diff as first-class context.

### 12. Configuration Complexity Despite "Simplicity" Branding
The config system (YAML files, env vars, CLI args, recursive merging, Jinja2 templates, key-value overrides) is actually quite complex. Issue #699 shows users confused by config propagation. Automaton's single-file approach with inline configuration is simpler to reason about.
