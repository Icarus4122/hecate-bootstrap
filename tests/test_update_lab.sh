#!/usr/bin/env bash
# tests/test_update_lab.sh - Tests for scripts/update-lab.sh logic.
#
# We source the script to test parse_flags, step_verify_repo,
# and summary tracking functions.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "update-lab.sh logic"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/update-lab.sh"

# Build a sourceable version: strip set -euo, main call, and lib source lines
sed -e 's/^set -euo pipefail$//' \
    -e 's/^main "\$@"$//' \
    -e '/^source.*lib\/compose\.sh/d' \
    -e '/^source.*lib\/ui\.sh/d' \
    "$SCRIPT" > "$SANDBOX/update-funcs.sh"

export LAB_ROOT="$SANDBOX/opt/lab"
export COMPOSE_PROJECT_NAME="lab"
mkdir -p "$LAB_ROOT"

# Source shared helpers from real repo, then the script functions.
source "$_REAL_REPO/scripts/lib/ui.sh"
source "$_REAL_REPO/scripts/lib/compose.sh"
source "$SANDBOX/update-funcs.sh"

# Override REPO_DIR to our sandbox
REPO_DIR="$SANDBOX/repo"
mkdir -p "$REPO_DIR"

# Mock docker to prevent real calls
docker() { echo "mock-docker $*"; }
export -f docker

# ═══════════════════════════════════════════════════════════════════
#  parse_flags - sets OPT_* variables correctly
# ═══════════════════════════════════════════════════════════════════

# Reset defaults
OPT_PULL=0; OPT_EMPUSA=0; OPT_BINARIES=0; OPT_BUILD=1; OPT_RESTART=1; OPT_BUILDER=0; OPT_FORCE=0

parse_flags --pull --empusa --binaries --no-build --no-restart --builder --force
assert_eq "1" "$OPT_PULL"      "parse_flags: --pull"
assert_eq "1" "$OPT_EMPUSA"    "parse_flags: --empusa"
assert_eq "1" "$OPT_BINARIES"  "parse_flags: --binaries"
assert_eq "0" "$OPT_BUILD"     "parse_flags: --no-build"
assert_eq "0" "$OPT_RESTART"   "parse_flags: --no-restart"
assert_eq "1" "$OPT_BUILDER"   "parse_flags: --builder"
assert_eq "1" "$OPT_FORCE"     "parse_flags: --force"

# Reset defaults
OPT_PULL=0; OPT_EMPUSA=0; OPT_BINARIES=0; OPT_BUILD=1; OPT_RESTART=1; OPT_BUILDER=0; OPT_FORCE=0

parse_flags --gpu --hostnet
assert_eq "1" "${LAB_GPU:-0}"     "parse_flags: --gpu exports LAB_GPU=1"
assert_eq "1" "${LAB_HOSTNET:-0}" "parse_flags: --hostnet exports LAB_HOSTNET=1"
unset LAB_GPU LAB_HOSTNET

# parse_flags: unknown flag -> die (run in subshell - die calls exit)
rc=0
( OPT_PULL=0; OPT_EMPUSA=0; OPT_BINARIES=0; OPT_BUILD=1; OPT_RESTART=1; OPT_BUILDER=0; OPT_FORCE=0
  parse_flags --bogus > "$OUT" 2>&1 ) || rc=$?
assert_eq "1" "$rc" "parse_flags: unknown flag -> exit 1"

# ═══════════════════════════════════════════════════════════════════
#  step_verify_repo - critical file presence
# ═══════════════════════════════════════════════════════════════════

# Case 1: missing critical files -> die (subshell for exit)
rc=0
( step_verify_repo > "$OUT" 2>&1 ) || rc=$?
assert_eq "1" "$rc" "verify_repo: missing files -> exit 1"

# Case 2: all critical files present
mkdir -p "$REPO_DIR"/{compose,docker/kali-main,scripts}
touch "$REPO_DIR/compose/docker-compose.yml"
touch "$REPO_DIR/docker/kali-main/Dockerfile"
touch "$REPO_DIR/scripts/verify-host.sh"
rc=0
step_verify_repo > "$OUT" 2>&1 || rc=$?
assert_eq "0" "$rc" "verify_repo: all present -> success"
assert_contains "$(cat "$OUT")" "intact" "verify_repo: reports intact"

# ═══════════════════════════════════════════════════════════════════
#  Summary tracking: _done, _skipped, _failed
# ═══════════════════════════════════════════════════════════════════
SUMMARY=()
_done "step A"
_skipped "step B"
_failed "step C"

assert_eq "3" "${#SUMMARY[@]}" "summary tracking: 3 entries"
assert_contains "${SUMMARY[0]}" "step A" "summary: _done recorded"
assert_contains "${SUMMARY[0]}" "[PASS]" "summary: _done prefix"
assert_contains "${SUMMARY[1]}" "step B" "summary: _skipped recorded"
assert_contains "${SUMMARY[1]}" "[INFO]" "summary: _skipped prefix"
assert_contains "${SUMMARY[2]}" "step C" "summary: _failed recorded"
assert_contains "${SUMMARY[2]}" "[WARN]" "summary: _failed prefix"

# ═══════════════════════════════════════════════════════════════════
#  step_summary - failure detection
# ═══════════════════════════════════════════════════════════════════

# With a failure in SUMMARY
SUMMARY=()
_done "ok step"
_failed "bad step"
step_summary > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "warnings" "step_summary: failure -> warnings message"

# All clean
SUMMARY=()
_done "ok step 1"
_done "ok step 2"
step_summary > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "Update complete" "step_summary: all clean -> complete"

# ═══════════════════════════════════════════════════════════════════
#  step_empusa / step_binaries - skipped by default
# ═══════════════════════════════════════════════════════════════════
SUMMARY=()
OPT_EMPUSA=0
step_empusa > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "Skipped" "step_empusa: OPT off -> skipped"

SUMMARY=()
OPT_BINARIES=0
step_binaries > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "Skipped" "step_binaries: OPT off -> skipped"

end_tests
