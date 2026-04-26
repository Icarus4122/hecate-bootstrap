#!/usr/bin/env bash
# tests/test_sync_binaries_checksum.sh - SHA256 verification path for
# scripts/sync-binaries.sh.  Exercises:
#   - verify_sha256(): match / mismatch / missing-file
#   - process_entry(): valid sha256 -> [PASS] checksum verified, dest promoted
#   - process_entry(): invalid sha256 -> [FAIL], dest absent, ERRORS++
#   - process_entry(): TODO_SHA256 in default mode -> [WARN], success
#   - process_entry(): TODO_SHA256 with STRICT_CHECKSUMS=1 -> [FAIL], no DL
#   - process_entry(): all-assets + real sha256 -> [FAIL] (per-asset NYI)
#
# All tests use a mocked curl (shell function) and the host's real
# sha256sum.  No network, no Docker.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "sync-binaries.sh checksum verification"

if ! command -v sha256sum &>/dev/null; then
    echo "# SKIP: sha256sum not available on this host"
    end_tests
    exit 0
fi
make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/sync-binaries.sh"

# Build a sourceable copy: just function defs + state vars (skip set -e, main, ui.sh source).
{
    sed -n '/^[a-z_][a-z0-9_]*() {/,/^}/p' "$SCRIPT"
    echo 'DRY_RUN=false; FILTER=""; ERRORS=0; SYNCED=0; SKIPPED=0'
    echo 'STRICT_CHECKSUMS=0'
    echo 'declare -A _release_cache'
    echo 'gh_curl_opts=(-fsSL)'
} > "$SANDBOX/sync-funcs.sh"

export LAB_ROOT="$SANDBOX/opt/lab"
BIN_DIR="$LAB_ROOT/tools/binaries"
REPO_DIR="$SANDBOX/repo"
mkdir -p "$BIN_DIR" "$REPO_DIR/manifests"

source "$_REAL_REPO/scripts/lib/ui.sh"
source "$SANDBOX/sync-funcs.sh"

_reset() {
    ERRORS=0; SYNCED=0; SKIPPED=0
    declare -gA _release_cache=()
}

# ═══════════════════════════════════════════════════════════════════
#  verify_sha256() - direct unit tests
# ═══════════════════════════════════════════════════════════════════
payload="$SANDBOX/payload.bin"
printf '\x1f\x8b\x08\x00hello-world' > "$payload"
expected="$(sha256sum "$payload" | awk '{print $1}')"

c=0
verify_sha256 "$payload" "$expected" > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "verify_sha256: matching digest -> rc=0"

c=0
verify_sha256 "$payload" "deadbeef$(printf 'a%.0s' {1..56})" > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "verify_sha256: mismatch -> rc=1"
assert_contains "$(cat "$OUT")" "[FAIL]" "verify_sha256: mismatch -> [FAIL] marker"
assert_contains "$(cat "$OUT")" "expected:" "verify_sha256: mismatch -> shows expected"
assert_contains "$(cat "$OUT")" "actual:" "verify_sha256: mismatch -> shows actual"

# ═══════════════════════════════════════════════════════════════════
#  process_entry() needs fetch_release JSON.  We pre-populate the
#  release cache so no curl call is ever made for the GH API.
# ═══════════════════════════════════════════════════════════════════
if command -v jq &>/dev/null; then
    HAS_JQ=1
else
    HAS_JQ=0
    echo "# SKIP: jq unavailable - skipping process_entry checksum cases"
fi

mock_release() {
    local repo="$1" tag="$2" asset="$3" url="$4" size="$5"
    _release_cache["${repo}@${tag}"]="$(cat <<EOF
{"assets":[{"name":"${asset}","browser_download_url":"${url}","size":${size}}]}
EOF
)"
}

# Mock curl: writes a known payload to -o <path>.  We capture the
# bytes so we can compute their sha256 once and feed it to the manifest.
PAYLOAD_BYTES='hecate-checksum-test-payload-v1'
ASSET_PATH="$SANDBOX/asset.bin"
printf '%s' "$PAYLOAD_BYTES" > "$ASSET_PATH"
ASSET_SIZE="$(wc -c < "$ASSET_PATH" | tr -d ' ')"
ASSET_SHA="$(sha256sum "$ASSET_PATH" | awk '{print $1}')"
WRONG_SHA="$(printf '0%.0s' {1..64})"

if [[ "$HAS_JQ" == "1" ]]; then

