#!/usr/bin/env bash
# scenarios/sc_04_builder_workflow.sh - Builder workflow lifecycle.
#
# Simulates: Operator needs to compile tools, starts builder sidecar,
# compiles in builder, accesses artifacts from kali, tears down.
#
# Prerequisites: root, Docker, images built (including builder)

begin_scenario "builder-workflow" "Builder sidecar from compile to cross-container artifact access"

require_root   || { skip_scenario "builder-workflow" "requires root"; return 0; }
require_docker || { skip_scenario "builder-workflow" "requires Docker"; return 0; }

LAB="${LAB_ROOT:-/opt/lab}"
WS_NAME="build-e2e"

# ── Pre-State ──────────────────────────────────────────────────────
section "Pre-State"

rm -rf "$LAB/workspaces/$WS_NAME" 2>/dev/null
bash "$REPO_ROOT/labctl" down &>/dev/null || true

# ── Step 1: Launch builder workflow ────────────────────────────────
section "Step 1 — Launch Builder"

set +e
launch_out="$(LAB_LAUNCH_NO_ATTACH=1 bash "$REPO_ROOT/labctl" launch build "$WS_NAME" 2>&1)"
launch_rc=$?
set -e
assert_eq "0" "$launch_rc" "launch build: exits 0"

# Both containers should be running
assert_container_running "lab-kali" "launch: lab-kali running"
assert_container_running "lab-builder" "launch: lab-builder running"

# Builder workspace directories
EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"
if [[ -x "$EMPUSA_BIN" ]]; then
    for d in src out notes logs; do
        assert_dir_exists "$LAB/workspaces/$WS_NAME/$d" "launch: build dir $d"
    done
    # Build profile should NOT have any templates
    tmpl_count="$(find "$LAB/workspaces/$WS_NAME" -maxdepth 1 -name '*.md' ! -name '.*.md' -type f 2>/dev/null | wc -l)"
    assert_eq "0" "$tmpl_count" "launch: no templates seeded (build profile)"
fi

# ── Step 2: Compile in builder ─────────────────────────────────────
section "Step 2 — Compile in Builder"

WS="/opt/lab/workspaces/$WS_NAME"

# Create a simple C program in builder
docker exec lab-builder bash -c "cat > $WS/src/hello.c << 'EOF'
#include <stdio.h>
int main() { printf(\"hello from builder\\n\"); return 0; }
EOF" 2>/dev/null

# Compile
set +e
compile_out="$(docker exec lab-builder bash -c "gcc -o $WS/out/hello $WS/src/hello.c" 2>&1)"
compile_rc=$?
set -e
assert_eq "0" "$compile_rc" "compile: gcc exits 0"
assert_container_path "lab-builder" "$WS/out/hello" "compile: binary exists in builder"

# ── Step 3: Cross-container artifact access ────────────────────────
section "Step 3 — Cross-Container Access"

# Binary should be visible from kali (shared bind mount)
assert_container_path "lab-kali" "$WS/out/hello" "cross: binary visible in kali"

# Execute from kali
set +e
run_out="$(docker exec lab-kali "$WS/out/hello" 2>&1)"
run_rc=$?
set -e
assert_eq "0" "$run_rc" "cross: binary executes in kali"
assert_contains "$run_out" "hello from builder" "cross: binary runs in kali"

# Verify on host too
assert_file_exists "$LAB/workspaces/$WS_NAME/out/hello" "cross: binary on host"

# ── Step 4: Builder-specific docker inspect ────────────────────────
section "Step 4 — Builder Docker Inspect"

# Builder should share the same bind mounts
assert_docker_mount "lab-builder" "$LAB/tools" "/opt/lab/tools" "rw" \
    "inspect: builder tools mount"
assert_docker_mount "lab-builder" "$LAB/workspaces" "/opt/lab/workspaces" "rw" \
    "inspect: builder workspaces mount"
assert_docker_mount "lab-builder" "$LAB/data" "/opt/lab/data" "rw" \
    "inspect: builder data mount"
assert_docker_mount "lab-builder" "$LAB/resources" "/opt/lab/resources" "rw" \
    "inspect: builder resources mount"
assert_docker_mount "lab-builder" "$LAB/knowledge" "/opt/lab/knowledge" "rw" \
    "inspect: builder knowledge mount"
assert_docker_mount "lab-builder" "$LAB/templates" "/opt/lab/templates" "rw" \
    "inspect: builder templates mount"

# Builder should have gcc, make available
assert_container_cmd "lab-builder" "builder: has gcc" which gcc
assert_container_cmd "lab-builder" "builder: has make" which make

# ── Step 5: Down without builder ───────────────────────────────────
section "Step 5 — Down and Non-Builder Up"

bash "$REPO_ROOT/labctl" down &>/dev/null
assert_container_stopped "lab-builder" "down: builder stopped"
assert_container_stopped "lab-kali" "down: kali stopped"

# Up without --builder — builder should NOT come back
bash "$REPO_ROOT/labctl" up &>/dev/null
assert_container_running "lab-kali" "up: kali running"
assert_container_stopped "lab-builder" "up: builder NOT running (no --builder)"

# Compiled artifact persists
assert_file_exists "$LAB/workspaces/$WS_NAME/out/hello" "persist: compiled binary survived"

# ── Teardown ───────────────────────────────────────────────────────
section "Teardown"

bash "$REPO_ROOT/labctl" down &>/dev/null
rm -rf "$LAB/workspaces/$WS_NAME"

end_scenario
