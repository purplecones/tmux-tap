# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Push adapter hooks now go through `tap_emit` instead of setting `@tap_state` directly, so all event hooks (`@tap_on_agent_start`, `@tap_on_agent_thinking`, etc.) fire correctly

### Added
- `@tap_state_since` pane option — epoch timestamp of last state change, set automatically by `tap_emit`
- `@tap_idle_timeout` option — seconds before firing idle event (default `0` = disabled)
- `@tap_on_agent_idle` event — fires once when a pane stays in `done` or `asking` longer than `@tap_idle_timeout`
- `scripts/tap-emit.sh` — shared emit wrapper generated at plugin load; used by all push adapter hooks
- `scripts/tap-classify.sh` — shared heuristic for determining `done` vs `asking` from assistant message text
- `scripts/tap-duration.sh` — outputs human-readable duration since last state change (e.g. `3m12s`)

### Changed
- Claude Code, Codex, and OpenCode adapter hooks now call `tap-emit.sh` instead of `tmux set-option` directly
- Stop hooks for all adapters now delegate to `tap-classify.sh` instead of inlining the asking heuristic
- Codex adapter no longer generates `tap-run-codex.sh` (superseded by `tap-emit.sh`)

### Migration
- After upgrading, re-source tmux config and reinstall adapter hooks:
  ```sh
  tmux source ~/.tmux.conf
  tap.tmux uninstall claude_code && tap.tmux install claude_code
  ```

## [0.1.0] - 2026-04-06

### Added
- Core state machine (`tap_emit`, `tap_get_state`, `tap_cleanup_pane`)
- Background monitor with poll loop for non-push adapters
- Push adapter support (`tap_push_capable_<name>`) for zero-latency state updates
- Stale-state reaper for push adapters via `tap_process_name_<name>`
- Pane-exit cleanup hook
- Claude Code adapter (push-based, wires into `settings.json` hooks)
- Codex adapter (push-based, wires into `hooks.json` hooks)
- OpenCode adapter (push-based, wires into JS plugin)
- Adapter template (`adapters/_template.sh`)
- User-configurable event hooks (`@tap_on_agent_start`, `@tap_on_agent_done`, etc.)
- Adapter spec documentation (`ADAPTER_SPEC.md`)

[0.1.0]: https://github.com/purplecones/tmux-tap/releases/tag/v0.1.0
