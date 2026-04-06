#!/usr/bin/env bash
# scripts/bootstrap-host.sh - One-shot provisioning for Ubuntu 24.04 LTS.
# Run via: sudo labctl bootstrap
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_ROOT="${LAB_ROOT:-/opt/lab}"
REAL_USER="${SUDO_USER:-$USER}"

source "${SCRIPT_DIR}/lib/ui.sh"

# ── Failure context ────────────────────────────────────────────────
CURRENT_STEP=""
trap '_bootstrap_fail' ERR
_bootstrap_fail() {
    ui_error_block \
        "Bootstrap failed${CURRENT_STEP:+ during: ${CURRENT_STEP}}" \
        "Host provisioning is incomplete" \
        "Review the error above" \
        "sudo labctl bootstrap"
    ui_note "Bootstrap is safe to re-run — it skips steps already completed." >&2
    exit 1
}

_step() { CURRENT_STEP="$1"; ui_section "$1"; }

ui_banner "Hecate" "Host provisioning" "Ubuntu 24.04 LTS"

# 1. Host packages
_step "1/8  Host apt packages"
apt-get update
grep -Ev '^\s*(#|$)' "$REPO_DIR/manifests/apt-host.txt" | \
    xargs -r apt-get install -y --no-install-recommends

# 2. Docker Engine
_step "2/8  Docker Engine"
if ! command -v docker &>/dev/null; then
    ui_info "Installing Docker Engine + Compose plugin..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/ubuntu \
       $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ui_pass "Docker Engine installed"
else
    ui_pass "Already installed — $(docker --version)"
fi

# 3. Docker group
_step "3/8  Docker group"
if ! groups "$REAL_USER" | grep -q '\bdocker\b'; then
    usermod -aG docker "$REAL_USER"
    ui_pass "Added ${REAL_USER} to docker group — re-login required"
else
    ui_pass "${REAL_USER} already in docker group"
fi

# 4. NVIDIA Container Toolkit
_step "4/8  NVIDIA Container Toolkit"
if command -v nvidia-smi &>/dev/null; then
    ui_info "NVIDIA GPU detected — installing container toolkit..."
    bash "$REPO_DIR/scripts/setup-nvidia.sh"
    ui_pass "NVIDIA container toolkit installed"
else
    ui_info "No NVIDIA GPU detected — skipping"
fi

# 5. Persistent lab tree
_step "5/8  $LAB_ROOT directory tree"
mkdir -p "$LAB_ROOT"/{data,tools/{binaries,git,venvs},resources,workspaces,knowledge,templates}
chown -R "$REAL_USER":"$REAL_USER" "$LAB_ROOT"
ui_pass "${LAB_ROOT} directory tree created (owner: ${REAL_USER})"

# 6. Seed .env
_step "6/8  .env"
if [[ ! -f "$REPO_DIR/.env" ]]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    ui_pass "Created .env from template — review and edit before first launch"
else
    ui_pass ".env already exists"
fi

# 7. Empusa
_step "7/8  Empusa"
if bash "$REPO_DIR/scripts/install-empusa.sh" install; then
    ui_pass "Empusa installed"
else
    ui_warn "Empusa install skipped (non-fatal)"
fi

# 8. Symlink labctl
_step "8/8  labctl symlink"
chmod +x "$REPO_DIR/labctl"
ln -sf "$REPO_DIR/labctl" /usr/local/bin/labctl
ui_pass "labctl symlinked to /usr/local/bin/labctl"

ui_summary_line

echo "  Result: Bootstrap complete."

ui_next_block \
    "1. Log out and back in        docker group takes effect" \
    "2. labctl verify              Confirm the host is ready" \
    "3. Edit .env                  Review LAB_ROOT, tokens, GPU settings" \
    "4. labctl build               Build the kali-main container image" \
    "5. labctl up                  Start the lab"
