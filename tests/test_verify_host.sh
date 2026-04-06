#!/usr/bin/env bash
# tests/test_veify_host.sh - Tests for scripts/verify-host.sh logic.
#
# Stategy: source the script's helper functions into a sandboxed
# environment with mocked commands, then exercise each check_*
# function individually.  We redirect output to files (not subshells)
# so global counter updates are preserved.
#
# We do NOT test actual Docker, GPU, o OS - those are integration
# concerns.  We test the branching logic and output classification.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "verify-host.sh logic"

# ── Setup: extact functions from the script ───────────────────────
make_sandbox
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/verify-host.sh"

# Build a sourceable version: strip main invocation so soucing
# only defines functions and variables.
_build_sourceable() {
    sed -e 's/^set -euo pipefail$//' \
        -e 's/^main "\$@"$//' \
        -e '/^source.*lib\/ui\.sh/d' \
        "$SCRIPT" > "$SANDBOX/verify-funcs.sh"
}
_build_sourceable

# Set LAB_ROOT BEFORE sourcing - the script expects ${LAB_ROOT:-...}
export LAB_ROOT="$SANDBOX/opt/lab"

# Source ui.sh from the real repo, then the verify functions.
source "$_REAL_REPO/scripts/lib/ui.sh"
source "$SANDBOX/verify-funcs.sh"

# Override REPO_DIR to our sandbox mock (the source set it to sandbox paent)
REPO_DIR="$SANDBOX/repo"
mkdir -p "$REPO_DIR"

# Captue file used for ediecting function output
OUT="$SANDBOX/out.txt"

# Reset counters between tests
_reset() { PASS=0; WARN=0; FAIL=0; FAIL_LOG=(); WARN_LOG=(); }

# ═══════════════════════════════════════════════════════════════════
#  Output helpers: _pass / _warn / _fail
#  (run in current shell via redirect, NOT subshell)
# ═══════════════════════════════════════════════════════════════════
_reset
_pass "something works" > "$OUT" 2>&1
assert_eq "1" "$PASS" "_pass increments PASS counter"
assert_contains "$(cat "$OUT")" "[PASS]" "_pass prints [PASS] tag"

_reset
_warn "something suspicious" > "$OUT" 2>&1
assert_eq "1" "$WARN" "_warn increments WARN counter"
assert_contains "$(cat "$OUT")" "[WARN]" "_warn prints [WARN] tag"

_reset
_fail "something boke" > "$OUT" 2>&1
assert_eq "1" "$FAIL" "_fail increments FAIL counter"
assert_contains "$(cat "$OUT")" "[FAIL]" "_fail prints [FAIL] tag"

# ═══════════════════════════════════════════════════════════════════
#  check_lab_layout - directory tree verification
# ═══════════════════════════════════════════════════════════════════

# Case 1: LAB_ROOT does not exist
_reset
check_lab_layout > "$OUT" 2>&1
assert_eq "1" "$FAIL" "lab_layout: missing LAB_ROOT -> FAIL"
assert_contains "$(cat "$OUT")" "does not exist" "lab_layout: reports LAB_ROOT missing"

# Case 2: LAB_ROOT exists with all required dirs
_reset
mkdir -p "$LAB_ROOT"/{data,tools/{binaries,git,venvs},resources,workspaces,knowledge,templates}
check_lab_layout > "$OUT" 2>&1
assert_eq "0" "$FAIL" "lab_layout: complete tree -> no FAILs"
# 1 for LAB_ROOT exists + 9 for each required dir = 10 PASSes
assert_eq "10" "$PASS" "lab_layout: complete tree -> 10 PASSes"

# Case 3: LAB_ROOT exists but some dirs missing
_reset
rm -rf "$LAB_ROOT/knowledge" "$LAB_ROOT/templates"
check_lab_layout > "$OUT" 2>&1
assert_eq "2" "$FAIL" "lab_layout: 2 dirs removed -> 2 FAILs"
assert_eq "8" "$PASS" "lab_layout: 2 dirs removed -> 8 PASSes"

# Restore for later tests
mkdir -p "$LAB_ROOT"/{knowledge,templates}

# ═══════════════════════════════════════════════════════════════════
#  check_repo_files - repository file presence
# ═══════════════════════════════════════════════════════════════════

# Case 1: no repo files at all
_reset
check_repo_files > "$OUT" 2>&1
assert_match "$FAIL" "^[1-9]" "epo_files: missing files -> FAILs"

# Case 2: all required repo files present
_reset
mkdir -p "$REPO_DIR"/{compose,docker/{kali-main,builder},manifests,tmux/profiles}
touch "$REPO_DIR/compose/docker-compose.yml"
touch "$REPO_DIR/compose/docker-compose.gpu.yml"
touch "$REPO_DIR/compose/docker-compose.hostnet.yml"
touch "$REPO_DIR/docker/kali-main/Dockerfile"
touch "$REPO_DIR/docker/builder/Dockerfile"
touch "$REPO_DIR/manifests/binaries.tsv"
echo '#!/bin/bash' > "$REPO_DIR/tmux/profiles/default.sh"
check_repo_files > "$OUT" 2>&1
assert_eq "0" "$FAIL" "epo_files: all present -> no FAILs"

# ═══════════════════════════════════════════════════════════════════
#  check_empusa - binary presence
# ═══════════════════════════════════════════════════════════════════

# Case 1: empusa not installed
_reset
check_empusa > "$OUT" 2>&1
assert_eq "0" "$FAIL" "empusa: missing -> WARN not FAIL"
assert_eq "1" "$WARN" "empusa: missing -> 1 WARN"

# Case 2: empusa binary exists and is executable
_reset
empusa_bin="$LAB_ROOT/tools/venvs/empusa/bin/empusa"
mkdir -p "$(dirname "$empusa_bin")"
cat > "$empusa_bin" <<'STUB'
#!/bin/bash
echo "empusa 2.2.0"
STUB
chmod +x "$empusa_bin"
check_empusa > "$OUT" 2>&1
assert_eq "1" "$PASS" "empusa: present + executable -> PASS"
assert_eq "0" "$FAIL" "empusa: present + executable -> no FAIL"
assert_contains "$(cat "$OUT")" "empusa installed" "empusa: output says installed"

# ═══════════════════════════════════════════════════════════════════
#  print_summary - output and exit-code logic
# ═══════════════════════════════════════════════════════════════════

# Summary with failures
FAIL=3; PASS=5; WARN=1; FAIL_LOG=("item A" "item B" "item C")
print_summary > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "5 passed" "summary: shows pass count"
assert_contains "$(cat "$OUT")" "3 failed" "summary: shows fail count"
assert_contains "$(cat "$OUT")" "1 warnings" "summary: shows warn count"
assert_contains "$(cat "$OUT")" "NOT ready" "summary: failures -> NOT ready"
assert_contains "$(cat "$OUT")" "Failed checks" "summary: reprints failed items header"

# Summary with only warnings
FAIL=0; PASS=5; WARN=2; FAIL_LOG=()
print_summary > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "usable but has warnings" "summary: warns-only text"

# Summary all clear
FAIL=0; PASS=5; WARN=0; FAIL_LOG=()
print_summary > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "Host is ready" "summary: all-clear text"

end_tests
