#!/usr/bin/env bash
# TAP Adapter: codex
#
# Push-based adapter using Codex's native hooks system (~/.codex/hooks.json).
# Hooks call tap_emit directly; the monitor loop is bypassed entirely.
#
# Setup: run `tap.tmux install codex` (or source tap.tmux which calls it automatically).
# This merges the required hooks into ~/.codex/hooks.json.

tap_push_capable_codex() { return 0; }
tap_process_name_codex() { echo "codex"; }

tap_install_codex() {
  local hooks_file="${HOME}/.codex/hooks.json"
  local config_file="${HOME}/.codex/config.toml"
  local hooks_dir="${HOME}/.tmux-tap/hooks"
  local stop_hook="${hooks_dir}/tap-stop-codex.sh"

  mkdir -p "$hooks_dir" "${HOME}/.codex"

  # Enable hooks feature flag in config.toml
  if [[ ! -f "$config_file" ]] || ! grep -q 'codex_hooks' "$config_file" 2>/dev/null; then
    printf '\n[features]\ncodex_hooks = true\n' >> "$config_file"
    echo "[TAP] codex_hooks = true written to ${config_file}"
  fi

  # Write the Stop hook script
  cat > "$stop_hook" << 'STOP_HOOK'
#!/usr/bin/env bash
# TAP hook: fires on Codex Stop event.
# Reads stop JSON from stdin and emits done or asking state.
PLUGIN_DIR="${TAP_PLUGIN_DIR:-${HOME}/.tmux/plugins/tmux-tap}"
source "$PLUGIN_DIR/scripts/tap_helpers.sh" 2>/dev/null || exit 0
source "$PLUGIN_DIR/scripts/tap_core.sh"   2>/dev/null || exit 0

input=$(cat 2>/dev/null)
pane_id="${TMUX_PANE:-}"
[[ -z "$pane_id" ]] && exit 0

last_msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)
state=$(printf '%s' "$last_msg" | "$PLUGIN_DIR/scripts/tap-classify.sh")
state="${state:-done}"

tap_emit "$pane_id" "$state"
exit 0
STOP_HOOK
  chmod +x "$stop_hook"

  # Check if already installed
  if [[ -f "$hooks_file" ]] && grep -q '"tap_owned"' "$hooks_file" 2>/dev/null; then
    echo "[TAP] codex hooks already present in ${hooks_file}"
    return 0
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    echo "[TAP] WARNING: jq not found. Install jq to use the codex adapter."
    return 1
  fi

  # Validate hooks.json before modification
  if [[ -f "$hooks_file" ]] && ! jq empty "$hooks_file" 2>/dev/null; then
    echo "[TAP] ERROR: ${hooks_file} is not valid JSON, aborting install"
    return 1
  fi

  # Warn if existing non-TAP hook groups would be merged over
  local conflicts=""
  for hook_key in UserPromptSubmit PreToolUse Stop; do
    if jq -e --arg k "$hook_key" \
        '(.hooks[$k] // []) | any(.tap_owned != true)' \
        "$hooks_file" &>/dev/null 2>&1; then
      conflicts="${conflicts:+$conflicts, }${hook_key}"
    fi
  done
  if [[ -n "$conflicts" ]]; then
    echo "[TAP] WARNING: existing non-TAP hooks found in: ${conflicts}"
    echo "[TAP]          Merge them manually, then re-run install."
    return 1
  fi

  # Merge hooks using jq
  local tmp
  tmp=$(mktemp)
  local hooks_json
  hooks_json=$(_tap_codex_hooks_json "$stop_hook")

  local base='{}'
  [[ -f "$hooks_file" ]] && base=$(cat "$hooks_file")

  if printf '%s' "$base" | \
      jq --argjson hooks "$hooks_json" '. * {hooks: (.hooks // {} | . * $hooks)}' \
      > "$tmp" 2>/dev/null; then
    mv "$tmp" "$hooks_file"
    echo "[TAP] codex hooks installed into ${hooks_file}"
  else
    rm -f "$tmp"
    echo "[TAP] WARNING: failed to merge hooks into ${hooks_file}"
    return 1
  fi
}

tap_uninstall_codex() {
  local hooks_file="${HOME}/.codex/hooks.json"
  if ! command -v jq &>/dev/null; then
    echo "[TAP] Remove tap_owned hook groups from ${hooks_file} manually"
    return 1
  fi
  if [[ -f "$hooks_file" ]]; then
    local tmp
    tmp=$(mktemp)
    jq '
      def rm_tap: map(select(.tap_owned != true));
      .hooks |= (
        if .UserPromptSubmit then .UserPromptSubmit |= rm_tap else . end |
        if .PreToolUse       then .PreToolUse       |= rm_tap else . end |
        if .Stop             then .Stop             |= rm_tap else . end |
        if (.UserPromptSubmit // [] | length) == 0 then del(.UserPromptSubmit) else . end |
        if (.PreToolUse       // [] | length) == 0 then del(.PreToolUse)       else . end |
        if (.Stop             // [] | length) == 0 then del(.Stop)             else . end
      )
    ' "$hooks_file" > "$tmp" && mv "$tmp" "$hooks_file" || rm -f "$tmp"
  fi
  rm -f "${HOME}/.tmux-tap/hooks/tap-stop-codex.sh" "${HOME}/.tmux-tap/hooks/tap-run-codex.sh"
  echo "[TAP] codex hooks removed from ${hooks_file}"
}

_tap_codex_hooks_json() {
  local stop_hook="$1"
  local emit="${HOME}/.tmux-tap/hooks/tap-emit.sh"
  local run_cmd="${emit} running"
  jq -n \
    --arg stop "$stop_hook" \
    --arg run  "$run_cmd" \
    '{
      "UserPromptSubmit": [
        {"matcher": "", "tap_owned": true, "hooks": [{"type": "command", "command": $run}]}
      ],
      "PreToolUse": [
        {"matcher": "Bash", "tap_owned": true, "hooks": [{"type": "command", "command": $run}]}
      ],
      "Stop": [
        {"matcher": "", "tap_owned": true, "hooks": [{"type": "command", "command": $stop}]}
      ]
    }'
}
