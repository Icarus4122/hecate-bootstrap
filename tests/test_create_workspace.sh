#!/usr/bin/env bash
# tests/test_ceate_wokspace.sh - Tests for scripts/create-workspace.sh.
#
# We test the shell fallback path (no Empusa installed) by running
# the script directly with a sandboxed LAB_ROOT.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "create-workspace.sh logic"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/create-workspace.sh"

# Set up sandbox LAB_ROOT with no Empusa binary
export LAB_ROOT="$SANDBOX/opt/lab"
mkdir -p "$LAB_ROOT/workspaces"

# Build a minimal PATH that excludes empusa (it may be on the host).
# The script needs: bash, ls, mkdir, dirname, cd - all in /usr/bin o /bin.
SAFE_PATH="/usr/bin:/bin"

# ═══════════════════════════════════════════════════════════════════
#  No arguments -> usage (exits 0)
# ═══════════════════════════════════════════════════════════════════
c=0
PATH="$SAFE_PATH" bash "$SCRIPT" > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "no args: exits 0 (usage)"
assert_contains "$(cat "$OUT")" "Usage" "no args: prints usage"

# ═══════════════════════════════════════════════════════════════════
#  Fallback scaffold: new workspace
# ═══════════════════════════════════════════════════════════════════
c=0
PATH="$SAFE_PATH" bash "$SCRIPT" "testbox" > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "fallback: exits 0"
assert_dir_exists "$LAB_ROOT/workspaces/testbox" "fallback: workspace dir created"
assert_dir_exists "$LAB_ROOT/workspaces/testbox/notes" "fallback: notes/ created"
assert_dir_exists "$LAB_ROOT/workspaces/testbox/scans" "fallback: scans/ created"
assert_dir_exists "$LAB_ROOT/workspaces/testbox/loot" "fallback: loot/ created"
assert_dir_exists "$LAB_ROOT/workspaces/testbox/logs" "fallback: logs/ created"
assert_contains "$(cat "$OUT")" "fallback" "fallback: output mentions fallback"

# ═══════════════════════════════════════════════════════════════════
#  Fallback: workspace already exists -> no error
# ═══════════════════════════════════════════════════════════════════
c=0
PATH="$SAFE_PATH" bash "$SCRIPT" "testbox" > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "idempotent: exits 0 when workspace exists"
assert_contains "$(cat "$OUT")" "Already exists" "idempotent: reports already exists"

# ═══════════════════════════════════════════════════════════════════
#  --profile flag is accepted
# ═══════════════════════════════════════════════════════════════════
c=0
PATH="$SAFE_PATH" bash "$SCRIPT" "buildbox" --profile build > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "--profile flag: exits 0"
assert_dir_exists "$LAB_ROOT/workspaces/buildbox" "--profile flag: workspace created"
assert_contains "$(cat "$OUT")" "build" "--profile flag: output mentions profile name"

end_tests
