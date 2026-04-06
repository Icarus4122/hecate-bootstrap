#!/usr/bin/env bash
# tests/test_labctl_ux.sh - Regression tests for labctl operator experience.
#
# Tests help text, dispatch errors, per-command help, and success/failure
# message structure.  All tests run against the real labctl file by sourcing
# it in a sandboxed environment with mocked docker.
#
# Strategy:
#   - Source labctl functions (strip main call + set -euo)
#   - Mock docker/_compose to prevent real container operations
#   - Assert on output patterns, not exact strings — avoids brittleness
#   - Validate structural properties: presence of sections, markers, commands
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "labctl UX regression"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
LABCTL="$_REAL_REPO/labctl"

# Build a sourceable version: strip set -euo, main "$@", and lib source
sed -e 's/^set -euo pipefail$//' \
    -e 's/^main "\$@"$//' \
    -e '/^source.*lib\/compose\.sh/d' \
    "$LABCTL" > "$SANDBOX/labctl-funcs.sh"

export LAB_ROOT="$SANDBOX/opt/lab"
export COMPOSE_PROJECT_NAME="lab"
mkdir -p "$LAB_ROOT"/{workspaces,tools/binaries}

# Source shared compose helper, then labctl functions.
source "$_REAL_REPO/scripts/lib/compose.sh"

# Override REPO_DIR before sourcing (the script computes it from BASH_SOURCE)
REPO_DIR="$_REAL_REPO"
SCRIPT_PATH="$LABCTL"
source "$SANDBOX/labctl-funcs.sh"
REPO_DIR="$_REAL_REPO"

# Mock docker to prevent real calls
docker() { echo "mock-docker $*" >> "$SANDBOX/docker.log"; return 0; }
export -f docker

# Mock _compose for subcommands that call it
_compose() { echo "mock-compose $*" >> "$SANDBOX/compose.log"; return 0; }

# ═══════════════════════════════════════════════════════════════════
#  1. Main help: structural sections
# ═══════════════════════════════════════════════════════════════════
help_out="$(cmd_help 2>&1)"

assert_contains "$help_out" "GETTING STARTED" \
    "help: has GETTING STARTED section"

assert_contains "$help_out" "DAILY WORKFLOW" \
    "help: has DAILY WORKFLOW section"

assert_contains "$help_out" "COMMANDS" \
    "help: has COMMANDS section"

assert_contains "$help_out" "EXAMPLES" \
    "help: has EXAMPLES section"

assert_contains "$help_out" "TROUBLESHOOTING" \
    "help: has TROUBLESHOOTING section"

assert_contains "$help_out" "ENVIRONMENT" \
    "help: has ENVIRONMENT section"

# ═══════════════════════════════════════════════════════════════════
#  2. Main help: critical commands listed
# ═══════════════════════════════════════════════════════════════════
for cmd in up down build shell launch workspace sync status verify \
           update bootstrap guide version help; do
    assert_contains "$help_out" "$cmd" \
        "help: lists command '${cmd}'"
done

# ═══════════════════════════════════════════════════════════════════
#  3. Main help: EXAMPLES section has copy-pasteable commands
# ═══════════════════════════════════════════════════════════════════
assert_contains "$help_out" "labctl launch htb" \
    "help examples: htb launch"

assert_contains "$help_out" "labctl up --gpu" \
    "help examples: gpu flag"

assert_contains "$help_out" "labctl sync" \
    "help examples: sync command"

assert_contains "$help_out" "labctl workspace" \
    "help examples: workspace command"

# ═══════════════════════════════════════════════════════════════════
#  4. Per-command help: every dispatch target has a help function
# ═══════════════════════════════════════════════════════════════════
for cmd in up down build launch workspace sync tmux status verify \
           update bootstrap clean version guide; do
    fn="cmd_help_${cmd}"
    if declare -f "$fn" &>/dev/null; then
        out="$("$fn" 2>&1)"
        # Each per-command help must contain the command name
        assert_contains "$out" "labctl $cmd" \
            "help ${cmd}: contains 'labctl ${cmd}'"
    else
        _record_fail "help ${cmd}: cmd_help_${cmd} function exists" "missing" "defined"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  5. Per-command help: commands with examples have Examples: section
# ═══════════════════════════════════════════════════════════════════
for cmd in up build launch workspace sync verify update guide clean tmux status; do
    fn="cmd_help_${cmd}"
    out="$("$fn" 2>&1)"
    # Accept "Example", "Examples", or "Common patterns" as the examples heading
    if echo "$out" | grep -qiE 'Example|Common patterns'; then
        _record_pass "help ${cmd}: has Examples section"
    else
        _record_fail "help ${cmd}: has Examples section" \
            "(no Examples/Common patterns heading)" "Example or Common patterns"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  6. Dispatch: unknown command -> exit 1 + help pointer
# ═══════════════════════════════════════════════════════════════════
rc=0
out="$(main "nonexistent-cmd" 2>&1)" || rc=$?
assert_eq "1" "$rc" "dispatch: unknown command -> exit 1"
assert_contains "$out" "Unknown command" \
    "dispatch: error says 'Unknown command'"
assert_contains "$out" "labctl help" \
    "dispatch: error points to 'labctl help'"

