# Raw operator validation

Validation checklist for proving Empusa + Hecate work end-to-end **outside**
the unit-test harness, as a real operator would invoke them.

This is a release/host-readiness doc. It complements:
- `docs/dev/release-process.md` (release gates and evidence)
- `docs/dev/validation-model.md` (warn vs fail policy)
- `docs/dev/cross-repo-contract-audit.md` (contract pin)

Conventions used below:
- All commands are **non-destructive by default**. Anything that mutates a
  real lab host, real workspace tree, or pulls binaries from the network is
  marked `[ACTION]` and gated.
- Empusa commands assume the Empusa repo is checked out at `../empusa`
  relative to Hecate (or `EMPUSA_SRC` is set).
- Hecate commands run from the Hecate repo root.
- All scripts emit canonical markers: `[PASS]`, `[FAIL]`, `[WARN]`,
  `[INFO]`, `[ACTION]`. A run is considered green when no `[FAIL]` lines
  are emitted and the exit code is 0 unless explicitly noted.

## 1. Clean checkout / clean tree

| # | Command | Expected exit | Expected output | Notes |
|---|---|---|---|---|
| 1.1 | `git -C ../empusa status --porcelain` | 0 | empty | Dirty Empusa tree blocks `release-evidence.sh --strict`. |
| 1.2 | `git status --porcelain` | 0 | empty | Same, Hecate side. |
| 1.3 | `git -C ../empusa describe --tags --always` | 0 | tag or short SHA | Recorded in evidence. |
| 1.4 | `git describe --tags --always` | 0 | tag or short SHA | Recorded in evidence. |

## 2. Empusa editable install

| # | Command | Expected exit | Expected output | Notes |
|---|---|---|---|---|
| 2.1 | `python -m venv .venv && source .venv/bin/activate` | 0 | venv created | Use a throwaway venv. |
| 2.2 | `pip install -e ../empusa[dev]` | 0 | `Successfully installed empusa-2.3.0` | Editable install pulls dev extras. |
| 2.3 | `python -c "import empusa; print(empusa.__version__)"` | 0 | `2.3.0` | Confirms import path. |

## 3. Empusa wheel install

| # | Command | Expected exit | Expected output | Notes |
|---|---|---|---|---|
| 3.1 | `cd ../empusa && python -m build --wheel` | 0 | `Successfully built empusa-2.3.0-py3-none-any.whl` | Output in `dist/`. |
| 3.2 | `python scripts/dev/package-sanity.py` | 0 | `[PASS] 1 wheel(s) clean` | Forbidden-artifact audit. |
| 3.3 | `pip install --force-reinstall dist/empusa-2.3.0-py3-none-any.whl` | 0 | reinstall succeeds | Use a throwaway venv. |

## 4. Empusa CLI smoke

| # | Command | Expected exit | Expected output | Notes |
|---|---|---|---|---|
| 4.1 | `empusa --version` | 0 | `empusa 2.3.0` | |
| 4.2 | `empusa --help` | 0 | usage with `{build,exploit-search,loot,report,plugins,workspace}` | |
| 4.3 | `empusa workspace --help` | 0 | sub-help listing init/list/select/status | |
| 4.4 | `empusa plugins --help` | 0 | sub-help | |
| 4.5 | `python scripts/dev/version-sanity.py` | 0 | `[PASS] empusa version 2.3.0 is consistent` | Cross-checks `pyproject.toml` and `__init__.py`. |

## 5. Empusa workspace lifecycle (temp root)

Use `WS=$(mktemp -d -t empusa-smoke-XXXX)` for a throwaway root. **Never**
target a real operator workspace tree.

