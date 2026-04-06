#!/usr/bin/env bash
# scenarios/sc_02_research_workflow.sh - Research workflow lifecycle.
#
# Simulates: Operator starts a research topic, creates workspace,
# works in container, re-enters, verifies persistence, tears down.
#
# Prerequisites: root, Docker, images built

begin_scenario "research-workflow" "Research topic from workspace creation through teardown"

require_root   || { skip_scenario "research-workflow" "requires root"; return 0; }
require_docker || { skip_scenario "research-workflow" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"
TOPIC="vuln-research-e2e"

# ── Pre-State ──────────────────────────────────────────────────────
section "Pre-State"

# No pre-existing workspace
if [[ -d "$LAB/workspaces/$TOPIC" ]]; then
    rm -rf "$LAB/workspaces/$TOPIC"
fi
assert_eq "1" "$([[ -d "$LAB/workspaces/$TOPIC" ]] && echo 0 || echo 1)" \
    "pre: workspace does not exist"

# ── Step 1: Launch research workflow ───────────────────────────────
section "Step 1 — Launch Research"

set +e
launch_out="$(LAB_LAUNCH_NO_ATTACH=1 bash "$REPO_ROOT/labctl" launch research "$TOPIC" 2>&1)"
launch_rc=$?
set -e
assert_eq "0" "$launch_rc" "launch research: exits 0"

# Workspace created with research profile dirs
assert_dir_exists "$LAB/workspaces/$TOPIC" "launch: workspace created"

EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"
if [[ -x "$EMPUSA_BIN" ]]; then
    for d in notes references poc logs; do
        assert_dir_exists "$LAB/workspaces/$TOPIC/$d" "launch: research dir $d"
    done
    # Research profile should have recon.md
    assert_file_exists "$LAB/workspaces/$TOPIC/recon.md" "launch: recon.md seeded"
    # Should NOT have htb-specific templates
    for tmpl in engagement.md target.md services.md finding.md web.md; do
        if [[ ! -f "$LAB/workspaces/$TOPIC/$tmpl" ]]; then
            _record_pass "launch: $tmpl correctly absent"
        else
            _record_fail "launch: $tmpl should not exist" "present" "absent"
        fi
    done
else
    # Fallback scaffold
    assert_dir_exists "$LAB/workspaces/$TOPIC/notes" "launch: fallback notes dir"
fi

# Container should be running
assert_container_running "lab-kali" "launch: container up"

# ── Step 2: Work in container ──────────────────────────────────────
section "Step 2 — Container Work"

# Write research data from inside container
docker exec lab-kali bash -c \
    "echo 'CVE-2024-XXXX analysis' > /opt/lab/workspaces/$TOPIC/notes/analysis.md" 2>/dev/null

# Verify on host
assert_file_exists "$LAB/workspaces/$TOPIC/notes/analysis.md" "work: file visible on host"
host_content="$(cat "$LAB/workspaces/$TOPIC/notes/analysis.md" 2>/dev/null)"
assert_contains "$host_content" "CVE-2024" "work: content correct"

# ── Step 3: Re-entry ──────────────────────────────────────────────
section "Step 3 — Re-entry"

set +e
reentry_out="$(LAB_LAUNCH_NO_ATTACH=1 bash "$REPO_ROOT/labctl" launch research "$TOPIC" 2>&1)"
reentry_rc=$?
set -e
assert_eq "0" "$reentry_rc" "re-entry: exits 0"

# Data persists
persist_content="$(docker exec lab-kali cat "/opt/lab/workspaces/$TOPIC/notes/analysis.md" 2>&1)"
assert_contains "$persist_content" "CVE-2024" "re-entry: data persists in container"

# Output should acknowledge existing workspace
assert_output_quality "$reentry_out" "re-entry output" \
    "-ERROR" "-FATAL" "-Traceback"

# ── Step 4: Down / Up cycle ───────────────────────────────────────
section "Step 4 — Down/Up Cycle"

bash "$REPO_ROOT/labctl" down &>/dev/null
assert_container_stopped "lab-kali" "cycle: stopped"

bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "cycle: restarted"

# Workspace data survives
survive_content="$(docker exec lab-kali cat "/opt/lab/workspaces/$TOPIC/notes/analysis.md" 2>&1)"
assert_contains "$survive_content" "CVE-2024" "cycle: data survives restart"

# ── Step 5: Teardown ──────────────────────────────────────────────
section "Step 5 — Teardown"

bash "$REPO_ROOT/labctl" down &>/dev/null
assert_container_stopped "lab-kali" "teardown: stopped"

# Workspace persists on host after teardown
assert_dir_exists "$LAB/workspaces/$TOPIC" "teardown: workspace persists"
assert_file_exists "$LAB/workspaces/$TOPIC/notes/analysis.md" "teardown: data persists"

# Clean up
rm -rf "$LAB/workspaces/$TOPIC"

end_scenario
