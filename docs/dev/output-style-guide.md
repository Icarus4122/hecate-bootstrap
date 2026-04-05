# labctl Output Style Guide

This document defines the visual language for all `labctl` subcommands and
supporting scripts.  Every operator-facing message should follow these rules
so that output is scannable, consistent, and actionable.

---

## 1. Banner

Long-running multi-step scripts (bootstrap, verify, update) open with a
**box banner**.  Short subcommands (`up`, `down`, `build`, `shell`) do not.

```
╔══════════════════════════════════════════════════════════════╗
║  Hecate · <Context> · <date or detail>                      ║
╚══════════════════════════════════════════════════════════════╝
```

Rules:
- One banner per invocation, at the very top.
- Box width is **62 characters** (inner).
- `<Context>` is the script purpose: `Host provisioning`, `Host verification`,
  `Update`, `Binary sync`.
- Optional trailing metadata: date (`2025-04-05`), flags, or mode.
- No banner for single-action subcommands (`up`, `down`, `build`, `shell`,
  `rebuild`, `clean`, `workspace`, `logs`).

---

## 2. Section Headers

Within multi-step scripts, each logical phase gets a **thin rule header**:

```
── <N>/<Total>  <Title> ──
```

Example:
```
── 3/9  Docker health ──
```

Rules:
- Use `──` (two em-dashes) as the rule character.
- Numbered steps use `<N>/<Total>` format for progress awareness.
- Unnumbered sections (e.g., summaries) use a descriptive title only:
  `── Summary ──`.
- Always preceded by one blank line.
- Never nested — sections are flat.

---

## 3. Status Markers (Vocabulary)

Every line of operational output starts with a **bracketed token** at a
**fixed indent** (2 spaces before the bracket).

| Token   | Meaning           | When to use |
|---------|-------------------|-------------|
| `[✓]`  | Pass / success    | A check passed, a step succeeded, a final "done" message |
| `[✗]`  | Fail / error      | A check failed, an operation hit a fatal error |
| `[!]`  | Warning / caution | Non-fatal issue, degraded but functional, operator attention needed |
| `[*]`  | Info / progress   | Neutral informational line, "now doing X", status update |
| `[=]`  | Skipped / no-op   | Step was skipped, item already current, nothing to do |
| `[~]`  | Changed / diff    | Something differs from expected (e.g., file size mismatch) |
| `[+]`  | Added / new       | New file downloaded, new directory created |

### Indentation

```
  [✓]  Item passed                    ← 2-space indent, then token, then 2 spaces, then text
       Remediation or detail line     ← 7-space indent (aligned under text above)
```

Detail lines (remediation, notes) are indented to align with the text
after the token — **7 spaces** from the left margin.

---

## 4. Pass / Warn / Fail Semantics

| Level   | Blocks progress? | Blocks `labctl update`? | Operator action required? |
|---------|:----------------:|:-----------------------:|:-------------------------:|
| Pass    | No               | No                      | No                        |
| Warn    | No               | No                      | Optional / at convenience |
| Fail    | Yes              | Yes                     | Must fix before continuing|

- **A single fail** means the host is not ready.  Exit code 1.
- **Warnings only** means the lab is functional.  Exit code 0.
- **All pass** means the host is fully ready.  Exit code 0.

---

## 5. Remediation Format

When a check fails or warns, print a **Fix** line immediately after:

```
  [✗]  Docker daemon unreachable
       Fix: sudo systemctl start docker
       Fix: sudo usermod -aG docker $USER && newgrp docker
```

Rules:
- `Fix:` prefix (capitalised, followed by a colon and a space).
- One fix per line.  Multiple alternatives get multiple `Fix:` lines.
- The fix must be a **copy-pasteable command** — no placeholders unless
  truly variable (e.g., `$USER`).
- Supplementary context uses plain text (no prefix):
  ```
       Docker may not be running, or the current user is not in the docker group.
  ```

---

## 6. Summary Format

Multi-step scripts end with a **summary block**:

