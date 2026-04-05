# Changelog

All notable changes to Hecate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-04-05

### Added

- Hecate branding (renamed from lab-bootstrap).
- CI workflow for shell test suite.
- TAP-style shell test harness with 96 assertions across 6 test files.
- `update-lab.sh` - safe platform update orchestrator.
- `verify-host.sh` - read-only pre-flight host checks.
- Empusa workspace integration in `launch-lab.sh` and `create-workspace.sh`.
- Workspace profiles: `htb`, `build`, `research`, `internal`.
- Binary sync via GitHub Releases API with `file(1)` validation.
- GPU and host-network compose overlays.
- Full documentation suite (`docs/`).
- Contract-pinning tests: htb profile dirs, ALL_EVENTS validation,
  make_event round-trips, fallback degradation assertions for launch-lab
  and create-workspace.

### Changed

- `labctl` now dispatches `update`, `verify`, and `workspace` subcommands.
- `launch-lab.sh` delegates workspace creation to Empusa when available.
- `create-workspace.sh` supports `--profile` flag for Empusa profiles.

### Fixed

- Documentation drift: workspace root, event names, profile list, and
  tmux profile paths now match Empusa v2.2.1 contract.
