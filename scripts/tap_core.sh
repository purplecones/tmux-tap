#!/usr/bin/env bash
# TAP core — state machine and event dispatch

TAP_VALID_STATES="inactive running thinking plan_ready done asking"

# Map state → event name
_tap_state_to_event() {
  case "$1" in
    running)    echo "agent_thinking" ;;
    thinking)   echo "agent_thinking" ;;
    plan_ready) echo "plan_ready"     ;;
    done)       echo "agent_done"     ;;
    asking)     echo "asking"         ;;
    *)          echo ""               ;;
  esac
}

# tap_emit <pane_id> <new_state>
# Core dispatch function. Writes state to all channels and fires event handlers.
tap_emit() {
  local pane_id="$1"
  local new_state="$2"

  # Validate state
  if [[ " $TAP_VALID_STATES " != *" $new_state "* ]]; then
    tap_log "WARN" "tap_emit: unknown state '$new_state' for pane $pane_id"
    return 1
  fi

  # Read current state
  local old_state
  old_state=$(tmux show-options -pqv -t "$pane_id" @tap_state 2>/dev/null)
  old_state="${old_state:-inactive}"

  # No-op if unchanged
  [[ "$new_state" == "$old_state" ]] && return 0

  tap_log "INFO" "pane $pane_id: $old_state → $new_state"

  # Pane-scoped option — readable as #{@tap_state} in format strings
  tmux set-option -p -t "$pane_id" @tap_state "$new_state" 2>/dev/null

  # Track when this state was entered (epoch seconds) and reset idle flag
  tmux set-option -p -t "$pane_id" @tap_state_since "$(date +%s)" 2>/dev/null
  tmux set-option -pu -t "$pane_id" @tap_idle_fired 2>/dev/null

  # Refresh status bar
  tap_refresh

  # Fire lifecycle events
  if [[ "$old_state" == "inactive" && "$new_state" != "inactive" ]]; then
    _tap_fire "$pane_id" "agent_start"
  fi
  if [[ "$new_state" == "inactive" && "$old_state" != "inactive" ]]; then
    _tap_fire "$pane_id" "agent_stop"
    return 0
  fi

  # Fire state-specific event
  local event
  event=$(_tap_state_to_event "$new_state")
  [[ -n "$event" ]] && _tap_fire "$pane_id" "$event"
}

# _tap_fire <pane_id> <event>
# Executes the user-defined handler for an event, if set.
_tap_fire() {
  local pane_id="$1"
  local event="$2"
  local handler
  handler=$(tmux show-options -gqv "@tap_on_${event}" 2>/dev/null)
  [[ -z "$handler" ]] && return 0
  tap_log "INFO" "firing $event on pane $pane_id"
  # run-shell expands tmux format strings (#{pane_id}, etc.) at call time
  tmux run-shell -t "$pane_id" "$handler" 2>/dev/null || true
}

# tap_get_state <pane_id>
# Returns current state for a pane (defaults to inactive).
tap_get_state() {
  local pane_id="$1"
  local state
  state=$(tmux show-options -pqv -t "$pane_id" @tap_state 2>/dev/null)
  echo "${state:-inactive}"
}

# tap_cleanup_pane <pane_id>
# Called when a pane exits. Clears all state.
tap_cleanup_pane() {
  local pane_id="$1"
  local old_state
  old_state=$(tap_get_state "$pane_id")

  # Fire agent_stop if agent was active
  if [[ "$old_state" != "inactive" ]]; then
    tap_emit "$pane_id" "inactive"
  fi

  # Clear idle-related pane options
  tmux set-option -pu -t "$pane_id" @tap_state_since 2>/dev/null
  tmux set-option -pu -t "$pane_id" @tap_idle_fired 2>/dev/null
}
