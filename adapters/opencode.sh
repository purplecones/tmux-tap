#!/usr/bin/env bash
# TAP Adapter: opencode
#
# Push-based adapter for OpenCode (sst/opencode). Installs a JavaScript plugin
# into ~/.config/opencode/opencode.json that calls tap_emit directly via tmux,
# so the monitor loop is bypassed entirely. Effective latency: ~0ms.
#
# Setup: run `tap.tmux install opencode` (or add opencode to @tap_adapters).
# Requires: jq (for config merging)

tap_push_capable_opencode() { return 0; }
tap_process_name_opencode() { echo "opencode"; }

tap_install_opencode() {
  local config_dir="${HOME}/.config/opencode"
  local config_file="${config_dir}/opencode.json"
  local hooks_dir="${HOME}/.tmux-tap/hooks"
  local plugin_file="${hooks_dir}/tap-opencode.js"

  mkdir -p "$hooks_dir" "$config_dir"

  # Seed initial state for any opencode panes already running.
  if command -v tmux &>/dev/null; then
    while IFS='|' read -r pane_id pane_cmd; do
      [[ "$pane_cmd" != "opencode" ]] && continue
      local current
      current=$(tmux show-options -pqv -t "$pane_id" @tap_state 2>/dev/null)
      [[ -n "$current" ]] && continue
      tap_emit "$pane_id" "done"
    done < <(tmux list-panes -a -F "#{pane_id}|#{pane_current_command}" 2>/dev/null)
  fi

  # Write the JS plugin.
  # OpenCode runs this in-process via Bun; $`...` executes shell commands.
  # TMUX_PANE is captured at plugin load time (when opencode starts in the pane).
  cat > "$plugin_file" << 'PLUGIN_JS'
// TAP OpenCode plugin — tracks agent state in tmux via @tap_state pane option.
// tap_owned: true  (used by tap_uninstall_opencode to identify this file)
export default function TapPlugin({ $ }) {
  const paneId = process.env.TMUX_PANE
  if (!paneId || !process.env.TMUX) return {}

  const emit = (state) =>
    $`tmux set-option -p -t ${paneId} @tap_state ${state}`.catch(() => {})

  // Accumulate streaming assistant text for the text-based asking heuristic.
  let lastText = ""
  // Track whether a native question is active (question.asked fired).
  let nativeAsking = false

  return {
    // User submitted a prompt — reset state and mark running.
    "chat.message": () => {
      lastText = ""
      nativeAsking = false
      emit("running")
    },

    // Tool calls — still running.
    "tool.execute.before": () => emit("running"),

    event: ({ event }) => {
      switch (event?.type) {

        // Native question tool — explicit asking signal, no heuristic needed.
        case "question.asked":
          nativeAsking = true
          emit("asking")
          break

        // User answered the native question — agent continues.
        case "question.replied":
          nativeAsking = false
          emit("running")
          break

        // Streaming text delta — accumulate for heuristic fallback.
        case "message.part.delta": {
          const delta = event?.part?.text ?? event?.part?.delta ?? event?.delta ?? ""
          if (typeof delta === "string" && delta) lastText += delta
          break
        }

        // Turn ended — emit done or asking based on heuristic (if no native question).
        case "server.instance.disposed":
          if (nativeAsking) break  // already in asking state
          const trimmed = lastText.trimEnd()
          const isAsking =
            trimmed.endsWith("?") ||
            /\n\s*\d+\.\s/.test(trimmed.split("\n").slice(-5).join("\n"))
          emit(isAsking ? "asking" : "done")
          break
      }
    },
  }
}
PLUGIN_JS

  # Check if already installed
  if [[ -f "$config_file" ]] && grep -q 'tap-opencode' "$config_file" 2>/dev/null; then
    echo "[TAP] opencode plugin already present in ${config_file}"
    return 0
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    echo "[TAP] WARNING: jq not found. Add the following to ${config_file} manually:"
    echo "  \"plugin\": [\"${plugin_file}\"]"
    return 1
  fi

  # Create config file if missing
  if [[ ! -f "$config_file" ]]; then
    echo '{}' > "$config_file"
  fi

  # Validate config file
  if ! jq empty "$config_file" 2>/dev/null; then
    echo "[TAP] ERROR: ${config_file} is not valid JSON, aborting install"
    return 1
  fi

  # Merge plugin entry; idempotent — skips if a tmux-tap entry already present
  local tmp
  tmp=$(mktemp)
  if jq --arg p "$plugin_file" '
      if (.plugin // [] | map(select(contains("tmux-tap"))) | length) > 0
      then .
      else .plugin = ((.plugin // []) + [$p])
      end' \
      "$config_file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$config_file"
    echo "[TAP] opencode plugin installed into ${config_file}"
  else
    rm -f "$tmp"
    echo "[TAP] WARNING: failed to update ${config_file}. Add manually:"
    echo "  \"plugin\": [\"${plugin_file}\"]"
    return 1
  fi
}

tap_uninstall_opencode() {
  local config_file="${HOME}/.config/opencode/opencode.json"
  local plugin_file="${HOME}/.tmux-tap/hooks/tap-opencode.js"

  if ! command -v jq &>/dev/null; then
    echo "[TAP] Remove the tap-opencode.js entry from ${config_file} manually"
    return 1
  fi

  if [[ -f "$config_file" ]]; then
    local tmp
    tmp=$(mktemp)
    jq '
      if .plugin then .plugin |= map(select(contains("tmux-tap") | not)) else . end |
      if (.plugin // [] | length) == 0 then del(.plugin) else . end
    ' "$config_file" > "$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
  fi

  rm -f "$plugin_file"
  echo "[TAP] opencode plugin removed from ${config_file}"
}
