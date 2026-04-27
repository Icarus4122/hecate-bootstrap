# Evidentia Integration Contract

This document describes Hecate's responsibility for the
[Evidentia](https://github.com/Icarus4122/Evidentia) evidence runtime
on the lab host.

Hecate's role is **environmental only**: it verifies that an
`evidentia` binary, if present, responds correctly to its documented
`version` command. Hecate does not install Evidentia, does not
understand Evidentia schemas, does not call workflow commands
(`ingest`, `replay`, `audit`), and does not open Evidentia's
persistent stores. The Empusa wrapper is the only component in this
workspace permitted to invoke Evidentia workflow commands, and
Evidentia never writes to Empusa workspace state on its own.

## Boundary

| System    | Owns                                                        |
| --------- | ----------------------------------------------------------- |
| Hecate    | Binary availability, PATH, JSON-shape sanity on `version`   |
| Empusa    | All Evidentia workflow invocations (via `empusa.evidentia`) |
| Evidentia | Schemas, stores, lifecycle, replay, audit                   |

Hecate must not:

- call `evidentia ingest`, `evidentia replay`, or `evidentia audit`
- open or read Evidentia's Badger store
- parse Evidentia output beyond the documented `version` field
- interpret any other Evidentia schema

## Installation Path

The canonical Hecate toolchain location for the binary is:

```text
${LAB_ROOT}/tools/binaries/evidentia/evidentia
```

Empusa accepts the binary from either:

1. the system `PATH` (whatever `command -v evidentia` resolves), or
2. the canonical toolchain path above (used when `PATH` lookup fails).

Empusa code may also override the path explicitly via its own
`--binary` flag; that override path is not Hecate's concern.

### Shared environment variables (Phase 18)

Empusa and Hecate honor the same shared environment contract for
locating Evidentia. CLI flags always win; the environment variable
wins over the discovery fallbacks.

| Variable | Used by | Purpose |
| --- | --- | --- |
| `EVIDENTIA_BINARY` | Empusa, Hecate | Pin a specific `evidentia` binary path. Hecate's `verify-host.sh` uses it before falling back to `PATH` and the toolchain location; if it is set but does not point at an executable, the check `[FAIL]`s clearly rather than silently falling back. |
| `EVIDENTIA_DB_PATH` | Empusa only | Override the Badger store directory passed by the Empusa wrapper. Hecate has no use for this variable; it never opens the store. |
| `LAB_ROOT` | Hecate, Empusa | Root of the Hecate toolchain used to derive the canonical binary path above. |

Resolution precedence for the binary, in order:

1. `--binary` (Empusa CLI) or the explicit kwarg (Empusa wrapper)
2. `EVIDENTIA_BINARY`
3. `PATH` (`command -v evidentia`)
4. `${LAB_ROOT}/tools/binaries/evidentia/evidentia`
   (and `evidentia.exe` on Windows for the Empusa side)

### Install status

**Installation is manual.** Hecate does not ship release automation
for Evidentia. Specifically:

- `scripts/sync-binaries.sh` does not download or refresh the
  `evidentia` binary.
- `scripts/update-lab.sh` and `scripts/update-empusa.sh` do not
  update Evidentia.
- `manifests/binaries.tsv` and `manifests/apt-host.txt` do not
  declare Evidentia.

The operator is responsible for building or copying an `evidentia`
binary into either `PATH` or the canonical toolchain location above.
The only Hecate touch point is the read-only `verify-host.sh`
readiness check described below.

## Verification

`scripts/verify-host.sh` includes an Evidentia readiness check
(step `10/10`). The check is read-only and does the following:

1. If `EVIDENTIA_BINARY` is set, validate that it points at an
   executable file. If yes, use it; if no, `[FAIL]` immediately
   without falling back (a misconfigured pin is surfaced rather
   than silently ignored).
2. Otherwise resolve the binary via `command -v evidentia`, then
   fall back to `${LAB_ROOT}/tools/binaries/evidentia/evidentia`.
3. If neither resolves, emit a `[WARN]` (not a `[FAIL]`) — Empusa's
   Evidentia integration is optional.
4. If the binary is found, run `evidentia version` and capture
   stdout.
5. Validate that stdout is **exactly** a JSON object with one key,
   `version`, whose value is a non-empty string. Whitespace around
   tokens is permitted; wrapped JSON, multiline garbage, additional
   keys, or unrelated payloads are rejected. Validation is performed
   by `python3 -c json.loads(...)` with a strict shape check —
   Hecate does not interpret the version value or any other
   Evidentia schema.
6. Emit `[PASS]` when both the binary and the JSON shape are valid;
   emit `[FAIL]` when the binary exists but `version` exits non-zero
   or returns output that does not match the contract.

This check is intentionally minimal. Hecate's only contract with
Evidentia is the binary's existence and the exact `evidentia version`
JSON shape. Hecate does not understand any other Evidentia schemas
(events, observations, capabilities, audits, replay diffs).

## Failure Modes

| State                                       | Result | Operator action                        |
| ------------------------------------------- | ------ | -------------------------------------- |
| `EVIDENTIA_BINARY` set but not executable   | FAIL   | Fix the path or `unset EVIDENTIA_BINARY`. |
| Binary missing on PATH and toolchain path   | WARN   | Install to the toolchain path or PATH. |
| Binary present, `evidentia version` fails   | FAIL   | Reinstall; check execute permission.   |
| `version` succeeds but output shape invalid | FAIL   | Reinstall a contract-compliant build.  |
| Binary present, valid JSON                  | PASS   | None.                                  |

The `[WARN]` state is intentional: Empusa workspaces operate without
Evidentia by default. The Evidentia consumer in Empusa (and the
`evidentia` plugin) only require the binary when explicitly invoked.

## Recommended operator entry point

Once `verify-host.sh` reports `[PASS]`, the recommended operator
command for an end-to-end workspace evidence summary is the
Empusa-side composition:

```bash
empusa evidentia report --workspace <workspace>
```

This composes `evidentia inspect workspace-summary` with a
read-only `evidentia replay` and emits a single Empusa-owned
report artifact. Hecate has no responsibility for this command;
it is documented here only as a forward pointer so operators
landing in this file know where to go next. Workflow ownership
remains with Empusa.

## Source of Truth

The authoritative integration sources live in sibling repositories:

- Empusa's CLI consumer module: `empusa/empusa/evidentia.py` in the
  [`Icarus4122/empusa`](https://github.com/Icarus4122/empusa)
  repository.
- Evidentia's consumer-side integration contract:
  `docs/integration/empusa-evidentia.md` in the
  [`Icarus4122/Evidentia`](https://github.com/Icarus4122/Evidentia)
  repository.

Deep links are intentionally omitted: those files may move between
branches and tags, and a stale deep link is worse than a repository
reference. Browse to the file via the repository's default branch.

When the contract documents conflict with this file on workflow
behavior, the consumer-side contract wins. This document only
governs binary availability and the verification surface.
