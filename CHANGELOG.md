# Changelog

All notable changes to Hecate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Hecate branding (renamed from lab-bootstrap).
- CI workflow for shell test suite.
- TAP-style shell test harness with 96 assertions across 6 test files.
- `update-lab.sh` — safe platform update orchestrator.
- `verify-host.sh` — read-only pre-flight host checks.
- Empusa workspace integration in `launch-lab.sh` and `create-workspace.sh`.
- Workspace profiles: `htb`, `build`, `research`, `internal`.
- Binary sync via GitHub Releases API with `file(1)` validation.
- GPU and host-network compose overlays.
- Full documentation suite (`docs/`).

### Changed

- `labctl` now dispatches `update`, `verify`, and `workspace` subcommands.
- `launch-lab.sh` delegates workspace creation to Empusa when available.
- `create-workspace.sh` supports `--profile` flag for Empusa profiles.
