#!/usr/bin/env bash
# scripts/launch-lab.sh — Launch the lab for a given profile and optional target.
#
# Authoritative implementation of launch behavior.  labctl delegates here.
# Handles: workspace creation, compose bring-up, container entry, tmux profile.
#
# Usage:
#   launch-lab.sh default
#   launch-lab.sh htb <target>
#   launch-lab.sh build [name]
#   launch-lab.sh research [topic]
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
export LAB_ROOT="${LAB_ROOT:-/opt/lab}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-lab}"

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: launch-lab.sh <profile> [target]

Profiles:
  default              General-purpose operator session in kali-main
  htb <target>         HTB engagement — creates workspace, enters kali-main
  build [name]         Build/compile session in kali-main (builder sidecar started)
  research [topic]     Research session in kali-main

All profiles run their tmux layout inside the kali-main container.
The `build` profile additionally starts the builder sidecar service,
which can be reached from kali-main via `docker exec` or the shared
/opt/lab/tools mount.  The builder itself has no tmux or operator
tooling — it is a headless cross-compilation environment.

Environment:
  LAB_ROOT             Persistent data root       (default: /opt/lab)
  LAB_GPU=1            Stack GPU compose overlay
  LAB_HOSTNET=1        Stack host-network compose overlay
EOF
    exit 0
}

# ── Helpers ────────────────────────────────────────────────────────────────────
die()  { echo "[!] $*" >&2; exit 1; }
info() { echo "[*] $*"; }

# ── Empusa detection ───────────────────────────────────────────────────────────
# Resolve empusa binary once; profiles use it for workspace init when available.
EMPUSA_VENV="${LAB_ROOT}/tools/venvs/empusa/bin/empusa"
EMPUSA=""
if [[ -x "$EMPUSA_VENV" ]]; then
    EMPUSA="$EMPUSA_VENV"
elif command -v empusa &>/dev/null; then
    EMPUSA="empusa"
fi

# Log tag so every message clearly shows which mode ran.
if [[ -n "$EMPUSA" ]]; then
    _TAG="empusa"
else
    _TAG="fallback"
fi

# Create a workspace via Empusa (primary) or mkdir fallback.
# Usage: ensure_workspace <profile> <name>
# Sets WORKSPACE_PATH to the resolved directory.
ensure_workspace() {
    local profile="$1" name="$2"
    WORKSPACE_PATH="${LAB_ROOT}/workspaces/${name}"

    if [[ -d "$WORKSPACE_PATH" ]]; then
        info "[${_TAG}] Workspace exists: ${WORKSPACE_PATH}"
        return 0
    fi

    if [[ -n "$EMPUSA" ]]; then
        info "[empusa] Creating workspace (${profile}/${name})..."
        "$EMPUSA" workspace init \
            --name "$name" \
            --profile "$profile" \
            --root "$LAB_ROOT/workspaces" \
            --templates-dir "$REPO_DIR/templates" \
            --set-active
    else
        info "[fallback] Empusa not found — creating generic workspace."
        mkdir -p "$WORKSPACE_PATH"/{notes,scans,loot,logs}
        info "[fallback] Created ${WORKSPACE_PATH} (install Empusa for full '${profile}' support)"
    fi
}

# ── Compose ────────────────────────────────────────────────────────────────────
source "${REPO_DIR}/scripts/lib/compose.sh"

# Bring up the base stack.  Extra args (e.g. --profile build) are prepended.
ensure_up() {
    info "Ensuring compose stack is running"
    _compose "$@" up -d
}

# Exec into kali-main and run a tmux profile.
# All profiles enter kali-main — it has the operator tooling + tmux config.
enter_kali() {
    local profile_script="$1"; shift
    info "Entering kali-main → ${profile_script%.sh}"
    _compose exec kali-main bash "/etc/tmux.d/profiles/${profile_script}" "$@"
}

# ── Profile: default ──────────────────────────────────────────────────────────
launch_default() {
    ensure_up
    enter_kali default.sh
}

# ── Profile: htb ──────────────────────────────────────────────────────────────
launch_htb() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        die "htb profile requires a target name.  Usage: launch-lab.sh htb <target>"
    fi

    ensure_workspace htb "$target"

    ensure_up
    enter_kali htb.sh "/opt/lab/workspaces/${target}"
}

# ── Profile: build ────────────────────────────────────────────────────────────
# The operator works inside kali-main.  The builder sidecar is started alongside
# for cross-compilation tasks — it shares /opt/lab/tools via bind mounts.
# The builder has no tmux, no operator tooling; use `docker exec lab-builder`
# from the host or kali-main if you need a shell in the builder directly.
launch_build() {
    local name="${1:-}"
    local ws_arg=""

    if [[ -n "$name" ]]; then
        ensure_workspace build "$name"
        ws_arg="/opt/lab/workspaces/${name}"
    fi

    # --profile build brings up the builder sidecar alongside kali-main.
    ensure_up --profile build

    if [[ -n "$ws_arg" ]]; then
        enter_kali build.sh "$ws_arg"
    else
        enter_kali build.sh
    fi
}

# ── Profile: research ─────────────────────────────────────────────────────────
launch_research() {
    local topic="${1:-}"
    local ws_arg=""

    if [[ -n "$topic" ]]; then
        ensure_workspace research "$topic"
        ws_arg="/opt/lab/workspaces/${topic}"
    fi

    ensure_up

    if [[ -n "$ws_arg" ]]; then
        enter_kali research.sh "$ws_arg"
    else
        enter_kali research.sh
    fi
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
main() {
    local profile="${1:-}"
    shift || true

    case "$profile" in
        default)          launch_default "$@" ;;
        htb)              launch_htb "$@" ;;
        build)            launch_build "$@" ;;
        research)         launch_research "$@" ;;
        -h|--help|"")     usage ;;
        *)                die "Unknown profile: ${profile}.  Valid: default, htb, build, research" ;;
    esac
}

main "$@"
