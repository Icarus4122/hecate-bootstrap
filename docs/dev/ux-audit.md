# labctl UX Audit — First-Time Operator Experience

> **Status: historical audit (2026-04-05).** Recommendations in this
> document predate the canonical UI vocabulary migration.  The current
> Hecate vocabulary is `[PASS]`, `[FAIL]`, `[WARN]`, `[INFO]`,
> `[ACTION]` (see `scripts/lib/ui.sh` and `docs/dev/output-style-guide.md`).
> Where this audit recommends `[✓]`/`[✗]`/`[!]`, treat those as the
> *intent* — the implemented form uses the bracketed-word tokens.

**Date:** 2026-04-05
**Scope:** End-to-end labctl flow for a first-time operator on Ubuntu 24.04

---

## 1. Prioritized UX Problem List

### P0 — Blocks or confuses novices on first run

| # | Problem | File(s) | Impact |
|---|---------|---------|--------|
| 1 | **`labctl help` uses jargon without context.** Categories like "LIFECYCLE", "TOOLING", "WORKFLOW", "OPS" don't tell a newcomer *what to do first* or *what order to follow*. No quick-start breadcrumb. | `labctl` | Novice stares at 30 lines of undifferentiated commands with no entry point. |
| 2 | **No first-run detection or guided nudge.** If `/opt/lab` doesn't exist or `.env` is missing, `labctl up` just fails inside compose with a Docker volume error. No preamble, no "did you bootstrap?" check. | `labctl` | Most common first-run failure has no actionable message. |
| 3 | **`verify-host.sh` has a typo bug.** Line 89: `_faile` instead of `_fail`. The Docker-unreachable check silently crashes with `set -e`, masking the real diagnostic. | `scripts/verify-host.sh` | Critical pre-flight check silently aborts mid-run. |
| 4 | **`labctl up` success message gives no context.** It prints `[✓] Lab is running.  Attach: labctl shell` — but doesn't mention `labctl launch` (the richer path) or `labctl status`. A newcomer types `labctl shell` and lands in a bare bash prompt with no orientation. | `labctl` | Missed opportunity to guide toward the tmux/workspace flow. |
| 5 | **`labctl launch` with no args exits silently via `usage()`.** The usage text is buried in `launch-lab.sh` and prints to stdout then `exit 0`. A novice running `labctl launch` gets a wall of text with no error signal. | `scripts/launch-lab.sh` | Ambiguous: did it work? Did it fail? |

### P1 — Degrades experience, causes confusion

| # | Problem | File(s) | Impact |
|---|---------|---------|--------|
| 6 | **Inconsistent banner styling.** `bootstrap-host.sh`, `verify-host.sh`, and `update-lab.sh` all use `╔═══╗` box banners but with different widths and alignment padding. `cmd_status` in `labctl` uses a different style (`═══ Lab Status ═══`). `sync-binaries.sh` has no banner. | Multiple | Platform feels like several tools bolted together. |
| 7 | **Inconsistent prefix vocabulary.** `[*]`, `[✓]`, `[!]`, `[=]`, `[+]`, `[~]`, `[PASS]`, `[WARN]`, `[FAIL]`, `✗`, `✓`, `~`, `⚠` are all used across scripts. Some use brackets, some use bare Unicode. `verify-host.sh` uses `[PASS]`/`[WARN]`/`[FAIL]` while `update-lab.sh` uses `[✓]`/`[=]`/`[!]`. | Multiple | Operator can't scan output by shape — each script trains different muscle memory. |
| 8 | **`labctl tmux` (no args) lists profile filenames, not descriptions.** Output is bare filenames (`build`, `default`, `htb`, `research`) with no explanation of what each profile sets up or which `launch` profiles use them. | `labctl` | Novice can't choose a profile without reading source. |
| 9 | **`labctl workspace` (no args) shows `ls -1` of workspaces with no column headers and no profile info.** Compare to `labctl status` which at least labels sections. | `scripts/create-workspace.sh` | Can't tell which profile a workspace was created with. |
| 10 | **Unknown-flag errors are terse.** `labctl up --foo` prints `[!] Unknown flag: --foo` with no "see labctl help" hint. `create-workspace.sh` prints `[!] Unknown flag: $1 (ignored)` and *continues silently*. | Multiple | Novice doesn't know the flag was dropped. |
| 11 | **`labctl clean` destructive prompt doesn't show what will be removed.** It says "This removes containers, volumes, and dangling images" but doesn't list the actual container names or volume names. | `labctl` | Operator can't make an informed yes/no decision. |
| 12 | **No `labctl --version`.** No way to confirm which checkout/tag is running. | `labctl` | Hinders troubleshooting and bug reports. |