# ═══════════════════════════════════════════════════════════════════
#  7. cmd_up: unknown flag -> exit 1 + help pointer
# ═══════════════════════════════════════════════════════════════════
# cmd_up checks for .env before parsing flags — use a sandbox REPO_DIR
# with .env present so we actually reach the flag-validation code path.
saved_repo="$REPO_DIR"
REPO_DIR="$SANDBOX/flag-repo"
mkdir -p "$REPO_DIR"
touch "$REPO_DIR/.env"
rc=0
out="$(cmd_up --bogus 2>&1)" || rc=$?
REPO_DIR="$saved_repo"
assert_eq "1" "$rc" "up: unknown flag -> exit 1"
assert_contains "$out" "Unknown flag" \
    "up: error says 'Unknown flag'"
assert_contains "$out" "labctl help up" \
    "up: error points to help"

# ═══════════════════════════════════════════════════════════════════
#  8. cmd_up: missing LAB_ROOT -> exit 1 + bootstrap hint
# ═══════════════════════════════════════════════════════════════════
saved_lab="$LAB_ROOT"
export LAB_ROOT="$SANDBOX/nonexistent"
rc=0
out="$(cmd_up 2>&1)" || rc=$?
assert_eq "1" "$rc" "up: missing LAB_ROOT -> exit 1"
assert_contains "$out" "[✗]" \
    "up: missing LAB_ROOT -> [✗] marker"
assert_contains "$out" "bootstrap" \
    "up: missing LAB_ROOT -> mentions bootstrap"
export LAB_ROOT="$saved_lab"

# ═══════════════════════════════════════════════════════════════════
#  9. cmd_up: missing .env -> exit 1 + copy hint
# ═══════════════════════════════════════════════════════════════════
saved_repo="$REPO_DIR"
REPO_DIR="$SANDBOX/empty-repo"
mkdir -p "$REPO_DIR"
rc=0
out="$(cmd_up 2>&1)" || rc=$?
assert_eq "1" "$rc" "up: missing .env -> exit 1"
assert_contains "$out" ".env" \
    "up: missing .env -> mentions .env"
assert_contains "$out" ".env.example" \
    "up: missing .env -> mentions .env.example"
REPO_DIR="$saved_repo"

# ═══════════════════════════════════════════════════════════════════
#  10. Success messages: consistent "Next:" phrasing
# ═══════════════════════════════════════════════════════════════════

# cmd_up success (mock _compose to succeed + create .env in sandbox)
saved_repo="$REPO_DIR"
REPO_DIR="$SANDBOX/success-repo"
mkdir -p "$REPO_DIR"
touch "$REPO_DIR/.env"
_compose() { return 0; }
out="$(cmd_up 2>&1)"
assert_contains "$out" "[✓]" "up success: has [✓] marker"
assert_contains "$out" "Next:" "up success: has 'Next:' pointer"

# cmd_build success
out="$(cmd_build 2>&1)"
assert_contains "$out" "[✓]" "build success: has [✓] marker"
assert_contains "$out" "Next:" "build success: has 'Next:' pointer"

# cmd_down success
out="$(cmd_down 2>&1)"
assert_contains "$out" "[✓]" "down success: has [✓] marker"
assert_contains "$out" "intact" "down success: mentions data intact"
REPO_DIR="$saved_repo"

# ═══════════════════════════════════════════════════════════════════
#  11. Failure messages: consistent [✗] + remediation
# ═══════════════════════════════════════════════════════════════════

# cmd_build failure
_compose() {
    [[ "$1" == "build" ]] && return 1
    return 0
}
rc=0
out="$(cmd_build 2>&1)" || rc=$?
assert_eq "1" "$rc" "build fail: exit 1"
assert_contains "$out" "[✗]" "build fail: has [✗] marker"
# Must suggest at least one remediation
assert_match "$out" "labctl|rebuild|Dockerfile" \
    "build fail: suggests remediation"

# cmd_shell failure (container not running)
_compose() { return 1; }
rc=0
out="$(cmd_shell 2>&1)" || rc=$?
assert_eq "1" "$rc" "shell fail: exit 1"
assert_contains "$out" "[✗]" "shell fail: has [✗] marker"
assert_contains "$out" "labctl" \
    "shell fail: suggests a labctl command"

# ═══════════════════════════════════════════════════════════════════
#  12. cmd_bootstrap: non-root -> exit 1 + sudo hint
# ═══════════════════════════════════════════════════════════════════
if [[ "$(id -u)" -ne 0 ]]; then
    rc=0
    out="$(cmd_bootstrap 2>&1)" || rc=$?
    assert_eq "1" "$rc" "bootstrap: non-root -> exit 1"
    assert_contains "$out" "sudo" \
        "bootstrap: non-root -> mentions sudo"
fi

# ═══════════════════════════════════════════════════════════════════
#  13. labctl help <topic>: nonexistent topic -> exit 1
# ═══════════════════════════════════════════════════════════════════
rc=0
out="$(cmd_help "nonexistent" 2>&1)" || rc=$?
assert_eq "1" "$rc" "help: bad topic -> exit 1"
assert_contains "$out" "No help entry" \
    "help: bad topic -> says 'No help entry'"
assert_contains "$out" "labctl help" \
    "help: bad topic -> points to 'labctl help'"

# ═══════════════════════════════════════════════════════════════════
#  14. -h/--help aliases work
# ═══════════════════════════════════════════════════════════════════
out="$(main -h 2>&1)"
assert_contains "$out" "COMMANDS" \
    "-h alias: shows help"

out="$(main --help 2>&1)"
assert_contains "$out" "COMMANDS" \
    "--help alias: shows help"

end_tests
