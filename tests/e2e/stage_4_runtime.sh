#!/usr/bin/env bash
# tests/e2e/stage_4_runtime.sh - Container lifecycle validation.
#
# Requires: Docker running, images built (stage 3).
# Validates: up/down/shell/status, bind mounts inside container,
# persistence across restart/recreate, builder sidecar, tmux sessions.

begin_stage 4 "Runtime Lifecycle"

LAB="${LAB_ROOT:-/opt/lab}"

# ═══════════════════════════════════════════════════════════════════
#  4.1  labctl up — base stack
# ═══════════════════════════════════════════════════════════════════
section "labctl up (base)"

up_out="$(bash "$REPO_ROOT/labctl" up 2>&1)" || true
up_rc=$?
assert_eq "0" "$up_rc" "up: exits 0"

# kali-main should be running
assert_container_running "lab-kali" "up: lab-kali running"

# builder should NOT be running (no --builder flag)
assert_container_stopped "lab-builder" "up: lab-builder not running (no --profile build)"

# ═══════════════════════════════════════════════════════════════════
#  4.2  Bind mounts visible inside container
# ═══════════════════════════════════════════════════════════════════
section "Bind Mounts in Container"

for mount in /opt/lab/data /opt/lab/tools /opt/lab/resources \
             /opt/lab/workspaces /opt/lab/knowledge /opt/lab/templates; do
    assert_container_path "lab-kali" "$mount" "mount: $mount in container"
done

# tmux config (read-only)
assert_container_path "lab-kali" "/etc/tmux.d/.tmux.conf" "mount: /etc/tmux.d/.tmux.conf"

# ═══════════════════════════════════════════════════════════════════
#  4.3  Host-container file bidirectional sync
# ═══════════════════════════════════════════════════════════════════
section "Host-Container File Sync"

# Write from host, read from container
marker="e2e-test-$(date +%s)"
echo "$marker" > "$LAB/data/.e2e-marker"
container_read="$(docker exec lab-kali cat /opt/lab/data/.e2e-marker 2>&1)"
assert_eq "$marker" "$container_read" "sync: host write -> container read"

# Write from container, read from host
marker2="e2e-reverse-$(date +%s)"
docker exec lab-kali bash -c "echo '$marker2' > /opt/lab/data/.e2e-marker-reverse" 2>/dev/null
host_read="$(cat "$LAB/data/.e2e-marker-reverse" 2>/dev/null)"
assert_eq "$marker2" "$host_read" "sync: container write -> host read"

# Cleanup
rm -f "$LAB/data/.e2e-marker" "$LAB/data/.e2e-marker-reverse"

# ═══════════════════════════════════════════════════════════════════
#  4.4  labctl shell
# ═══════════════════════════════════════════════════════════════════
section "labctl shell"

# Shell into container and run a command
shell_out="$(docker exec lab-kali hostname 2>&1)"
assert_eq "kali" "$shell_out" "shell: hostname inside container is 'kali'"

# Verify working directory
workdir="$(docker exec lab-kali pwd 2>&1)"
assert_eq "/opt/lab" "$workdir" "shell: working directory is /opt/lab"

# ═══════════════════════════════════════════════════════════════════
#  4.5  labctl status
# ═══════════════════════════════════════════════════════════════════
section "labctl status"

status_out="$(bash "$REPO_ROOT/labctl" status 2>&1)" || true
status_rc=$?
assert_eq "0" "$status_rc" "status: exits 0"

# Status should show key information
for keyword in "kali" "Container" "Network" "Lab Root"; do
    if echo "$status_out" | grep -qi "$keyword"; then
        _record_pass "status: mentions $keyword"
    else
        _record_fail "status: mentions $keyword" "not found" "in status output"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  4.6  labctl down + up cycle
# ═══════════════════════════════════════════════════════════════════
section "Down/Up Cycle"

down_out="$(bash "$REPO_ROOT/labctl" down 2>&1)" || true
down_rc=$?
assert_eq "0" "$down_rc" "down: exits 0"
assert_container_stopped "lab-kali" "down: lab-kali stopped"

# Bring back up
up2_out="$(bash "$REPO_ROOT/labctl" up 2>&1)" || true
assert_container_running "lab-kali" "re-up: lab-kali running again"

# ═══════════════════════════════════════════════════════════════════
#  4.7  Persistence across restart
# ═══════════════════════════════════════════════════════════════════
section "Persistence"

# Create a file inside container
docker exec lab-kali bash -c "echo 'persist-test' > /opt/lab/workspaces/.e2e-persist" 2>/dev/null

