#!/usr/bin/env bash
# scripts/bootstrap-host.sh - One-shot provisioning for Ubuntu 24.04 LTS.
# Run via: sudo labctl bootstrap
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_ROOT="${LAB_ROOT:-/opt/lab}"
REAL_USER="${SUDO_USER:-$USER}"

# ── Failure context ────────────────────────────────────────────────
CURRENT_STEP=""
trap '_bootstrap_fail' ERR
_bootstrap_fail() {
    echo "" >&2
    echo "[✗] Bootstrap failed${CURRENT_STEP:+ during: ${CURRENT_STEP}}" >&2
    echo "    Review the error above, fix the issue, and re-run:" >&2
    echo "      sudo labctl bootstrap" >&2
    echo "" >&2
    echo "    Bootstrap is safe to re-run — it skips steps already completed." >&2
    exit 1
}

banner() { CURRENT_STEP="$1"; echo ""; echo "── $1 ──"; }
info() { echo "  [*]  $*"; }
ok()   { echo "  [✓]  $*"; }
skip() { echo "  [=]  $*"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Hecate · Host provisioning · Ubuntu 24.04 LTS              ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# 1. Host packages
banner "1/8  Host apt packages"
apt-get update
grep -Ev '^\s*(#|$)' "$REPO_DIR/manifests/apt-host.txt" | \
    xargs -r apt-get install -y --no-install-recommends

# 2. Docker Engine
banner "2/8  Docker Engine"
if ! command -v docker &>/dev/null; then
    info "Installing Docker Engine + Compose plugin..."
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
    ok "Docker Engine installed"
else
    skip "Already installed — $(docker --version)"
fi

# 3. Docker group
banner "3/8  Docker group"
if ! groups "$REAL_USER" | grep -q '\bdocker\b'; then
    usermod -aG docker "$REAL_USER"
    ok "Added ${REAL_USER} to docker group — re-login required"
else
    skip "${REAL_USER} already in docker group"
fi

# 4. NVIDIA Container Toolkit
banner "4/8  NVIDIA Container Toolkit"
if command -v nvidia-smi &>/dev/null; then
    info "NVIDIA GPU detected — installing container toolkit..."
    bash "$REPO_DIR/scripts/setup-nvidia.sh"
    ok "NVIDIA container toolkit installed"
else
    skip "No NVIDIA GPU detected — skipping"
fi

# 5. Persistent lab tree
banner "5/8  $LAB_ROOT directory tree"
mkdir -p "$LAB_ROOT"/{data,tools/{binaries,git,venvs},resources,workspaces,knowledge,templates}
chown -R "$REAL_USER":"$REAL_USER" "$LAB_ROOT"
ok "${LAB_ROOT} directory tree created (owner: ${REAL_USER})"

# 6. Seed .env
banner "6/8  .env"
if [[ ! -f "$REPO_DIR/.env" ]]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    ok "Created .env from template — review and edit before first launch"
else
    skip ".env already exists"
fi

# 7. Empusa
banner "7/8  Empusa"
if bash "$REPO_DIR/scripts/install-empusa.sh" install; then
    ok "Empusa installed"
else
    skip "Empusa install skipped (non-fatal)"
fi

# 8. Symlink labctl
banner "8/8  labctl symlink"
chmod +x "$REPO_DIR/labctl"
ln -sf "$REPO_DIR/labctl" /usr/local/bin/labctl
ok "labctl symlinked to /usr/local/bin/labctl"

echo ""
echo "── Summary ──────────────────────────────────────────────────"
echo ""
echo "  Result: Bootstrap complete."
echo ""
echo "  Next steps:"
echo "    1. Log out and back in        docker group takes effect"
echo "    2. labctl verify              Confirm the host is ready"
echo "    3. Edit .env                  Review LAB_ROOT, tokens, GPU settings"
echo "    4. labctl build               Build the kali-main container image"
echo "    5. labctl up                  Start the lab"
echo ""
