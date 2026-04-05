#!/usr/bin/env bash
# scripts/install-empusa.sh — Install, update, or reinstall Empusa.
#
# Empusa is the workspace / engagement environment manager.
# Repo:  ${LAB_ROOT}/tools/git/empusa
# Venv:  ${LAB_ROOT}/tools/venvs/empusa
#
# Usage:
#   install-empusa.sh install      Clone repo + create venv + editable install
#   install-empusa.sh update       git pull + re-run editable install
#   install-empusa.sh reinstall    Destroy venv, recreate, editable install
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
EMPUSA_REPO_URL="${EMPUSA_REPO:-https://github.com/Icarus4122/empusa.git}"
LAB_ROOT="${LAB_ROOT:-/opt/lab}"
REPO_DIR="${LAB_ROOT}/tools/git/empusa"
VENV_DIR="${LAB_ROOT}/tools/venvs/empusa"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: install-empusa.sh <command>

Commands:
  install     Clone the repo (if absent) and create a fresh venv with
              an editable install. Safe to rerun — skips steps already done.
  update      Pull latest changes and re-run the editable install.
  reinstall   Delete the existing venv, recreate it, and reinstall.
              The git repo is preserved.

Environment:
  LAB_ROOT       Base lab directory          (default: /opt/lab)
  EMPUSA_REPO    Git clone URL               (default: https://github.com/Icarus4122/empusa.git)
EOF
    exit 0
}

# ── Helpers ────────────────────────────────────────────────────────────────────
die()  { echo "[!] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok()   { echo "[✓] $*"; }

# ── Dependency check ──────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v git     &>/dev/null || missing+=(git)
    command -v python3 &>/dev/null || missing+=(python3)
    if ! python3 -m venv --help &>/dev/null; then
        missing+=(python3-venv)
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}
  On Ubuntu 24.04:  sudo apt install ${missing[*]}"
    fi
}

# ── Clone or verify repo ──────────────────────────────────────────────────────
ensure_repo() {
    if [[ -d "${REPO_DIR}/.git" ]]; then
        info "Repo already exists: ${REPO_DIR}"
    else
        if [[ -e "$REPO_DIR" ]]; then
            die "${REPO_DIR} exists but is not a git repo — remove it first"
        fi
        info "Cloning ${EMPUSA_REPO_URL}"
        mkdir -p "$(dirname "$REPO_DIR")"
        git clone "$EMPUSA_REPO_URL" "$REPO_DIR"
        ok "Cloned → ${REPO_DIR}"
    fi
}

# ── Pull latest ───────────────────────────────────────────────────────────────
pull_repo() {
    if [[ ! -d "${REPO_DIR}/.git" ]]; then
        die "Repo not found at ${REPO_DIR} — run 'install' first"
    fi
    info "Pulling latest changes"
    git -C "$REPO_DIR" pull --ff-only
}

# ── Create venv ───────────────────────────────────────────────────────────────
create_venv() {
    if [[ -d "$VENV_DIR" ]]; then
        info "Venv already exists: ${VENV_DIR}"
        return 0
    fi
    info "Creating venv: ${VENV_DIR}"
    mkdir -p "$(dirname "$VENV_DIR")"
    python3 -m venv "$VENV_DIR"
    ok "Venv created"
}

# ── Destroy venv ──────────────────────────────────────────────────────────────
destroy_venv() {
    if [[ -d "$VENV_DIR" ]]; then
        info "Removing existing venv: ${VENV_DIR}"
        rm -rf "$VENV_DIR"
    fi
}

# ── Install into venv ─────────────────────────────────────────────────────────
pip_install() {
    local pip="${VENV_DIR}/bin/pip"

    # Upgrade pip/setuptools inside the venv first.
    info "Upgrading pip + setuptools in venv"
    "$pip" install --quiet --upgrade pip setuptools wheel

    # Prefer editable install: supports live development without reinstalling.
    if [[ -f "${REPO_DIR}/pyproject.toml" || -f "${REPO_DIR}/setup.py" || -f "${REPO_DIR}/setup.cfg" ]]; then
        info "Installing Empusa (editable) from ${REPO_DIR}"
        "$pip" install --quiet --editable "$REPO_DIR"
    elif [[ -f "${REPO_DIR}/requirements.txt" ]]; then
        info "No pyproject.toml/setup.py found — installing requirements.txt"
        "$pip" install --quiet -r "${REPO_DIR}/requirements.txt"
    else
        info "No Python packaging metadata found — venv created but nothing installed"
        info "You can manually install into the venv later"
    fi
}

# ── Print summary ─────────────────────────────────────────────────────────────
print_summary() {
    local empusa_bin="${VENV_DIR}/bin/empusa"

    echo ""
    echo "── Empusa paths ─────────────────────────────────────────"
    echo "  repo : ${REPO_DIR}"
    echo "  venv : ${VENV_DIR}"
    echo ""
    echo "── Activate ────────────────────────────────────────────"
    echo "  source ${VENV_DIR}/bin/activate"
    echo ""

    if [[ -x "$empusa_bin" ]]; then
        echo "── Quick test ──────────────────────────────────────────"
        echo "  ${empusa_bin} --help"
        echo ""

        local version
        version="$("$empusa_bin" --version 2>/dev/null || true)"
        if [[ -n "$version" ]]; then
            echo "  Installed version: ${version}"
        fi
    else
        echo "── Note ────────────────────────────────────────────────"
        echo "  No 'empusa' console script found in the venv."
        echo "  The project may use a different entry point."
        echo "  Check: ls ${VENV_DIR}/bin/"
    fi
}

# ── Commands ───────────────────────────────────────────────────────────────────
cmd_install() {
    check_deps
    ensure_repo
    create_venv
    pip_install
    ok "Empusa installed"
    print_summary
}

cmd_update() {
    check_deps
    pull_repo
    create_venv
    pip_install
    ok "Empusa updated"
    print_summary
}

cmd_reinstall() {
    check_deps
    ensure_repo
    destroy_venv
    create_venv
    pip_install
    ok "Empusa reinstalled"
    print_summary
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
case "${1:-}" in
    install)   cmd_install   ;;
    update)    cmd_update    ;;
    reinstall) cmd_reinstall ;;
    -h|--help) usage         ;;
    "")        die "No command given. Usage: install-empusa.sh {install|update|reinstall}" ;;
    *)         die "Unknown command: $1. Usage: install-empusa.sh {install|update|reinstall}" ;;
esac
