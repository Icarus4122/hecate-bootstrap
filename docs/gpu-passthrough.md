# GPU Passthrough - NVIDIA RTX 2080

## Prerequisites

- NVIDIA driver on host (`nvidia-smi`)
- nvidia-container-toolkit (installed by `labctl bootstrap`)
- Docker configured with nvidia runtime

## Quick Start

```bash
labctl up --gpu
labctl shell
nvidia-smi
hashcat -I
```

## Hashcat Examples

```bash
# NTLM
hashcat -m 1000 -a 0 -d 1 hashes.txt /usr/share/wordlists/rockyou.txt

# Kerberoast
hashcat -m 13100 -a 0 tgs.txt /usr/share/wordlists/rockyou.txt
```

## Troubleshooting

| Symptom | Fix |
| --------- | ----- |
| "Failed to initialize NVML" | Ensure `--gpu` was passed to `labctl up`. |
| GPU not visible in container | Verify runtime: `docker info \| grep nvidia`. Restart Docker. |
| Slow hashcat performance | Plug in power. `sudo nvidia-smi -pm 1`. |

## Hardware

| Spec | Value |
| ------ | ------- |
| GPU | RTX 2080 Mobile |
| VRAM | 8 GB GDDR6 |
| CUDA Cores | 2944 |
| Compute | 7.5 |