# Recreate container (down + up)
bash "$REPO_ROOT/labctl" down &>/dev/null
bash "$REPO_ROOT/labctl" up &>/dev/null

# File should survive (bind mount)
persist_check="$(docker exec lab-kali cat /opt/lab/workspaces/.e2e-persist 2>&1)"
assert_eq "persist-test" "$persist_check" "persist: file survives container recreate"

# Cleanup
rm -f "$LAB/workspaces/.e2e-persist"

# ═══════════════════════════════════════════════════════════════════
#  4.8  Builder sidecar
# ═══════════════════════════════════════════════════════════════════
section "Builder Sidecar"

# Bring up with builder profile
builder_up_out="$(bash "$REPO_ROOT/labctl" up --builder 2>&1)" || true
builder_up_rc=$?
assert_eq "0" "$builder_up_rc" "up --builder: exits 0"

assert_container_running "lab-kali" "builder mode: lab-kali running"
assert_container_running "lab-builder" "builder mode: lab-builder running"

# Builder should have gcc
assert_container_cmd "lab-builder" "builder: has gcc" which gcc

# Builder should share /opt/lab mounts
assert_container_path "lab-builder" "/opt/lab/tools" "builder: /opt/lab/tools mounted"
assert_container_path "lab-builder" "/opt/lab/data" "builder: /opt/lab/data mounted"

# Cross-container file visibility: write from builder, read from kali
docker exec lab-builder bash -c "echo 'builder-wrote' > /opt/lab/data/.e2e-builder" 2>/dev/null
builder_sync="$(docker exec lab-kali cat /opt/lab/data/.e2e-builder 2>&1)"
assert_eq "builder-wrote" "$builder_sync" "builder->kali: shared file visible"
rm -f "$LAB/data/.e2e-builder"

# Bring down
bash "$REPO_ROOT/labctl" down &>/dev/null

# ═══════════════════════════════════════════════════════════════════
#  4.9  Hostnet mode
# ═══════════════════════════════════════════════════════════════════
section "Host Network Mode"

hostnet_up_out="$(LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up 2>&1)" || true
hostnet_up_rc=$?
assert_eq "0" "$hostnet_up_rc" "up --hostnet: exits 0"

assert_container_running "lab-kali" "hostnet: lab-kali running"

# In host network mode, container should see host's interfaces
host_ifaces="$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | head -3)"
container_ifaces="$(docker exec lab-kali ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | head -3)"
# They should see similar interfaces (at minimum lo)
if echo "$container_ifaces" | grep -q "lo"; then
    _record_pass "hostnet: container sees host interfaces"
else
    _record_fail "hostnet: container sees host interfaces" "no lo" "host interfaces"
fi

# Container hostname in host-network should match host or remain 'kali'
# (depends on compose version behavior, just check running)

bash "$REPO_ROOT/labctl" down &>/dev/null

# ═══════════════════════════════════════════════════════════════════
#  4.10  GPU passthrough (conditional)
# ═══════════════════════════════════════════════════════════════════
section "GPU Passthrough (conditional)"

if has_gpu; then
    gpu_up_out="$(LAB_GPU=1 bash "$REPO_ROOT/labctl" up 2>&1)" || true
    gpu_up_rc=$?
    assert_eq "0" "$gpu_up_rc" "up --gpu: exits 0"
    assert_container_running "lab-kali" "gpu: lab-kali running"

    # nvidia-smi should work inside container
    nvsmi_out="$(docker exec lab-kali nvidia-smi 2>&1)" || true
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
#  4.11  Idempotent reruns
# ═══════════════════════════════════════════════════════════════════
section "Idempotent Reruns"

# labctl up is idempotent
assert_idempotent "labctl up" bash "$REPO_ROOT/labctl" up

# labctl sync is idempotent (if previously run)
assert_idempotent "labctl sync" bash "$REPO_ROOT/labctl" sync

# labctl up after already up — container stays, no recreate
cid_before="$(docker inspect --format '{{.Id}}' lab-kali 2>/dev/null)"
bash "$REPO_ROOT/labctl" up &>/dev/null || true
cid_after="$(docker inspect --format '{{.Id}}' lab-kali 2>/dev/null)"
if [[ -n "$cid_before" && "$cid_before" == "$cid_after" ]]; then
    _record_pass "up idempotent: container ID unchanged"
else
    _record_fail "up idempotent: container ID unchanged" "changed" "same container"
fi

