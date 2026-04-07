# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
