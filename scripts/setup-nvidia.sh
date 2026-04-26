#!/usr/bin/env bash
# scripts/setup-nvidia.sh - Install/verify NVIDIA Container Toolkit.
# Called by bootstrap-host.sh when nvidia-smi is present.
set -euo pipefail

if dpkg -l nvidia-container-toolkit &>/dev/null; then
    echo "nvidia-container-toolkit already installed."
    nvidia-ctk --version
    exit 0
fi

echo "Adding NVIDIA Container Toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-container-toolkit

echo "Configuring Docker runtime..."
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "Verifying GPU passthrough..."
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi

echo "[PASS] NVIDIA Container Toolkit ready."
