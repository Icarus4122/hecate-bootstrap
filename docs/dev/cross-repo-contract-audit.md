# Cross-Repo Contract Audit — Empusa ↔ Hecate

**Audit date:** 2026-04-26
**Scope:**
- Empusa  → target v2.3.0
- Hecate Bootstrap → target v0.2.0

**Expected Empusa contract version:** `2.3.0`
(pinned by `scripts/dev/release-sanity.sh::EXPECTED_EMPUSA_VERSION`;
release-sanity verifies that this string and the Empusa source tree
agree before a release is allowed)

**Architectural boundary (locked):**
- Hecate owns: bootstrap, host setup, Docker/Compose, tmux, labctl, lab/platform validation.
- Empusa owns: workflow, workspace lifecycle, events, hooks, plugins, modules, services, artifacts, loot, reports.
- Hecate validates Empusa assumptions but does not reimplement Empusa behaviour.
- Hecate must not import Empusa Python directly; integration is via subprocess + filesystem contract.

---

## 1. Hecate command → Empusa command dependency

| Hecate caller (file:line) | Hecate-side command | Empusa-side target | Verified | Notes |
|---|---|---|---|---|
| `scripts/create-workspace.sh:55` | `empusa workspace init --name --profile --root --templates-dir --set-active` | `empusa.cli_workspace.cmd_workspace_init` | ✅ | All 5 flags present in Empusa CLI |
| `scripts/launch-lab.sh:101` | `empusa workspace init …` (same flag set) | `cmd_workspace_init` | ✅ | Idempotent on rerun |
| `tests/e2e/stage_5_empusa.sh:33` | `empusa --version` | `empusa.cli.main` global flag | ✅ | Stable contract |
| `tests/e2e/stage_5_empusa.sh:36` | `empusa --help` | `empusa.cli.main` global flag | ✅ | Asserts on subcommand keywords (`workspace`, `build`, `plugins`) only |
| `tests/e2e/stage_5_empusa.sh:66` | `empusa workspace init …` | `cmd_workspace_init` | ✅ | All 4 profiles exercised |
| `tests/e2e/stage_5_empusa.sh:93` | `empusa workspace init …` (idempotent) | `cmd_workspace_init` | ✅ | Re-run on existing workspace |
| `tests/e2e/stage_5_empusa.sh:105` | `empusa workspace select --name --root` | `cmd_workspace_select` | ✅ | |
| `tests/e2e/stage_5_empusa.sh:110` | `empusa workspace status --name --root` | `cmd_workspace_status` | ✅ | Asserts on workspace name + profile keywords |
| `tests/test_empusa_contract.sh:67–293` | Python `from empusa.* import …` (subprocess) | `empusa.workspace`, `empusa.events` | ✅ | Subprocess-isolated; opt-in if local Empusa source exists |
| `scripts/install-empusa.sh` | `git clone` Empusa repo + editable `pip install` | n/a (deployment) | ✅ | Clone URL configurable via `EMPUSA_REPO` |

**Result:** Zero invocation mismatches. Every Hecate-side empusa call targets a real subcommand with correct flags. No interactive-prompt surprises in non-interactive callers.

---

## 2. Script → expected dependencies

