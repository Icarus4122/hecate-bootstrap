#!/usr/bin/env bash
# tests/test_release_sanity_strict_checksum.sh
#
# Verifies the strict binary-checksum gate added to
# scripts/dev/release-sanity.sh:
#
#   1. Manifest with all-real-hex sha256 → gate passes.
#   2. Manifest with TODO_SHA256 row    → [FAIL] precise reason.
#   3. Manifest with all-assets+TODO    → [FAIL] all-assets reason.
#   4. Manifest with malformed sha256   → [FAIL] malformed reason.
#   5. RELEASE_SANITY_SKIP_CHECKSUMS=1  → [WARN] and skip.
#   6. RELEASE_SANITY_VERSION_ONLY=1    → bypass entirely (no checksum lines).
#
# No Docker, no network, no Empusa install required.  Empusa is mocked
# so the script's static contract checks pass before reaching the
# strict-checksum gate.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers.sh
source "$TESTS_DIR/helpers.sh"
begin_tests "release-sanity strict checksum gate"

REPO_DIR="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_DIR/scripts/dev/release-sanity.sh"
assert_file_exists "$SCRIPT" "release-sanity.sh present"

EXPECTED=$(grep -E '^EXPECTED_EMPUSA_VERSION=' "$SCRIPT" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

make_sandbox

write_empusa_fixture() {
    local root="$1" v="$2"
    mkdir -p "$root/empusa"
    cat > "$root/pyproject.toml" <<EOF
[project]
name = "empusa"
version = "${v}"
EOF
    cat > "$root/empusa/__init__.py" <<EOF
__version__ = "${v}"
EOF
    cat > "$root/CHANGELOG.md" <<EOF
# Changelog

## [${v}] - 2026-04-26
- placeholder
EOF
}

build_hecate_stub() {
    local hroot="$1" manifest_body="$2"
    mkdir -p "$hroot/scripts/dev" "$hroot/docs/dev" "$hroot/manifests" "$hroot/tests"
    cp "$SCRIPT" "$hroot/scripts/dev/release-sanity.sh"
    chmod +x "$hroot/scripts/dev/release-sanity.sh"
    cat > "$hroot/docs/dev/cross-repo-contract-audit.md" <<EOF
# stub
**Expected Empusa contract version:** \`${EXPECTED}\`
EOF
    # Preserve the literal tabs in the manifest body
    printf '%s' "$manifest_body" > "$hroot/manifests/binaries.tsv"
    # tests/run-all.sh exists so non-version-only path can complete the
    # earlier `cd "$EMPUSA_DIR"` flow even though we exit before it.
    cp "$REPO_DIR/tests/run-all.sh" "$hroot/tests/run-all.sh"
}

run_strict() {
    local hroot="$1" empusa_root="$2"
    local extra_env="${3:-}"
    set +e
    OUT=$(env -i PATH="$PATH" HOME="$HOME" \
          RELEASE_SANITY_SKIP_CHECKSUMS="${RELEASE_SANITY_SKIP_CHECKSUMS:-0}" \
          RELEASE_SANITY_VERSION_ONLY="${RELEASE_SANITY_VERSION_ONLY:-0}" \
          $extra_env \
          bash "$hroot/scripts/dev/release-sanity.sh" "$empusa_root" 2>&1)
    RC=$?
    set -e
}

# Real 64-hex sha256 (from `printf '' | sha256sum` modified — never used,
# manifest validation only checks the format pattern, not the actual file).
GOOD_HEX="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

TAB=$'\t'
HEADER="name${TAB}type${TAB}repo${TAB}tag${TAB}mode${TAB}dest${TAB}flags${TAB}sha256"

# ── 1. all-pinned manifest → strict gate PASS, but full sanity will
#     still continue past us; we only assert the gate output. ───────
H1="$SANDBOX/h1"; E1="$SANDBOX/e1"
PINNED_TSV="$HEADER"$'\n'"toolA${TAB}github-release${TAB}o/r${TAB}v1${TAB}toolA_linux${TAB}toolA${TAB}executable${TAB}${GOOD_HEX}"$'\n'
build_hecate_stub "$H1" "$PINNED_TSV"
write_empusa_fixture "$E1" "$EXPECTED"
# Force script to exit at gate by skipping post-gate work.  The simplest
# way: manifest fully-pinned then have the rest of the script fail out
# (Empusa lacks venv/ruff/pytest) — that's fine, we only assert the gate
# lines.  Capture combined output, ignore RC after asserting gate text.
run_strict "$H1" "$E1"
assert_contains "$OUT" "[PASS] toolA: sha256 pinned" "all-pinned: per-row PASS"
assert_contains "$OUT" "[PASS] All 1 active binary row(s) pass strict checksum gate" \
    "all-pinned: gate PASS summary"

# ── 2. TODO_SHA256 row → strict gate FAIL with precise reason ─────
H2="$SANDBOX/h2"; E2="$SANDBOX/e2"
TODO_TSV="$HEADER"$'\n'"toolB${TAB}github-release${TAB}o/r${TAB}v1${TAB}toolB_linux${TAB}toolB${TAB}executable${TAB}TODO_SHA256"$'\n'
build_hecate_stub "$H2" "$TODO_TSV"
write_empusa_fixture "$E2" "$EXPECTED"
run_strict "$H2" "$E2"
assert_neq "0" "$RC" "TODO_SHA256: nonzero exit"
assert_contains "$OUT" "[FAIL] toolB: TODO_SHA256 (unpinned)" \
    "TODO_SHA256: per-row FAIL"
assert_contains "$OUT" "1/1 binary rows fail strict checksum gate" \
    "TODO_SHA256: gate FAIL summary"

# ── 3. all-assets + TODO_SHA256 → all-assets-specific FAIL reason ─
H3="$SANDBOX/h3"; E3="$SANDBOX/e3"
AA_TSV="$HEADER"$'\n'"toolC${TAB}github-release${TAB}o/r${TAB}v1${TAB}all-assets${TAB}toolC/v1${TAB}-${TAB}TODO_SHA256"$'\n'
build_hecate_stub "$H3" "$AA_TSV"
write_empusa_fixture "$E3" "$EXPECTED"
run_strict "$H3" "$E3"
assert_neq "0" "$RC" "all-assets TODO: nonzero exit"
assert_contains "$OUT" "[FAIL] toolC: mode=all-assets cannot be strictly pinned" \
    "all-assets TODO: precise reason"
assert_contains "$OUT" "Per-asset checksums are not supported for all-assets rows" \
    "all-assets TODO: explanatory help"

# ── 4. Malformed sha256 → malformed FAIL reason ───────────────────
H4="$SANDBOX/h4"; E4="$SANDBOX/e4"
BAD_TSV="$HEADER"$'\n'"toolD${TAB}github-release${TAB}o/r${TAB}v1${TAB}toolD_linux${TAB}toolD${TAB}executable${TAB}NOT-A-HASH"$'\n'
build_hecate_stub "$H4" "$BAD_TSV"
write_empusa_fixture "$E4" "$EXPECTED"
run_strict "$H4" "$E4"
assert_neq "0" "$RC" "malformed: nonzero exit"
assert_contains "$OUT" "[FAIL] toolD: malformed sha256" \
    "malformed: per-row FAIL"

# ── 5. RELEASE_SANITY_SKIP_CHECKSUMS=1 → [WARN] skip line ─────────
H5="$SANDBOX/h5"; E5="$SANDBOX/e5"
build_hecate_stub "$H5" "$TODO_TSV"
write_empusa_fixture "$E5" "$EXPECTED"
RELEASE_SANITY_SKIP_CHECKSUMS=1 run_strict "$H5" "$E5"
assert_contains "$OUT" "[WARN] Strict checksum gate skipped" \
    "skip env: WARN line emitted"
assert_not_contains "$OUT" "[FAIL] toolB: TODO_SHA256" \
    "skip env: per-row FAIL not emitted"

# ── 6. RELEASE_SANITY_VERSION_ONLY=1 → no checksum gate output ────
H6="$SANDBOX/h6"; E6="$SANDBOX/e6"
build_hecate_stub "$H6" "$TODO_TSV"
write_empusa_fixture "$E6" "$EXPECTED"
RELEASE_SANITY_VERSION_ONLY=1 run_strict "$H6" "$E6"
assert_exit_code "0" "$RC" "version-only: exit 0"
assert_not_contains "$OUT" "Strict binary checksum gate" \
    "version-only: gate header NOT printed"
assert_contains "$OUT" "Version-only mode: contract checks passed" \
    "version-only: contract message present"

end_tests
