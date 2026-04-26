#!/usr/bin/env bash
# tests/test_verify_host_paths.sh - PATH-stub negative tests for
# scripts/verify-host.sh's check_commands and check_docker, plus a
# read-only behavior assertion.
#
# Existing test_verify_host.sh covers _pass/_warn/_fail counters,
# check_lab_layout, check_repo_files, check_empusa, and print_summary.
# This file adds:
#   - missing docker          -> [FAIL] from check_commands + check_docker
#   - missing compose         -> [FAIL] from check_docker
#   - missing git / python3   -> [FAIL] from check_commands (current sev.)
#   - verify-host.sh is read-only (no workspaces created)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "verify-host.sh PATH stubs / read-only"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/verify-host.sh"

# Sourceable: strip set/main/source-of-ui to leave funcs only.
sed -e 's/^set -euo pipefail$//' \
    -e 's/^main "\$@"$//' \
    -e '/^source.*lib\/ui\.sh/d' \
    "$SCRIPT" > "$SANDBOX/verify-funcs.sh"

export LAB_ROOT="$SANDBOX/opt/lab"
mkdir -p "$LAB_ROOT"

source "$_REAL_REPO/scripts/lib/ui.sh"
source "$SANDBOX/verify-funcs.sh"

REPO_DIR="$_REAL_REPO"

_reset() { PASS=0; WARN=0; FAIL=0; FAIL_LOG=(); WARN_LOG=(); }

# ── Build a minimal "utility" bin dir with thin wrappers around the
#    helpers the script's success branches need (head/wc/find/grep/cat).
#    We use wrapper scripts (not symlinks) because Git-Bash MSYS binaries
#    require their sibling DLLs from /usr/bin to load -- a bare symlink
#    breaks DLL resolution and the binary fails with rc=127.  Anything
#    the script looks up (docker/git/etc.) MUST be absent from this dir
#    so that `command -v <cmd>` returns nothing in FAIL-path tests.
UTIL_BIN="$SANDBOX/util-bin"
mkdir -p "$UTIL_BIN"
for u in head wc find grep cat sed awk tr cut sort uniq; do
    src="$(command -v "$u" 2>/dev/null || true)"
    if [[ -n "$src" ]]; then
        printf '#!/bin/bash\nexec %q "$@"\n' "$src" > "$UTIL_BIN/$u"
        chmod +x "$UTIL_BIN/$u"
    fi
done

