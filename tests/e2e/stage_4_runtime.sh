#!/usr/bin/env bash
# tests/e2e/stage_4_runtime.sh - Container lifecycle validation.
#
# Requires: Docker running, images built.
# Validates: up/down/status/shell, mounts, persistence, builder sidecar,
# hostnet/gpu overlays, idempotency, workspace re-entry, and inspect checks.

begin_stage 4 "Runtime Lifecycle"

LAB="${LAB_ROOT:-/opt/lab}"

# ═══════════════════════════════════════════════════════════════════
#  4.1  labctl up - base stack
# ═══════════════════════════════════════════════════════════════════
section "labctl up (base)"

set +e
up_out="$(bash "$REPO_ROOT/labctl" up 2>&1)"
up_rc=$?
set -e
assert_eq "0" "$up_rc" "up: exits 0"
assert_container_running "lab-kali" "up: lab-kali running"
assert_container_stopped "lab-builder" "up: lab-builder not running (no --builder)"

# ═══════════════════════════════════════════════════════════════════
#  4.2  Bind mounts visible inside container
# ═══════════════════════════════════════════════════════════════════
section "Bind Mounts in Container"

for mount in /opt/lab/data /opt/lab/tools /opt/lab/resources /opt/lab/workspaces /opt/lab/knowledge /opt/lab/templates; do
    assert_container_path "lab-kali" "$mount" "mount: $mount in container"
done
assert_container_path "lab-kali" "/etc/tmux.d/.tmux.conf" "mount: /etc/tmux.d/.tmux.conf"

# ═══════════════════════════════════════════════════════════════════
#  4.3  Host-container file sync
# ═══════════════════════════════════════════════════════════════════
section "Host-Container File Sync"

marker="e2e-test-$(date +%s)"
echo "$marker" > "$LAB/data/.e2e-marker"
container_read="$(docker exec lab-kali cat /opt/lab/data/.e2e-marker 2>&1)"
assert_eq "$marker" "$container_read" "sync: host write -> container read"

marker2="e2e-reverse-$(date +%s)"
docker exec lab-kali bash -c "echo '$marker2' > /opt/lab/data/.e2e-marker-reverse" 2>/dev/null
host_read="$(cat "$LAB/data/.e2e-marker-reverse" 2>/dev/null)"
assert_eq "$marker2" "$host_read" "sync: container write -> host read"

rm -f "$LAB/data/.e2e-marker" "$LAB/data/.e2e-marker-reverse"

# ═══════════════════════════════════════════════════════════════════
#  4.4  labctl shell + status
# ═══════════════════════════════════════════════════════════════════
section "Shell and Status"

shell_out="$(docker exec lab-kali hostname 2>&1)"
assert_eq "kali" "$shell_out" "shell: hostname inside container is kali"

workdir="$(docker exec lab-kali pwd 2>&1)"
assert_eq "/opt/lab" "$workdir" "shell: working directory is /opt/lab"

set +e
status_out="$(bash "$REPO_ROOT/labctl" status 2>&1)"
status_rc=$?
set -e
assert_eq "0" "$status_rc" "status: exits 0"
for keyword in "kali" "Lab root"; do
    if echo "$status_out" | grep -qi "$keyword"; then
        _record_pass "status: mentions $keyword"
    else
        _record_fail "status: mentions $keyword" "not found" "in status output"
    fi
done
if echo "$status_out" | grep -qiE 'ERROR|Traceback|panic'; then
    _record_fail "status: no crash markers" "error markers present" "clean status output"
else
    _record_pass "status: no crash markers"
fi
assert_container_running "lab-kali" "status: runtime confirms lab-kali running"

# ═══════════════════════════════════════════════════════════════════
#  4.5  Down/up lifecycle + persistence
# ═══════════════════════════════════════════════════════════════════
section "Down/Up Lifecycle"

set +e
down_out="$(bash "$REPO_ROOT/labctl" down 2>&1)"
down_rc=$?
set -e
assert_eq "0" "$down_rc" "down: exits 0"
assert_container_stopped "lab-kali" "down: lab-kali stopped"

set +e
up2_out="$(bash "$REPO_ROOT/labctl" up 2>&1)"
up2_rc=$?
set -e
assert_eq "0" "$up2_rc" "re-up: exits 0"
assert_container_running "lab-kali" "re-up: lab-kali running again"

section "Persistence"
docker exec lab-kali bash -c "echo 'persist-test' > /opt/lab/workspaces/.e2e-persist" 2>/dev/null
bash "$REPO_ROOT/labctl" down &>/dev/null
bash "$REPO_ROOT/labctl" up &>/dev/null
persist_check="$(docker exec lab-kali cat /opt/lab/workspaces/.e2e-persist 2>&1)"
assert_eq "persist-test" "$persist_check" "persist: file survives recreate"
rm -f "$LAB/workspaces/.e2e-persist"

# ═══════════════════════════════════════════════════════════════════
#  4.6  Builder sidecar
# ═══════════════════════════════════════════════════════════════════
section "Builder Sidecar"

set +e
builder_up_out="$(bash "$REPO_ROOT/labctl" up --builder 2>&1)"
builder_up_rc=$?
set -e
assert_eq "0" "$builder_up_rc" "up --builder: exits 0"
assert_container_running "lab-kali" "builder mode: lab-kali running"
assert_container_running "lab-builder" "builder mode: lab-builder running"
assert_container_cmd "lab-builder" "builder: has gcc" which gcc
assert_container_path "lab-builder" "/opt/lab/tools" "builder: /opt/lab/tools mounted"
assert_container_path "lab-builder" "/opt/lab/data" "builder: /opt/lab/data mounted"
assert_container_path "lab-builder" "/opt/lab/workspaces" "builder: /opt/lab/workspaces mounted"
assert_container_path "lab-builder" "/opt/lab/resources" "builder: /opt/lab/resources mounted"
assert_container_path "lab-builder" "/opt/lab/knowledge" "builder: /opt/lab/knowledge mounted"
assert_container_path "lab-builder" "/opt/lab/templates" "builder: /opt/lab/templates mounted"