| Script | Required commands | Required env | Notes |
|---|---|---|---|
| `scripts/bootstrap-host.sh` | `apt`, `docker`, `docker compose`, `git`, `python3`, `python3-venv` | `LAB_ROOT`, `SUDO_USER` | Creates `/opt/lab/{data,knowledge,resources,templates,tools/{binaries,git,venvs},workspaces}` and symlinks `/usr/local/bin/labctl` |
| `scripts/install-empusa.sh` | `git`, `python3`, `python3-venv`, `pip` | `LAB_ROOT`, `EMPUSA_REPO` | Editable install into `${LAB_ROOT}/tools/venvs/empusa` |
| `scripts/launch-lab.sh` | `docker`, `docker compose`, `tmux`, optional `empusa` | `LAB_ROOT`, `LAB_LAUNCH_NO_ATTACH` (opt) | Resolves Empusa via venv → PATH → fallback scaffold |
| `scripts/create-workspace.sh` | optional `empusa` | `LAB_ROOT` | Same resolution chain; fallback scaffold creates `notes/scans/loot/logs` |
| `scripts/sync-binaries.sh` | `curl`, `file(1)` | `LAB_ROOT`, optional `GITHUB_TOKEN` | Downloads + validates released binaries |
| `scripts/verify-host.sh` | `docker`, `docker compose`, `python3`, `git` | `LAB_ROOT` | Read-only pre-flight |
| `scripts/update-lab.sh` | `git`, `docker compose` | `LAB_ROOT`, `OPT_PULL`, `OPT_EMPUSA`, `OPT_BINARIES` | Orchestrator |
| `scripts/setup-nvidia.sh` | `apt`, `nvidia-smi` | n/a | Optional GPU runtime install |
| `scripts/dev/ci-syntax-check.sh` | `bash` | n/a | Walks `scripts/`, `tests/`, root scripts |
| `scripts/dev/ci-repo-integrity.sh` | `bash` | n/a | Checks required files exist |
| `scripts/dev/ci-compose-lint.sh` | `docker` or `docker-compose` | n/a | Auto-detects compose v1 vs v2 |
| `scripts/dev/ci-contract-check.sh` | `python3`, Empusa source tree | `EMPUSA_SRC` (opt) | Validates PROFILES, htb dirs, ALL_EVENTS, CLI entry |
| `scripts/dev/release-sanity.sh` | `python3`, ruff (Empusa repo) | `EMPUSA_SRC` (opt), `PYTHON` (opt) | Runs against Empusa, not Hecate |

All scripts referenced in docs and CHANGELOG entries exist on disk.

---

## 3. Environment variable → defined-by → consumed-by → default → tested

| Variable | Defined by | Consumed by | Required | Default | Documented | Tested |
|---|---|---|---|---|---|---|
| `LAB_ROOT` | `.env.example`, fallback in every script | `bootstrap-host`, `labctl`, `install-empusa`, `launch-lab`, `create-workspace`, `sync-binaries`, `update-lab`, `verify-host`, compose YAML | no | `/opt/lab` | README §Configuration; `.env.example` | yes (multiple test files) |
| `COMPOSE_PROJECT_NAME` | `.env.example`, `labctl`, `launch-lab.sh` | `labctl`, compose helpers | no | `lab` | README; `.env.example` | yes (compose stacking) |
| `LAB_GPU` | `.env.example`, `labctl`, `update-lab.sh` | `labctl verify`, `scripts/lib/compose.sh` | no | `0` | README §GPU; `.env.example` | yes (compose overlay) |
| `LAB_HOSTNET` | `.env.example`, `labctl` | `scripts/lib/compose.sh` | no | `0` | README §Networking; `.env.example` | yes (compose overlay) |
| `EMPUSA_REPO` | `install-empusa.sh:15` | `install-empusa.sh:66,68` | no | `https://github.com/Icarus4122/empusa.git` | README; `.env.example` | manual |
| `EMPUSA_SRC` | dev scripts | `scripts/dev/ci-contract-check.sh`, `release-sanity.sh` | no | sibling `../empusa` | dev-script headers | manual |
| `GITHUB_TOKEN` | env (caller) | `sync-binaries.sh:73` | no | unset | README §Sync; `.env.example` | manual |
| `LAB_LAUNCH_NO_ATTACH` | env (caller) | `launch-lab.sh:14,56` | no | `0` | `launch-lab.sh` header | automation/CI |
| `OPT_PULL` / `OPT_EMPUSA` / `OPT_BINARIES` | `update-lab.sh` flag-parser | `update-lab.sh` | no | `0` | `update-lab.sh --help` | flag-parsing |
| `NO_COLOR` | env (caller) | `empusa/cli.py`, `scripts/lib/ui.sh` | no | unset | `lib/ui.sh` header; Empusa CLI | implicit |
| `EMPUSA_BIN` | computed in scripts | `scripts/lib/empusa.sh` consumers, e2e helpers | no | `${LAB_ROOT}/tools/venvs/empusa/bin/empusa` | `docs/empusa.md`; README | `tests/test_empusa_resolution.sh` |
| `SUDO_USER` | OS / sudo | `bootstrap-host.sh:9,61,81` | no | falls back to `$USER` | bootstrap header | manual |

**Conflicts:** none detected. All defaults agree across scripts and docs.

---

## 4. Path → created by → consumed by → documented → tested

Intended structure:
```
/opt/lab/
  data/
  knowledge/
  resources/
  templates/
  tools/{binaries, git, venvs}
  workspaces/
```

