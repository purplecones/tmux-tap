#!/usr/bin/env bash
# TAP monitor — background polling loop for non-push adapters

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$PLUGIN_DIR/scripts/tap_helpers.sh"
source "$PLUGIN_DIR/scripts/tap_core.sh"

POLL_INTERVAL="${1:-2}"

# Load adapters from config; collect poll adapters and known process names
_load_adapters() {
  POLL_ADAPTERS=()
  KNOWN_AGENT_CMDS=""
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

      # Collect process name for the stale-state reaper
      if declare -f "tap_process_name_${adapter}" &>/dev/null; then
        local pname
        pname=$("tap_process_name_${adapter}")
        KNOWN_AGENT_CMDS="${KNOWN_AGENT_CMDS:+$KNOWN_AGENT_CMDS|}${pname}"
      fi

      # Skip push-capable adapters from polling
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

# Reap stale state from panes where the agent process has exited.
# Covers push adapters (which skip polling) and any other edge case
# where the stop hook didn't fire (kill -9, OOM, crash).
_reap_stale() {
  [[ -z "$KNOWN_AGENT_CMDS" ]] && return 0

  while IFS=$'\t' read -r pane_id pane_cmd tap_state; do
    [[ -z "$pane_id" ]] && continue
    [[ -z "$tap_state" || "$tap_state" == "inactive" ]] && continue

    # Agent process still running — nothing to reap
    if [[ "$pane_cmd" =~ ^($KNOWN_AGENT_CMDS)$ ]]; then
      continue
    fi

    tap_log "INFO" "reaper: pane $pane_id state '$tap_state' but cmd='$pane_cmd' — resetting to inactive"
    tap_emit "$pane_id" "inactive"
  done < <(tmux list-panes -a -F $'#{pane_id}\t#{pane_current_command}\t#{@tap_state}' 2>/dev/null)
}

# Fire @tap_on_agent_idle when a pane has been in done/asking longer than @tap_idle_timeout.
_check_idle() {
  local timeout
  timeout=$(get_tmux_option "@tap_idle_timeout" "0")
  [[ "$timeout" -le 0 ]] 2>/dev/null && return 0

  local now
  now=$(date +%s)

  while IFS=$'\t' read -r pane_id tap_state state_since idle_fired; do
    [[ -z "$pane_id" ]] && continue

    # Only idle-check attention states
    [[ "$tap_state" != "done" && "$tap_state" != "asking" ]] && continue

    # Already fired for this state
    [[ "$idle_fired" == "1" ]] && continue

    # No timestamp yet
    [[ -z "$state_since" ]] && continue

    # Check elapsed time
    local elapsed=$(( now - state_since ))
    if [[ "$elapsed" -ge "$timeout" ]]; then
      tap_log "INFO" "idle: pane $pane_id in '$tap_state' for ${elapsed}s (timeout=${timeout}s)"
      tmux set-option -p -t "$pane_id" @tap_idle_fired 1 2>/dev/null
      _tap_fire "$pane_id" "agent_idle"
    fi
  done < <(tmux list-panes -a -F $'#{pane_id}\t#{@tap_state}\t#{@tap_state_since}\t#{@tap_idle_fired}' 2>/dev/null)
}

# Store PID for cleanup
tmux setenv -g TAP_MONITOR_PID "$$" 2>/dev/null

trap 'exit 0' TERM INT

while true; do
  _load_adapters

  # Always reap stale state (covers push adapters and ungraceful exits)
  _reap_stale

  if [[ "${#POLL_ADAPTERS[@]}" -gt 0 ]]; then
    _poll_once
  fi

  _check_idle

  sleep "$POLL_INTERVAL"
done
