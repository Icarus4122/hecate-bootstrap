# Hecate release process

A reproducible release of Hecate-bootstrap requires evidence and gates
beyond a passing test suite.  This document is the canonical checklist.

## 1. Required validation commands

Run these from the Hecate repo root:

```bash
bash scripts/dev/ci-syntax-check.sh
bash scripts/dev/ci-repo-integrity.sh
bash tests/run-all.sh
bash tests/test_output_style.sh
RELEASE_SANITY_VERSION_ONLY=1 bash scripts/dev/release-sanity.sh ../empusa
```

If `shellcheck` is available locally, also run:

```bash
shellcheck -x scripts/**/*.sh tests/**/*.sh labctl
```

## 2. Strict checksum requirement

Release-grade syncs of external binaries must pin every active row in
`manifests/binaries.tsv` with a real lowercase 64-hex `sha256`.

The strict gate runs as part of `release-sanity.sh` whenever
`RELEASE_SANITY_VERSION_ONLY=1` is **not** set.  It walks
`manifests/binaries.tsv` and prints `[PASS]` / `[FAIL]` per row.

Per-asset checksums are **not** supported for `mode=all-assets` rows.
A row that is both `all-assets` and `TODO_SHA256` is a release blocker
under strict mode and must either be:

- narrowed to a single deterministic asset filename (then pinned), or
- intentionally excluded from the release (deactivated in the manifest).

To skip the strict gate for a non-release/dev snapshot:

```bash
RELEASE_SANITY_SKIP_CHECKSUMS=1 bash scripts/dev/release-sanity.sh ../empusa
```

To force-fail any TODO_SHA256 entry in `sync-binaries.sh` itself:

```bash
STRICT_CHECKSUMS=1 bash scripts/sync-binaries.sh --dry-run
```

> **Resolved (chisel pinned).**  The active `chisel` row was previously
> `mode=all-assets` (per-asset checksums unsupported, so strict mode failed).
> It is now narrowed to the single deterministic asset
> `chisel_<TAG>_linux_amd64.gz` with a SHA256 verified against the upstream
> `chisel_<TAG>_checksums.txt` published with the release.
> See the comment block in `manifests/binaries.tsv` for the refresh recipe.
> `mode=all-assets` rows are still permitted as **dev-only** examples but
> remain blocked by `STRICT_CHECKSUMS=1` and the strict release-sanity gate.

### 2.1 Single-asset `.gz` extraction

When a single-asset row downloads a `*.gz` artifact (e.g. chisel),
`sync-binaries.sh` performs the following steps in order:

1. Download to a `.tmp.$$` file.
2. Validate with `file(1)` (rejects HTML/XML; text only when `allow-text`).
3. Promote `.tmp.$$` → final `<asset>.gz` path.
4. Verify SHA256 of the **compressed** `.gz` artifact (the checksum in
   `manifests/binaries.tsv` always refers to the bytes that were downloaded).
5. Decompress alongside it: `<asset>.gz` → `<asset>` (sibling, same dir).
6. `chmod +x <asset>`.

The verified `.gz` is **preserved** so the release artifact remains on
disk for re-extraction or audit.  Decompression failure removes the
partial sibling and increments the error count; the verified `.gz` is
left untouched.  Compressed `.gz` files are never marked executable.

## 3. Empusa contract version pin

The expected Empusa contract version is the constant
`EXPECTED_EMPUSA_VERSION` at the top of
`scripts/dev/release-sanity.sh` and is mirrored in
`docs/dev/cross-repo-contract-audit.md` as:

```
**Expected Empusa contract version:** `<X.Y.Z>`
```

Both must change together when bumping the Empusa contract.
`release-sanity.sh` fails fast on mismatch.

## 4. Release evidence

Capture machine- and operator-readable evidence with:

```bash
bash scripts/dev/release-evidence.sh ../empusa \
    --out build/release-evidence/$(date -u +%Y%m%dT%H%M%SZ).txt
```

The script reports:

- Hecate git commit SHA, branch, tag (if any), and clean/dirty status
- Docker / Compose versions (warns if not installed — never fails)
- Dockerfile base images and whether they use mutable tags (`:latest`)
- Local image RepoDigests when Docker is installed (no automatic `docker pull`)
- Empusa expected contract version + supplied source version
- `STRICT_CHECKSUMS` env value + `binaries.tsv` per-row pin status

Add `--strict` to fail the script on a dirty worktree.  A clean
worktree is required for an actual tagged release.