### P2 — Polish and discoverability gaps

| # | Problem | File(s) | Impact |
|---|---------|---------|--------|
| 13 | **`cmd_help` doesn't explain what `--hostnet` or `--gpu` mean** beyond the flag name. A novice doesn't know that `--hostnet` gives VPN passthrough and `--gpu` enables hashcat. | `labctl` | Operator guesses or ignores useful flags. |
| 14 | **`labctl build` prints no summary.** Just raw Docker build output, then silence on success. Compare to `labctl rebuild` which prints `[✓] Rebuilt.  Run: labctl up`. | `labctl` | Inconsistent success feedback. |
| 15 | **`labctl down` has no confirmation or status echo.** Operator can't tell if it worked without running `labctl status` manually. | `labctl` | Ambiguous outcome. |
| 16 | **`labctl logs` with no container defaults to all-container interleaved logs.** For a novice, this is usually not what they want. A hint like "Tip: labctl logs kali-main" would help. | `labctl` | Overwhelming output for newcomers. |
| 17 | **Tmux profiles are minimal.** Each profile creates 2 windows with no panes, no welcome messages, no status hints. The `htb.sh` profile doesn't display the target name or workspace path in the window. | `tmux/profiles/*.sh` | Novice enters tmux and doesn't know where they are or what the workspace layout is. |
| 18 | **`labctl status` doesn't show Empusa status** or the active workspace. It shows containers, VPN, GPU, disk — but the workspace/engagement context is missing. | `labctl` | Operator can't see what workspace is active without `ls /opt/lab/workspaces`. |
| 19 | **`bootstrap-host.sh` "Next steps" box uses `vim .env`** — not everyone uses vim. Should say "edit .env" or recommend `$EDITOR .env`. | `scripts/bootstrap-host.sh` | Minor assumption that may confuse nano/emacs users. |
| 20 | **`labctl update` with no flags does nothing useful.** `--pull`, `--empusa`, `--binaries` are all opt-in. A bare `labctl update` runs verify + build + restart, which is reasonable, but the "Skipped (use --X to enable)" messages dominate the output and give the impression nothing happened. | `scripts/update-lab.sh` | Unclear value of running `labctl update` without flags. |

---

## 2. File-Level Recommendations

### `labctl` (main dispatcher)

| Line(s) | Recommendation |
|----------|----------------|
| `cmd_help()` | Rewrite with a "Getting Started" section at top. Add one-line descriptions of what `--gpu` and `--hostnet` do. Add `labctl --version`. |
| `cmd_up()` | Add pre-flight guard: if `$LAB_ROOT` doesn't exist, print remediation and exit 1. On success, show 2-3 "next step" hints. |
| `cmd_down()` | Print `[✓] Lab stopped.` on success. |
| `cmd_build()` | Print `[✓] Build complete.  Run: labctl up` on success (match `cmd_rebuild`). |
| `cmd_shell()` | On success entry, no change needed. On failure (container not running), catch and print remediation. |
| `cmd_tmux()`, no-arg case | Show profile name + one-line description. |
| `cmd_status()` | Add Empusa version + active workspace display. |
| `cmd_clean()` | Before confirmation, show `_compose ps` and `docker volume ls` scoped to project. |
| Unknown cmd case | Append `Run 'labctl help' for available commands.` |
| New: `cmd_version()` | Print repo origin + HEAD short SHA + date. |

### `scripts/verify-host.sh`

