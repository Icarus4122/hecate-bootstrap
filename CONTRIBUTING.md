# Contributing to Hecate

Thanks for your interest in Hecate! Here is how you can help.

## Quick Start

1. Fork & clone the repository.
2. Ensure you have Bash 5.x and Docker with the Compose plugin.
3. Create a feature branch:

   ```bash
   git checkout -b feature/my-feature
   ```

4. Identify the right area for your change:

   | Area | Path | Purpose |
   | ---- | ---- | ------- |
   | Dispatcher | `labctl` | Thin command router — all subcommands dispatch to `scripts/` |
   | Bootstrap | `scripts/bootstrap-host.sh` | One-time host setup |
   | Compose | `compose/` | Container definitions and overlays |
   | Images | `docker/` | Dockerfiles and rootfs layers |
   | Lifecycle | `scripts/launch-lab.sh`, `update-lab.sh` | Launch and update flows |
   | Empusa integration | `scripts/install-empusa.sh`, `create-workspace.sh` | Workspace delegation |
   | Shared lib | `scripts/lib/compose.sh` | Compose file-stacking helper |
   | Templates | `templates/*.md` | Workspace report/methodology templates |
   | Tests | `tests/` | TAP-style shell test suite |

5. Run the test suite:

   ```bash
   bash tests/run-all.sh
   ```

6. Submit a pull request with a clear description.

## Code Style

- **Bash** — all scripts target Bash 5.x with `set -euo pipefail`.
- Use `"$var"` quoting everywhere.  No unquoted expansions.
- Use `[[ ]]` for conditionals, not `[ ]`.
- Keep functions short.  If a function exceeds ~40 lines, extract a helper.
- Scripts should be runnable standalone and testable in isolation.
- Use `info`, `die`, `_pass`, `_warn`, `_fail` helpers from existing scripts
  rather than inventing new output patterns.

## Documentation Style

These rules apply to all markdown files in both Empusa and Hecate.
Contract docs (`docs/empusa.md`, profile tables, env-var tables) **must** stay
aligned with source code and test assertions — update them in the same commit.

### Badges

- Use `shields.io` flat badges at the top of `README.md` only.
- One line per badge.  No blank lines between badges.
- Link each badge to something actionable (CI page, section anchor, license file).

### Mermaid diagrams

- Use only for: architecture boundaries, lifecycle flows, dispatch graphs, topology.
- Do **not** use FA icons (`fa:fa-*`) — they don't render on GitHub.
- Do **not** add `classDef` / `class` blocks — GitHub ignores custom styles.
- Keep nodes ≤ 2 lines of text.  If a node needs 3+ lines, it belongs in a table.
- Node IDs should map to real files or components (`BUS`, `LABCTL`, not `box1`).

### Tables

- Prefer tables over bullet lists for structured data (flags, variables, paths).
- Environment variables: include **Type**, **Default**, and **Used by** columns.
- CLI flags: include **Type** and **Default** columns.
- Profile/contract tables: reference the source-of-truth file in a caption or header.

Example (env var):

```markdown
| Variable | Type | Default | Used by |
|----------|------|---------|---------|
| `LAB_GPU` | `0\|1` | `0` | launch-lab.sh, lib/compose.sh |
```

### Code fences

- Always tag the language: `` ```bash ``, `` ```python ``, `` ```text ``.
- Use `text` for static output, directory trees, and non-executable content.
- Separate commands from their output — don't paste both in one fence.

### Paths

- Use backtick-wrapped paths: `` `empusa/workspace.py` ``, `` `${LAB_ROOT}/tools/` ``.
- Use forward slashes in docs, even if the host is Windows.
- Prefer `${VAR}` over hardcoded absolute paths when a variable exists.

### Terminology

| Term | Meaning | Do NOT use |
| ------ | --------- | ----------- |
| workspace | An Empusa-managed engagement directory | environment, env |
| profile | A workspace profile (`htb`, `build`, `research`, `internal`) | template, layout |
| Hecate | The platform bootstrap product | lab-bootstrap |
| Empusa | The workspace engine | orchestrator |
| `labctl` | The Hecate CLI dispatcher | lab script |

### Source-of-truth discipline

- Profile definitions (dirs, templates) → `empusa/workspace.py → PROFILES`.
- Template files → `hecate-bootstrap/templates/*.md`.
- Delegation logic → `hecate-bootstrap/scripts/create-workspace.sh`, `launch-lab.sh`.
- If you change a contract surface, update the matching doc table **and** the
  test assertion in the same PR.

## Reporting Issues

Open a GitHub Issue with:

- Host OS and version
- Docker / Compose version (`docker compose version`)
- Hecate branch / commit
- Steps to reproduce
- Full terminal output (if applicable)

## License

By contributing you agree that your contributions will be licensed under the
[GPL-3.0-or-later](LICENSE) license.
