# Troubleshooting

## Pre-flight: `labctl verify`

Run `labctl verify` before diagnosing issues manually.  It checks OS version,
required commands, Docker health, `/opt/lab` layout, repo files, Empusa
installation, binary sync state, and GPU runtime in one pass.

```bash
labctl verify                     # standard checks
LAB_GPU=1 labctl verify           # also verify GPU runtime
```

FAIL items are critical and will block `labctl update`.  WARN items are
informational.

---

## Docker

| Problem | Solution |
| --------- | ---------- |
| Permission denied | `sudo usermod -aG docker $USER && newgrp docker` |
| Daemon unreachable | `sudo systemctl start docker` — `labctl verify` catches this |
| Can't reach internet from container | `docker network inspect bridge`, check DNS in compose |
| Can't reach VPN targets | See [vpn-routing.md](vpn-routing.md) |
| `docker compose` not found | Install compose plugin: `sudo apt install docker-compose-plugin` |
| Full rebuild | `labctl clean && labctl rebuild && labctl up` |

## GPU

| Problem | Solution |
| --------- | ---------- |
| `nvidia-smi` missing on host | Install NVIDIA driver first, then `scripts/setup-nvidia.sh` |
| `nvidia-smi` missing in container | Start with GPU overlay: `labctl up --gpu` |
| hashcat `-I` empty | Restart Docker after nvidia-ctk install: `sudo systemctl restart docker` |
| NVIDIA runtime not in `docker info` | Run `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker` |
| Container won't start after GPU changes | `labctl clean && labctl build && labctl up --gpu` |

## VPN

| Problem | Solution |
| --------- | ---------- |
| Auth failure | Check `.ovpn` path and system clock: `timedatectl` |
| DNS resolution | Add target DNS to host `/etc/resolv.conf` or use `--hostnet` |

---

## Empusa — Missing / Fallback Mode

**Symptom:** `[fallback]` prefix in output when running `labctl workspace` or
`labctl launch`.

**Cause:** Empusa is not installed or the venv binary is not executable.

**Impact:** Workspaces are created with four generic directories (`notes/`,
`scans/`, `loot/`, `logs/`) — no profile-specific layout, no template
seeding, no workspace metadata, no lifecycle events.  The lab remains
functional but loses structured engagement support.

**Fix:**

```bash
bash scripts/install-empusa.sh install
```

**Verify:**

```bash
labctl verify              # should show [PASS] for empusa
${LAB_ROOT}/tools/venvs/empusa/bin/empusa --version
```

If the venv exists but `empusa` is broken:

```bash
bash scripts/install-empusa.sh reinstall
```

---

## Path Drift

**Symptom:** Scripts fail with "directory not found" or files appear in
unexpected locations.

**Cause:** `LAB_ROOT` is inconsistent between shell sessions, `.env`,
scripts, and manual invocations.

**Check:**

```bash
echo $LAB_ROOT                  # should be /opt/lab (or your override)
grep LAB_ROOT .env              # if using .env
labctl verify                   # checks all required directories exist
```

**Canonical layout:**

```text
/opt/lab/{data, tools/{binaries,git,venvs}, resources, workspaces, knowledge, templates}
```

All scripts default to `${LAB_ROOT:-/opt/lab}`.  If you override `LAB_ROOT`,
ensure it is consistent everywhere — exported in your shell profile, set in
`.env`, and passed to `sudo` invocations (`sudo LAB_ROOT=/custom/path labctl bootstrap`).

---

## Package-Name Drift in Kali Rolling

**Symptom:** `labctl build` fails on a missing apt package.

**Cause:** Kali Rolling is a rolling release — package names change over time.

**Known renames:**

| Old | Current | Notes |
| ----- | --------- | ------- |
| `crackmapexec` | `netexec` | Fork/rename |
| `exiftool` | `libimage-exiftool-perl` | Virtual package gone |

**Fix:** Check [pkg.kali.org](https://pkg.kali.org/) for the current name
and update `docker/kali-main/apt-packages.txt`.  Then:

```bash
labctl rebuild
```

---

## Binary Sync — HTML Download Issues

**Symptom:** `sync-binaries.sh` reports "HTML/XML detected" or downloads are
rejected after `file(1)` validation.

**Cause:** The download returned an HTML error page instead of the actual
binary.  Common reasons:

| Cause | Fix |
| ------- | ----- |
| Wrong release tag in `binaries.tsv` | Check the actual tag on the GitHub releases page |
| Rate-limited by GitHub API | Set `GITHUB_TOKEN=ghp_xxx` (raises limit from 60 → 5,000 req/hr) |
| Asset name mismatch | Run `labctl sync --dry-run` to see available asset names |
| Repo is private | Ensure `GITHUB_TOKEN` has `repo` scope |

The sync script uses the GitHub Releases API — not HTML scraping — so
browser-style download URLs will not work in the manifest.

**Debug:**

```bash
labctl sync --name chisel --dry-run    # preview what would be fetched
GITHUB_TOKEN=ghp_xxx labctl sync       # retry with auth
```

---

## Builder Container

**The builder has no tmux** — by design.  It is a headless cross-compilation
environment.  All operator work happens in `kali-main`.

```bash
labctl shell builder          # raw shell if needed
```

The builder is only started when using `labctl launch build` or
`labctl up --builder`.

---

## Update Failures

**Symptom:** `labctl update` reports a build failure.

**Behavior:** Running containers are **not** destroyed.  The operator can
continue using the previous images while diagnosing the build.

**Debug:**

```bash
labctl build                  # retry build interactively
labctl build --no-cache       # force clean rebuild
```

If the issue is in the repo pull:

```bash
cd <repo-dir>
git status                    # check for local modifications
git stash                     # stash changes
labctl update --pull --force
```

---

## Nuclear Reset

Destroys all containers and images but preserves `/opt/lab`:

```bash
labctl clean
labctl rebuild
labctl up
```

Full reset including `/opt/lab` (destructive — all engagement data lost):

```bash
labctl clean
sudo rm -rf /opt/lab
sudo labctl bootstrap
labctl sync
labctl build
labctl up
```

---

## Shell Tests

The `tests/` directory contains automated tests for script logic.  They run in
sandboxed temp directories and do not require Docker, network, or a specific OS.

```bash
bash tests/run-all.sh
```

If a test fails, the output identifies the exact assertion and expected vs actual
value.  Fix the script, re-run, and confirm all assertions pass before pushing.

Tests do **not** cover Docker operations, GPU detection, network-dependent
downloads, or host provisioning.  Use `labctl verify` on a live host for those.
