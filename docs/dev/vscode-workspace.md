# VS Code multi-root workspace

This document covers the shared VS Code workspace for **Empusa** and
**Hecate-bootstrap** contributor workflows.

## What this is

A single `.code-workspace` file that gives contributors a unified
IDE experience across both repos without merging them.  Settings,
tasks, launch configs, and extension recommendations all live in
`empusa-hecate.code-workspace` at the parent folder level.

The `.code-workspace` file is the **canonical contributor workflow**.
Opening the parent folder directly works but is not the documented
path.

## Prerequisites

| Tool | Version | Notes |
| ------ | ------ | ------ |
| Python | 3.12 (local dev) | Empusa supports 3.9+; dev tooling targets 3.12 |
| pip | current | Bundled with Python |
| Git | 2.x | |
| ShellCheck | 0.9+ | `apt install shellcheck` on Ubuntu |
| Docker | 24+ | Optional — only for container workflows |
| VS Code | 1.90+ | Multi-root workspace support |

**Windows additionally**: Git for Windows (provides `bash.exe` at
`C:\Program Files\Git\bin\bash.exe`).

## Getting the workspace file

A tracked reference copy lives in this repo:

```md
hecate-bootstrap/docs/dev/empusa-hecate.code-workspace.example
```

Copy it to the parent folder above both repos (one level up):

```bash
cp hecate-bootstrap/docs/dev/empusa-hecate.code-workspace.example \
   empusa-hecate.code-workspace
```

The live copy at the parent level is `.gitignore`d (it sits outside
both repos).  The `.example` in this repo is the canonical, versioned
reference.

## Opening the workspace

```bash
code empusa-hecate.code-workspace
```

Or: **File → Open Workspace from File…** and select the file from the
parent folder above both repos.

VS Code will prompt to install recommended extensions on first open.
Accept — they cover Python, Ruff, ShellCheck, GitLens, Markdown,
TOML/YAML, Mermaid, and Docker.

## Empusa venv setup

```bash
cd empusa
python3 -m venv .venv
source .venv/bin/activate        # Linux/macOS
# .venv\Scripts\activate         # Windows
pip install -e ".[dev]"
```

VS Code's Python extension auto-discovers `.venv` as the interpreter.
If it doesn't, use **Python: Select Interpreter** from the command
palette and point at `empusa/.venv`.

## Tasks

Run from the command palette: **Tasks: Run Task**.

### Empusa

| Task | What it does |
| --- | --- |
| **Empusa: Ruff format** | Auto-format Python source and tests |
| **Empusa: Ruff check** | Lint (default build task — `Ctrl+Shift+B`) |
| **Empusa: Pytest all** | Full test suite (default test task) |
| **Empusa: Pytest current file** | Tests in the open file only |
| **Empusa: Pytest nearest** | Prompts for a test name, runs with `-k` |
| **Empusa: Pytest contract** | Contract-pinning test subset |
| **Empusa: format + lint + test** | Compound: format → lint → test (stops on failure) |

### Hecate

| Task | What it does |
| --- | --- |
| **Hecate: Run shell tests** | `tests/run-all.sh` — full TAP suite |
| **Hecate: Run Empusa contract test** | Cross-repo contract validation |
| **Hecate: Run launch-lab test** | launch-lab.sh test suite |
| **Hecate: Run create-workspace test** | create-workspace.sh test suite |
| **Hecate: shell test suite** | Compound wrapper for the full suite |

### Cross-repo

| Task | What it does |
| --- | --- |
| **Cross-repo: Contract sanity** | Empusa contract tests → Hecate contract test |
| **Cross-repo: Release sanity** | Read-only: version consistency, changelog, lint, tests across both repos |

Release sanity **never** creates tags, mutates files, or publishes.  It
runs `scripts/dev/release-sanity.sh` (a small helper kept in the Hecate
repo because the version/changelog checks require nested quoting that
makes an inline task brittle).

## Launch / debug configs

From the Run and Debug panel (`Ctrl+Shift+D`):

| Config | What it does |
| --- | --- |
| **Empusa: interactive** | Run `python -m empusa` in the integrated terminal |
| **Empusa: pytest file** | Run pytest on the currently open test file |
| **Empusa: debug current test** | Debug a single test by name with breakpoints |

### Hecate scripts

Phase 1 does **not** include a Bash debugger extension.  Run Hecate
scripts via the tasks panel or directly in the integrated terminal:

```bash
cd hecate-bootstrap
bash tests/test_launch_lab.sh
bash scripts/launch-lab.sh --help
```

## Linux-first behavior

The workspace assumes Ubuntu 24.04 with Bash as the default terminal.
All tasks use Linux-native commands.  ShellCheck, Ruff, and pytest run
identically on Linux.

What this means in practice:

- The default integrated terminal is Bash.
- Hecate shell tasks invoke `bash` directly.
- Python tasks use `python` (resolved from the active venv).

## Windows compatibility

Windows is a **secondary path**.  Support relies on Git for Windows:

1. Install [Git for Windows](https://git-scm.com/download/win) (the
   default installer places `bash.exe` at
   `C:\Program Files\Git\bin\bash.exe`).
2. The workspace configures Git Bash as the default Windows terminal.
3. Every Hecate/cross-repo task has a `windows.options.shell` override
   pointing at Git Bash.

**Known limitations on Windows**:

- ShellCheck must be installed separately (`scoop install shellcheck`
  or download the binary).
- Hecate tests that rely on Linux-only features (`/proc`, `strace`,
  etc.) will skip or fail — this is expected since Hecate targets Linux
  hosts.

## Repo-local `.vscode`

`empusa/.vscode/settings.json` exists with a narrow, repo-local-only
override.  All shared workspace settings live in the `.code-workspace`
file.  Do not duplicate shared settings into repo-local files.

Hecate has no `.vscode/` directory and does not need one.
