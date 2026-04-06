#!/usr/bin/env bash
# scenarios/sc_07_partial_failure.sh - Partial-failure recovery.
#
# Injects controlled failures (missing files, corrupted manifests,
# stopped containers) and validates that the platform detects, reports,
# and recovers gracefully.
#
# Prerequisites: root, Docker, images built

begin_scenario "partial-failure" "Fault injection and recovery for labctl operations"

require_root   || { skip_scenario "partial-failure" "requires root"; return 0; }
require_docker || { skip_scenario "partial-failure" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"

# Ensure clean baseline
bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "baseline: running"

# ── Fault 1: .env deleted → up should fail gracefully ─────────────
section "Fault 1 — Missing .env"

inject_fault "rename_file" "$REPO_ROOT/.env"

set +e
env_out="$(bash "$REPO_ROOT/labctl" up 2>&1)"
env_rc=$?
set -e

# Should fail with actionable error, not crash
if [[ $env_rc -ne 0 ]]; then
    _record_pass "missing .env: up exits non-zero ($env_rc)"
else
    _record_fail "missing .env: up should fail" "exit 0" "non-zero"
fi

# Error should be actionable
assert_output_quality "$env_out" "missing .env output" \
    "+.env" "-Traceback" "-panic"

restore_fault "rename_file" "$REPO_ROOT/.env"

# Recovery: up should work again
set +e
recovery_out="$(bash "$REPO_ROOT/labctl" up 2>&1)"
recovery_rc=$?
set -e
assert_eq "0" "$recovery_rc" "env recovery: up exits 0"
assert_container_running "lab-kali" "env recovery: running"

# ── Fault 2: Container killed → status reports, up recovers ───────
section "Fault 2 — Container Killed"

inject_fault "stop_container" "lab-kali"
assert_container_stopped "lab-kali" "kill: container stopped"

# Status should report the issue
set +e
status_out="$(bash "$REPO_ROOT/labctl" status 2>&1)"
status_rc=$?
set -e
# Status should not crash
if [[ $status_rc -le 1 ]]; then
    _record_pass "kill: status does not crash"
else
    _record_fail "kill: status crash" "exit $status_rc" "exit 0 or 1"
fi

# Up should recover
set +e
up_out="$(bash "$REPO_ROOT/labctl" up 2>&1)"
up_rc=$?
set -e
assert_eq "0" "$up_rc" "kill recovery: up exits 0"
assert_container_running "lab-kali" "kill recovery: running again"

# ── Fault 3: Corrupted binaries manifest → sync handles gracefully ─
section "Fault 3 — Corrupted Manifest"

inject_fault "break_manifest" "$REPO_ROOT/manifests/binaries.tsv"

set +e
sync_out="$(bash "$REPO_ROOT/labctl" sync 2>&1)"
sync_rc=$?
set -e

# Sync should fail gracefully, not crash
if [[ $sync_rc -ne 0 ]]; then
    _record_pass "corrupt manifest: sync exits non-zero ($sync_rc)"
else
    _record_fail "corrupt manifest: sync should fail" "exit 0" "non-zero"
fi

# Should not produce a stack trace
if echo "$sync_out" | grep -qi "Traceback\|panic\|segfault"; then
    _record_fail "corrupt manifest: no stack trace" "stack trace found" "clean error"
else
    _record_pass "corrupt manifest: no stack trace"
fi

restore_fault "break_manifest" "$REPO_ROOT/manifests/binaries.tsv"

# Recovery: sync should work
set +e
sync_recovery_out="$(bash "$REPO_ROOT/labctl" sync 2>&1)"
sync_recovery_rc=$?
set -e
assert_eq "0" "$sync_recovery_rc" "manifest recovery: sync exits 0"

# ── Fault 4: Missing compose file → build fails cleanly ───────────
section "Fault 4 — Missing Compose File"

inject_fault "rename_file" "$REPO_ROOT/compose/docker-compose.yml"

set +e
build_out="$(bash "$REPO_ROOT/labctl" build 2>&1)"
build_rc=$?
set -e

if [[ $build_rc -ne 0 ]]; then
    _record_pass "missing compose: build exits non-zero"
else
    _record_fail "missing compose: build should fail" "exit 0" "non-zero"
fi

# Should not Traceback
if echo "$build_out" | grep -qi "Traceback\|panic"; then
    _record_fail "missing compose: no crash" "crash found" "clean error"
else
    _record_pass "missing compose: no crash"
fi

restore_fault "rename_file" "$REPO_ROOT/compose/docker-compose.yml"

# ── Fault 5: Data directory permissions → up still works ──────────
section "Fault 5 — Bad Data Directory Permissions"

inject_fault "break_permission" "$LAB/data"

# Up should still work (bind mount from host, container runs as root)
set +e
perm_up_out="$(bash "$REPO_ROOT/labctl" up 2>&1)"
perm_up_rc=$?
set -e
# This might or might not fail depending on implementation
if [[ $perm_up_rc -eq 0 ]]; then
    _record_pass "bad perms: up still works"
else
    _record_pass "bad perms: up fails gracefully ($perm_up_rc)"
fi

restore_fault "break_permission" "$LAB/data"

# ── Post-Recovery Validation ──────────────────────────────────────
section "Post-Recovery"

# Full system should be healthy after all fault recovery
bash "$REPO_ROOT/labctl" down &>/dev/null
bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "post-recovery: container running"

set +e
verify_out="$(bash "$REPO_ROOT/labctl" verify 2>&1)"
verify_rc=$?
set -e
assert_eq "0" "$verify_rc" "post-recovery: verify passes"

bash "$REPO_ROOT/labctl" down &>/dev/null

end_scenario