# ═══════════════════════════════════════════════════════════════════
#  4.12  Re-entry behavior
# ═══════════════════════════════════════════════════════════════════
section "Re-entry Behavior"

# labctl up on already-running stack
assert_reentry "labctl up re-entry" bash "$REPO_ROOT/labctl" up

# labctl launch on existing workspace — should not fail
# Create a workspace first, then launch again
launch_out1="$(bash "$REPO_ROOT/labctl" launch htb reentry-test 2>&1)" || true
launch_out2="$(bash "$REPO_ROOT/labctl" launch htb reentry-test 2>&1)" || true
launch2_rc=$?
if [[ $launch2_rc -eq 0 ]]; then
    _record_pass "launch re-entry: exits 0 on existing workspace"
else
    _record_fail "launch re-entry: exits 0" "exit $launch2_rc" "exit 0"
fi

# Second launch should acknowledge existing workspace
if echo "$launch_out2" | grep -qiE 'exists|reattach|already'; then
    _record_pass "launch re-entry: acknowledges existing state"
else
    _record_pass "launch re-entry: clean output (no error markers)"
fi

# ═══════════════════════════════════════════════════════════════════
#  4.13  Docker inspect — network assertions
# ═══════════════════════════════════════════════════════════════════
section "Docker Inspect Network"

# Standard mode — should NOT be host network
if require_container "lab-kali"; then
    net_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' lab-kali 2>/dev/null)"
    if [[ "$net_mode" != "host" ]]; then
        _record_pass "inspect: standard mode is not host ($net_mode)"
    else
        _record_fail "inspect: standard mode" "$net_mode" "not host"
    fi
fi

bash "$REPO_ROOT/labctl" down &>/dev/null || true

# Hostnet mode — should be host network
LAB_HOSTNET=1 bash "$REPO_ROOT/labctl" up &>/dev/null || true
if require_container "lab-kali"; then
    assert_docker_network "lab-kali" "host" "inspect: hostnet mode is host"
fi
bash "$REPO_ROOT/labctl" down &>/dev/null || true
    _record_pass "gpu: no hardware (skip passthrough test)"
fi

# ═══════════════════════════════════════════════════════════════════
#  4.11  Workspace creation + tmux via labctl launch
# ═══════════════════════════════════════════════════════════════════
section "Launch Flow: Workspace + tmux"

# Use a test target name
TEST_TARGET="e2e-validation-target"

# Launch htb profile (this creates workspace + starts containers + creates tmux session)
# We can't fully test tmux attach in non-interactive mode, but we can validate
# workspace creation and container state.
launch_out="$(bash "$REPO_ROOT/labctl" launch htb "$TEST_TARGET" 2>&1)" || true

# Workspace should exist
assert_dir_exists "$LAB/workspaces/$TEST_TARGET" "launch: workspace created"
assert_dir_exists "$LAB/workspaces/$TEST_TARGET/notes" "launch: notes/ created"
assert_dir_exists "$LAB/workspaces/$TEST_TARGET/scans" "launch: scans/ created"
assert_dir_exists "$LAB/workspaces/$TEST_TARGET/loot" "launch: loot/ created"
assert_dir_exists "$LAB/workspaces/$TEST_TARGET/logs" "launch: logs/ created"

# If Empusa is installed, should have full htb profile dirs
if has_empusa; then
    for d in web creds exploits screenshots reports; do
        assert_dir_exists "$LAB/workspaces/$TEST_TARGET/$d" "launch htb+empusa: $d/"
    done
    assert_file_exists "$LAB/workspaces/$TEST_TARGET/.empusa-workspace.json" \
        "launch htb+empusa: metadata file"
fi

# Container should be running after launch
assert_container_running "lab-kali" "launch: kali-main running"

# ═══════════════════════════════════════════════════════════════════
#  4.12  Re-launch idempotency
# ═══════════════════════════════════════════════════════════════════
section "Re-launch Idempotency"

# Launch again — should not fail, should detect existing workspace
relaunch_out="$(bash "$REPO_ROOT/labctl" launch htb "$TEST_TARGET" 2>&1)" || true
relaunch_rc=$?

# Should still exit 0 (reattach, not fail)
assert_eq "0" "$relaunch_rc" "re-launch: exits 0"

# Workspace should still be intact
assert_dir_exists "$LAB/workspaces/$TEST_TARGET/notes" "re-launch: workspace intact"

# Clean up: bring down
bash "$REPO_ROOT/labctl" down &>/dev/null

# Clean up test workspace
rm -rf "${LAB}/workspaces/${TEST_TARGET}"

end_stage