| Path | Created by | Consumed by | Documented | Tested | Status |
|---|---|---|---|---|---|
| `/opt/lab/` | `bootstrap-host.sh:80` | every script | README, `docs/architecture.md` | yes | ✅ |
| `/opt/lab/data/` | bootstrap (mkdir -p) | compose volumes | architecture | yes | ✅ |
| `/opt/lab/knowledge/` | bootstrap | compose volumes | architecture | yes | ✅ |
| `/opt/lab/resources/` | bootstrap | compose volumes | architecture | yes | ✅ |
| `/opt/lab/templates/` | bootstrap | compose volumes; `--templates-dir` to empusa | architecture | yes | ✅ |
| `/opt/lab/tools/binaries/` | bootstrap; `sync-binaries.sh` populates | `labctl status`, container PATH | README §Binaries | yes | ✅ |
| `/opt/lab/tools/git/` | bootstrap | `install-empusa.sh:17` | `docs/empusa.md` | yes | ✅ |
| `/opt/lab/tools/git/empusa/` | `install-empusa.sh` (`git clone`) | venv editable install | README §Empusa | yes | ✅ |
| `/opt/lab/tools/venvs/` | bootstrap | `install-empusa.sh:18` | README | yes | ✅ |
| `/opt/lab/tools/venvs/empusa/bin/empusa` | `install-empusa.sh` (`pip install -e`) | `launch-lab.sh`, `create-workspace.sh` | README, `docs/empusa.md` | `test_empusa_resolution.sh` | ✅ |
| `/opt/lab/workspaces/` | bootstrap | `empusa workspace init` writes here | README §Workspace | yes | ✅ |
| `/opt/lab/workspaces/<name>/` | `empusa workspace init` (or fallback in `create-workspace.sh`) | Empusa cli_scan/cli_loot/cli_reports | README §Workspace | `stage_5_empusa.sh` | ✅ |
| `/opt/lab/workspaces/<name>/.empusa-workspace.json` | `empusa.workspace.create_workspace` | `empusa.workspace.load_metadata` | implicit | `test_empusa_contract.sh` | ✅ |
| `/usr/local/bin/labctl` | `bootstrap-host.sh:104` (symlink) | shell PATH | README §Quickstart | manual | ✅ |
| `/opt/empusa/` | NOT created by Hecate; opt-in dev path | `tests/e2e/stage_5_empusa.sh:13` (gracefully skipped) | dev docs | yes (skip path) | ✅ opt-in |

**Drift:** none. No documented path is missing a creator; no created path is undocumented at the directory level. Workspace subdirectories (`notes/scans/web/creds/loot/exploits/screenshots/reports/logs` for `htb`, etc.) are owned by Empusa's `PROFILES` table and verified by `tests/test_empusa_contract.sh` + `stage_5_empusa.sh`.

---

## 5. Output marker → producer → consumer/test

Canonical vocabulary: `[PASS]`, `[FAIL]`, `[WARN]`, `[INFO]`, `[ACTION]`.

| Marker | Producer (Hecate) | Producer (Empusa) | Consumer / test |
|---|---|---|---|
| `[PASS]` | `lib/ui.sh: ui_pass`; literal in dev/CI scripts | `cli_common.log_success` callsites prefix `[PASS]`; panel content uses Rich-escaped `\[PASS]` | `tests/test_output_style.sh`; `tests/e2e/e2e-helpers.sh` regex `\[(PASS|FAIL|WARN|INFO|ACTION)\]` |
| `[FAIL]` | `lib/ui.sh: ui_fail`; `die()` helpers | `log_error` callsites (where appropriate) | same |
| `[WARN]` | `lib/ui.sh: ui_warn` | `log_info(..., style='yellow')` callsites | same |
| `[INFO]` | `lib/ui.sh: ui_info`; `info()` helpers | `log_info` callsites | same |
| `[ACTION]` | `lib/ui.sh: ui_action`, `ui_next_block` | `cli_workspace` next-step blocks | e2e and operator-facing only |

Hecate tests assert on canonical bracketed markers, exit codes, and file existence. No remaining test depends on Rich colour codes or decorative glyphs. (`tests/test_output_style.sh` enforces canonical vocabulary in repo scripts and rejects bare `✓`/`✗` outside `printf` summary blocks.)

---

## 6. Documentation claim → backing code/test → status

