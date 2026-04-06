# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TAP (Tmux Agent Protocol) is a tmux plugin that provides a standardized state/event system for agentic coding tools (Claude Code, Codex, OpenCode, etc.). It owns **state and events only** — no status bar modifications, no pane borders.

## No build system

This is pure bash. There are no build steps, test runners, or package managers. Validate changes by:
- Sourcing scripts manually: `bash -n scripts/tap_core.sh` (syntax check)
- Installing via TPM and reloading tmux: `tmux source ~/.tmux.conf && prefix+I`
- Tailing the log file when `@tap_log_file` is set

## Architecture

```
tap.tmux                   ← TPM entry point; loads adapters, registers pane-exited hook, starts monitor
scripts/tap_helpers.sh     ← Shared utilities (get_tmux_option, tap_log, tap_refresh)
scripts/tap_core.sh        ← State machine: tap_emit, tap_get_state, tap_cleanup_pane, _tap_fire
scripts/tap_monitor.sh     ← Background polling loop for non-push adapters
scripts/pane-exit.sh       ← Cleans up state when a pane exits
adapters/claude_code.sh    ← Push-based adapter (0ms latency via settings.json hooks)
adapters/codex.sh          ← Push-based adapter (0ms latency via hooks.json hooks)
adapters/opencode.sh       ← Push-based adapter (0ms latency via JS plugin)
adapters/_template.sh      ← Canonical template for new adapters
install/codex_wrapper.sh   ← Legacy shell rc wrapper for Codex (superseded by push adapter)
```

### State flow

State transitions are driven by `tap_emit <pane_id> <state>` in `tap_core.sh`. Every call:
1. Validates the state string against `TAP_VALID_STATES`
2. Reads current state via `tmux show-options -p @tap_state`; exits if unchanged
3. Writes `@tap_state` on the pane (single source of truth)
4. Fires lifecycle events (`agent_start` on `inactive→running`, `agent_stop` on `*→inactive`) then state-specific events via `_tap_fire`

### Push vs. poll adapters

- **Push adapters** define `tap_push_capable_<name>()` (returns 0) and call `tap_emit` directly from tool-native hooks. The monitor loop skips them entirely.
- **Poll adapters** implement `tap_detect_<name>` and `tap_state_<name>`; the monitor calls these on every interval.

### Adapter interface

**Poll adapters** — four functions: `tap_detect_<name>`, `tap_state_<name>`, `tap_install_<name>`, `tap_uninstall_<name>`

**Push adapters** — define `tap_push_capable_<name>()` (returns 0) instead of detect/state, plus `tap_install_<name>` and `tap_uninstall_<name>`

Adapters load from (in priority order): absolute path, `~/.tmux-tap/adapters/<name>.sh`, `adapters/<name>.sh` in plugin dir.

### Claude Code adapter internals

`tap_install_claude_code` merges three hook types into `~/.claude/settings.json` using `jq`:
- `UserPromptSubmit` → sets `@tap_state running` directly on the pane
- `PreToolUse` → sets `running`, `asking` (on `AskUserQuestion`), or `plan_ready` (on `ExitPlanMode`)
- `Stop` → runs `~/.tmux-tap/hooks/tap-stop.sh`, which uses `jq` to parse the stop JSON and calls `tap_emit` with `asking` or `done` based on whether the last assistant message ends with `?` or contains a numbered list

### Valid states

`inactive` | `running` | `thinking` | `plan_ready` | `done` | `asking`

### Event hooks (user-configured)

`@tap_on_agent_start` | `@tap_on_agent_thinking` | `@tap_on_plan_ready` | `@tap_on_asking` | `@tap_on_agent_done` | `@tap_on_agent_stop`

Commands run via `tmux run-shell`, so tmux format strings (`#{pane_id}`) are expanded at fire time.

## Key constraints

- Bash ≥ 3.2 compatible (no associative arrays with `-A`, no `bash 4+` features)
- `jq` required for Claude Code, Codex, and OpenCode adapters (install/uninstall and Stop hook state inference)
- All scripts must be sourced-safe (no side effects at source time except function definitions and variable assignments)
- `tap_emit` is idempotent — same-state transitions are no-ops
- The monitor loop re-reads `@tap_adapters` on every tick (users can add adapters without restarting)
