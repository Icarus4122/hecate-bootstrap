#!/usr/bin/env bash
# tests/test_sync_binaries_download.sh - Negative-path and promotion
# tests for sync-binaries.sh download_one() + dry-run / filter logic.
#
# We mock curl as a shell function so no network access happens.
# Existing test_sync_binaries.sh covers validate_download() classification;
# this file fills in: temp-file promotion, failure cleanup, dry-run gate,
# filter selection, and BIN_DIR creation.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "sync-binaries.sh download/promotion"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/sync-binaries.sh"

# ── Build a sourceable copy: just function defs + state vars ───────
{
    sed -n '/^[a-z_]*() {/,/^}/p' "$SCRIPT"
    echo 'DRY_RUN=false; FILTER=""; ERRORS=0; SYNCED=0; SKIPPED=0'
    echo 'declare -A _release_cache'
    echo 'gh_curl_opts=(-fsSL)'
} > "$SANDBOX/sync-funcs.sh"

export LAB_ROOT="$SANDBOX/opt/lab"
BIN_DIR="$LAB_ROOT/tools/binaries"
REPO_DIR="$SANDBOX/repo"
mkdir -p "$BIN_DIR" "$REPO_DIR/manifests"

source "$_REAL_REPO/scripts/lib/ui.sh"
source "$SANDBOX/sync-funcs.sh"

# ═══════════════════════════════════════════════════════════════════
#  download_one - successful path: temp file is promoted
# ═══════════════════════════════════════════════════════════════════
# Mock curl: write a 4-byte gzip magic header to the -o destination.
curl() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o) out="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    [[ -n "$out" ]] && printf '\x1f\x8b\x08\x00extra' > "$out"
    return 0
}

dest_dir="$BIN_DIR/test1"
mkdir -p "$dest_dir"
dest="$dest_dir/payload.gz"
rm -f "$dest"
c=0
download_one "https://example/a" "$dest" "false" "false" > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "download_one: success -> rc=0"
assert_file_exists "$dest" "download_one: dest file promoted"

