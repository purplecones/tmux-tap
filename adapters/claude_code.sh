#!/usr/bin/env bash
# TAP Adapter: claude_code
#
# Push-based adapter. Claude Code's settings.json hooks call tap_emit directly,
# so the monitor loop is bypassed entirely. Effective latency: ~0ms.
#
# Setup: run `tap.tmux install claude_code` (or source tap.tmux which calls it automatically).
# This merges the required hooks into ~/.claude/settings.json.

tap_push_capable_claude_code() { return 0; }
tap_process_name_claude_code() { echo "claude"; }

tap_install_claude_code() {
  local settings="${HOME}/.claude/settings.json"
  local hooks_dir="${HOME}/.tmux-tap/hooks"
  local stop_hook="${hooks_dir}/tap-stop.sh"

  mkdir -p "$hooks_dir"

  # Seed initial state for any claude panes already running.
  # Without this, panes that were waiting before install show no state until the next hook fires.
  if command -v tmux &>/dev/null; then
    while IFS='|' read -r pane_id pane_cmd; do
      [[ "$pane_cmd" != "claude" ]] && continue
      local current
      current=$(tmux show-options -pqv -t "$pane_id" @tap_state 2>/dev/null)
      [[ -n "$current" ]] && continue  # already has state, don't overwrite
      tap_emit "$pane_id" "done"
    done < <(tmux list-panes -a -F "#{pane_id}|#{pane_current_command}" 2>/dev/null)
  fi

  # Write the Stop hook script
  cat > "$stop_hook" << 'STOP_HOOK'
#!/usr/bin/env bash
# TAP hook: fires on Claude Code Stop event.
# Reads stop JSON from stdin and emits done or asking state.
PLUGIN_DIR="${TAP_PLUGIN_DIR:-${HOME}/.tmux/plugins/tmux-tap}"
source "$PLUGIN_DIR/scripts/tap_helpers.sh" 2>/dev/null || exit 0
source "$PLUGIN_DIR/scripts/tap_core.sh"   2>/dev/null || exit 0

input=$(cat 2>/dev/null)
pane_id="${TMUX_PANE:-}"
[[ -z "$pane_id" ]] && exit 0

# Heuristic: if last assistant message ends with '?' or ends with a numbered list
# (last 5 lines), it's asking rather than waiting for a new prompt.
last_msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)

state="done"
if printf '%s' "$last_msg" | grep -qE '\?[[:space:]]*$'; then
    state="asking"
elif printf '%s' "$last_msg" | tail -5 | grep -qE '^[[:space:]]*[0-9]+\.[[:space:]]'; then
    # Numbered list at end of message = presenting options to choose from
    state="asking"
fi

tap_emit "$pane_id" "$state"
exit 0
STOP_HOOK
  chmod +x "$stop_hook"

  # Check if already installed
  if grep -q '"tap_' "$settings" 2>/dev/null; then
    echo "[TAP] claude_code hooks already present in ${settings}"
    return 0
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    echo "[TAP] WARNING: jq not found. Add the following hooks to ${settings} manually:"
    _tap_claude_hooks_snippet "$stop_hook"
    return 1
  fi

  # Warn if existing non-TAP hooks would be overwritten
  local conflicts=""
  for hook_key in UserPromptSubmit PreToolUse Stop; do
    if jq -e --arg k "$hook_key" \
        '(.hooks[$k] // []) | any(.tap_owned != true)' \
        "$settings" &>/dev/null; then
      conflicts="${conflicts:+$conflicts, }${hook_key}"
    fi
  done
  if [[ -n "$conflicts" ]]; then
    echo "[TAP] WARNING: existing non-TAP hooks found in: ${conflicts}"
    echo "[TAP]          Merge them manually, then re-run install."
    return 1
  fi

  # Validate settings.json before modification
  if [[ -f "$settings" ]] && ! jq empty "$settings" 2>/dev/null; then
    echo "[TAP] ERROR: ${settings} is not valid JSON, aborting install"
    return 1
  fi

  # Merge hooks using jq
  local tmp
  tmp=$(mktemp)
  local hooks_json
  hooks_json=$(_tap_claude_hooks_json "$stop_hook")

  if jq --argjson hooks "$hooks_json" '. * {hooks: (.hooks // {} | . * $hooks)}' \
      "$settings" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$settings"
    echo "[TAP] claude_code hooks installed into ${settings}"
  else
    rm -f "$tmp"
    echo "[TAP] WARNING: failed to merge hooks. Add manually:"
    _tap_claude_hooks_snippet "$stop_hook"
    return 1
  fi
}

