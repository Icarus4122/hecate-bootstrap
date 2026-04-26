# Validation Model

How Hecate's test and CI infrastructure is organized.

## Workflow matrix

| Check | Runs when | Docker? | Root? | Self-hosted? | Blocks merge? | Blocks release? |
|-------|-----------|---------|-------|--------------|---------------|-----------------|
| Shell syntax (`bash -n`) | push / PR | No | No | No | Yes | Yes |
| ShellCheck lint | push / PR | No | No | No | Yes | Yes |
| TAP shell tests | push / PR | No | No | No | Yes | Yes |
| Repo integrity | push / PR | No | No | No | Yes | Yes |
| Compose config lint | push / PR | No\* | No | No | Yes | Yes |
| E2E stages 0-7 | `workflow_dispatch` | Yes (2-5) | Yes (1) | Yes | No | Recommended |
| E2E scenarios 1-7 | `workflow_dispatch` | Yes | Yes | Yes | No | Recommended |
| E2E scenarios 8-10 | `workflow_dispatch` | No | No | Yes\*\* | No | Recommended |
| Contract validation | `workflow_dispatch` + weekly | No | No | No | No | Yes |
| Release sanity | `workflow_dispatch` | No | No | No | No | Yes |

\* Compose lint installs `docker-compose` for config parsing, but does not need a running daemon.
\*\* Scenarios 8-10 need the empusa repo+venv but not Docker or root.

## CI on push / PR

**File:** `.github/workflows/ci.yml`

Four parallel jobs that run on every push to `main` and every PR:

1. **shellcheck** — `bash -n` syntax check on all `.sh` files + ShellCheck `--severity=error`
2. **shell-tests** — Runs `tests/run-all.sh` (10 test files, TAP output)
3. **repo-integrity** — Validates critical files, templates, tmux profiles, manifest formats
4. **compose-lint** — Parses all compose file combinations with `docker-compose config -q`

All four must pass for the CI check to succeed.

## Platform validation (workflow_dispatch)

**File:** `.github/workflows/platform-validation.yml`

Full e2e harness — 8 stages + 10 scenarios.  Requires a **self-hosted runner** on Ubuntu 24.04 with:
- Root access
- Docker daemon running
- `/opt/lab` provisioned (or `skip_bootstrap=false`)
- Kali images built

Inputs:
- **scope**: `full`, `stages-only`, or `scenarios-only`
- **single_stage**: Run only one stage (0-7)
- **single_scenario**: Run only one named scenario
- **stop_on_fail**: Halt on first failure
- **skip_bootstrap**: Skip bootstrap stage (default: true)

Reports are uploaded as artifacts with 30-day retention.

### Why self-hosted?

The e2e harness validates real Docker containers, compose overlays, bind mounts,
builder sidecar lifecycle, tmux sessions, binary sync from GitHub API, and empusa
workspace creation inside running containers.  None of this is reproducible on a
stock GitHub-hosted runner.

## Contract validation

**File:** `.github/workflows/contract-validation.yml`

Detects drift between Hecate's integration assumptions and the real Empusa API.
Runs on GitHub-hosted `ubuntu-latest` — no Docker or root needed.

Checks:
- empusa importable
- Version format (semver)
- Workspace profiles exist (htb, build, research, internal)
- HTB profile dirs match expectations
- Template lists align with repo `templates/` contents
- CLI entry point (`empusa.cli:main`)
- `create_workspace` function available
- `EmpusaEvent` contract (fields, `to_dict()`)

Triggers:
- Manual dispatch (with configurable `empusa_ref`)
- Weekly schedule (Monday 06:00 UTC against `main`)

## Release sanity

**File:** `.github/workflows/release-sanity.yml`

Pre-tag/pre-release readiness gate.  Wraps the existing
`scripts/dev/release-sanity.sh` which validates:

1. Empusa `__version__` matches `pyproject.toml`
2. `CHANGELOG.md` has matching version entry
3. Git tag exists (advisory)
4. `ruff check` clean
5. `pytest` passes
6. Hecate shell tests pass

## Local development

```bash
# Quick syntax check
bash scripts/dev/ci-syntax-check.sh

# Repo integrity
bash scripts/dev/ci-repo-integrity.sh

# Compose lint
bash scripts/dev/ci-compose-lint.sh

# Cross-repo contract check
bash scripts/dev/ci-contract-check.sh /path/to/empusa

# Full release sanity
bash scripts/dev/release-sanity.sh

# Full platform validation (root + Docker)
sudo bash tests/e2e/run-validation.sh
```

## Helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/dev/ci-syntax-check.sh` | `bash -n` on all shell scripts |
| `scripts/dev/ci-repo-integrity.sh` | Critical file, template, manifest checks |
| `scripts/dev/ci-compose-lint.sh` | Compose config validation (all overlays) |
| `scripts/dev/ci-contract-check.sh` | Empusa contract verification |
| `scripts/dev/release-sanity.sh` | Cross-repo pre-release validation |

## Binary sync supply-chain validation

`scripts/sync-binaries.sh` reads `manifests/binaries.tsv` (8 columns including
`sha256`) and verifies each downloaded artifact:

- **Real 64-hex sha256** — computed via `sha256sum`, compared after download.
  Mismatch → temp file deleted, destination not promoted, `[FAIL]` emitted,
  process exits non-zero.
- **`TODO_SHA256`** — accepted in default/dev mode with `[WARN] checksum not
  pinned`.  Refused in **strict mode** with `[FAIL] checksum required`.
- **Strict mode** — enabled via `STRICT_CHECKSUMS=1` env or `--strict-checksums`
  flag.  Required for release-grade sync.
- **`mode=all-assets`** — per-asset checksums are not yet supported; a real
  sha256 on an all-assets row is rejected with `[FAIL]`.  Use TODO_SHA256 (with
  a `[WARN]`) for those rows until per-asset pinning is added.

`scripts/dev/ci-repo-integrity.sh` enforces the 8-column manifest layout, the
`^[0-9a-f]{64}$|^TODO_SHA256$` format constraint on the `sha256` column, and
emits a single `[WARN]` summary line listing how many rows are still unpinned.

Checksums reduce supply-chain risk but do not eliminate it: a compromised
upstream release could publish both the artifact and a matching digest.  Pair
checksums with pinned tags and periodic rotation for defense in depth.