```
── Summary ──────────────────────────────────────────────────

  ✓ 22 passed   ! 2 warnings   ✗ 0 failed

  Result: Host is ready.

  Next steps:
    labctl build            Build container images
    labctl up               Start the lab
```

Rules:
- Header is `── Summary ──` with trailing dashes to fill width.
- Counter line uses **bare tokens** (no brackets): `✓`, `!`, `✗`.
- **Result** line: one sentence, plain English.
  - `Host is ready.`
  - `Host is usable but has warnings.`
  - `Host is NOT ready — fix the failed items above.`
  - `Sync complete.`
  - `Update complete.`
  - `Update completed with warnings.  Review items above.`
- When fails > 0, reprint the failed items in the summary so the
  operator doesn't have to scroll.

---

## 7. "Next Steps" Blocks

When the operator needs to do something after the script finishes, print a
**Next steps** block inside the summary:

```
  Next steps:
    labctl build            Build container images
    labctl up               Start the lab
    labctl launch default   Enter kali-main with tmux
```

Rules:
- `Next steps:` label, indented 2 spaces, followed by a colon.
- Each step is a **copy-pasteable command** with a short description.
- Commands are left-aligned at 4-space indent; descriptions start at a
  consistent column (use at minimum 2-space gap after the longest command).
- At most 5 steps.  If more context is needed, point to a doc:
  `See docs/troubleshooting.md for more detail.`
- Quick-action blocks in `labctl status` use the same format but with
  a 2-column layout for compactness.

---

## 8. When to Print Paths

| Situation | Print the path? |
|-----------|:---------------:|
| Workspace created or detected | Yes — full path |
| Lab root referenced in error | Yes — `$LAB_ROOT` value |
| Remediation command that uses a path | Yes — absolute |
| Successful lifecycle action (up, down) | Only `$LAB_ROOT` in "data intact" message |
| Normal progress (building, syncing) | No — paths add noise |

---

## 9. When to Print Example Commands

| Situation | Print examples? |
|-----------|:---------------:|
| Error message with fix | Always — in `Fix:` lines |
| Summary / next-steps | Always |
| Unknown flag or subcommand | Always — show `labctl help <cmd>` |
| Bare invocation with no flags | One-time hint showing common patterns |
| Normal success | Only the immediate next command (e.g., `labctl up`) |
| Help text | Yes — in `Examples:` section of each `cmd_help_*` |

---

## 10. Colour

No ANSI colours.  The tokens `[✓]`, `[✗]`, `[!]` provide enough visual
structure in any terminal.  This keeps output clean when piped, redirected,
or viewed in CI logs.

---

## 11. Error Messages (stderr)

Fatal errors go to stderr.  Format:

```
[✗] What went wrong.
    Why it probably happened.
    Fix: copy-pasteable remediation command
```

Always three parts when possible:
1. **What** — one sentence, `[✗]` prefix.
2. **Why** — brief context (optional but preferred).
3. **Fix** — actionable command.

---

## 12. Success Messages

Single-line, `[✓]` prefix, with the obvious next command:

```
[✓] Lab is running.  Next: labctl shell
[✓] Images built.  Next: labctl up
[✓] Lab stopped.  Data in /opt/lab is intact.
```

---

## 13. File Reference

| File | Role |
|------|------|
| `labctl` | Dispatcher — success/fail one-liners, pre-flight guards, help text |
| `scripts/verify-host.sh` | Read-only checker — full pass/warn/fail + summary |
| `scripts/bootstrap-host.sh` | Multi-step provisioner — banner + step headers + final next-steps |
| `scripts/sync-binaries.sh` | Manifest sync — per-entry progress + summary |
| `scripts/update-lab.sh` | Update orchestrator — banner + step headers + summary |
| `scripts/launch-lab.sh` | Launch flow — structured summary block before container entry |
| `scripts/create-workspace.sh` | Workspace creator — minimal output, one result line |
| `scripts/guide.sh` | Interactive guide — headings + explain blocks (exempt from compact rules) |
