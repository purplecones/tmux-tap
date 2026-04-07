# TAP Adapter Specification

An adapter bridges a specific agentic coding tool and the TAP event system. Any developer can write one by implementing the interface described here.

## Interface

An adapter is a single `.sh` file that defines shell functions following the naming convention `tap_<function>_<adapter_name>`. The adapter name must be lowercase with underscores (e.g. `my_tool`).

### Poll adapter functions (required unless push-capable)

#### `tap_detect_<name> PANE_ID PANE_CMD PANE_PID PANE_TITLE`

Returns `0` (true) if this adapter owns the given pane, `1` otherwise.

Use the cheapest check first. The recommended hierarchy:

1. **Process name** — `pane_current_command` is provided directly by tmux, no subprocess
2. **Env var** — check `TAP_PANE_${PANE_ID}_ADAPTER` or tool-specific state files
3. **Child process** — `pgrep -P PANE_PID` (one subprocess per pane)
4. **Pane output** — `tmux capture-pane -p` (expensive, use sparingly)

The monitor calls adapters in priority order (`@tap_adapters`). First match wins and is stored; subsequent panes skip already-claimed adapters.

#### `tap_state_<name> PANE_ID PANE_PID PANE_TITLE`

Echoes the current state of the agent in this pane. Must be one of:

| State | Meaning |
|-------|---------|
| `inactive` | No agent active |
| `running` | Agent is executing / calling tools |
| `thinking` | Agent is processing (LLM inference, no tool calls) |
| `plan_ready` | Agent finished planning, awaiting user approval |
| `asking` | Agent presented a question or choice |
| `done` | Agent completed task |

#### `tap_install_<name>`

Called once on plugin load. Set up any tool-side plumbing: merge config files, register hooks, etc. Should be idempotent.

#### `tap_uninstall_<name>`

Reverses `tap_install_<name>`.

### Common functions

#### `tap_process_name_<name>`

Echoes the expected `pane_current_command` for this agent (e.g. `claude`, `codex`). The monitor's stale-state reaper calls this to detect when an agent process exits without firing its stop hook — if the process name disappears from a pane that still has a non-`inactive` state, the reaper resets it.

All adapters should define this. Push adapters especially need it because they have no poll cycle to notice a disappeared process.

```sh
tap_process_name_my_tool() { echo "my-tool"; }
```

### Push adapter functions

#### `tap_push_capable_<name>` (replaces detect + state)

Define this (returning `0`) to tell the monitor loop to skip polling this adapter. Push adapters call `tap_emit` directly from tool-native hooks — `tap_detect_*` and `tap_state_*` are not needed and not called.

```sh
tap_push_capable_my_tool() { return 0; }
```

Still requires `tap_install_<name>` and `tap_uninstall_<name>`.

## Calling `tap_emit`

From a push-based hook or wrapper:

```sh
source "${TAP_PLUGIN_DIR}/scripts/tap_helpers.sh"
source "${TAP_PLUGIN_DIR}/scripts/tap_core.sh"

tap_emit "$TMUX_PANE" "running"
```

`tap_emit` is idempotent — calling it with the same state as the current state is a no-op.

## Registering your adapter

Users add your adapter to their `.tmux.conf`:

```tmux
set -g @tap_adapters "claude_code my_tool"
```

Adapters in the bundled `adapters/` directory are found automatically by name. For third-party adapters, provide the full path or install to `~/.tmux-tap/adapters/<name>.sh`.

## Minimal push adapter example

```sh
#!/usr/bin/env bash
# TAP Adapter: my_tool (push-based)

tap_push_capable_my_tool() { return 0; }
tap_process_name_my_tool() { echo "my-tool"; }

tap_install_my_tool() {
  echo "[TAP] my_tool adapter ready. Wire your tool to call tap_emit directly."
}

tap_uninstall_my_tool() {
  echo "[TAP] my_tool adapter removed."
}
```

From your tool's hooks, source TAP and call `tap_emit`:

```sh
PLUGIN_DIR="${TAP_PLUGIN_DIR:-${HOME}/.tmux/plugins/tmux-tap}"
source "$PLUGIN_DIR/scripts/tap_helpers.sh"
source "$PLUGIN_DIR/scripts/tap_core.sh"
tap_emit "$TMUX_PANE" "running"
```

## Minimal poll adapter example

```sh
#!/usr/bin/env bash
# TAP Adapter: my_tool (poll-based)

tap_detect_my_tool() {
  local pane_cmd="$2"
  [[ "$pane_cmd" == "my-tool" ]] && return 0
  return 1
}

tap_state_my_tool() {
  # Inspect process, title, or output to determine state
  echo "done"
}

tap_process_name_my_tool() { echo "my-tool"; }

tap_install_my_tool() {
  echo "[TAP] my_tool adapter ready."
}

tap_uninstall_my_tool() {
  echo "[TAP] my_tool adapter removed."
}
```