curl() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o) out="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    if [[ -n "$out" ]]; then
        printf '%s' "$PAYLOAD_BYTES" > "$out"
    fi
    return 0
}

# Override file(1) classification: process_entry's download_one() runs
# validate_download() which calls `file -b`.  Our payload is plain text
# and would be rejected.  Force-allow text downloads by setting flag.

# ═══════════════════════════════════════════════════════════════════
#  Case A: valid sha256 -> PASS, dest promoted
# ═══════════════════════════════════════════════════════════════════
_reset
mock_release "owner/repo" "v1" "asset.bin" "https://example/a" "$ASSET_SIZE"
DEST_DIR_A="$BIN_DIR/case_a"
rm -rf "$DEST_DIR_A"
process_entry "alpha" "github-release" "owner/repo" "v1" "asset.bin" "case_a" "allow-text" "$ASSET_SHA" > "$OUT" 2>&1
A_OUT="$(cat "$OUT")"
assert_eq "0" "$ERRORS" "valid sha256: ERRORS=0"
assert_eq "1" "$SYNCED" "valid sha256: SYNCED=1"
assert_file_exists "$DEST_DIR_A/asset.bin" "valid sha256: dest file promoted"
assert_contains "$A_OUT" "[PASS] checksum verified for asset.bin" "valid sha256: [PASS] checksum verified message"

# ═══════════════════════════════════════════════════════════════════
#  Case B: invalid sha256 -> FAIL, dest absent, ERRORS++
# ═══════════════════════════════════════════════════════════════════
_reset
mock_release "owner/repo" "v1" "asset.bin" "https://example/b" "$ASSET_SIZE"
DEST_DIR_B="$BIN_DIR/case_b"
rm -rf "$DEST_DIR_B"
process_entry "alpha" "github-release" "owner/repo" "v1" "asset.bin" "case_b" "allow-text" "$WRONG_SHA" > "$OUT" 2>&1
B_OUT="$(cat "$OUT")"
assert_eq "1" "$ERRORS" "invalid sha256: ERRORS=1"
assert_eq "0" "$SYNCED" "invalid sha256: SYNCED=0"
if [[ -e "$DEST_DIR_B/asset.bin" ]]; then
    _record_fail "invalid sha256: dest NOT promoted" "(present)" "absent"
else
    _record_pass "invalid sha256: dest NOT promoted"
