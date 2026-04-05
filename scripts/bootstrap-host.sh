#!/usr/bin/env bash
# scripts/bootstrap-host.sh - One-shot provisioning for Ubuntu 24.04 LTS.
# Run via: sudo labctl bootstrap
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_ROOT="${LAB_ROOT:-/opt/lab}"
REAL_USER="${SUDO_USER:-$USER}"

banner() { echo ""; echo "── $1 ──"; }

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Hecate · Host provisioning · Ubuntu 24.04 LTS            ║"
echo "╚═══════════════════════════════════════════════════════════╝"

# 1. Host packages
banner "1/8  Host apt packages"
apt-get update
grep -Ev '^\s*(#|$)' "$REPO_DIR/manifests/host-packages.txt" | \
    xargs -r apt-get install -y --no-install-recommends

# 2. Docker Engine
banner "2/8  Docker Engine"
if ! command -v docker &>/dev/null; then
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
else
    echo "Already installed - $(docker --version)"
fi

# 3. Docker group
banner "3/8  Docker group"
if ! groups "$REAL_USER" | grep -q '\bdocker\b'; then
    usermod -aG docker "$REAL_USER"
    echo "Added $REAL_USER - re-login or newgrp docker."
else
    echo "$REAL_USER already in docker group."
fi

# 4. NVIDIA Container Toolkit
banner "4/8  NVIDIA Container Toolkit"
if command -v nvidia-smi &>/dev/null; then
    bash "$REPO_DIR/scripts/setup-nvidia.sh"
else
    echo "nvidia-smi not found - skipping GPU setup."
fi

# 5. Persistent lab tree
banner "5/8  $LAB_ROOT directory tree"
mkdir -p "$LAB_ROOT"/{data,tools/{binaries,git,venvs},resources,workspaces,knowledge,templates}
chown -R "$REAL_USER":"$REAL_USER" "$LAB_ROOT"

# 6. Seed .env
banner "6/8  .env"
if [[ ! -f "$REPO_DIR/.env" ]]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    echo "Created - review and edit."
else
    echo "Already exists."
fi

# 7. Empusa
banner "7/8  Empusa"
bash "$REPO_DIR/scripts/install-empusa.sh" install || echo "Empusa install skipped."

# 8. Symlink labctl
banner "8/8  labctl symlink"
chmod +x "$REPO_DIR/labctl"
ln -sf "$REPO_DIR/labctl" /usr/local/bin/labctl
echo "labctl -> /usr/local/bin/labctl"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  Done.  Next steps:                                       ║"
echo "║    1. Re-login (docker group)                             ║"
echo "║    2. vim .env                                            ║"
echo "║    3. labctl sync                                         ║"
echo "║    4. labctl build                                        ║"
echo "║    5. labctl up                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
