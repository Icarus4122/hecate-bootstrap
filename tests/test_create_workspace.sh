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

# ── Fallback degradation: must NOT have profile-specific dirs ──────
for missing_dir in web creds exploits screenshots reports; do
    if [[ -d "$LAB_ROOT/workspaces/testbox/$missing_dir" ]]; then
        _record_fail "fallback: ${missing_dir}/ must NOT exist" "present" "absent"
    else
        _record_pass "fallback: ${missing_dir}/ correctly absent"
    fi
done

# Fallback must not create metadata file
if [[ -f "$LAB_ROOT/workspaces/testbox/.empusa-workspace.json" ]]; then
    _record_fail "fallback: no metadata file" "present" "absent"
else
    _record_pass "fallback: no metadata file (correctly degraded)"
fi

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

# ═══════════════════════════════════════════════════════════════════
#  --profile build fallback still creates only generic dirs
# ═══════════════════════════════════════════════════════════════════
# The build profile in Empusa has: src, out, notes, logs.  The fallback
# knows nothing about profiles - it always creates the same 4 generic
# dirs regardless of --profile.  This is intentional degradation.
assert_dir_exists "$LAB_ROOT/workspaces/buildbox/notes" "build fallback: notes/ created"
assert_dir_exists "$LAB_ROOT/workspaces/buildbox/scans" "build fallback: scans/ (generic)"
assert_dir_exists "$LAB_ROOT/workspaces/buildbox/loot"  "build fallback: loot/ (generic)"
assert_dir_exists "$LAB_ROOT/workspaces/buildbox/logs"  "build fallback: logs/ created"

# Build profile-specific dirs must NOT exist in fallback
for build_only in src out; do
    if [[ -d "$LAB_ROOT/workspaces/buildbox/$build_only" ]]; then
        _record_fail "build fallback: ${build_only}/ must NOT exist" "present" "absent"
    else
        _record_pass "build fallback: ${build_only}/ correctly absent (profile-unaware)"
    fi
done

end_tests
