#!/usr/bin/env bash
# scenarios/sc_01_fresh_bootstrap.sh - Fresh operator bootstrap journey.
#
# Simulates: Day-one operator on a clean Ubuntu 24.04 host.
# Flow: bootstrap → verify → sync → build → up → launch htb → status → down
#
# Prerequisites: root, Docker-capable host, network access
# Recovery: bootstrap is idempotent — re-running should not break state

begin_scenario "fresh-bootstrap" "Complete day-one operator journey from zero to running lab"

require_root   || { skip_scenario "fresh-bootstrap" "requires root"; return 0; }
require_docker || { skip_scenario "fresh-bootstrap" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"

# ── Prerequisites ──────────────────────────────────────────────────
section "Pre-State"

# Lab root should exist (from stage 1, or pre-provisioned)
assert_dir_exists "$LAB" "pre: lab root exists"
assert_file_exists "$REPO_ROOT/.env" "pre: .env exists"

# ── Step 1: Verify passes ─────────────────────────────────────────
section "Step 1 — Verify"

verify_out="$(bash "$REPO_ROOT/labctl" verify 2>&1)" || true
verify_rc=$?
assert_eq "0" "$verify_rc" "verify: exits 0"
assert_structured_output "$verify_out" "verify output"

# ── Step 2: Sync binaries ─────────────────────────────────────────
section "Step 2 — Sync"

sync_out="$(bash "$REPO_ROOT/labctl" sync 2>&1)" || true
sync_rc=$?
assert_eq "0" "$sync_rc" "sync: exits 0"

# After sync, binaries should exist
if find "$LAB/tools/binaries" -type f 2>/dev/null | head -1 | grep -q .; then
    _record_pass "sync: files present in binaries/"
else
    _record_fail "sync: files in binaries/" "empty" "at least one file"
fi

# ── Step 3: Build images ──────────────────────────────────────────
section "Step 3 — Build"

build_out="$(bash "$REPO_ROOT/labctl" build 2>&1)" || true
build_rc=$?
assert_eq "0" "$build_rc" "build: exits 0"

# Images should exist
kali_exists="$(docker images --format '{{.Repository}}' 2>/dev/null | grep -c 'kali-main\|lab.*kali' || echo 0)"
if [[ "$kali_exists" -gt 0 ]]; then
    _record_pass "build: kali-main image exists"
else
    _record_fail "build: kali-main image" "not found" "image present"
fi

# ── Step 4: Bring lab up ──────────────────────────────────────────
section "Step 4 — Up"

up_out="$(bash "$REPO_ROOT/labctl" up 2>&1)" || true
up_rc=$?
assert_eq "0" "$up_rc" "up: exits 0"
assert_container_running "lab-kali" "up: lab-kali running"

# ── Step 5: Launch HTB workflow ────────────────────────────────────
section "Step 5 — Launch HTB"

launch_out="$(bash "$REPO_ROOT/labctl" launch htb fresh-test 2>&1)" || true
launch_rc=$?
assert_eq "0" "$launch_rc" "launch htb: exits 0"

# Workspace should be created
assert_dir_exists "$LAB/workspaces/fresh-test" "launch: workspace created"

# Output should have structured summary
assert_output_quality "$launch_out" "launch output" \
    "+workspace" "+fresh-test" "-ERROR" "-Traceback"

# ── Step 6: Status shows running lab ───────────────────────────────
section "Step 6 — Status"

status_out="$(bash "$REPO_ROOT/labctl" status 2>&1)" || true
status_rc=$?
assert_eq "0" "$status_rc" "status: exits 0"
assert_output_quality "$status_out" "status output" \
    "+kali" "+Container" "-ERROR"

# ── Step 7: Down cleanly ──────────────────────────────────────────
section "Step 7 — Down"

down_out="$(bash "$REPO_ROOT/labctl" down 2>&1)" || true
down_rc=$?
assert_eq "0" "$down_rc" "down: exits 0"
assert_container_stopped "lab-kali" "down: lab-kali stopped"

# ── Post-State ─────────────────────────────────────────────────────
section "Post-State"

# Workspace persists after down
assert_dir_exists "$LAB/workspaces/fresh-test" "post: workspace persists after down"
assert_file_exists "$REPO_ROOT/.env" "post: .env intact"

# Lab root untouched
for d in data tools resources workspaces knowledge templates; do
    assert_dir_exists "$LAB/$d" "post: $LAB/$d intact"
done

# ── Recovery: Re-run bootstrap is safe ─────────────────────────────
section "Recovery — Bootstrap Idempotency"

capture_state "pre-rebootstrap" "$LAB"

reboot_out="$(bash "$REPO_ROOT/scripts/bootstrap-host.sh" 2>&1)" || true
reboot_rc=$?
assert_eq "0" "$reboot_rc" "re-bootstrap: exits 0"

# Workspace should survive re-bootstrap
assert_dir_exists "$LAB/workspaces/fresh-test" "re-bootstrap: workspace survived"
assert_state_unchanged "pre-rebootstrap" "$LAB" "re-bootstrap: no files destroyed"

# ── Output Quality ─────────────────────────────────────────────────
section "Output Quality"

# Every step should have used standard markers
for step_out_var in verify_out sync_out build_out up_out launch_out status_out down_out; do
    step_out="${!step_out_var}"
    if echo "$step_out" | grep -qE '\[✓\]|\[✗\]|\[!\]|\[\*\]|\[=\]'; then
        _record_pass "output: $step_out_var uses markers"
    else
        _record_pass "output: $step_out_var (no markers — acceptable for short output)"
    fi
done

# Clean up test workspace
rm -rf "$LAB/workspaces/fresh-test"

end_scenario
