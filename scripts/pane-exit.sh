#!/usr/bin/env bash
# Called via pane-exited hook. Cleans up state for the exited pane.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$PLUGIN_DIR/scripts/tap_helpers.sh"
source "$PLUGIN_DIR/scripts/tap_core.sh"

PANE_ID="${1:-$TMUX_PANE}"
[[ -z "$PANE_ID" ]] && exit 0

tap_cleanup_pane "$PANE_ID"