tap_uninstall_claude_code() {
  local settings="${HOME}/.claude/settings.json"
  if ! command -v jq &>/dev/null; then
    echo "[TAP] Remove tap_ hook entries from ${settings} manually"
    return 1
  fi
  local tmp
  tmp=$(mktemp)
  jq '
    def is_tap: .tap_owned == true or ((.command? // "") | test("@tap_state|tap-stop\\.sh"));
    def rm_tap: map(select(is_tap | not));
    .hooks |= (
      if .UserPromptSubmit then .UserPromptSubmit |= rm_tap else . end |
      if .PreToolUse       then .PreToolUse       |= rm_tap else . end |
      if .Stop             then .Stop             |= rm_tap else . end |
      if (.UserPromptSubmit // [] | length) == 0 then del(.UserPromptSubmit) else . end |
      if (.PreToolUse       // [] | length) == 0 then del(.PreToolUse)       else . end |
      if (.Stop             // [] | length) == 0 then del(.Stop)             else . end
    )
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" || rm -f "$tmp"
  rm -f "${HOME}/.tmux-tap/hooks/tap-stop.sh"
  echo "[TAP] claude_code hooks removed from ${settings}"
}

_tap_claude_hooks_json() {
  local stop_hook="$1"
  local run_cmd='[ -n "$TMUX_PANE" ] && tmux set-option -p -t "$TMUX_PANE" @tap_state running 2>/dev/null; true'
  local ask_cmd='[ -n "$TMUX_PANE" ] && tmux set-option -p -t "$TMUX_PANE" @tap_state asking 2>/dev/null; true'
  local plan_cmd='[ -n "$TMUX_PANE" ] && tmux set-option -p -t "$TMUX_PANE" @tap_state plan_ready 2>/dev/null; true'
  jq -n \
    --arg stop  "$stop_hook" \
    --arg run   "$run_cmd" \
    --arg ask   "$ask_cmd" \
    --arg plan  "$plan_cmd" \
    '{
      "UserPromptSubmit": [
        {"matcher": "", "tap_owned": true, "hooks": [{"type": "command", "command": $run}]}
      ],
      "PreToolUse": [
        {"matcher": "AskUserQuestion", "tap_owned": true, "hooks": [{"type": "command", "command": $ask}]},
        {"matcher": "ExitPlanMode",    "tap_owned": true, "hooks": [{"type": "command", "command": $plan}]},
        {"matcher": "",                "tap_owned": true, "hooks": [{"type": "command", "command": $run}]}
      ],
      "Stop": [
        {"matcher": "", "tap_owned": true, "hooks": [{"type": "command", "command": $stop}]}
      ]
    }'
}

_tap_claude_hooks_snippet() {
  local stop_hook="$1"
  echo ""
  echo "  \"hooks\": {"
  echo "    \"UserPromptSubmit\": [{\"matcher\": \"\", \"tap_owned\": true, \"hooks\": [{\"type\": \"command\", \"command\": \"[ -n \\\"\$TMUX_PANE\\\" ] && tmux set-option -p -t \$TMUX_PANE @tap_state running 2>/dev/null; true\"}]}],"
  echo "    \"PreToolUse\": ["
  echo "      {\"matcher\": \"AskUserQuestion\", \"tap_owned\": true, \"hooks\": [{\"type\": \"command\", \"command\": \"[ -n \\\"\$TMUX_PANE\\\" ] && tmux set-option -p -t \$TMUX_PANE @tap_state asking 2>/dev/null; true\"}]},"
  echo "      {\"matcher\": \"ExitPlanMode\",    \"tap_owned\": true, \"hooks\": [{\"type\": \"command\", \"command\": \"[ -n \\\"\$TMUX_PANE\\\" ] && tmux set-option -p -t \$TMUX_PANE @tap_state plan_ready 2>/dev/null; true\"}]},"
  echo "      {\"matcher\": \"\",                \"tap_owned\": true, \"hooks\": [{\"type\": \"command\", \"command\": \"[ -n \\\"\$TMUX_PANE\\\" ] && tmux set-option -p -t \$TMUX_PANE @tap_state running 2>/dev/null; true\"}]}"
  echo "    ],"
  echo "    \"Stop\": [{\"matcher\": \"\", \"tap_owned\": true, \"hooks\": [{\"type\": \"command\", \"command\": \"${stop_hook}\"}]}]"
  echo "  }"
}
