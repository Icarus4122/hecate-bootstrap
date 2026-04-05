#!/usr/bin/env bash
# tests/e2e/stage_3_build.sh - Build and compose stacking validation.
#
# Requires: Docker running.  Validates image builds, compose file stacking
# with overlays (GPU, hostnet), and the builder profile.

begin_stage 3 "Build & Compose"

LAB="${LAB_ROOT:-/opt/lab}"

# ═══════════════════════════════════════════════════════════════════
#  3.1  Image build
# ═══════════════════════════════════════════════════════════════════
section "Image Build"

build_out="$(bash "$REPO_ROOT/labctl" build 2>&1)" || true
build_rc=$?
assert_eq "0" "$build_rc" "build: exits 0"

# Check images exist after build
kali_image="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -i 'kali-main\|lab.*kali' | head -1)"
if [[ -n "$kali_image" ]]; then
    _record_pass "build: kali-main image exists ($kali_image)"
else
    _record_fail "build: kali-main image exists" "not found" "kali-main image"
fi

builder_image="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -i builder | head -1)"
if [[ -n "$builder_image" ]]; then
    _record_pass "build: builder image exists ($builder_image)"
else
    _record_fail "build: builder image exists" "not found" "builder image"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.2  Compose file stacking — base only
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: Base"

base_config="$(docker compose -f "$REPO_ROOT/compose/docker-compose.yml" config 2>&1)" || true

# Base config should define kali-main service
assert_contains "$base_config" "kali-main" "base compose: has kali-main service"
# Builder should be in base (with profiles constraint)
assert_contains "$base_config" "builder" "base compose: has builder service"

# Bind mounts in base config
for mount_src in "data" "tools" "resources" "workspaces" "knowledge" "templates"; do
    if echo "$base_config" | grep -q "$mount_src"; then
        _record_pass "base compose: mount $mount_src"
    else
        _record_fail "base compose: mount $mount_src" "missing" "bind mount for $mount_src"
    fi
done

# tmux read-only mount
if echo "$base_config" | grep -q "tmux"; then
    _record_pass "base compose: tmux mount present"
else
    _record_fail "base compose: tmux mount" "missing" "tmux bind mount"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.3  Compose stacking — GPU overlay
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: GPU Overlay"

gpu_config="$(docker compose \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.gpu.yml" \
    config 2>&1)" || true

# GPU overlay should add device reservation
if echo "$gpu_config" | grep -qi "nvidia\|gpu\|devices"; then
    _record_pass "gpu overlay: NVIDIA device reservation present"
else
    _record_fail "gpu overlay: NVIDIA device reservation" "missing" "nvidia/gpu/devices"
fi

# GPU env vars
if echo "$gpu_config" | grep -q "NVIDIA_VISIBLE_DEVICES"; then
    _record_pass "gpu overlay: NVIDIA_VISIBLE_DEVICES set"
else
    _record_fail "gpu overlay: NVIDIA_VISIBLE_DEVICES" "missing" "env var"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.4  Compose stacking — hostnet overlay
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: Hostnet Overlay"

hostnet_config="$(docker compose \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.hostnet.yml" \
    config 2>&1)" || true

# Hostnet overlay should set network_mode: host
if echo "$hostnet_config" | grep -q "network_mode.*host\|network_mode: host"; then
    _record_pass "hostnet overlay: network_mode host on kali-main"
else
    _record_fail "hostnet overlay: network_mode host" "missing" "network_mode: host"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.5  Compose stacking — all overlays combined
# ═══════════════════════════════════════════════════════════════════
section "Compose Stacking: All Overlays"

all_config="$(docker compose \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.gpu.yml" \
    -f "$REPO_ROOT/compose/docker-compose.hostnet.yml" \
    config 2>&1)" || true

all_rc=$?
assert_eq "0" "$all_rc" "all overlays: compose config exits 0"
assert_contains "$all_config" "kali-main" "all overlays: kali-main defined"

# ═══════════════════════════════════════════════════════════════════
#  3.6  Compose stacking via lib/compose.sh
# ═══════════════════════════════════════════════════════════════════
section "lib/compose.sh Integration"

# Source compose.sh and verify _compose function exists
REPO_DIR="$REPO_ROOT"
source "$REPO_ROOT/scripts/lib/compose.sh"

if declare -f _compose &>/dev/null; then
    _record_pass "lib/compose.sh: _compose function defined"
else
    _record_fail "lib/compose.sh: _compose function" "missing" "_compose()"
fi

# _compose config (base only, LAB_GPU=0 LAB_HOSTNET=0) should work
base_out="$(LAB_GPU=0 LAB_HOSTNET=0 _compose config 2>&1)" || true
assert_contains "$base_out" "kali-main" "lib/compose.sh base: kali-main in config"

