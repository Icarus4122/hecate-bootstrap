#!/usr/bin/env bash
# tests/test_labctl_routing.sh - Verify labctl subcommands route to the
# expected scripts/, plus structural behavior of cmd_status and the
# cmd_clean confirmation gate.
#
# Strategy:
#   - Source labctl with REPO_DIR pointing at a sandbox repo whose
#     scripts/ contains stubs that echo a deterministic marker.
#   - Call each cmd_X and assert the marker appears in output.
#   - For cmd_clean, drive the y/N prompt via stdin and assert that
#     the destructive _compose call only happens on "y".
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "labctl subcommand routing"

make_sandbox
_REAL_REPO="$(dirname "$TESTS_DIR")"
LABCTL="$_REAL_REPO/labctl"

# ── Build a sandbox "repo" with stub scripts ───────────────────────
SBREPO="$SANDBOX/repo"
mkdir -p "$SBREPO/scripts" "$SBREPO/tmux/profiles" "$SBREPO/compose"
touch "$SBREPO/.env"
touch "$SBREPO/compose/docker-compose.yml"

# Each stub prints a marker we can grep for.
make_stub() {
    local name="$1" marker="$2"
    cat > "$SBREPO/scripts/$name" <<EOF
#!/usr/bin/env bash
echo "${marker} \$*"
exit 0
EOF
    chmod +x "$SBREPO/scripts/$name"
}
make_stub verify-host.sh      "STUB_VERIFY"
make_stub update-lab.sh       "STUB_UPDATE"
make_stub create-workspace.sh "STUB_WORKSPACE"
make_stub launch-lab.sh       "STUB_LAUNCH"
make_stub sync-binaries.sh    "STUB_SYNC"
make_stub bootstrap-host.sh   "STUB_BOOTSTRAP"
make_stub guide.sh            "STUB_GUIDE"

# Stub tmux profile.
echo '#!/usr/bin/env bash' > "$SBREPO/tmux/profiles/default.sh"
echo 'echo "STUB_TMUX_DEFAULT"' >> "$SBREPO/tmux/profiles/default.sh"
chmod +x "$SBREPO/tmux/profiles/default.sh"

# ── Source libs and labctl functions ───────────────────────────────
source "$_REAL_REPO/scripts/lib/compose.sh"
source "$_REAL_REPO/scripts/lib/ui.sh"

# Strip the shebang/set/main-call so we can source as a library.
sed -e 's/^set -euo pipefail$//' \
    -e 's/^main "\$@"$//' \
    -e '/^source.*lib\/compose\.sh/d' \
    -e '/^source.*lib\/ui\.sh/d' \
    "$LABCTL" > "$SANDBOX/labctl-funcs.sh"

REPO_DIR="$SBREPO"
SCRIPT_PATH="$LABCTL"
export LAB_ROOT="$SANDBOX/opt/lab"
mkdir -p "$LAB_ROOT/workspaces" "$LAB_ROOT/tools/binaries"

source "$SANDBOX/labctl-funcs.sh"
REPO_DIR="$SBREPO"  # may have been clobbered by labctl's own assignment

# Mock _compose so up/down/clean don't need real Docker.
_COMPOSE_LOG="$SANDBOX/compose.log"
: > "$_COMPOSE_LOG"
_compose() { echo "_compose $*" >> "$_COMPOSE_LOG"; return 0; }
docker() { echo "docker $*" >> "$_COMPOSE_LOG"; return 0; }
export -f docker

# ═══════════════════════════════════════════════════════════════════
#  Routing: verify / update / workspace / launch / sync / guide
# ═══════════════════════════════════════════════════════════════════
out="$(cmd_verify --check 2>&1)"
assert_contains "$out" "STUB_VERIFY --check"  "verify routes to scripts/verify-host.sh and forwards args"

out="$(cmd_update --empusa 2>&1)"
assert_contains "$out" "STUB_UPDATE --empusa" "update routes to scripts/update-lab.sh and forwards args"

