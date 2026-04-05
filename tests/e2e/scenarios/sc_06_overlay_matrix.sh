#!/usr/bin/env bash
# scenarios/sc_06_overlay_matrix.sh - Hostnet and GPU overlay matrix.
#
# Tests every combination of overlay flags and validates the resulting
# container configuration via docker inspect. Verifies that overlays
# compose correctly, don't interfere with each other, and produce the
# expected network and device configuration.
#
# Prerequisites: root, Docker, images built

begin_scenario "overlay-matrix" "Overlay flag combinations and docker inspect validation"

require_root   || { skip_scenario "overlay-matrix" "requires root"; return 0; }
require_docker || { skip_scenario "overlay-matrix" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"

# Ensure clean start
bash "$REPO_ROOT/labctl" down &>/dev/null || true

# ── Combination 1: Base (no overlays) ─────────────────────────────
section "Base — No Overlays"

LAB_GPU=0 LAB_HOSTNET=0 bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "base: running"

# Network: should be bridge/default, not host
net_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' lab-kali 2>/dev/null)"
if [[ "$net_mode" != "host" ]]; then
    _record_pass "base: not host network ($net_mode)"
else
    _record_fail "base: not host network" "$net_mode" "bridge/default"
fi

# No GPU devices
gpu_devs="$(docker inspect --format '{{json .HostConfig.DeviceRequests}}' lab-kali 2>/dev/null)"
if [[ "$gpu_devs" == "null" || "$gpu_devs" == "[]" ]]; then
    _record_pass "base: no GPU device requests"
else
    _record_fail "base: no GPU devices" "$gpu_devs" "null/[]"
fi

bash "$REPO_ROOT/labctl" down &>/dev/null

# ── Combination 2: Hostnet only ───────────────────────────────────
section "Hostnet Only"

LAB_GPU=0 LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "hostnet: running"

assert_docker_network "lab-kali" "host" "hostnet: network is host"

# Container should see host interfaces
iface_count="$(docker exec lab-kali ip -o link show 2>/dev/null | wc -l)"
if [[ "$iface_count" -gt 1 ]]; then
    _record_pass "hostnet: sees multiple interfaces ($iface_count)"
else
    _record_fail "hostnet: sees interfaces" "$iface_count" ">1"
fi

bash "$REPO_ROOT/labctl" down &>/dev/null

# ── Combination 3: GPU only (conditional) ─────────────────────────
section "GPU Only (conditional)"

if has_gpu; then
    LAB_GPU=1 LAB_HOSTNET=0 bash "$REPO_ROOT/labctl" up &>/dev/null
    assert_container_running "lab-kali" "gpu: running"

    # Should have GPU device request
    gpu_devs="$(docker inspect --format '{{json .HostConfig.DeviceRequests}}' lab-kali 2>/dev/null)"
    if echo "$gpu_devs" | grep -qi "nvidia\|gpu"; then
        _record_pass "gpu: device requests present"
    else
        _record_fail "gpu: device requests" "$gpu_devs" "nvidia device"
    fi

    # nvidia-smi should work
    nvsmi_out="$(docker exec lab-kali nvidia-smi 2>&1)" || true
    if echo "$nvsmi_out" | grep -qi "NVIDIA\|Driver"; then
        _record_pass "gpu: nvidia-smi works"
    else
        _record_fail "gpu: nvidia-smi" "failed" "GPU visible"
    fi

    # Network should NOT be host
    net_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' lab-kali 2>/dev/null)"
    if [[ "$net_mode" != "host" ]]; then
        _record_pass "gpu: not host network ($net_mode)"
    else
        _record_fail "gpu: not host network" "$net_mode" "bridge/default"
    fi

    bash "$REPO_ROOT/labctl" down &>/dev/null
else
    _record_pass "gpu only: no hardware (skip)"
fi

# ── Combination 4: GPU + Hostnet (conditional) ────────────────────
section "GPU + Hostnet Combined (conditional)"

if has_gpu; then
    LAB_GPU=1 LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up &>/dev/null
    assert_container_running "lab-kali" "combined: running"

    assert_docker_network "lab-kali" "host" "combined: network is host"

    gpu_devs="$(docker inspect --format '{{json .HostConfig.DeviceRequests}}' lab-kali 2>/dev/null)"
    if echo "$gpu_devs" | grep -qi "nvidia\|gpu"; then
        _record_pass "combined: GPU device requests present"
    else
        _record_fail "combined: GPU devices" "$gpu_devs" "nvidia device"
    fi

    bash "$REPO_ROOT/labctl" down &>/dev/null
else
    _record_pass "gpu+hostnet: no hardware (skip)"
fi

# ── Combination 5: Builder + Hostnet ──────────────────────────────
section "Builder + Hostnet"

LAB_GPU=0 LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up --builder &>/dev/null
assert_container_running "lab-kali" "builder+hostnet: kali running"
assert_container_running "lab-builder" "builder+hostnet: builder running"

assert_docker_network "lab-kali" "host" "builder+hostnet: kali host network"
# Builder should have its own network (NOT host, unless compose says so)

bash "$REPO_ROOT/labctl" down &>/dev/null

# ── Compose variant compatibility for all overlays ─────────────────
section "Overlay Compose Compatibility"

assert_dual_compose "base only" \
    -f "$REPO_ROOT/compose/docker-compose.yml" config

assert_dual_compose "gpu overlay" \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.gpu.yml" config

assert_dual_compose "hostnet overlay" \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.hostnet.yml" config

assert_dual_compose "all overlays" \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.gpu.yml" \
    -f "$REPO_ROOT/compose/docker-compose.hostnet.yml" config

# ── Bind mounts survive all overlay combos ─────────────────────────
section "Bind Mount Stability"

LAB_GPU=0 LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up &>/dev/null
if require_container "lab-kali"; then
    for mount in /opt/lab/data /opt/lab/tools /opt/lab/workspaces; do
        assert_container_path "lab-kali" "$mount" "hostnet mount: $mount"
    done
fi
bash "$REPO_ROOT/labctl" down &>/dev/null

end_scenario