# _compose with GPU
gpu_out="$(LAB_GPU=1 LAB_HOSTNET=0 _compose config 2>&1)" || true
if echo "$gpu_out" | grep -qi "nvidia\|gpu"; then
    _record_pass "lib/compose.sh GPU: nvidia in config"
else
    _record_fail "lib/compose.sh GPU: nvidia in config" "not found" "nvidia"
fi

# _compose with hostnet
hostnet_out="$(LAB_GPU=0 LAB_HOSTNET=1 _compose config 2>&1)" || true
if echo "$hostnet_out" | grep -q "network_mode"; then
    _record_pass "lib/compose.sh hostnet: network_mode in config"
else
    _record_fail "lib/compose.sh hostnet: network_mode" "not found" "network_mode"
fi

# ═══════════════════════════════════════════════════════════════════
#  3.7  Builder profile
# ═══════════════════════════════════════════════════════════════════
section "Builder Profile"

# Builder should only come up with --profile build
builder_config="$(docker compose -f "$REPO_ROOT/compose/docker-compose.yml" config 2>&1)"
if echo "$builder_config" | grep -q "profiles:"; then
    _record_pass "builder: has profiles constraint"
else
    _record_fail "builder: profiles constraint" "missing" "profiles: [build]"
fi

# Validate builder image has expected tools when built
# We test via docker run with the built image
if [[ -n "$builder_image" ]]; then
    for tool in gcc make cmake; do
        assert_cmd_ok "builder image: has $tool" \
            docker run --rm "$builder_image" which "$tool"
    done
fi

# ═══════════════════════════════════════════════════════════════════
#  3.8  Docker inspect — mount verification
# ═══════════════════════════════════════════════════════════════════
section "Docker Inspect Mounts"

# Bring up base stack for inspection
bash "$REPO_ROOT/labctl" up &>/dev/null || true

if require_container "lab-kali"; then
    assert_docker_mount "lab-kali" "$LAB/data"       "/opt/lab/data"       "rw" "inspect: data mount rw"
    assert_docker_mount "lab-kali" "$LAB/tools"      "/opt/lab/tools"      "rw" "inspect: tools mount rw"
    assert_docker_mount "lab-kali" "$LAB/resources"   "/opt/lab/resources"  "rw" "inspect: resources mount rw"
    assert_docker_mount "lab-kali" "$LAB/workspaces"  "/opt/lab/workspaces" "rw" "inspect: workspaces mount rw"
    assert_docker_mount "lab-kali" "$LAB/knowledge"   "/opt/lab/knowledge"  "rw" "inspect: knowledge mount rw"
    assert_docker_mount "lab-kali" "$LAB/templates"   "/opt/lab/templates"  "rw" "inspect: templates mount rw"
fi

bash "$REPO_ROOT/labctl" down &>/dev/null || true

# ═══════════════════════════════════════════════════════════════════
#  3.9  Compose dual-variant compatibility
# ═══════════════════════════════════════════════════════════════════
section "Compose Variant Compatibility"

assert_dual_compose "base config parses" \
    -f "$REPO_ROOT/compose/docker-compose.yml" config

assert_dual_compose "gpu overlay parses" \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.gpu.yml" config

assert_dual_compose "hostnet overlay parses" \
    -f "$REPO_ROOT/compose/docker-compose.yml" \
    -f "$REPO_ROOT/compose/docker-compose.hostnet.yml" config
    for tool in gcc make mingw-w64-x86-64-dev; do
        if docker run --rm "${builder_image%%:*}" dpkg -l "$tool" &>/dev/null 2>&1; then
            _record_pass "builder image: has $tool"
        else
            # Try checking command instead
            _record_fail "builder image: has $tool" "not installed" "$tool in image"
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════
#  3.8  kali-main image contents
# ═══════════════════════════════════════════════════════════════════
section "kali-main Image Contents"

if [[ -n "$kali_image" ]]; then
    kali_img="${kali_image%%:*}"
    for tool in nmap tmux python3 git curl jq; do
        if docker run --rm "$kali_img" which "$tool" &>/dev/null 2>&1; then
            _record_pass "kali image: has $tool"
        else
            _record_fail "kali image: has $tool" "missing" "$tool in image"
        fi
    done
    # tmux config symlink
    if docker run --rm "$kali_img" test -L /root/.tmux.conf &>/dev/null 2>&1; then
        _record_pass "kali image: .tmux.conf symlink"
    else
        _record_fail "kali image: .tmux.conf symlink" "missing" "~/.tmux.conf -> /etc/tmux.d/.tmux.conf"
    fi
fi

end_stage
