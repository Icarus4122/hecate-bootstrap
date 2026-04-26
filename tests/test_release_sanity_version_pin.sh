#!/usr/bin/env bash
# tests/test_release_sanity_version_pin.sh
#
# Verifies the static cross-repo version pin enforced by
# scripts/dev/release-sanity.sh:
#
#   1. Matching Empusa version succeeds.
#   2. Mismatched pyproject.toml version fails.
#   3. Mismatched empusa/__init__.py version fails.
#   4. Missing Empusa CHANGELOG heading fails.
#   5. Missing Hecate-side contract reference fails.
#
# Uses temporary fixture directories. No Docker, no network,
# no Empusa install required. RELEASE_SANITY_VERSION_ONLY=1
# short-circuits the script after the static contract checks
# so we don't need ruff / pytest / Empusa runtime.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers.sh
source "$TESTS_DIR/helpers.sh"
begin_tests "release-sanity Empusa version pin"

REPO_DIR="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_DIR/scripts/dev/release-sanity.sh"
assert_file_exists "$SCRIPT" "release-sanity.sh present"

# Read the pinned version straight from the script so the test does
# not have to be edited in lockstep with version bumps.
EXPECTED=$(grep -E '^EXPECTED_EMPUSA_VERSION=' "$SCRIPT" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
assert_neq "" "$EXPECTED" "EXPECTED_EMPUSA_VERSION constant present"

make_sandbox

# ── fixture builders ─────────────────────────────────────────────
write_empusa_fixture() {
    local root="$1" pyproject_v="$2" init_v="$3" changelog_v="$4"
    mkdir -p "$root/empusa"
    cat > "$root/pyproject.toml" <<EOF
[project]
name = "empusa"
version = "${pyproject_v}"
EOF
    cat > "$root/empusa/__init__.py" <<EOF
__version__ = "${init_v}"
EOF
    if [[ -n "$changelog_v" ]]; then
        cat > "$root/CHANGELOG.md" <<EOF
# Changelog

## [${changelog_v}] - 2026-04-26
- placeholder
EOF
    else
        cat > "$root/CHANGELOG.md" <<'EOF'
# Changelog

## [0.0.0] - 1970-01-01
- placeholder
EOF
    fi
}

# Build a stub HECATE_DIR that mirrors the structure release-sanity
# probes: scripts/dev/release-sanity.sh + docs/dev/cross-repo-contract-audit.md
build_hecate_stub() {
    local hroot="$1" include_marker="$2"
    mkdir -p "$hroot/scripts/dev" "$hroot/docs/dev"
    cp "$SCRIPT" "$hroot/scripts/dev/release-sanity.sh"
    chmod +x "$hroot/scripts/dev/release-sanity.sh"
    if [[ "$include_marker" == "yes" ]]; then
        cat > "$hroot/docs/dev/cross-repo-contract-audit.md" <<EOF
# stub
**Expected Empusa contract version:** \`${EXPECTED}\`
EOF
    else
        cat > "$hroot/docs/dev/cross-repo-contract-audit.md" <<'EOF'
# stub
no contract pin here
EOF
    fi
}

# Run the script in version-only mode against the supplied fixtures.
# Captures combined stdout+stderr into $OUT and exit code into $RC.
# Must tolerate nonzero exits without tripping `set -e` from helpers.sh.
run_sanity() {
    local hroot="$1" empusa_root="$2"
    set +e
    OUT=$(RELEASE_SANITY_VERSION_ONLY=1 \
          bash "$hroot/scripts/dev/release-sanity.sh" "$empusa_root" 2>&1)
    RC=$?
    set -e
}

# ═══════════════════════════════════════════════════════════════════
#  1. Matching versions  →  exit 0  +  three [PASS] lines
# ═══════════════════════════════════════════════════════════════════
H1="$SANDBOX/h1"; E1="$SANDBOX/e1"
build_hecate_stub "$H1" "yes"
write_empusa_fixture "$E1" "$EXPECTED" "$EXPECTED" "$EXPECTED"
run_sanity "$H1" "$E1"
assert_exit_code "0" "$RC" "match: exit 0"
assert_contains "$OUT" "[PASS] Empusa pyproject.toml version = ${EXPECTED}" \
    "match: pyproject [PASS]"
assert_contains "$OUT" "[PASS] Empusa __init__.py __version__ = ${EXPECTED}" \
    "match: __init__ [PASS]"
assert_contains "$OUT" "[PASS] Empusa CHANGELOG.md has heading for ${EXPECTED}" \
    "match: CHANGELOG [PASS]"
assert_contains "$OUT" "[PASS] Hecate doc pins Empusa contract version ${EXPECTED}" \
    "match: Hecate doc [PASS]"

# ═══════════════════════════════════════════════════════════════════
#  2. Mismatched pyproject.toml  →  exit nonzero  +  [FAIL]
# ═══════════════════════════════════════════════════════════════════
H2="$SANDBOX/h2"; E2="$SANDBOX/e2"
build_hecate_stub "$H2" "yes"
write_empusa_fixture "$E2" "9.9.9" "$EXPECTED" "$EXPECTED"
run_sanity "$H2" "$E2"
assert_neq "0" "$RC" "pyproject mismatch: exit nonzero"
assert_contains "$OUT" "[FAIL] Empusa pyproject.toml version mismatch" \
    "pyproject mismatch: [FAIL] line"
assert_contains "$OUT" "expected: ${EXPECTED}" \
    "pyproject mismatch: expected printed"
assert_contains "$OUT" "actual:   9.9.9" \
    "pyproject mismatch: actual printed"

# ═══════════════════════════════════════════════════════════════════
#  3. Mismatched empusa/__init__.py  →  exit nonzero  +  [FAIL]
# ═══════════════════════════════════════════════════════════════════
H3="$SANDBOX/h3"; E3="$SANDBOX/e3"
build_hecate_stub "$H3" "yes"
write_empusa_fixture "$E3" "$EXPECTED" "8.8.8" "$EXPECTED"
run_sanity "$H3" "$E3"
assert_neq "0" "$RC" "__init__ mismatch: exit nonzero"
assert_contains "$OUT" "[FAIL] Empusa empusa/__init__.py __version__ mismatch" \
    "__init__ mismatch: [FAIL] line"
assert_contains "$OUT" "actual:   8.8.8" \
    "__init__ mismatch: actual printed"

# ═══════════════════════════════════════════════════════════════════
#  4. Missing Empusa CHANGELOG heading  →  exit nonzero  +  [FAIL]
# ═══════════════════════════════════════════════════════════════════
H4="$SANDBOX/h4"; E4="$SANDBOX/e4"
build_hecate_stub "$H4" "yes"
write_empusa_fixture "$E4" "$EXPECTED" "$EXPECTED" ""
run_sanity "$H4" "$E4"
assert_neq "0" "$RC" "missing changelog heading: exit nonzero"
assert_contains "$OUT" "[FAIL] Empusa CHANGELOG.md missing heading for ${EXPECTED}" \
    "missing changelog: [FAIL] line"

# ═══════════════════════════════════════════════════════════════════
#  5. Missing Hecate-side contract reference  →  exit nonzero  +  [FAIL]
# ═══════════════════════════════════════════════════════════════════
H5="$SANDBOX/h5"; E5="$SANDBOX/e5"
build_hecate_stub "$H5" "no"
write_empusa_fixture "$E5" "$EXPECTED" "$EXPECTED" "$EXPECTED"
run_sanity "$H5" "$E5"
assert_neq "0" "$RC" "missing Hecate marker: exit nonzero"
assert_contains "$OUT" "[FAIL] Hecate contract reference missing" \
    "missing Hecate marker: [FAIL] line"

end_tests
