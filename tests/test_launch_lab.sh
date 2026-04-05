#!/usr/bin/env bash
# tests/test_launch_lab.sh — Tests for scripts/launch-lab.sh logic.
#
# We source launch-lab.sh after stripping the main call and mocking
# docker to capture compose file stacking and ensure_workspace fallback.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "launch-lab.sh logic"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/launch-lab.sh"

# Build a sourceable version: strip set -euo, main call, and lib source
# (the shared lib is sourced directly below with the real repo path)
sed -e 's/^set -euo pipefail$//' \
    -e 's/^main "\$@"$//' \
    -e '/^source.*lib\/compose\.sh/d' \
    "$SCRIPT" > "$SANDBOX/launch-funcs.sh"

# Set up sandbox environment
export LAB_ROOT="$SANDBOX/opt/lab"
mkdir -p "$LAB_ROOT"/{workspaces,tools/venvs/empusa/bin}
export COMPOSE_PROJECT_NAME="lab"

# Source shared compose helper from real repo, then the script functions.
source "$_REAL_REPO/scripts/lib/compose.sh"
source "$SANDBOX/launch-funcs.sh"

# Force fallback mode (empusa may be on the host PATH)
EMPUSA=""
_TAG="fallback"

# Override REPO_DIR to our sandbox repo (for compose file stacking)
REPO_DIR="$SANDBOX/repo"
mkdir -p "$REPO_DIR/compose"
touch "$REPO_DIR/compose/docker-compose.yml"
touch "$REPO_DIR/compose/docker-compose.gpu.yml"
touch "$REPO_DIR/compose/docker-compose.hostnet.yml"

# ── Mock docker to capture arguments ──────────────────────────────
DOCKER_ARGS_LOG="$SANDBOX/docker-args.log"
docker() {
    echo "$*" >> "$DOCKER_ARGS_LOG"
}
export -f docker

# ═══════════════════════════════════════════════════════════════════
#  ensure_workspace: fallback path (no Empusa)
# ═══════════════════════════════════════════════════════════════════

# EMPUSA should be "" since we have no binary
assert_eq "" "$EMPUSA" "ensure_workspace: EMPUSA is empty (no binary)"

# Case 1: workspace does not exist → creates scaffold
ensure_workspace htb "target1" > "$OUT" 2>&1
assert_dir_exists "$LAB_ROOT/workspaces/target1" "fallback: workspace dir created"
assert_dir_exists "$LAB_ROOT/workspaces/target1/notes" "fallback: notes/ created"
assert_dir_exists "$LAB_ROOT/workspaces/target1/scans" "fallback: scans/ created"
assert_dir_exists "$LAB_ROOT/workspaces/target1/loot" "fallback: loot/ created"
assert_dir_exists "$LAB_ROOT/workspaces/target1/logs" "fallback: logs/ created"
assert_contains "$(cat "$OUT")" "fallback" "fallback: output mentions fallback"

# Case 2: workspace already exists → skips creation
ensure_workspace htb "target1" > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "exists" "fallback: existing workspace detected"

# ═══════════════════════════════════════════════════════════════════
#  launch_htb: requires target argument
#  (run in subshell — die() calls exit)
# ═══════════════════════════════════════════════════════════════════
rc=0
( launch_htb > "$OUT" 2>&1 ) || rc=$?
assert_eq "1" "$rc" "launch_htb: no target → exit 1"
assert_contains "$(cat "$OUT")" "requires a target" "launch_htb: error message mentions target"

# ═══════════════════════════════════════════════════════════════════
#  dispatch: unknown profile
# ═══════════════════════════════════════════════════════════════════
rc=0
( main "nonexistent" > "$OUT" 2>&1 ) || rc=$?
assert_eq "1" "$rc" "dispatch: unknown profile → exit 1"
assert_contains "$(cat "$OUT")" "Unknown profile" "dispatch: error mentions unknown profile"

end_tests
