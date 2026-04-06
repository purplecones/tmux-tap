#!/usr/bin/env bash
# TAP monitor — background polling loop for non-push adapters

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$PLUGIN_DIR/scripts/tap_helpers.sh"
source "$PLUGIN_DIR/scripts/tap_core.sh"

POLL_INTERVAL="${1:-2}"

# Load adapters from config, skip push-capable ones
_load_poll_adapters() {
  POLL_ADAPTERS=()
  local adapters
  adapters=$(get_tmux_option "@tap_adapters" "claude_code")

  for adapter in $adapters; do
    local file=""
    if [[ -f "$adapter" ]]; then
      file="$adapter"
    elif [[ -f "${HOME}/.tmux-tap/adapters/${adapter}.sh" ]]; then
      file="${HOME}/.tmux-tap/adapters/${adapter}.sh"
    elif [[ -f "${PLUGIN_DIR}/adapters/${adapter}.sh" ]]; then
      file="${PLUGIN_DIR}/adapters/${adapter}.sh"
    fi

    if [[ -n "$file" ]]; then
      # shellcheck source=/dev/null
      source "$file"
      # Skip if push-capable
      if declare -f "tap_push_capable_${adapter}" &>/dev/null; then
        tap_log "INFO" "monitor: skipping push-capable adapter '$adapter'"
        continue
      fi
      POLL_ADAPTERS+=("$adapter")
    else
      tap_log "WARN" "monitor: adapter '$adapter' not found"
    fi
  done
}

_poll_once() {
  while IFS=$'\t' read -r pane_id pane_pid pane_cmd pane_title; do
    [[ -z "$pane_id" ]] && continue

    for adapter in "${POLL_ADAPTERS[@]}"; do
      local detect_fn="tap_detect_${adapter}"
      local state_fn="tap_state_${adapter}"

      if declare -f "$detect_fn" &>/dev/null; then
        if "$detect_fn" "$pane_id" "$pane_cmd" "$pane_pid" "$pane_title" 2>/dev/null; then
          local state
          state=$("$state_fn" "$pane_id" "$pane_pid" "$pane_title" 2>/dev/null)
          state="${state:-inactive}"
          tap_emit "$pane_id" "$state"
          break  # first matching adapter wins
        fi
      fi
    done
  done < <(tmux list-panes -a -F $'#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}' 2>/dev/null)
}

# Store PID for cleanup
tmux setenv -g TAP_MONITOR_PID "$$" 2>/dev/null

trap 'exit 0' TERM INT

while true; do
  _load_poll_adapters

  if [[ "${#POLL_ADAPTERS[@]}" -eq 0 ]]; then
    # No poll adapters — sleep and check again (user may add one later)
    sleep 10
    continue
  fi

  _poll_once
  sleep "$POLL_INTERVAL"
done
