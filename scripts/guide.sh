#!/usr/bin/env bash
# scripts/guide.sh — Interactive setup guide for the Hecate lab.
#
# Walks a first-time operator through the full setup process, one step
# at a time.  Each step is explained before anything runs.  Nothing
# happens without explicit confirmation.
#
# Usage:
#   labctl guide              Interactive walkthrough (confirm each step)
#   labctl guide --explain    Read-only reference (no prompts, no execution)
#
# The guide detects what is already done and notes it, so re-running
# after a partial setup picks up where you left off.
set -uo pipefail
# No set -e — this is an interactive orchestrator; we handle errors per step.

# ── Paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
export LAB_ROOT="${LAB_ROOT:-/opt/lab}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-lab}"

# ── Modes ──────────────────────────────────────────────────────────
EXPLAIN_ONLY=false
TOTAL_STEPS=7

# ── Argument parsing ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --explain|--dry-run)
            EXPLAIN_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: labctl guide [--explain]"
            echo ""
            echo "  labctl guide            Interactive setup walkthrough"
            echo "  labctl guide --explain  Read-only reference (prints all steps, runs nothing)"
            exit 0 ;;
        *)
            echo "[FAIL] Unknown flag: $1" >&2
            echo "    Usage: labctl guide [--explain]" >&2
            exit 1 ;;
    esac
done

# ── Output helpers ─────────────────────────────────────────────────
_heading() {
    local step="$1" title="$2"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  Step %d of %d · %s\n" "$step" "$TOTAL_STEPS" "$title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

_body() {
    # Print pre-formatted text as-is.  Called with a heredoc.
    cat
}

_hint_done() {
    echo "  [PASS] Already done: $*"
}

_hint_needed() {
    echo "  [INFO] $*"
}

# Prompt the operator.  Returns 0 = run, 1 = skip.  Exits on quit.
_ask() {
    if $EXPLAIN_ONLY; then return 1; fi
    echo ""
    while true; do
        printf "  ► [y] run    [s] skip    [q] quit\n"
        read -rp "  > " ans
        case "${ans,,}" in
            y|yes)  return 0 ;;
            s|skip) return 1 ;;
            q|quit)
                echo ""
                echo "  Re-run 'labctl guide' any time to resume."
                exit 0 ;;
            "")     return 0 ;;
            *)      echo "  Enter y, s, or q." ;;
        esac
    done
}

# Run a command.  On failure, offer retry / skip / quit.
# Returns 0 on success, 1 if user chose to skip after failure.
_run() {
    while true; do
        echo ""
        echo "  Running: $*"
        echo ""
        local rc=0
        "$@" || rc=$?
        echo ""
        if [[ $rc -eq 0 ]]; then
            echo "  [PASS] Step succeeded."
            return 0
        fi
        echo "  [FAIL] Step failed (exit ${rc})."
        echo ""
        while true; do
            printf "  ► [r] retry    [s] skip    [q] quit\n"
            read -rp "  > " ans
            case "${ans,,}" in
                r|retry) break ;;
                s|skip)  return 1 ;;
                q|quit)
                    echo ""
                    echo "  Re-run 'labctl guide' to continue from this step."
                    exit 0 ;;
                *)  echo "  Enter r, s, or q." ;;
            esac
        done
    done
}