# No leftover .tmp.* file in the dest dir
shopt -s nullglob
leftover=( "$dest_dir"/*.tmp.* )
shopt -u nullglob
assert_eq "0" "${#leftover[@]}" "download_one: success -> no leftover .tmp file"

# make_exec=true -> file must be executable.  On Git-Bash/NTFS the
# executable bit is not always honored; gate on a real Linux fs.
if [[ "$OSTYPE" != msys* && "$OSTYPE" != cygwin* ]]; then
    dest2="$dest_dir/payload.gz.x"
    download_one "https://example/b" "$dest2" "false" "true" > "$OUT" 2>&1
    if [[ -x "$dest2" ]]; then
        _record_pass "download_one: make_exec=true -> dest is executable"
    else
        _record_fail "download_one: make_exec=true -> dest is executable" "(not +x)" "executable"
    fi
else
    echo "# SKIP: make_exec executable-bit assertion (msys/cygwin fs)"
fi

# ═══════════════════════════════════════════════════════════════════
#  download_one - validation failure: temp NOT promoted, exit 1
# ═══════════════════════════════════════════════════════════════════
# Mock curl to write an HTML body (will be rejected by validate_download).
curl() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o) out="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    [[ -n "$out" ]] && echo '<!DOCTYPE html><html><body>404</body></html>' > "$out"
    return 0
}

dest3="$dest_dir/should-not-exist.bin"
rm -f "$dest3"
c=0
download_one "https://example/html" "$dest3" "false" "false" > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "download_one: HTML response -> rc=1 (rejected)"
if [[ -e "$dest3" ]]; then
    _record_fail "download_one: validation fail -> dest NOT promoted" "(present)" "absent"
else
    _record_pass "download_one: validation fail -> dest NOT promoted"
fi
shopt -s nullglob
leftover=( "$dest_dir"/should-not-exist.bin.tmp.* )
shopt -u nullglob
assert_eq "0" "${#leftover[@]}" "download_one: validation fail -> .tmp cleaned up"
assert_contains "$(cat "$OUT")" "[FAIL]" "download_one: validation fail -> [FAIL] marker"

# ═══════════════════════════════════════════════════════════════════
#  download_one - curl failure: dest absent, [FAIL], exit 1
# ═══════════════════════════════════════════════════════════════════
curl() { return 22; }   # simulate HTTP 4xx via -f

dest4="$dest_dir/curl-fail.bin"
rm -f "$dest4"
c=0
download_one "https://example/fail" "$dest4" "false" "false" > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "download_one: curl failure -> rc=1"
if [[ -e "$dest4" ]]; then
    _record_fail "download_one: curl failure -> dest absent" "(present)" "absent"
else
    _record_pass "download_one: curl failure -> dest absent"
fi
assert_contains "$(cat "$OUT")" "Download failed" "download_one: curl failure -> 'Download failed'"
assert_contains "$(cat "$OUT")" "[FAIL]" "download_one: curl failure -> [FAIL] marker"

# Belt-and-braces: clear the curl mock so nothing leaks into later assertions.
unset -f curl

# ═══════════════════════════════════════════════════════════════════
#  Script-level: --dry-run does NOT create BIN_DIR; non-dry-run does
# ═══════════════════════════════════════════════════════════════════
if command -v jq &>/dev/null && command -v curl &>/dev/null && command -v file &>/dev/null; then
    # Empty-but-valid manifest: header row only, so the loop iterates
    # zero data entries and never reaches fetch_release/curl.
    EMPTY_MANIFEST="$SANDBOX/empty.tsv"
    printf 'name\ttype\trepo\ttag\tmode\tdest\tflags\n' > "$EMPTY_MANIFEST"

    # Patch a copy of the script to point at our empty manifest
    # and our sandbox lib path.
    mkdir -p "$SANDBOX/lib"
    ln -sf "$_REAL_REPO/scripts/lib/ui.sh" "$SANDBOX/lib/ui.sh"
    sed "s|^MANIFEST=.*|MANIFEST=\"$EMPTY_MANIFEST\"|" "$SCRIPT" \
        > "$SANDBOX/sync-empty.sh"

    # Dry-run: BIN_DIR must NOT be created
    DRY_BIN_ROOT="$SANDBOX/dryrun-lab"
    rm -rf "$DRY_BIN_ROOT"
    LAB_ROOT="$DRY_BIN_ROOT" bash "$SANDBOX/sync-empty.sh" --dry-run > "$OUT" 2>&1 || true
    if [[ -d "$DRY_BIN_ROOT/tools/binaries" ]]; then
        _record_fail "script --dry-run: BIN_DIR NOT created" "(present)" "absent"
    else
        _record_pass "script --dry-run: BIN_DIR NOT created"
    fi
    assert_contains "$(cat "$OUT")" "DRY-RUN" "script --dry-run: announces DRY-RUN mode"

    # Non-dry-run: BIN_DIR IS created
    REAL_BIN_ROOT="$SANDBOX/real-lab"
    rm -rf "$REAL_BIN_ROOT"
    LAB_ROOT="$REAL_BIN_ROOT" bash "$SANDBOX/sync-empty.sh" > "$OUT" 2>&1 || true
    assert_dir_exists "$REAL_BIN_ROOT/tools/binaries" \
        "script (no dry-run): BIN_DIR created when needed"

    # ───────────────────────────────────────────────────────────────
    # --name filter: only the matching entry is processed.  We patch
    # process_entry into a recorder so we don't need a real network.
    # ───────────────────────────────────────────────────────────────
    TWO_MANIFEST="$SANDBOX/two.tsv"
    cat > "$TWO_MANIFEST" <<'TSV'
name	type	repo	tag	mode	dest	flags
alpha	github-release	o/alpha	v1	binary	alpha	-
beta	github-release	o/beta	v1	binary	beta	-
TSV

    RECORD="$SANDBOX/processed.log"
    : > "$RECORD"

    # Patch: replace the body of process_entry with a recorder, and
    # point MANIFEST at the two-entry file.
    awk -v rec="$RECORD" '
        /^process_entry\(\) \{/ {
            print "process_entry() { echo \"$1\" >> \"" rec "\"; }"
            in_pe = 1; brace = 0; next
        }
        in_pe {
            for (i=1;i<=length($0);i++) {
                c = substr($0,i,1)
                if (c == "{") brace++
                else if (c == "}") { brace--; if (brace == 0) { in_pe = 0; next } }
            }
            next
        }
        { print }
    ' "$SCRIPT" \
        | sed "s|^MANIFEST=.*|MANIFEST=\"$TWO_MANIFEST\"|" \
        > "$SANDBOX/sync-recorder.sh"

    LAB_ROOT="$SANDBOX/filter-lab" \
        bash "$SANDBOX/sync-recorder.sh" --dry-run --name beta > "$OUT" 2>&1 || true

    processed_count="$(wc -l < "$RECORD" | tr -d ' ')"
    assert_eq "1" "$processed_count" "filter --name beta: exactly 1 entry processed"
    assert_eq "beta" "$(head -1 "$RECORD")" "filter --name beta: the 'beta' entry was the one processed"

    # And without --name: both entries processed.
    : > "$RECORD"
    LAB_ROOT="$SANDBOX/filter-lab" \
        bash "$SANDBOX/sync-recorder.sh" --dry-run > "$OUT" 2>&1 || true
    processed_count="$(wc -l < "$RECORD" | tr -d ' ')"
    assert_eq "2" "$processed_count" "no filter: both manifest entries processed"
else
    echo "# SKIP: jq/curl/file unavailable - skipping script-level tests"
fi

end_tests
