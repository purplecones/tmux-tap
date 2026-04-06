#!/usr/bin/env bash
# TAP: Codex push-mode wrapper
#
# Source this in your shell rc (~/.zshrc or ~/.bashrc) to enable push-mode
# for the Codex adapter. This wraps the `codex` command so TAP state is
# written immediately on state transitions instead of being polled.
#
#   source "${HOME}/.tmux/plugins/tmux-tap/install/codex_wrapper.sh"

_TAP_CODEX_STATE_DIR="${HOME}/.tmux-tap/codex/pane-states"

# Inform the monitor that codex is push-capable when this file is sourced.
# The monitor checks for this function at runtime via `declare -f`.
tap_push_capable_codex() { return 0; }

_tap_codex_write_state() {
  local state="$1"
  local pane_id="${TMUX_PANE:-}"
  [[ -z "$pane_id" ]] && return 0

  mkdir -p "$_TAP_CODEX_STATE_DIR"
  printf '%s' "$state" > "$_TAP_CODEX_STATE_DIR/$pane_id"

  local tap_core
  tap_core="${TAP_PLUGIN_DIR:-${HOME}/.tmux/plugins/tmux-tap}/scripts/tap_core.sh"
  if [[ -f "$tap_core" ]]; then
    # shellcheck source=/dev/null
    source "$tap_core"
    tap_emit "$pane_id" "$state"
  else
    # Fallback: write directly to tmux option
    tmux set-option -p -t "$pane_id" @tap_state "$state" 2>/dev/null || true
    tmux refresh-client -S 2>/dev/null || true
  fi
}

codex() {
  _tap_codex_write_state "running"
  command codex "$@"
  local exit_code=$?
  _tap_codex_write_state "done"
  return $exit_code
}