| # | Command | Expected exit | Expected output | Expected files |
|---|---|---|---|---|
| 5.1 | `empusa workspace init --name raw_smoke --profile htb --root "$WS"` | 0 | `Workspace Init  raw_smoke (htb)` panel | `$WS/raw_smoke/{notes,scans,creds,loot,exploits,reports,logs,screenshots,web}` |
| 5.2 | `empusa workspace list --root "$WS"` | 0 | `raw_smoke` listed | – |
| 5.3 | `empusa workspace select --name raw_smoke --root "$WS"` | 0 | `Workspace Select  raw_smoke` panel | active marker updated |
| 5.4 | `empusa workspace status --name raw_smoke --root "$WS"` | 0 | metadata panel | – |
| 5.5 | `rm -rf "$WS"` | 0 | – | cleanup |

## 6. Empusa strict-mode validation

### 6.1 STRICT_TEMPLATES

| # | Command | Expected exit | Expected output |
|---|---|---|---|
| 6.1.a | `STRICT_TEMPLATES=1 empusa workspace init --name strict_miss --profile htb --root "$WS"` | **1** | `[FAIL] STRICT_TEMPLATES: profile 'htb' expects templates but --templates-dir was not supplied` |
| 6.1.b | `STRICT_TEMPLATES=1 empusa workspace init --name strict_bad --profile htb --root "$WS" --templates-dir /no/such/path` | **1** | `[FAIL]` referencing missing dir |
| 6.1.c | `STRICT_TEMPLATES=1 empusa workspace init --name strict_ok --profile htb --root "$WS" --templates-dir "$VALID_TPL"` | 0 | normal init panel |
| 6.1.d | `unset STRICT_TEMPLATES; empusa workspace init --name soft --profile htb --root "$WS"` | 0 | warn-and-continue (no `[FAIL]`) |

### 6.2 STRICT_MODULES

`STRICT_MODULES` gates module **discovery**, which the CLI invokes via
`empusa build`. There is no `empusa modules list` surface — the gate is
exercised through build/test paths and through unit tests.

| # | Command | Expected exit | Expected output |
|---|---|---|---|
| 6.2.a | `STRICT_MODULES=1 python -m pytest -q tests/test_cli_modules.py` | 0 | all pass | (run from inside Empusa repo) |
| 6.2.b | `STRICT_MODULES=1 empusa build --help` | 0 | help text only | confirms env is harmless when no discovery runs |

## 7. Hecate script validation

| # | Command | Expected exit | Expected output |
|---|---|---|---|
| 7.1 | `bash scripts/dev/ci-syntax-check.sh` | 0 | one `[PASS]` per script |
| 7.2 | `bash scripts/dev/ci-repo-integrity.sh` | 0 | `[PASS]` integrity summary |
| 7.3 | `bash tests/run-all.sh` | 0 | aggregate pass count + `0 failed` |
| 7.4 | `bash tests/test_output_style.sh` | 0 | canonical-marker check passes |
| 7.5 | `bash scripts/verify-host.sh --help` | 0 | usage including `--strict` |
| 7.6 | `shellcheck --severity=error --shell=bash scripts/**/*.sh tests/**/*.sh labctl` | 0 | (only if shellcheck installed) |

## 8. Hecate strict release validation

| # | Command | Expected exit | Expected output | Notes |
|---|---|---|---|---|
| 8.1 | `RELEASE_SANITY_VERSION_ONLY=1 bash scripts/dev/release-sanity.sh ../empusa` | 0 | `── Version-only mode: contract checks passed ──` | Cheap pre-tag gate. |
| 8.2 | `STRICT_CHECKSUMS=1 bash scripts/dev/release-sanity.sh ../empusa` | 0 | `[PASS] All N active binary row(s) pass strict checksum gate` | Full gate. |
| 8.3 | `bash scripts/dev/release-evidence.sh --strict --out build/release-evidence/$(date -u +%Y%m%dT%H%M%SZ).txt ../empusa` | 0 | `[PASS]` lines for git/contract; warns only on optional digest evidence | Fails on dirty worktree, missing `release-sanity.sh`, or contract mismatch. |
| 8.4 | `[ACTION]` `bash scripts/verify-host.sh --strict` | 0 on a provisioned lab host | `[PASS]` for required tools, LAB_ROOT, tmux profiles, binary sync | **Lab host only**; not satisfiable on hosted CI. |

