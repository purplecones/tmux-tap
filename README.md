# tmux-tap

**TAP — Tmux Agent Protocol**

A tmux plugin that provides a standardized event system for agentic coding tools (Claude Code, Codex, OpenCode, etc.). TAP owns **state and events only** — it does not touch your status bar or pane borders. What you do with those events is entirely up to you.

## Why

Every agentic tool integrates with tmux differently. `tmux-tap` gives you one consistent interface:

```tmux
set -g @tap_on_plan_ready  "tmux select-pane -t '#{pane_id}'"
set -g @tap_on_asking      "tmux select-pane -t '#{pane_id}'"
set -g @tap_on_agent_done  "afplay /System/Library/Sounds/Glass.aiff"
```

And a single pane option you can read anywhere:

```tmux
# In pane-border-format, status-right, or any format string:
#{@tap_state}   # → inactive | running | thinking | plan_ready | asking | done
```

## Installation

### Via TPM

```tmux
set -g @plugin 'purplecones/tmux-tap'
```

Then `prefix + I` to install.

### Manual

```sh
git clone https://github.com/purplecones/tmux-tap ~/.tmux/plugins/tmux-tap
```

Add to `~/.tmux.conf`:

```tmux
run '~/.tmux/plugins/tmux-tap/tap.tmux'
```

## Configuration

```tmux
# Which adapters to load (space-separated, in priority order)
set -g @tap_adapters "claude_code codex"

# Poll interval for non-push adapters (seconds, 0 = disable polling)
set -g @tap_poll_interval "2"

# Idle timeout — fire @tap_on_agent_idle after N seconds in done/asking (0 = disabled)
set -g @tap_idle_timeout "30"

# Optional: log file for debugging
set -g @tap_log_file "/tmp/tap.log"
```

## Event hooks

Each event fires a shell command defined by a tmux option. The command is executed via `tmux run-shell`, so tmux format strings like `#{pane_id}` are expanded at fire time.

| Option | Fires when |
|--------|-----------|
| `@tap_on_agent_start` | Agent becomes active in a pane |
| `@tap_on_agent_thinking` | Agent is running or processing |
| `@tap_on_plan_ready` | Agent finished planning, awaiting approval |
| `@tap_on_asking` | Agent presented a question or choice |
| `@tap_on_agent_done` | Agent completed its task |
| `@tap_on_agent_stop` | Agent exits or pane closes |
| `@tap_on_agent_idle` | Agent in `done`/`asking` longer than `@tap_idle_timeout` seconds |

Empty value = no-op.

## States

```
inactive ──[start]──► running ──► thinking
                         │
                         ├──► plan_ready   (awaiting plan approval)
                         ├──► asking       (agent asked a question)
                         └──► done         (task complete)

Any state ──[stop/exit]──► inactive
```

State is stored as a pane-scoped tmux option `@tap_state` — readable in any tmux format string at zero cost, or via `tmux show-options -pqv -t <pane_id> @tap_state` from any process.

The timestamp of the last state change is stored in `@tap_state_since` (epoch seconds). A helper script is provided to format this as a human-readable duration:

```sh
scripts/tap-duration.sh <pane_id>   # → "3m12s", "45s", "1h5m"
```

## Bundled adapters

### Claude Code (push-based, ~0ms latency)

Wires into Claude Code's `settings.json` hook system. No polling.

```sh
~/.tmux/plugins/tmux-tap/tap.tmux install claude_code
```

This merges hooks into `~/.claude/settings.json` using `jq`.

### Codex (push-based, ~0ms latency)

Wires into Codex's `hooks.json` hook system. No polling.

```sh
~/.tmux/plugins/tmux-tap/tap.tmux install codex
```

This merges hooks into `~/.codex/hooks.json` using `jq` and enables `codex_hooks = true` in `~/.codex/config.toml`.

### OpenCode (push-based, ~0ms latency)

Installs a JavaScript plugin into OpenCode's config. No polling.

```sh
~/.tmux/plugins/tmux-tap/tap.tmux install opencode
```

This adds a plugin entry to `~/.config/opencode/opencode.json`.

## Writing your own adapter

See [ADAPTER_SPEC.md](ADAPTER_SPEC.md) and [adapters/_template.sh](adapters/_template.sh).

**Poll adapters** implement 4 functions: `tap_detect_*`, `tap_state_*`, `tap_install_*`, `tap_uninstall_*`.

**Push adapters** define `tap_push_capable_*` (returning 0) and call `tap_emit` directly from tool-native hooks — no detect/state needed.

Install to `~/.tmux-tap/adapters/my_tool.sh` and add `my_tool` to `@tap_adapters`.

## Example: status bar integration

```tmux
set -g pane-border-format \
  "#{?#{==:#{@tap_state},running},● ,\
#{?#{==:#{@tap_state},plan_ready},📋 ,\
#{?#{==:#{@tap_state},asking},💬 ,\
#{?#{==:#{@tap_state},done},✓ ,\
  }}}}#{pane_title}"
```

## Requirements

- tmux ≥ 3.0
- bash ≥ 3.2
- `jq` (required for Claude Code, Codex, and OpenCode adapters)
