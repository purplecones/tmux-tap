#!/usr/bin/env bash
# TAP helpers — shared utilities sourced by all scripts

get_tmux_option() {
  local option="$1"
  local default="${2:-}"
  local value
  value=$(tmux show-options -gqv "$option" 2>/dev/null)
  echo "${value:-$default}"
}

tap_log() {
  local level="$1"
  shift
  local msg="$*"
  local logfile
  logfile=$(get_tmux_option "@tap_log_file" "")
  [[ -n "$logfile" ]] && printf '[%s] TAP %s: %s\n' "$(date +%T)" "$level" "$msg" >> "$logfile"
}

tap_refresh() {
  tmux refresh-client -S 2>/dev/null || true
}
