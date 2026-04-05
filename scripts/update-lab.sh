#!/usr/bin/env bash
# scripts/update-lab.sh - Safely update the lab platform.
#
# Updates the hecate-bootstrap repo, optionally updates Empusa, rebuilds
# container images, and optionally refreshes external binaries.
#
# /opt/lab runtime data is NEVER touched.  On build failure the running
# stack is left intact - the operator can continue using the previous
# images until the issue is resolved.
#
# Usage:
#   bash scripts/update-lab.sh [flags]
#   labctl update [flags]
#
# Flags:
#   --pull        git pull hecate-bootstrap repo before rebuild
#   --empusa      update Empusa via install-empusa.sh update
#   --binaries    refresh external binaries via sync-binaries.sh
#   --no-build    skip image rebuild
#   --no-restart  skip compose restart after successful rebuild
#   --builder     include builder profile in restart
#   --gpu         set LAB_GPU=1 for compose operations
#   --hostnet     set LAB_HOSTNET=1 for compose operations
#   --force       bypass confirmation prompts
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
export LAB_ROOT="${LAB_ROOT:-/opt/lab}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-lab}"

# ── Defaults ───────────────────────────────────────────────────────
OPT_PULL=0
OPT_EMPUSA=0
OPT_BINARIES=0
OPT_BUILD=1
OPT_RESTART=1
OPT_BUILDER=0
OPT_FORCE=0

# ── Helpers ────────────────────────────────────────────────────────
die()  { echo "[!] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok()   { echo "[✓] $*"; }
skip() { echo "[=] $*"; }
banner() { echo ""; echo "── $1 ──"; }

# ── Compose file stacker ──────────────────────────────────────────
source "${REPO_DIR}/scripts/lib/compose.sh"

# ── Confirmation prompt ────────────────────────────────────────────
confirm() {
    if [[ "$OPT_FORCE" == "1" ]]; then
        return 0
    fi
    local msg="${1:-Proceed?}"
    read -rp "  ${msg} [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

usage() {
    cat <<'EOF'
Usage: update-lab.sh [flags]

Flags:
  --pull        git pull hecate-bootstrap repo before rebuild
  --empusa      update Empusa (install-empusa.sh update)
  --binaries    refresh external binaries (sync-binaries.sh)
  --no-build    skip image rebuild
  --no-restart  skip compose restart after successful rebuild
  --builder     include builder profile in restart
  --gpu         set LAB_GPU=1 for compose operations
  --hostnet     set LAB_HOSTNET=1 for compose operations
  --force       bypass confirmation prompts

Examples:
  update-lab.sh --pull --empusa --binaries   Full update
  update-lab.sh --no-build --empusa          Update Empusa only
  update-lab.sh --pull --force               Pull + rebuild, no prompts
EOF
    exit 0
}

# ── Parse flags ────────────────────────────────────────────────────
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pull)       OPT_PULL=1       ;;
            --empusa)     OPT_EMPUSA=1     ;;
            --binaries)   OPT_BINARIES=1   ;;
            --no-build)   OPT_BUILD=0      ;;
            --no-restart) OPT_RESTART=0    ;;
            --builder)    OPT_BUILDER=1    ;;
            --gpu)        export LAB_GPU=1 ;;
            --hostnet)    export LAB_HOSTNET=1 ;;
            --force)      OPT_FORCE=1      ;;
            -h|--help)    usage            ;;
            *)            die "Unknown flag: $1
  Run 'labctl help update' for valid flags." ;;
        esac
        shift
    done
}

# ── Summary tracking ──────────────────────────────────────────────
declare -a SUMMARY=()
_done()    { SUMMARY+=("[✓] $*"); }
_skipped() { SUMMARY+=("[=] $*"); }
_failed()  { SUMMARY+=("[!] $*"); }

# ═══════════════════════════════════════════════════════════════════
#  Steps
# ═══════════════════════════════════════════════════════════════════

step_verify_repo() {
    banner "Verify repo"
    local critical=(
        compose/docker-compose.yml
        docker/kali-main/Dockerfile
        scripts/verify-host.sh
    )
    for f in "${critical[@]}"; do
        [[ -f "${REPO_DIR}/${f}" ]] || die "Missing critical file: ${f} - is this the hecate-bootstrap repo?"
    done
    ok "Repo structure intact"
}

step_pull() {
    banner "Git pull"
    if [[ "$OPT_PULL" == "0" ]]; then
        skip "Skipped (use --pull to enable)"
        _skipped "git pull"
        return
    fi

    if [[ ! -d "${REPO_DIR}/.git" ]]; then
        die "Not a git repo - cannot pull"
    fi

    local branch
    branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    info "Pulling ${branch}..."

    if ! confirm "Pull latest changes from origin/${branch}?"; then
        skip "Pull skipped by operator"
        _skipped "git pull (declined)"
        return
    fi

    if git -C "$REPO_DIR" pull --ff-only; then
        ok "Pulled latest (${branch})"
        _done "git pull (${branch})"
    else
        die "git pull failed - resolve manually before retrying"
    fi
}

