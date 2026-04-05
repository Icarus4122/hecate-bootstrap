#!/usr/bin/env bash
# scripts/launch-lab.sh - Launch the lab for a given profile and optional target.
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

# ── State ──────────────────────────────────────────────────────────────────────
WORKSPACE_PATH=""
WS_STATUS="none"  # none | created | exists

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: labctl launch <profile> [target]

Profiles:
  default              General-purpose operator session
  htb <target>         Offensive engagement — creates a workspace for <target>
  build [name]         Compilation / tooling — starts builder sidecar alongside
  research [topic]     Research / study session

Each profile opens a tmux session inside the kali-main container with a
window layout tuned to the task.  Workspaces are directories under
/opt/lab/workspaces/ that hold notes, scans, loot, and logs for an
engagement or project.

Run 'labctl help launch' for full detail and examples.
EOF
    exit "${1:-0}"
}

# ── Helpers ────────────────────────────────────────────────────────────────────
die()  { echo "[✗] $*" >&2; exit 1; }
info() { echo "[*] $*"; }

# ── Session naming ─────────────────────────────────────────────────────────────
# Produces a deterministic, collision-free tmux session name.
# Sanitises to [a-zA-Z0-9_-] — tmux forbids ':' and '.' in session names.
_sanitize() { printf '%s' "$1" | tr -c 'a-zA-Z0-9_-' '-' | sed 's/--*/-/g; s/-$//'; }

_session_name() {
    local profile="$1" name="${2:-}"
    case "$profile" in
        default)  echo "lab" ;;
        htb)      echo "htb-$(_sanitize "$name")" ;;
        build)    [[ -n "$name" ]] && echo "build-$(_sanitize "$name")" || echo "build" ;;
        research) [[ -n "$name" ]] && echo "research-$(_sanitize "$name")" || echo "research" ;;
    esac
}

# ── Empusa detection ───────────────────────────────────────────────────────────
EMPUSA_VENV="${LAB_ROOT}/tools/venvs/empusa/bin/empusa"
EMPUSA=""
if [[ -x "$EMPUSA_VENV" ]]; then
    EMPUSA="$EMPUSA_VENV"
elif command -v empusa &>/dev/null; then
    EMPUSA="empusa"
fi

# ── Workspace ──────────────────────────────────────────────────────────────────
# Creates (or detects) a workspace directory.
# Sets: WORKSPACE_PATH, WS_STATUS
ensure_workspace() {
    local profile="$1" name="$2"
    WORKSPACE_PATH="${LAB_ROOT}/workspaces/${name}"

    if [[ -d "$WORKSPACE_PATH" ]]; then
        WS_STATUS="exists"
        return 0
    fi

    WS_STATUS="created"
    if [[ -n "$EMPUSA" ]]; then
        if ! "$EMPUSA" workspace init \
            --name "$name" \
            --profile "$profile" \
            --root "$LAB_ROOT/workspaces" \
            --templates-dir "$REPO_DIR/templates" \
            --set-active 2>/dev/null; then
            echo "[!] Empusa workspace creation failed — falling back to scaffold." >&2
            mkdir -p "$WORKSPACE_PATH"/{notes,scans,loot,logs}
        fi
    else
        echo "[!] Empusa not found — creating minimal workspace." >&2
        mkdir -p "$WORKSPACE_PATH"/{notes,scans,loot,logs}
    fi
}

# ── Compose ────────────────────────────────────────────────────────────────────
source "${REPO_DIR}/scripts/lib/compose.sh"

ensure_up() {
    if ! _compose "$@" up -d; then
        echo "" >&2
        echo "[✗] Compose failed to bring up the stack." >&2
        echo "    Is Docker running?   systemctl status docker" >&2
        echo "    Pre-flight check:    labctl verify" >&2
        exit 1
    fi
}

# Exec into kali-main and run a tmux profile.
# Args: <profile-script> <session-name> [workspace-path]
enter_kali() {
    local profile_script="$1" session="$2"; shift 2
    if ! _compose exec kali-main bash "/etc/tmux.d/profiles/${profile_script}" "$session" "$@"; then
        echo "" >&2
        echo "[✗] Failed to enter kali-main." >&2
        echo "    Is the container healthy?   labctl status" >&2
        echo "    Check container logs:        labctl logs kali-main" >&2
        exit 1
    fi
}

# ── Summary ────────────────────────────────────────────────────────────────────
# Check if a tmux session already exists inside the running container.
_has_tmux_session() {
    _compose exec -T kali-main tmux has-session -t "$1" 2>/dev/null
}