> The CLI flag advertised in earlier drafts as `--artifact PATH` is
> implemented in `release-evidence.sh` as `--out FILE`. Use `--out` and
> stage the file under `build/release-evidence/` so CI artifact upload
> picks it up.

## 9. Hecate binary sync validation (chisel)

| # | Command | Expected exit | Expected output | Notes |
|---|---|---|---|---|
| 9.1 | `bash scripts/sync-binaries.sh --dry-run chisel` | 0 | `[INFO]` lines describing the planned download; **no** network call | Safe offline. |
| 9.2 | `[ACTION]` `bash scripts/sync-binaries.sh chisel` | 0 | `[PASS] sha256 verified` then extract step | Network required. |
| 9.3 | `ls -l "$LAB_ROOT/tools/binaries"` | 0 | both `chisel_*_linux_amd64.gz` **and** the executable sibling `chisel_*_linux_amd64` | `.gz` is preserved as audit evidence. |
| 9.4 | `file "$LAB_ROOT/tools/binaries/chisel_*_linux_amd64"` | 0 | `ELF 64-bit LSB executable` | Must be executable. |
| 9.5 | `[ -x "$LAB_ROOT/tools/binaries/chisel_"*"_linux_amd64" ]` | 0 | – | Sibling has `+x`; `.gz` does **not**. |

## 10. labctl raw workflow

All `[ACTION]` items require Docker and a provisioned `LAB_ROOT`. **Do not
run these on a non-lab host.**

| # | Command | Expected exit | Expected output |
|---|---|---|---|
| 10.1 | `labctl --help` | 0 | usage with subcommands |
| 10.2 | `labctl status` | 0 | host status report (`[PASS]`/`[WARN]` lines) |
| 10.3 | `labctl verify` | 0 | host verify summary |
| 10.4 | `labctl tmux list` | 0 | tmux profiles enumerated |
| 10.5 | `labctl sync` | 0 | binary sync summary |
| 10.6 | `[ACTION]` `labctl up` | 0 | compose stack up |
| 10.7 | `[ACTION]` `labctl status` (post-up) | 0 | services healthy |
| 10.8 | `[ACTION]` `labctl shell <service>` | interactive | shell prompt inside container |
| 10.9 | `[ACTION]` `labctl launch research raw_smoke` | 0 | research workspace launched in tmux |

## 11. Cross-repo workspace handoff

Validates that Hecate-driven workspace creation goes **through** Empusa and
that the resulting tree matches the Empusa profile contract.

| # | Command | Expected exit | Expected output | Expected files |
|---|---|---|---|---|
| 11.1 | `bash tests/test_empusa_contract.sh` | 0 | `[PASS]` per contract assertion | – |
| 11.2 | `bash scripts/dev/ci-contract-check.sh ../empusa` | 0 | profile/event/template summary | – |
| 11.3 | `[ACTION]` `labctl launch research handoff_smoke` | 0 | research stack up | `$LAB_ROOT/workspaces/handoff_smoke/{notes,scans,…}` plus `templates/` populated |
| 11.4 | `cat "$LAB_ROOT/workspaces/handoff_smoke/.empusa-workspace.json"` | 0 | profile = `research`, version = `2.3.0` | – |

## 12. Failure-mode raw checks

