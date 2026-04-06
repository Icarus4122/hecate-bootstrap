#!/usr/bin/env bash
# tests/e2e/stage_3_build.sh - Build and compose stacking validation.
#
# Requires: Docker running. Validates image builds, compose stacking
# (base + overlays), builder profile, mount wiring, and compose variant
# compatibility (docker compose + docker-compose).

begin_stage 3 "Build & Compose"

LAB="${LAB_ROOT:-/opt/lab}"
BASE_COMPOSE="$REPO_ROOT/compose/docker-compose.yml"
GPU_COMPOSE="$REPO_ROOT/compose/docker-compose.gpu.yml"
HOSTNET_COMPOSE="$REPO_ROOT/compose/docker-compose.hostnet.yml"

# ═══════════════════════════════════════════════════════════════════
#  3.1  Image build
# ═══════════════════════════════════════════════════════════════════
section "Image Build"

set +e
build_out="$(bash "$REPO_ROOT/labctl" build 2>&1)"
build_rc=$?
set -e
assert_eq "0" "$build_rc" "build: exits 0"

kali_image="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -i 'kali-main\|lab.*kali' | head -1)"
if [[ -n "$kali_image" ]]; then
    _record_pass "build: kali-main image exists ($kali_image)"
else
    _record_fail "build: kali-main image exists" "not found" "kali-main image"
fi

builder_image="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -i 'builder' | head -1)"
if [[ -n "$builder_image" ]]; then
    _record_pass "build: builder image exists ($builder_image)"
else
    _record_fail "build: builder image exists" "not found" "builder image"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.2  Compose stacking - base
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: Base"

set +e
base_config="$(run_compose -f "$BASE_COMPOSE" config 2>&1)"
base_rc=$?
set -e
assert_eq "0" "$base_rc" "base compose: config exits 0"
assert_contains "$base_config" "kali-main:" "base compose: has kali-main service"
assert_contains "$base_config" "builder:" "base compose: has builder service"
assert_contains "$base_config" "container_name: lab-kali" "base compose: lab-kali container name"
assert_contains "$base_config" "container_name: lab-builder" "base compose: lab-builder container name"

for mount_src in "/opt/lab/data" "/opt/lab/tools" "/opt/lab/resources" "/opt/lab/workspaces" "/opt/lab/knowledge" "/opt/lab/templates"; do
    if echo "$base_config" | grep -q "$mount_src"; then
        _record_pass "base compose: mount $mount_src"
    else
        _record_fail "base compose: mount $mount_src" "missing" "bind mount present"
    fi
done

if echo "$base_config" | grep -q "/etc/tmux.d"; then
    _record_pass "base compose: tmux mount present"
else
    _record_fail "base compose: tmux mount" "missing" "tmux bind mount"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.3  Compose stacking - GPU overlay
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: GPU Overlay"

set +e
gpu_config="$(run_compose -f "$BASE_COMPOSE" -f "$GPU_COMPOSE" config 2>&1)"
gpu_rc=$?
set -e
assert_eq "0" "$gpu_rc" "gpu overlay: compose config exits 0"

if echo "$gpu_config" | grep -qiE 'nvidia|gpu|device_requests|driver: nvidia'; then
    _record_pass "gpu overlay: NVIDIA device reservation present"
else
    _record_fail "gpu overlay: NVIDIA device reservation" "missing" "nvidia/gpu/device reservation"
fi

if echo "$gpu_config" | grep -q "NVIDIA_VISIBLE_DEVICES"; then
    _record_pass "gpu overlay: NVIDIA_VISIBLE_DEVICES set"
else
    _record_fail "gpu overlay: NVIDIA_VISIBLE_DEVICES" "missing" "env var"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.4  Compose stacking - hostnet overlay
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: Hostnet Overlay"

set +e
hostnet_config="$(run_compose -f "$BASE_COMPOSE" -f "$HOSTNET_COMPOSE" config 2>&1)"
hostnet_rc=$?
set -e
assert_eq "0" "$hostnet_rc" "hostnet overlay: compose config exits 0"
if echo "$hostnet_config" | grep -q "network_mode: host"; then
    _record_pass "hostnet overlay: network_mode host"
else
    _record_fail "hostnet overlay: network_mode host" "missing" "network_mode: host"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.5  Compose stacking - all overlays
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: All Overlays"

set +e
all_config="$(run_compose -f "$BASE_COMPOSE" -f "$GPU_COMPOSE" -f "$HOSTNET_COMPOSE" config 2>&1)"
all_rc=$?
set -e
assert_eq "0" "$all_rc" "all overlays: compose config exits 0"
assert_contains "$all_config" "kali-main:" "all overlays: kali-main defined"
assert_contains "$all_config" "network_mode: host" "all overlays: hostnet retained"

# ═══════════════════════════════════════════════════════════════════
#  3.6  compose.sh helper integration
# ═══════════════════════════════════════════════════════════════════
section "lib/compose.sh Integration"