| Line | Recommendation |
|------|----------------|
| 89 | **Bug fix:** `_faile` → `_fail`. |
| `print_summary()` | When FAIL > 0, list the specific failed items again (don't make operator scroll up). |
| Banner date | Box width is hardcoded. Dynamic date can push the closing `║` out of alignment. Use `printf` with padding. |

### `scripts/bootstrap-host.sh`

| Section | Recommendation |
|---------|----------------|
| "Next steps" box | Replace `vim .env` with `$EDITOR .env` (or just `edit .env`). |
| Step banners | Use consistent `N/TOTAL` format — already good, keep it. |
| Exit | Print `labctl verify` as a suggested validation step after re-login. |

### `scripts/launch-lab.sh`

| Line(s) | Recommendation |
|---------|----------------|
| `usage()` | When called with no args from `labctl launch`, print as an error (exit 1) not a success (exit 0). |
| `launch_htb()` | On missing target, suggest `labctl workspace` to list existing workspaces. |
| `enter_kali()` | Print a "Launching profile: <name>" line before exec so the operator knows what's happening during container startup delay. |

### `scripts/create-workspace.sh`

| Section | Recommendation |
|---------|----------------|
| No-name path | The workspace listing should show creation dates or profiles if available. |
| Unknown-flag handling | Change "ignored" to hard error — silently dropping flags is worse than failing. |

### `scripts/update-lab.sh`

| Section | Recommendation |
|---------|----------------|
| Summary | Bold/highlight failures. Print "nothing was opted-in" hint if all optional steps were skipped. |

### `scripts/sync-binaries.sh`

| Section | Recommendation |
|---------|----------------|
| Top-of-run | Add a banner matching the house style. |
| Missing `GITHUB_TOKEN` | Print advisory once if unset (not an error, just a heads-up about rate limits). |

### `tmux/profiles/*.sh`

| All profiles | Recommendation |
|--------------|----------------|
| After session creation | Send a welcome message to the first pane: workspace path, IP of tun0 if available, useful aliases. |

---

## 3. Output Style Guide for labctl and Related Scripts

### Principles

1. **Scannable.** Every line of output should be parseable by eye in under 1 second.
2. **Consistent.** Same prefixes, same alignment, same vocabulary across all scripts.
3. **Actionable.** When something fails, say what to run next. When something succeeds, say what to do next.
4. **Progressive disclosure.** Default output is compact. `--verbose` (future) adds detail.

### Prefix Tokens

Use these and only these across all `labctl` scripts:

| Token | Meaning | When |
|-------|---------|------|
| `[✓]` | Success / step completed | After a successful operation |
| `[✗]` | Failure / step failed | After a failed operation |
| `[!]` | Warning / attention needed | Non-fatal issues, needs operator review |
| `[*]` | Informational / in-progress | Status updates, step starting |
| `[=]` | Skipped | Step was deliberately skipped |

**Retire:** `[PASS]`/`[WARN]`/`[FAIL]` (verify-host), bare `✓`/`✗`/`~`/`⚠` (various), `[+]`/`[~]` (sync-binaries).

> **Migration note for `verify-host.sh`:** Map `[PASS]` → `[✓]`, `[WARN]` → `[!]`, `[FAIL]` → `[✗]`. This is the single biggest visual consistency win.

### Banners

Use for command-level entry points (not for internal functions):

```
── <Title> ──────────────────────────────────────────────
```

For major scripts with multi-step flows, use a box banner at the top only:

```
╔═══════════════════════════════════════════════════════╗
║  Hecate · <Context> · <Dynamic Info>                  ║
╚═══════════════════════════════════════════════════════╝
```

Use `printf` to right-pad the dynamic content so `║` aligns correctly.

### Section Headers

For numbered steps within a script:

```
── 3/8  Docker Engine ───────────────────────────────────
```

### Summaries

Every multi-step command should end with a summary block:

```
── Summary ──────────────────────────────────────────────
  ✓  3 passed
  ✗  1 failed
  !  2 warnings

  Next: <actionable next step>
```

### Error Messages

Structure: **what happened** → **why it might have happened** → **what to do**.

```
[✗] Docker daemon unreachable.
    Docker may not be running or the current user is not in the docker group.
    Fix: sudo systemctl start docker
    Fix: sudo usermod -aG docker $USER && newgrp docker
```

### Colors (optional, future)

If color is added later, use it as enhancement, not information carrier. All output must be readable without color (piped to `tee`, `less`, or a log file).

### Post-Command Hints

After major commands (`up`, `down`, `build`, `bootstrap`), print 1-2 "next step" suggestions:

```
[✓] Lab is running.
    Shell:    labctl shell
    Launch:   labctl launch default
    Status:   labctl status
```

---

## 4. Patch Plan — Top 5 Highest-Value Changes

### Patch 1: Fix `_faile` typo in verify-host.sh

**File:** `scripts/verify-host.sh` line 89
**Change:** `_faile` → `_fail`
**Why:** This is a crash bug in the most important pre-flight check. With `set -e`, calling an undefined function aborts the script silently mid-run. Docker health check never reports failure.
**Risk:** Zero.
**Acceptance criteria:** `labctl verify` on a host where Docker is stopped prints `[FAIL]  Docker daemon unreachable (is dockerd running?)` and continues to remaining checks.

---

### Patch 2: Rewrite `cmd_help()` with getting-started guidance

**File:** `labctl`
**Change:** Add a "FIRST TIME?" section at the top of help output. Add short explanations for `--gpu` and `--hostnet`. Add `labctl --version`.
**Why:** The single most-viewed output for any CLI. Currently organized for someone who already knows the tool. A 3-line getting-started block makes the path obvious.
**Risk:** Low — cosmetic change to output.
**Acceptance criteria:**
- `labctl help` starts with a "QUICK START" block showing the bootstrap → build → up flow.
- `--gpu` and `--hostnet` have one-line descriptions.
- `labctl --version` prints repo info.
- Existing `labctl help` content remains, lightly reorganized.

---

### Patch 3: Add pre-flight guard to `cmd_up()`

**File:** `labctl`
**Change:** Before calling `_compose up`, check that `$LAB_ROOT` exists and `.env` is present. On failure, print specific remediation.
**Why:** The #1 first-run failure mode. Docker compose errors about missing bind-mount sources are cryptic. A 5-line guard converts them into a clear "run `sudo labctl bootstrap` first" message.
**Risk:** Low — adds a guard before the existing compose call.
**Acceptance criteria:**
- Running `labctl up` when `/opt/lab` doesn't exist prints: `[✗] /opt/lab does not exist.` + `Run: sudo labctl bootstrap`.
- Running `labctl up` when `.env` is missing prints: `[!] .env not found. Copy from .env.example:` + `cp .env.example .env`.
- Normal `labctl up` path is unaffected.

---

### Patch 4: Unify output prefixes in verify-host.sh

**File:** `scripts/verify-host.sh`
**Change:** Replace `[PASS]`/`[WARN]`/`[FAIL]` with `[✓]`/`[!]`/`[✗]` to match the style guide. Update summary to reprint failed items.
**Why:** Largest single consistency win. `verify-host.sh` is run frequently and its output style currently diverges from every other script. Reprinting failures in the summary saves scrolling.
**Risk:** Low — output-only change. Test assertions that match on `[PASS]`/`[FAIL]` etc. in `test_verify_host.sh` will need updating.
**Acceptance criteria:**
- All output lines use `[✓]`/`[!]`/`[✗]` prefixes.
- Summary block reprints each `[✗]` item.
- `tests/test_verify_host.sh` passes with updated assertions.

---

### Patch 5: Post-command hints for `up`, `down`, `build`, `launch`

**File:** `labctl`, `scripts/launch-lab.sh`
**Changes:**
- `cmd_up()`: after success, print shell/launch/status hints.
- `cmd_down()`: print `[✓] Lab stopped.`
- `cmd_build()`: print `[✓] Build complete.  Run: labctl up`.
- `labctl launch` with no args: exit 1 instead of exit 0, prepend `[✗] No profile specified.`.
- `launch_htb()` on missing target: include `labctl workspace` suggestion.
**Why:** Each of these is a moment where the operator is deciding what to do next. A 1-2 line hint keeps them moving without looking at docs.
**Risk:** Low — additive output only.
**Acceptance criteria:**
- `labctl up` success output includes "labctl shell" and "labctl launch" hints.
- `labctl down` prints confirmation line.
- `labctl build` prints next-step hint.
- `labctl launch` with no profile exits 1 with error prefix.
- `labctl launch htb` with no target suggests `labctl workspace`.

---

## 5. Before/After Terminal Output Examples

### 5a. `labctl help`

#### BEFORE

```
labctl - Offensive-security lab control

LIFECYCLE
  up [--gpu] [--hostnet] [--builder]   Start containers
  down                                 Stop containers
  build [--no-cache]                   Build images
  rebuild                              Build images (no cache)
  clean                                Remove containers / volumes / prune

INTERACTION
  shell [container]                    Exec into container (default: kali-main)
  logs  [container]                    Follow logs

TOOLING
  sync [-n NAME] [--dry-run]           Sync pinned binaries from manifests/binaries.tsv
  tmux  <profile>                      Launch a tmux session profile (inside container)

WORKFLOW
  launch <profile> [target]            Workspace + compose up + kali-main tmux session
                                       Profiles: default, htb, build, research
                                       Uses Empusa for workspace init when available
  workspace <name> [--profile P]       Create workspace via Empusa (htb|build|research|internal)
                                       Falls back to minimal scaffold without Empusa

OPS
  status                               Lab health, VPN, GPU, disk
  verify                               Pre-flight host checks (read-only)
  update [flags]                       Safe platform update (--pull --empusa --binaries
                                         --no-build --no-restart --builder --gpu
                                         --hostnet --force)
  bootstrap                            One-time host provisioning (sudo)
  help                                 This message

ENVIRONMENT
  LAB_ROOT       /opt/lab              Persistent data root
  LAB_GPU=1                            Stack GPU compose overlay
  LAB_HOSTNET=1                        Stack host-network compose overlay
```

#### AFTER

```
labctl - Offensive-security lab control

QUICK START (first time)
  1. sudo labctl bootstrap       Provision host and install dependencies
  2. labctl build                Build container images
  3. labctl up                   Start the lab
  4. labctl launch default       Enter kali-main with tmux

LIFECYCLE
  up [--gpu] [--hostnet] [--builder]   Start containers
  down                                 Stop and remove containers
  build [--no-cache]                   Build container images
  rebuild                              Build images from scratch (no cache)
  clean                                Remove containers, volumes, prune images

INTERACTION
  shell [container]                    Exec into container (default: kali-main)
  logs  [container]                    Follow container logs

TOOLING
  sync [-n NAME] [--dry-run]           Download pinned binaries from manifests/binaries.tsv
  tmux  <profile>                      Launch a tmux session profile (inside container)
                                       Profiles: default, htb, build, research

WORKFLOW
  launch <profile> [target]            Full launch: workspace + containers + tmux session
                                       Profiles: default, htb, build, research
  workspace <name> [--profile P]       Create engagement workspace (htb|build|research|internal)

OPS
  status                               Lab health — containers, VPN, GPU, disk
  verify                               Pre-flight host checks (read-only, safe to run anytime)
  update [flags]                       Safe platform update
                                       Flags: --pull --empusa --binaries --no-build
                                              --no-restart --builder --gpu --hostnet --force
  bootstrap                            One-time host provisioning (requires sudo)
  version                              Show version and repo info
  help                                 This message

ENVIRONMENT
  LAB_ROOT       /opt/lab              Persistent data root
  LAB_GPU=1                            Stack GPU overlay (enables hashcat / GPU workloads)
  LAB_HOSTNET=1                        Stack host-network overlay (direct VPN/tun0 access)
```

---

### 5b. `labctl verify`

#### BEFORE

```
╔═══════════════════════════════════════════════════════════╗
║  Hecate · Host verification · 2026-04-05                  ║
╚═══════════════════════════════════════════════════════════╝

── 1/9  Host OS ──
  [PASS]  Ubuntu 24.04 LTS (Ubuntu 24.04.2 LTS)

── 2/9  Required host commands ──
  [PASS]  docker - Docker version 27.5.1, build 9f9e405
  [PASS]  git - git version 2.43.0
  [PASS]  curl - curl 8.5.0 (x86_64-pc-linux-gnu)
  [PASS]  jq - jq-1.7.1
  [PASS]  file - found
  [PASS]  python3 - Python 3.12.3

── 3/9  Docker health ──
                                        <-- crashes here due to _faile typo
```

#### AFTER

```
╔═══════════════════════════════════════════════════════════╗
║  Hecate · Host verification · 2026-04-05                  ║
╚═══════════════════════════════════════════════════════════╝

── 1/9  Host OS ──
  [✓]  Ubuntu 24.04 LTS (Ubuntu 24.04.2 LTS)

── 2/9  Required host commands ──
  [✓]  docker - Docker version 27.5.1, build 9f9e405
  [✓]  git - git version 2.43.0
  [✓]  curl - curl 8.5.0 (x86_64-pc-linux-gnu)
  [✓]  jq - jq-1.7.1
  [✓]  file - found
  [✓]  python3 - Python 3.12.3

── 3/9  Docker health ──
  [✓]  Docker daemon is reachable
  [✓]  Docker Compose plugin available

── 4/9  /opt/lab directory tree ──
  [✓]  /opt/lab exists
  [✓]  /opt/lab/data
  [✓]  /opt/lab/tools
  ...

── Summary ──────────────────────────────────────────────
  ✓ 22 passed  |  ! 1 warning  |  ✗ 0 failed

  Host is ready.  Run: labctl up
```

---

### 5c. `labctl up`

#### BEFORE (when /opt/lab is missing)

```
 ⠿ Container lab-kali  Error
Error response from daemon: failed to create task for container:
failed to create shim task ... bind source path does not exist: /opt/lab/data
```

#### AFTER (when /opt/lab is missing)

```
[✗] /opt/lab does not exist.
    The lab host has not been provisioned yet.
    Run:  sudo labctl bootstrap
```

#### BEFORE (success)

```
[+] Running 1/1
 ✔ Container lab-kali  Started
[✓] Lab is running.  Attach: labctl shell
```

#### AFTER (success)

```
[+] Running 1/1
 ✔ Container lab-kali  Started
[✓] Lab is running.
    Shell:    labctl shell
    Launch:   labctl launch default
    Status:   labctl status
```

---

### 5d. `labctl launch research <topic>`

#### BEFORE

```
[*] [empusa] Creating workspace (research/lateral-movement)...
[empusa] workspace init ...
[*] Ensuring compose stack is running
[+] Running 1/1
 ✔ Container lab-kali  Running
[*] Entering kali-main -> research
```

#### AFTER

```
[*] Creating workspace: lateral-movement (profile: research)
    Using Empusa for full workspace support.
[✓] Workspace ready: /opt/lab/workspaces/lateral-movement

[*] Ensuring containers are running...
[✓] Containers up.

[*] Launching tmux profile: research
    Windows: research, notes
    Workspace: /opt/lab/workspaces/lateral-movement
```

---

### 5e. Failed dependency check

#### BEFORE (`labctl verify` — Docker not running)

```
── 3/9  Docker health ──
                                        <-- script crashes, _faile is undefined
```

#### AFTER

```
── 3/9  Docker health ──
  [✗]  Docker daemon unreachable.
       Docker may not be running or the current user is not in the docker group.
       Fix: sudo systemctl start docker
       Fix: sudo usermod -aG docker $USER && newgrp docker
  [✗]  Docker Compose plugin not found (docker compose version failed).
       Fix: sudo apt install docker-compose-plugin

── Summary ──────────────────────────────────────────────
  ✓ 6 passed  |  ! 0 warnings  |  ✗ 2 failed

  Failed items:
    ✗ Docker daemon unreachable
    ✗ Docker Compose plugin not found

  Host is NOT ready.  Fix the failed items above.
  Most can be resolved with:  sudo labctl bootstrap
```

---

## Appendix: Bug Reference

| Bug | File | Line | Severity |
|-----|------|------|----------|
| `_faile` typo (undefined function → crash under `set -e`) | `scripts/verify-host.sh` | 89 | **P0** — silent abort of pre-flight check |
