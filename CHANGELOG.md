# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Contract entries are called out separately from app changes, because they are
the only ones that can break a third-party provider.

## [Unreleased]

## [0.1.0]

Initial public release.

### Added

- Menu bar panel showing what a provider reports: state, a summary line, plain
  label/value lines, numeric metrics with a sparkline history, and repeating
  items with their own metrics and actions.
- The menu bar glyph reflects the worst state across every provider, so one
  glance answers whether anything needs attention.
- Provider discovery from `~/.config/maester/providers/`, polled on
  `capabilities.refresh` (default 5s, 4s timeout) or run as a supervised
  `stream` child with backoff and a fallback to polling.
- `mac` provider: CPU, GPU, memory, storage, and the top processes, streamed
  from a single long-lived `iostat`.
- `apps` provider: running applications, hang detection, and quit / force
  quit actions.
- Icon resolution for `bundle:`, `path:`, `pid:`, `sf:`, and `asset:` schemes,
  degrading to a plain state mark rather than rendering blank when a symbol
  cannot be resolved.
- Provider optionality: a `disabled` list in `config.json`, toggled from the
  gear menu or by hand, reread on the same schedule as provider discovery.
- `maester-doctor`, validating a provider's output against the contract and
  checking its file and directory permissions.
- An opt-in "Open at Login" toggle using `SMAppService`.
- Recovery on sleep/wake: streams restart and providers re-poll immediately
  on wake rather than waiting out their normal schedule.
- `--providers`, `--enable`/`--disable`, and `MAESTER_DEBUG` diagnostics for
  inspecting and adjusting the running app from a shell.
- No telemetry and no network requests made by the app itself.

### Contract

- `schema: 1`. See [CONTRACT.md](CONTRACT.md) for the full shape of a
  provider report and the permission model providers are checked against.

[Unreleased]: https://github.com/kishorekanthan/maester/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kishorekanthan/maester/releases/tag/v0.1.0
