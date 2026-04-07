#!/usr/bin/env bash
# TAP duration — outputs human-readable time since last state change.
# Usage: tap-duration.sh <pane_id>
# Returns empty string if pane has no state or is inactive.

pane_id="${1:-}"
[[ -z "$pane_id" ]] && exit 0

state=$(tmux show-options -pqv -t "$pane_id" @tap_state 2>/dev/null)
[[ -z "$state" || "$state" == "inactive" ]] && exit 0

since=$(tmux show-options -pqv -t "$pane_id" @tap_state_since 2>/dev/null)
[[ -z "$since" ]] && exit 0

now=$(date +%s)
elapsed=$(( now - since ))
[[ "$elapsed" -lt 0 ]] && exit 0

if [[ "$elapsed" -ge 3600 ]]; then
  printf '%dh%dm' $(( elapsed / 3600 )) $(( (elapsed % 3600) / 60 ))
elif [[ "$elapsed" -ge 60 ]]; then
  printf '%dm%ds' $(( elapsed / 60 )) $(( elapsed % 60 ))
else
  printf '%ds' "$elapsed"
fi