| # | Command | Expected exit | Expected output |
|---|---|---|---|
| 12.1 | `empusa workspace init --name 'bad name' --profile htb --root "$WS"` | non-zero | `[FAIL]` rejecting the name |
| 12.2 | `empusa workspace init --name x --profile no-such-profile --root "$WS"` | non-zero | `[FAIL]` invalid profile |
| 12.3 | `STRICT_TEMPLATES=1 empusa workspace init --name miss --profile htb --root "$WS"` | 1 | `[FAIL] STRICT_TEMPLATES:` |
| 12.4 | `STRICT_CHECKSUMS=1 RELEASE_SANITY_SKIP_CHECKSUMS=0 bash scripts/dev/release-sanity.sh ../empusa` against a temp manifest containing a `TODO_SHA256` row | 1 | `[FAIL] <name>: TODO_SHA256 (unpinned)` |
| 12.5 | `bash scripts/verify-host.sh --strict` from a non-lab host | non-zero | `[FAIL]` for missing `LAB_ROOT`, missing tmux profiles, etc. |

For 12.4, copy `manifests/binaries.tsv` to a temp file, append a fake row
with `TODO_SHA256`, point `release-sanity.sh` at it via test override, and
confirm the strict gate fails. Do **not** edit the real manifest.

## 13. Release evidence artifact review

After running 8.3, inspect the produced file:

```bash
ls -la build/release-evidence/
sed -n '1,80p' build/release-evidence/<UTC>.txt
grep -E '^\[(PASS|FAIL|WARN|INFO|ACTION)\]' build/release-evidence/<UTC>.txt
```

Required content:
- Hecate git SHA + clean/dirty status
- Empusa expected contract version `2.3.0` and supplied version `2.3.0`
- `STRICT_CHECKSUMS` env value + per-row pin status for `manifests/binaries.tsv`
- Dockerfile base image references with `[WARN]` on `:latest`

Acceptance: zero `[FAIL]` lines, zero unexpected `[WARN]` lines beyond the
documented Kali-rolling `:latest` warning.

## 14. Cleanup

```bash
# Empusa-side
rm -rf "$WS"                         # temp workspace root
rm -rf ../empusa/build ../empusa/dist ../empusa/*.egg-info
deactivate 2>/dev/null || true
rm -rf .venv

# Hecate-side
rm -rf build/release-evidence/*.txt   # keep dir, drop artifacts after upload
```

`labctl` workspaces and `LAB_ROOT` state are **not** part of cleanup here —
those are operator decisions.

---

## Validation results — last run

The following was executed against the local sibling checkouts on the
authoring host. Hecate-side bash entries marked **(deferred)** require a
POSIX shell; record results from a Linux runner before tagging.

| Section | Command | RC | Result |
|---|---|---:|---|
| 4.1 | `empusa --version` | 0 | `[PASS]` `empusa 2.3.0` |
| 4.2 | `empusa --help` | 0 | `[PASS]` |
| 4.5 | `python scripts/dev/version-sanity.py` | 0 | `[PASS] empusa version 2.3.0 is consistent` |
| 3.1 | `python -m build --wheel` | 0 | `empusa-2.3.0-py3-none-any.whl` produced |
| 3.2 | `python scripts/dev/package-sanity.py` | 0 | `[PASS] 1 wheel(s) clean` |
| 5.1–5.4 | workspace init/list/select/status, htb, temp root | 0 | full htb directory tree present (`notes/scans/creds/loot/exploits/reports/logs/screenshots/web`) |
| 6.1.a | `STRICT_TEMPLATES=1` workspace init w/o `--templates-dir` | 1 | `[FAIL]` strict gate fired |
| 6.1.d | `unset STRICT_TEMPLATES` repeat | 0 | warn-and-create preserved |
| 6.2.b | `STRICT_MODULES=1 empusa build --help` | 0 | env is a no-op when discovery is not invoked |
| 7.1–7.6 | Hecate script suite | – | **(deferred)** authoring host has no `bash` |
| 8.1–8.3 | Hecate strict release | – | **(deferred)** see above |
| 9.1 | `sync-binaries.sh --dry-run chisel` | – | **(deferred)** see above |
| 10.x | labctl | – | **(deferred)** lab host only |