## 5. Docker base image digests / `:latest`

`docker/kali-main/Dockerfile` currently uses
`kalilinux/kali-rolling:latest`, a deliberately mutable rolling tag.
This is **not** byte-for-byte reproducible across re-pulls.

For a fully reproducible release:

1. Pull the image locally: `docker pull kalilinux/kali-rolling:latest`
2. Read the digest:
   ```bash
   docker image inspect --format '{{index .RepoDigests 0}}' \
       kalilinux/kali-rolling:latest
   ```
3. Replace `:latest` with `@sha256:<digest>` in the Dockerfile, or
   record the digest in the release evidence output without changing
   the Dockerfile (acceptable for rolling-distribution images).

`release-evidence.sh` flags every mutable `:latest` reference with
`[WARN]` so the operator can decide per release.

### 5.1 Local digest evidence

When `docker` is on `PATH`, `release-evidence.sh` runs
`docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' <image>`
for each Dockerfile base reference and emits one of:

- `[INFO]   local RepoDigest: <repo>@sha256:<digest>` — the image was
  previously pulled locally and the digest is recorded for traceability.
- `[WARN]   digest unavailable locally (image not pulled; no auto-pull)`
  — the image is tag-based and not present in the local Docker engine.
  The script never invokes `docker pull` automatically; this is by
  design so that running release-evidence has zero network cost.
- `[WARN] docker unavailable; digest evidence skipped` (printed once at
  the top of the section) — the host has no `docker` CLI; no digest
  collection happens.

Local digest evidence improves traceability of which exact image
contents the release was tested against, but it does **not** by itself
pin Dockerfile builds — the Dockerfile `FROM` reference still needs to
be rewritten to `@sha256:<digest>` for byte-for-byte reproducibility.

## 6. Attaching the evidence report

Copy the file produced by `release-evidence.sh --out` into the GitHub
release notes (or the artifact bundle) for the tagged release.

## 7. Strict release validation path

The full CI/release validation chain promotes every soft warning that
matters at release time into a hard gate. Run from the Hecate repo root
with the Empusa source tree available at `../empusa`:

```bash
# 1. Hecate-side release readiness with strict checksum gate.
STRICT_CHECKSUMS=1 bash scripts/dev/release-sanity.sh ../empusa

# 2. Strict release evidence artifact (fails on dirty worktree, missing
#    release-sanity.sh, or Empusa contract mismatch).
bash scripts/dev/release-evidence.sh --strict \
    --out build/release-evidence/$(date -u +%Y%m%dT%H%M%SZ).txt \
    ../empusa

# 3. Empusa-side strict validation (run inside the Empusa worktree).
( cd ../empusa && \
    STRICT_MODULES=1 STRICT_TEMPLATES=1 python -m pytest -q )
```

On the actual release/lab host (not GitHub-hosted CI), also run:

```bash
bash scripts/verify-host.sh --strict
```

`verify-host.sh --strict` is intentionally **not** wired into the
hosted `Release Sanity` workflow because GitHub-hosted runners do not
provide the `LAB_ROOT` layout, tmux profiles, synced binary tree, or
optional GPU/host-net configuration the strict mode checks for. It is
a host-readiness gate that must be executed by the release operator
on the provisioned lab host.

The hosted `Release Sanity` workflow already exports
`STRICT_CHECKSUMS=1`, `STRICT_MODULES=1`, and `STRICT_TEMPLATES=1` for
the `release-sanity.sh` and `release-evidence.sh` steps, and uploads
`build/release-evidence/` as a workflow artifact for traceability.

`RELEASE_SANITY_SKIP_CHECKSUMS=1` remains available as a documented
escape hatch for non-release dev snapshots and **must not** be set in
the release workflow.

## 8. Remaining reproducibility gaps

- **Kali rolling base image** — see section 5.
- **`apt` package state inside containers** — `docker/*/apt-packages.txt`
  pins package names but not exact versions; the live apt repository
  resolves versions at build time.
- **`mode=all-assets` binaries** — `all-assets` rows cannot be strictly
  pinned until per-asset checksum support is added.  No active row uses
  `all-assets` today; future additions must pin a single asset filename.
- **External tool installs invoked at lab-launch time** — anything
  fetched at runtime (post-bootstrap) is outside this evidence pass.

These gaps are deliberate tradeoffs for a Kali-rolling lab; the
release evidence file is the authoritative snapshot per release.
