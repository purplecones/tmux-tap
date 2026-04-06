#!/usr/bin/env bash
# TAP Adapter Template
#
# Copy this file to adapters/<name>.sh (or ~/.tmux-tap/adapters/<name>.sh for local adapters).
# Replace every occurrence of <name> with your adapter's lowercase identifier.
# Then add '<name>' to @tap_adapters in your .tmux.conf.
#
# Poll adapters require: tap_detect_<name>, tap_state_<name>, tap_install_<name>, tap_uninstall_<name>
# Push adapters require: tap_push_capable_<name>, tap_install_<name>, tap_uninstall_<name>
#   Push adapters call tap_emit directly from tool-native hooks; detect/state are never called.

ADAPTER_NAME="<name>"

# tap_detect_<name> PANE_ID PANE_CMD PANE_PID PANE_TITLE
#
# Return 0 if this adapter owns the given pane, 1 otherwise.
# Keep cheap checks first; avoid spawning subprocesses unless necessary.
#
# Detection hierarchy (use as many tiers as needed):
#   1. Process name match    — tmux provides pane_current_command directly
#   2. Env var presence      — check TAP_PANE_${PANE_ID}_* or tool-specific markers
#   3. Child process scan    — pgrep -P PANE_PID (one subprocess)
#   4. Pane output pattern   — tmux capture-pane (expensive, opt-in only)
tap_detect_<name>() {
  local pane_id="$1"
  local pane_cmd="$2"
  local pane_pid="$3"
  local pane_title="$4"

  # Example: match by process name
  [[ "$pane_cmd" == "<tool_binary>" ]] && return 0

  # Example: match by child process
  # pgrep -P "$pane_pid" -x "<tool_binary>" &>/dev/null && return 0

  return 1
}

# tap_state_<name> PANE_ID PANE_PID PANE_TITLE
#
# Echo one of: inactive | running | thinking | plan_ready | done | asking
# Called only when tap_detect_<name> returned 0 for this pane.
tap_state_<name>() {
  local pane_id="$1"
  local pane_pid="$2"
  local pane_title="$3"

  # Example: read from a tool-written state file
  # local state_file="${HOME}/.<tooldir>/pane-states/${pane_id}"
  # [[ -f "$state_file" ]] && cat "$state_file" && return

  # Default fallback
  echo "inactive"
}

# tap_install_<name>
#
# Called once when tap.tmux loads (or via `tap.tmux install <name>`).
# Set up any tool-side plumbing: merge config, create directories, etc.
tap_install_<name>() {
  echo "[TAP] <name>: nothing to install"
}

# tap_uninstall_<name>
#
# Reverses tap_install_<name>.
tap_uninstall_<name>() {
  echo "[TAP] <name>: nothing to uninstall"
}

# tap_process_name_<name>
#
# Echo the expected pane_current_command when this agent is running (e.g. "claude").
# Used by the stale-state reaper to detect when an agent has exited without
# firing its stop hook. Required for push adapters; optional for poll adapters.
#
# tap_process_name_<name>() { echo "<tool_binary>"; }

# tap_push_capable_<name>  (makes this a push adapter)
#
# Define this (returning 0) to tell the monitor to skip polling this adapter.
# Push adapters call tap_emit directly from tool-native hooks; no detect/state needed.
#
# tap_push_capable_<name>() { return 0; }