step_verify_host() {
    banner "Host verification"
    info "Running verify-host.sh..."
    if bash "$REPO_DIR/scripts/verify-host.sh"; then
        ok "Host verification passed"
    else
        die "Host verification failed - fix reported issues before updating"
    fi
}

step_empusa() {
    banner "Empusa"
    if [[ "$OPT_EMPUSA" == "0" ]]; then
        skip "Skipped (use --empusa to enable)"
        _skipped "Empusa update"
        return
    fi

    local install_script="${REPO_DIR}/scripts/install-empusa.sh"
    if [[ ! -f "$install_script" ]]; then
        die "install-empusa.sh not found"
    fi

    info "Updating Empusa..."
    if bash "$install_script" update; then
        ok "Empusa updated"
        _done "Empusa update"
    else
        echo "[!] Empusa update failed - continuing (non-fatal)" >&2
        _failed "Empusa update"
    fi
}

step_binaries() {
    banner "Binary sync"
    if [[ "$OPT_BINARIES" == "0" ]]; then
        skip "Skipped (use --binaries to enable)"
        _skipped "Binary sync"
        return
    fi

    local sync_script="${REPO_DIR}/scripts/sync-binaries.sh"
    if [[ ! -f "$sync_script" ]]; then
        die "sync-binaries.sh not found"
    fi

    info "Syncing binaries..."
    if bash "$sync_script"; then
        ok "Binaries synced"
        _done "Binary sync"
    else
        echo "[!] Binary sync failed - continuing (non-fatal)" >&2
        _failed "Binary sync"
    fi
}

step_build() {
    banner "Image rebuild"
    if [[ "$OPT_BUILD" == "0" ]]; then
        skip "Skipped (use default or remove --no-build)"
        _skipped "Image rebuild"
        return
    fi

    info "Rebuilding container images..."
    if ! confirm "Rebuild container images?"; then
        skip "Build skipped by operator"
        _skipped "Image rebuild (declined)"
        return
    fi

    if _compose build; then
        ok "Images rebuilt"
        _done "Image rebuild"
    else
        _failed "Image rebuild"
        die "Image rebuild failed - running containers are untouched.
  Diagnose with:  labctl build
  Existing stack remains operational."
    fi
}

step_restart() {
    banner "Compose restart"
    if [[ "$OPT_RESTART" == "0" ]]; then
        skip "Skipped (use default or remove --no-restart)"
        _skipped "Compose restart"
        return
    fi

    # Only restart if we actually rebuilt (or if operator wants it)
    local built=0
    for entry in "${SUMMARY[@]}"; do
        [[ "$entry" == *"Image rebuild" ]] && [[ "$entry" == "[✓]"* ]] && built=1
    done
    if [[ "$built" == "0" && "$OPT_BUILD" == "1" ]]; then
        skip "No successful build - skipping restart"
        _skipped "Compose restart (no build)"
        return
    fi

    local profiles=()
    if [[ "$OPT_BUILDER" == "1" ]]; then
        profiles+=(--profile build)
    fi

    info "Restarting compose stack..."
    if _compose "${profiles[@]}" up -d; then
        ok "Stack restarted"
        _done "Compose restart"
    else
        _failed "Compose restart"
        echo "[!] Compose restart failed - check: docker compose ps" >&2
    fi
}

step_summary() {
    echo ""
    echo "── Summary ──────────────────────────────────────────────────"
    for entry in "${SUMMARY[@]}"; do
        echo "  ${entry}"
    done
    echo ""

    local had_failure=0
    for entry in "${SUMMARY[@]}"; do
        [[ "$entry" == "[!]"* ]] && had_failure=1
    done

    if [[ "$had_failure" == "1" ]]; then
        echo "  Result: Update completed with warnings.  Review items above."
    else
        echo "  Result: Update complete."
    fi
    echo ""
    echo "  ${LAB_ROOT} was not modified by this script."
    echo ""
}

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════
main() {
    parse_flags "$@"

    echo "╔══════════════════════════════════════════════════════════════╗"
    printf "║  Hecate · Update · %-42s║\n" "$(date +%F)"
    echo "╚══════════════════════════════════════════════════════════════╝"

    step_verify_repo

    # Hint when operator runs bare `labctl update` with no flags.
    if [[ "$OPT_PULL" == "0" && "$OPT_EMPUSA" == "0" && "$OPT_BINARIES" == "0" ]]; then
        echo ""
        echo "[*] No update flags specified — only verify + rebuild will run."
        echo "    Common patterns:"
        echo "      labctl update --pull                     Pull repo + rebuild images"
        echo "      labctl update --pull --empusa --binaries Full update"
        echo "      labctl update --help                     See all flags"
        echo ""
    fi

    step_pull
    step_verify_host
    step_empusa
    step_binaries
    step_build
    step_restart
    step_summary
}

main "$@"