# Helper: build a stub-bin dir that contains the requested commands as
# trivial recording stubs, plus the utility wrappers above.
make_stub_bin() {
    local dir="$1"; shift
    mkdir -p "$dir"
    # Copy utility wrappers
    for f in "$UTIL_BIN"/*; do
        [[ -e "$f" ]] || continue
        cp -f "$f" "$dir/$(basename "$f")"
    done
    # Create requested command stubs
    for cmd in "$@"; do
        cat > "$dir/$cmd" <<EOF
#!/bin/bash
echo "${cmd} stub 1.0"
exit 0
EOF
        chmod +x "$dir/$cmd"
    done
}

# An "empty" stub bin: only utilities, no docker/git/etc.
EMPTY_BIN="$SANDBOX/empty-bin"
make_stub_bin "$EMPTY_BIN"
EMPTY_PATH="$EMPTY_BIN"

# ═══════════════════════════════════════════════════════════════════
#  check_commands - all required commands missing
# ═══════════════════════════════════════════════════════════════════
_reset
PATH="$EMPTY_PATH" check_commands > "$OUT" 2>&1

# 6 commands: docker, git, curl, jq, file, python3
assert_eq "6" "$FAIL" "check_commands: 6 missing -> 6 FAILs"
for cmd in docker git curl jq file python3; do
    assert_contains "$(cat "$OUT")" "${cmd} not found" \
        "check_commands: reports '${cmd} not found'"
done
assert_contains "$(cat "$OUT")" "[FAIL]" "check_commands: emits [FAIL] marker"
assert_contains "$(cat "$OUT")" "sudo apt install" "check_commands: suggests apt install"

# ═══════════════════════════════════════════════════════════════════
#  check_commands - only docker missing (others stubbed)
# ═══════════════════════════════════════════════════════════════════
STUB_BIN="$SANDBOX/stub-bin"
make_stub_bin "$STUB_BIN" git curl jq file python3

_reset
PATH="$STUB_BIN" check_commands > "$OUT" 2>&1
assert_eq "1" "$FAIL" "check_commands: only docker missing -> 1 FAIL"
assert_contains "$(cat "$OUT")" "docker not found" "check_commands: docker missing reported"

# ═══════════════════════════════════════════════════════════════════
#  check_commands - only git missing
# ═══════════════════════════════════════════════════════════════════
STUB_BIN2="$SANDBOX/stub-bin2"
make_stub_bin "$STUB_BIN2" docker curl jq file python3

_reset
PATH="$STUB_BIN2" check_commands > "$OUT" 2>&1
assert_eq "1" "$FAIL" "check_commands: only git missing -> 1 FAIL (current severity)"
assert_contains "$(cat "$OUT")" "git not found" "check_commands: git missing reported"

# ═══════════════════════════════════════════════════════════════════
#  check_commands - only python3 missing
# ═══════════════════════════════════════════════════════════════════
STUB_BIN3="$SANDBOX/stub-bin3"
make_stub_bin "$STUB_BIN3" docker git curl jq file

_reset
PATH="$STUB_BIN3" check_commands > "$OUT" 2>&1
assert_eq "1" "$FAIL" "check_commands: only python3 missing -> 1 FAIL (current severity)"
assert_contains "$(cat "$OUT")" "python3 not found" "check_commands: python3 missing reported"

# ═══════════════════════════════════════════════════════════════════
#  check_docker - no docker at all -> [FAIL] daemon + [FAIL] compose
# ═══════════════════════════════════════════════════════════════════
_reset
PATH="$EMPTY_PATH" check_docker > "$OUT" 2>&1
assert_match "$FAIL" "^[1-9]" "check_docker: no docker -> >=1 FAIL"
assert_contains "$(cat "$OUT")" "Docker daemon unreachable" \
    "check_docker: 'Docker daemon unreachable'"
assert_contains "$(cat "$OUT")" "Docker Compose not found" \
    "check_docker: 'Docker Compose not found'"
assert_contains "$(cat "$OUT")" "[FAIL]" "check_docker: [FAIL] marker present"

# ═══════════════════════════════════════════════════════════════════
#  check_docker - docker present but compose plugin/standalone absent
# ═══════════════════════════════════════════════════════════════════
DOCK_BIN="$SANDBOX/dock-bin"
make_stub_bin "$DOCK_BIN"
cat > "$DOCK_BIN/docker" <<'EOF'
#!/bin/bash
case "${1:-}" in
    info)    exit 0 ;;          # daemon reachable
    compose) exit 1 ;;          # plugin not available
    *)       exit 0 ;;
esac
EOF
chmod +x "$DOCK_BIN/docker"
# No docker-compose stub: standalone also absent.

_reset
PATH="$DOCK_BIN" check_docker > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "[PASS]" "check_docker: daemon reachable -> [PASS]"
assert_contains "$(cat "$OUT")" "Docker Compose not found" \
    "check_docker: compose absent -> [FAIL] Compose not found"
assert_match "$FAIL" "^[1-9]" "check_docker: missing compose -> >=1 FAIL"

# ═══════════════════════════════════════════════════════════════════
#  check_docker - docker + standalone docker-compose only
# ═══════════════════════════════════════════════════════════════════
LEGACY_BIN="$SANDBOX/legacy-bin"
make_stub_bin "$LEGACY_BIN"
cat > "$LEGACY_BIN/docker" <<'EOF'
#!/bin/bash
case "${1:-}" in
    info)    exit 0 ;;
    compose) exit 1 ;;          # plugin missing -> falls through to docker-compose
    *)       exit 0 ;;
esac
EOF
chmod +x "$LEGACY_BIN/docker"
cat > "$LEGACY_BIN/docker-compose" <<'EOF'
#!/bin/bash
echo "docker-compose 1.29.2"
exit 0
EOF
chmod +x "$LEGACY_BIN/docker-compose"

_reset
PATH="$LEGACY_BIN" check_docker > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "[WARN]" \
    "check_docker: legacy docker-compose only -> [WARN] (not [FAIL])"
assert_contains "$(cat "$OUT")" "Legacy docker-compose found" \
    "check_docker: explicitly mentions legacy docker-compose"
assert_eq "0" "$FAIL" "check_docker: legacy compose -> 0 FAIL"

# ═══════════════════════════════════════════════════════════════════
#  Read-only assertion: full-script run must NOT mutate workspaces
# ═══════════════════════════════════════════════════════════════════
RO_LAB="$SANDBOX/ro-lab"
mkdir -p "$RO_LAB/workspaces"
# Snapshot before
before="$(find "$RO_LAB" -type f -o -type d 2>/dev/null | sort)"

# Run the real script (allow it to fail; we only care that nothing
# new shows up under LAB_ROOT/workspaces).
LAB_ROOT="$RO_LAB" PATH="$EMPTY_PATH:/usr/bin:/bin" \
    bash "$SCRIPT" > "$OUT" 2>&1 || true

after="$(find "$RO_LAB" -type f -o -type d 2>/dev/null | sort)"
if [[ "$before" == "$after" ]]; then
    _record_pass "verify-host.sh is read-only: LAB_ROOT contents unchanged"
else
    _record_fail "verify-host.sh is read-only: LAB_ROOT contents unchanged" \
        "(modified)" "no changes under LAB_ROOT"
fi

# Workspaces dir must remain empty (no test workspaces created).
ws_count="$(find "$RO_LAB/workspaces" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$ws_count" "verify-host.sh: no workspaces created during run"

end_tests
