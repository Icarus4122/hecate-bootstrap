#!/usr/bin/env bash
# tests/test_compose_lib.sh — Tests for scripts/lib/compose.sh shared helper.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "lib/compose.sh file stacking"

make_sandbox
_REAL_REPO="$(dirname "$TESTS_DIR")"

# Set REPO_DIR to sandbox with minimal compose dir structure
REPO_DIR="$SANDBOX/repo"
mkdir -p "$REPO_DIR/compose"
touch "$REPO_DIR/compose/docker-compose.yml"
touch "$REPO_DIR/compose/docker-compose.gpu.yml"
touch "$REPO_DIR/compose/docker-compose.hostnet.yml"

# Source the shared lib
source "$_REAL_REPO/scripts/lib/compose.sh"

# Mock docker to capture arguments
DOCKER_ARGS_LOG="$SANDBOX/docker-args.log"
docker() { echo "$*" >> "$DOCKER_ARGS_LOG"; }
export -f docker

OUT="$SANDBOX/out.txt"

# ═══════════════════════════════════════════════════════════════════
#  Base only (no overlays)
# ═══════════════════════════════════════════════════════════════════
> "$DOCKER_ARGS_LOG"
unset LAB_GPU LAB_HOSTNET 2>/dev/null || true
_compose ps > "$OUT" 2>&1
args="$(cat "$DOCKER_ARGS_LOG")"
assert_contains "$args" "docker-compose.yml" "base: includes base file"
assert_not_contains "$args" "gpu" "base: no GPU overlay"
assert_not_contains "$args" "hostnet" "base: no hostnet overlay"

# ═══════════════════════════════════════════════════════════════════
#  LAB_GPU=1
# ═══════════════════════════════════════════════════════════════════
> "$DOCKER_ARGS_LOG"
export LAB_GPU=1
unset LAB_HOSTNET 2>/dev/null || true
_compose ps > "$OUT" 2>&1
args="$(cat "$DOCKER_ARGS_LOG")"
assert_contains "$args" "docker-compose.gpu.yml" "GPU: includes GPU overlay"
assert_not_contains "$args" "hostnet" "GPU: no hostnet overlay"

# ═══════════════════════════════════════════════════════════════════
#  LAB_HOSTNET=1
# ═══════════════════════════════════════════════════════════════════
> "$DOCKER_ARGS_LOG"
unset LAB_GPU 2>/dev/null || true
export LAB_HOSTNET=1
_compose ps > "$OUT" 2>&1
args="$(cat "$DOCKER_ARGS_LOG")"
assert_not_contains "$args" "gpu" "hostnet: no GPU overlay"
assert_contains "$args" "docker-compose.hostnet.yml" "hostnet: includes hostnet overlay"

# ═══════════════════════════════════════════════════════════════════
#  Both GPU + hostnet
# ═══════════════════════════════════════════════════════════════════
> "$DOCKER_ARGS_LOG"
export LAB_GPU=1
export LAB_HOSTNET=1
_compose ps > "$OUT" 2>&1
args="$(cat "$DOCKER_ARGS_LOG")"
assert_contains "$args" "docker-compose.gpu.yml" "both: GPU overlay present"
assert_contains "$args" "docker-compose.hostnet.yml" "both: hostnet overlay present"

# ═══════════════════════════════════════════════════════════════════
#  Extra args forwarded
# ═══════════════════════════════════════════════════════════════════
> "$DOCKER_ARGS_LOG"
unset LAB_GPU LAB_HOSTNET 2>/dev/null || true
_compose --profile build up -d > "$OUT" 2>&1
args="$(cat "$DOCKER_ARGS_LOG")"
assert_contains "$args" "--profile build up -d" "extra args: forwarded verbatim"

# ═══════════════════════════════════════════════════════════════════
#  LAB_GPU=0 treated as off (not just unset)
# ═══════════════════════════════════════════════════════════════════
> "$DOCKER_ARGS_LOG"
export LAB_GPU=0
export LAB_HOSTNET=0
_compose ps > "$OUT" 2>&1
args="$(cat "$DOCKER_ARGS_LOG")"
assert_not_contains "$args" "gpu" "explicit 0: GPU off"
assert_not_contains "$args" "hostnet" "explicit 0: hostnet off"

unset LAB_GPU LAB_HOSTNET 2>/dev/null || true

end_tests
