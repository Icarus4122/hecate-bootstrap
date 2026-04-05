#!/usr/bin/env bash
# tests/helpers.sh - Minimal TAP-style test harness for hecate-bootstrap scripts.
#
# Source this file in each test script.  Usage:
#
#   #!/usr/bin/env bash
#   source "$(dirname "$0")/helpers.sh"
#   begin_tests "my test group"
#   assert_eq "expected" "actual" "test label"
#   end_tests
#
# Output conforms to TAP (Test Anything Protocol) enough for humans
# and simple CI parsers.  No external dependencies beyond bash ≥ 4.
set -euo pipefail

# ── Test state ─────────────────────────────────────────────────────
_T_COUNT=0
_T_PASS=0
_T_FAIL=0
_T_NAME=""

# ── Sandbox helpers ────────────────────────────────────────────────
# Create a temp directory that is auto-cleaned on EXIT.
# Call WITHOUT command substitution:   make_sandbox
# Result is stored in the global $SANDBOX variable.
SANDBOX=""
make_sandbox() {
    SANDBOX="$(mktemp -d)"
    # Cleanup trap registered in the CALLER's shell, not a subshell.
    trap 'rm -rf "$SANDBOX"' EXIT
}

# ── Assertions ─────────────────────────────────────────────────────
begin_tests() {
    _T_NAME="${1:-tests}"
    echo "# ── ${_T_NAME} ──"
}

_record_pass() {
    _T_COUNT=$((_T_COUNT + 1))
    _T_PASS=$((_T_PASS + 1))
    echo "ok ${_T_COUNT} - $1"
}

_record_fail() {
    _T_COUNT=$((_T_COUNT + 1))
    _T_FAIL=$((_T_FAIL + 1))
    echo "not ok ${_T_COUNT} - $1"
    if [[ -n "${2:-}" ]]; then
        echo "#   got:      ${2}"
    fi
    if [[ -n "${3:-}" ]]; then
        echo "#   expected: ${3}"
    fi
}

assert_eq() {
    local expected="$1" actual="$2" label="${3:-assert_eq}"
    if [[ "$expected" == "$actual" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$actual" "$expected"
    fi
}

assert_neq() {
    local unexpected="$1" actual="$2" label="${3:-assert_neq}"
    if [[ "$unexpected" != "$actual" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$actual" "anything except ${unexpected}"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="${3:-assert_contains}"
    if [[ "$haystack" == *"$needle"* ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "(output does not contain '${needle}')" "'${needle}' in output"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="${3:-assert_not_contains}"
    if [[ "$haystack" != *"$needle"* ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "(output unexpectedly contains '${needle}')" "'${needle}' absent"
    fi
}

assert_match() {
    local text="$1" pattern="$2" label="${3:-assert_match}"
    if [[ "$text" =~ $pattern ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$text" "match /${pattern}/"
    fi
}

assert_file_exists() {
    local path="$1" label="${2:-file exists: $1}"
    if [[ -f "$path" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "(missing)" "$path"
    fi
}

assert_dir_exists() {
    local path="$1" label="${2:-dir exists: $1}"
    if [[ -d "$path" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "(missing)" "$path"
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" label="${3:-exit code}"
    if [[ "$expected" == "$actual" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "exit=$actual" "exit=$expected"
    fi
}

# Assert that output contains ALL listed substrings (space-safe: one per arg).
assert_contains_all() {
    local haystack="$1"; shift
    local label="${1:-assert_contains_all}"; shift
    local missing=()
    for needle in "$@"; do
        [[ "$haystack" == *"$needle"* ]] || missing+=("$needle")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "missing: ${missing[*]}" "all present"
    fi
}

# Assert that a multi-line string contains a line matching a regex.
assert_line_match() {
    local text="$1" pattern="$2" label="${3:-assert_line_match}"
    while IFS= read -r line; do
        if [[ "$line" =~ $pattern ]]; then
            _record_pass "$label"
            return
        fi
    done <<< "$text"
    _record_fail "$label" "(no line matches /${pattern}/)" "at least one match"
}

# ── Summary ────────────────────────────────────────────────────────
end_tests() {
    echo ""
    echo "1..${_T_COUNT}"
    echo "# ${_T_NAME}: ${_T_PASS} passed, ${_T_FAIL} failed (of ${_T_COUNT})"

    if [[ $_T_FAIL -gt 0 ]]; then
        return 1
    fi
    return 0
}