out="$(cmd_workspace box1 --profile htb 2>&1)"
assert_contains "$out" "STUB_WORKSPACE box1 --profile htb" \
    "workspace routes to scripts/create-workspace.sh and forwards args"

out="$(cmd_launch htb 2>&1)"
assert_contains "$out" "STUB_LAUNCH htb" "launch routes to scripts/launch-lab.sh"

out="$(cmd_sync --dry-run 2>&1)"
assert_contains "$out" "STUB_SYNC --dry-run" "sync routes to scripts/sync-binaries.sh"

out="$(cmd_guide 2>&1)"
assert_contains "$out" "STUB_GUIDE" "guide routes to scripts/guide.sh"

# tmux dispatch
out="$(cmd_tmux default 2>&1)"
assert_contains "$out" "STUB_TMUX_DEFAULT" "tmux <profile> routes to tmux/profiles/<profile>.sh"

# tmux with no arg lists profiles
out="$(cmd_tmux 2>&1)"
assert_contains "$out" "default" "tmux (no arg) lists default profile"
assert_contains "$out" "htb"     "tmux (no arg) lists htb profile"

# tmux unknown profile -> exit 1
rc=0
out="$(cmd_tmux nonexistent-profile 2>&1)" || rc=$?
assert_eq "1" "$rc" "tmux unknown profile -> exit 1"
assert_contains "$out" "[FAIL]" "tmux unknown profile -> [FAIL] marker"

# ═══════════════════════════════════════════════════════════════════
#  cmd_status: prints LAB_ROOT path and mode information
# ═══════════════════════════════════════════════════════════════════
out="$(cmd_status 2>&1)"
assert_contains "$out" "$LAB_ROOT"  "status: prints LAB_ROOT path"
assert_contains "$out" "Network"    "status: shows Network section"
assert_contains "$out" "GPU"        "status: shows GPU section"
assert_contains "$out" "VPN"        "status: shows VPN section"
assert_contains "$out" "Workspaces" "status: shows Workspaces count line"

# Mode flips show through
LAB_HOSTNET=1 out="$(cmd_status 2>&1)"
assert_contains "$out" "host" "status with LAB_HOSTNET=1: reports host network mode"

LAB_GPU=1 out="$(cmd_status 2>&1)"
assert_contains "$out" "on" "status with LAB_GPU=1: reports GPU on"

# ═══════════════════════════════════════════════════════════════════
#  cmd_clean: confirmation gate
# ═══════════════════════════════════════════════════════════════════
# Decline path ("n"): _compose down must NOT be invoked.
: > "$_COMPOSE_LOG"
out="$(cmd_clean <<<"n" 2>&1)"
assert_contains "$out" "Aborted" "clean decline: prints Aborted"
if grep -q "_compose down" "$_COMPOSE_LOG"; then
    _record_fail "clean decline: no destructive _compose call" \
        "_compose down was invoked" "no _compose down call"
else
    _record_pass "clean decline: no destructive _compose call"
fi

# Accept path ("y"): _compose down -v --remove-orphans must be invoked.
: > "$_COMPOSE_LOG"
out="$(cmd_clean <<<"y" 2>&1)"
assert_contains "$out" "[PASS]" "clean accept: emits [PASS]"
if grep -q "_compose down -v --remove-orphans" "$_COMPOSE_LOG"; then
    _record_pass "clean accept: invoked _compose down -v --remove-orphans"
else
    _record_fail "clean accept: invoked _compose down -v --remove-orphans" \
        "$(cat "$_COMPOSE_LOG")" "_compose down -v --remove-orphans"
fi
if grep -q "docker image prune -f" "$_COMPOSE_LOG"; then
    _record_pass "clean accept: invoked docker image prune -f"
else
    _record_fail "clean accept: invoked docker image prune -f" \
        "$(cat "$_COMPOSE_LOG")" "docker image prune -f"
fi

end_tests