# ═══════════════════════════════════════════════════════════════════
#  Step 1 · Pre-flight verification
# ═══════════════════════════════════════════════════════════════════
step_verify() {
    _heading 1 "Pre-flight verification"
    _body <<'EOF'
  What it does
    Scans the host for missing packages, Docker status, the /opt/lab
    directory tree, repository files, and configuration gaps.

  Why it matters
    Catches problems now, before they show up as confusing Docker or
    compose errors during build or launch.

  Command
    labctl verify

  Safety
    Read-only.  Does not install or change anything on your system.
EOF

    if $EXPLAIN_ONLY; then return 0; fi

    if _ask; then
        _run bash "$REPO_DIR/scripts/verify-host.sh"
    else
        echo "  [INFO] Skipped."
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Step 2 · Host provisioning (bootstrap)
# ═══════════════════════════════════════════════════════════════════
step_bootstrap() {
    _heading 2 "Host provisioning (bootstrap)"
    _body <<'EOF'
  What it does
    One-time setup of the host machine:
      • Installs host packages (git, curl, jq, python3, ...)
      • Installs Docker Engine + Compose plugin
      • Adds your user to the docker group
      • Creates /opt/lab directory tree
      • Seeds .env configuration file
      • Installs Empusa (workspace engine)
      • Symlinks labctl to /usr/local/bin/

  Command
    sudo labctl bootstrap

  Safety
    Installs system packages and creates directories.  Requires root
    access — sudo will prompt for your password.  Safe to re-run;
    it skips steps that are already done.
EOF

    # Detection
    if [[ -d "$LAB_ROOT" ]] && command -v docker &>/dev/null && [[ -f "$REPO_DIR/.env" ]]; then
        echo ""
        _hint_done "Bootstrap appears complete."
        echo "      /opt/lab exists, Docker is installed, .env is present."
        echo "      You can skip or re-run (safe either way)."
    else
        echo ""
        _hint_needed "Bootstrap has not been run yet (or is incomplete)."
    fi

    if $EXPLAIN_ONLY; then return 0; fi

    if _ask; then
        _run sudo bash "$REPO_DIR/scripts/bootstrap-host.sh"
    else
        echo "  [INFO] Skipped."
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Step 3 · Docker group check
# ═══════════════════════════════════════════════════════════════════
step_docker_group() {
    _heading 3 "Docker group membership"
    _body <<'EOF'
  What it does
    Checks that your user account is in the 'docker' group so you
    can run Docker commands without sudo.

  Why it matters
    Without this, every docker and compose command fails with a
    permission error.

  Command
    (no command — this is an automatic check)
EOF

    echo ""
    if id -nG 2>/dev/null | grep -qw docker; then
        _hint_done "You are in the 'docker' group."
        echo ""
        echo "  No action needed.  Continuing."
        return 0
    fi

    echo ""
    echo "  [WARN] You are NOT in the 'docker' group yet."
    echo ""
    echo "  Bootstrap added you to the group, but your current shell"
    echo "  session doesn't know about it.  You need to either:"
    echo ""
    echo "    Option A (recommended)"
    echo "      Log out and log back in, then re-run:"
    echo "        labctl guide"
    echo ""
    echo "    Option B (quick fix for this session)"
    echo "      Run this in your terminal:"
    echo "        newgrp docker"
    echo "        labctl guide"
    echo ""
    echo "  The guide detects completed steps — it will pick up here."

    if ! $EXPLAIN_ONLY; then
        echo ""
        echo "  Pausing.  Fix docker group membership, then re-run."
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Step 4 · Sync external binaries
# ═══════════════════════════════════════════════════════════════════
step_sync() {
    _heading 4 "Sync external binaries"
    _body <<'EOF'
  What it does
    Downloads pinned versions of external tools (e.g. chisel,
    ligolo-ng) from GitHub Releases into /opt/lab/tools/binaries/.
    These are bind-mounted into the container at runtime.

  Why it matters
    Gives your operator container a curated toolbox without baking
    binaries into the Docker image.

  Command
    labctl sync

  Safety
    Downloads files to /opt/lab/tools/binaries/.  Never modifies
    the container images.  Can be re-run — skips files already
    present with matching sizes.

  Note
    Optional.  The lab works without synced binaries, but you will
    not have tools like chisel available inside the container until
    you run this.  Set GITHUB_TOKEN for higher API rate limits.
EOF

    # Detection
    local bin_count=0
    if [[ -d "$LAB_ROOT/tools/binaries" ]]; then
        bin_count="$(find "$LAB_ROOT/tools/binaries" -type f 2>/dev/null | wc -l)"
    fi
    echo ""
    if [[ "$bin_count" -gt 0 ]]; then
        _hint_done "${bin_count} files in ${LAB_ROOT}/tools/binaries/"
        echo "      You can skip or re-run to refresh."
    else
        _hint_needed "No binaries synced yet."
    fi

    if $EXPLAIN_ONLY; then return 0; fi

    if _ask; then
        _run bash "$REPO_DIR/scripts/sync-binaries.sh"
    else
        echo "  [INFO] Skipped."
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Step 5 · Build container images
# ═══════════════════════════════════════════════════════════════════
step_build() {
    _heading 5 "Build container images"
    _body <<'EOF'
  What it does
    Builds the kali-main Docker image (and the optional builder
    sidecar) from the Dockerfiles in docker/.

  Why it matters
    The container is your operator workstation — it has Kali tools,
    tmux, your dotfiles, and everything mounted from /opt/lab.
    You need to build the image before you can start the lab.

  Command
    labctl build

  Safety
    Builds Docker images locally.  Does not push anything.  Does not
    modify /opt/lab.  Takes 5–15 minutes on a first run depending on
    your network speed.
EOF

    # Detection
    local has_image=false
    if docker images --format '{{.Repository}}' 2>/dev/null | grep -q "kali-main"; then
        has_image=true
    fi
    echo ""
    if $has_image; then
        _hint_done "kali-main image exists."
        echo "      Skip if it's up to date, or re-run to rebuild."
    else
        _hint_needed "kali-main image not found — build required."
    fi

    if $EXPLAIN_ONLY; then return 0; fi

    if _ask; then
        source "${REPO_DIR}/scripts/lib/compose.sh"
        _run _compose build
    else
        echo "  [INFO] Skipped."
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Step 6 · Start the lab
# ═══════════════════════════════════════════════════════════════════
step_up() {
    _heading 6 "Start the lab"
    _body <<'EOF'
  What it does
    Starts the kali-main container (and any enabled sidecars) in the
    background using Docker Compose.

  Why it matters
    The container is your working environment.  Once it is up, you
    can open a shell or launch a full tmux session inside it.

  Command
    labctl up

  Safety
    Starts existing images as containers.  Your /opt/lab data is
    bind-mounted in — nothing is copied or deleted.
EOF

    # Detection
    local running=false
    if docker compose ps --status running 2>/dev/null | grep -q "kali-main" ||
       docker-compose ps 2>/dev/null | grep -q "Up"; then
        running=true
    fi
    echo ""
    if $running; then
        _hint_done "kali-main is already running."
        echo "      Skip to proceed, or re-run to restart cleanly."
    else
        _hint_needed "Lab is not running."
    fi

    if $EXPLAIN_ONLY; then return 0; fi

    if _ask; then
        source "${REPO_DIR}/scripts/lib/compose.sh"
        _run _compose up -d
    else
        echo "  [INFO] Skipped."
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Step 7 · Enter the lab & what's next
# ═══════════════════════════════════════════════════════════════════
step_whats_next() {
    _heading 7 "Enter the lab"
    _body <<'EOF'
  Your lab is set up.  Here's how to use it.

  Quick access
    labctl shell                  Open a bash shell in kali-main

  Launch profiles (tmux sessions)
    labctl launch default         General-purpose operator session
    labctl launch htb <target>    HTB engagement (creates a workspace)
    labctl launch build [name]    Compilation session (starts builder sidecar)
    labctl launch research [topic]  Research / study session

  Day-to-day
    labctl status                 Check what's running, VPN, GPU, disk
    labctl down                   Stop the lab when done
    labctl up                     Restart the lab later

  Workspace management
    labctl workspace <name>       Create an engagement workspace
    labctl workspace              List existing workspaces

  Maintenance
    labctl update --pull          Pull repo changes + rebuild images
    labctl sync                   Refresh external binaries
    labctl verify                 Re-run pre-flight checks any time

  Get help
    labctl help                   Full command reference
    labctl help <command>         Detail for a specific command
EOF

    if $EXPLAIN_ONLY; then return 0; fi

    echo ""
    echo "  Ready to try it?  Open a shell now:"
    echo ""
    echo "    labctl shell"
    echo ""
    echo "  Or start a full tmux session:"
    echo ""
    echo "    labctl launch default"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════
main() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  Hecate · Setup Guide                                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    if $EXPLAIN_ONLY; then
        echo "  Mode: explain only (read-only reference — nothing will be executed)"
    else
        echo "  This guide walks through setting up and running the Hecate"
        echo "  offensive-security lab on your machine."
        echo ""
        echo "    • Each step is explained before anything runs."
        echo "    • Nothing happens without your confirmation."
        echo "    • Quit any time with 'q' or Ctrl-C."
        echo "    • Re-run later — the guide detects what's already done."
    fi

    step_verify
    step_bootstrap
    step_docker_group
    step_sync
    step_build
    step_up
    step_whats_next

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if $EXPLAIN_ONLY; then
        echo "  End of guide.  Run 'labctl guide' (without --explain) for"
        echo "  the interactive walkthrough."
    else
        echo "  Guide complete.  You're all set."
        echo ""
        echo "  This guide is always available:"
        echo "    labctl guide              Interactive walkthrough"
        echo "    labctl guide --explain    Read-only reference"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

main