# List top-level subdirectories of a workspace, space-separated.
_workspace_dirs() {
    local ws="$1"
    local dirs=()
    for d in "$ws"/*/; do
        [[ -d "$d" ]] && dirs+=("$(basename "$d")/")
    done
    [[ ${#dirs[@]} -gt 0 ]] && echo "${dirs[*]}"
}

# Print a structured summary before entering the container.
_print_summary() {
    local profile="$1" name="${2:-}" session="$3" reattach="${4:-false}"

    # Per-profile metadata.
    local desc windows extra=""
    case "$profile" in
        default)
            desc="General-purpose operator session"
            windows="main, ops" ;;
        htb)
            desc="Offensive engagement (HTB / CTF)"
            windows="main, ops" ;;
        build)
            desc="Compilation / tooling session"
            windows="build, tools"
            extra="  Builder      lab-builder sidecar running alongside (headless Ubuntu)" ;;
        research)
            desc="Research / study session"
            windows="research, notes" ;;
    esac

    echo ""
    echo "── launch: ${profile}${name:+ / ${name}} ─────────────────────────────────────"
    echo ""
    printf "  %-12s %s — %s\n" "Profile" "$profile" "$desc"

    # Workspace line.
    if [[ "$WS_STATUS" == "created" ]]; then
        printf "  %-12s %s  [+created]\n" "Workspace" "$WORKSPACE_PATH"
        local dirs
        dirs="$(_workspace_dirs "$WORKSPACE_PATH")"
        [[ -n "$dirs" ]] && printf "  %-12s dirs: %s\n" "" "$dirs"
    elif [[ "$WS_STATUS" == "exists" ]]; then
        printf "  %-12s %s  [=exists]\n" "Workspace" "$WORKSPACE_PATH"
    fi

    # Container and optional sidecar.
    printf "  %-12s %s\n" "Container" "kali-main (Kali Rolling)"
    [[ -n "$extra" ]] && echo "$extra"

    # tmux.
    if $reattach; then
        printf "  %-12s %s  (reattaching — session already exists)\n" "tmux" "$session"
    else
        printf "  %-12s %s  (windows: %s)\n" "tmux" "$session" "$windows"
    fi

    echo ""
    printf "  Detach: Ctrl-b d     Reattach: labctl launch %s%s\n" "$profile" "${name:+ ${name}}"
    echo ""
}

# ── Profile: default ──────────────────────────────────────────────────────────
launch_default() {
    local session
    session="$(_session_name default)"

    ensure_up

    local reattach=false
    _has_tmux_session "$session" && reattach=true

    _print_summary default "" "$session" "$reattach"
    info "Entering kali-main..."
    enter_kali default.sh "$session"
}

# ── Profile: htb ──────────────────────────────────────────────────────────────
launch_htb() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        die "htb profile requires a target name.
  Usage:  labctl launch htb <target>
  List workspaces:  labctl workspace"
    fi

    local session
    session="$(_session_name htb "$target")"

    ensure_workspace htb "$target"
    ensure_up

    local reattach=false
    _has_tmux_session "$session" && reattach=true

    _print_summary htb "$target" "$session" "$reattach"
    info "Entering kali-main..."
    enter_kali htb.sh "$session" "/opt/lab/workspaces/${target}"
}

# ── Profile: build ────────────────────────────────────────────────────────────
# The operator works inside kali-main.  The builder sidecar is started alongside
# for cross-compilation tasks — it shares /opt/lab/tools via bind mounts.
launch_build() {
    local name="${1:-}"
    local session ws_arg=""
    session="$(_session_name build "$name")"

    if [[ -n "$name" ]]; then
        ensure_workspace build "$name"
        ws_arg="/opt/lab/workspaces/${name}"
    fi

    # --profile build brings up the builder sidecar alongside kali-main.
    ensure_up --profile build

    local reattach=false
    _has_tmux_session "$session" && reattach=true

    _print_summary build "$name" "$session" "$reattach"
    info "Entering kali-main..."

    if [[ -n "$ws_arg" ]]; then
        enter_kali build.sh "$session" "$ws_arg"
    else
        enter_kali build.sh "$session"
    fi
}

# ── Profile: research ─────────────────────────────────────────────────────────
launch_research() {
    local topic="${1:-}"
    local session ws_arg=""
    session="$(_session_name research "$topic")"

    if [[ -n "$topic" ]]; then
        ensure_workspace research "$topic"
        ws_arg="/opt/lab/workspaces/${topic}"
    fi

    ensure_up

    local reattach=false
    _has_tmux_session "$session" && reattach=true

    _print_summary research "$topic" "$session" "$reattach"
    info "Entering kali-main..."

    if [[ -n "$ws_arg" ]]; then
        enter_kali research.sh "$session" "$ws_arg"
    else
        enter_kali research.sh "$session"
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
        -h|--help)        usage 0 ;;
        "")               usage 1 ;;
        *)                die "Unknown profile: ${profile}.  Valid: default, htb, build, research
  Usage:  labctl launch <profile> [target]
  Help:   labctl help launch" ;;
    esac
}

main "$@"
