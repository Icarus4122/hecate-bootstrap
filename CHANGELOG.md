# Changelog

All notable changes to Hecate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.2.0] - 2026-04-26

### Added

- **`scripts/lib/ui.sh`** - Canonical UI primitives library defining
  `ui_pass`, `ui_fail`, `ui_warn`, `ui_info`, `ui_action`, `ui_fix`,
  `ui_note`, `ui_banner`, `ui_section`, `ui_kv`, `ui_summary_line`,
  `ui_next_block`, and `ui_error_block`. TTY-aware ANSI colouring
  with `NO_COLOR=1` honoured.
- **`docs/dev/validation-model.md`** - Documents the production
  validation workflow (contract, platform, release sanity).
- **CI workflows** - New GitHub Actions for compose lint, contract
  validation, platform validation, and `.env` / labctl integrity.
- **Dev helper scripts** - `scripts/dev/ci-syntax-check.sh`,
  `ci-repo-integrity.sh`, `ci-compose-lint.sh`, `ci-contract-check.sh`,
  and `release-sanity.sh` for local pre-release validation.
- **Non-interactive launch mode** - `launch-lab.sh` now supports a
  scriptable / CI-friendly path.
- **E2E hardening** - Stage 5 (Empusa) reworked into focused contract
  assertions; helpers and scenarios updated to assert on canonical
  markers and exit codes rather than glyph output.

### Changed

- **Canonical UI vocabulary migration** - Operator-facing scripts
  (`labctl`, `guide.sh`, `install-empusa.sh`, `setup-nvidia.sh`,
  `lib/compose.sh`, dev / CI scripts, e2e harness) now emit
  `[PASS]` / `[FAIL]` / `[WARN]` / `[INFO]` / `[ACTION]` instead of
  the legacy glyph set (`✓`, `✗`, `[!]`, `[*]`, `[=]`).
- **`docs/dev/output-style-guide.md`** - Rewritten Status Markers and
  related sections to match the canonical vocabulary; calls out
  `scripts/lib/ui.sh` as the runtime source of truth.
- **`docs/dev/ux-audit.md`** - Marked as a historical 2026-04-05
  audit; recommendations now expressed in the canonical vocabulary.

### Fixed

- **Builder bind mount** - Compose builder service mount path corrected.
- **CI compose lint** - Detects both `docker compose` and
  `docker-compose`; clearer failure messages.
- **`.env` and labctl integrity** - Repo-integrity check now flags
  missing or malformed `.env` and labctl entry points.



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