fi
# No leftover .tmp files either.
shopt -s nullglob
leftover=( "$DEST_DIR_B"/*.tmp.* )
shopt -u nullglob
assert_eq "0" "${#leftover[@]}" "invalid sha256: no leftover .tmp file"
assert_contains "$B_OUT" "[FAIL] checksum mismatch" "invalid sha256: [FAIL] checksum mismatch"
assert_contains "$B_OUT" "$WRONG_SHA" "invalid sha256: shows expected hash"
assert_contains "$B_OUT" "$ASSET_SHA" "invalid sha256: shows actual hash"

# ═══════════════════════════════════════════════════════════════════
#  Case C: TODO_SHA256 in default mode -> WARN, success
# ═══════════════════════════════════════════════════════════════════
_reset
STRICT_CHECKSUMS=0
mock_release "owner/repo" "v1" "asset.bin" "https://example/c" "$ASSET_SIZE"
DEST_DIR_C="$BIN_DIR/case_c"
rm -rf "$DEST_DIR_C"
process_entry "alpha" "github-release" "owner/repo" "v1" "asset.bin" "case_c" "allow-text" "TODO_SHA256" > "$OUT" 2>&1
C_OUT="$(cat "$OUT")"
assert_eq "0" "$ERRORS" "TODO default: ERRORS=0"
assert_eq "1" "$SYNCED" "TODO default: SYNCED=1"
assert_file_exists "$DEST_DIR_C/asset.bin" "TODO default: dest promoted"
assert_contains "$C_OUT" "[WARN] checksum not pinned for asset.bin" "TODO default: [WARN] message"

# ═══════════════════════════════════════════════════════════════════
#  Case D: TODO_SHA256 with STRICT_CHECKSUMS=1 -> FAIL, no download
# ═══════════════════════════════════════════════════════════════════
_reset
STRICT_CHECKSUMS=1
mock_release "owner/repo" "v1" "asset.bin" "https://example/d" "$ASSET_SIZE"
DEST_DIR_D="$BIN_DIR/case_d"
rm -rf "$DEST_DIR_D"
process_entry "alpha" "github-release" "owner/repo" "v1" "asset.bin" "case_d" "allow-text" "TODO_SHA256" > "$OUT" 2>&1
D_OUT="$(cat "$OUT")"
assert_eq "1" "$ERRORS" "TODO strict: ERRORS=1"
assert_eq "0" "$SYNCED" "TODO strict: SYNCED=0"
if [[ -d "$DEST_DIR_D" ]]; then
    _record_fail "TODO strict: dest dir NOT created (no download attempted)" "(present)" "absent"
else
    _record_pass "TODO strict: dest dir NOT created (no download attempted)"
fi
assert_contains "$D_OUT" "[FAIL]" "TODO strict: [FAIL] marker"
assert_contains "$D_OUT" "checksum required for alpha under strict mode" \
    "TODO strict: explains strict-mode requirement"
STRICT_CHECKSUMS=0

# ═══════════════════════════════════════════════════════════════════
#  Case E: all-assets + real sha256 -> FAIL (per-asset NYI)
# ═══════════════════════════════════════════════════════════════════
_reset
DEST_DIR_E="$BIN_DIR/case_e"
rm -rf "$DEST_DIR_E"
process_entry "multi" "github-release" "owner/repo" "v1" "all-assets" "case_e" "-" "$ASSET_SHA" > "$OUT" 2>&1
E_OUT="$(cat "$OUT")"
assert_eq "1" "$ERRORS" "all-assets+real sha: ERRORS=1"
assert_contains "$E_OUT" "per-asset checksums not supported for mode=all-assets" \
    "all-assets+real sha: explains per-asset NYI"
if [[ -d "$DEST_DIR_E" ]]; then
    _record_fail "all-assets+real sha: dest dir NOT created" "(present)" "absent"
else
    _record_pass "all-assets+real sha: dest dir NOT created"
fi

unset -f curl

fi  # ── end HAS_JQ guard for process_entry cases A–E ──

# ═══════════════════════════════════════════════════════════════════
#  extract_gz_asset() unit tests + integrated .gz extraction path
# ═══════════════════════════════════════════════════════════════════
if command -v gunzip &>/dev/null && command -v gzip &>/dev/null; then

    # ── Direct unit: extract a known .gz, sibling produced + +x ────
    GZ_DIR="$SANDBOX/gz_unit"
    mkdir -p "$GZ_DIR"
    printf 'hecate-binary-payload-bytes\n' > "$GZ_DIR/asset_v1_linux_amd64"
    gzip -f "$GZ_DIR/asset_v1_linux_amd64"
    GZ_FILE="$GZ_DIR/asset_v1_linux_amd64.gz"
    OUT_FILE="$GZ_DIR/asset_v1_linux_amd64"
    rc=0
    extract_gz_asset "$GZ_FILE" > "$OUT" 2>&1 || rc=$?
    EX_OUT="$(cat "$OUT")"
    assert_eq "0" "$rc" "extract_gz_asset: rc=0 on valid .gz"
    assert_file_exists "$OUT_FILE" "extract_gz_asset: sibling produced"
    assert_file_exists "$GZ_FILE" "extract_gz_asset: original .gz preserved"
    assert_contains "$EX_OUT" "[PASS] extracted asset_v1_linux_amd64.gz -> asset_v1_linux_amd64" \
        "extract_gz_asset: [PASS] extracted line"
    assert_contains "$EX_OUT" "[PASS] marked executable asset_v1_linux_amd64" \
        "extract_gz_asset: [PASS] marked executable line"
    if [[ "$(uname -s)" == "Linux" ]]; then
        if [[ -x "$OUT_FILE" ]]; then
            _record_pass "extract_gz_asset: sibling has +x bit (Linux)"
        else
            _record_fail "extract_gz_asset: sibling has +x bit (Linux)" "(no +x)" "+x set"
        fi
    fi

    # ── Direct unit: corrupt .gz → FAIL, no partial sibling ────────
    BAD_DIR="$SANDBOX/gz_bad"
    mkdir -p "$BAD_DIR"
    BAD_GZ="$BAD_DIR/broken.bin.gz"
    printf 'this is not a gzip stream' > "$BAD_GZ"
    rm -f "$BAD_DIR/broken.bin"
    rc=0
    extract_gz_asset "$BAD_GZ" > "$OUT" 2>&1 || rc=$?
    BAD_OUT="$(cat "$OUT")"
    assert_eq "1" "$rc" "extract_gz_asset: rc=1 on corrupt .gz"
    assert_contains "$BAD_OUT" "[FAIL] decompression failed" \
        "extract_gz_asset: [FAIL] decompression failed"
    if [[ -e "$BAD_DIR/broken.bin" ]]; then
        _record_fail "extract_gz_asset: no partial sibling on failure" "(present)" "absent"
    else
        _record_pass "extract_gz_asset: no partial sibling on failure"
    fi

    # ── Direct unit: non-.gz input → FAIL ──────────────────────────
    rc=0
    extract_gz_asset "$payload" > "$OUT" 2>&1 || rc=$?
    assert_eq "1" "$rc" "extract_gz_asset: rc=1 on non-.gz path"
    assert_contains "$(cat "$OUT")" "called on non-.gz path" \
        "extract_gz_asset: explains non-.gz error"

    # ── Integrated: process_entry .gz asset → DL + verify + extract ─
    if command -v jq &>/dev/null; then
        GZ_PAYLOAD_DIR="$SANDBOX/gz_payload"
        mkdir -p "$GZ_PAYLOAD_DIR"
        printf 'integrated-extracted-payload\n' > "$GZ_PAYLOAD_DIR/tool_v1_linux_amd64"
        gzip -f "$GZ_PAYLOAD_DIR/tool_v1_linux_amd64"
        GZ_BYTES_PATH="$GZ_PAYLOAD_DIR/tool_v1_linux_amd64.gz"
        GZ_SIZE="$(wc -c < "$GZ_BYTES_PATH" | tr -d ' ')"
        GZ_SHA="$(sha256sum "$GZ_BYTES_PATH" | awk '{print $1}')"

        curl() {
            local out=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -o) out="$2"; shift 2 ;;
                    *)  shift ;;
                esac
            done
            [[ -n "$out" ]] && cp "$GZ_BYTES_PATH" "$out"
            return 0
        }

        _reset
        STRICT_CHECKSUMS=0
        mock_release "owner/repo" "v1" "tool_v1_linux_amd64.gz" \
            "https://example/gz" "$GZ_SIZE"
        DEST_DIR_F="$BIN_DIR/case_f"
        rm -rf "$DEST_DIR_F"
        process_entry "tool" "github-release" "owner/repo" "v1" \
            "tool_v1_linux_amd64.gz" "case_f" "-" "$GZ_SHA" > "$OUT" 2>&1
        F_OUT="$(cat "$OUT")"
        assert_eq "0" "$ERRORS" "integrated .gz: ERRORS=0"
        assert_eq "1" "$SYNCED" "integrated .gz: SYNCED=1"
        assert_file_exists "$DEST_DIR_F/tool_v1_linux_amd64.gz" \
            "integrated .gz: .gz preserved"
        assert_file_exists "$DEST_DIR_F/tool_v1_linux_amd64" \
            "integrated .gz: decompressed sibling exists"
        assert_contains "$F_OUT" "[PASS] checksum verified for tool_v1_linux_amd64.gz" \
            "integrated .gz: checksum verified"
        assert_contains "$F_OUT" "[PASS] extracted tool_v1_linux_amd64.gz -> tool_v1_linux_amd64" \
            "integrated .gz: extraction PASS"
        if [[ "$(uname -s)" == "Linux" ]]; then
            if [[ -x "$DEST_DIR_F/tool_v1_linux_amd64" ]]; then
                _record_pass "integrated .gz: sibling has +x (Linux)"
            else
                _record_fail "integrated .gz: sibling has +x (Linux)" "(no +x)" "+x set"
            fi
        fi

        # Integrated: checksum mismatch on .gz → no .gz, no sibling.
        _reset
        mock_release "owner/repo" "v1" "tool_v1_linux_amd64.gz" \
            "https://example/gz2" "$GZ_SIZE"
        DEST_DIR_G="$BIN_DIR/case_g"
        rm -rf "$DEST_DIR_G"
        process_entry "tool" "github-release" "owner/repo" "v1" \
            "tool_v1_linux_amd64.gz" "case_g" "-" "$WRONG_SHA" > "$OUT" 2>&1
        G_OUT="$(cat "$OUT")"
        assert_eq "1" "$ERRORS" "mismatch .gz: ERRORS=1"
        if [[ -e "$DEST_DIR_G/tool_v1_linux_amd64.gz" ]]; then
            _record_fail "mismatch .gz: .gz NOT promoted" "(present)" "absent"
        else
            _record_pass "mismatch .gz: .gz NOT promoted"
        fi
        if [[ -e "$DEST_DIR_G/tool_v1_linux_amd64" ]]; then
            _record_fail "mismatch .gz: sibling NOT created" "(present)" "absent"
        else
            _record_pass "mismatch .gz: sibling NOT created"
        fi
        assert_not_contains "$G_OUT" "extracted" \
            "mismatch .gz: no extraction performed"

        # Integrated: dry-run predicts extraction.
        _reset
        DRY_RUN=true
        mock_release "owner/repo" "v1" "tool_v1_linux_amd64.gz" \
            "https://example/gz3" "$GZ_SIZE"
        DEST_DIR_H="$BIN_DIR/case_h"
        rm -rf "$DEST_DIR_H"
        process_entry "tool" "github-release" "owner/repo" "v1" \
            "tool_v1_linux_amd64.gz" "case_h" "-" "$GZ_SHA" > "$OUT" 2>&1
        H_OUT="$(cat "$OUT")"
        DRY_RUN=false
        assert_contains "$H_OUT" "would extract tool_v1_linux_amd64.gz -> tool_v1_linux_amd64" \
            "dry-run .gz: predicts extraction target"
        if [[ -e "$DEST_DIR_H/tool_v1_linux_amd64" ]]; then
            _record_fail "dry-run .gz: sibling NOT created" "(present)" "absent"
        else
            _record_pass "dry-run .gz: sibling NOT created"
        fi

        # Integrated: non-.gz asset path unchanged (no extraction noise).
        _reset
        mock_release "owner/repo" "v1" "asset.bin" "https://example/plain" "$ASSET_SIZE"
        # Restore original mock curl for plain payload.
        curl() {
            local out=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -o) out="$2"; shift 2 ;;
                    *)  shift ;;
                esac
            done
            [[ -n "$out" ]] && printf '%s' "$PAYLOAD_BYTES" > "$out"
            return 0
        }
        DEST_DIR_I="$BIN_DIR/case_i"
        rm -rf "$DEST_DIR_I"
        process_entry "alpha" "github-release" "owner/repo" "v1" "asset.bin" \
            "case_i" "allow-text" "$ASSET_SHA" > "$OUT" 2>&1
        I_OUT="$(cat "$OUT")"
        assert_eq "0" "$ERRORS" "non-.gz: ERRORS=0 (unchanged behavior)"
        assert_eq "1" "$SYNCED" "non-.gz: SYNCED=1 (unchanged behavior)"
        assert_file_exists "$DEST_DIR_I/asset.bin" "non-.gz: dest promoted"
        assert_not_contains "$I_OUT" "extracted" "non-.gz: no extraction line"
        assert_not_contains "$I_OUT" "would extract" "non-.gz: no dry-run extraction line"

        unset -f curl
    fi
else
    echo "# SKIP: gunzip/gzip unavailable - skipping extract_gz_asset cases"
fi

# ═══════════════════════════════════════════════════════════════════
#  Script-level: --strict-checksums flag is parsed
# ═══════════════════════════════════════════════════════════════════
if command -v jq &>/dev/null; then
    SCRIPT_OUT="$SANDBOX/script.out"
    EMPTY_TSV="$SANDBOX/empty.tsv"
    printf 'name\ttype\trepo\ttag\tmode\tdest\tflags\tsha256\n' > "$EMPTY_TSV"
    sed "s|^MANIFEST=.*|MANIFEST=\"$EMPTY_TSV\"|" "$SCRIPT" > "$SANDBOX/sync-empty.sh"

    LAB_ROOT="$SANDBOX/strict-lab" \
        bash "$SANDBOX/sync-empty.sh" --strict-checksums --dry-run > "$SCRIPT_OUT" 2>&1 || true
    assert_contains "$(cat "$SCRIPT_OUT")" "STRICT_CHECKSUMS=1" \
        "script --strict-checksums: announces strict mode"

    # And --help mentions both --strict-checksums and STRICT_CHECKSUMS env.
    bash "$SANDBOX/sync-empty.sh" --help > "$SCRIPT_OUT" 2>&1 || true
    assert_contains "$(cat "$SCRIPT_OUT")" "--strict-checksums" \
        "script --help: documents --strict-checksums"
    assert_contains "$(cat "$SCRIPT_OUT")" "STRICT_CHECKSUMS" \
        "script --help: documents STRICT_CHECKSUMS env var"
else
    echo "# SKIP: jq unavailable - skipping script-level flag tests"
fi

end_tests
