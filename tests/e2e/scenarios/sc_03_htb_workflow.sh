#!/usr/bin/env bash
# scenarios/sc_03_htb_workflow.sh - HTB workflow lifecycle.
#
# Simulates: Operator targets an HTB box, creates full workspace,
# writes scan data, adds loot, validates template usage, re-enters
# after restart, runs second target workspace.
#
# Prerequisites: root, Docker, images built

begin_scenario "htb-workflow" "Full HTB engagement from target assignment through teardown"

require_root   || { skip_scenario "htb-workflow" "requires root"; return 0; }
require_docker || { skip_scenario "htb-workflow" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"
TARGET="devvortex"

# ── Pre-State ──────────────────────────────────────────────────────
section "Pre-State"

rm -rf "$LAB/workspaces/$TARGET" 2>/dev/null
assert_eq "1" "$([[ -d "$LAB/workspaces/$TARGET" ]] && echo 0 || echo 1)" \
    "pre: workspace clean"

# ── Step 1: Launch HTB target ──────────────────────────────────────
section "Step 1 — Launch HTB"

launch_out="$(bash "$REPO_ROOT/labctl" launch htb "$TARGET" 2>&1)" || true
launch_rc=$?
assert_eq "0" "$launch_rc" "launch htb: exits 0"

assert_dir_exists "$LAB/workspaces/$TARGET" "launch: workspace created"
assert_container_running "lab-kali" "launch: container running"

# Full HTB directory scaffold
EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"
if [[ -x "$EMPUSA_BIN" ]]; then
    for d in notes scans web creds loot exploits screenshots reports logs; do
        assert_dir_exists "$LAB/workspaces/$TARGET/$d" "launch: htb dir $d"
    done

    # HTB templates seeded
    for tmpl in engagement.md target.md recon.md services.md finding.md privesc.md web.md; do
        assert_file_exists "$LAB/workspaces/$TARGET/$tmpl" "launch: template $tmpl"
        assert_file_not_empty "$LAB/workspaces/$TARGET/$tmpl" "launch: template $tmpl non-empty"
    done

    # Templates should have workspace name substituted
    if grep -q "$TARGET" "$LAB/workspaces/$TARGET/engagement.md" 2>/dev/null || \
       ! grep -q '{{NAME}}' "$LAB/workspaces/$TARGET/engagement.md" 2>/dev/null; then
        _record_pass "launch: engagement.md has name substituted"
    else
        _record_fail "launch: engagement.md substitution" "{{NAME}} still present" "substituted"
    fi

    # Metadata
    assert_file_exists "$LAB/workspaces/$TARGET/.empusa-workspace.json" "launch: metadata exists"
    assert_file_contains "$LAB/workspaces/$TARGET/.empusa-workspace.json" "htb" "launch: metadata profile=htb"
fi

# Output quality
assert_output_quality "$launch_out" "launch output" \
    "+$TARGET" "-ERROR" "-Traceback"

# ── Step 2: Simulate operator work ────────────────────────────────
section "Step 2 — Operator Work"

WS="/opt/lab/workspaces/$TARGET"

# Write scan data
docker exec lab-kali bash -c "echo 'PORT   STATE SERVICE' > $WS/scans/nmap-initial.txt" 2>/dev/null
docker exec lab-kali bash -c "echo '22/tcp open  ssh' >> $WS/scans/nmap-initial.txt" 2>/dev/null
docker exec lab-kali bash -c "echo '80/tcp open  http' >> $WS/scans/nmap-initial.txt" 2>/dev/null

# Write creds
docker exec lab-kali bash -c "echo 'admin:SuperSecretPass123!' > $WS/creds/found.txt" 2>/dev/null

# Write notes
docker exec lab-kali bash -c "echo '## Initial Recon\nTarget appears to be running Joomla' > $WS/notes/recon.md" 2>/dev/null

# Verify on host
assert_file_exists "$LAB/workspaces/$TARGET/scans/nmap-initial.txt" "work: scan file on host"
assert_file_exists "$LAB/workspaces/$TARGET/creds/found.txt" "work: creds file on host"

# ── Step 3: Restart and re-enter ───────────────────────────────────
section "Step 3 — Restart Re-entry"

bash "$REPO_ROOT/labctl" down &>/dev/null
bash "$REPO_ROOT/labctl" up &>/dev/null

# All data survives
assert_file_exists "$LAB/workspaces/$TARGET/scans/nmap-initial.txt" "restart: scan data persists"
assert_file_exists "$LAB/workspaces/$TARGET/creds/found.txt" "restart: creds persist"

# Re-launch — should detect existing workspace
relaunch_out="$(bash "$REPO_ROOT/labctl" launch htb "$TARGET" 2>&1)" || true
relaunch_rc=$?
assert_eq "0" "$relaunch_rc" "re-launch: exits 0"

# Container should have data
scan_check="$(docker exec lab-kali cat "$WS/scans/nmap-initial.txt" 2>&1)"
assert_contains "$scan_check" "22/tcp" "re-launch: scan data in container"

# ── Step 4: Second target workspace ───────────────────────────────
section "Step 4 — Second Target"

TARGET2="sandworm"
rm -rf "$LAB/workspaces/$TARGET2" 2>/dev/null

launch2_out="$(bash "$REPO_ROOT/labctl" launch htb "$TARGET2" 2>&1)" || true
launch2_rc=$?
assert_eq "0" "$launch2_rc" "second target: exits 0"

assert_dir_exists "$LAB/workspaces/$TARGET2" "second: workspace created"
# First workspace should still be intact
assert_dir_exists "$LAB/workspaces/$TARGET" "second: first workspace intact"
assert_file_exists "$LAB/workspaces/$TARGET/scans/nmap-initial.txt" "second: first data intact"

# ── Teardown ───────────────────────────────────────────────────────
section "Teardown"

bash "$REPO_ROOT/labctl" down &>/dev/null
rm -rf "$LAB/workspaces/$TARGET" "$LAB/workspaces/$TARGET2"

end_scenario