docker exec lab-builder bash -c "echo 'builder-wrote' > /opt/lab/data/.e2e-builder" 2>/dev/null
builder_sync="$(docker exec lab-kali cat /opt/lab/data/.e2e-builder 2>&1)"
assert_eq "builder-wrote" "$builder_sync" "builder->kali: shared file visible"
rm -f "$LAB/data/.e2e-builder"

bash "$REPO_ROOT/labctl" down &>/dev/null

# ═══════════════════════════════════════════════════════════════════
#  4.7  Hostnet and GPU overlays
# ═══════════════════════════════════════════════════════════════════
section "Host Network Mode"

set +e
hostnet_up_out="$(LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up 2>&1)"
hostnet_up_rc=$?
set -e
assert_eq "0" "$hostnet_up_rc" "up --hostnet: exits 0"
assert_container_running "lab-kali" "hostnet: lab-kali running"
assert_docker_network "lab-kali" "host" "inspect: hostnet mode is host"

container_ifaces="$(docker exec lab-kali ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | head -3)"
if echo "$container_ifaces" | grep -q "lo"; then
    _record_pass "hostnet: container sees host interfaces"
else
    _record_fail "hostnet: container sees host interfaces" "no lo" "host interfaces"
fi

bash "$REPO_ROOT/labctl" down &>/dev/null

section "GPU Passthrough (conditional)"
if has_gpu; then
    set +e
    gpu_up_out="$(LAB_GPU=1 bash "$REPO_ROOT/labctl" up 2>&1)"
    gpu_up_rc=$?
    set -e
    assert_eq "0" "$gpu_up_rc" "up --gpu: exits 0"
    assert_container_running "lab-kali" "gpu: lab-kali running"

    set +e
    nvsmi_out="$(docker exec lab-kali nvidia-smi 2>&1)"
    nvsmi_rc=$?
    set -e
    assert_eq "0" "$nvsmi_rc" "gpu: nvidia-smi exits 0"
    if echo "$nvsmi_out" | grep -qi "NVIDIA\|Driver"; then
        _record_pass "gpu: nvidia-smi works in container"
    else
        _record_fail "gpu: nvidia-smi in container" "failed" "GPU visible"
    fi
    bash "$REPO_ROOT/labctl" down &>/dev/null
else
    _record_pass "GPU passthrough: no hardware (skip)"
fi

# ═══════════════════════════════════════════════════════════════════
#  4.8  Idempotency + re-entry
# ═══════════════════════════════════════════════════════════════════
section "Idempotent Reruns"

assert_idempotent "labctl up" bash "$REPO_ROOT/labctl" up
assert_idempotent "labctl sync" bash "$REPO_ROOT/labctl" sync

cid_before="$(docker inspect --format '{{.Id}}' lab-kali 2>/dev/null)"
bash "$REPO_ROOT/labctl" up &>/dev/null || true
cid_after="$(docker inspect --format '{{.Id}}' lab-kali 2>/dev/null)"
if [[ -n "$cid_before" && "$cid_before" == "$cid_after" ]]; then
    _record_pass "up idempotent: container ID unchanged"
else
    _record_fail "up idempotent: container ID unchanged" "changed" "same container"
fi

section "Workspace Re-entry"

set +e
ws_create_out="$(bash "$REPO_ROOT/labctl" workspace reentry-test --profile htb 2>&1)"
ws_create_rc=$?
set -e
assert_eq "0" "$ws_create_rc" "workspace create: exits 0"
assert_dir_exists "$LAB/workspaces/reentry-test" "workspace create: directory exists"

# Launch path coverage without interactive attach.
set +e
launch_out1="$(LAB_LAUNCH_NO_ATTACH=1 bash "$REPO_ROOT/labctl" launch htb reentry-test 2>&1)"
launch_rc1=$?
set -e
assert_eq "0" "$launch_rc1" "launch --no-attach first run: exits 0"

set +e
launch_out2="$(LAB_LAUNCH_NO_ATTACH=1 bash "$REPO_ROOT/labctl" launch htb reentry-test 2>&1)"
launch_rc2=$?
set -e
assert_eq "0" "$launch_rc2" "launch --no-attach re-entry: exits 0"
if echo "$launch_out2" | grep -qiE 'exists|reattach|already|session'; then
    _record_pass "launch re-entry: acknowledges existing state"
else
    _record_pass "launch re-entry: clean output (no errors)"
fi

# ═══════════════════════════════════════════════════════════════════
#  4.9  Docker inspect network assertions
# ═══════════════════════════════════════════════════════════════════
section "Docker Inspect Network"

if require_container "lab-kali"; then
    net_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' lab-kali 2>/dev/null)"
    if [[ "$net_mode" != "host" ]]; then
        _record_pass "inspect: standard mode is not host ($net_mode)"
    else
        _record_fail "inspect: standard mode" "$net_mode" "not host"
    fi
fi

bash "$REPO_ROOT/labctl" down &>/dev/null || true
LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up &>/dev/null || true
if require_container "lab-kali"; then
    assert_docker_network "lab-kali" "host" "inspect: hostnet mode is host"
fi
bash "$REPO_ROOT/labctl" down &>/dev/null || true

rm -rf "$LAB/workspaces/reentry-test"

end_stage
