#!/usr/bin/env bash
# scripts/create-workspace.sh - Create an engagement workspace directory.
#
# Delegation order:
#   1. Empusa venv at ${LAB_ROOT}/tools/venvs/empusa/bin/empusa
#   2. Empusa on PATH (`empusa`)
#   3. Shell fallback (minimal scaffold - no profile-specific logic)
#
# Called by: labctl workspace <name> [--profile P]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_ROOT="${LAB_ROOT:-/opt/lab}"

source "${SCRIPT_DIR}/lib/ui.sh"

name="${1:-}"
profile="${2:-htb}"

if [[ -z "$name" ]]; then
    echo "Usage: labctl workspace <name> [--profile <profile>]"
    echo ""
    echo "Profiles: htb (default), build, research, internal"
    echo ""
    echo "Existing workspaces:"
    ls -1 "$LAB_ROOT/workspaces/" 2>/dev/null || echo "  (none)"
    exit 0
fi

# ── Parse optional flags after positional name ─────────────────────
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) shift; profile="${1:-htb}"; [[ $# -gt 0 ]] && shift ;;
        *)         ui_fail "Unknown flag: $1"
                   ui_note "Valid flags: --profile <name>" >&2
                   ui_note "Run 'labctl help workspace' for usage." >&2
                   exit 1 ;;
    esac
done

# ── Resolve Empusa binary ─────────────────────────────────────────
EMPUSA_VENV="${LAB_ROOT}/tools/venvs/empusa/bin/empusa"
EMPUSA=""
if [[ -x "$EMPUSA_VENV" ]]; then
    EMPUSA="$EMPUSA_VENV"
elif command -v empusa &>/dev/null; then
    EMPUSA="empusa"
fi

# ── Primary path: delegate to Empusa ──────────────────────────────
if [[ -n "$EMPUSA" ]]; then
    ui_info "Delegating workspace creation to Empusa (${EMPUSA})..."
    exec "$EMPUSA" workspace init \
        --name "$name" \
        --profile "$profile" \
        --root "$LAB_ROOT/workspaces" \
        --templates-dir "$REPO_DIR/templates" \
        --set-active
fi

# ── Fallback: minimal scaffold ────────────────────────────────────
# This path runs only when Empusa is not installed.  It creates a
# bare workspace directory with no profile-specific subdirectories,
# no template seeding, and no event emission.  Install Empusa for
# full workspace support.
ui_warn "Empusa not found — creating minimal workspace."

ws="$LAB_ROOT/workspaces/$name"
if [[ -d "$ws" ]]; then
    ui_info "Already exists: $ws"
    exit 0
fi

mkdir -p "$ws"/{notes,scans,loot,logs}
ui_pass "Created $ws (generic layout — install Empusa for profile '${profile}' support)"
ui_fix "bash scripts/install-empusa.sh install"
