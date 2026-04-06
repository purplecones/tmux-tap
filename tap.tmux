#!/usr/bin/env bash
# TAP — Tmux Agent Protocol
# TPM entry point. Sourced automatically by TPM on tmux startup.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TAP_PLUGIN_DIR="$PLUGIN_DIR"

source "$PLUGIN_DIR/scripts/tap_helpers.sh"
source "$PLUGIN_DIR/scripts/tap_core.sh"

# ── Register tmux hooks (with deduplication to handle reloads) ──────────────

# Clean up state when a pane exits
tmux set-hook -ug pane-exited 2>/dev/null
tmux set-hook -g  pane-exited \
  "run-shell '${PLUGIN_DIR}/scripts/pane-exit.sh #{pane_id}'"

# ── Load adapters ─────────────────────────────────────────────────────────────

TAP_ADAPTERS=$(get_tmux_option "@tap_adapters" "claude_code")

for adapter in $TAP_ADAPTERS; do
  adapter_file=""

  if [[ -f "$adapter" ]]; then
    adapter_file="$adapter"
  elif [[ -f "${HOME}/.tmux-tap/adapters/${adapter}.sh" ]]; then
    adapter_file="${HOME}/.tmux-tap/adapters/${adapter}.sh"
  elif [[ -f "${PLUGIN_DIR}/adapters/${adapter}.sh" ]]; then
    adapter_file="${PLUGIN_DIR}/adapters/${adapter}.sh"
  fi

  if [[ -n "$adapter_file" ]]; then
    # shellcheck source=/dev/null
    source "$adapter_file"

    # Run install hook on first load
    if declare -f "tap_install_${adapter}" &>/dev/null; then
      "tap_install_${adapter}"
    fi
  else
    echo "[TAP] Warning: adapter '${adapter}' not found" >&2
  fi
done

# ── Handle install/uninstall subcommands ──────────────────────────────────────

case "${1:-}" in
  install)
    adapter="${2:-}"
    if [[ -n "$adapter" ]] && declare -f "tap_install_${adapter}" &>/dev/null; then
      "tap_install_${adapter}"
    fi
    exit 0
    ;;
  uninstall)
    adapter="${2:-}"
    if [[ -n "$adapter" ]] && declare -f "tap_uninstall_${adapter}" &>/dev/null; then
      "tap_uninstall_${adapter}"
    fi
    exit 0
    ;;
esac

# ── Start background monitor for poll-only adapters ───────────────────────────

POLL_INTERVAL=$(get_tmux_option "@tap_poll_interval" "2")

# Kill any existing monitor process
existing_pid=$(tmux showenv -g TAP_MONITOR_PID 2>/dev/null | cut -d= -f2)
if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
  kill "$existing_pid" 2>/dev/null || true
fi

if [[ "$POLL_INTERVAL" -gt 0 ]]; then
  bash "$PLUGIN_DIR/scripts/tap_monitor.sh" "$POLL_INTERVAL" &
  disown
fi
