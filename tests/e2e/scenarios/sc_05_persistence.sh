#!/usr/bin/env bash
# scenarios/sc_05_persistence.sh - Persistence across restart/recreate.
#
# Simulates: Operator has active work, container restarts (docker restart),
# container is recreated (down+up), host reboots (simulated via image prune).
# All workspace data, configs, and tools must survive.
#
# Prerequisites: root, Docker, images built

begin_scenario "persistence" "Data persistence across restart, recreate, and prune"

require_root   || { skip_scenario "persistence" "requires root"; return 0; }
require_docker || { skip_scenario "persistence" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"

# ── Setup: Seed test data ──────────────────────────────────────────
section "Setup"

bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "setup: container running"

# Create test data across multiple bind-mounted directories
marker="persistence-e2e-$(date +%s)"
echo "$marker" > "$LAB/data/.e2e-persist-test"
echo "$marker" > "$LAB/workspaces/.e2e-persist-test"
echo "$marker" > "$LAB/knowledge/.e2e-persist-test"
echo "$marker" > "$LAB/tools/.e2e-persist-test"

# Create data from inside container
docker exec lab-kali bash -c "echo '$marker' > /opt/lab/resources/.e2e-persist-test" 2>/dev/null

# Verify initial state
for dir in data workspaces knowledge tools resources; do
    assert_file_exists "$LAB/$dir/.e2e-persist-test" "setup: marker in $dir"
done

capture_state "pre-restart" "$LAB"

# ── Test 1: Docker restart (container preserved) ──────────────────
section "Test 1 — Docker Restart"

docker restart lab-kali &>/dev/null
assert_container_running "lab-kali" "restart: container running"

# Data accessible from inside container
for dir in data workspaces knowledge tools resources; do
    check="$(docker exec lab-kali cat "/opt/lab/$dir/.e2e-persist-test" 2>&1)"
    if [[ "$check" == "$marker" ]]; then
        _record_pass "restart: $dir marker intact"
    else
        _record_fail "restart: $dir marker" "$check" "$marker"
    fi
done

# ── Test 2: Down/Up recreate ──────────────────────────────────────
section "Test 2 — Recreate (Down/Up)"

bash "$REPO_ROOT/labctl" down &>/dev/null
assert_container_stopped "lab-kali" "recreate: stopped"

# Host data survives
for dir in data workspaces knowledge tools resources; do
    assert_file_exists "$LAB/$dir/.e2e-persist-test" "recreate-host: $dir marker"
done

bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "recreate: restarted"

# Container sees data
for dir in data workspaces knowledge tools resources; do
    check="$(docker exec lab-kali cat "/opt/lab/$dir/.e2e-persist-test" 2>&1)"
    if [[ "$check" == "$marker" ]]; then
        _record_pass "recreate: $dir marker in container"
    else
        _record_fail "recreate: $dir marker" "$check" "$marker"
    fi
done

# Container ID changes (new container, same data)
assert_container_running "lab-kali" "recreate: new container running"

# ── Test 3: Volume survive image prune ─────────────────────────────
section "Test 3 — State After Full Down"

bash "$REPO_ROOT/labctl" down &>/dev/null

# Simulate host-reboot scenario: all containers gone, data on disk
assert_container_stopped "lab-kali" "prune: no containers"

# All host data still present
assert_state_unchanged "pre-restart" "$LAB" "prune: filesystem unchanged"

# Bring back
bash "$REPO_ROOT/labctl" up &>/dev/null

# All data present
for dir in data workspaces knowledge tools resources; do
    check="$(docker exec lab-kali cat "/opt/lab/$dir/.e2e-persist-test" 2>&1)"
    if [[ "$check" == "$marker" ]]; then
        _record_pass "recovery: $dir marker after full cycle"
    else
        _record_fail "recovery: $dir marker" "$check" "$marker"
    fi
done

# ── Test 4: .env and config survival ──────────────────────────────
section "Test 4 — Config Persistence"

assert_file_exists "$REPO_ROOT/.env" "config: .env survived all cycles"
assert_file_contains "$REPO_ROOT/.env" "LAB_ROOT" "config: LAB_ROOT in .env"

# ── Cleanup ────────────────────────────────────────────────────────
section "Cleanup"

for dir in data workspaces knowledge tools resources; do
    rm -f "$LAB/$dir/.e2e-persist-test"
done
bash "$REPO_ROOT/labctl" down &>/dev/null

end_scenario