| Claim | Source | Backing | Status |
|---|---|---|---|
| Bootstrap creates `/opt/lab/{data,knowledge,resources,templates,tools/*,workspaces}` | Hecate README, `docs/architecture.md` | `bootstrap-host.sh:80` | ✅ |
| `labctl` symlinked to `/usr/local/bin/labctl` | Hecate README §Quickstart | `bootstrap-host.sh:104` | ✅ |
| Four workspace profiles (`htb`, `build`, `research`, `internal`) | Hecate `docs/empusa.md`; Empusa README | `empusa/workspace.py` `PROFILES` | ✅ |
| HTB profile dirs / templates | Empusa README; Hecate `docs/empusa.md` | `empusa/workspace.py:35–55`; templates exist in `hecate-bootstrap/templates/` | ✅ |
| Empusa resolution: venv → PATH → fallback | Hecate README; `docs/empusa.md` | `tests/test_empusa_resolution.sh` 5-case suite | ✅ |
| `labctl up`, `labctl down`, `labctl shell`, `labctl launch`, `labctl workspace`, `labctl verify`, `labctl status`, `labctl update` | Hecate README, `docs/labctl.md` | `labctl` dispatcher; corresponding scripts | ✅ |
| GPU stacking via `LAB_GPU=1` | Hecate README §GPU | `scripts/lib/compose.sh:16`; `setup-nvidia.sh` | ✅ |
| Host-network stacking via `LAB_HOSTNET=1` | Hecate README §Networking | `scripts/lib/compose.sh:19` | ✅ |
| Empusa v2.3.0 changelog: workspace `[ACTION]` next-step blocks | Empusa CHANGELOG | `cli_workspace` ACTION emission | ✅ |
| Empusa v2.3.0 changelog: canonical marker alignment across cli_* | Empusa CHANGELOG | call-site markers `[PASS]/[FAIL]/[WARN]/[INFO]/[ACTION]` in cli.py, cli_loot.py, cli_modules.py, cli_scan.py etc. | ✅ |
| Hecate v0.2.0 changelog: `scripts/lib/ui.sh` canonical primitives | Hecate CHANGELOG | `scripts/lib/ui.sh` (ui_pass/fail/warn/info/action) | ✅ |
| Hecate v0.2.0 changelog: dev/CI scripts | Hecate CHANGELOG | five files in `scripts/dev/` exist and converted to canonical markers | ✅ |
| Hecate v0.2.0 changelog: 4 CI workflows | Hecate CHANGELOG | `.github/workflows/` ci, contract-validation, platform-validation, release-sanity | ✅ |
| Hecate v0.2.0 changelog: `validation-model.md` doc | Hecate CHANGELOG | `docs/dev/validation-model.md` | ✅ |
| Empusa `--version` prints `2.3.0` | INSTALL.md (post-fix), README packaging table (post-fix) | `empusa/__init__.py`, `pyproject.toml` | ✅ (after this audit's fixes) |

---

## Findings & actions

| # | Finding | Severity | Action taken |
|---|---|---|---|
| 1 | `INSTALL.md:68` claimed `--version` prints `2.2.0` | doc-fix | Updated to `2.3.0` |
| 2 | `README.md:767` packaging table version cell read `2.2.0` | doc-fix | Updated to `2.3.0` |
| 3 | Hecate test stubs (`echo "empusa 2.2.0"` in test_empusa_resolution.sh / test_verify_host.sh) | none | Left as-is — these are mock fixtures; tests assert on resolution path, not on the literal version |
| 4 | Hecate CHANGELOG v0.1.0 references `Empusa v2.2.1 contract` | none | Historical; do not rewrite past changelog entries |
| 5 | False positives flagged by automated vocab sweep against `log_success("[PASS] …")` callsites | none | Investigated `cli_common.py:228` — `log_success` does NOT auto-prefix; the literal `[PASS]` belongs at the callsite. The pattern is correct |

No release blockers identified.

---

## Unverified items (informational)

- `pytest` and `ruff` were not executed in this audit (no Linux/bash runtime available on the audit host); the user must run `pytest -q` and `ruff check empusa/ tests/` locally before tagging.
- E2E scripts `tests/e2e/sc_02 .. sc_09` were not individually re-walked this audit; the helper-level marker contract was confirmed (`tests/e2e/e2e-helpers.sh`).
- `/opt/empusa` opt-in dev path is exercised only when both an Empusa source tree and its venv are present; gate-checked correctly.

---

## Conclusion

Cross-repo contract is consistent. After the two `2.2.0 → 2.3.0` doc fixes above, both repos are tag-ready pending the local `pytest` / `ruff` / `bash tests/run-all.sh` validation runs.