REPO_DIR="$REPO_ROOT"
source "$REPO_ROOT/scripts/lib/compose.sh"

if declare -f _compose &>/dev/null; then
    _record_pass "lib/compose.sh: _compose function defined"
else
    _record_fail "lib/compose.sh: _compose function" "missing" "_compose()"
fi

set +e
base_out="$(LAB_GPU=0 LAB_HOSTNET=0 _compose config 2>&1)"
base_out_rc=$?
set -e
assert_eq "0" "$base_out_rc" "lib/compose.sh base: config exits 0"
assert_contains "$base_out" "kali-main:" "lib/compose.sh base: kali-main in config"

set +e
gpu_out="$(LAB_GPU=1 LAB_HOSTNET=0 _compose config 2>&1)"
gpu_out_rc=$?
set -e
assert_eq "0" "$gpu_out_rc" "lib/compose.sh gpu: config exits 0"
if echo "$gpu_out" | grep -qiE 'nvidia|gpu'; then
    _record_pass "lib/compose.sh GPU: nvidia in config"
else
    _record_fail "lib/compose.sh GPU: nvidia in config" "not found" "nvidia markers"
fi

set +e
hostnet_out="$(LAB_GPU=0 LAB_HOSTNET=1 _compose config 2>&1)"
hostnet_out_rc=$?
set -e
assert_eq "0" "$hostnet_out_rc" "lib/compose.sh hostnet: config exits 0"
if echo "$hostnet_out" | grep -q "network_mode: host"; then
    _record_pass "lib/compose.sh hostnet: network_mode in config"
else
    _record_fail "lib/compose.sh hostnet: network_mode" "not found" "network_mode: host"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.7  Builder profile and image toolchain
# ═══════════════════════════════════════════════════════════════════
section "Builder Profile"

if echo "$base_config" | grep -q "profiles:" && echo "$base_config" | grep -q -- "- build"; then
    _record_pass "builder: has profiles constraint"
else
    _record_fail "builder: profiles constraint" "missing" "profiles: [build]"
fi

if [[ -n "$builder_image" ]]; then
    for tool in gcc make cmake; do
        assert_cmd_ok "builder image: has $tool" docker run --rm "$builder_image" which "$tool"
    done
fi

# ═══════════════════════════════════════════════════════════════════
#  3.8  Docker inspect assertions (mounts + names + restart)
# ═══════════════════════════════════════════════════════════════════
section "Docker Inspect"

bash "$REPO_ROOT/labctl" up &>/dev/null || true

if require_container "lab-kali"; then
    assert_docker_mount "lab-kali" "$LAB/data" "/opt/lab/data" "rw" "inspect: data mount rw"
    assert_docker_mount "lab-kali" "$LAB/tools" "/opt/lab/tools" "rw" "inspect: tools mount rw"
    assert_docker_mount "lab-kali" "$LAB/resources" "/opt/lab/resources" "rw" "inspect: resources mount rw"
    assert_docker_mount "lab-kali" "$LAB/workspaces" "/opt/lab/workspaces" "rw" "inspect: workspaces mount rw"
    assert_docker_mount "lab-kali" "$LAB/knowledge" "/opt/lab/knowledge" "rw" "inspect: knowledge mount rw"
    assert_docker_mount "lab-kali" "$LAB/templates" "/opt/lab/templates" "rw" "inspect: templates mount rw"
    assert_docker_restart "lab-kali" "unless-stopped" "inspect: restart policy"
fi

bash "$REPO_ROOT/labctl" down &>/dev/null || true

# ═══════════════════════════════════════════════════════════════════
#  3.9  Compose dual-variant compatibility
# ═══════════════════════════════════════════════════════════════════
section "Compose Variant Compatibility"

assert_dual_compose "base config parses" -f "$BASE_COMPOSE" config
assert_dual_compose "gpu overlay parses" -f "$BASE_COMPOSE" -f "$GPU_COMPOSE" config
assert_dual_compose "hostnet overlay parses" -f "$BASE_COMPOSE" -f "$HOSTNET_COMPOSE" config
assert_dual_compose "all overlays parse" -f "$BASE_COMPOSE" -f "$GPU_COMPOSE" -f "$HOSTNET_COMPOSE" config

# ═══════════════════════════════════════════════════════════════════
#  3.10  kali-main image contents
# ═══════════════════════════════════════════════════════════════════
section "kali-main Image Contents"

if [[ -n "$kali_image" ]]; then
    for tool in nmap tmux python3 git curl jq; do
        assert_cmd_ok "kali image: has $tool" docker run --rm "$kali_image" which "$tool"
    done
    if docker run --rm "$kali_image" test -L /root/.tmux.conf &>/dev/null 2>&1; then
        _record_pass "kali image: .tmux.conf symlink"
    else
        _record_fail "kali image: .tmux.conf symlink" "missing" "~/.tmux.conf -> /etc/tmux.d/.tmux.conf"
    fi
fi

end_stage
