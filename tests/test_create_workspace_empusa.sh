#!/usr/bin/env bash
# tests/test_create_workspace_empusa.sh - Tests for the Empusa
# delegation path of scripts/create-workspace.sh.
#
# We stub `empusa` as a recording shell script (writes its argv to a
# logfile) and verify create-workspace.sh:
#   - prefers ${LAB_ROOT}/tools/venvs/empusa/bin/empusa over PATH
#   - falls back to PATH empusa when the venv binary is absent
#   - invokes the documented contract:
#       empusa workspace init --name <n> --profile <p> \
#                             --root <root> --templates-dir <td> --set-active
#   - threads LAB_ROOT through to --root
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "create-workspace.sh empusa delegation"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/create-workspace.sh"

# ── Stub builder ───────────────────────────────────────────────────
# Each stub records its identity + argv to a fresh log file so we can
# tell which binary was actually invoked.
make_recording_stub() {
    local path="$1" tag="$2" log="$3"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF
#!/usr/bin/env bash
{
    echo "BIN=${tag}"
    for a in "\$@"; do echo "ARG=\$a"; done
} > "${log}"
exit 0
EOF
    chmod +x "$path"
}

# ═══════════════════════════════════════════════════════════════════
#  Case A: venv empusa wins over PATH empusa
# ═══════════════════════════════════════════════════════════════════
LAB_A="$SANDBOX/labA"
mkdir -p "$LAB_A/workspaces"
LOG_A="$SANDBOX/A.log"
PATH_BIN_A="$SANDBOX/path-bin-A"
mkdir -p "$PATH_BIN_A"

make_recording_stub "$LAB_A/tools/venvs/empusa/bin/empusa" "VENV" "$LOG_A"
make_recording_stub "$PATH_BIN_A/empusa"                   "PATH" "$LOG_A"

# Mark log empty so we can detect if neither stub wrote.
: > "$LOG_A"
LAB_ROOT="$LAB_A" PATH="$PATH_BIN_A:/usr/bin:/bin" \
    bash "$SCRIPT" "boxA" --profile htb > "$OUT" 2>&1
assert_contains "$(cat "$LOG_A")" "BIN=VENV" \
    "venv empusa wins: venv binary was invoked (not PATH)"
assert_not_contains "$(cat "$LOG_A")" "BIN=PATH" \
    "venv empusa wins: PATH binary was NOT invoked"

# Verify contract argv: name, profile, root, templates-dir, set-active
log_contents="$(cat "$LOG_A")"
assert_contains "$log_contents" "ARG=workspace" "venv: argv has 'workspace'"
assert_contains "$log_contents" "ARG=init"      "venv: argv has 'init'"
assert_contains "$log_contents" "ARG=--name"    "venv: argv has --name"
assert_contains "$log_contents" "ARG=boxA"      "venv: argv has the workspace name"
assert_contains "$log_contents" "ARG=--profile" "venv: argv has --profile"
assert_contains "$log_contents" "ARG=htb"       "venv: argv has profile value 'htb'"
assert_contains "$log_contents" "ARG=--root"    "venv: argv has --root"
assert_contains "$log_contents" "ARG=$LAB_A/workspaces" \
    "venv: --root resolves to LAB_ROOT/workspaces (LAB_ROOT override honored)"
assert_contains "$log_contents" "ARG=--templates-dir" "venv: argv has --templates-dir"
assert_contains "$log_contents" "ARG=$_REAL_REPO/templates" \
    "venv: --templates-dir is REPO_DIR/templates"
assert_contains "$log_contents" "ARG=--set-active" "venv: argv has --set-active"

# ═══════════════════════════════════════════════════════════════════
#  Case B: PATH empusa is used when venv binary is absent
# ═══════════════════════════════════════════════════════════════════
LAB_B="$SANDBOX/labB"
mkdir -p "$LAB_B/workspaces"
LOG_B="$SANDBOX/B.log"
PATH_BIN_B="$SANDBOX/path-bin-B"
mkdir -p "$PATH_BIN_B"

# Note: NO venv stub created.
make_recording_stub "$PATH_BIN_B/empusa" "PATH" "$LOG_B"

: > "$LOG_B"
LAB_ROOT="$LAB_B" PATH="$PATH_BIN_B:/usr/bin:/bin" \
    bash "$SCRIPT" "boxB" --profile research > "$OUT" 2>&1
assert_contains "$(cat "$LOG_B")" "BIN=PATH" \
    "no venv: PATH empusa was invoked"
assert_contains "$(cat "$LOG_B")" "ARG=research" \
    "no venv: --profile value 'research' threaded through"
assert_contains "$(cat "$LOG_B")" "ARG=$LAB_B/workspaces" \
    "no venv: --root reflects LAB_ROOT override"

# Fallback scaffold must NOT have run on the Empusa-present paths.
if [[ -d "$LAB_B/workspaces/boxB/notes" ]]; then
    _record_fail "PATH empusa: fallback scaffold did NOT run" \
        "(notes/ created)" "no fallback dirs"
else
    _record_pass "PATH empusa: fallback scaffold did NOT run"
fi

# ═══════════════════════════════════════════════════════════════════
#  Case C: no Empusa anywhere -> fallback scaffold
#  (Already covered in test_create_workspace.sh; we add one assertion
#   confirming the fallback degraded message + rc=0.)
# ═══════════════════════════════════════════════════════════════════
LAB_C="$SANDBOX/labC"
mkdir -p "$LAB_C/workspaces"
SAFE_PATH="/usr/bin:/bin"

c=0
LAB_ROOT="$LAB_C" PATH="$SAFE_PATH" \
    bash "$SCRIPT" "boxC" --profile htb > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "no empusa: fallback exits 0"
assert_dir_exists "$LAB_C/workspaces/boxC/notes" "no empusa: notes/ created"
assert_dir_exists "$LAB_C/workspaces/boxC/scans" "no empusa: scans/ created"
assert_dir_exists "$LAB_C/workspaces/boxC/loot"  "no empusa: loot/ created"
assert_dir_exists "$LAB_C/workspaces/boxC/logs"  "no empusa: logs/ created"
assert_contains "$(cat "$OUT")" "Empusa not found" \
    "no empusa: warns 'Empusa not found'"

end_tests
