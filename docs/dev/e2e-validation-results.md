# E2E Validation Results — Empusa v2.3.0 / Hecate v0.2.0

**Date:** 2026-04-26
**Audit host:** Windows (no `bash`/`docker`/`pytest` runtime available locally).
**Status of execution:** All commands documented as **expected** results derived from static inspection of the scripts. The user must execute these on a Linux host with bash, Docker, and Python 3.9+ to confirm.

---

## 1. Smoke path commands

| # | Command | Expected exit | Expected key output | Files / dirs created | Blocker if fails? |
|---|---|---|---|---|---|
| 1 | `labctl verify` | `0` (or `1` if hard fail) | `[PASS]` lines per check + `── Summary ──` block; `Result: Host is ready.` on success | none | yes — gates everything else |
| 2 | `labctl up` | `0` | `[PASS] Lab is running.` after `docker compose up -d`; `[ACTION] Next` block pointing at `labctl shell` | container state under `/opt/lab/data` | yes |
| 3 | `labctl status` | `0` | Compose service status table; LAB_ROOT, GPU/HOSTNET flags echoed | none | no — informational |
| 4 | `labctl launch research test-target` | `0` | Resolution: venv → PATH → fallback. Calls `empusa workspace init --name test-target --profile research --root /opt/lab/workspaces --templates-dir /opt/lab/templates --set-active`; tmux session attached unless `LAB_LAUNCH_NO_ATTACH=1` | `/opt/lab/workspaces/test-target/{notes,references,poc,logs}` + `recon.md` template + `.empusa-workspace.json` | yes |
| 5 | `labctl shell` | `0` | drops into kali-main container | none | yes |
| 6 | (in container or via venv) `empusa --version` | `0` | `empusa 2.3.0` | none | yes — version contract |
| 7 | `empusa workspace init test-target` | `0` (idempotent if exists) | `[PASS] Created workspace: …` plus `[ACTION] Next` block | workspace tree (see #4) | yes |
| 8 | `empusa workspace select --name test-target --root /opt/lab/workspaces` | `0` | `[PASS] Active workspace: test-target (profile=research)` | updates active marker | yes |

---

## 2. Failure-mode expectations

These behaviours are **documented contracts** — fail-loudly, machine-parseable.

| Scenario | Trigger | Expected marker | Expected exit | Notes |
|---|---|---|---|---|
| Docker daemon down | `labctl verify` / `up` | `[FAIL] Docker daemon unreachable` + `Fix:` lines | `1` | `verify-host.sh` checks docker-info |
| `docker compose` plugin missing | `labctl up` / dev/ci-compose-lint | `[FAIL] Neither 'docker compose' nor 'docker-compose' found` | `1` | implemented in `scripts/dev/ci-compose-lint.sh` |
| Empusa venv + binary missing | `labctl launch …` | `[WARN] Empusa not found …` then fallback scaffold creates `notes/scans/loot/logs` only | `0` (degraded but functional) | `tests/test_empusa_resolution.sh` + `tests/test_create_workspace.sh:44` confirm |
| Empusa wrong major version | n/a | not actively asserted; relies on Empusa's own back-compat for `workspace init` flags | n/a | recommendation: add `release-sanity.sh` cross-version pin in a future release |
| Missing `.env` | `labctl up` | each script falls back to defaults silently (no `.env` is required) | `0` | `.env.example` documents the optional vars |
| Invalid workspace name (e.g. `..`) | `empusa workspace init --name ..` | Empusa rejects with `[FAIL]` and non-zero exit | `1` | Empusa-side validation |
| Workspace already exists | `empusa workspace init --name X` (twice) | Empusa is idempotent: re-uses existing dirs/metadata; emits `[PASS]` | `0` | covered in `stage_5_empusa.sh:93` (Workspace Idempotency) |
| Missing lab root (`/opt/lab` absent) | any `labctl` command | scripts mkdir-p where they own it; for downstream consumers, fail-fast with `[FAIL] LAB_ROOT does not exist` | `1` | `bootstrap-host.sh` is the canonical creator |
| Bad bind mount (e.g. tools/binaries empty) | `labctl up` | container starts but tools missing on PATH; `labctl status` notes count | `0` (compose-up succeeds) | non-blocker; `sync-binaries.sh` repopulates |
| Non-interactive missing required input | `empusa workspace init` without `--name` | argparse error to stderr, non-zero exit | `2` | argparse default behaviour |
| Empusa Python deps not installed (broken venv) | `labctl launch …` | `[FAIL]` from venv launcher; fallback scaffold still runs | `0` (degraded) | covered in `test_empusa_resolution.sh` cases |

---

## 3. Test suites (expected outcomes when run on Linux)

| Suite | Command | Expected |
|---|---|---|
| Hecate shell unit tests | `bash tests/run-all.sh` | all assertions pass; no bare-glyph violations from `tests/test_output_style.sh` |
| Hecate dev/CI sanity | `bash scripts/dev/ci-syntax-check.sh && bash scripts/dev/ci-repo-integrity.sh && bash scripts/dev/ci-compose-lint.sh` | each ends with `[PASS]` line and exit 0 |
| Hecate cross-repo contract | `bash scripts/dev/ci-contract-check.sh ../empusa` | `[PASS]` lines for all of: PROFILES present, htb dirs exact, ALL_EVENTS contains workspace events, CLI entry resolves |
| Hecate release-sanity (against Empusa) | `bash scripts/dev/release-sanity.sh ../empusa` | `[PASS] version 2.3.0 consistent` + `[PASS] [2.3.0] in CHANGELOG.md` |
| Hecate e2e (Linux + Docker) | `bash tests/e2e/run-validation.sh` (or per-stage) | stages 0–7 pass; stage 5 conditional on local Empusa source |
| Empusa lint | `ruff check empusa/ tests/` | clean |
| Empusa unit + integration | `pytest -q` | green |

---

## 4. Outstanding items the user must run

```bash
# Empusa
cd empusa
ruff check empusa/ tests/
pytest -q

# Hecate
cd ../hecate-bootstrap
bash scripts/dev/ci-syntax-check.sh
bash scripts/dev/ci-repo-integrity.sh
bash scripts/dev/ci-compose-lint.sh
bash scripts/dev/ci-contract-check.sh ../empusa
bash scripts/dev/release-sanity.sh ../empusa
bash tests/run-all.sh
bash tests/test_output_style.sh
# E2E (requires Docker + Empusa installed):
bash tests/e2e/run-validation.sh   # requires Docker + Empusa installed
```

If all of the above succeed, both repos are tag-ready:

```bash
cd empusa            && git add -A && git commit -m "release: v2.3.0" && git tag v2.3.0
cd ../hecate-bootstrap && git add -A && git commit -m "release: v0.2.0" && git tag v0.2.0
```

---

## 5. Unverified

- Live execution of any e2e scenario (no bash on audit host).
- pytest / ruff outcomes (no Python runtime exercised against the repo).
- Docker compose `up` behaviour with the post-vocab-migration scripts (no Docker on audit host).

These are deferred to the user's local validation pass.
