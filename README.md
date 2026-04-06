# tmux-tap

**TAP — Tmux Agent Protocol**

A tmux plugin that provides a standardized event system for agentic coding tools (Claude Code, Codex, Aider, etc.). TAP owns **state and events only** — it does not touch your status bar or pane borders. What you do with those events is entirely up to you.

## Why

Every agentic tool integrates with tmux differently. `tmux-tap` gives you one consistent interface:

```tmux
set -g @tap_on_plan_ready  "tmux select-pane -t '#{pane_id}'"
set -g @tap_on_needs_input "tmux select-pane -t '#{pane_id}'"
set -g @tap_on_agent_done  "afplay /System/Library/Sounds/Glass.aiff"
```

And a single pane option you can read anywhere:

```tmux
# In pane-border-format, status-right, or any format string:
#{@tap_state}   # → idle | running | thinking | plan_ready | needs_input | asking | done
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
| `@tap_on_needs_input` | Agent is blocked waiting for user input |
| `@tap_on_asking` | Agent presented a question or choice |
| `@tap_on_agent_done` | Agent completed its task |
| `@tap_on_agent_stop` | Agent exits or pane closes |

Empty value = no-op.

## States

```
idle ──[start]──► running ──► thinking
                     │
                     ├──► plan_ready   (awaiting plan approval)
                     ├──► needs_input  (blocked, new prompt expected)
                     ├──► asking       (agent asked a question)
                     └──► done         (task complete)

Any state ──[stop/exit]──► idle
```

State is stored as a pane-scoped tmux option `@tap_state` — readable in any tmux format string at zero cost, or via `tmux show-options -pqv -t <pane_id> @tap_state` from any process.

## Bundled adapters

### Claude Code (push-based, ~0ms latency)

Wires into Claude Code's `settings.json` hook system. No polling.

```sh
~/.tmux/plugins/tmux-tap/tap.tmux install claude_code
```

This merges hooks into `~/.claude/settings.json` using `jq`.

### Codex (poll-based by default)

Heuristic detection via process name and child processes. For near-realtime state, add to your shell rc:

```sh
source "${HOME}/.tmux/plugins/tmux-tap/install/codex_wrapper.sh"
```

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
#{?#{==:#{@tap_state},needs_input},⏳ ,\
#{?#{==:#{@tap_state},asking},💬 ,\
  }}}}#{pane_title}"
```

## Requirements

- tmux ≥ 3.0
- bash ≥ 3.2
- `jq` (optional, for Claude Code adapter)
