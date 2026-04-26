#!/usr/bin/env bash
# tests/test_compose_binary_selection.sh - Tests that scripts/lib/compose.sh
# correctly prefers `docker compose` (plugin), falls back to `docker-compose`
# (standalone), and fails cleanly when neither is available.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "compose binary selection"

make_sandbox
_REAL_REPO="$(dirname "$TESTS_DIR")"

REPO_DIR="$SANDBOX/repo"
mkdir -p "$REPO_DIR/compose"
touch "$REPO_DIR/compose/docker-compose.yml"

source "$_REAL_REPO/scripts/lib/compose.sh"

LOG="$SANDBOX/log"

# ═══════════════════════════════════════════════════════════════════
#  Plugin preferred when both are available
# ═══════════════════════════════════════════════════════════════════
: > "$LOG"
docker() {
    if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
        echo "Docker Compose version v2.x" ; return 0
    fi
    echo "DOCKER_PLUGIN $*" >> "$LOG"
    return 0
}
docker-compose() {
    echo "STANDALONE $*" >> "$LOG"
    return 0
}
export -f docker docker-compose

_compose ps >/dev/null 2>&1
out="$(cat "$LOG")"
assert_contains "$out" "DOCKER_PLUGIN compose" \
    "plugin preferred: 'docker compose' invoked when plugin available"
assert_not_contains "$out" "STANDALONE" \
    "plugin preferred: 'docker-compose' standalone NOT invoked"

# ═══════════════════════════════════════════════════════════════════
#  Fallback to docker-compose when plugin probe fails
# ═══════════════════════════════════════════════════════════════════
: > "$LOG"
docker() {
    if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
        return 1   # plugin probe fails
    fi
    echo "DOCKER_PLUGIN $*" >> "$LOG"
    return 0
}
docker-compose() {
    echo "STANDALONE $*" >> "$LOG"
    return 0
}
export -f docker docker-compose

_compose ps >/dev/null 2>&1
out="$(cat "$LOG")"
assert_contains "$out" "STANDALONE" \
    "fallback: docker-compose standalone invoked when plugin probe fails"

# ═══════════════════════════════════════════════════════════════════
#  Neither available -> clean [FAIL] and nonzero exit
# ═══════════════════════════════════════════════════════════════════
: > "$LOG"
docker() {
    if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then
        return 1
    fi
    echo "DOCKER_PLUGIN $*" >> "$LOG"
    return 0
}
unset -f docker-compose
# command -v docker-compose must report not-found. Override via PATH so
# `command -v` cannot find it.
SAFE_PATH=""
mkdir -p "$SANDBOX/empty-bin"
SAFE_PATH="$SANDBOX/empty-bin"
export -f docker

rc=0
out="$(PATH="$SAFE_PATH" _compose ps 2>&1)" || rc=$?
assert_neq "0" "$rc" "no compose: nonzero exit"
assert_contains "$out" "[FAIL]" "no compose: [FAIL] marker"
assert_contains "$out" "Compose" "no compose: mentions Docker Compose"
assert_contains "$out" "docker-compose-plugin" "no compose: suggests install command"

end_tests
